local M = {}

local DEFAULT_CHUNK_SIZE = 512
local CHILD_DISPATCH = [[
local session, kind, payload = ...
local worker = rawget(_G, "__scrollbar_search_worker_child")
if worker ~= nil and worker.session == session then
    local ok, err = pcall(worker.handle, kind, payload)
    if not ok then
        worker.fail(tostring(err))
    end
end
]]
local CHILD_BOOTSTRAP = [=[
local session, options = ...
local mirrors = {}
local callback_source = [==[
local session, event, payload = ...
local callback = rawget(_G, "__scrollbar_search_worker_callback")
if callback ~= nil then
    callback(session, event, payload)
end
]==]

local function send(event, payload)
    vim.rpcnotify(1, "nvim_exec_lua", callback_source, { session, event, payload })
end

local function ensure_buffer(mirror)
    if mirror.child_buf == nil or not vim.api.nvim_buf_is_valid(mirror.child_buf) then
        mirror.child_buf = vim.api.nvim_create_buf(false, true)
    end
    return mirror.child_buf
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

local function scan(payload)
    local mirror = mirrors[payload.bufnr]
    if mirror == nil
        or not mirror.complete
        or mirror.id ~= payload.mirror.id
        or mirror.version ~= payload.mirror.version
        or mirror.changedtick ~= payload.mirror.changedtick
    then
        send("mirror_invalid", { bufnr = payload.bufnr })
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

    send("result", {
        bufnr = payload.bufnr,
        generation = payload.generation,
        signature = payload.signature,
        mirror = payload.mirror,
        compact = ok and compact or vim.NIL,
        scan_duration_ms = scan_started and (vim.uv.hrtime() - scan_started) / 1000000 or nil,
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
        if options.timing then
            send("mirror_complete", {
                bufnr = payload.bufnr,
                id = payload.id,
                version = payload.version,
                changedtick = payload.changedtick,
            })
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
        if options.timing then
            send("delta_complete", {
                bufnr = payload.bufnr,
                id = payload.id,
                version = payload.version,
                changedtick = payload.changedtick,
            })
        end
    elseif kind == "detach" then
        local mirror = mirrors[payload.bufnr]
        if mirror ~= nil and mirror.child_buf ~= nil and vim.api.nvim_buf_is_valid(mirror.child_buf) then
            pcall(vim.api.nvim_buf_delete, mirror.child_buf, { force = true })
        end
        mirrors[payload.bufnr] = nil
    elseif kind == "scan" then
        scan(payload)
    elseif kind == "dispose" then
        for _, mirror in pairs(mirrors) do
            if mirror.child_buf ~= nil and vim.api.nvim_buf_is_valid(mirror.child_buf) then
                pcall(vim.api.nvim_buf_delete, mirror.child_buf, { force = true })
            end
        end
        mirrors = {}
    end
end

_G.__scrollbar_search_worker_child = worker
send("ready", {})
]=]

---@class ScrollbarSearchWorkerMirror
---@field bufnr integer
---@field id integer
---@field version integer
---@field changedtick? integer
---@field complete boolean
---@field attached boolean
---@field snapshot_tick? integer
---@field snapshot_next? integer
---@field snapshot_line_count? integer

---@type "disposed"|"starting"|"ready"|"failed"
local worker_state = "disposed"

---@type integer?
local job_id

---@type string?
local session

---@type table<integer, ScrollbarSearchWorkerMirror>
local mirrors = {}

---@type table<integer, table>
local pending = {}

---@type table?
local in_flight

---@type fun(result: table)?
local on_result

---@type fun(reason: string)?
local on_failure

---@type integer?
local shutdown_group

local session_sequence = 0
local mirror_sequence = 0
local request_sequence = 0
local expected_exit = false
local warned = false
local stderr = {}
local chunk_size = DEFAULT_CHUNK_SIZE
local max_in_flight = 0
local command

---@type fun(event: string, payload?: table)?
local timing_hook

local dispatch_pending

---@param event string
---@param payload? table
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
    vim.notify("[scrollbar.nvim] search worker failed; using synchronous fallback: " .. reason, vim.log.levels.WARN)
end

local function detach_mirror(bufnr, notify)
    local mirror = mirrors[bufnr]
    if mirror == nil then
        return
    end
    mirrors[bufnr] = nil
    pending[bufnr] = nil
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

function M.failure(reason)
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

local function start_snapshot(mirror)
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
    mirror.snapshot_tick = vim.api.nvim_buf_get_changedtick(mirror.bufnr)
    mirror.snapshot_next = 0
    mirror.snapshot_line_count = vim.api.nvim_buf_line_count(mirror.bufnr)
    emit_timing("snapshot_started", { bufnr = mirror.bufnr, id = mirror.id })
    notify_child("snapshot_start", {
        bufnr = mirror.bufnr,
        id = mirror.id,
        version = mirror.version,
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
            M.failure("buffer snapshot notification failed")
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
            M.failure("buffer snapshot completion failed")
            return
        end
        emit_timing("snapshot_parent_complete", { bufnr = mirror.bufnr, id = mirror.id })
        dispatch_pending()
    end
    vim.schedule(read_chunk)
end

function M.sync_buffer(bufnr)
    if worker_state == "failed" or worker_state == "disposed" then
        return false
    end
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return false
    end

    local mirror = mirrors[bufnr]
    if mirror ~= nil then
        return true
    end
    mirror = {
        bufnr = bufnr,
        id = 0,
        version = 0,
        complete = false,
        attached = false,
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

            local delta_started = vim.uv.hrtime()
            emit_timing("delta_started", { bufnr = buffer })
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
                    M.failure("buffer delta notification failed")
                end)
                return true
            end
            emit_timing("delta_sent", {
                bufnr = buffer,
                version = current.version,
                duration_ms = (vim.uv.hrtime() - delta_started) / 1000000,
            })
            dispatch_pending()
            return false
        end,
        on_detach = function(_, buffer)
            if mirrors[buffer] == mirror then
                mirrors[buffer] = nil
                pending[buffer] = nil
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

function M.detach_buffer(bufnr)
    detach_mirror(bufnr, true)
end

dispatch_pending = function()
    if worker_state ~= "ready" or in_flight ~= nil then
        return
    end

    local selected
    for bufnr, request in pairs(pending) do
        local mirror = mirrors[bufnr]
        if
            mirror ~= nil
            and mirror.complete
            and mirror.changedtick == request.changedtick
            and (selected == nil or request.worker_sequence > selected.worker_sequence)
        then
            selected = request
        end
    end
    if selected == nil then
        return
    end

    pending[selected.bufnr] = nil
    local mirror = mirrors[selected.bufnr]
    selected.mirror = {
        session = session,
        id = mirror.id,
        version = mirror.version,
        changedtick = mirror.changedtick,
    }
    in_flight = selected
    max_in_flight = math.max(max_in_flight, 1)
    if not notify_child("scan", selected) then
        M.failure("scan notification failed")
        return
    end
    emit_timing("scan_dispatched", {
        bufnr = selected.bufnr,
        generation = selected.generation,
    })
end

function M.request(request)
    if worker_state == "failed" or worker_state == "disposed" then
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

function M._dispatch(callback_session, event, payload)
    if callback_session ~= session or worker_state == "disposed" or worker_state == "failed" then
        return
    end
    if event == "ready" then
        worker_state = "ready"
        emit_timing("worker_ready")
        dispatch_pending()
        return
    end
    if event == "mirror_complete" or event == "delta_complete" then
        emit_timing(event, payload)
        return
    end
    if event == "mirror_invalid" then
        local mirror = mirrors[payload.bufnr]
        if mirror ~= nil then
            start_snapshot(mirror)
        end
        return
    end
    if event == "failure" then
        M.failure(payload.reason or "child protocol failure")
        return
    end
    if event ~= "result" or in_flight == nil then
        return
    end

    emit_timing("result_callback_started", payload)
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
    emit_timing("result_callback_complete", payload)
end

function M.setup(options)
    M.dispose()
    options = options or {}
    on_result = options.on_result
    on_failure = options.on_failure
    local test_options = options.test or {}
    timing_hook = test_options.on_timing
    chunk_size = test_options.chunk_size or DEFAULT_CHUNK_SIZE
    warned = false
    expected_exit = false
    stderr = {}
    mirrors = {}
    pending = {}
    in_flight = nil
    max_in_flight = 0
    session_sequence = session_sequence + 1
    session = string.format("%d:%s", session_sequence, tostring(vim.uv.hrtime()))
    worker_state = "starting"
    emit_timing("startup_started")

    shutdown_group = vim.api.nvim_create_augroup("ScrollbarSearchWorker", { clear = true })
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = shutdown_group,
        callback = function()
            M.dispose()
        end,
    })

    if test_options.fail_start then
        M.failure("injected startup failure")
        return false
    end

    local token = session
    command = {
        vim.v.progpath,
        "--embed",
        "--headless",
        "-u",
        "NONE",
        "-i",
        "NONE",
        "--noplugin",
    }
    job_id = vim.fn.jobstart(command, {
        rpc = true,
        on_stderr = function(_, data)
            if token ~= session or type(data) ~= "table" then
                return
            end
            for _, line in ipairs(data) do
                if line ~= "" then
                    stderr[#stderr + 1] = line
                end
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                if token ~= session or expected_exit or worker_state == "disposed" then
                    return
                end
                local detail = #stderr > 0 and table.concat(stderr, "\n") or "exit code " .. tostring(code)
                M.failure(detail)
            end)
        end,
    })
    if job_id == nil or job_id <= 0 then
        local code = job_id
        job_id = nil
        M.failure("jobstart returned " .. tostring(code))
        return false
    end

    local ok = pcall(vim.rpcnotify, job_id, "nvim_exec_lua", CHILD_BOOTSTRAP, {
        session,
        { scan_delay_ms = test_options.scan_delay_ms, timing = test_options.timing == true },
    })
    if not ok then
        M.failure("bootstrap notification failed")
        return false
    end
    vim.defer_fn(function()
        if token == session and worker_state == "starting" then
            M.failure("startup timed out")
        end
    end, 5000)
    return true
end

function M.status()
    local mirror_status = {}
    for bufnr, mirror in pairs(mirrors) do
        mirror_status[#mirror_status + 1] = {
            bufnr = bufnr,
            id = mirror.id,
            version = mirror.version,
            changedtick = mirror.changedtick,
            complete = mirror.complete,
        }
    end
    table.sort(mirror_status, function(left, right)
        return left.bufnr < right.bufnr
    end)
    return {
        state = worker_state,
        session = session,
        job_id = job_id,
        mirrors = mirror_status,
        in_flight = in_flight and {
            bufnr = in_flight.bufnr,
            generation = in_flight.generation,
            signature = in_flight.signature,
            mirror = vim.deepcopy(in_flight.mirror),
        } or nil,
        pending_count = vim.tbl_count(pending),
        max_in_flight = max_in_flight,
        argv = vim.deepcopy(command),
    }
end

function M.dispose()
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
    worker_state = "disposed"
end

-- selene: allow(global_usage)
_G.__scrollbar_search_worker_callback = function(callback_session, event, payload)
    M._dispatch(callback_session, event, payload)
end

return M
