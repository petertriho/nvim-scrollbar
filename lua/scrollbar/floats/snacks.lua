--- Adapter of the snacks.nvim picker list. The list is virtual: its buffer
--- holds only the visible rows, and `List:render` resets `topline` to 1. So
--- the scrollbar reads the list position from the list object, not from the
--- window. The adapter reads private fields of snacks (`list.top`,
--- `list.state.height`, `list.reverse`, and `List.render`). A missing field
--- gives no view, and the scrollbar then shows no bar on the list.

local float_kinds = require("scrollbar.shared.float_kinds")

local M = {}

-- Field on the `List` class of snacks that keeps the original `render` and the
-- current callback. The field outlives a reload of this module, so the method
-- is wrapped only once.
local HOOK_FIELD = "__nvim_scrollbar"

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

---@class ScrollbarSnacksListView
---@field count integer Item count, at least 1. An empty list counts as one item
---@field top integer Zero-based first visible item in visual order
---@field bottom integer Zero-based last visible item in visual order
---@field reverse boolean Whether item 1 is on the bottom row

---@param list table
---@return integer?
local function item_count(list)
    if type(list.count) ~= "function" then
        return nil
    end
    local ok, count = pcall(list.count, list)
    if not ok or not is_integer(count) then
        return nil
    end
    return count
end

--- The visible items of the list in `winid`. In a reversed list, item 1 is on
--- the bottom row, so the view mirrors the positions into visual order.
---@param winid integer
---@return ScrollbarSnacksListView?
M.view = function(winid)
    local list = float_kinds.snacks_list(winid)
    if list == nil then
        return nil
    end
    local count = item_count(list)
    local top = list.top
    local state = list.state
    local height = type(state) == "table" and state.height or nil
    if count == nil or not is_integer(top) or not is_integer(height) then
        return nil
    end

    local reverse = list.reverse == true
    count = math.max(1, count)
    local first = math.max(0, math.min(top - 1, count - 1))
    local last = math.max(first, math.min(top + height - 2, count - 1))
    if reverse then
        first, last = count - 1 - last, count - 1 - first
    end
    return { count = count, top = first, bottom = last, reverse = reverse }
end

--- Select the item at the zero-based visual position `line`. `List:move`
--- takes a visual position and mirrors a reversed list itself, so the
--- selection and the preview follow the bar in both orders.
---@param winid integer
---@param line integer
---@return boolean moved
M.navigate = function(winid, line)
    local list = float_kinds.snacks_list(winid)
    if list == nil or type(list.move) ~= "function" then
        return false
    end
    local count = item_count(list)
    if count == nil or count < 1 then
        return false
    end
    local position = math.max(0, math.min(line, count - 1)) + 1
    return (pcall(list.move, list, position, true))
end

--- Wrap `List.render` once, so that each render of a list calls `on_render`
--- with the list window. The wrapper calls the original first. A later call
--- replaces the callback. The function does nothing when snacks has not
--- loaded the list module or when the module has no `render` method.
---@param on_render fun(winid: integer)
---@return boolean installed
M.install = function(on_render)
    local List = package.loaded["snacks.picker.core.list"]
    if type(List) ~= "table" then
        return false
    end
    local hook = rawget(List, HOOK_FIELD)
    if type(hook) ~= "table" then
        local original = rawget(List, "render")
        if type(original) ~= "function" then
            return false
        end
        hook = { render = original }
        rawset(List, HOOK_FIELD, hook)
        List.render = function(self, ...)
            local results = vim.F.pack_len(original(self, ...))
            local callback = hook.on_render
            local win = type(self) == "table" and type(self.win) == "table" and self.win.win or nil
            if callback ~= nil and type(win) == "number" then
                -- A failed callback must not break the picker. The next render
                -- of the scrollbar corrects the bar.
                pcall(callback, win)
            end
            return vim.F.unpack_len(results)
        end
    end
    hook.on_render = on_render
    return true
end

return M
