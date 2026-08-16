--- Minimap worker: mirrors source buffers into a headless child Neovim and
--- runs `minimap/squash.lua`, optionally with treesitter captures, returning
--- the cell grid to the parent. The `"sync"` backend runs the same logic
--- inline on the main thread; output is bit-identical between backends.
---
--- Parallels `lua/scrollbar/providers/search_worker.lua`. On worker failure
--- the module emits exactly one warning and flips to the sync path for the
--- rest of the session.

local squash_module = require("scrollbar.minimap.squash")
local semantic_module = require("scrollbar.minimap.semantic")
local treesitter_provider = require("scrollbar.providers.treesitter")

local M = {}

local DEFAULT_CHUNK_SIZE = 512
local STARTUP_TIMEOUT_MS = 5000

--- Read a runtime file's source so we can inject it into the child. The
--- child runs with `--noplugin` so it cannot `require()` plugin modules
--- directly; we send the squash source over RPC at bootstrap time.
local function read_runtime_source(rel_path)
    local path = vim.api.nvim_get_runtime_file(rel_path, false)[1]
    if not path then
        return nil
    end
    local file = io.open(path, "r")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

local CHILD_DISPATCH = [=[
local session, kind, payload = ...
local worker = rawget(_G, "__scrollbar_minimap_worker_child")
if worker ~= nil and worker.session == session then
    local ok, err = pcall(worker.handle, kind, payload)
    if not ok then
        worker.fail(tostring(err))
    end
end
]=]

