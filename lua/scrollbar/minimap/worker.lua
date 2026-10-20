--- Minimap worker: runs `minimap/squash.lua`, optionally with treesitter
--- captures, on buffers mirrored into a headless child Neovim, and returns the
--- cell rows of the requested grid slice to the parent. `scrollbar.mirror`
--- owns the child process and the buffer mirrors. The `"sync"` backend runs
--- the same logic inline on the main thread, and the output of both backends
--- is bit-identical.
---
--- On worker failure the module emits exactly one warning and flips to the
--- sync path for the rest of the session.

local mirror_host = require("scrollbar.mirror")
local squash_module = require("scrollbar.minimap.squash")
local semantic_module = require("scrollbar.minimap.semantic")
local treesitter_provider = require("scrollbar.providers.treesitter")

local M = {}

-- Child code that adds the `semantic_snapshot` and `squash` request kinds. It
-- runs after the mirror prelude. The child runs with `--noplugin` and cannot
-- `require()` plugin modules, so the parent sends the module sources in the
-- extension options.
local CHILD_EXTENSION = [==[
local child, options = ...
local squash = loadstring(options.squash_source)()
local semantic = loadstring(options.semantic_source)()
local treesitter = loadstring(options.treesitter_source)()
local trace_treesitter = options.trace_treesitter == true

local function trace(event, payload)
    if trace_treesitter then
        payload = payload or {}
        payload.event = event
        child.send("trace", payload)
    end
end

child.on_snapshot_start = function(mirror, payload)
    mirror.lang = payload.lang
    mirror.semantic_revision = 0
    mirror.semantic_spans = {}
end

child.on_snapshot_complete = function(mirror, payload)
    if mirror.lang ~= nil then
        trace("treesitter_start", { bufnr = payload.bufnr })
        pcall(vim.treesitter.start, mirror.child_buf, mirror.lang)
    end
end

child.handlers.semantic_snapshot = function(payload)
    local mirror = child.mirror(payload.bufnr)
    if mirror == nil or mirror.id ~= payload.id then
        child.send("mirror_invalid", { bufnr = payload.bufnr, id = payload.id })
        return
    end
    mirror.semantic_revision = payload.revision
    mirror.semantic_spans = payload.spans
end

child.handlers.squash = function(payload)
    local mirror = child.current(payload)
    if mirror == nil then
        return
    end
    if mirror.semantic_revision ~= payload.semantic_revision then
        child.send("mirror_invalid", { bufnr = payload.bufnr, id = payload.mirror.id })
        return
    end

    local grid = payload.grid
    local first, last = squash.line_range(grid, vim.api.nvim_buf_line_count(mirror.child_buf))
    local lines = vim.api.nvim_buf_get_lines(mirror.child_buf, first, last, false)
    local worker_spans = {}
    if mirror.lang ~= nil then
        trace("capture_extract", { bufnr = payload.bufnr })
        local ok, spans = pcall(treesitter.collect, mirror.child_buf, mirror.lang, first, last)
        if ok then
            worker_spans = spans or {}
        end
    end

    local spans_by_provider = vim.deepcopy(mirror.semantic_spans)
    if #worker_spans > 0 then
        spans_by_provider.treesitter = worker_spans
    end
    local highlights = semantic.compose(lines, spans_by_provider, first)
    child.send("result", {
        bufnr = payload.bufnr,
        generation = payload.generation,
        signature = payload.signature,
        mirror = payload.mirror,
        semantic_revision = payload.semantic_revision,
        filetype = payload.filetype,
        grid = grid,
        cells = squash.squash(lines, first, grid, highlights),
        worker_spans = worker_spans,
    })
end
]==]

---@class ScrollbarMinimapWorkerMirror: ScrollbarMirror
---@field semantic_revision integer Semantic revision that the child mirror holds

