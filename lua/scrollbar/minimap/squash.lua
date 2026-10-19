--- Pure squash algorithm and grid math for the minimap.
---
--- The minimap grid is a grid of dots. Each cell has 2 dot columns and 4 dot
--- rows. One dot column covers `columns_per_dot` source display columns, and
--- source columns past `width * 2 * columns_per_dot` are clipped. One dot row
--- covers `scale_lines / scale_dots` source lines. Dot row `k` owns the lines
--- `[floor(k * scale_lines / scale_dots), floor((k + 1) * scale_lines / scale_dots))`,
--- so every line belongs to exactly one dot row. The integer ratio keeps the
--- squash, the renderer, the overlays, and the mouse in exact agreement.
---
--- A dot is set when any line of its dot row has a non-blank character in any
--- of its display columns. A cell with dots draws a Braille character
--- (`encoding = "braille"`) or `█` (`encoding = "block"`). An empty cell is a
--- space. The cell highlight is the ordered semantic highlight with the lowest
--- order among the filled source columns of the cell. Legacy unordered tuples
--- keep source and tuple order.
---
--- The worker child loads this file with `loadstring`, so it must not
--- `require` plugin modules.

local M = {}

M.DOT_ROWS = 4
M.DOT_COLUMNS = 2

local BLOCK = "█"

-- Braille dot bits by dot column, then by dot row.
local BRAILLE_BITS = {
    { 0x01, 0x02, 0x04, 0x40 },
    { 0x08, 0x10, 0x20, 0x80 },
}

---@type table<integer, string>
local braille_chars = {}

---@param mask integer 1-255
---@return string
local function braille(mask)
    local char = braille_chars[mask]
    if char == nil then
        -- UTF-8 of U+2800 + mask.
        char = string.char(0xE2, 0xA0 + math.floor(mask / 64), 0x80 + mask % 64)
        braille_chars[mask] = char
    end
    return char
end

---@param mask integer
---@param bit integer
---@return integer
local function with_bit(mask, bit)
    if math.floor(mask / bit) % 2 == 0 then
        return mask + bit
    end
    return mask
end

--- First source line (0-based) of dot row `dot`.
---@param dot integer Zero-based dot row of the whole map
---@param grid { scale_lines: integer, scale_dots: integer }
---@return integer
M.dot_first_line = function(dot, grid)
    return math.floor(dot * grid.scale_lines / grid.scale_dots)
end

--- Dot row (0-based) that owns source line `line`.
---@param line integer Zero-based source line
---@param grid { scale_lines: integer, scale_dots: integer }
---@return integer
M.line_dot = function(line, grid)
    return math.floor(((line + 1) * grid.scale_dots - 1) / grid.scale_lines)
end

--- Source lines that the rows of `grid` cover.
---@param grid ScrollbarMinimapGrid
---@param line_count integer
---@return integer first Zero-based first line
---@return integer last Zero-based end line, exclusive
M.line_range = function(grid, line_count)
    local first = math.min(line_count, M.dot_first_line(grid.first_row * M.DOT_ROWS, grid))
    local last = math.min(line_count, M.dot_first_line((grid.first_row + grid.row_count) * M.DOT_ROWS, grid))
    return first, math.max(first, last)
end

local function is_blank_char(ch)
    return ch == " " or ch == "\t"
end

--- Non-blank display columns of `line`, up to `limit`.
---@param line string
---@param limit integer
---@return table<integer, true> densities One-based display columns with content
---@return integer width Last examined display column
local function line_densities(line, limit)
    local densities = {}
    if line == "" or limit <= 0 then
        return densities, 0
    end

    if not line:find("[\t\128-\255]") then
        local last = math.min(#line, limit)
        for col = 1, last do
            if line:byte(col) ~= 32 then
                densities[col] = true
            end
        end
        return densities, last
    end

    local display_col = 1
    local char_count = vim.fn.strchars(line, 1)
    for index = 0, char_count - 1 do
        if display_col > limit then
            break
        end
        local ch = vim.fn.strcharpart(line, index, 1, 1)
        local ch_width = math.max(0, vim.fn.strdisplaywidth(ch, display_col - 1))
        if not is_blank_char(ch:sub(1, 1)) then
            for col = display_col, math.min(display_col + ch_width - 1, limit) do
                densities[col] = true
            end
        end
        display_col = display_col + ch_width
    end
    return densities, math.min(display_col - 1, limit)
end

---@param candidate ScrollbarMinimapSquashHighlight
---@param current ScrollbarMinimapSquashHighlight?
---@return boolean
local function highlight_wins(candidate, current)
    if current == nil then
        return true
    end
    if candidate.order ~= nil and current.order ~= nil then
        return candidate.order < current.order
    end
    return candidate.order ~= nil and current.order == nil
end

--- Squash a slice of source lines into `grid.row_count` rows of
--- `grid.width` cells. `lines[1]` is source line `first_line`. `highlights`
--- maps an index of `lines` to `{ hl_group, col_start, col_end, order? }`
--- tuples with one-based, inclusive display columns.
---@param lines string[]
---@param first_line integer Zero-based source line of `lines[1]`
---@param grid ScrollbarMinimapGrid
---@param highlights? table<integer, ScrollbarMinimapSquashHighlight[]>
---@return ScrollbarMinimapCell[][]
M.squash = function(lines, first_line, grid, highlights)
    local width = grid.width
    local row_count = grid.row_count
    if width <= 0 or row_count <= 0 then
        return {}
    end
    highlights = highlights or {}

    local columns_per_dot = grid.columns_per_dot
    local cell_columns = M.DOT_COLUMNS * columns_per_dot
    local limit = width * cell_columns
    local block = grid.encoding == "block"

    local result = {}
    for row = 1, row_count do
        local masks = {}
        local winners = {}
        local map_row = grid.first_row + row - 1
        for dot_row = 1, M.DOT_ROWS do
            local dot = map_row * M.DOT_ROWS + dot_row - 1
            local line_start = M.dot_first_line(dot, grid)
            local line_end = M.dot_first_line(dot + 1, grid)
            for line = line_start, line_end - 1 do
                local index = line - first_line + 1
                local text = lines[index]
                if text ~= nil then
                    local densities, line_width = line_densities(text, limit)
                    for col = 1, line_width do
                        if densities[col] then
                            local dot_col = math.floor((col - 1) / columns_per_dot)
                            local cell = math.floor(dot_col / M.DOT_COLUMNS) + 1
                            local bit = BRAILLE_BITS[dot_col % M.DOT_COLUMNS + 1][dot_row]
                            masks[cell] = with_bit(masks[cell] or 0, bit)
                        end
                    end
                    for _, tuple in ipairs(highlights[index] or {}) do
                        for col = math.max(1, tuple.col_start), math.min(line_width, tuple.col_end) do
                            if densities[col] then
                                local cell = math.floor((col - 1) / cell_columns) + 1
                                if highlight_wins(tuple, winners[cell]) then
                                    winners[cell] = tuple
                                end
                            end
                        end
                    end
                end
            end
        end

        local cells = {}
        for cell = 1, width do
            local mask = masks[cell]
            if mask == nil then
                cells[cell] = { char = " " }
            else
                local winner = winners[cell]
                cells[cell] = {
                    char = block and BLOCK or braille(mask),
                    hl_group = winner and winner.hl_group or nil,
                }
            end
        end
        result[row] = cells
    end
    return result
end

return M