local CHILD_BOOTSTRAP = [==[
local session, options = ...
local squash = loadstring(options.squash_source)()
local semantic = loadstring(options.semantic_source)()
local treesitter = loadstring(options.treesitter_source)()
local mirrors = {}
local trace_treesitter = options.trace_treesitter == true

local callback_source = [=[
local session, event, payload = ...
local callback = rawget(_G, "__scrollbar_minimap_worker_callback")
if callback ~= nil then
    callback(session, event, payload)
end
]=]

local function send(event, payload)
    vim.rpcnotify(1, "nvim_exec_lua", callback_source, { session, event, payload })
end

local function trace(event, payload)
    if trace_treesitter then
        payload = payload or {}
        payload.event = event
        send("trace", payload)
    end
end

local function ensure_buffer(mirror)
    if mirror.child_buf == nil or not vim.api.nvim_buf_is_valid(mirror.child_buf) then
        mirror.child_buf = vim.api.nvim_create_buf(false, true)
    end
    return mirror.child_buf
end

local function squash_payload(payload)
    local mirror = mirrors[payload.bufnr]
    if mirror == nil
        or not mirror.complete
        or mirror.id ~= payload.mirror.id
        or mirror.version ~= payload.mirror.version
        or mirror.changedtick ~= payload.mirror.changedtick
        or mirror.semantic_revision ~= payload.semantic_revision
    then
        send("mirror_invalid", { bufnr = payload.bufnr })
        return
    end

    local lines = vim.api.nvim_buf_get_lines(mirror.child_buf, 0, -1, true)
    local worker_spans = {}
    if mirror.lang ~= nil then
        trace("capture_extract", { bufnr = payload.bufnr })
        local ok, spans = pcall(treesitter.collect, mirror.child_buf, mirror.lang)
        if ok then
            worker_spans = spans or {}
        end
    end

    local spans_by_provider = vim.deepcopy(mirror.semantic_spans)
    if #worker_spans > 0 then
        spans_by_provider.treesitter = worker_spans
    end
    local highlights = semantic.compose(lines, spans_by_provider)
    local cells, max_line_width = squash.squash(lines, payload.width, payload.height, highlights)
    send("result", {
        bufnr = payload.bufnr,
        generation = payload.generation,
        signature = payload.signature,
        mirror = payload.mirror,
        semantic_revision = payload.semantic_revision,
        filetype = payload.filetype,
        cells = cells,
        max_line_width = max_line_width,
        worker_spans = worker_spans,
    })
end

local worker = { session = session }
worker.fail = function(reason)
    send("failure", { reason = reason })
end
worker.handle = function(kind, payload)
    if kind == "snapshot_start" then
        local previous = mirrors[payload.bufnr]
        mirrors[payload.bufnr] = {
            child_buf = previous and previous.child_buf or nil,
            id = payload.id,
            version = payload.version,
            changedtick = nil,
            complete = false,
            lines = {},
            lang = payload.lang,
            semantic_revision = 0,
            semantic_spans = {},
        }
    elseif kind == "snapshot_chunk" then
        local mirror = mirrors[payload.bufnr]
        if mirror ~= nil and mirror.id == payload.id and #mirror.lines == payload.start then
            for _, line in ipairs(payload.lines) do
                mirror.lines[#mirror.lines + 1] = line
            end
        end
    elseif kind == "snapshot_complete" then
        local mirror = mirrors[payload.bufnr]
        if mirror == nil or mirror.id ~= payload.id or #mirror.lines ~= payload.line_count then
            send("mirror_invalid", { bufnr = payload.bufnr })
            return
        end
        local child_buf = ensure_buffer(mirror)
        vim.api.nvim_buf_set_lines(child_buf, 0, -1, false, mirror.lines)
        mirror.lines = nil
        mirror.version = payload.version
        mirror.changedtick = payload.changedtick
        mirror.complete = true
        if mirror.lang ~= nil then
            trace("treesitter_start", { bufnr = payload.bufnr })
            pcall(vim.treesitter.start, child_buf, mirror.lang)
        end
    elseif kind == "delta" then
        local mirror = mirrors[payload.bufnr]
        if mirror == nil
            or not mirror.complete
            or mirror.id ~= payload.id
            or mirror.version ~= payload.from_version
        then
            send("mirror_invalid", { bufnr = payload.bufnr })
            return
        end
        vim.api.nvim_buf_set_lines(mirror.child_buf, payload.first, payload.last, false, payload.lines)
        mirror.version = payload.version
        mirror.changedtick = payload.changedtick
    elseif kind == "semantic_snapshot" then
        local mirror = mirrors[payload.bufnr]
        if mirror == nil or mirror.id ~= payload.id then
            send("mirror_invalid", { bufnr = payload.bufnr })
            return
        end
        mirror.semantic_revision = payload.revision
        mirror.semantic_spans = payload.spans
    elseif kind == "detach" then
        local mirror = mirrors[payload.bufnr]
        if mirror ~= nil and mirror.child_buf ~= nil and vim.api.nvim_buf_is_valid(mirror.child_buf) then
            pcall(vim.api.nvim_buf_delete, mirror.child_buf, { force = true })
        end
        mirrors[payload.bufnr] = nil
    elseif kind == "squash" then
        squash_payload(payload)
    elseif kind == "dispose" then
        for _, mirror in pairs(mirrors) do
            if mirror.child_buf ~= nil and vim.api.nvim_buf_is_valid(mirror.child_buf) then
                pcall(vim.api.nvim_buf_delete, mirror.child_buf, { force = true })
            end
        end
        mirrors = {}
    end
end

_G.__scrollbar_minimap_worker_child = worker
send("ready", {})
]==]

---@class ScrollbarMinimapWorkerMirror
---@field bufnr integer
---@field id integer
---@field version integer
---@field changedtick? integer
---@field complete boolean
---@field attached boolean
---@field lang? string
---@field snapshot_tick? integer
---@field snapshot_next? integer
---@field snapshot_line_count? integer
---@field semantic_revision integer

local backend = "sync"
local treesitter_enabled = false
local worker_state = "disposed"
local job_id
local session
local mirrors = {}
local pending = {}
local in_flight
local on_result
local on_failure
local timing_hook
local shutdown_group
local session_sequence = 0
local mirror_sequence = 0
local request_sequence = 0
local expected_exit = false
local warned = false
local chunk_size = DEFAULT_CHUNK_SIZE
local argv

local dispatch_pending
local start_snapshot

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

local function emit_timing(event, payload)
    if timing_hook ~= nil then
        pcall(timing_hook, event, payload or {})
    end
end

local function notify_child(kind, payload)
    if job_id == nil or worker_state == "failed" or worker_state == "disposed" then
        return false
    end
    local ok = pcall(vim.rpcnotify, job_id, "nvim_exec_lua", CHILD_DISPATCH, { session, kind, payload })
    return ok
end

local function warn_once(reason)
    if warned then
        return
    end
    warned = true
    vim.notify("[scrollbar.nvim] minimap worker failed; using synchronous fallback: " .. reason, vim.log.levels.WARN)
end

--- Sync backend: run squash on the main thread and invoke `on_result`
--- synchronously. Both backends use the same capture policy and squash path.
local function sync_execute(request)
    local bufnr = request.bufnr
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local spans_by_provider = vim.deepcopy(request.semantic_spans or {})
    local worker_spans = {}
    if treesitter_enabled then
        local lang = treesitter_provider.language_for(request.filetype)
        worker_spans = treesitter_provider.collect(bufnr, lang)
        if #worker_spans > 0 then
            spans_by_provider.treesitter = worker_spans
        end
    end
    local highlights = semantic_module.compose(lines, spans_by_provider)
    local cells, max_line_width = squash_module.squash(lines, request.width, request.height, highlights)
    if on_result ~= nil then
        on_result({
            bufnr = bufnr,
            generation = request.generation,
            signature = request.signature,
            changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
            semantic_revision = request.semantic_revision or 0,
            filetype = request.filetype or "",
            cells = cells,
            max_line_width = max_line_width,
            worker_spans = worker_spans,
        })
    end
end

local function detach_mirror(bufnr, notify)
    local mirror = mirrors[bufnr]
    if mirror == nil then
        return
    end
    mirrors[bufnr] = nil
    clear_pending_buffer(bufnr)
    if mirror.attached and vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_detach, bufnr)
    end
    if notify then
        notify_child("detach", { bufnr = bufnr })
    end
