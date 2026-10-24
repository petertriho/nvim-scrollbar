--- Minimap overlays: project the marks that are published to
--- `lua/scrollbar/shared/store.lua` onto the minimap grid. The module only
--- reads the store and never changes it. The filter uses the provider demand
--- of the minimap and the shown mark types of the selected minimap variant.
--- Collision resolution uses the priority of the mark type (the lowest value
--- wins).

local minimap_config = require("scrollbar.minimap.config")
local projection_module = require("scrollbar.minimap.projection")
local providers = require("scrollbar.providers")
local search_compact = require("scrollbar.providers.search.compact")
local store = require("scrollbar.shared.store")

local M = {}

local active = false

local function reset_state()
    active = false
end

reset_state()

---@param _options ScrollbarMinimapOverlaysOptions
M.setup = function(_options)
    reset_state()
    active = true
end

M.dispose = function()
    reset_state()
end

---@return boolean
M.is_active = function()
    return active
end

--- Read-only projection of all published marks for `source_win` onto the
--- float rows of `projection`. Returns one winning projected overlay for each
--- row after the filter and the collision resolution, in ascending
--- `minimap_row` order. The function skips marks on rows outside the float.
--- The renderer separately filters each winner to occupied squash cells.
---
--- The mark type metadata and the highlight groups for the renderer come from
--- the selected minimap variant. The store stays a shared read-only source.
---
---@param source_win integer
---@param projection ScrollbarMinimapProjection
---@return ScrollbarMinimapOverlay[]
M.project = function(source_win, projection)
    return M.project_with(source_win, projection)
end

---@param source_win integer
---@param projection ScrollbarMinimapProjection
---@param marks? table<string, ScrollbarMinimapMarkSpec> Shown mark types. Default: the marks of the selected variant
---@return ScrollbarMinimapOverlay[]
M.project_with = function(source_win, projection, marks)
    if not active or projection.rows <= 0 then
        return {}
    end
    if projection.line_count <= 0 or not vim.api.nvim_win_is_valid(source_win) then
        return {}
    end

    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local buffer_snapshot = store._get_snapshot(source_buf)
    local window_snapshot = store._get_window_snapshot(source_win)
    marks = marks or minimap_config.select(source_win).config.marks
    if next(marks) == nil then
        return {}
    end
    local provider_names = {}
    local seen = {}
    for name in pairs(buffer_snapshot.marks) do
        seen[name] = true
    end
    for name in pairs(window_snapshot.marks) do
        seen[name] = true
    end
    if buffer_snapshot.compact_search ~= nil then
        seen.search = true
    end
    for name in pairs(seen) do
        if providers._consumer_enabled(name, "minimap") then
            provider_names[#provider_names + 1] = name
        end
    end
    table.sort(provider_names)

    ---@type table<integer, ScrollbarMinimapOverlay>
    local by_row = {}
    ---@type integer[]
    local occupied_rows = {}

    local function add_mark(provider, line, mark_type)
        local spec = marks[mark_type]
        if spec == nil then
            return
        end

        local row = projection_module.float_row(projection, line)
        if row == nil then
            return
        end
        local existing = by_row[row]
        if
            existing == nil
            or spec.priority < existing.priority
            or (spec.priority == existing.priority and provider < existing.provider)
        then
            if existing == nil then
                occupied_rows[#occupied_rows + 1] = row
            end
            by_row[row] = {
                source_line = line,
                minimap_row = row,
                mark_type = mark_type,
                priority = spec.priority,
                highlight = spec.group,
                provider = provider,
            }
        end
    end

    for _, provider in ipairs(provider_names) do
        for _, mark in ipairs(buffer_snapshot.marks[provider] or {}) do
            add_mark(provider, mark.line, mark.type)
        end
        if provider == "search" and buffer_snapshot.compact_search ~= nil then
            search_compact.each(buffer_snapshot.compact_search, function(line)
                add_mark(provider, line, "Search")
            end)
        end
        for _, mark in ipairs(window_snapshot.marks[provider] or {}) do
            add_mark(provider, mark.line, mark.type)
        end
    end

    table.sort(occupied_rows)

    ---@type ScrollbarMinimapOverlay[]
    local result = {}
    for _, row in ipairs(occupied_rows) do
        result[#result + 1] = by_row[row]
    end
    return result
end

return M
