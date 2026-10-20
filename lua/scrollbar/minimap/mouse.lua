--- Minimap mouse: the press, drag, and release policy of the minimap float.
--- `scrollbar.shared.mouse` owns the runtime, the mappings, focus, and the
--- autohide hold.
---
--- A press jumps to the first line of the pressed row, which the projection
--- of the last render gives. A drag is a slider drag: it scrolls the source
--- window so that the viewport band follows the pointer, and it moves the
--- cursor only when the cursor leaves the visible lines. Every press holds
--- the autohide deadline until the interaction ends.
---
--- The minimap scheduler coalesces the frames of a drag. Each `<LeftDrag>`
--- invalidates the source window through the scheduler, and the `throttle_ms`
--- of the scheduler coalesces the flushes that result.

local mouse_core = require("scrollbar.shared.mouse")
local projection_module = require("scrollbar.minimap.projection")

local M = {}

-- Maximum number of scroll corrections for one drag event. Each pass moves the
-- topline, so a few passes reach the target unless folds or wrapped lines
-- stop it.
local MAX_SCROLL_PASSES = 8

---@type ScrollbarMouseCore
local core

---Scroll the current window until its 0-based topline reaches `topline`.
---`CTRL-E` and `CTRL-Y` count a closed fold as one line, so the scroll can
---go past `topline`. A pass that goes past `topline` or does not move ends the
---scroll.
---@param topline integer
local function scroll_current(topline)
    for _ = 1, MAX_SCROLL_PASSES do
        local before = vim.fn.line("w0") - 1
        local delta = topline - before
        if delta == 0 then
            return
        end
        if delta > 0 then
            vim.cmd("normal! " .. delta .. "\5")
        else
            vim.cmd("normal! " .. -delta .. "\25")
        end
        local after = vim.fn.line("w0") - 1
        if after == before or (delta > 0 and after >= topline) or (delta < 0 and after <= topline) then
            return
        end
    end
end

---@param current ScrollbarMinimapMouseInteraction
---@param topline integer 0-based source topline
---@return boolean
local function scroll_to(current, topline)
    if not mouse_core.valid_source(current) then
        return false
    end
    local ok = pcall(vim.api.nvim_win_call, current.source_win, function()
        scroll_current(topline)
    end)
    if ok then
        core.invalidate(current)
    end
    return ok
end

---@param source_win integer
---@return integer topline 0-based
local function source_topline(source_win)
    return vim.api.nvim_win_call(source_win, function()
        return vim.fn.line("w0") - 1
    end)
end

---@param state ScrollbarMinimapRendererState
---@param row integer
---@return ScrollbarMinimapMouseInteraction?
local function start(state, row)
    if state.projection == nil then
        return nil
    end
    return {
        source_win = state.source_win,
        source_buf = state.source_buf,
        float_win = state.float_win,
        float_buf = state.float_buf,
        height = state.height,
        width = state.width,
        projection = state.projection,
        pressed_row = row,
        pressed_topline = 0,
        dragging = false,
        held = true,
    }
end

---@param current ScrollbarMinimapMouseInteraction
local function on_press(current)
    core.navigate(current, projection_module.row_line(current.projection, current.pressed_row))
    current.pressed_topline = source_topline(current.source_win)
end

---Scroll the source so that the band moves by the rows that the pointer
---moved since the press. The pointer can leave the float. The topline clamps
---at the ends of the buffer.
---@param current ScrollbarMinimapMouseInteraction
local function drag(current)
    if not mouse_core.valid_window(current.float_win) then
        core.cancel()
        return
    end
    local _, row = mouse_core.mouse_position(current.float_win)
    current.dragging = true
    scroll_to(
        current,
        projection_module.drag_topline(current.projection, current.pressed_topline, row - current.pressed_row)
    )
end

---@param current ScrollbarMinimapMouseInteraction
local function release(current)
    if current.dragging or not mouse_core.valid_window(current.float_win) then
        return
    end
    local _, row = mouse_core.mouse_position(current.float_win)
    row = mouse_core.clamp(row, 0, current.height - 1)
    core.navigate(current, projection_module.row_line(current.projection, row))
end

core = mouse_core.new({
    name = "ScrollbarMinimapMouse",
    renderer = "scrollbar.minimap.renderer",
    scheduler = "scrollbar.minimap.scheduler",
    start = start,
    on_press = on_press,
    drag = drag,
    release = release,
})

---@type fun(options?: ScrollbarMinimapMouseOptions)
M.setup = core.setup
M.dispose = core.dispose
---@type fun(float_win?: integer)
M.press = core.press
M.drag = core.drag
M.release = core.release
M.cancel = core.cancel
---@type fun(state: ScrollbarMinimapRendererState)
M.attach = core.attach
---@type fun(): ScrollbarMinimapMouseInteraction?
M.get_interaction = core.get_interaction

return M
