local M = { name = "search" }
local compact_search = require("scrollbar.providers.search_compact")
local store = require("scrollbar.store")
local worker = require("scrollbar.providers.search_worker")

local INCSEARCH_DEBOUNCE_MS = 30
local EDIT_DEBOUNCE_MS = 50

---@class ScrollbarSearchCommandlineState
---@field bufnr integer
---@field pattern string
---@field incsearch_pattern string
---@field visible boolean

---@type ScrollbarProviderContext?
local active_context

---@type ScrollbarSearchProviderConfig
local options = { backend = "worker" }

---@type ScrollbarSearchCommandlineState?
local commandline

---@alias ScrollbarSearchRequestMode "accepted"|"incsearch"|"edit"

---@class ScrollbarSearchRequest
---@field bufnr integer
---@field generation integer
---@field changedtick integer
---@field pattern string
---@field visible boolean
---@field signature string
---@field mode ScrollbarSearchRequestMode
---@field ignore_visibility boolean
---@field ignorecase boolean
---@field smartcase boolean
---@field magic boolean
---@field iskeyword string

---@class ScrollbarSearchRequestState
---@field generation integer
---@field pending? ScrollbarSearchRequest
---@field completed_signature? string
---@field completed_changedtick? integer
---@field worker_request? ScrollbarSearchRequest

---@type table<integer, ScrollbarSearchRequestState>
local request_states = {}

---@type "sync"|"worker"
local backend = "sync"

---@type fun(event: string, payload?: table)?
local timing_hook

---@param event string
---@param payload? table
local function emit_timing(event, payload)
    if timing_hook ~= nil then
        pcall(timing_hook, event, payload or {})
    end
end

local function search_is_visible()
    return vim.o.hlsearch and vim.v.hlsearch ~= 0 and vim.fn.getreg("/") ~= ""
end

local function incsearch_enabled()
    if options.incsearch ~= nil then
        return options.incsearch
    end
    return vim.o.incsearch
end

---@param bufnr integer
---@param pattern string
---@return string
local function search_signature(bufnr, pattern)
    return table.concat({
        pattern,
        tostring(vim.o.ignorecase),
        tostring(vim.o.smartcase),
        tostring(vim.o.magic),
        vim.bo[bufnr].iskeyword,
    }, "\0")
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@return integer?
local function source_window(context, bufnr)
    local current = vim.api.nvim_get_current_win()
    if
        vim.api.nvim_win_is_valid(current)
        and vim.api.nvim_win_get_config(current).relative == ""
        and vim.api.nvim_win_get_buf(current) == bufnr
    then
        return current
    end

    for _, winid in ipairs(context.source_windows(bufnr)) do
        if vim.api.nvim_win_is_valid(winid) then
            return winid
        end
    end
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@param pattern string
---@return ScrollbarCompactSearch?
local function scan(context, bufnr, pattern)
    local winid = source_window(context, bufnr)
    if winid == nil then
        return nil
    end

    local call_ok, scan_result = pcall(vim.api.nvim_win_call, winid, function()
        local view = vim.fn.winsaveview()
        local ok, result = pcall(function()
            local matches = {}
            local seen = {}

            local function collect()
                local position = { vim.fn.line("."), vim.fn.col(".") }
                local key = string.format("%d:%d", position[1], position[2])
                if not seen[key] then
                    seen[key] = true
                    table.insert(matches, position)
                end
                return true
            end

            vim.fn.searchpos(pattern, "Wnc", 0, 0, collect)
            vim.fn.searchpos(pattern, "bWnc", 0, 0, collect)
            table.sort(matches, function(a, b)
                return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
            end)

            local lines = {}
            for index, position in ipairs(matches) do
                lines[index] = position[1] - 1
            end
            return compact_search.encode(lines)
        end)
        vim.fn.winrestview(view)
        return { ok, result }
    end)

    if not call_ok or not scan_result[1] then
        return nil
    end
    return scan_result[2]
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@param compact ScrollbarCompactSearch
---@return boolean
local function publish_compact(context, bufnr, compact)
    local publication_started = timing_hook and vim.uv.hrtime() or nil
    local published, changed = store._set_search_compact(bufnr, compact)
    for changed_bufnr in pairs(changed) do
        context.invalidate_buffer(changed_bufnr)
    end
    if publication_started ~= nil then
        emit_timing("set_marks", {
            duration_ms = (vim.uv.hrtime() - publication_started) / 1000000,
            mark_count = compact.count,
        })
    end
    return published
end

---@param bufnr integer
---@return ScrollbarSearchRequestState
local function request_state(bufnr)
    local state = request_states[bufnr]
    if state == nil then
        state = { generation = 0 }
        request_states[bufnr] = state
    end
    return state
end

---@param bufnr integer
local function cancel_request(bufnr)
    local state = request_state(bufnr)
    state.generation = state.generation + 1
    state.pending = nil
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function clear_buffer(context, bufnr)
    local state = request_state(bufnr)
    cancel_request(bufnr)
    state.completed_signature = nil
    state.completed_changedtick = nil
    context.clear_marks(bufnr)