end

local function detach_all(notify)
    local buffers = vim.tbl_keys(mirrors)
    for _, bufnr in ipairs(buffers) do
        detach_mirror(bufnr, notify)
    end
end

local function failure(reason)
    if worker_state == "failed" or worker_state == "disposed" then
        return
    end
    worker_state = "failed"
    expected_exit = true
    local failed_job = job_id
    job_id = nil
    detach_all(false)
    in_flight = nil
    pending = {}
    if failed_job ~= nil then
        pcall(vim.fn.jobstop, failed_job)
    end
    warn_once(reason)
    if on_failure ~= nil then
        on_failure(reason)
    end
end

dispatch_pending = function()
    if worker_state ~= "ready" or in_flight ~= nil then
        return
    end

    local selected
    for _, request in pairs(pending) do
        local mirror = mirrors[request.bufnr]
        if
            mirror ~= nil
            and mirror.complete
            and (selected == nil or request.worker_sequence > selected.worker_sequence)
        then
            selected = request
        end
    end
    if selected == nil then
        return
    end

    pending[selected.pending_key] = nil
    selected.pending_key = nil
    local mirror = mirrors[selected.bufnr]
    local semantic_revision = selected.semantic_revision or 0
    local semantic_spans = selected.semantic_spans or {}
    if mirror.semantic_revision ~= semantic_revision then
        if
            not notify_child("semantic_snapshot", {
                bufnr = selected.bufnr,
                id = mirror.id,
                revision = semantic_revision,
                spans = semantic_spans,
            })
        then
            failure("semantic snapshot notification failed")
            return
        end
        mirror.semantic_revision = semantic_revision
        emit_timing("semantic_snapshot_sent", { bufnr = selected.bufnr, revision = semantic_revision })
    end
    selected.semantic_spans = nil
    selected.mirror = {
        session = session,
        id = mirror.id,
        version = mirror.version,
        changedtick = mirror.changedtick,
    }
    in_flight = selected
    if not notify_child("squash", selected) then
        failure("squash notification failed")
        return
    end
    emit_timing("squash_dispatched", {
        bufnr = selected.bufnr,
        generation = selected.generation,
        semantic_spans_sent = selected.semantic_spans ~= nil,
    })
end

