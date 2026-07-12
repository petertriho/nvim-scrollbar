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

---@param bufnr integer
---@param context ScrollbarProviderContext
---@return ScrollbarMark[]?
local function collect(bufnr, context)
    if not is_buffer_eligible(bufnr, context) then
        return nil
    end

    local current_win = vim.api.nvim_get_current_win()
    local source_win
    if vim.api.nvim_win_is_valid(current_win) and vim.api.nvim_win_get_buf(current_win) == bufnr then
        source_win = current_win
    else
        for _, winid in ipairs(context.source_windows(bufnr)) do
            if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
                source_win = winid
                break
            end
        end
    end

    if source_win == nil then
        return nil
    end
    return { { line = vim.api.nvim_win_get_cursor(source_win)[1] - 1, type = "Cursor" } }
end

---@param bufnr integer
---@param context ScrollbarProviderContext
local function update(bufnr, context)
    local marks = collect(bufnr, context)
    if marks == nil then
        context.clear_marks(bufnr)
    else
        context.set_marks(bufnr, marks)
    end
end

---@type ScrollbarProvider
return {
    name = "cursor",
    setup = function(context)
        local group = context.create_augroup("events")
        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
            group = group,
            callback = function(args)
                update(args.buf, context)
            end,
            desc = "Update scrollbar cursor marks",
        })
    end,
    refresh = function(bufnr, context)
        local marks = collect(bufnr, context)
        if marks == nil then
            context.clear_marks(bufnr)
        end
        return marks
    end,
    dispose = function(context)
        context.clear_marks()
    end,
}
