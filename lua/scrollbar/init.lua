--[[
-- TODO:
-- - Improve performance by deferring + debouncing
-- - Investigate how to use existing highlights from diagnostics
-- - Store mark level instead of text
-- - Git(signs) integration
]]

local config = require("scrollbar.config")

local M = {}

local NAME_PREFIX = "Scrollbar"
local NAME_SUFFIX = "Handle"

local NAMESPACE = vim.api.nvim_create_namespace(NAME_PREFIX)

local BUF_VAR_KEY = "scrollbar_marks"

local function get_highlight_name(mark_type, handle)
    return string.format("%s%s%s", NAME_PREFIX, mark_type, handle and NAME_SUFFIX or "")
end

M.get_scrollbar_marks = function(bufnr)
    local ok, scrollbar_marks = pcall(function()
        return vim.api.nvim_buf_get_var(bufnr, BUF_VAR_KEY)
    end)

    if not ok then
        scrollbar_marks = {}
    end

    return scrollbar_marks
end

M.set_scrollbar_marks = function(bufnr, scrollbar_marks)
    vim.api.nvim_buf_set_var(bufnr, BUF_VAR_KEY, scrollbar_marks)
end

M.render = function()
    vim.api.nvim_buf_clear_namespace(0, NAMESPACE, 0, -1)

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

    local scrollbar_marks = M.get_scrollbar_marks(0)

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
                    { handle_mark.text, get_highlight_name(handle_mark.type, show_handle) },
                }
            else
                handle_opts.virt_text = {
                    { config.handle.text, get_highlight_name("", show_handle) },
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
                    virt_text = { { mark.text, get_highlight_name(mark.type, false) } },
                }
                vim.api.nvim_buf_set_extmark(0, NAMESPACE, mark_line, -1, mark_opts)
            end
        end
    end
end

local diagnostics_mark_type_map = {}

if vim.diagnostic then
    diagnostics_mark_type_map = {
        [vim.diagnostic.severity.ERROR] = "Error",
        [vim.diagnostic.severity.WARN] = "Warn",
        [vim.diagnostic.severity.INFO] = "Info",
        [vim.diagnostic.severity.HINT] = "Hint",
    }
else
    diagnostics_mark_type_map = {
        [1] = "Error",
        [2] = "Warn",
        [3] = "Info",
        [4] = "Hint",
    }
end

M.diagnostics_handler = function(bufnr, get_diagnostics, diagnostic_mapper)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

    if not vim.tbl_contains(config.excluded_filetypes, filetype) then
        local diagnostics_scrollbar_marks = {}

        local diagnostics = get_diagnostics()

        for _, diagnostic in pairs(diagnostics) do
            table.insert(diagnostics_scrollbar_marks, diagnostic_mapper(diagnostic))
        end

        local scrollbar_marks = M.get_scrollbar_marks(bufnr)
        scrollbar_marks.diagnostics = diagnostics_scrollbar_marks
        M.set_scrollbar_marks(bufnr, scrollbar_marks)

        if bufnr == vim.api.nvim_get_current_buf() then
            M.render()
        end
    end
end

M.lsp_diagnostics_handler = function(_, result, _, _)
    local bufnr = vim.uri_to_bufnr(result.uri)

    local function get_diagnostics()
        return result.diagnostics
    end

    local function diagnostic_mapper(diagnostic)
        local mark_type = diagnostics_mark_type_map[diagnostic.severity]
        return {
            line = diagnostic.range.start.line,
            text = config.marks[mark_type].text[1],
            type = mark_type,
        }
    end

    M.diagnostics_handler(bufnr, get_diagnostics, diagnostic_mapper)
end

M.diagnostic_handler = {
    show = function(_, bufnr, _, _)
        local function get_diagnostics()
            return vim.diagnostic.get(bufnr)
        end

        local function diagnostic_mapper(diagnostic)
            local mark_type = diagnostics_mark_type_map[diagnostic.severity]
            return {
                line = diagnostic.lnum,
                text = config.marks[mark_type].text[1],
                type = mark_type,
            }
        end

        M.diagnostics_handler(bufnr, get_diagnostics, diagnostic_mapper)
    end,
    hide = function(_, bufnr, _, _)
        local scrollbar_marks = M.get_scrollbar_marks(bufnr)
        scrollbar_marks.diagnostics = nil
        M.set_scrollbar_marks(bufnr, scrollbar_marks)
        M.render()
    end,
}

M.search_handler = {
    show = function(plist)
        if config.handlers.search then
            local search_scrollbar_marks = {}

            for _, result in pairs(plist) do
                table.insert(search_scrollbar_marks, {
                    line = result[1] - 1,
                    text = "-",
                    type = "Search",
                })
            end

            local bufnr = vim.api.nvim_get_current_buf()
            local scrollbar_marks = M.get_scrollbar_marks(bufnr)
            scrollbar_marks.search = search_scrollbar_marks
            M.set_scrollbar_marks(bufnr, scrollbar_marks)
            M.render()
        end
    end,
    hide = function()
        if not vim.v.event.abort then
            local cmdl = vim.trim(vim.fn.getcmdline())
            if #cmdl > 2 then
                for _, cl in ipairs(vim.split(cmdl, "|")) do
                    if ("nohlsearch"):match(vim.trim(cl)) then
                        local bufnr = vim.api.nvim_get_current_buf()
                        local scrollbar_marks = M.get_scrollbar_marks(bufnr)
                        scrollbar_marks.search = nil
                        M.set_scrollbar_marks(bufnr, scrollbar_marks)
                        M.render()
                        break
                    end
                end
            end
        end
    end,
}

M.setup_highlights = function()
    vim.cmd(string.format("highlight %s guifg=%s guibg=%s", get_highlight_name("", true), "none", config.handle.color))
    for mark_type, properties in pairs(config.marks) do
        vim.cmd(
            string.format(
                "highlight %s guifg=%s guibg=%s",
                get_highlight_name(mark_type, false),
                properties.color,
                "NONE"
            )
        )
        vim.cmd(
            string.format(
                "highlight %s guifg=%s guibg=%s",
                get_highlight_name(mark_type, true),
                properties.color,
                config.handle.color
            )
        )
    end
end

M.setup = function(overrides)
    config = vim.tbl_deep_extend("force", config, overrides or {})

    M.setup_highlights()

    vim.cmd([[
        augroup scrollbar_setup_highlights
            autocmd!
            autocmd ColorScheme * lua require('scrollbar').setup_highlights()
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
        if vim.diagnostic then
            vim.diagnostic.handlers["petertriho/scrollbar"] = M.diagnostic_handler
        else
            vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, conf)
                vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, conf)
                M.lsp_diagnostic_handler(err, result, ctx, conf)
            end
        end
    end
end

return M