start_snapshot = function(mirror)
    if worker_state == "failed" or worker_state == "disposed" then
        return
    end
    if not vim.api.nvim_buf_is_valid(mirror.bufnr) or not vim.api.nvim_buf_is_loaded(mirror.bufnr) then
        detach_mirror(mirror.bufnr, true)
        return
    end

    mirror_sequence = mirror_sequence + 1
    mirror.id = mirror_sequence
    mirror.version = 1
    mirror.complete = false
    mirror.semantic_revision = 0
    mirror.snapshot_tick = vim.api.nvim_buf_get_changedtick(mirror.bufnr)
    mirror.snapshot_next = 0
    mirror.snapshot_line_count = vim.api.nvim_buf_line_count(mirror.bufnr)
    emit_timing("snapshot_started", { bufnr = mirror.bufnr, id = mirror.id })
    notify_child("snapshot_start", {
        bufnr = mirror.bufnr,
        id = mirror.id,
        version = mirror.version,
        lang = mirror.lang,
    })

    local snapshot_id = mirror.id
    local function read_chunk()
        if mirrors[mirror.bufnr] ~= mirror or mirror.id ~= snapshot_id or mirror.complete then
            return
        end
        if not vim.api.nvim_buf_is_valid(mirror.bufnr) or not vim.api.nvim_buf_is_loaded(mirror.bufnr) then
            detach_mirror(mirror.bufnr, true)
            return
        end
        if vim.api.nvim_buf_get_changedtick(mirror.bufnr) ~= mirror.snapshot_tick then
            start_snapshot(mirror)
            return
        end

        local first = mirror.snapshot_next
        local last = math.min(first + chunk_size, mirror.snapshot_line_count)
        local chunk_started = vim.uv.hrtime()
        local lines = vim.api.nvim_buf_get_lines(mirror.bufnr, first, last, true)
        if vim.api.nvim_buf_get_changedtick(mirror.bufnr) ~= mirror.snapshot_tick then
            start_snapshot(mirror)
            return
        end
        if
            not notify_child("snapshot_chunk", {
                bufnr = mirror.bufnr,
                id = mirror.id,
                start = first,
                lines = lines,
            })
        then
            failure("buffer snapshot notification failed")
            return
        end
        mirror.snapshot_next = last
        emit_timing("snapshot_chunk", {
            bufnr = mirror.bufnr,
            id = mirror.id,
            duration_ms = (vim.uv.hrtime() - chunk_started) / 1000000,
        })

        if last < mirror.snapshot_line_count then
            vim.schedule(read_chunk)
            return
        end
        if vim.api.nvim_buf_get_changedtick(mirror.bufnr) ~= mirror.snapshot_tick then
            start_snapshot(mirror)
            return
        end

        mirror.changedtick = mirror.snapshot_tick
        mirror.complete = true
        if
            not notify_child("snapshot_complete", {
                bufnr = mirror.bufnr,
                id = mirror.id,
                version = mirror.version,
                changedtick = mirror.changedtick,
                line_count = mirror.snapshot_line_count,
            })
        then
            failure("buffer snapshot completion failed")
            return
        end
        emit_timing("snapshot_parent_complete", { bufnr = mirror.bufnr, id = mirror.id })
        dispatch_pending()
    end
    vim.schedule(read_chunk)
end

local function sync_buffer_worker(bufnr, filetype)
    if worker_state == "failed" or worker_state == "disposed" then
        return false
    end
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return false
    end

    local desired_lang = treesitter_enabled and treesitter_provider.language_for(filetype) or nil
    local mirror = mirrors[bufnr]
    if mirror ~= nil and mirror.lang == desired_lang then
        return true
    end
    if mirror ~= nil then
        detach_mirror(bufnr, true)
    end
    mirror = {
        bufnr = bufnr,
        id = 0,
        version = 0,
        complete = false,
        attached = false,
        lang = desired_lang,
        semantic_revision = 0,
    }
    mirrors[bufnr] = mirror
    mirror.attached = vim.api.nvim_buf_attach(bufnr, false, {
        on_lines = function(_, buffer, changedtick, first, last, new_last)
            local current = mirrors[buffer]
            if current ~= mirror then
                return true
            end
            if not current.complete then
                start_snapshot(current)
                return false
            end

            local lines = vim.api.nvim_buf_get_lines(buffer, first, new_last, true)
            local from_version = current.version
            current.version = current.version + 1
            current.changedtick = changedtick
            if
                not notify_child("delta", {
                    bufnr = buffer,
                    id = current.id,
                    from_version = from_version,
                    version = current.version,
                    changedtick = changedtick,
                    first = first,
                    last = last,
                    lines = lines,
                })
            then
                vim.schedule(function()
                    failure("buffer delta notification failed")
                end)
                return true
            end
            emit_timing("delta_sent", {
                bufnr = buffer,
                version = current.version,
            })
            dispatch_pending()
            return false
        end,
        on_detach = function(_, buffer)
            if mirrors[buffer] == mirror then
                mirrors[buffer] = nil
                clear_pending_buffer(buffer)
                notify_child("detach", { bufnr = buffer })
            end
        end,
    })
    if not mirror.attached then
        mirrors[bufnr] = nil
        return false
    end
    start_snapshot(mirror)
    return true
