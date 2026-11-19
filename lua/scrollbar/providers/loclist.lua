local list_marks = require("scrollbar.providers.list_marks")

local OWN_TYPE = "Loclist"

--- The state of one source window at its last update. Each window has its own
--- location list, so the marks belong to the window.
---@class ScrollbarLoclistWindow
---@field id integer The id of the current list of the window
---@field changedtick integer The changedtick of that list
---@field bufnr integer The buffer of the window
---@field line_count integer The line count of that buffer

local state = {
    ---@type ScrollbarProviderContext?
    context = nil,
    ---@type table<integer, ScrollbarLoclistWindow>
    windows = {},
    -- The line counts that started the pending timer.
    ---@type string?
    pending = nil,
    ---@type ScrollbarListTimer?
    timer = nil,
}

---@param context? ScrollbarProviderContext
local function reset(context)
    if state.timer ~= nil then
        state.timer.close()
    end
    state.context = context
    state.windows = {}
    state.pending = nil
    state.timer = nil
end

---@param winid integer
---@param list table The result of getloclist() with `id` and `changedtick`
---@return ScrollbarLoclistWindow
local function signature(winid, list)
    local bufnr = vim.api.nvim_win_get_buf(winid)
    return {
        id = list.id,
        changedtick = list.changedtick,
        bufnr = bufnr,
        line_count = vim.api.nvim_buf_line_count(bufnr),
    }
end

--- The signature of a window without its entries.
---@param winid integer
---@return ScrollbarLoclistWindow
local function current_signature(winid)
    return signature(winid, vim.fn.getloclist(winid, { id = 0, changedtick = 0 }))
end

---@param previous? ScrollbarLoclistWindow
---@param current ScrollbarLoclistWindow
---@return boolean
local function list_changed(previous, current)
    return previous == nil
        or previous.id ~= current.id
        or previous.changedtick ~= current.changedtick
        or previous.bufnr ~= current.bufnr
end

--- Publish the entries of the list of a window that point at its buffer.
---@param context ScrollbarProviderContext
---@param winid integer
local function update(context, winid)
    if not vim.api.nvim_win_is_valid(winid) then
        state.windows[winid] = nil
        return
    end
    local list = vim.fn.getloclist(winid, { id = 0, changedtick = 0, items = 0 })
    local current = signature(winid, list)
    state.windows[winid] = current
    local marks = list_marks.by_buffer(
        list.items or {},
        list_marks.types(context.config.providers.loclist),
        OWN_TYPE,
        current.bufnr
    )[current.bufnr]
    -- set_window_marks clears the marks of a window that is not a source
    -- window.
    if marks == nil or not context.set_window_marks(winid, marks) then
        context.clear_window_marks(winid)
    end
end

--- Update one window when its list, its buffer, or its line count changed.
---@param context ScrollbarProviderContext
---@param winid integer
local function update_if_changed(context, winid)
    if not vim.api.nvim_win_is_valid(winid) then
        state.windows[winid] = nil
        return
    end
    local previous = state.windows[winid]
    local current = current_signature(winid)
    if list_changed(previous, current) or previous.line_count ~= current.line_count then
        update(context, winid)
    end
end

--- Update each source window whose list or buffer changed, and clear the
--- windows that are no longer source windows. A window whose only change is
--- its line count updates when the line counts stay the same for the delay,
--- or at once with `moves`.
---@param context ScrollbarProviderContext
---@param moves boolean
local function check(context, moves)
    local seen = {}
    local moved
    for _, winid in ipairs(context.source_windows()) do
        if vim.api.nvim_win_is_valid(winid) then
            seen[winid] = true
            local previous = state.windows[winid]
            local current = current_signature(winid)
            if list_changed(previous, current) then
                update(context, winid)
            elseif previous.line_count ~= current.line_count then
                if moves then
                    update(context, winid)
                else
                    moved = (moved and moved .. "," or "") .. winid .. ":" .. current.line_count
                end
            end
        end
    end
    for winid in pairs(state.windows) do
        if not seen[winid] then
            state.windows[winid] = nil
            if vim.api.nvim_win_is_valid(winid) then
                context.clear_window_marks(winid)
            end
        end
    end

    if moved == state.pending then
        return
    end
    state.pending = moved
    local timer = assert(state.timer, "loclist timer is missing")
    if moved == nil then
        timer.stop()
    else
        timer.restart()
    end
end

---@type ScrollbarProvider
return {
    name = "loclist",
    targets = { scrollbar = true, minimap = true },
    refresh_owner = { window = "provider" },
    setup = function(context)
        reset(context)
        state.timer = list_marks.timer(list_marks.LINE_MOVE_DELAY_MS, function()
            if state.context == context then
                check(context, true)
            end
        end)
        local group = context.create_augroup("events")
        -- setloclist(), `:lolder`, and `:lnewer` fire no event, so SafeState
        -- compares the list and the buffer of each source window. The check
        -- costs one getloclist() call without the entries for each source
        -- window.
        vim.api.nvim_create_autocmd({ "QuickFixCmdPost", "SafeState" }, {
            group = group,
            callback = function()
                check(context, false)
            end,
            desc = "Update scrollbar location list marks",
        })
        vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
            group = group,
            callback = function()
                update_if_changed(context, vim.api.nvim_get_current_win())
            end,
            desc = "Update scrollbar location list marks",
        })
        vim.api.nvim_create_autocmd("WinClosed", {
            group = group,
            callback = function(args)
                local winid = tonumber(args.match)
                if winid ~= nil then
                    state.windows[winid] = nil
                end
            end,
            desc = "Forget the scrollbar location list state of a window",
        })
    end,
    refresh_window = function(winid, context)
        -- A manual refresh reads the list at once, so it also catches an edit
        -- that keeps the line count, such as `:move`.
        update(context, winid)
        return nil
    end,
    dispose = function(context)
        context.clear_window_marks()
        reset(nil)
    end,
}