---@type ScrollbarMinimapBackend
local backend = "sync"
local sync_active = false
local treesitter_enabled = false
local pending = {}
local in_flight
-- Semantic spans of the request in flight. The squash notification leaves
-- them out, and a requeued request needs them again.
---@type ScrollbarMinimapSpanStoreSnapshot?
local in_flight_spans
local on_result
local on_failure
local request_sequence = 0

---@type ScrollbarMirrorHost
local host

---@return string
local function worker_state()
    if sync_active then
        return "sync"
    end
    return host.state()
end

---@param request ScrollbarMinimapWorkerRequest
---@return string
local function pending_key(request)
    return string.format("%d\0%s", request.bufnr, request.signature)
end

---@param bufnr integer
local function clear_pending_buffer(bufnr)
    for key, request in pairs(pending) do
        if request.bufnr == bufnr then
            pending[key] = nil
        end
    end
end

--- Sync backend: run squash on the main thread and invoke `on_result`
--- synchronously. Both backends use the same capture policy and squash path.
local function sync_execute(request)
    local bufnr = request.bufnr
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end
    local grid = request.grid
    local first, last = squash_module.line_range(grid, vim.api.nvim_buf_line_count(bufnr))
    local lines = vim.api.nvim_buf_get_lines(bufnr, first, last, false)
    local spans_by_provider = vim.deepcopy(request.semantic_spans or {})
    local worker_spans = {}
    if treesitter_enabled then
        local lang = treesitter_provider.language_for(request.filetype)
        worker_spans = treesitter_provider.collect(bufnr, lang, first, last)
        if #worker_spans > 0 then
            spans_by_provider.treesitter = worker_spans
        end
    end
    local highlights = semantic_module.compose(lines, spans_by_provider, first)
    local cells = squash_module.squash(lines, first, grid, highlights)
    if on_result ~= nil then
        on_result({
            bufnr = bufnr,
            generation = request.generation,
            signature = request.signature,
            changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
            semantic_revision = request.semantic_revision or 0,
            filetype = request.filetype or "",
            grid = grid,
            cells = cells,
            worker_spans = worker_spans,
        })
    end
end

local function dispatch_pending()
    if host.state() ~= "ready" or in_flight ~= nil then
        return
    end

    local selected
    local selected_mirror
    for _, request in pairs(pending) do
        local mirror = host.ready_mirror(request.bufnr)
        if mirror ~= nil and (selected == nil or request.worker_sequence > selected.worker_sequence) then
            selected = request
            selected_mirror = mirror
        end
    end
    if selected == nil then
        return
    end
    ---@cast selected_mirror ScrollbarMinimapWorkerMirror

    pending[selected.pending_key] = nil
    selected.pending_key = nil
    local semantic_revision = selected.semantic_revision or 0
    local semantic_spans = selected.semantic_spans or {}
    if selected_mirror.semantic_revision ~= semantic_revision then
        if
            not host.notify("semantic_snapshot", {
                bufnr = selected.bufnr,
                id = selected_mirror.id,
                revision = semantic_revision,
                spans = semantic_spans,
            })
        then
            host.failure("semantic snapshot notification failed")
            return
        end
        selected_mirror.semantic_revision = semantic_revision
        host.emit("semantic_snapshot_sent", { bufnr = selected.bufnr, revision = semantic_revision })
    end
    selected.semantic_spans = nil
    selected.mirror = {
        session = host.session(),
        id = selected_mirror.id,
        version = selected_mirror.version,
        changedtick = selected_mirror.changedtick,
    }
    in_flight = selected
    in_flight_spans = semantic_spans
    if not host.notify("squash", selected) then
        host.failure("squash notification failed")
        return
    end
    host.emit("squash_dispatched", {
        bufnr = selected.bufnr,
        generation = selected.generation,
        semantic_spans_sent = selected.semantic_spans ~= nil,
    })
end

