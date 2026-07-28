local config = require("scrollbar.minimap.config")
local utils = require("scrollbar.utils")

local M = {}
local PREFIX = "ScrollbarMinimap"
local GENERATED_PREFIX = PREFIX .. "Generated."
local RESOLVED_PREFIX = PREFIX .. "Resolved."
local resolved_cache = {}
local resolved_count = 0

local function definition(source)
    if type(source) == "table" then
        return vim.deepcopy(source)
    end
    return {
        fg = utils.highlight_to_hex_color(source, "foreground", "Normal", "#000000"),
    }
end

local function generated_name(public_name)
    return GENERATED_PREFIX .. public_name:sub(#PREFIX + 1)
end

local function set_default_link(name, target)
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
end

local function reset_resolved()
    resolved_cache = {}
    resolved_count = 0
end

local function resolved_definition(source)
    local ok, resolved = pcall(vim.api.nvim_get_hl, 0, { name = source, link = false })
    if not ok or type(resolved) ~= "table" then
        return {}
    end
    return vim.deepcopy(resolved)
end

local function resolved_name(mode)
    resolved_count = resolved_count + 1
    return string.format("%s%s%d", RESOLVED_PREFIX, mode == "base" and "Base" or "Layer", resolved_count)
end

M.set = function()
    reset_resolved()
    local root = config.get()
    if not root.set_highlights then
        return
    end

    set_default_link("ScrollbarMinimapBase", "NormalFloat")
    set_default_link("ScrollbarMinimapContent", "Comment")
    set_default_link("ScrollbarMinimapViewport", "CursorLine")
    set_default_link("ScrollbarMinimapCursor", "Cursor")

    for _, variant in ipairs(config.get_variants()) do
        for _, spec in pairs(variant.config.overlays.types) do
            local resolved = definition(spec.highlight)
            if variant.id == 0 then
                local private_name = generated_name(spec.group)
                vim.api.nvim_set_hl(0, private_name, resolved)
                set_default_link(spec.group, private_name)
            else
                vim.api.nvim_set_hl(0, spec.group, resolved)
            end
        end
    end
end

---@param source string
---@param blend integer
---@param mode "base"|"layer"
---@return string
M.resolve = function(source, blend, mode)
    assert(mode == "base" or mode == "layer", "invalid minimap highlight resolution mode")

    local by_mode = resolved_cache[mode]
    if by_mode == nil then
        by_mode = {}
        resolved_cache[mode] = by_mode
    end
    local by_blend = by_mode[blend]
    if by_blend == nil then
        by_blend = {}
        by_mode[blend] = by_blend
    end
    if by_blend[source] ~= nil then
        return by_blend[source]
    end

    local resolved = resolved_definition(source)
    if mode == "layer" and (resolved.bg == nil or resolved.blend ~= nil) then
        by_blend[source] = source
        return source
    end

    resolved.blend = blend
    local name = resolved_name(mode)
    vim.api.nvim_set_hl(0, name, resolved)
    by_blend[source] = name
    return name
end

return M
