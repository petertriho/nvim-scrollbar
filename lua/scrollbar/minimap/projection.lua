--- Pure mapping between source lines and minimap rows for one render.
---
--- `scale = "fixed"` gives each dot row one source line, so a cell row covers
--- 4 lines. When the map has more rows than the float, the map scrolls in
--- proportion to the source window: the top of the file shows the top of the
--- map, and the end of the file shows the end of the map.
---
--- `scale = "fit"` shrinks the whole buffer into the float height. A buffer
--- that fits at the fixed scale looks the same in both scales.
---
--- The grid math comes from `lua/scrollbar/minimap/squash.lua`, so a line
--- always lands on the row that the squash draws it in.

local squash = require("scrollbar.minimap.squash")

local M = {}

local DOT_ROWS = squash.DOT_ROWS
local DOT_COLUMNS = squash.DOT_COLUMNS

---@param value number
---@param minimum number
---@param maximum number
---@return number
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

---@class ScrollbarMinimapProjectionOptions
---@field scale ScrollbarMinimapScale
---@field line_count integer
---@field rows integer Float rows
---@field width integer Float columns
---@field columns_per_dot integer
---@field top integer Zero-based first visible source line
---@field bottom integer Zero-based last visible source line

--- Build the projection of one render.
---@param options ScrollbarMinimapProjectionOptions
---@return ScrollbarMinimapProjection
M.new = function(options)
    local line_count = math.max(0, options.line_count)
    local rows = math.max(1, options.rows)
    local dots = rows * DOT_ROWS

    local scale_lines = 1
    local scale_dots = 1
    if options.scale == "fit" and line_count > dots then
        scale_lines = line_count
        scale_dots = dots
    end
    local lines_per_row = DOT_ROWS * scale_lines / scale_dots
    local map_rows = 0
    if line_count > 0 then
        map_rows = math.floor(
            squash.line_dot(line_count - 1, { scale_lines = scale_lines, scale_dots = scale_dots }) / DOT_ROWS
        ) + 1
    end

    local last_line = math.max(0, line_count - 1)
    local top = clamp(options.top, 0, last_line)
    local bottom = clamp(options.bottom, top, last_line)
    local scrollable = math.max(0, line_count - (bottom - top + 1))
    local max_offset = math.max(0, map_rows - rows)
    local offset = 0
    -- Rows that the viewport band moves for each line of scrolling.
    local band_rate = 1 / lines_per_row
    if max_offset > 0 and scrollable > 0 then
        offset = math.floor(math.min(1, top / scrollable) * max_offset + 0.5)
        band_rate = band_rate - max_offset / scrollable
    end

    ---@type ScrollbarMinimapProjection
    return {
        scale = options.scale,
        line_count = line_count,
        rows = rows,
        width = options.width,
        columns_per_dot = options.columns_per_dot,
        scale_lines = scale_lines,
        scale_dots = scale_dots,
        map_rows = map_rows,
        offset = offset,
        top = top,
        bottom = bottom,
        max_topline = scrollable,
        scroll_rate = band_rate > 0 and 1 / band_rate or lines_per_row,
    }
end

--- Zero-based map row that shows source line `line`.
---@param projection ScrollbarMinimapProjection
---@param line integer
---@return integer
M.map_row = function(projection, line)
    return math.floor(squash.line_dot(line, projection) / DOT_ROWS)
end

--- One-based float row that shows source line `line`, or `nil` when the row
--- is outside the float.
---@param projection ScrollbarMinimapProjection
---@param line integer Zero-based source line
---@return integer?
M.float_row = function(projection, line)
    if line < 0 or line >= projection.line_count then
        return nil
    end
    local row = M.map_row(projection, line) - projection.offset + 1
    if row < 1 or row > projection.rows then
        return nil
    end
    return row
end

--- First source line (0-based) of a float row.
---@param projection ScrollbarMinimapProjection
---@param row integer Zero-based float row
---@return integer
M.row_line = function(projection, row)
    local line = squash.dot_first_line((projection.offset + row) * DOT_ROWS, projection)
    return clamp(line, 0, math.max(0, projection.line_count - 1))
end

--- One-based cell of a zero-based display column, clamped to the float width.
---@param projection ScrollbarMinimapProjection
---@param display_col integer
---@return integer
M.cell = function(projection, display_col)
    local cell = math.floor(display_col / (DOT_COLUMNS * projection.columns_per_dot)) + 1
    return clamp(cell, 1, projection.width)
end

--- One-based float rows of the viewport band. The band covers every row that
--- shows a visible line. Returns `nil` when no such row is in the float.
---@param projection ScrollbarMinimapProjection
---@return integer? first
---@return integer? last
M.band = function(projection)
    if projection.line_count <= 0 then
        return nil, nil
    end
    local first = M.map_row(projection, projection.top) - projection.offset + 1
    local last = M.map_row(projection, projection.bottom) - projection.offset + 1
    if last < 1 or first > projection.rows then
        return nil, nil
    end
    return math.max(1, first), math.min(projection.rows, last)
end

--- Map rows to request from the squash: the visible rows plus one float
--- height above and below.
---@param projection ScrollbarMinimapProjection
---@return integer first_row
---@return integer row_count
M.slice = function(projection)
    local first = math.max(0, projection.offset - projection.rows)
    local last = math.min(projection.map_rows, projection.offset + 2 * projection.rows)
    return first, math.max(0, last - first)
end

--- Whether cached rows `[first_row, first_row + row_count)` serve this
--- projection. With `margin`, a side that is not a file end must keep half a
--- float height of rows past the visible rows.
---@param projection ScrollbarMinimapProjection
---@param first_row integer
---@param row_count integer
---@param margin boolean
---@return boolean
M.covers = function(projection, first_row, row_count, margin)
    local extra = margin and math.floor(projection.rows / 2) or 0
    local need_first = math.max(0, projection.offset - extra)
    local need_last = math.min(projection.map_rows, projection.offset + projection.rows + extra)
    return first_row <= need_first and first_row + row_count >= need_last
end

--- Source topline (0-based) after a drag of `delta` float rows that started
--- at `topline`. The viewport band follows the pointer.
---@param projection ScrollbarMinimapProjection
---@param topline integer
---@param delta integer
---@return integer
M.drag_topline = function(projection, topline, delta)
    local target = topline + delta * projection.scroll_rate
    return clamp(math.floor(target + 0.5), 0, projection.max_topline)
end

return M