end

---@param context ScrollbarProviderContext
local function clear_all(context)
    for _, state in pairs(request_states) do
        state.generation = state.generation + 1
        state.pending = nil
        state.completed_signature = nil
        state.completed_changedtick = nil
    end
    context.clear_marks()
end

---@param request ScrollbarSearchRequest
---@return boolean
local function request_is_current(request)
    if active_context == nil then
        return false
    end

    local state = request_states[request.bufnr]
    if state == nil or state.generation ~= request.generation then
        return false
    end
    if not vim.api.nvim_buf_is_valid(request.bufnr) or not vim.api.nvim_buf_is_loaded(request.bufnr) then
        return false
    end
    if vim.api.nvim_buf_get_changedtick(request.bufnr) ~= request.changedtick then
        return false
    end

    local signature_ok, signature = pcall(search_signature, request.bufnr, request.pattern)
    if not signature_ok or signature ~= request.signature then
        return false
    end

    if request.mode == "incsearch" then
        if not incsearch_enabled() then
            return false
        end
        return commandline == nil
            or (commandline.bufnr == request.bufnr and commandline.incsearch_pattern == request.pattern)
    end

    if vim.fn.getreg("/") ~= request.pattern then
        return false
    end
    return request.ignore_visibility or search_is_visible() == request.visible
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@param generation integer
local function execute_request(context, bufnr, generation)
    if active_context ~= context then
        return
    end

    local state = request_states[bufnr]
    local request = state and state.pending or nil
    if request == nil or request.generation ~= generation then
        return
    end
    state.pending = nil

    if not request_is_current(request) then
        return
    end
    if source_window(context, bufnr) == nil then
        return
    end

    if backend == "worker" then
        state.worker_request = request
        if worker.request(request) then
            return
        end
        state.worker_request = nil
        backend = "sync"
    end

    local scan_started = timing_hook and vim.uv.hrtime() or nil
    if scan_started ~= nil then
        emit_timing("sync_scan_started")
    end
    local compact = scan(context, bufnr, request.pattern)
    if scan_started ~= nil then
        emit_timing("sync_scan", { duration_ms = (vim.uv.hrtime() - scan_started) / 1000000 })
    end
    if not request_is_current(request) then
        return
    end

    if compact == nil then
        state.completed_signature = nil
        state.completed_changedtick = nil
        context.clear_marks(bufnr)
        return
    end

    if publish_compact(context, bufnr, compact) then
        state.completed_signature = request.signature
        state.completed_changedtick = request.changedtick
    end
end

---@param result table
local function handle_worker_result(result)
    if active_context == nil then
        return
    end
    local state = request_states[result.bufnr]
    local request = state and state.worker_request or nil
    if
        request == nil
        or request.generation ~= result.generation
        or request.signature ~= result.signature
        or result.mirror == nil
        or result.mirror.changedtick ~= request.changedtick
    then
        return
    end
    state.worker_request = nil
    if not request_is_current(request) then
        return
    end

    if result.compact == nil then
        state.completed_signature = nil
        state.completed_changedtick = nil
        active_context.clear_marks(result.bufnr)
        return
    end
    local published = publish_compact(active_context, result.bufnr, result.compact)
    if published then
        state.completed_signature = request.signature
        state.completed_changedtick = request.changedtick
    end
end

local function handle_worker_failure()
    local context = active_context
    if context == nil then
        return
    end
    backend = "sync"
    for bufnr, state in pairs(request_states) do
        local request = state.worker_request
        state.worker_request = nil
        if request ~= nil and state.pending == nil and request_is_current(request) then
            state.pending = request
            vim.schedule(function()
                execute_request(context, bufnr, request.generation)
            end)
        end
    end
end

---@param request ScrollbarSearchRequest
---@param other ScrollbarSearchRequest
---@return boolean
local function same_request(request, other)
    return request.changedtick == other.changedtick
        and request.signature == other.signature
        and request.visible == other.visible
        and request.mode == other.mode
        and request.ignore_visibility == other.ignore_visibility
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@param pattern string
---@param mode ScrollbarSearchRequestMode
---@param ignore_visibility? boolean
---@return boolean
local function request_refresh(context, bufnr, pattern, mode, ignore_visibility)
    local visible = search_is_visible()
    if not ignore_visibility and not visible then
        clear_all(context)
        return false
    end
    if pattern == "" then
        if mode == "incsearch" then
            cancel_request(bufnr)
            return false
        end
        clear_buffer(context, bufnr)
        return false
    end

    if source_window(context, bufnr) == nil then
        cancel_request(bufnr)
        return false
    end

    local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
    local signature = search_signature(bufnr, pattern)
    local state = request_state(bufnr)
    local pending = {
        bufnr = bufnr,
        generation = state.generation,
        changedtick = changedtick,
        pattern = pattern,
        visible = visible,
        signature = signature,
        mode = mode,
        ignore_visibility = ignore_visibility == true,
        ignorecase = vim.o.ignorecase,
        smartcase = vim.o.smartcase,
        magic = vim.o.magic,
        iskeyword = vim.bo[bufnr].iskeyword,
    }
    if mode ~= "edit" and state.completed_signature == signature and state.completed_changedtick == changedtick then
        if state.pending ~= nil then
            state.generation = state.generation + 1
            state.pending = nil
        end
        return false
    end
    if state.pending ~= nil and same_request(state.pending, pending) then
        return false
    end

    state.generation = state.generation + 1
    pending.generation = state.generation
    state.pending = pending

    local callback = function()
        execute_request(context, bufnr, pending.generation)
    end
    if mode == "accepted" then
        vim.schedule(callback)
    elseif mode == "incsearch" then
        vim.defer_fn(callback, INCSEARCH_DEBOUNCE_MS)
    else
        vim.defer_fn(callback, EDIT_DEBOUNCE_MS)
    end
    return true
