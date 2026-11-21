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
local frame = require("scrollbar.navigate.frame")
local targets = require("scrollbar.navigate.targets")
local window_config = require("scrollbar.config.window")

local M = {}

--- Window variable of the peek float and the glance panes. The source policy
--- reads it.
M.OWNED_VAR = "scrollbar_navigate_owned"

local AUGROUP = "ScrollbarPeek"

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
---@field anchor_row? integer

---@type ScrollbarPeekState?
local current

-- The options of the last open call. A resize opens the float again with
-- them. They stay out of the state, because a frame function cannot leave
-- the process in a copy of the state.
---@type ScrollbarPeekOpenOptions?
local current_options

---@class ScrollbarPeekOpenOptions
---@field frame? ScrollbarFrameValue Default: `peek.frame`
---@field anchor_row? integer Zero-based text row of the source window that a `"scrollbar"` frame centers on. Default: the cursor row
---@field types? table<string, true> Mark types that the title names. Nil names every type except `Cursor`
---@field free_col? integer Zero-based column of the source window that a `"scrollbar"` frame does not cover, for the labels beside the scrollbar

---@param winid? integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
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
    line = frame.clamp(line, 0, vim.api.nvim_buf_line_count(buf) - 1)
    vim.api.nvim_win_set_cursor(win, { line + 1, 0 })
    vim.api.nvim_win_call(win, function()
        vim.cmd("normal! zz")
    end)
end

--- The configuration of the float in `placed`, a frame with its border.
---@param source_win integer
---@param placed ScrollbarFrame
---@param sides ScrollbarWindowSides
---@param window ScrollbarWindowConfig
---@param hidden boolean
---@return table<string, any>
local function float_config(source_win, placed, sides, window, hidden)
    local result = {}
    for key, value in pairs(window.open) do
        result[key] = value
    end
    frame.apply_position(placed, source_win, result)
    result.width = placed.width - sides.left - sides.right
    result.height = placed.height - sides.top - sides.bottom
    result.focusable = false
    result.hide = hidden
    return result
end

local HIDDEN_FRAME = { relative = "win", row = 0, col = 0, width = 1, height = 1 }
local NO_SIDES = { top = 0, right = 0, bottom = 0, left = 0 }

--- Close the peek float.
M.close = function()
    local state = current
    current = nil
    current_options = nil
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
    if state ~= nil and valid_window(state.win) then
        pcall(vim.api.nvim_win_close, state.win, true)
    end
end

--- Open the float again with the options of the last open call, after a
--- resize. The float closes when the frame no longer fits.
local function relayout()
    local state = current
    if state == nil then
        return
    end
    if not valid_window(state.win) or not valid_window(state.source_win) then
        M.close()
        return
    end
    M.open(state.source_win, state.line, current_options)
end

local function watch()
    local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
    frame.on_resize(group, function()
        return current and current.source_win or nil
    end, relayout)
end

--- Open the peek float at `line` of the buffer of `source_win`, or move the
--- open float there.
---@param source_win integer
---@param line integer Zero-based line
---@param options? ScrollbarPeekOpenOptions
---@return integer? win The float, or nil when the source window has no room for it or the frame failed
M.open = function(source_win, line, options)
    options = options or {}
    local peek_config = config.get_peek()
    local window = peek_config.window
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
        local initial = float_config(source_win, HIDDEN_FRAME, NO_SIDES, window, true)
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
    local placed = frame.layout("peek", "peek.frame", options.frame or peek_config.frame, source_win, sides, {
        anchor_row = options.anchor_row,
        free_col = options.free_col,
    })
    if placed == nil or placed.width - sides.left - sides.right < 1 or placed.height - sides.top - sides.bottom < 1 then
        pcall(vim.api.nvim_win_close, win, true)
        M.close()
        return nil
    end
    local desired = float_config(source_win, placed, sides, window, false)
    if window.open.title == nil and sides.top > 0 then
        desired.title = title(source_win, line, options.types)
    end
    vim.api.nvim_win_set_config(win, desired)
    show_line(win, line)
    if current == nil then
        watch()
    end
    current = {
        source_win = source_win,
        source_buf = source_buf,
        win = win,
        line = line,
        anchor_row = options.anchor_row,
    }
    current_options = options
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
