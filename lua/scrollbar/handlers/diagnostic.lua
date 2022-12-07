local utils = require("scrollbar.utils")
local render = require("scrollbar").throttled_render

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

        if bufnr == 0 or bufnr == vim.api.nvim_get_current_buf() then
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
        if scrollbar_marks.diagnostic then
            scrollbar_marks.diagnostics = nil
            utils.set_scrollbar_marks(bufnr, scrollbar_marks)
            render()
        end
    end,
}

-------------------
-- coc diagnostics
-------------------
local severity_map = { Error = 1, Warning = 2, Information = 3, Hint = 4 }
local uri_diagnostics = {}
local function coc_diagnostic_handler(error, diagnosticList)
    if error ~= vim.NIL then
        return
    end
    if type(diagnosticList) ~= "table" then
        diagnosticList = {}
    end

    for uri in pairs(uri_diagnostics) do
        uri_diagnostics[uri] = {}
    end

    for _, diagnostic in ipairs(diagnosticList) do
        local uri = diagnostic.location.uri
        local diagnostics = uri_diagnostics[uri] or {}
        table.insert(diagnostics, {
            range = diagnostic.location.range,
            severity = severity_map[diagnostic.severity],
        })
        uri_diagnostics[uri] = diagnostics
    end

    for uri, diagnostics in pairs(uri_diagnostics) do
        M.lsp_handler(nil, { uri = uri, diagnostics = diagnostics })
        if vim.tbl_count(diagnostics) == 0 then
            uri_diagnostics[uri] = nil
        end
    end
end

function M.update_coc_diagnostics()
    vim.fn.CocActionAsync("diagnosticList", coc_diagnostic_handler)
end

M.setup = function()
    local config = require("scrollbar.config").get()
    config.handlers.diagnostic = true

    if vim.diagnostic then
        vim.diagnostic.handlers["petertriho/scrollbar"] = M.handler
        vim.cmd([[autocmd DiagnosticChanged * lua require("scrollbar.handlers.diagnostic").handler.show(_, 0)]])
    else
        vim.lsp.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, conf)
            vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, conf)
            M.lsp_handler(err, result, ctx, conf)
        end
    end

    vim.cmd([[autocmd User CocDiagnosticChange lua require("scrollbar.handlers.diagnostic").update_coc_diagnostics()]])
end

return M
