--- Hover peek: when the pointer rests on a mark cell of a scrollbar float for
--- `scrollbar.hover.delay_ms`, the peek float opens at the line of the cell.
---
--- - Hover acts on the scrollbar floats whose `mouse` option is true, on
---   normal windows and on float sources. It does nothing during label mode,
---   and it sets no labels.
--- - The hover peek closes when the pointer leaves the cell, on any key that
---   is not `<MouseMove>`, and when the source window scrolls.
--- - Neovim sends `<MouseMove>` only with 'mousemoveevent'. The setup sets the
---   option. The dispose restores it only when the setup set it.

local jump = require("scrollbar.navigate.jump")
local peek = require("scrollbar.navigate.peek")
local targets = require("scrollbar.navigate.targets")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarHover")
local AUGROUP = "ScrollbarHover"
local MOUSE_MOVE = vim.keycode("<MouseMove>")

---@class ScrollbarHoverSpot
---@field source_win integer
---@field row integer Zero-based row of the float content
---@field col integer One-based first column of the cell
---@field line integer
---@field topline integer One-based first line of the source window when the pointer came to the cell
---@field leftcol integer

---@class ScrollbarHoverRuntime
---@field delay_ms integer
---@field set_option boolean Whether the setup turned on 'mousemoveevent'
---@field timer? any
---@field pending? ScrollbarHoverSpot Spot that the timer opens
---@field shown? ScrollbarHoverSpot Spot of the open hover peek
---@field scheduled boolean Whether a pointer check waits in the event loop
---@field augroup integer

---@type ScrollbarHoverRuntime?
local runtime

---@param left? ScrollbarHoverSpot
---@param right? ScrollbarHoverSpot
---@return boolean
local function same_spot(left, right)
    -- The view is not part of the spot: a scroll closes the peek by the
    -- `WinScrolled` rule, not by a pointer check.
    return left ~= nil
        and right ~= nil
        and left.source_win == right.source_win
        and left.row == right.row
        and left.col == right.col
        and left.line == right.line
end

---@param active ScrollbarHoverRuntime
local function stop_timer(active)
    active.pending = nil
    if active.timer ~= nil then
        active.timer:stop()
        if not active.timer:is_closing() then
            active.timer:close()
        end
        active.timer = nil
    end
end

--- Close the hover peek and stop the timer. A peek of label mode stays.
---@param active ScrollbarHoverRuntime
local function hide(active)
    stop_timer(active)
    local shown = active.shown
    active.shown = nil
    if shown == nil or jump.active() then
        return
    end
    local open = peek.get()
    if open ~= nil and open.source_win == shown.source_win and open.line == shown.line then
        peek.close()
    end
end

--- The spot under the pointer, and the anchor row of its peek.
---@return ScrollbarHoverSpot?
---@return integer? anchor_row
local function spot_under_pointer()
    local renderer = package.loaded["scrollbar.renderer"]
    if renderer == nil then
        return nil
    end
    local mouse = vim.fn.getmousepos()
    local state = renderer.get_state_by_float(mouse.winid)
    if state == nil or not state.config.mouse then
        return nil
    end
    local row = mouse.winrow - 1 - state.sides.top
    local col = mouse.wincol - state.sides.left
    local cell = targets.cell_at(state.source_win, row, col)
    if cell == nil then
        return nil
    end
    local view = vim.api.nvim_win_call(state.source_win, vim.fn.winsaveview)
    return {
        source_win = state.source_win,
        row = cell.row,
        col = cell.col,
        line = cell.line,
        topline = view.topline,
        leftcol = view.leftcol,
    },
        state.config.placement.row + state.sides.top + cell.row
end

--- Whether the source window of `spot` scrolled since the pointer came to the
--- cell.
---@param spot ScrollbarHoverSpot
---@return boolean
local function scrolled(spot)
    if not vim.api.nvim_win_is_valid(spot.source_win) then
        return true
    end
    local view = vim.api.nvim_win_call(spot.source_win, vim.fn.winsaveview)
    return view.topline ~= spot.topline or view.leftcol ~= spot.leftcol
end

---@param active ScrollbarHoverRuntime
local function check_pointer(active)
    if jump.active() then
        hide(active)
        return
    end
    local spot = spot_under_pointer()
    if spot == nil then
        hide(active)
        return
    end
    if same_spot(spot, active.shown) or same_spot(spot, active.pending) then
        return
    end
    hide(active)
    active.pending = spot
    local timer = assert(vim.uv.new_timer())
    active.timer = timer
    timer:start(
        active.delay_ms,
        0,
        vim.schedule_wrap(function()
            if runtime ~= active or active.timer ~= timer then
                return
            end
            stop_timer(active)
            if jump.active() then
                return
            end
            -- The pointer must still rest on the cell, and the cell must
            -- still show the same mark.
            local current, anchor_row = spot_under_pointer()
            if not same_spot(current, spot) then
                return
            end
            local ok = pcall(peek.open, spot.source_win, spot.line, { anchor_row = anchor_row })
            if ok then
                active.shown = spot
            end
        end)
    )
end

---@param active ScrollbarHoverRuntime
---@param key string
---@param typed string
local function on_key(active, key, typed)
    if key == MOUSE_MOVE or typed == MOUSE_MOVE then
        if not active.scheduled then
            active.scheduled = true
            vim.schedule(function()
                active.scheduled = false
                if runtime == active then
                    check_pointer(active)
                end
            end)
        end
    elseif active.shown ~= nil or active.pending ~= nil then
        vim.schedule(function()
            if runtime == active then
                hide(active)
            end
        end)
    end
end

--- Start hover. A `false` configuration only disposes the old runtime.
---@param hover_config false|ScrollbarHoverConfig
M.setup = function(hover_config)
    M.dispose()
    if hover_config == false then
        return
    end
    local set_option = not vim.o.mousemoveevent
    if set_option then
        vim.o.mousemoveevent = true
    end
    ---@type ScrollbarHoverRuntime
    local active = {
        delay_ms = hover_config.delay_ms,
        set_option = set_option,
        scheduled = false,
        augroup = vim.api.nvim_create_augroup(AUGROUP, { clear = true }),
    }
    runtime = active
    vim.on_key(function(key, typed)
        on_key(active, key, typed or "")
    end, NAMESPACE)
    vim.api.nvim_create_autocmd("WinScrolled", {
        group = active.augroup,
        callback = function()
            local spot = active.shown or active.pending
            if spot ~= nil and scrolled(spot) then
                hide(active)
            end
        end,
    })
end

--- Stop hover, close the hover peek, and restore 'mousemoveevent' when the
--- setup set it.
M.dispose = function()
    local active = runtime
    if active == nil then
        return
    end
    hide(active)
    runtime = nil
    vim.on_key(nil, NAMESPACE)
    pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
    if active.set_option then
        vim.o.mousemoveevent = false
    end
end

--- The spot of the open hover peek, for tests.
---@return ScrollbarHoverSpot?
M.shown = function()
    return runtime and runtime.shown and vim.deepcopy(runtime.shown) or nil
end

return M
