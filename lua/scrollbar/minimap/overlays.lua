--- Minimap overlays: project marks published to `lua/scrollbar/store.lua` onto
--- the minimap grid. Read-only — never mutates the store. Filtering uses the
--- minimap's provider demand and keyed `overlays.types` specs; collision
--- resolution uses the selected minimap variant's priority (lowest wins).

local minimap_config = require("scrollbar.minimap.config")
local providers = require("scrollbar.providers")
local search_compact = require("scrollbar.providers.search_compact")
local store = require("scrollbar.store")

local M = {}

local active = false

local function reset_state()
    active = false
end

reset_state()

--- Clamp a 1-based minimap row to `[1, height]`.
---@param row integer
---@param height integer
---@return integer
local function clamp_row(row, height)
    if row < 1 then
        return 1
    end
    if row > height then
        return height
    end
    return row
end

--- Project a 0-based source line to a 1-based minimap row using the same
--- bucketing math as `lua/scrollbar/minimap/squash.lua`:
--- `floor(line / v_ratio) + 1`, clamped to the target height.
---@param line integer
---@param v_ratio number
---@param minimap_height integer
---@return integer
local function project_line(line, v_ratio, minimap_height)
    return clamp_row(math.floor(line / v_ratio) + 1, minimap_height)
end

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

--- Read-only projection of all published marks for `source_win` onto a
--- minimap grid of height `minimap_height`. Returns one winning projected
--- overlay per row after filtering and collision resolution, sorted ascending
--- by `minimap_row`. The renderer separately filters each winner to occupied
--- squash cells.
---
--- Mark type metadata and renderer-facing highlight groups come from the
--- selected minimap presentation. The store remains a shared read-only source.
---
---@param source_win integer
---@param minimap_height integer
---@return ScrollbarMinimapOverlay[]
M.project = function(source_win, minimap_height)
    if not active or minimap_height <= 0 then
        return {}
    end
    if not vim.api.nvim_win_is_valid(source_win) then
        return {}
    end
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local source_line_count = vim.api.nvim_buf_line_count(source_buf)
    return M.project_with(source_win, minimap_height, source_line_count)
end

--- Projection core. Split from `M.project` so callers that already know the
--- source line count (e.g. the renderer caching geometry) can reuse the
--- computation. `source_line_count` is the 1-based count of source lines.
---@param source_win integer
---@param minimap_height integer
---@param source_line_count integer
---@param presentation? ScrollbarMinimapOverlaysConfig
---@return ScrollbarMinimapOverlay[]
M.project_with = function(source_win, minimap_height, source_line_count, presentation)
    if not active or minimap_height <= 0 then
        return {}
    end
    if source_line_count <= 0 or not vim.api.nvim_win_is_valid(source_win) then
        return {}
    end

    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local buffer_snapshot = store._get_snapshot(source_buf)
    local window_snapshot = store._get_window_snapshot(source_win)
    presentation = presentation or minimap_config.select(source_win).config.overlays
    if not presentation.enabled then
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

    local v_ratio = math.max(1, source_line_count / minimap_height)

    ---@type table<integer, ScrollbarMinimapOverlay>
    local by_row = {}
    ---@type integer[]
    local occupied_rows = {}

    local function add_mark(provider, line, mark_type)
        local spec = presentation.types[mark_type]
        if spec == nil then
            return
        end

        local row = project_line(line, v_ratio, minimap_height)
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
