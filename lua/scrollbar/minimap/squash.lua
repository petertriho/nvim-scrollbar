--- Pure vertical + horizontal squash algorithm for the minimap.
---
--- Input: a list of source lines plus a target `(width, height)` and optional
--- per-line highlight tuples. Output: a `(height × width)` grid of cells where
--- each cell is `{ char = <canonical char>, hl_group = <string|nil> }`, plus
--- a second return value `max_line_width` (display width of the longest source
--- line).
---
--- Single-box algorithm:
---   1. Per source line, compute a binary density array (one entry per
---      display column). Blank/whitespace columns are 0; any non-blank
---      column is 1. Run length no longer matters.
---   2. Vertical merge: `v_ratio = max(1, source_lines / height)`. Target row `r`
---      owns source lines `[floor(r * v_ratio), floor((r+1) * v_ratio))`.
---      Per column, binary OR of the merged range wins; the first ordered
---      semantic highlight among filled columns wins.
---   3. Horizontal merge: `h_ratio = max(1, max_source_line_len / width)`.
---      Target column `c` owns source columns aggregated by binary OR.
---   4. Canonical output. Empty cells emit a space and occupied cells emit `█`.
---      Ordered semantic highlights keep their priority across all merged lines;
---      legacy unordered tuples retain source and tuple order.
---
--- Indentation is preserved as leading blank cells because whitespace columns
--- always produce density 0. The function is pure and deterministic: identical
--- inputs produce identical outputs across calls.

local M = {}

local function is_blank_char(ch)
    return ch == " " or ch == "\t"
end

--- Compute the per-display-column binary density array for a source line.
--- Returns `(densities, width)` where `densities[col]` is 0 or 1 for col in
--- `[1, width]`. Whitespace columns are 0; every display column occupied by a
--- non-blank character is 1.
local function line_densities(line)
    local width = vim.fn.strdisplaywidth(line)
    if width <= 0 then
        return {}, 0
    end

    local densities = {}
    for col = 1, width do
        densities[col] = 0
    end

    local display_col = 1
    local char_count = vim.fn.strchars(line, 1)
    for index = 0, char_count - 1 do
        local ch = vim.fn.strcharpart(line, index, 1, 1)
        local ch_width = math.max(0, vim.fn.strdisplaywidth(ch, display_col - 1))
        if not is_blank_char(ch:sub(1, 1)) then
            for col = display_col, display_col + ch_width - 1 do
                densities[col] = 1
            end
        end
        display_col = display_col + ch_width
    end

    return densities, width
end

--- Build a fully-blank target grid (all spaces / no highlight).
local function blank_grid(width, height)
    local grid = {}
    for row = 1, height do
        local cells = {}
        for col = 1, width do
            cells[col] = { char = " ", hl_group = nil }
        end
        grid[row] = cells
    end
    return grid
end

---@class ScrollbarMinimapResolvedHighlight
---@field hl_group string
---@field order? integer

---@param candidate ScrollbarMinimapResolvedHighlight
---@param current ScrollbarMinimapResolvedHighlight?
---@return boolean
local function highlight_wins(candidate, current)
    if current == nil then
        return true
    end
    if candidate.order ~= nil and current.order ~= nil then
        return candidate.order < current.order
    end
    if candidate.order ~= nil then
        return true
    end
    return false
end

--- Pure squash. `highlights` is an optional table mapping 1-indexed source
--- line number to a list of `{ hl_group, col_start, col_end }` tuples, where
--- `col_start` and `col_end` are 1-indexed display columns and `col_end` is
--- inclusive.
---
---@param source_lines string[]
---@param target_width integer
---@param target_height integer Terminal row count.
---@param highlights? table<integer, ScrollbarMinimapSquashHighlight[]>
---@return ScrollbarMinimapCell[][] grid
---@return integer max_line_width Display width of the longest source line.
M.squash = function(source_lines, target_width, target_height, highlights)
    if target_width <= 0 or target_height <= 0 then
        return {}, 0
    end

    local source_count = #source_lines
    if source_count == 0 then
        return blank_grid(target_width, target_height), 0
    end

    highlights = highlights or {}

    local line_density = {}
    local max_width = 0
    for index = 1, source_count do
        local densities, width = line_densities(source_lines[index])
        line_density[index] = { densities = densities, width = width }
        if width > max_width then
            max_width = width
        end
    end

    if max_width == 0 then
        return blank_grid(target_width, target_height), 0
    end

    local v_ratio = math.max(1, source_count / target_height)

    ---@type { density: integer[], hl: (ScrollbarMinimapResolvedHighlight|nil)[] }[]
    local merged_rows = {}
    for row = 1, target_height do
        local row_start = math.floor((row - 1) * v_ratio) + 1
        local row_end_exclusive = math.floor(row * v_ratio) + 1

        local merged_density = {}
        local merged_hl = {}
        for col = 1, max_width do
            merged_density[col] = 0
            merged_hl[col] = nil
        end

        for src = row_start, row_end_exclusive - 1 do
            local data = line_density[src]
            if data ~= nil then
                for col = 1, data.width do
                    if data.densities[col] == 1 then
                        merged_density[col] = 1
                    end
                end
            end
        end

        for src = row_start, row_end_exclusive - 1 do
            local data = line_density[src]
            if data ~= nil then
                local line_hls = highlights[src]
                if line_hls ~= nil then
                    for _, tuple in ipairs(line_hls) do
                        local start_col = math.max(1, tuple.col_start)
                        local end_col = math.min(data.width, tuple.col_end)
                        local candidate = { hl_group = tuple.hl_group, order = tuple.order }
                        for col = start_col, end_col do
                            if
                                data.densities[col] == 1
                                and merged_density[col] == 1
                                and highlight_wins(candidate, merged_hl[col])
                            then
                                merged_hl[col] = candidate
                            end
                        end
                    end
                end
            end
        end

        merged_rows[row] = { density = merged_density, hl = merged_hl }
    end

    local h_ratio = math.max(1, max_width / target_width)

    local grid = {}
    for row = 1, target_height do
        local merged = merged_rows[row]
        local cells = {}
        for col = 1, target_width do
            local col_start = math.floor((col - 1) * h_ratio) + 1
            local col_end_exclusive = math.floor(col * h_ratio) + 1

            local filled = false
            for src_col = col_start, col_end_exclusive - 1 do
                if merged.density[src_col] == 1 then
                    filled = true
                end
            end

            ---@type ScrollbarMinimapResolvedHighlight?
            local resolved_hl
            if filled then
                for src_col = col_start, col_end_exclusive - 1 do
                    local candidate = merged.hl[src_col]
                    if merged.density[src_col] == 1 and candidate ~= nil and highlight_wins(candidate, resolved_hl) then
                        resolved_hl = candidate
                    end
                end
            end

            cells[col] = {
                char = filled and "█" or " ",
                hl_group = resolved_hl and resolved_hl.hl_group or nil,
            }
        end
        grid[row] = cells
    end

    return grid, max_width
end

return M
