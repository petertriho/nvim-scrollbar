local const = require("scrollbar.const")

local M = {}

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

M.get_highlight_name = function(mark_type, handle)
    return string.format("%s%s%s", const.NAME_PREFIX, mark_type, handle and const.NAME_SUFFIX or "")
end

M.set_highlights = function()
    local config = require("scrollbar.config").get()

    vim.cmd(
        string.format(
            "highlight default %s guifg=%s guibg=%s",
            M.get_highlight_name("", true),
            "NONE",
            config.handle.color
        )
    )
    for mark_type, properties in pairs(config.marks) do
        vim.cmd(
            string.format(
                "highlight default %s guifg=%s guibg=%s",
                M.get_highlight_name(mark_type, false),
                properties.color,
                "NONE"
            )
        )
        vim.cmd(
            string.format(
                "highlight default %s guifg=%s guibg=%s",
                M.get_highlight_name(mark_type, true),
                properties.color,
                config.handle.color
            )
        )
    end
end

M.set_next_level_text = function(mark)
    local config = require("scrollbar.config").get()

    local next_level = (mark.level or 0) + 1
    if config.marks[mark.type].text[next_level] then
        mark.text = config.marks[mark.type].text[next_level]
    end
end

M.toggle = function()
    local config = require("scrollbar.config").get()
    config.show = not config.show
    require("scrollbar").render()
end

M.show = function()
    local config = require("scrollbar.config").get()
    config.show = true
    require("scrollbar").render()
end

M.hide = function()
    local config = require("scrollbar.config").get()
    config.show = false
    require("scrollbar").render()
end

M.set_commands = function()
    vim.cmd([[
        command! ScrollbarToggle lua require("scrollbar.utils").toggle()
        command! ScrollbarShow lua require("scrollbar.utils").show()
        command! ScrollbarHide lua require("scrollbar.utils").hide()
    ]])
end

return M
