--- Arrangement of the scrollbar float and the minimap float that share one
--- side of a source window. Each renderer publishes a footprint for each
--- source window and resolves its own origin and z-index against the
--- footprint of the other renderer. `minimap.placement.stack` selects the
--- arrangement:
---
--- - `inner`: side by side. The scrollbar is the outer float at the window
---   edge, and the minimap starts at its inward edge.
--- - `outer`: side by side. The minimap is the outer float.
--- - `above` and `below`: the floats overlap. If both configured z-indexes are
---   equal, the bottom float drops by one. If the value is 1, the top float
---   rises by one instead. Different explicit z-indexes always win.
---
--- On a floating source window, the base z-index of both floats is the
--- z-index of the source + 1, and `placement.zindex` does not apply. An
--- overlap resolves upward: the bottom float keeps the base, and the top float
--- gets the base + 1. Thus neither float drops under its source.
---
--- A renderer keeps its footprint while its float is hidden for a short time
--- (cursor overlap, autohide), so the other float keeps its position. For a
--- lasting hide, the renderer removes the footprint, and the other float moves
--- back to its own origin.

local M = {}

---@alias ScrollbarStackRenderer "scrollbar"|"minimap"

---@class ScrollbarStackPlacement
---@field relative ScrollbarPlacementRelative
---@field side "E"|"W"
---@field zindex integer Configured `placement.zindex`, or the base z-index above a floating source window
---@field float? boolean Whether the source window is a float
---@field stack? ScrollbarMinimapStack Minimap only

---@class ScrollbarStackFootprint: ScrollbarStackPlacement
---@field origin integer Column that `col` applies to, without stacking
---@field col integer Configured `placement.col`
---@field width integer Rendered width, or the declared width before the first render

---@type table<ScrollbarStackRenderer, table<integer, ScrollbarStackFootprint>>
local footprints = { scrollbar = {}, minimap = {} }

---@type table<ScrollbarStackRenderer, fun(source_win: integer)>
local repositioners = {}

local notifying = false

local OTHER = { scrollbar = "minimap", minimap = "scrollbar" }
local FIELDS = { "relative", "side", "origin", "col", "width", "zindex", "float", "stack" }

-- The z-index of a float when `nvim_win_get_config` gives none.
local DEFAULT_ZINDEX = 50

---@param left? ScrollbarStackFootprint
---@param right? ScrollbarStackFootprint
---@return boolean
local function same_footprint(left, right)
    if left == right then
        return true
    end
    if left == nil or right == nil then
        return left == right
    end
    for _, field in ipairs(FIELDS) do
        if left[field] ~= right[field] then
            return false
        end
    end
    return true
end

---@param footprint ScrollbarStackFootprint
---@return integer
local function inward_edge(footprint)
    if footprint.side == "W" then
        return footprint.origin + footprint.col + footprint.width
    end
    return footprint.origin + footprint.col - footprint.width
end

---@param renderer ScrollbarStackRenderer
---@param source_win integer
local function notify(renderer, source_win)
    local reposition = repositioners[OTHER[renderer]]
    if reposition == nil or notifying then
        return
    end
    notifying = true
    -- A failed reposition leaves the other float in place until its next
    -- render, which resolves the position again.
    pcall(reposition, source_win)
    notifying = false
end

--- Store the footprint of one renderer for one source window. `nil` removes
--- it. A change repositions the float of the other renderer at once.
---@param renderer ScrollbarStackRenderer
---@param source_win integer
---@param footprint? ScrollbarStackFootprint
---@param options? { notify?: boolean } `notify = false` skips the reposition, for a closing window
M.publish = function(renderer, source_win, footprint, options)
    local current = footprints[renderer][source_win]
    if same_footprint(current, footprint) then
        return
    end
    footprints[renderer][source_win] = footprint
    if options == nil or options.notify ~= false then
        notify(renderer, source_win)
    end
end

--- Resolve the origin and the effective z-index of the float of one renderer.
---@param renderer ScrollbarStackRenderer
---@param source_win integer
---@param own ScrollbarStackPlacement
---@return integer? origin Inward edge of the outer float, or nil when the float keeps its own origin
---@return integer zindex
M.resolve = function(renderer, source_win, own)
    local other = footprints[OTHER[renderer]][source_win]
    if other == nil or other.relative ~= own.relative or other.side ~= own.side then
        return nil, own.zindex
    end

    local stack = renderer == "minimap" and own.stack or other.stack
    if stack == "inner" or stack == "outer" then
        local inner = stack == "inner" and "minimap" or "scrollbar"
        if renderer == inner then
            return inward_edge(other), own.zindex
        end
        return nil, own.zindex
    end

    if own.zindex ~= other.zindex then
        return nil, own.zindex
    end
    local top = stack == "above" and "minimap" or "scrollbar"
    if own.float then
        return nil, renderer == top and own.zindex + 1 or own.zindex
    end
    if renderer == top then
        return nil, own.zindex == 1 and 2 or own.zindex
    end
    return nil, own.zindex == 1 and 1 or own.zindex - 1
end

--- The base z-index of a float above a floating source window: the z-index of
--- the source + 1.
---@param source_win integer
---@return integer
M.float_zindex = function(source_win)
    local ok, window_config = pcall(vim.api.nvim_win_get_config, source_win)
    local zindex = ok and window_config.zindex or nil
    return (type(zindex) == "number" and zindex or DEFAULT_ZINDEX) + 1
end

---@param renderer ScrollbarStackRenderer
---@param source_win integer
---@return ScrollbarStackFootprint?
M.footprint = function(renderer, source_win)
    return footprints[renderer][source_win]
end

---@param renderer ScrollbarStackRenderer
---@return integer[]
M.windows = function(renderer)
    local result = {}
    for source_win in pairs(footprints[renderer]) do
        result[#result + 1] = source_win
    end
    return result
end

--- Remove every footprint of one renderer and reposition the other floats.
---@param renderer ScrollbarStackRenderer
M.clear = function(renderer)
    for _, source_win in ipairs(M.windows(renderer)) do
        M.publish(renderer, source_win, nil)
    end
end

---@param renderer ScrollbarStackRenderer
---@param reposition? fun(source_win: integer)
M.register = function(renderer, reposition)
    repositioners[renderer] = reposition
end

M.reset = function()
    footprints = { scrollbar = {}, minimap = {} }
    repositioners = {}
    notifying = false
end

return M
