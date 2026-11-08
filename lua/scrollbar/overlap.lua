--- How the scrollbar shares the screen cells with the text of its source
--- window. The blend rules give each generated group an explicit `blend`, and
--- the reservation keeps the text away from an east scrollbar.
---
--- Neovim blends the cells of a float only when the float has `'winblend'`
--- greater than zero. A cell then takes the `blend` of its highlight group, or
--- else the `'winblend'` of the float. A space cell with a blend shows the
--- character of the window below it. Every generated group has an explicit
--- `blend`, so the `'winblend'` of the float only turns blending on.
---
--- The reservation sets two window-local options of the source window. In a
--- window without 'wrap', 'sidescrolloff' keeps the cursor out of the columns
--- under the scrollbar. In a window with 'wrap', 'wrapcolumn' wraps the text
--- before the scrollbar. Neovim releases without 'wrapcolumn' have only the
--- 'sidescrolloff' part. The reservation keeps the original values and
--- restores them only when the current value is still the applied value, so an
--- edit of the user wins.

local M = {}

-- The group of a cleared row. A space with blend 100 shows the cell below it
-- with its own colors.
M.CLEAR_GROUP = "ScrollbarGenerated.Clear"

-- Neovim drops a group that sets only `blend`, because the group has no
-- attribute that changes a cell. The special color keeps the group. It does
-- not change a cell: Neovim draws it only for an underline style, and a
-- blended cell that shows the text below takes the special color of the text.
local ANCHOR_SP = "#000000"

---A definition that changes only the blend of a cell.
---@param blend integer
---@return vim.api.keyset.highlight
M.blend_only = function(blend)
    return { blend = blend, sp = ANCHOR_SP }
end

---Add the blend to a definition. A definition without colors gets the
---special color that keeps the group.
---@param definition vim.api.keyset.highlight
---@param blend integer
---@return vim.api.keyset.highlight
M.with_blend = function(definition, blend)
    if definition.blend == nil then
        definition.blend = blend
    end
    if definition.fg == nil and definition.bg == nil and definition.sp == nil and definition.link == nil then
        definition.sp = ANCHOR_SP
    end
    return definition
end

local WRAPCOLUMN_SUPPORTED = pcall(vim.api.nvim_get_option_info2, "wrapcolumn", {})

---@return boolean
M.wrapcolumn_supported = function()
    return WRAPCOLUMN_SUPPORTED
end

---@param active_config ScrollbarConfig
---@return integer? winblend The `winblend` of `window.wo`, or nil
local function window_winblend(active_config)
    local value = active_config.window.wo.winblend
    if type(value) == "number" then
        return value
    end
    return nil
end

---The blend of the track and the tint marks.
---@param active_config ScrollbarConfig
---@return integer
M.surface_blend = function(active_config)
    local show_through = active_config.overlap.show_through
    if show_through then
        return show_through
    end
    return window_winblend(active_config) or 0
end

---The blend of the base, the group of the undeclared cells. With
---`show_through`, the base does not cover the text.
---@param active_config ScrollbarConfig
---@return integer
M.base_blend = function(active_config)
    if active_config.overlap.show_through then
        return 100
    end
    return window_winblend(active_config) or 0
end

---The blend of the thumb. With `show_through`, the text shows through the
---thumb at least as much as through the track.
---@param active_config ScrollbarConfig
---@return integer
M.thumb_blend = function(active_config)
    local show_through = active_config.overlap.show_through
    if show_through then
        return math.max(active_config.thumb.blend, show_through)
    end
    return active_config.thumb.blend
end

---The `winblend` of the float. A `winblend` in `window.wo` wins, because
---`wo` applies last. Otherwise, the value is 0 when no cell blends, so Neovim
---does not blend the float. The groups set their own blend, so a value of 1
---only turns blending on. With `show_through`, a group without its own blend,
---such as a public group that a colorscheme defines, also shows the text.
---@param active_config ScrollbarConfig
---@return integer
M.float_winblend = function(active_config)
    local configured = window_winblend(active_config)
    if configured ~= nil then
        return configured
    end
    local show_through = active_config.overlap.show_through
    if show_through then
        return show_through
    end
    if active_config.thumb.blend > 0 or active_config.hide_on_cursor == "row" then
        return 1
    end
    return 0
