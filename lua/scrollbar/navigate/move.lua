--- The cursor move of a jump to a mark. A click on a mark of the scrollbar
--- and a jump from label mode or the glance list use the same move: the cursor
--- goes to the start of the mark line, the folds at the line open, and the line
--- goes to the center of the window. Only the keyboard jumps add a jumplist
--- entry first, so `<C-o>` returns.

local M = {}

--- Move the cursor of `source_win` to the 0-based `line` of `source_buf`. The
--- line is clamped to the buffer.
---@param source_win integer
---@param source_buf integer Buffer that `source_win` shows
---@param line integer
---@param jumplist? boolean Add a jumplist entry at the old cursor position first
---@return boolean ok
M.line = function(source_win, source_buf, line, jumplist)
    local line_count = vim.api.nvim_buf_line_count(source_buf)
    line = math.max(0, math.min(line, line_count - 1))
    return pcall(vim.api.nvim_win_call, source_win, function()
        if jumplist then
            vim.cmd("normal! m'")
        end
        vim.api.nvim_win_set_cursor(source_win, { line + 1, 0 })
        vim.cmd("normal! zv")
        vim.cmd("normal! zz")
    end)
end

return M
