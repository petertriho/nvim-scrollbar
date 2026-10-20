--- Parent side of the buffer mirror protocol, shared by the search worker and
--- the minimap worker. Each worker creates one host. A host starts a headless
--- child Neovim, copies each requested buffer into it with chunked snapshots,
--- and sends every later text change from `on_lines` as a delta. The child side
--- is `lua/scrollbar/shared/mirror_child.lua`.
---
--- The worker keeps its own request queue and child request kinds. The host
--- calls the hooks of the worker when a mirror can serve a request, when the
--- child rejects a request, and when the worker fails or is disposed.
---
--- `on_lines` runs synchronously for every text change, so a complete mirror
--- never misses text. A buffer `changedtick` can still increase without a text
--- change, for example when `:write` resets 'modified'. `ready_mirror` takes
--- the current `changedtick` for such a mirror, so that requests made after the
--- increase match it.

local M = {}

local DEFAULT_CHUNK_SIZE = 512
local STARTUP_TIMEOUT_MS = 5000

local BOOTSTRAP = [[
local session, options = ...
local child = loadstring(options.prelude)().new(session, options)
loadstring(options.extension)(child, options.extension_options)
child.send("ready", {})
]]

---@class ScrollbarMirror
---@field bufnr integer
---@field id integer
---@field version integer
---@field changedtick? integer
---@field complete boolean
---@field lang? string
---@field snapshot_tick? integer
---@field snapshot_next? integer
---@field snapshot_line_count? integer

---@class ScrollbarMirrorHostOptions
---@field name string Worker name in the failure warning
---@field augroup string Augroup that disposes the worker on `VimLeavePre`
---@field child_global string Child global that receives the parent notifications
---@field callback_global string Parent global that receives the child events
---@field extension string Child source that adds the request kinds of the worker
---@field dispatch_pending fun() Called when a mirror can serve a request
---@field on_event fun(event: string, payload: table) Child events of the worker
---@field on_mirror_invalid fun(bufnr: integer, id?: integer) The child rejected work for a mirror
---@field on_detach fun(bufnr: integer) A mirror was removed
---@field on_reset fun() The worker failed or was disposed
---@field on_failure fun(reason: string) Called after the failure warning
---@field on_leave fun() Called on `VimLeavePre`
---@field on_snapshot_start? fun(mirror: ScrollbarMirror)
---@field exit_reason fun(code: integer, stderr: string[]): string

---@class ScrollbarMirrorStartOptions
---@field chunk_size? integer
---@field timing? fun(event: string, payload: table)
---@field child_timing? boolean Ask the child for `mirror_complete` and `delta_complete` events
---@field fail_reason? string Fail the start with this reason before the child starts
---@field extension_options? table

---@class ScrollbarMirrorStatus
---@field bufnr integer
---@field id integer
---@field version integer
---@field changedtick? integer
---@field complete boolean

---@class ScrollbarMirrorHost
---@field start fun(options: ScrollbarMirrorStartOptions): boolean
---@field dispose fun()
---@field failure fun(reason: string)
---@field dispatch fun(callback_session: string, event: string, payload: table)
---@field notify fun(kind: string, payload: table): boolean
---@field sync fun(bufnr: integer, lang?: string): boolean
---@field detach fun(bufnr: integer, notify: boolean)
---@field ready_mirror fun(bufnr: integer): ScrollbarMirror?
---@field emit fun(event: string, payload?: table)
---@field state fun(): "disposed"|"starting"|"ready"|"failed"
---@field session fun(): string?
---@field job_id fun(): integer?
---@field argv fun(): string[]?
---@field status_mirrors fun(decorate?: fun(entry: table, mirror: ScrollbarMirror)): ScrollbarMirrorStatus[]

--- Read the source of a runtime file, for code that runs in the child.
---@param rel_path string
---@return string?
M.read_runtime_source = function(rel_path)
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