end

local function request_worker(request)
    if not sync_buffer_worker(request.bufnr, request.filetype) then
        return false
    end
    request_sequence = request_sequence + 1
    local queued = {}
    for key, value in pairs(request) do
        queued[key] = value
    end
    queued.worker_sequence = request_sequence
    queued.pending_key = pending_key(queued)
    local mirror = mirrors[request.bufnr]
    if mirror ~= nil and mirror.complete then
        queued.changedtick = mirror.changedtick
    elseif mirror ~= nil and mirror.snapshot_tick ~= nil then
        queued.changedtick = mirror.snapshot_tick
    end
    pending[queued.pending_key] = queued
    dispatch_pending()
    return true
end

local function dispatch_callback(event, payload)
    if event == "ready" then
        if worker_state == "starting" then
            worker_state = "ready"
            emit_timing("worker_ready")
            dispatch_pending()
        end
        return
    end
    if event == "mirror_invalid" then
        if in_flight ~= nil and in_flight.bufnr == payload.bufnr then
            local request = in_flight
            in_flight = nil
            request.pending_key = pending_key(request)
            local queued = pending[request.pending_key]
            if queued == nil or request.worker_sequence > queued.worker_sequence then
                pending[request.pending_key] = request
            end
        end
        local mirror = mirrors[payload.bufnr]
        if mirror ~= nil then
            start_snapshot(mirror)
        end
        return
    end
    if event == "trace" then
        emit_timing(payload.event, payload)
        return
    end
    if event == "failure" then
        failure(payload.reason or "child protocol failure")
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
    if on_result ~= nil then
        on_result({
            bufnr = payload.bufnr,
            generation = payload.generation,
            signature = payload.signature,
            changedtick = request.mirror.changedtick,
            semantic_revision = payload.semantic_revision,
            filetype = request.filetype or "",
            cells = payload.cells,
            max_line_width = payload.max_line_width,
            worker_spans = payload.worker_spans or {},
        })
    end
    dispatch_pending()
end

