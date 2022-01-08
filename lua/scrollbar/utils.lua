local const = require("scrollbar.const")

local M = {}

M.get_highlight_name = function(mark_type, handle)
    return string.format("%s%s%s", const.NAME_PREFIX, mark_type, handle and const.NAME_SUFFIX or "")
end

M.get_scrollbar_marks = function(bufnr)
    local ok, scrollbar_marks = pcall(function()
        return vim.api.nvim_buf_get_var(bufnr, const.BUF_VAR_KEY)
    end)

    if not ok then
        scrollbar_marks = {}
    end

    return scrollbar_marks
end

M.set_scrollbar_marks = function(bufnr, scrollbar_marks)
    vim.api.nvim_buf_set_var(bufnr, const.BUF_VAR_KEY, scrollbar_marks)
end

M.set_highlights = function()
    local config = require("scrollbar.config").get()

    vim.cmd(
        string.format("highlight %s guifg=%s guibg=%s", M.get_highlight_name("", true), "none", config.handle.color)
    )
    for mark_type, properties in pairs(config.marks) do
        vim.cmd(
            string.format(
                "highlight %s guifg=%s guibg=%s",
                M.get_highlight_name(mark_type, false),
                properties.color,
                "NONE"
            )
        )
        vim.cmd(
            string.format(
                "highlight %s guifg=%s guibg=%s",
                M.get_highlight_name(mark_type, true),
                properties.color,
                config.handle.color
            )
        )
    end
end

return M
