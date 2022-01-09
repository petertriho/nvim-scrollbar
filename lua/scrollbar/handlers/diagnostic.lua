local utils = require("scrollbar.utils")
local render = require("scrollbar").render

local M = {}

local DIAGNOSTIC_MARK_TYPE_MAP = nil

if not DIAGNOSTIC_MARK_TYPE_MAP then
    if vim.diagnostic then
        DIAGNOSTIC_MARK_TYPE_MAP = {
            [vim.diagnostic.severity.ERROR] = "Error",
            [vim.diagnostic.severity.WARN] = "Warn",
            [vim.diagnostic.severity.INFO] = "Info",
            [vim.diagnostic.severity.HINT] = "Hint",
        }
    else
        DIAGNOSTIC_MARK_TYPE_MAP = {
            [1] = "Error",
            [2] = "Warn",
            [3] = "Info",
            [4] = "Hint",
        }
    end
end

M.generic_handler = function(bufnr, get_diagnostics, diagnostic_mapper)
    local config = require("scrollbar.config").get()
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
    local config = require("scrollbar.config").get()
    local bufnr = vim.uri_to_bufnr(result.uri)

    local function get_diagnostics()
        return result.diagnostics
    end

    local function diagnostic_mapper(diagnostic)
        local mark_type = DIAGNOSTIC_MARK_TYPE_MAP[diagnostic.severity]
        return {
            line = diagnostic.range.start.line,
            text = config.marks[mark_type].text[1],
            type = mark_type,
            level = 1,
        }
    end

    M.generic_handler(bufnr, get_diagnostics, diagnostic_mapper)
end

M.handler = {
    show = function(_, bufnr, _, _)
        local config = require("scrollbar.config").get()

        local function get_diagnostics()
            return vim.diagnostic.get(bufnr)
        end

        local function diagnostic_mapper(diagnostic)
            local mark_type = DIAGNOSTIC_MARK_TYPE_MAP[diagnostic.severity]
            return {
                line = diagnostic.lnum,
                text = config.marks[mark_type].text[1],
                type = mark_type,
                level = 1,
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

M.setup = function()
    local config = require("scrollbar.config").get()
    config.handlers.diagnostic = true

    if vim.diagnostic then
        vim.diagnostic.handlers["petertriho/scrollbar"] = M.handler
    else
        vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, conf)
            vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, conf)
            M.lsp_handler(err, result, ctx, conf)
        end
    end
end

return M
