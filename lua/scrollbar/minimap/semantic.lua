--- Normalizes the source byte spans of providers for the squash path of the
--- minimap.

local M = {}

---@class ScrollbarMinimapSemanticEntry
---@field provider string
---@field index integer
---@field span ScrollbarMinimapSourceSpan

---@param value string
---@return string
local function encoded(value)
    return #value .. ":" .. value
end

---@param text string
---@param byte_col integer
---@return integer
local function display_width_to(text, byte_col)
    local prefix = text:sub(1, math.max(0, math.min(byte_col, #text)))
    local ok, width = pcall(vim.fn.strdisplaywidth, prefix)
    return ok and width or 0
end

---@param spans_by_provider ScrollbarMinimapSpanStoreSnapshot
---@return ScrollbarMinimapSemanticEntry[]
local function ordered_entries(spans_by_provider)
    local providers = vim.tbl_keys(spans_by_provider)
    table.sort(providers)

    local entries = {}
    for _, provider in ipairs(providers) do
        for index, span in ipairs(spans_by_provider[provider]) do
            entries[#entries + 1] = { provider = provider, index = index, span = span }
        end
    end
    table.sort(entries, function(left, right)
        if left.span.priority ~= right.span.priority then
            return left.span.priority > right.span.priority
        end
        if left.provider ~= right.provider then
            return left.provider < right.provider
        end
        return left.index < right.index
    end)
    return entries
end

---Convert zero-based source byte spans into ordered one-based display tuples.
---`source_lines[1]` is source line `first_line`. The result is keyed by the
---index of `source_lines`, and spans outside the lines are skipped.
---@param source_lines string[]
---@param spans_by_provider ScrollbarMinimapSpanStoreSnapshot
---@param first_line? integer Zero-based source line of `source_lines[1]`
---@return table<integer, ScrollbarMinimapSquashHighlight[]>
M.compose = function(source_lines, spans_by_provider, first_line)
    first_line = first_line or 0
    local highlights = {}
    for order, entry in ipairs(ordered_entries(spans_by_provider)) do
        local span = entry.span
        local line = span.line - first_line + 1
        local source_line = source_lines[line]
        if source_line ~= nil then
            local start_display = display_width_to(source_line, span.start_col)
            local end_display = display_width_to(source_line, span.end_col)
            if end_display > start_display then
                highlights[line] = highlights[line] or {}
                highlights[line][#highlights[line] + 1] = {
                    hl_group = span.highlight,
                    col_start = start_display + 1,
                    col_end = end_display,
                    order = order,
                }
            end
        end
    end
    return highlights
end

---Return a deterministic identity for a provider snapshot that is already
---checked.
---@param spans_by_provider ScrollbarMinimapSpanStoreSnapshot
---@return string
M.signature = function(spans_by_provider)
    local parts = {}
    local providers = vim.tbl_keys(spans_by_provider)
    table.sort(providers)
    for _, provider in ipairs(providers) do
        local provider_spans = spans_by_provider[provider]
        if #provider_spans > 0 then
            parts[#parts + 1] = encoded(provider)
            for _, span in ipairs(provider_spans) do
                parts[#parts + 1] = table.concat({
                    span.line,
                    span.start_col,
                    span.end_col,
                    span.priority,
                    encoded(span.highlight),
                }, ",")
            end
        end
    end
    return table.concat(parts, "|")
end

return M
