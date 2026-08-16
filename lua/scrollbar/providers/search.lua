local M = {
    name = "search",
    targets = { scrollbar = true, minimap = true },
    refresh_owner = { buffer = "provider" },
}
local compact_search = require("scrollbar.providers.search_compact")
local worker = require("scrollbar.providers.search_worker")

local INCSEARCH_DEBOUNCE_MS = 30
local EDIT_DEBOUNCE_MS = 50

local SYNC_BUDGET_MS = 400
local SYNC_PER_CALL_TIMEOUT_MS = 200
local SYNC_STOPLINE_CAP = 200000

---@class ScrollbarSearchSyncBudget
---@field total_ms integer Total wall-clock budget for one sync scan in milliseconds
---@field per_call_ms integer Per-call timeout passed to each searchpos invocation
---@field stopline integer Maximum line distance from the cursor for either direction

---@type ScrollbarSearchSyncBudget
local sync_budget = {
    total_ms = SYNC_BUDGET_MS,
    per_call_ms = SYNC_PER_CALL_TIMEOUT_MS,
    stopline = SYNC_STOPLINE_CAP,
}

---@class ScrollbarSearchCommandlineState
---@field bufnr integer
---@field pattern string
---@field incsearch_pattern string
---@field visible boolean

---@class ScrollbarSearchProviderContext: ScrollbarProviderContext
---@field _set_search_compact fun(bufnr: integer, compact: ScrollbarCompactSearch): boolean

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
    if context.is_source_window(current) and vim.api.nvim_win_get_buf(current) == bufnr then
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

            local cursor_line = vim.fn.line(".")
            local last_line = vim.fn.line("$")
            local forward_stop = math.min(last_line, cursor_line + sync_budget.stopline)
            local backward_stop = math.max(1, cursor_line - sync_budget.stopline)
            local forward_capped = forward_stop < last_line
            local backward_capped = backward_stop > 1

            local t0 = vim.uv.hrtime()
            vim.fn.searchpos(pattern, "Wnc", forward_stop, sync_budget.per_call_ms, collect)
            local forward_ms = (vim.uv.hrtime() - t0) / 1e6
            local partial = forward_capped or forward_ms >= sync_budget.per_call_ms * 0.95

            if forward_ms < sync_budget.total_ms - sync_budget.per_call_ms then
                vim.fn.searchpos(pattern, "bWnc", backward_stop, sync_budget.per_call_ms, collect)
                local total_ms = (vim.uv.hrtime() - t0) / 1e6
                if backward_capped or total_ms >= sync_budget.total_ms then
                    partial = true
                end
            else
                partial = true
            end

            table.sort(matches, function(a, b)
                return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
            end)

            local lines = {}
            for index, position in ipairs(matches) do
                lines[index] = position[1] - 1
            end
            return compact_search.encode(lines, partial)
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
    ---@cast context ScrollbarSearchProviderContext
    local published = context._set_search_compact(bufnr, compact)
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

-- TextChanged autocmds are attached only while at least one buffer holds
-- pending or completed search state. With no live search they would run on
-- every keystroke only to prove there is nothing to refresh.
local text_change_group ---@type integer?
local text_change_attached = false

local reconcile_text_change_events ---@type fun(context: ScrollbarProviderContext)

---@return boolean
local function search_state_active()
    for _, state in pairs(request_states) do
        if state.pending ~= nil or state.completed_signature ~= nil then
            return true
        end
    end
    return false
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
    reconcile_text_change_events(context)
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
    reconcile_text_change_events(context)
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
    else
        state.completed_signature = nil
        state.completed_changedtick = nil
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
    else
        state.completed_signature = nil
        state.completed_changedtick = nil
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
            reconcile_text_change_events(context)
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
    if not text_change_attached then
        reconcile_text_change_events(context)
    end

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
reconcile_text_change_events = function(context)
    local needed = search_state_active()
    if needed == text_change_attached then
        return
    end
    if not needed then
        pcall(vim.api.nvim_clear_autocmds, { group = text_change_group })
        text_change_attached = false
        return
    end
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = text_change_group,
        callback = function(args)
            request_refresh(context, args.buf, vim.fn.getreg("/"), "edit")
        end,
        desc = "Refresh search marks after edits",
    })
    text_change_attached = true
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
    text_change_group = context.create_augroup("text_change")
    text_change_attached = false
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
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(args)
            worker.detach_buffer(args.buf)
            request_states[args.buf] = nil
            if commandline ~= nil and commandline.bufnr == args.buf then
                commandline = nil
            end
            reconcile_text_change_events(context)
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

---@param opts ScrollbarSearchSyncBudget
function M._set_sync_budget_for_test(opts)
    if type(package.loaded["scrollbar.test.search_worker"]) ~= "table" then
        return
    end
    sync_budget = {
        total_ms = SYNC_BUDGET_MS,
        per_call_ms = SYNC_PER_CALL_TIMEOUT_MS,
        stopline = SYNC_STOPLINE_CAP,
    }
    for key, value in pairs(opts or {}) do
        sync_budget[key] = value
    end
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
    text_change_group = nil
    text_change_attached = false
end

return M
