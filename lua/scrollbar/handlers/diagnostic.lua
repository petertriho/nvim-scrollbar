local config = require("scrollbar.config").get()
local utils = require("scrollbar.utils")
local render = require("scrollbar").render

local M = {}

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

M.generic_handler = function(bufnr, get_diagnostics, diagnostic_mapper)
    local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")

    if not vim.tbl_contains(config.excluded_filetypes, filetype) then
        local diagnostics_scrollbar_marks = {}

        local diagnostics = get_diagnostics()

        for _, diagnostic in pairs(diagnostics) do
            table.insert(diagnostics_scrollbar_marks, diagnostic_mapper(diagnostic))
        end

        local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
        scrollbar_marks.diagnostics = diagnostics_scrollbar_marks
        utils.set_scrollbar_marks(bufnr, scrollbar_marks)

        if bufnr == vim.api.nvim_get_current_buf() then
            render()
        end
    end
end

M.lsp_handler = function(_, result, _, _)
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

    M.generic_handler(bufnr, get_diagnostics, diagnostic_mapper)
end

M.handler = {
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

        M.generic_handler(bufnr, get_diagnostics, diagnostic_mapper)
    end,
    hide = function(_, bufnr, _, _)
        local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
        scrollbar_marks.diagnostics = nil
        utils.set_scrollbar_marks(bufnr, scrollbar_marks)
        render()
    end,
}

return M
