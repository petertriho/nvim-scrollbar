local const = require("scrollbar.const")

local M = {}

M.throttle = function(fn, time_ms)
    local timer = vim.loop.new_timer()
    local running = false

    return function(...)
        if not running then
            timer:start(time_ms, 0, function()
                running = false
            end)
            running = true
            pcall(vim.schedule_wrap(fn), select(1, ...))
        end
    end
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

M.get_highlight_name = function(mark_type, handle)
    return string.format("%s%s%s", const.NAME_PREFIX, mark_type, handle and const.NAME_SUFFIX or "")
end

M.to_hex_color = function(rgb_color)
    return string.format("#%06x", rgb_color)
end

M.highlight_to_hex_color = function(hl, property, fallback_hl, fallback_hex)
    local highlight_ok, highlight = pcall(vim.api.nvim_get_hl_by_name, hl, true)

    if not highlight_ok then
        highlight_ok, highlight = pcall(vim.api.nvim_get_hl_by_name, fallback_hl, true)
    end

    local hex_color = fallback_hex

    if highlight_ok then
        local color = highlight[property]

        if color then
            local hex_ok
            hex_ok, hex_color = pcall(M.to_hex_color, color)

            if not hex_ok then
                hex_color = fallback_hex
            end
        end
    end

    return hex_color
end

M.set_highlights = function()
    local config = require("scrollbar.config").get()

    local handle_blend = config.handle.blend or 30
    local handle_color = config.handle.color
        or M.highlight_to_hex_color(config.handle.highlight, "background", "CursorColumn", "#ffffff")
    local handle_color_nr = config.handle.color_nr
    local handle_gui = config.handle.gui or "NONE"
    local handle_cterm = config.handle.cterm or "NONE"

    -- ScrollbarHandle
    vim.cmd(
        string.format(
            "highlight %s ctermfg=%s ctermbg=%s guifg=%s guibg=%s blend=%s",
            M.get_highlight_name("", true),
            "NONE",
            handle_color_nr or 15,
            "NONE",
            handle_color or "white",
            handle_blend
        )
    )

    for mark_type, properties in pairs(config.marks) do
        local type_color = properties.color
            or M.highlight_to_hex_color(properties.highlight, "foreground", "Normal", "#000000")
        local type_color_nr = properties.color_nr
        local type_gui = properties.gui or "NONE"
        local type_cterm = properties.cterm or "NONE"

        -- Scrollbar<MarkType>
        vim.cmd(
            string.format(
                "highlight %s cterm=%s ctermfg=%s ctermbg=%s gui=%s guifg=%s guibg=%s",
                M.get_highlight_name(mark_type, false),
                type_cterm,
                type_color_nr or 0,
                "NONE",
                type_gui,
                type_color or "black",
                "NONE"
            )
        )

        -- Scrollbar<MarkType>Handle
        vim.cmd(
            string.format(
                "highlight %s cterm=%s ctermfg=%s ctermbg=%s gui=%s guifg=%s guibg=%s blend=%s",
                M.get_highlight_name(mark_type, true),
                type_cterm,
                type_color_nr or 0,
                handle_color_nr or 15,
                type_gui,
                type_color,
                handle_color,
                handle_blend
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
    local folds = {}

    if M.has_folds() then
        local total_lines = vim.api.nvim_buf_line_count(0)

        local cur_line = 0
        while cur_line < total_lines do
            cur_line = cur_line + 1

            local fold_closed_end = vim.fn.foldclosedend(cur_line)

            if fold_closed_end ~= -1 then
                table.insert(folds, { cur_line, fold_closed_end })

                cur_line = fold_closed_end
            end
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

M.has_folds = function()
    return vim.wo.foldenable
end

return M