---@param event string
---@param payload table
local function handle_event(event, payload)
    if event == "trace" then
        host.emit(payload.event, payload)
        return
    end
    if event ~= "result" or in_flight == nil then
        return
    end

    local request = in_flight
    local same_result = payload.bufnr == request.bufnr
        and payload.generation == request.generation
        and payload.signature == request.signature
        and payload.semantic_revision == (request.semantic_revision or 0)
        and payload.filetype == (request.filetype or "")
        and vim.deep_equal(payload.mirror, request.mirror)
    if not same_result then
        return
    end
    in_flight = nil
    in_flight_spans = nil
    if on_result ~= nil then
        on_result({
            bufnr = payload.bufnr,
            generation = payload.generation,
            signature = payload.signature,
            changedtick = request.mirror.changedtick,
            semantic_revision = payload.semantic_revision,
            filetype = request.filetype or "",
            grid = request.grid,
            cells = payload.cells,
            worker_spans = payload.worker_spans or {},
        })
    end
    dispatch_pending()
end

-- The child rejected work for mirror `id` of `bufnr`. The squash in flight goes
-- back to the queue when it was made for that mirror, unless a newer request
-- with the same key replaced it.
---@param bufnr integer
---@param id? integer
local function requeue_in_flight(bufnr, id)
    local request = in_flight
    if request == nil or request.bufnr ~= bufnr or (id ~= nil and request.mirror.id ~= id) then
        return
    end
    in_flight = nil
    request.semantic_spans = in_flight_spans
    in_flight_spans = nil
    request.pending_key = pending_key(request)
    local queued = pending[request.pending_key]
    if queued == nil or request.worker_sequence > queued.worker_sequence then
        pending[request.pending_key] = request
    end
end

---@param entry table
---@param mirror ScrollbarMinimapWorkerMirror
local function decorate_status(entry, mirror)
    entry.semantic_revision = mirror.semantic_revision
end

host = mirror_host.new({
    name = "minimap",
    augroup = "ScrollbarMinimapWorker",
    child_global = "__scrollbar_minimap_worker_child",
    callback_global = "__scrollbar_minimap_worker_callback",
    extension = CHILD_EXTENSION,
    dispatch_pending = dispatch_pending,
    on_event = handle_event,
    on_mirror_invalid = requeue_in_flight,
    on_detach = clear_pending_buffer,
    on_reset = function()
        pending = {}
        in_flight = nil
        in_flight_spans = nil
    end,
    on_failure = function(reason)
        if on_failure ~= nil then
            on_failure(reason)
        end
    end,
    on_leave = function()
        M.dispose()
    end,
    ---@param mirror ScrollbarMinimapWorkerMirror
    on_snapshot_start = function(mirror)
        mirror.semantic_revision = 0
    end,
    exit_reason = function(code)
        return "worker exit code " .. tostring(code)
    end,
})

---@param filetype? string
---@return string?
local function mirror_lang(filetype)
    return treesitter_enabled and treesitter_provider.language_for(filetype) or nil
end

local function request_worker(request)
    if not host.sync(request.bufnr, mirror_lang(request.filetype)) then
        return false
    end
    request_sequence = request_sequence + 1
    local queued = {}
    for key, value in pairs(request) do
        queued[key] = value
    end
    queued.worker_sequence = request_sequence
    queued.pending_key = pending_key(queued)
    local mirror = host.mirror(request.bufnr)
    if mirror ~= nil and mirror.complete then
        queued.changedtick = mirror.changedtick
    elseif mirror ~= nil and mirror.snapshot_tick ~= nil then
        queued.changedtick = mirror.snapshot_tick
    end
    pending[queued.pending_key] = queued
    dispatch_pending()
    return true
end

