local const = require("scrollbar.const")
local utils = require("scrollbar.utils")
local handlers = require("scrollbar.handlers")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace(const.NAME_PREFIX)

M.clear = function()
    vim.api.nvim_buf_clear_namespace(0, NAMESPACE, 0, -1)
end

M.render = function()
    M.clear()

    local config = require("scrollbar.config").get()

    if not config.show then
        return
    end

    if vim.tbl_contains(config.excluded_buftypes, vim.bo.buftype) then
        return
    end

    if vim.tbl_contains(config.excluded_filetypes, vim.bo.filetype) then
        return
    end

    local total_lines = vim.api.nvim_buf_line_count(0)

    if config.max_lines and total_lines > config.max_lines then
        return
    end

    local visible_lines = vim.api.nvim_win_get_height(0)
    local first_visible_line = vim.fn.line("w0")
    local last_visible_line = vim.fn.line("w$")
    local folds = {}

    if
        (tonumber(config.folds) == nil and config.folds)
        or (tonumber(config.folds) ~= nil and config.folds >= total_lines)
    then
        folds = utils.get_folds()
    end

    local show_handle = config.handlers.handle

    if visible_lines >= total_lines then
        visible_lines = total_lines

        if config.handle.hide_if_all_visible then
            show_handle = false
        end

        if config.hide_if_all_visible then
            return
        end
    end

    local ratio = visible_lines / total_lines
    local height = math.floor(visible_lines * visible_lines / total_lines)

    local relative_first_line = math.floor(first_visible_line * ratio) - math.floor(1 * ratio)
    local relative_last_line = relative_first_line + height

    -- correct the folding diff
    relative_first_line = utils.fix_invisible_lines(folds, relative_first_line, first_visible_line)
    relative_last_line = utils.fix_invisible_lines(folds, relative_last_line, first_visible_line)

    local scrollbar_marks = utils.get_scrollbar_marks(0)

    local sorted_scrollbar_marks = {}

    for _, namespace_marks in pairs(scrollbar_marks) do
        for _, mark in ipairs(namespace_marks) do
            table.insert(sorted_scrollbar_marks, mark)
        end
    end

    table.sort(sorted_scrollbar_marks, function(a, b)
        local relative_line_a = math.floor(a.line * ratio)
        local relative_line_b = math.floor(b.line * ratio)
        if relative_line_a == relative_line_b then
            return config.marks[a.type].priority < config.marks[b.type].priority
        end
        return relative_line_a < relative_line_b
    end)

    local handle_marks = {}
    local other_marks = {}

    for _, mark in pairs(sorted_scrollbar_marks) do
        local relative_mark_line = math.floor(mark.line * ratio)
        relative_mark_line = utils.fix_invisible_lines(folds, relative_mark_line, first_visible_line)

        if mark.line <= total_lines then
            if
                handle_marks[#handle_marks]
                and utils.fix_invisible_lines(
                        folds,
                        math.floor(handle_marks[#handle_marks].line * ratio),
                        first_visible_line
                    )
                    == relative_mark_line
            then
                utils.set_next_level_text(handle_marks[#handle_marks])
            elseif
                other_marks[#other_marks]
                and utils.fix_invisible_lines(
                        folds,
                        math.floor(other_marks[#other_marks].line * ratio),
                        first_visible_line
                    )
                    == relative_mark_line
            then
                utils.set_next_level_text(other_marks[#other_marks])
            else
                if relative_mark_line >= relative_first_line and relative_mark_line <= relative_last_line then
                    table.insert(handle_marks, mark)
                else
                    table.insert(other_marks, mark)
                end
            end
        end
    end

    local diff_last = utils.get_scroll_offset_diff(folds, last_visible_line)
    local scroll_offset = visible_lines - (last_visible_line - first_visible_line) + diff_last

    for i = relative_first_line, relative_last_line, 1 do
        local mark_line = math.min(first_visible_line + i - scroll_offset, total_lines)

        if mark_line >= 0 then
            local handle_opts = {
                virt_text_pos = "right_align",
                hl_mode = 'blend',
            }

            local handle_mark = nil

            for index, mark in ipairs(handle_marks) do
                local relative_mark_line = math.floor(mark.line * ratio)
                relative_mark_line = utils.fix_invisible_lines(folds, relative_mark_line, first_visible_line)

                if relative_mark_line >= i - 1 and relative_mark_line <= i then
                    handle_mark = mark
                    table.remove(handle_marks, index)
                    break
                end
            end

            if handle_mark then
                handle_opts.virt_text = {
                    { handle_mark.text, utils.get_highlight_name(handle_mark.type, show_handle) },
                }
            else
                local handle_mark_text = config.handle.text

                if not show_handle then
                    handle_mark_text = ""
                end

                handle_opts.virt_text = {
                    { handle_mark_text, utils.get_highlight_name("", show_handle) },
                }
            end

            vim.api.nvim_buf_set_extmark(0, NAMESPACE, mark_line, 0, handle_opts)
        end
    end

    for _, mark in pairs(other_marks) do
        if mark ~= nil then
            local relative_mark_line = math.floor(mark.line * ratio)
            relative_mark_line = utils.fix_invisible_lines(folds, relative_mark_line, first_visible_line)

            local mark_line = first_visible_line + relative_mark_line - scroll_offset

            if mark_line >= 0 then
                local mark_opts = {
                    virt_text_pos = "right_align",
                    virt_text = { { mark.text, utils.get_highlight_name(mark.type, false) } },
                }
                vim.api.nvim_buf_set_extmark(0, NAMESPACE, mark_line, 0, mark_opts)
            end
        end
    end
end

M.throttled_render = M.render

M.on_scroll = function()
    local wins = {0}
    if vim.v.event.all ~= nil then
        wins = {}
        for win, _ in pairs(vim.v.event) do
            if win ~= 'all' then
                table.insert(wins, tonumber(win))
            end
        end
    end
    for _, win in ipairs(wins) do
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_call(win, function()
                handlers.show()
                M.render()
            end)
        end
    end
end

M.setup = function(overrides)
    local config = require("scrollbar.config").set(overrides)

    if config.throttle_ms > 0 then
        M.throttled_render = utils.throttle(M.render, config.throttle_ms)
    end

    if config.set_highlights then
        utils.set_highlights()

        vim.cmd([[
        augroup scrollbar_setup_highlights
            autocmd!
            autocmd ColorScheme * lua require('scrollbar.utils').set_highlights()
        augroup END
        ]])
    end

    utils.set_commands()

    if config.autocmd and config.autocmd.render and #config.autocmd.render > 0 then
        vim.cmd(string.format(
            [[
        augroup scrollbar_render
            autocmd!
            autocmd %s * lua require('scrollbar').on_scroll()
        augroup END
        ]],
            table.concat(config.autocmd.render, ",")
        ))
    end

    if config.handlers.cursor then
        require("scrollbar.handlers.cursor").setup()
    end

    if config.handlers.diagnostic then
        require("scrollbar.handlers.diagnostic").setup()
    end

    if config.handlers.gitsigns then
        require("scrollbar.handlers.gitsigns").setup()
    end

    if config.handlers.search then
        require("scrollbar.handlers.search").setup()
    end

    if config.handlers.ale then
        require("scrollbar.handlers.ale").setup()
    end

    if config.show_in_active_only then
        vim.cmd(string.format(
            [[
        augroup scrollbar_clear
            autocmd!
            autocmd %s * lua require('scrollbar').clear()
        augroup END
        ]],
            table.concat(config.autocmd.clear, ",")
        ))
    end
end

return M