---@class ScrollbarMinimapWorkerRequest
---@field bufnr integer
---@field width integer
---@field height integer
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
    timing_hook = test_options.on_timing
    chunk_size = test_options.chunk_size or DEFAULT_CHUNK_SIZE
    warned = false
    expected_exit = false
    mirrors = {}
    pending = {}
    in_flight = nil
    session_sequence = session_sequence + 1
    session = string.format("%d:%s", session_sequence, tostring(vim.uv.hrtime()))

    if backend == "sync" then
        worker_state = "sync"
        return true
    end

    worker_state = "starting"
    emit_timing("startup_started")
    shutdown_group = vim.api.nvim_create_augroup("ScrollbarMinimapWorker", { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = shutdown_group,
        callback = function()
            M.dispose()
        end,
    })

    if test_options.fail_start then
        failure("injected startup failure")
        return false
    end

    local squash_source = read_runtime_source("lua/scrollbar/minimap/squash.lua")
    if squash_source == nil then
        failure("could not read squash.lua source")
        return false
    end
    local semantic_source = read_runtime_source("lua/scrollbar/minimap/semantic.lua")
    if semantic_source == nil then
        failure("could not read semantic.lua source")
        return false
    end
    local treesitter_source = read_runtime_source("lua/scrollbar/providers/treesitter.lua")
    if treesitter_source == nil then
        failure("could not read treesitter provider source")
        return false
    end

    local token = session
    argv = {
        vim.v.progpath,
        "--embed",
        "--headless",
        "-u",
        "NONE",
        "-i",
        "NONE",
        "--noplugin",
    }
    job_id = vim.fn.jobstart(argv, {
        rpc = true,
        on_exit = function(_, code)
            vim.schedule(function()
                if token ~= session or expected_exit or worker_state == "disposed" or worker_state == "failed" then
                    return
                end
                failure("worker exit code " .. tostring(code))
            end)
        end,
    })
    if job_id == nil or job_id <= 0 then
        local code = job_id
        job_id = nil
        failure("jobstart returned " .. tostring(code))
        return false
    end

    local ok = pcall(vim.rpcnotify, job_id, "nvim_exec_lua", CHILD_BOOTSTRAP, {
        session,
        {
            squash_source = squash_source,
            semantic_source = semantic_source,
            treesitter_source = treesitter_source,
            trace_treesitter = test_options.trace_treesitter == true,
        },
    })
    if not ok then
        failure("bootstrap notification failed")
        return false
    end
    vim.defer_fn(function()
        if token == session and worker_state == "starting" then
            failure("startup timed out")
        end
    end, STARTUP_TIMEOUT_MS)
    return true
end

local function resolve_bufnr(bufnr)
    if bufnr == 0 then
        return vim.api.nvim_get_current_buf()
    end
    return bufnr
end

M.sync_buffer = function(bufnr, filetype)
    if worker_state == "sync" or worker_state == "disposed" or worker_state == "failed" then
        return true
    end
    return sync_buffer_worker(resolve_bufnr(bufnr), filetype)
end

M.detach_buffer = function(bufnr)
    if worker_state == "sync" or worker_state == "disposed" or worker_state == "failed" then
        return
    end
    detach_mirror(resolve_bufnr(bufnr), true)
end

M.request = function(request)
    if worker_state == "disposed" then
        return false
    end
    request.bufnr = resolve_bufnr(request.bufnr)
    request.filetype = request.filetype or ""
    request.semantic_revision = request.semantic_revision or 0
    request.semantic_spans = request.semantic_spans or {}
    if worker_state == "sync" or worker_state == "failed" then
        sync_execute(request)
        return true
    end
    if worker_state == "starting" or worker_state == "ready" then
        return request_worker(request)
    end
    return false
end

M.dispose = function()
    if shutdown_group ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, shutdown_group)
        shutdown_group = nil
    end
    expected_exit = true
    if job_id ~= nil then
        notify_child("dispose", {})
    end
    detach_all(false)
    local disposed_job = job_id
    job_id = nil
    if disposed_job ~= nil then
        pcall(vim.fn.jobstop, disposed_job)
    end
    pending = {}
    in_flight = nil
    on_result = nil
    on_failure = nil
    timing_hook = nil
    treesitter_enabled = false
    worker_state = "disposed"
end

M.status = function()
    local mirror_status = {}
    for bufnr, mirror in pairs(mirrors) do
        mirror_status[#mirror_status + 1] = {
            bufnr = bufnr,
            id = mirror.id,
            version = mirror.version,
            changedtick = mirror.changedtick,
            complete = mirror.complete,
            semantic_revision = mirror.semantic_revision,
        }
    end
    table.sort(mirror_status, function(left, right)
        return left.bufnr < right.bufnr
    end)
    return {
        backend = backend,
        state = worker_state,
        session = session,
        job_id = job_id,
        mirrors = mirror_status,
        in_flight = in_flight and {
            bufnr = in_flight.bufnr,
            generation = in_flight.generation,
            signature = in_flight.signature,
        } or nil,
        pending_count = vim.tbl_count(pending),
        argv = argv and vim.deepcopy(argv) or nil,
    }
end

-- selene: allow(global_usage)
_G.__scrollbar_minimap_worker_callback = function(callback_session, event, payload)
    if callback_session ~= session then
        return
    end
    dispatch_callback(event, payload)
end

return M