--- Read the module sources that the child code loads.
---@param trace_treesitter boolean
---@return table? options
---@return string? reason
local function child_options(trace_treesitter)
    local squash_source = mirror_host.read_runtime_source("lua/scrollbar/minimap/squash.lua")
    if squash_source == nil then
        return nil, "could not read squash.lua source"
    end
    local semantic_source = mirror_host.read_runtime_source("lua/scrollbar/minimap/semantic.lua")
    if semantic_source == nil then
        return nil, "could not read semantic.lua source"
    end
    local treesitter_source = mirror_host.read_runtime_source("lua/scrollbar/providers/treesitter.lua")
    if treesitter_source == nil then
        return nil, "could not read treesitter provider source"
    end
    return {
        squash_source = squash_source,
        semantic_source = semantic_source,
        treesitter_source = treesitter_source,
        trace_treesitter = trace_treesitter,
    }
end

---@class ScrollbarMinimapWorkerRequest
---@field bufnr integer
---@field grid ScrollbarMinimapGrid Rows to squash
---@field filetype? string
---@field generation integer Caller-defined monotonic id; mismatched results are dropped
---@field signature string Caller-defined dedup key; mismatched results are dropped
---@field semantic_revision? integer Parent semantic input revision
---@field semantic_spans? ScrollbarMinimapSpanStoreSnapshot Parent-published spans grouped by provider

---@class ScrollbarMinimapWorkerOptions
---@field backend? ScrollbarMinimapBackend
---@field treesitter? boolean
---@field on_result? fun(payload: table)
---@field on_failure? fun(reason: string)
---@field test? table

M.setup = function(options)
    M.dispose()
    options = options or {}
    backend = options.backend == "worker" and "worker" or "sync"
    treesitter_enabled = options.treesitter == true
    on_result = options.on_result
    on_failure = options.on_failure
    local test_options = options.test or {}
    pending = {}
    in_flight = nil
    in_flight_spans = nil

    if backend == "sync" then
        sync_active = true
        return true
    end

    local extension_options, fail_reason
    if test_options.fail_start then
        fail_reason = "injected startup failure"
    else
        extension_options, fail_reason = child_options(test_options.trace_treesitter == true)
    end
    return host.start({
        chunk_size = test_options.chunk_size,
        timing = test_options.on_timing,
        fail_reason = fail_reason,
        extension_options = extension_options,
    })
end

local function resolve_bufnr(bufnr)
    if bufnr == 0 then
        return vim.api.nvim_get_current_buf()
    end
    return bufnr
end

M.sync_buffer = function(bufnr, filetype)
    local state = worker_state()
    if state == "sync" or state == "disposed" or state == "failed" then
        return true
    end
    return host.sync(resolve_bufnr(bufnr), mirror_lang(filetype))
end

M.detach_buffer = function(bufnr)
    local state = worker_state()
    if state == "sync" or state == "disposed" or state == "failed" then
        return
    end
    host.detach(resolve_bufnr(bufnr), true)
end

M.request = function(request)
    local state = worker_state()
    if state == "disposed" then
        return false
    end
    request.bufnr = resolve_bufnr(request.bufnr)
    request.filetype = request.filetype or ""
    request.semantic_revision = request.semantic_revision or 0
    request.semantic_spans = request.semantic_spans or {}
    if state == "sync" or state == "failed" then
        sync_execute(request)
        return true
    end
    if state == "starting" or state == "ready" then
        return request_worker(request)
    end
    return false
end

M.dispose = function()
    host.dispose()
    sync_active = false
    on_result = nil
    on_failure = nil
    treesitter_enabled = false
end

M.status = function()
    return {
        backend = backend,
        state = worker_state(),
        session = host.session(),
        job_id = host.job_id(),
        mirrors = host.status_mirrors(decorate_status),
        in_flight = in_flight and {
            bufnr = in_flight.bufnr,
            generation = in_flight.generation,
            signature = in_flight.signature,
        } or nil,
        pending_count = vim.tbl_count(pending),
        argv = host.argv(),
    }
end

-- selene: allow(global_usage)
_G.__scrollbar_minimap_worker_callback = function(callback_session, event, payload)
    host.dispatch(callback_session, event, payload)
end

return M
