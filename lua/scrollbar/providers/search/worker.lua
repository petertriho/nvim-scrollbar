--- Search worker: scans mirrored buffers for the search pattern in a headless
--- child Neovim. `scrollbar.shared.mirror` owns the child process and the
--- buffer mirrors. This module keeps one pending scan for each buffer and one
--- scan in flight. On worker failure the module emits exactly one warning, and
--- the search provider uses the synchronous scan for the rest of the session.

local mirror_host = require("scrollbar.shared.mirror")
local text_tick = require("scrollbar.shared.text_tick")

local M = {}

-- Child code that adds the `scan` request kind. It runs after the mirror
-- prelude, with the child mirror table and the extension options.
local CHILD_EXTENSION = [[
local child, options = ...

local function encode_lines(lines)
    local encoded = {}
    for index, line in ipairs(lines) do
        encoded[index] = string.char(
            math.floor(line / 0x1000000) % 0x100,
            math.floor(line / 0x10000) % 0x100,
            math.floor(line / 0x100) % 0x100,
            line % 0x100
        )
    end
    return { data = table.concat(encoded), count = #lines, partial = false }
end

child.handlers.scan = function(payload)
    local mirror = child.current(payload)
    if mirror == nil then
        return
    end

    local scan_started = options.timing and vim.uv.hrtime() or nil
    if options.scan_delay_ms ~= nil and options.scan_delay_ms > 0 then
        vim.uv.sleep(options.scan_delay_ms)
    end

    local ok, compact = pcall(function()
        vim.o.ignorecase = payload.ignorecase
        vim.o.smartcase = payload.smartcase
        vim.o.magic = payload.magic
        vim.bo[mirror.child_buf].iskeyword = payload.iskeyword
        vim.api.nvim_win_set_buf(0, mirror.child_buf)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local matches = {}
        local seen = {}
        local function collect()
            local position = { vim.fn.line("."), vim.fn.col(".") }
            local key = string.format("%d:%d", position[1], position[2])
            if not seen[key] then
                seen[key] = true
                matches[#matches + 1] = position
            end
            return true
        end

        vim.fn.searchpos(payload.pattern, "Wnc", 0, 0, collect)
        vim.fn.searchpos(payload.pattern, "bWnc", 0, 0, collect)
        table.sort(matches, function(left, right)
            return left[1] < right[1] or (left[1] == right[1] and left[2] < right[2])
        end)

        local result = {}
        for index, position in ipairs(matches) do
            result[index] = position[1] - 1
        end
        return encode_lines(result)
    end)

    child.send("result", {
        bufnr = payload.bufnr,
        generation = payload.generation,
        signature = payload.signature,
        mirror = payload.mirror,
        compact = ok and compact or vim.NIL,
        scan_duration_ms = scan_started and (vim.uv.hrtime() - scan_started) / 1000000 or nil,
    })
end
]]

---@type table<integer, table>
local pending = {}

---@type table?
local in_flight

---@type fun(result: table)?
local on_result

---@type fun(reason: string)?
local on_failure

local request_sequence = 0
local max_in_flight = 0

---@type ScrollbarMirrorHost
local host

local function dispatch_pending()
    if host.state() ~= "ready" or in_flight ~= nil then
        return
    end

    -- A complete mirror has the current text, so a request whose text tick
    -- is the current one scans the text that it was made for.
    local selected
    local selected_mirror
    for bufnr, request in pairs(pending) do
        local mirror = host.ready_mirror(bufnr)
        if
            mirror ~= nil
            and text_tick.get(bufnr) == request.changedtick
            and (selected == nil or request.worker_sequence > selected.worker_sequence)
        then
            selected = request
            selected_mirror = mirror
        end
    end
    if selected == nil then
        return
    end

    pending[selected.bufnr] = nil
    selected.mirror = {
        session = host.session(),
        id = selected_mirror.id,
        version = selected_mirror.version,
        changedtick = selected.changedtick,
    }
    in_flight = selected
    max_in_flight = math.max(max_in_flight, 1)
    if not host.notify("scan", selected) then
        host.failure("scan notification failed")
        return
    end
    host.emit("scan_dispatched", {
        bufnr = selected.bufnr,
        generation = selected.generation,
    })
end

---@param event string
---@param payload table
local function handle_event(event, payload)
    if event ~= "result" or in_flight == nil then
        return
    end

    host.emit("result_callback_started", payload)
    local request = in_flight
    in_flight = nil
    local same_result = payload.bufnr == request.bufnr
        and payload.generation == request.generation
        and payload.signature == request.signature
        and vim.deep_equal(payload.mirror, request.mirror)
    if same_result and on_result ~= nil then
        if payload.compact == vim.NIL then
            payload.compact = nil
        end
        on_result(payload)
    end
    dispatch_pending()
    host.emit("result_callback_complete", payload)
end

-- The child rejected work for mirror `id` of `bufnr`. The scan in flight goes
-- back to the queue when it was made for that mirror, unless a newer request
-- for the buffer replaced it.
---@param bufnr integer
---@param id? integer
local function requeue_in_flight(bufnr, id)
    local request = in_flight
    if request == nil or request.bufnr ~= bufnr or (id ~= nil and request.mirror.id ~= id) then
        return
    end
    in_flight = nil
    local queued = pending[bufnr]
    if queued == nil or request.worker_sequence > queued.worker_sequence then
        pending[bufnr] = request
    end
end

host = mirror_host.new({
    name = "search",
    augroup = "ScrollbarSearchWorker",
    child_global = "__scrollbar_search_worker_child",
    callback_global = "__scrollbar_search_worker_callback",
    extension = CHILD_EXTENSION,
    dispatch_pending = dispatch_pending,
    on_event = handle_event,
    on_mirror_invalid = requeue_in_flight,
    on_detach = function(bufnr)
        pending[bufnr] = nil
    end,
    on_reset = function()
        pending = {}
        in_flight = nil
    end,
    on_failure = function(reason)
        if on_failure ~= nil then
            on_failure(reason)
        end
    end,
    on_leave = function()
        M.dispose()
    end,
    exit_reason = function(code, stderr)
        return #stderr > 0 and table.concat(stderr, "\n") or "exit code " .. tostring(code)
    end,
})

---@type fun(reason: string)
M.failure = host.failure

---@param bufnr integer
---@return boolean
M.sync_buffer = function(bufnr)
    return host.sync(bufnr, nil)
end

---@param bufnr integer
M.detach_buffer = function(bufnr)
    host.detach(bufnr, true)
end

---@param request table
---@return boolean
M.request = function(request)
    local state = host.state()
    if state == "failed" or state == "disposed" then
        return false
    end
    if not M.sync_buffer(request.bufnr) then
        return false
    end
    request_sequence = request_sequence + 1
    local queued = vim.deepcopy(request)
    queued.worker_sequence = request_sequence
    pending[request.bufnr] = queued
    dispatch_pending()
    return true
end

---@type fun(callback_session: string, event: string, payload: table)
M._dispatch = host.dispatch

---@param options? table
---@return boolean
M.setup = function(options)
    M.dispose()
    options = options or {}
    on_result = options.on_result
    on_failure = options.on_failure
    local test_options = options.test or {}
    pending = {}
    in_flight = nil
    max_in_flight = 0
    return host.start({
        chunk_size = test_options.chunk_size,
        timing = test_options.on_timing,
        child_timing = test_options.timing == true,
        fail_reason = test_options.fail_start and "injected startup failure" or nil,
        extension_options = {
            scan_delay_ms = test_options.scan_delay_ms,
            timing = test_options.timing == true,
        },
    })
end

M.status = function()
    return {
        state = host.state(),
        session = host.session(),
        job_id = host.job_id(),
        mirrors = host.status_mirrors(),
        in_flight = in_flight and {
            bufnr = in_flight.bufnr,
            generation = in_flight.generation,
            signature = in_flight.signature,
            mirror = vim.deepcopy(in_flight.mirror),
        } or nil,
        pending_count = vim.tbl_count(pending),
        max_in_flight = max_in_flight,
        argv = host.argv(),
    }
end

M.dispose = function()
    host.dispose()
    on_result = nil
    on_failure = nil
end

-- selene: allow(global_usage)
_G.__scrollbar_search_worker_callback = function(callback_session, event, payload)
    M._dispatch(callback_session, event, payload)
end

return M
