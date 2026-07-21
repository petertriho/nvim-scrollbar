local config = require("scrollbar.minimap.config")
local utils = require("scrollbar.utils")

local M = {}
local PREFIX = "ScrollbarMinimap"
local GENERATED_PREFIX = PREFIX .. "Generated."

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

M.set = function()
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

return M
