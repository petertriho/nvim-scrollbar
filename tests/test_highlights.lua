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

local function base_config(overrides)
    return vim.tbl_deep_extend("force", {
        show = false,
        set_highlights = true,
        mouse = { enabled = false },
        providers = {
            cursor = false,
            diagnostic = false,
            search = false,
            marks = false,
            gitsigns = false,
            mini_diff = false,
            signify = false,
            vgit = false,
            ale = false,
            coc = false,
        },
    }, overrides or {})
end

T["generates canonical Thumb groups transparent base and equivalent Handle aliases"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_set_hl(0, "Special", { fg = "#abcdef" })
        vim.api.nvim_set_hl(0, "PmenuSbar", { bg = "#112233" })
        vim.api.nvim_set_hl(0, "PmenuThumb", { bg = "#445566" })
        vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#778899" })
        require("scrollbar").setup(config)
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        return {
            base = get("ScrollbarBase"),
            track = get("ScrollbarTrack"),
            thumb = get("ScrollbarThumb"),
            thumb_pressed = get("ScrollbarThumbPressed"),
            mark = get("ScrollbarMark"),
            overlap = get("ScrollbarMarkThumb"),
            overlap_pressed = get("ScrollbarMarkThumbPressed"),
            legacy_thumb = get("ScrollbarHandle"),
            legacy_thumb_pressed = get("ScrollbarHandlePressed"),
            legacy_overlap = get("ScrollbarMarkHandle"),
            legacy_overlap_pressed = get("ScrollbarMarkHandlePressed"),
        }
    end, base_config())

    expect.equality(result.base, {})
    expect.equality(result.track, { bg = 0x112233 })
    expect.equality(result.thumb, { bg = 0x445566, blend = 30 })
    expect.equality(result.thumb_pressed, { bg = 0x778899, blend = 30 })
    expect.equality(result.mark, { fg = 0xABCDEF })
    expect.equality(result.overlap, { fg = 0xABCDEF, bg = 0x445566, blend = 30 })
    expect.equality(result.overlap_pressed, { fg = 0xABCDEF, bg = 0x778899, blend = 30 })
    expect.equality(result.legacy_thumb, result.thumb)
    expect.equality(result.legacy_thumb_pressed, result.thumb_pressed)
    expect.equality(result.legacy_overlap, result.overlap)
    expect.equality(result.legacy_overlap_pressed, result.overlap_pressed)
end

T["applies full highlight tables and projects string sources by channel"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            vim.api.nvim_set_hl(0, "DirectTrackSource", { fg = "#030303", bg = "#234567", italic = true })
            vim.api.nvim_set_hl(0, "DirectThumbSource", { fg = "#010101", bg = "#123456", bold = true })
            vim.api.nvim_set_hl(0, "DirectMarkSource", { fg = "#654321", bg = "#020202", italic = true })
            vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#345678" })
            require("scrollbar").setup(config)
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            return {
                track = get("ScrollbarTrack"),
                thumb = get("ScrollbarThumb"),
                pressed = get("ScrollbarThumbPressed"),
                string_mark = get("ScrollbarSearch"),
                string_overlap = get("ScrollbarSearchThumb"),
                table_mark = get("ScrollbarError"),
                table_overlap = get("ScrollbarErrorThumb"),
            }
        end,
        base_config({
            track = { highlight = "DirectTrackSource" },
            thumb = { blend = 27, highlight = "DirectThumbSource" },
            marks = {
                Search = { highlight = "DirectMarkSource" },
                Error = {
                    highlight = {
                        fg = "#fedcba",
                        bg = "#445566",
                        underline = true,
                        cterm = { underline = true },
                    },
                },
            },
        })
    )

    expect.equality(result.track, { bg = 0x234567 })
    expect.equality(result.thumb, { bg = 0x123456, blend = 27 })
    expect.equality(result.pressed, { bg = 0x345678, blend = 27 })
    expect.equality(result.string_mark, { fg = 0x654321 })
    expect.equality(result.string_overlap, { fg = 0x654321, bg = 0x123456, blend = 27 })
    expect.equality(result.table_mark, {
        fg = 0xFEDCBA,
        bg = 0x445566,
        underline = true,
        cterm = { underline = true },
    })
    expect.equality(result.table_overlap, {
        fg = 0xFEDCBA,
        bg = 0x445566,
        blend = 27,
        underline = true,
        cterm = { underline = true },
    })
