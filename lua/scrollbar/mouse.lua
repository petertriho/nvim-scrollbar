--- Scrollbar mouse: the press, drag, and release policy of the scrollbar
--- float. `scrollbar.shared.mouse` owns the runtime, the mappings, focus, and
--- the autohide hold.
---
--- A press reads the hit map of the last render. A press on a mark or the
--- track holds the autohide deadline. A press on the thumb also drags it: the
--- source cursor follows the thumb row, and the thumb shows the pressed
--- highlight until the release. A click on a mark jumps to its line, and a
--- click on the track jumps to the line of the pressed row. On a snacks list,
--- the press and the drag select an item instead of a line.

local layout = require("scrollbar.layout")
local mouse_core = require("scrollbar.shared.mouse")

local M = {}

local clamp = mouse_core.clamp

---@type ScrollbarMouseCore
local core

---@param current ScrollbarInteractionState
---@param pressed boolean
---@param active? ScrollbarMouseCoreRuntime
local function set_handle_pressed(current, pressed, active)
    if active == nil or current.handle_grab_offset == nil or type(active.renderer.set_handle_pressed) ~= "function" then
        return
    end
    pcall(active.renderer.set_handle_pressed, current.float_win, pressed)
end

---@param current ScrollbarInteractionState
---@param row integer
---@return integer
local function track_line(current, row)
    if current.source_kind == "snacks_list" then
        -- The list buffer holds only the visible rows, so the rows map to the
        -- items of the render before the press.
        return layout.row_to_line(row, current.height, current.geometry.total_extent)
    end
    return layout.track_row_to_line(
        current.source_win,
        row,
        current.height,
        current.geometry.unit,
        current.geometry.total_extent
    )
end

---@param current ScrollbarInteractionState
---@param pointer_row integer
---@return integer
local function drag_line(current, pointer_row)
    local handle_height = current.handle.last_row - current.handle.first_row + 1
    local travel = math.max(0, current.height - handle_height)
    local handle_row = clamp(pointer_row - (current.handle_grab_offset or 0), 0, travel)
    local track_row = travel == 0 and 0 or math.floor(handle_row * (current.height - 1) / travel + 0.5)
    return track_line(current, track_row)
end

---@param state ScrollbarWindowState
---@param row integer
---@param col integer
---@param screen_row integer
---@param screen_col integer
---@return ScrollbarInteractionState
local function start(state, row, col, screen_row, screen_col)
    local hit = state.hitmap[row + 1] and state.hitmap[row + 1][col] or { track = false, thumb = false }
    local pressed_handle = hit.thumb == true and state.handle ~= false
    return {
        source_win = state.source_win,
        source_buf = state.source_buf,
        source_kind = state.source_kind,
        float_win = state.float_win,
        float_buf = state.float_buf,
        sides = state.sides,
        pressed_row = row,
        pressed_col = col,
        pressed_screen_row = screen_row,
        pressed_screen_col = screen_col,
        pressed_hit = vim.deepcopy(hit),
        handle = state.handle and vim.deepcopy(state.handle) or false,
        width = state.width,
        height = state.height,
        geometry = vim.deepcopy(state.geometry),
        handle_grab_offset = pressed_handle and row - state.handle.first_row or nil,
        last_row = row,
        last_col = col,
        dragging = false,
        held = hit.line ~= nil or hit.track or hit.thumb,
    }
end

---@param current ScrollbarInteractionState
local function drag(current)
    local state = core.interaction_state(current)
    if state == nil then
        core.cancel()
        return
    end

    local _, row, col, screen_row, screen_col = mouse_core.mouse_position(current.float_win, current.sides)
    row = clamp(row, 0, current.height - 1)
    col = clamp(col, 1, state.width)
    local moved = screen_row ~= current.pressed_screen_row or screen_col ~= current.pressed_screen_col
    if moved and current.handle_grab_offset ~= nil then
        current.dragging = true
        core.navigate(current, drag_line(current, row))
    end
    current.last_row = row
    current.last_col = col
end

---@param current ScrollbarInteractionState
local function release(current)
    if core.interaction_state(current) == nil then
        return
    end

    local _, row = mouse_core.mouse_position(current.float_win, current.sides)
    row = clamp(row, 0, current.height - 1)
    pcall(function()
        if current.dragging then
            core.navigate(current, drag_line(current, row))
        elseif current.pressed_hit.line ~= nil then
            core.navigate(current, current.pressed_hit.line)
        elseif current.pressed_hit.track and not current.pressed_hit.thumb then
            core.navigate(current, track_line(current, current.pressed_row))
        end
    end)
end

---@param current ScrollbarInteractionState
---@param _ ScrollbarWindowState
---@param active ScrollbarMouseCoreRuntime
local function on_press(current, _, active)
    set_handle_pressed(current, true, active)
end

---@param current ScrollbarInteractionState
---@param active? ScrollbarMouseCoreRuntime
local function on_finish(current, active)
    set_handle_pressed(current, false, active)
end

core = mouse_core.new({
    name = "ScrollbarMouse",
    renderer = "scrollbar.renderer",
    scheduler = "scrollbar.scheduler",
    start = start,
    on_press = on_press,
    drag = drag,
    release = release,
    on_finish = on_finish,
})

--- The mouse reads the configuration of each rendered state, so
--- `options.config` has no effect.
---@type fun(options?: ScrollbarMouseOptions)
M.setup = core.setup
M.dispose = core.dispose
---@type fun(float_win?: integer)
M.press = core.press
M.drag = core.drag
M.release = core.release
M.cancel = core.cancel
---@type fun(state: ScrollbarWindowState)
M.attach = core.attach
---@type fun(): ScrollbarInteractionState?
M.get_interaction = core.get_interaction

return M
