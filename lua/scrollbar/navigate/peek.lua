--- The peek float: a float window on the source buffer that shows the lines
--- around one mark. Label mode and hover use one peek float at a time. The
--- glance preview pane uses the same window setup.
---
--- The float opens with `noautocmd`, so the autocmds of other plugins do not
--- see it. It shows the source buffer itself, so the diagnostics, the signs,
--- and the other extmarks of the buffer show in it too. A window variable
--- marks it, and the source policy of both renderers never takes such a
--- window as a source.

local config = require("scrollbar.config")
local stack = require("scrollbar.shared.stack")
local targets = require("scrollbar.navigate.targets")
local window_config = require("scrollbar.config.window")

local M = {}

--- Window variable of the peek float and the glance panes. The source policy
--- reads it.
M.OWNED_VAR = "scrollbar_navigate_owned"

-- Window options of a float on the source buffer. `peek.window.wo` and
-- `glance.window.wo` apply after them.
local WINDOW_OPTIONS = {
    number = true,
    cursorline = true,
    signcolumn = "auto",
    foldenable = false,
    wrap = false,
}

---@class ScrollbarPeekState
---@field source_win integer
---@field source_buf integer
---@field win integer
---@field line integer Zero-based line under the cursor of the float
---@field position ScrollbarPeekPosition
---@field anchor_row? integer

---@type ScrollbarPeekState?
local current

---@class ScrollbarPeekOpenOptions
---@field position? ScrollbarPeekPosition Default: `peek.position`
---@field anchor_row? integer Zero-based text row of the source window that a `"scrollbar"` float centers on. Default: the cursor row
---@field types? table<string, true> Mark types that the title names. Nil names every type except `Cursor`

---@class ScrollbarPeekGeometry
---@field row integer Zero-based row of the frame, relative to the text area of the source window
---@field col integer Zero-based column of the frame, relative to the source window
---@field width integer Content width
---@field height integer Content height

---@param winid? integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---@param source_win integer
---@return { width: integer, height: integer, textoff: integer, screen_col: integer }
local function text_area(source_win)
    local winbar = vim.api.nvim_get_option_value("winbar", { win = source_win })
    local info = vim.fn.getwininfo(source_win)[1]
    return {
        width = vim.api.nvim_win_get_width(source_win),
        height = math.max(0, vim.api.nvim_win_get_height(source_win) - (winbar == "" and 0 or 1)),
        textoff = info.textoff,
        screen_col = vim.fn.win_screenpos(source_win)[2] - 1,
    }
end

--- The side of the floats of the source window and their inward edge: the
--- column next to the float that is nearest to the text. Without a float, the
--- side is east and the edge is the right edge of the window.
---@param source_win integer
---@param area { width: integer, screen_col: integer }
---@return "E"|"W" side
---@return integer edge Zero-based column relative to the window. On the east side, the first column of the floats
local function float_edge(source_win, area)
    local side, edge
    for _, renderer in ipairs({ "scrollbar", "minimap" }) do
        local footprint = stack.footprint(renderer, source_win)
        if footprint ~= nil and (side == nil or footprint.side == side) then
            local origin = stack.resolve(renderer, source_win, footprint) or footprint.origin
            local inward
            if footprint.side == "W" then
                inward = origin + footprint.col + footprint.width
            else
                inward = origin + footprint.col - footprint.width
            end
            if footprint.relative == "editor" then
                inward = inward - area.screen_col
            end
            if side == nil then
                side, edge = footprint.side, inward
            elseif side == "W" then
                edge = math.max(edge, inward)
            else
                edge = math.min(edge, inward)
            end
        end
    end
    if side == nil then
        return "E", area.width
    end
    return side, math.max(0, math.min(edge, area.width))
end

---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

--- The rows of the cursor line of `source_win`, relative to its text area.
---@param source_win integer
---@return integer
local function cursor_row(source_win)
    return vim.api.nvim_win_call(source_win, vim.fn.winline) - 1
end

--- Place the frame of a peek float in the source window.
---@param source_win integer
---@param position ScrollbarPeekPosition
---@param anchor_row? integer
---@param sides ScrollbarWindowSides
---@param peek_config ScrollbarPeekConfig
---@return ScrollbarPeekGeometry?
M._geometry = function(source_win, position, anchor_row, sides, peek_config)
    local area = text_area(source_win)
    local frame_rows = sides.top + sides.bottom
    local frame_cols = sides.left + sides.right
    local height = math.min(2 * peek_config.context + 1, area.height - frame_rows)
    local width = math.floor(peek_config.width * area.width)

    local first_col = area.textoff
    local last_col = area.width
    local side = "E"
    if position == "scrollbar" then
        local edge
        side, edge = float_edge(source_win, area)
        if side == "E" then
            last_col = edge
        else
            first_col = math.max(first_col, edge)
        end
    end
    width = math.min(width, last_col - first_col - frame_cols)
    if height < 1 or width < 1 then
        return nil
    end
    local frame_height = height + frame_rows
    local frame_width = width + frame_cols
    local max_row = area.height - frame_height

    local row, col
    if position == "scrollbar" then
        local center = anchor_row or cursor_row(source_win)
        row = center - sides.top - math.floor(height / 2)
        col = side == "E" and last_col - frame_width or first_col
    elseif position == "cursor" then
        local cursor = cursor_row(source_win)
        row = cursor + 1
        if row > max_row then
            -- No room below, so the float goes above the cursor line.
            row = cursor - frame_height
        end
        col = first_col
    else
        row = math.floor(max_row / 2)
        col = first_col + math.floor((last_col - first_col - frame_width) / 2)
    end
    return {
        row = clamp(row, 0, max_row),
        col = clamp(col, first_col, last_col - frame_width),
        width = width,
        height = height,
    }
