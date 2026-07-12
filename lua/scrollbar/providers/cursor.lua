---@param bufnr integer
---@param context ScrollbarProviderContext
---@return boolean
local function is_buffer_eligible(bufnr, context)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return false
    end
    if vim.tbl_contains(context.config.excluded_buftypes, vim.bo[bufnr].buftype) then
        return false
    end
    if vim.tbl_contains(context.config.excluded_filetypes, vim.bo[bufnr].filetype) then
        return false
    end
    if context.config.max_lines and vim.api.nvim_buf_line_count(bufnr) > context.config.max_lines then
        return false
    end
    return true
end

---@param winid integer
---@param context ScrollbarProviderContext
---@return ScrollbarMark[]?
local function collect(winid, context)
    if not vim.api.nvim_win_is_valid(winid) then
        return nil
    end

    local bufnr = vim.api.nvim_win_get_buf(winid)
    if not is_buffer_eligible(bufnr, context) then
        return nil
    end

    local is_source = false
    for _, source_win in ipairs(context.source_windows(bufnr)) do
        if source_win == winid then
            is_source = true
            break
        end
    end
    if not is_source then
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
