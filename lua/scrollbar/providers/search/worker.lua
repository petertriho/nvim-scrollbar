--- Search worker: scans mirrored buffers for the search pattern in a headless
--- child Neovim. `scrollbar.shared.mirror` owns the child process and the
--- buffer mirrors. This module keeps one pending scan for each buffer and one
--- scan in flight. After an edit, the child searches only the changed lines
--- when the pattern cannot match across lines. On worker failure the module
--- emits exactly one warning, and the search provider uses the synchronous
--- scan for the rest of the session.

local mirror_host = require("scrollbar.shared.mirror")
local text_tick = require("scrollbar.shared.text_tick")

local M = {}

-- Child code that adds the `scan` request kind. It runs after the mirror
-- prelude, with the child mirror table and the extension options.
local CHILD_EXTENSION = [[
local child, options = ...

-- The last scan of each buffer. A later scan with the same signature applies
-- the edits since then to its match lines, and searches only the changed
-- lines. Each delta adds one edit, so the scan has every edit when its
-- version plus the edit count equals the mirror version.
local scans = {}

-- More edits than this drop the last scan, for example while the search is
-- hidden and the user edits for a long time.
local MAX_EDITS = 64

-- Atoms with which a match can span lines, or depend on the line number, the
-- cursor, a mark, or the last substitute string. A pattern with one of them
-- gets a full scan. The check is textual, so an escaped backslash before one
-- of them also gives a full scan.
local FULL_SCAN_ATOMS = { "\\n", "\\_", "\\%", "\\v", "\\@", "~" }

local function line_local(pattern)
    for _, atom in ipairs(FULL_SCAN_ATOMS) do
        if pattern:find(atom, 1, true) then
            return false
        end
    end
    return true
end

child.on_snapshot_start = function(_, payload)
    scans[payload.bufnr] = nil
end

child.on_delta = function(mirror, payload)
    local scan = scans[payload.bufnr]
    if scan == nil then
        return
    end
    if scan.id ~= mirror.id or #scan.edits >= MAX_EDITS then
        scans[payload.bufnr] = nil
        return
    end
    scan.edits[#scan.edits + 1] = { payload.first, payload.last, #payload.lines }
end

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

-- The zero-based line of each match from line `start_line` (one-based) to
-- `stopline` (zero for the end of the buffer), in buffer order. A forward
-- search without wrap reports the matches in order, and the skip callback
-- runs once for each match.
local function collect(pattern, start_line, stopline)
    local lines = {}
    local previous_row, previous_col = -1, -1
    local sorted = true
    local get_cursor = vim.api.nvim_win_get_cursor
    vim.api.nvim_win_set_cursor(0, { start_line, 0 })
    vim.fn.searchpos(pattern, "Wnc", stopline, 0, function()
        local cursor = get_cursor(0)
        local row, col = cursor[1], cursor[2]
        if row ~= previous_row or col ~= previous_col then
            if row < previous_row or (row == previous_row and col < previous_col) then
                sorted = false
            end
            previous_row, previous_col = row, col
            lines[#lines + 1] = row - 1
        end
        return true
    end)
    if not sorted then
        table.sort(lines)
    end
    return lines
end

-- Applies the edits to the match lines of the last scan. Each edit replaces
-- lines [first, last) with `count` lines. The result drops the matches in the
-- replaced lines, shifts the later matches, and returns the span [low, high)
-- that holds every changed line, or nil without edits.
local function apply_edits(lines, edits)
    local low, high
    for _, edit in ipairs(edits) do
        local first, last, count = edit[1], edit[2], edit[3]
        local delta = count - (last - first)
        local shifted = {}
        for _, line in ipairs(lines) do
            if line < first then
                shifted[#shifted + 1] = line
            elseif line >= last then
                shifted[#shifted + 1] = line + delta
            end
        end
        lines = shifted
        if low == nil then
            low, high = first, first + count
        else
            if low >= last then
                low = low + delta
            elseif low > first then
                low = first
            end
            if high >= last then
                high = high + delta
            elseif high > first then
                high = first + count
            end
            low = math.min(low, first)
            high = math.max(high, first + count)
        end
    end
    return lines, low, high
end

-- The match lines of the last scan, updated for the edits since then, or nil
-- when a full scan is needed. The second result is the count of searched
-- lines.
local function changed_scan(payload, mirror, line_count)
    local scan = scans[payload.bufnr]
    if
        scan == nil
        or scan.id ~= mirror.id
        or scan.signature ~= payload.signature
        or scan.version + #scan.edits ~= mirror.version
        or not line_local(payload.pattern)
    then
        return nil
    end
    local kept, low, high = apply_edits(scan.lines, scan.edits)
    if low == nil then
        return kept, 0
    end
    high = math.min(high, line_count)
    if high - low > line_count / 2 then
        return nil
    end
    local found = low < high and collect(payload.pattern, low + 1, high) or {}
    local lines = {}
    for _, line in ipairs(kept) do
        if line >= low then
            break
        end
        lines[#lines + 1] = line
    end
    for _, line in ipairs(found) do
        lines[#lines + 1] = line
    end
    for _, line in ipairs(kept) do
        if line >= high then
            lines[#lines + 1] = line
        end
    end
    return lines, math.max(0, high - low)
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

    local ok, lines, scanned_lines = pcall(function()
        vim.o.ignorecase = payload.ignorecase
        vim.o.smartcase = payload.smartcase
        vim.o.magic = payload.magic
        vim.bo[mirror.child_buf].iskeyword = payload.iskeyword
        vim.api.nvim_win_set_buf(0, mirror.child_buf)
        local line_count = vim.api.nvim_buf_line_count(mirror.child_buf)
        local changed, searched = changed_scan(payload, mirror, line_count)
        if changed ~= nil then
            return changed, searched
        end
        return collect(payload.pattern, 1, 0), line_count
    end)

    if ok and line_local(payload.pattern) then
        scans[payload.bufnr] = {
            id = mirror.id,
            version = mirror.version,
            signature = payload.signature,
            lines = lines,
            edits = {},
        }
    else
        scans[payload.bufnr] = nil
    end

    child.send("result", {
        bufnr = payload.bufnr,
        generation = payload.generation,
        signature = payload.signature,
        mirror = payload.mirror,
        compact = ok and encode_lines(lines) or vim.NIL,
        scan_duration_ms = scan_started and (vim.uv.hrtime() - scan_started) / 1000000 or nil,
        scanned_lines = options.timing and ok and scanned_lines or nil,
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
