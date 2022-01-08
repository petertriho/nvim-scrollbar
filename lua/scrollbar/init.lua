local const = require("scrollbar.const")
local utils = require("scrollbar.utils")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace(const.NAME_PREFIX)

M.render = function()
    vim.api.nvim_buf_clear_namespace(0, NAMESPACE, 0, -1)

    local config = require("scrollbar.config").get()

    if not config.show then
        return
    end

    if vim.tbl_contains(config.excluded_filetypes, vim.bo.filetype) then
        return
    end

    local total_lines = vim.api.nvim_buf_line_count(0)
    local visible_lines = vim.api.nvim_win_get_height(0)
    local first_visible_line = vim.fn.line("w0")
    local last_visible_line = vim.fn.line("w$")

    local show_handle = true

    if visible_lines >= total_lines then
        visible_lines = total_lines

        if config.handle.hide_if_all_visible then
            show_handle = false
        end
    end

    local ratio = visible_lines / total_lines

    local relative_first_line = math.floor(first_visible_line * ratio) - math.floor(1 * ratio)
    local relative_last_line = math.floor(last_visible_line * ratio)

    local scrollbar_marks = utils.get_scrollbar_marks(0)

    local sorted_scrollbar_marks = {}

    for _, namespace_marks in pairs(scrollbar_marks) do
        for _, mark in ipairs(namespace_marks) do
            table.insert(sorted_scrollbar_marks, mark)
        end
    end

    table.sort(sorted_scrollbar_marks, function(a, b)
        if a.line == b.line then
            return config.marks[a.type].priority < config.marks[b.type].priority
        end
        return a.line < b.line
    end)

    local handle_marks = {}
    local other_marks = {}

    for _, mark in pairs(sorted_scrollbar_marks) do
        local relative_mark_line = math.floor(mark.line * ratio)

        if mark.line <= total_lines then
            if
                handle_marks[#handle_marks]
                and math.floor(handle_marks[#handle_marks].line * ratio) == relative_mark_line
            then
                handle_marks[#handle_marks].text = config.marks[mark.type].text[2]
            elseif
                other_marks[#other_marks]
                and math.floor(other_marks[#other_marks].line * ratio) == relative_mark_line
            then
                other_marks[#other_marks].text = config.marks[mark.type].text[2]
            else
                if relative_mark_line >= relative_first_line and relative_mark_line <= relative_last_line then
                    table.insert(handle_marks, mark)
                else
                    table.insert(other_marks, mark)
                end
            end
        end
    end

    local scroll_offset = visible_lines - (last_visible_line - first_visible_line)

    for i = relative_first_line, relative_last_line, 1 do
        local mark_line = first_visible_line + i - scroll_offset

        if mark_line >= 0 then
            local handle_opts = {
                virt_text_pos = "right_align",
            }

            local handle_mark = nil

            for index, mark in ipairs(handle_marks) do
                local relative_mark_line = math.floor(mark.line * ratio)
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
                handle_opts.virt_text = {
                    { config.handle.text, utils.get_highlight_name("", show_handle) },
                }
            end

            vim.api.nvim_buf_set_extmark(0, NAMESPACE, mark_line, -1, handle_opts)
        end
    end

    for _, mark in pairs(other_marks) do
        if mark ~= nil then
            local mark_line = first_visible_line + math.floor(tonumber(mark.line) * ratio) - scroll_offset

            if mark_line >= 0 then
                local mark_opts = {
                    virt_text_pos = "right_align",
                    virt_text = { { mark.text, utils.get_highlight_name(mark.type, false) } },
                }
                vim.api.nvim_buf_set_extmark(0, NAMESPACE, mark_line, -1, mark_opts)
            end
        end
    end
end

M.setup = function(overrides)
    local config = require("scrollbar.config").set(overrides)

    utils.set_highlights()
    utils.set_commands()

    vim.cmd([[
        augroup scrollbar_setup_highlights
            autocmd!
            autocmd ColorScheme * lua require('scrollbar.utils').set_highlights()
        augroup END
    ]])

    if config.autocmd and config.autocmd.render and #config.autocmd.render > 0 then
        vim.cmd(string.format(
            [[
        augroup scrollbar
            autocmd!
            autocmd %s * lua require('scrollbar').render()
        augroup END
        ]],
            table.concat(config.autocmd.render, ",")
        ))
    end

    if config.handlers.diagnostic then
        local diagnostic = require("scrollbar.handlers.diagnostic")

        if vim.diagnostic then
            vim.diagnostic.handlers["petertriho/scrollbar"] = diagnostic.handler
        else
            vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, conf)
                vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, conf)
                diagnostic.lsp_handler(err, result, ctx, conf)
            end
        end
    end
end

return M
