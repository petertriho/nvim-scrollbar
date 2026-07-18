---@param winid integer
---@param context ScrollbarProviderContext
---@return ScrollbarMark[]?
local function collect(winid, context)
    if not context.is_source_window(winid) then
        return nil
    end
    return { { line = vim.api.nvim_win_get_cursor(winid)[1] - 1, type = "Cursor" } }
end

---@param winid integer
---@param context ScrollbarProviderContext
local function update(winid, context)
    local marks = collect(winid, context)
    if marks == nil then
        context.clear_window_marks(winid)
    else
        context.set_window_marks(winid, marks)
    end
end

---@type ScrollbarProvider
return {
    name = "cursor",
    refresh_owner = { window = "provider" },
    setup = function(context)
        local group = context.create_augroup("events")
        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufWinEnter", "WinEnter" }, {
            group = group,
            callback = function(args)
                local winid = vim.api.nvim_get_current_win()
                if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == args.buf then
                    update(winid, context)
                end
            end,
            desc = "Update scrollbar cursor marks",
        })
    end,
    refresh_window = function(winid, context)
        local marks = collect(winid, context)
        if marks == nil then
            context.clear_window_marks(winid)
        end
        return marks
    end,
    dispose = function(context)
        context.clear_window_marks()
    end,
}
