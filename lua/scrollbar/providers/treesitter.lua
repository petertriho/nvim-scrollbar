local PRIORITY = 100

local M = {
    name = "treesitter",
    targets = { scrollbar = false, minimap = true },
    execution = "worker",
    priority = PRIORITY,
}

---@param filetype string?
---@return string?
M.language_for = function(filetype)
    if filetype == nil or filetype == "" then
        return nil
    end
    local ok_lang, lang = pcall(vim.treesitter.language.get_lang, filetype)
    if not ok_lang or lang == nil then
        return nil
    end
    if not pcall(vim.treesitter.language.add, lang) then
        return nil
    end
    return lang
end

---@param bufnr integer
---@param lang string?
---@return ScrollbarMinimapSourceSpan[]
M.collect = function(bufnr, lang)
    if lang == nil or lang == "" then
        return {}
    end
    if not pcall(vim.treesitter.language.add, lang) then
        return {}
    end
    local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
    if not ok_parser or parser == nil or not pcall(parser.parse, parser) then
        return {}
    end
    local ok_trees, trees = pcall(parser.trees, parser)
    local tree = ok_trees and trees[1] or nil
    if tree == nil then
        return {}
    end
    local ok_root, root = pcall(tree.root, tree)
    if not ok_root or root == nil then
        return {}
    end
    local ok_query, query = pcall(vim.treesitter.query.get, lang, "highlights")
    if not ok_query or query == nil then
        return {}
    end

    local spans = {}
    local ok_iter = pcall(function()
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        ---@diagnostic disable-next-line: redundant-parameter
        for id, node in query:iter_captures(root, bufnr, 0, line_count) do
            local capture_name = query.captures[id]
            if capture_name ~= nil then
                local start_row, start_col, end_row, end_col = node:range()
                if start_row == end_row and start_col < end_col then
                    spans[#spans + 1] = {
                        line = start_row,
                        start_col = start_col,
                        end_col = end_col,
                        highlight = "@" .. capture_name,
                        priority = PRIORITY,
                    }
                end
            end
        end
    end)
    return ok_iter and spans or {}
end

---@type ScrollbarProvider
return M
