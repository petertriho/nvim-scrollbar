--- Update rules of the providers that read the marks of one buffer at a time:
--- `ale`, `gitsigns`, `mini_diff`, `signify`, and `vgit`.

local M = {}

--- Set the marks of `bufnr` to the result of `collect(bufnr)`. Clear them when
--- the buffer is not eligible or when `collect` raises an error.
---@param context ScrollbarProviderContext
---@param bufnr integer
---@param collect fun(bufnr: integer): ScrollbarMark[]
M.update = function(context, bufnr, collect)
    if not context.is_buffer_eligible(bufnr) then
        context.clear_marks(bufnr)
        return
    end
    local ok, marks = pcall(collect, bufnr)
    if ok then
        context.set_marks(bufnr, marks)
    else
        context.clear_marks(bufnr)
    end
end

--- The buffers of the source windows, each one time, in ascending order.
---@param context ScrollbarProviderContext
---@return integer[]
M.source_buffers = function(context)
    local buffers = {}
    for _, winid in ipairs(context.source_windows()) do
        local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
        if ok then
            buffers[bufnr] = true
        end
    end
    local ordered = vim.tbl_keys(buffers)
    table.sort(ordered)
    return ordered
end

return M
