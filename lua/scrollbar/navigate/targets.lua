--- Mark queries of label mode, the peek, and the glance list.
---
--- `cells` reads the hit map of the last render of the scrollbar, so a label
--- target is exactly a cell that a click can reach. `marks` and `entries` read
--- the mark store with the provider rule of the renderer
--- (`providers._consumed_marks`), so the glance list works also without a
--- scrollbar float. The list reads the providers that the scrollbar consumes,
--- or the providers that the minimap consumes when the scrollbar is disabled.
---
--- `Cursor` marks are targets only when `types` names them.

local config = require("scrollbar.config")
local providers = require("scrollbar.providers")
local search_compact = require("scrollbar.providers.search.compact")
local store = require("scrollbar.shared.store")

local M = {}

local CURSOR = "Cursor"
local MARK = "Mark"
-- The glyph of a mark type without a fixed glyph, such as a type with a text
-- function.
local FALLBACK_GLYPH = "•"

---@class ScrollbarNavigateCell
---@field row integer Zero-based row of the scrollbar float
---@field col integer One-based first display column of the glyph
---@field end_col integer One-based last display column of the glyph
---@field line integer Zero-based line that a click on the cell moves to
---@field lines integer[] Every line that the cell compresses
---@field type string
---@field provider string

---@class ScrollbarNavigateMark
---@field line integer Zero-based line
---@field type string
---@field provider string
---@field text? string Text of the provider
---@field priority integer
---@field glyph string
---@field group string Highlight group of the glyph

---@class ScrollbarNavigateEntry
---@field kind "entry"|"header"
---@field line integer Zero-based line. A header has the line of the first entry of its group
---@field marks ScrollbarNavigateMark[] Marks of the entry in priority order. A header has the marks of its group
---@field type string Mark type of the first mark

---@param types? table<string, true>
---@param mark_type string
---@return boolean
local function wanted(types, mark_type)
    if types == nil then
        return mark_type ~= CURSOR
    end
    return types[mark_type] == true
end

---@param source_win integer
---@return ScrollbarHitCell[][]?
local function hitmap_of(source_win)
    local renderer = package.loaded["scrollbar.renderer"]
    return renderer and renderer.get_hitmap(source_win) or nil
end

--- The target of a hit cell, or nil when a click on the cell does not jump to
--- a mark of a wanted type.
---@param hit ScrollbarHitCell
---@param row integer One-based row of the hit map
---@param col integer One-based column of the hit map
---@param types? table<string, true>
---@return ScrollbarNavigateCell?
local function to_cell(hit, row, col, types)
    if hit.line == nil or hit.type == nil or not wanted(types, hit.type) then
        return nil
    end
    local start_col = hit.start_col or col
    return {
        row = row - 1,
        col = start_col,
        end_col = hit.end_col or start_col,
        line = hit.line,
        lines = hit.lines or { hit.line },
        type = hit.type,
        provider = hit.provider,
    }
end