---@param options ScrollbarMirrorHostOptions
---@return ScrollbarMirrorHost
M.new = function(options)
    local name = options.name
    local dispatch_pending = options.dispatch_pending
    local on_event = options.on_event
    local on_mirror_invalid = options.on_mirror_invalid
    local on_detach = options.on_detach
    local on_reset = options.on_reset
    local on_failure = options.on_failure
    local on_snapshot_start = options.on_snapshot_start
    local child_dispatch = string.format(
        [[
local session, kind, payload = ...
local worker = rawget(_G, %q)
if worker ~= nil and worker.session == session then
    local ok, err = pcall(worker.handle, kind, payload)
    if not ok then
        worker.fail(tostring(err))
    end
end
]],
        options.child_global
    )

    ---@type "disposed"|"starting"|"ready"|"failed"
    local state = "disposed"
    ---@type integer?
    local job_id
    ---@type string?
    local session
    ---@type string[]?
    local argv
    ---@type table<integer, ScrollbarMirror>
    local mirrors = {}
    ---@type integer?
    local shutdown_group
    ---@type fun(event: string, payload: table)?
    local timing_hook
    local session_sequence = 0
    local mirror_sequence = 0
    local expected_exit = false
    local warned = false
    local stderr = {}
    local chunk_size = DEFAULT_CHUNK_SIZE

    ---@param event string
    ---@param payload? table
    local function emit(event, payload)
        if timing_hook ~= nil then
            pcall(timing_hook, event, payload or {})
        end
    end

    ---@param kind string
    ---@param payload table
    ---@return boolean
    local function notify(kind, payload)
        if job_id == nil or state == "failed" or state == "disposed" then
            return false
        end
        local ok = pcall(vim.rpcnotify, job_id, "nvim_exec_lua", child_dispatch, { session, kind, payload })
        return ok
    end

    ---@param reason string
    local function warn_once(reason)
        if warned then
            return
        end
        warned = true
        vim.notify(
            "[nvim-scrollbar] " .. name .. " worker failed; using synchronous fallback: " .. reason,
            vim.log.levels.WARN
        )
    end

    -- A Lua `on_lines` callback cannot be detached directly. Instead, the
    -- callback returns true on its next call, when its mirror is not
    -- registered.
    ---@param bufnr integer
    ---@param notify_child boolean
    local function detach(bufnr, notify_child)
        if mirrors[bufnr] == nil then
            return
        end
        mirrors[bufnr] = nil
        on_detach(bufnr)
        if notify_child then
            notify("detach", { bufnr = bufnr })
        end
    end

    ---@param notify_child boolean
    local function detach_all(notify_child)
        for _, bufnr in ipairs(vim.tbl_keys(mirrors)) do
            detach(bufnr, notify_child)
        end
    end

    ---@param reason string
    local function failure(reason)
        if state == "failed" or state == "disposed" then
            return
        end
        state = "failed"
        expected_exit = true
        local failed_job = job_id
        job_id = nil
        detach_all(false)
        on_reset()
        if failed_job ~= nil then
            pcall(vim.fn.jobstop, failed_job)
        end
        warn_once(reason)
        on_failure(reason)
    end

    ---@param mirror ScrollbarMirror
    local function start_snapshot(mirror)
        if state == "failed" or state == "disposed" then
            return
        end
        if not vim.api.nvim_buf_is_valid(mirror.bufnr) or not vim.api.nvim_buf_is_loaded(mirror.bufnr) then
            detach(mirror.bufnr, true)
            return
        end

        mirror_sequence = mirror_sequence + 1
        mirror.id = mirror_sequence
        mirror.version = 1
        mirror.complete = false
        mirror.snapshot_tick = vim.api.nvim_buf_get_changedtick(mirror.bufnr)
        mirror.snapshot_next = 0
        mirror.snapshot_line_count = vim.api.nvim_buf_line_count(mirror.bufnr)
        if on_snapshot_start ~= nil then
            on_snapshot_start(mirror)
        end
        emit("snapshot_started", { bufnr = mirror.bufnr, id = mirror.id })
        notify("snapshot_start", {
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
                detach(mirror.bufnr, true)
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
                not notify("snapshot_chunk", {
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
            emit("snapshot_chunk", {
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
                not notify("snapshot_complete", {
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
            emit("snapshot_parent_complete", { bufnr = mirror.bufnr, id = mirror.id })
            dispatch_pending()
        end
        vim.schedule(read_chunk)
    end

    ---@param start_options ScrollbarMirrorStartOptions
    ---@return boolean
    local function start(start_options)
        chunk_size = start_options.chunk_size or DEFAULT_CHUNK_SIZE
        timing_hook = start_options.timing
        warned = false
        expected_exit = false
        stderr = {}
        mirrors = {}
        session_sequence = session_sequence + 1
        session = string.format("%d:%s", session_sequence, tostring(vim.uv.hrtime()))
        state = "starting"
        emit("startup_started")

        shutdown_group = vim.api.nvim_create_augroup(options.augroup, { clear = true })
        vim.api.nvim_create_autocmd("VimLeavePre", {
            group = shutdown_group,
            callback = function()
                options.on_leave()
            end,
        })

        if start_options.fail_reason ~= nil then
            failure(start_options.fail_reason)
            return false
        end

        local prelude = M.read_runtime_source("lua/scrollbar/shared/mirror_child.lua")
        if prelude == nil then
            failure("could not read mirror_child.lua source")
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
                    if token ~= session or expected_exit or state == "disposed" or state == "failed" then
                        return
                    end
                    failure(options.exit_reason(code, stderr))
                end)
            end,
        })
        if job_id == nil or job_id <= 0 then
            local code = job_id
            job_id = nil
            failure("jobstart returned " .. tostring(code))
            return false
        end

        local ok = pcall(vim.rpcnotify, job_id, "nvim_exec_lua", BOOTSTRAP, {
            session,
            {
                prelude = prelude,
                extension = options.extension,
                extension_options = start_options.extension_options or {},
                child_global = options.child_global,
                callback_global = options.callback_global,
                timing = start_options.child_timing == true,
            },
        })
        if not ok then
            failure("bootstrap notification failed")
            return false
        end
        vim.defer_fn(function()
            if token == session and state == "starting" then
                failure("startup timed out")
            end
        end, STARTUP_TIMEOUT_MS)
        return true
    end

    local function dispose()
        if shutdown_group ~= nil then
            pcall(vim.api.nvim_del_augroup_by_id, shutdown_group)
            shutdown_group = nil
        end
        expected_exit = true
        if job_id ~= nil then
            notify("dispose", {})
        end
        detach_all(false)
        local disposed_job = job_id
        job_id = nil
        if disposed_job ~= nil then
            pcall(vim.fn.jobstop, disposed_job)
        end
        on_reset()
        timing_hook = nil
        state = "disposed"
    end

    ---@param bufnr integer
    ---@param lang? string
    ---@return boolean
    local function sync(bufnr, lang)
        if state == "failed" or state == "disposed" then
            return false
        end
        if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
            return false
        end

        local mirror = mirrors[bufnr]
        if mirror ~= nil and mirror.lang == lang then
            return true
        end
        if mirror ~= nil then
            detach(bufnr, true)
        end
        ---@type ScrollbarMirror
        mirror = {
            bufnr = bufnr,
            id = 0,
            version = 0,
            complete = false,
            lang = lang,
        }
        mirrors[bufnr] = mirror
        local attached = vim.api.nvim_buf_attach(bufnr, false, {
            on_lines = function(_, buffer, changedtick, first, last, new_last)
                local current = mirrors[buffer]
                if current ~= mirror then
                    return true
                end
                if not current.complete then
                    start_snapshot(current)
                    return false
                end

                local delta_started = timing_hook and vim.uv.hrtime() or nil
                if delta_started ~= nil then
                    emit("delta_started", { bufnr = buffer })
                end
                local lines = vim.api.nvim_buf_get_lines(buffer, first, new_last, true)
                local from_version = current.version
                current.version = from_version + 1
                current.changedtick = changedtick
                if
                    not notify("delta", {
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
                if delta_started ~= nil then
                    emit("delta_sent", {
                        bufnr = buffer,
                        version = current.version,
                        duration_ms = (vim.uv.hrtime() - delta_started) / 1000000,
                    })
                end
                dispatch_pending()
                return false
            end,
            on_detach = function(_, buffer)
                if mirrors[buffer] == mirror then
                    mirrors[buffer] = nil
                    on_detach(buffer)
                    notify("detach", { bufnr = buffer })
                end
            end,
        })
        if not attached then
            mirrors[bufnr] = nil
            return false
        end
        start_snapshot(mirror)
        return true
    end

    ---@param bufnr integer
    ---@return ScrollbarMirror?
    local function ready_mirror(bufnr)
        local mirror = mirrors[bufnr]
        if mirror == nil or not mirror.complete then
            return nil
        end
        -- A complete mirror has every text change, so a different changedtick
        -- comes from an increase without a text change.
        mirror.changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
        return mirror
    end

    ---@param callback_session string
    ---@param event string
    ---@param payload table
    local function dispatch(callback_session, event, payload)
        if callback_session ~= session or state == "disposed" or state == "failed" then
            return
        end
        if event == "ready" then
            if state == "starting" then
                state = "ready"
                emit("worker_ready")
                dispatch_pending()
            end
            return
        end
        if event == "mirror_invalid" then
            -- The child names the mirror id of the rejected work. An id of an
            -- older mirror still rejects the in-flight request made for that
            -- mirror. But the current mirror needs no new snapshot, and the
            -- requeued request can go to it immediately.
            on_mirror_invalid(payload.bufnr, payload.id)
            local mirror = mirrors[payload.bufnr]
            if mirror ~= nil and (payload.id == nil or payload.id == mirror.id) then
                start_snapshot(mirror)
            end
            dispatch_pending()
            return
        end
        if event == "mirror_complete" or event == "delta_complete" then
            emit(event, payload)
            return
        end
        if event == "failure" then
            failure(payload.reason or "child protocol failure")
            return
        end
        on_event(event, payload)
    end

    ---@param decorate? fun(entry: table, mirror: ScrollbarMirror)
    ---@return ScrollbarMirrorStatus[]
    local function status_mirrors(decorate)
        local result = {}
        for bufnr, mirror in pairs(mirrors) do
            local entry = {
                bufnr = bufnr,
                id = mirror.id,
                version = mirror.version,
                changedtick = mirror.changedtick,
                complete = mirror.complete,
            }
            if decorate ~= nil then
                decorate(entry, mirror)
            end
            result[#result + 1] = entry
        end
        table.sort(result, function(left, right)
            return left.bufnr < right.bufnr
        end)
        return result
    end

    return {
        start = start,
        dispose = dispose,
        failure = failure,
        dispatch = dispatch,
        notify = notify,
        sync = sync,
        detach = detach,
        ready_mirror = ready_mirror,
        emit = emit,
        state = function()
            return state
        end,
        session = function()
            return session
        end,
        job_id = function()
            return job_id
        end,
        argv = function()
            return argv and vim.deepcopy(argv) or nil
        end,
        status_mirrors = status_mirrors,
    }
end

return M
