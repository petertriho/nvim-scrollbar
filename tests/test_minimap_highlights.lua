local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

T["private base resolution follows links and forces the requested blend"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        require("scrollbar.minimap.config").set({ set_highlights = false })
        local highlights = require("scrollbar.minimap.highlights")
        vim.api.nvim_set_hl(0, "MinimapBaseTarget", { fg = "#abcdef", bg = "#123456", blend = 12 })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapBase", { link = "MinimapBaseTarget" })
        local before = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapBase", link = true })

        highlights.set()
        local resolved = highlights.resolve("ScrollbarMinimapBase", 55, "base")
        return {
            name = resolved,
            definition = vim.api.nvim_get_hl(0, { name = resolved, link = false }),
            before = before,
            after = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapBase", link = true }),
        }
    end)

    expect.no_equality(result.name, "ScrollbarMinimapBase")
    expect.equality(result.definition, { fg = 0xABCDEF, bg = 0x123456, blend = 55 })
    expect.equality(result.after, result.before)
end

T["non-base resolution protects only implicit background blends"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        require("scrollbar.minimap.config").set({ set_highlights = false })
        local highlights = require("scrollbar.minimap.highlights")
        highlights.set()
        vim.api.nvim_set_hl(0, "ImplicitBackground", { fg = "#abcdef", bg = "#123456" })
        vim.api.nvim_set_hl(0, "ForegroundOnly", { fg = "#fedcba", bold = true })
        vim.api.nvim_set_hl(0, "ExplicitBlend", { bg = "#334455", blend = 17 })

        local protected = highlights.resolve("ImplicitBackground", 0, "layer")
        local protected_again = highlights.resolve("ImplicitBackground", 0, "layer")
        local other_blend = highlights.resolve("ImplicitBackground", 40, "layer")
        return {
            protected = protected,
            protected_again = protected_again,
            protected_definition = vim.api.nvim_get_hl(0, { name = protected, link = false }),
            other_blend = other_blend,
            other_definition = vim.api.nvim_get_hl(0, { name = other_blend, link = false }),
            foreground = highlights.resolve("ForegroundOnly", 40, "layer"),
            explicit = highlights.resolve("ExplicitBlend", 40, "layer"),
            explicit_definition = vim.api.nvim_get_hl(0, { name = "ExplicitBlend", link = false }),
        }
    end)

    expect.no_equality(result.protected, "ImplicitBackground")
    expect.equality(result.protected, result.protected_again)
    expect.equality(result.protected_definition, { fg = 0xABCDEF, bg = 0x123456, blend = 0 })
    expect.no_equality(result.other_blend, result.protected)
    expect.equality(result.other_definition, { fg = 0xABCDEF, bg = 0x123456, blend = 40 })
    expect.equality(result.foreground, "ForegroundOnly")
    expect.equality(result.explicit, "ExplicitBlend")
    expect.equality(result.explicit_definition, { bg = 0x334455, blend = 17 })
end

T["ColorScheme refreshes cached private definitions without changing public groups"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        vim.api.nvim_set_hl(0, "ScrollbarMinimapViewport", { bg = "#102030" })
        require("scrollbar").setup({
            scrollbar = { show = false },
            minimap = {
                enabled = true,
                backend = "sync",
                set_highlights = false,
            },
        })
        local highlights = require("scrollbar.minimap.highlights")
        local before_public = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapViewport", link = true })
        local first = highlights.resolve("ScrollbarMinimapViewport", 30, "layer")
        local first_definition = vim.api.nvim_get_hl(0, { name = first, link = false })

        vim.api.nvim_set_hl(0, "ScrollbarMinimapViewport", { bg = "#405060" })
        local changed_public = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapViewport", link = true })
        vim.cmd("doautocmd ColorScheme")
        local second = highlights.resolve("ScrollbarMinimapViewport", 30, "layer")
        return {
            first_definition = first_definition,
            second_definition = vim.api.nvim_get_hl(0, { name = second, link = false }),
            before_public = before_public,
            changed_public = changed_public,
            after_public = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapViewport", link = true }),
        }
    end)

    expect.equality(result.first_definition, { bg = 0x102030, blend = 30 })
    expect.equality(result.second_definition, { bg = 0x405060, blend = 30 })
    expect.no_equality(result.changed_public, result.before_public)
    expect.equality(result.after_public, result.changed_public)
end

return T