end

---@class ScrollbarTextReservation
---@field option string The window-local option that the reservation sets
---@field original integer The local value before the reservation
---@field applied integer The value that the reservation set

---@type table<integer, ScrollbarTextReservation>
local reservations = {}

M.reservations = reservations

-- Every render of an east scrollbar reads these options, so the calls reuse
-- their option tables. The API copies a table, so a reuse is safe.
local LOCAL_OPTIONS = { scope = "local", win = 0 }
local WINDOW_OPTIONS = { win = 0 }
local GLOBAL_OPTIONS = { scope = "global" }

---@param winid integer
---@param name string
---@return integer
local function local_value(winid, name)
    LOCAL_OPTIONS.win = winid
    return vim.api.nvim_get_option_value(name, LOCAL_OPTIONS)
end

---@param winid integer
---@param name string
---@param value integer
local function set_local_value(winid, name, value)
    LOCAL_OPTIONS.win = winid
    vim.api.nvim_set_option_value(name, value, LOCAL_OPTIONS)
end

---@param source_win integer
M.release = function(source_win)
    local reservation = reservations[source_win]
    reservations[source_win] = nil
    if reservation == nil or not vim.api.nvim_win_is_valid(source_win) then
        return
    end
    if local_value(source_win, reservation.option) == reservation.applied then
        set_local_value(source_win, reservation.option, reservation.original)
    end
end

---The value of the reservation option for `width` columns under the
---scrollbar, from the original local value of the option.
---@param option string
---@param original integer
---@param width integer
---@param text_width integer
---@return integer? value Nil when the option needs no change
local function reserved_value(option, original, width, text_width)
    if option == "sidescrolloff" then
        local effective = original >= 0 and original or vim.api.nvim_get_option_value("sidescrolloff", GLOBAL_OPTIONS)
        if effective >= width then
            return nil
        end
        return width
    end
    local limit = text_width - width
    if limit < 1 or (original > 0 and original <= limit) then
        return nil
    end
    return limit
end

---Reserve `width` columns at the right edge of the text area. A width of 0
---releases the reservation.
---@param source_win integer
---@param width integer Text columns that the scrollbar covers at the right edge
---@param text_width integer Columns of the text area, without the gutter
---@return boolean changed Whether the call changed the 'wrapcolumn' of the window
M.reserve = function(source_win, width, text_width)
    if width <= 0 and reservations[source_win] == nil then
        return false
    end
    WINDOW_OPTIONS.win = source_win
    local wrap = vim.api.nvim_get_option_value("wrap", WINDOW_OPTIONS)
    local option = wrap and "wrapcolumn" or "sidescrolloff"
    local changed = false

    ---@type ScrollbarTextReservation?
    local reservation = reservations[source_win]
    if
        reservation ~= nil
        and (
            width <= 0
            or reservation.option ~= option
            or local_value(source_win, reservation.option) ~= reservation.applied
        )
    then
        -- The reservation ends, 'wrap' changed, or the user edited the option.
        -- An edit of the user becomes the new original value.
        changed = reservation.option == "wrapcolumn"
        M.release(source_win)
        reservation = nil
    end
    if width <= 0 or (option == "wrapcolumn" and not WRAPCOLUMN_SUPPORTED) then
        return changed
    end

    local original = reservation and reservation.original or local_value(source_win, option)
    local value = reserved_value(option, original, width, text_width)
    if value == nil then
        if reservation ~= nil then
            M.release(source_win)
            return changed or option == "wrapcolumn"
        end
        return changed
    end
    if reservation ~= nil and reservation.applied == value then
        return changed
    end
    set_local_value(source_win, option, value)
    reservations[source_win] = { option = option, original = original, applied = value }
    return changed or option == "wrapcolumn"
end

return M