---@param source_win integer
---@param types? table<string, true> Mark types to keep. Nil keeps every type except `Cursor`
---@return ScrollbarNavigateCell[] cells In row order, then column order
M.cells = function(source_win, types)
    local hitmap = hitmap_of(source_win)
    if hitmap == nil then
        return {}
    end
    local result = {}
    for row, cells in ipairs(hitmap) do
        local last_col = 0
        for col, hit in ipairs(cells) do
            local cell = to_cell(hit, row, col, types)
            -- Each column of a wide glyph has a copy of its cell.
            if cell ~= nil and cell.col > last_col then
                last_col = cell.col
                result[#result + 1] = cell
            end
        end
    end
    return result
end

--- The target at one position of the scrollbar float.
---@param source_win integer
---@param row integer Zero-based row of the float content
---@param col integer One-based column of the float content
---@param types? table<string, true> Mark types to keep. Nil keeps every type except `Cursor`
---@return ScrollbarNavigateCell?
M.cell_at = function(source_win, row, col, types)
    local hitmap = hitmap_of(source_win)
    local hit = hitmap and hitmap[row + 1] and hitmap[row + 1][col] or nil
    if hit == nil then
        return nil
    end
    return to_cell(hit, row + 1, col, types)
end

--- The consumer whose providers the list reads.
---@return "scrollbar"|"minimap"
local function consumer()
    return config.get().enabled and "scrollbar" or "minimap"
end

M.consumer = consumer

--- The source kind of `source_win` for the renderer of `name`, or nil when
--- the window is not a source of it. A renderer that is not loaded has no
--- sources. A profile can match a float kind, so the selection needs the kind.
--- Nil selects as for a normal window.
---@param source_win integer
---@param name "scrollbar"|"minimap"
---@return ScrollbarSourceKind?
local function source_kind(source_win, name)
    local renderer = package.loaded[name == "scrollbar" and "scrollbar.renderer" or "scrollbar.minimap.renderer"]
    return renderer ~= nil and renderer.source_kind(source_win) or nil
end

M.source_kind = source_kind

--- The mark types that the renderer of `name` shows in `source_win`.
---@param source_win integer
---@param name "scrollbar"|"minimap"
---@return table<string, { priority: integer }>
local function shown_marks(source_win, name)
    local kind = source_kind(source_win, name)
    if name == "scrollbar" then
        return config.select(source_win, kind).config.marks
    end
    return require("scrollbar.minimap.config").select(source_win, kind).config.marks
end

--- The glyph that a single mark of `mark_type` shows in the scrollbar.
---@param mark_type string
---@param text? ScrollbarText Configured text of the type
---@param provider_text? string
---@return string
local function glyph(mark_type, text, provider_text)
    local variant = type(text) == "table" and text[1] or nil
    local result
    if mark_type == MARK then
        result = variant or provider_text
    else
        result = provider_text or variant
    end
    if result == nil or result == "" then
        return FALLBACK_GLYPH
    end
    return result
end

---@param left ScrollbarNavigateMark
---@param right ScrollbarNavigateMark
---@return boolean
local function mark_less(left, right)
    if left.line ~= right.line then
        return left.line < right.line
    end
    if left.priority ~= right.priority then
        return left.priority < right.priority
    end
    if left.type ~= right.type then
        return left.type < right.type
    end
    if left.provider ~= right.provider then
        return left.provider < right.provider
    end
    return (left.text or "") < (right.text or "")
end

--- The marks of `source_win` and its buffer that the list reads, sorted by
--- line, then by priority. An exact duplicate shows once.
---@param source_win integer
---@param types? table<string, true> Mark types to keep. Nil keeps every type except `Cursor`
---@return ScrollbarNavigateMark[]
M.marks = function(source_win, types)
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local line_count = vim.api.nvim_buf_line_count(source_buf)
    local name = consumer()
    local shown = shown_marks(source_win, name)
    -- The minimap has no glyphs, so the glyphs come from the scrollbar
    -- configuration, which exists also when the scrollbar is disabled.
    local glyph_specs = name == "scrollbar" and shown or config.get().marks
    local buffer_snapshot = store._get_snapshot(source_buf)
    local window_snapshot = store._get_window_snapshot(source_win)
    local provider_names, compact_search = providers._consumed_marks(buffer_snapshot, window_snapshot, name)

    local result = {}
    local seen = {}
    -- One glyph and one group for each type.
    local styles = {}

    ---@param provider string
    ---@param line integer
    ---@param mark_type string
    ---@param text? string
    local function add(provider, line, mark_type, text)
        local spec = shown[mark_type]
        if spec == nil or line < 0 or line >= line_count or not wanted(types, mark_type) then
            return
        end
        local key = line .. "\0" .. mark_type .. "\0" .. provider .. "\0" .. (text or "")
        if seen[key] then
            return
        end
        seen[key] = true
        local glyph_text = glyph_specs[mark_type] and glyph_specs[mark_type].text or nil
        local style = styles[mark_type]
        if style == nil then
            style = {
                glyph = glyph(mark_type, glyph_text, nil),
                group = "Scrollbar" .. mark_type,
            }
            styles[mark_type] = style
        end
        result[#result + 1] = {
            line = line,
            type = mark_type,
            provider = provider,
            text = text,
            priority = spec.priority,
            glyph = text ~= nil and glyph(mark_type, glyph_text, text) or style.glyph,
            group = style.group,
        }
    end

    for _, provider in ipairs(provider_names) do
        for _, snapshot in ipairs({ buffer_snapshot.marks, window_snapshot.marks }) do
            for _, mark in ipairs(snapshot[provider] or {}) do
                add(provider, mark.line, mark.type, mark.text)
            end
        end
    end
    if compact_search ~= nil then
        search_compact.each(compact_search, function(line)
            add("search", line, "Search")
        end)
    end
    table.sort(result, mark_less)
    return result
end

--- The marks on one line, in priority order.
---@param source_win integer
---@param line integer
---@param types? table<string, true>
---@return ScrollbarNavigateMark[]
M.line_marks = function(source_win, line, types)
    local result = {}
    for _, mark in ipairs(M.marks(source_win, types)) do
        if mark.line == line then
            result[#result + 1] = mark
        elseif mark.line > line then
            break
        end
    end
    return result
end

---@param marks ScrollbarNavigateMark[]
---@return ScrollbarNavigateEntry[]
local function by_line(marks)
    local result = {}
    local current
    for _, mark in ipairs(marks) do
        if current == nil or current.line ~= mark.line then
            current = { kind = "entry", line = mark.line, marks = {}, type = mark.type }
            result[#result + 1] = current
        end
        current.marks[#current.marks + 1] = mark
    end
    return result
end

---@param marks ScrollbarNavigateMark[]
---@return ScrollbarNavigateEntry[]
local function by_mark(marks)
    local result = {}
    for index, mark in ipairs(marks) do
        result[index] = { kind = "entry", line = mark.line, marks = { mark }, type = mark.type }
    end
    return result
end

---@param marks ScrollbarNavigateMark[]
---@return ScrollbarNavigateEntry[]
local function by_type(marks)
    local groups = {}
    local order = {}
    for _, mark in ipairs(marks) do
        local group = groups[mark.type]
        if group == nil then
            group = { type = mark.type, priority = mark.priority, marks = {} }
            groups[mark.type] = group
            order[#order + 1] = group
        end
        group.marks[#group.marks + 1] = mark
    end
    table.sort(order, function(left, right)
        if left.priority ~= right.priority then
            return left.priority < right.priority
        end
        return left.type < right.type
    end)

    local result = {}
    for _, group in ipairs(order) do
        result[#result + 1] = {
            kind = "header",
            line = group.marks[1].line,
            marks = group.marks,
            type = group.type,
        }
        for _, entry in ipairs(by_line(group.marks)) do
            result[#result + 1] = entry
        end
    end
    return result
end

local BUILDERS = { line = by_line, mark = by_mark, type = by_type }

--- The entries of the glance list.
--- - `"line"`: one entry for each marked line.
--- - `"mark"`: one entry for each mark.
--- - `"type"`: one group for each type, in priority order and then in name
---   order. A header starts each group, and the group has one entry for each
---   line.
---@param source_win integer
---@param mode ScrollbarGlanceEntries
---@param types? table<string, true> Mark types to keep. Nil keeps every type except `Cursor`
---@return ScrollbarNavigateEntry[]
M.entries = function(source_win, mode, types)
    return BUILDERS[mode](M.marks(source_win, types))
end

return M