end

T["regenerates automatic groups on ColorScheme and leaves manual groups untouched"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local scrollbar = require("scrollbar")
        vim.api.nvim_set_hl(0, "ConfiguredTrackSource", { bg = "#102030" })
        vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#405060" })
        scrollbar.setup(config.enabled)
        for _, name in ipairs({
            "ScrollbarBase",
            "ScrollbarTrack",
            "ScrollbarThumb",
            "ScrollbarThumbPressed",
            "ScrollbarSearch",
            "ScrollbarSearchThumb",
            "ScrollbarHandle",
            "ScrollbarSearchHandle",
        }) do
            vim.api.nvim_set_hl(0, name, { bg = "#000000" })
        end
        vim.cmd("doautocmd ColorScheme")
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        local regenerated = {
            base = get("ScrollbarBase"),
            track = get("ScrollbarTrack"),
            thumb = get("ScrollbarThumb"),
            pressed = get("ScrollbarThumbPressed"),
            mark = get("ScrollbarSearch"),
            overlap = get("ScrollbarSearchThumb"),
            alias = get("ScrollbarSearchHandle"),
        }

        local manual = {
            ScrollbarBase = { bg = "#010101" },
            ScrollbarTrack = { bg = "#123456" },
            ScrollbarThumb = { bg = "#223344", bold = true },
            ScrollbarThumbPressed = { bg = "#334455" },
            ScrollbarSearch = { fg = "#556677", italic = true },
            ScrollbarSearchThumb = { fg = "#667788", bg = "#778899" },
            ScrollbarHandle = { bg = "#8899aa" },
            ScrollbarSearchHandle = { fg = "#99aabb" },
        }
        for name, definition in pairs(manual) do
            vim.api.nvim_set_hl(0, name, definition)
        end
        scrollbar.setup(config.disabled)
        vim.cmd("doautocmd ColorScheme")
        local untouched = {}
        for name in pairs(manual) do
            untouched[name] = get(name)
        end
        return { regenerated = regenerated, untouched = untouched }
    end, {
        enabled = base_config({
            track = { highlight = "ConfiguredTrackSource" },
            thumb = { highlight = { bg = "#112233" } },
            marks = { Search = { highlight = { fg = "#abcdef" } } },
        }),
        disabled = base_config({ set_highlights = false }),
    })

    expect.equality(result.regenerated.base, {})
    expect.equality(result.regenerated.track.bg, 0x102030)
    expect.equality(result.regenerated.thumb, { bg = 0x112233, blend = 30 })
    expect.equality(result.regenerated.pressed, { bg = 0x405060, blend = 30 })
    expect.equality(result.regenerated.mark, { fg = 0xABCDEF })
    expect.equality(result.regenerated.overlap, { fg = 0xABCDEF, bg = 0x112233, blend = 30 })
    expect.equality(result.regenerated.alias, result.regenerated.overlap)
    expect.equality(result.untouched.ScrollbarBase, { bg = 0x010101 })
    expect.equality(result.untouched.ScrollbarTrack, { bg = 0x123456 })
    expect.equality(result.untouched.ScrollbarThumb, { bg = 0x223344, bold = true, cterm = { bold = true } })
    expect.equality(result.untouched.ScrollbarThumbPressed, { bg = 0x334455 })
    expect.equality(result.untouched.ScrollbarSearch, {
        fg = 0x556677,
        italic = true,
        cterm = { italic = true },
    })
    expect.equality(result.untouched.ScrollbarSearchThumb, { fg = 0x667788, bg = 0x778899 })
    expect.equality(result.untouched.ScrollbarHandle, { bg = 0x8899AA })
    expect.equality(result.untouched.ScrollbarSearchHandle, { fg = 0x99AABB })
end

return T