end

---@param context ScrollbarProviderContext
---@param bufnr? integer
local function sync_visibility(context, bufnr)
    if commandline ~= nil then
        return
    end
    if not search_is_visible() then
        clear_all(context)
        return
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local pattern = vim.fn.getreg("/")
    request_refresh(context, bufnr, pattern, "accepted")
end

---@param context ScrollbarProviderContext
---@param callback fun()
local function schedule(context, callback)
    vim.schedule(function()
        if active_context == context then
            callback()
        end
    end)
end

---@param context ScrollbarProviderContext
function M.setup(context)
    local search_options = context.config.providers.search
    if search_options == false then
        error("search provider cannot be set up while disabled")
    end

    active_context = context
    options = search_options
    commandline = nil
    request_states = {}
    worker.dispose()
    local worker_test = package.loaded["scrollbar.test.search_worker"]
    timing_hook = type(worker_test) == "table" and worker_test.on_timing or nil
    backend = type(worker_test) == "table" and worker_test.backend or search_options.backend
    if backend == "worker" then
        if
            not worker.setup({
                on_result = handle_worker_result,
                on_failure = handle_worker_failure,
                test = worker_test,
            })
        then
            backend = "sync"
        end
    end

    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("CmdlineEnter", {
        group = group,
        pattern = { "/", "?" },
        callback = function()
            commandline = {
                bufnr = vim.api.nvim_get_current_buf(),
                pattern = vim.fn.getreg("/"),
                incsearch_pattern = vim.fn.getcmdline(),
                visible = search_is_visible(),
            }
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineChanged", {
        group = group,
        pattern = { "/", "?" },
        callback = function()
            local pattern = vim.fn.getcmdline()
            if commandline ~= nil then
                commandline.incsearch_pattern = pattern
            end
            if incsearch_enabled() then
                request_refresh(context, vim.api.nvim_get_current_buf(), pattern, "incsearch", true)
            end
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        callback = function(args)
            local cmdtype = args.match
            local aborted = vim.v.event.abort == true or vim.v.event.abort == 1
            local previous = commandline
            local bufnr = vim.api.nvim_get_current_buf()
            if previous ~= nil then
                cancel_request(previous.bufnr)
            end
            commandline = nil

            schedule(context, function()
                if commandline ~= nil then
                    return
                end
                if cmdtype ~= "/" and cmdtype ~= "?" then
                    sync_visibility(context, bufnr)
                elseif aborted and previous ~= nil then
                    if previous.visible and previous.pattern ~= "" then
                        request_refresh(context, previous.bufnr, previous.pattern, "accepted", true)
                    else
                        clear_buffer(context, previous.bufnr)
                    end
                else
                    request_refresh(context, bufnr, vim.fn.getreg("/"), "accepted")
                end
            end)
        end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function(args)
            request_refresh(context, args.buf, vim.fn.getreg("/"), "accepted")
        end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = group,
        callback = function(args)
            request_refresh(context, args.buf, vim.fn.getreg("/"), "edit")
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(args)
            worker.detach_buffer(args.buf)
            request_states[args.buf] = nil
            if commandline ~= nil and commandline.bufnr == args.buf then
                commandline = nil
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "SafeState" }, {
        group = group,
        callback = function(args)
            sync_visibility(context, args.buf)
        end,
    })
    vim.api.nvim_create_autocmd("OptionSet", {
        group = group,
        pattern = { "hlsearch", "ignorecase", "smartcase", "magic", "iskeyword" },
        callback = function(args)
            local bufnr = args.buf
            schedule(context, function()
                sync_visibility(context, bufnr)
            end)
        end,
    })
end

---@param bufnr integer
---@param context ScrollbarProviderContext
function M.refresh(bufnr, context)
    request_refresh(context, bufnr, vim.fn.getreg("/"), "accepted")
end

---@param context ScrollbarProviderContext
function M.dispose(context)
    if active_context ~= context then
        return
    end
    active_context = nil
    backend = "sync"
    worker.dispose()
    timing_hook = nil
    commandline = nil
    request_states = {}
end

return M
