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

M.to_hex_color = function(rgb_color)
    return string.format("#%06x", rgb_color)
end

M.set_highlights = function()
    local config = require("scrollbar.config").get()

    local handle_color = config.handle.color
    local handle_cterm = config.handle.cterm

    -- ScrollbarHandle
    if not handle_color then
        handle_color = M.to_hex_color(
            vim.api.nvim_get_hl_by_name(config.handle.highlight or "CursorColumn", true).background
        )
    end

    vim.cmd(
        string.format(
            "highlight default %s ctermfg=%s ctermbg=%s guifg=%s guibg=%s",
            M.get_highlight_name("", true),
            "NONE",
            handle_cterm or 15,
            "NONE",
            handle_color or "white"
        )
    )

    for mark_type, properties in pairs(config.marks) do
        local type_color = properties.color
        local type_cterm = properties.cterm

        if not type_color then
            type_color = M.to_hex_color(vim.api.nvim_get_hl_by_name(properties.highlight or "Special", true).foreground)
        end

        -- Scrollbar<MarkType>
        vim.cmd(
            string.format(
                "highlight default %s ctermfg=%s ctermbg=%s guifg=%s guibg=%s",
                M.get_highlight_name(mark_type, false),
                type_cterm or 0,
                "NONE",
                type_color or "black",
                "NONE"
            )
        )

        -- Scrollbar<MarkType>Handle
        vim.cmd(
            string.format(
                "highlight default %s ctermfg=%s ctermbg=%s guifg=%s guibg=%s",
                M.get_highlight_name(mark_type, true),
                type_cterm or 0,
                handle_cterm or "white",
                type_color,
                handle_color
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

M.get_folds = function()
    local total_lines = vim.api.nvim_buf_line_count(0)

    local folds = {}
    local cur_line = 0
    while cur_line < total_lines do
        cur_line = cur_line + 1

        local fold_closed_end = vim.fn.foldclosedend(cur_line)

        if fold_closed_end ~= -1 then
            table.insert(folds, { cur_line, fold_closed_end })

            cur_line = fold_closed_end
        end
    end

    return folds
end

M.get_surrounding_fold = function(folds, line_nr)
    local sur_fold = nil

    if folds == nil then
        return nil
    end

    for _, fold in pairs(folds) do
        if fold[1] < line_nr and fold[2] >= line_nr then
            return fold
        end
    end

    return sur_fold
end

M.find_affected_folds = function(folds, end_nr)
    local aff_folds = {}

    local cur_line = vim.fn.line("w0")
    while cur_line < end_nr do
        cur_line = cur_line + 1

        local sur_fold = M.get_surrounding_fold(folds, cur_line)

        if sur_fold ~= nil then
            table.insert(aff_folds, sur_fold)

            cur_line = sur_fold[2]
        end
    end

    return aff_folds
end

M.fix_invisible_lines = function(folds, rel_line_nr, offset)
    local abs_line_nr = rel_line_nr + offset

    for _, sur_fold in pairs(folds) do
        -- abs_line_nr in fold
        if sur_fold[1] < abs_line_nr and sur_fold[1] >= vim.fn.line("w0") then
            rel_line_nr = rel_line_nr + (sur_fold[2] - sur_fold[1])
            abs_line_nr = abs_line_nr + (sur_fold[2] - sur_fold[1])
        end
    end

    return rel_line_nr
end

M.get_scroll_offset_diff = function(folds, abs_line_nr)
    local aff_folds = M.find_affected_folds(folds, abs_line_nr)

    local diff = 0
    for _, sur_fold in pairs(aff_folds) do
        -- abs_line_nr in fold
        if sur_fold[1] < abs_line_nr then
            diff = diff + (sur_fold[2] - sur_fold[1])
        end
    end

    return diff
end

return M