end

--- The title of a peek float: the mark types of the line and the line number.
---@param source_win integer
---@param line integer
---@param types? table<string, true>
---@return string
local function title(source_win, line, types)
    local names = {}
    local seen = {}
    for _, mark in ipairs(targets.line_marks(source_win, line, types)) do
        if not seen[mark.type] then
            seen[mark.type] = true
            names[#names + 1] = mark.type
        end
    end
    if #names == 0 then
        return string.format(" %d ", line + 1)
    end
    return string.format(" %s · %d ", table.concat(names, ", "), line + 1)
end

--- Apply the window options of a float on the source buffer: the defaults,
--- then the options of the `window` configuration.
---@param win integer
---@param window ScrollbarWindowConfig
---@param defaults? table<string, any> Options that replace the shared defaults
M.configure_window = function(win, window, defaults)
    for name, value in pairs(WINDOW_OPTIONS) do
        vim.api.nvim_set_option_value(name, value, { win = win })
    end
    for name, value in pairs(defaults or {}) do
        vim.api.nvim_set_option_value(name, value, { win = win })
    end
    for name, value in pairs(window.wo) do
        vim.api.nvim_set_option_value(name, value, { win = win })
    end
    if window.winhighlight then
        vim.api.nvim_set_option_value("winhighlight", window.winhighlight.value, { win = win })
    end
    vim.api.nvim_win_set_var(win, M.OWNED_VAR, true)
end

--- Show `line` at the center of the float.
---@param win integer
---@param line integer
local function show_line(win, line)
    local buf = vim.api.nvim_win_get_buf(win)
    line = clamp(line, 0, vim.api.nvim_buf_line_count(buf) - 1)
    vim.api.nvim_win_set_cursor(win, { line + 1, 0 })
    vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zz")
    end)
end

---@param source_win integer
---@param geometry ScrollbarPeekGeometry
---@param window ScrollbarWindowConfig
---@param hidden boolean
---@return table<string, any>
local function float_config(source_win, geometry, window, hidden)
    local result = {}
    for key, value in pairs(window.open) do
        result[key] = value
    end
    result.relative = "win"
    result.win = source_win
    result.row = geometry.row
    result.col = geometry.col
    result.width = geometry.width
    result.height = geometry.height
    result.focusable = false
    result.hide = hidden
    return result
end

--- Close the peek float.
M.close = function()
    local state = current
    current = nil
    if state ~= nil and valid_window(state.win) then
        pcall(vim.api.nvim_win_close, state.win, true)
    end
end

--- Open the peek float at `line` of the buffer of `source_win`, or move the
--- open float there.
---@param source_win integer
---@param line integer Zero-based line
---@param options? ScrollbarPeekOpenOptions
---@return integer? win The float, or nil when the source window has no room for it
M.open = function(source_win, line, options)
    options = options or {}
    local peek_config = config.get_peek()
    local window = peek_config.window
    local position = options.position or peek_config.position
    local source_buf = vim.api.nvim_win_get_buf(source_win)

    local state = current
    if state ~= nil and (state.source_win ~= source_win or not valid_window(state.win)) then
        M.close()
        state = nil
    end

    local win = state and state.win or nil
    if win == nil then
        -- Without a `border` key, the float applies 'winborder', so the sides
        -- are known only after the float opens. It opens hidden.
        local initial = float_config(source_win, { row = 0, col = 0, width = 1, height = 1 }, window, true)
        initial.style = "minimal"
        initial.noautocmd = true
        local ok, opened = pcall(vim.api.nvim_open_win, source_buf, false, initial)
        if not ok then
            vim.notify("[nvim-scrollbar] peek failed: " .. tostring(opened), vim.log.levels.ERROR)
            return nil
        end
        win = opened
        M.configure_window(win, window)
    end
    ---@cast win integer

    local sides = window_config.sides(win)
    local geometry = M._geometry(source_win, position, options.anchor_row, sides, peek_config)
    if geometry == nil then
        pcall(vim.api.nvim_win_close, win, true)
        current = nil
        return nil
    end
    local desired = float_config(source_win, geometry, window, false)
    if window.open.title == nil and sides.top > 0 then
        desired.title = title(source_win, line, options.types)
    end
    vim.api.nvim_win_set_config(win, desired)
    show_line(win, line)
    current = {
        source_win = source_win,
        source_buf = source_buf,
        win = win,
        line = line,
        position = position,
        anchor_row = options.anchor_row,
    }
    return win
end

--- A copy of the state of the open peek float, or nil.
---@return ScrollbarPeekState?
M.get = function()
    if current ~= nil and not valid_window(current.win) then
        current = nil
    end
    return current and vim.deepcopy(current) or nil
end

return M
