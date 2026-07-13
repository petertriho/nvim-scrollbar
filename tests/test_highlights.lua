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
            gitsigns = false,
            ale = false,
            coc = false,
        },
    }, overrides or {})
end

T["uses popup menu backgrounds for the track and handle states"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            vim.api.nvim_set_hl(0, "PmenuSbar", { bg = "#112233" })
            vim.api.nvim_set_hl(0, "PmenuThumb", { bg = "#445566" })
            vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#778899" })
            require("scrollbar").setup(config)
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            return {
                track = get("ScrollbarTrack"),
                handle = get("ScrollbarHandle"),
                pressed = get("ScrollbarHandlePressed"),
                overlap = get("ScrollbarCustomHandlePressed"),
            }
        end,
        base_config({
            marks = {
                Custom = {
                    text = "!",
                    column = 1,
                    priority = 10,
                    highlight = { fg = "#abcdef", bold = true },
                },
            },
        })
    )

    expect.equality(result.track, { bg = 0x112233 })
    expect.equality(result.handle, { bg = 0x445566, blend = 30 })
    expect.equality(result.pressed, { bg = 0x778899, blend = 30 })
    expect.equality(result.overlap, {
        fg = 0xABCDEF,
        bg = 0x778899,
        bold = true,
        blend = 30,
        cterm = { bold = true },
    })
end

T["applies full highlight tables and merges overlaps with mark precedence"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            require("scrollbar").setup(config)
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            return {
                track = get("ScrollbarTrack"),
                handle = get("ScrollbarHandle"),
                mark = get("ScrollbarSearch"),
                overlap = get("ScrollbarSearchHandle"),
            }
        end,
        base_config({
            track = {
                highlight = {
                    bg = "#223344",
                    italic = true,
                },
            },
            handle = {
                blend = 33,
                highlight = {
                    fg = "#010203",
                    bg = "#112233",
                    bold = true,
                    blend = 11,
                    ctermbg = 4,
                    cterm = { bold = true },
                },
            },
            marks = {
                Search = {
                    highlight = {
                        fg = "#abcdef",
                        bg = "#445566",
                        sp = "#a1b2c3",
                        italic = true,
                        undercurl = true,
                        ctermfg = 5,
                        cterm = { italic = true },
                    },
                },
            },
        })
    )

    expect.equality(result.track, {
        bg = 0x223344,
        italic = true,
        cterm = { italic = true },
    })
    expect.equality(result.handle, {
        fg = 0x010203,
        bg = 0x112233,
        bold = true,
        blend = 11,
        ctermbg = 4,
        cterm = { bold = true },
    })
    expect.equality(result.mark, {
        fg = 0xABCDEF,
        bg = 0x445566,
        sp = 0xA1B2C3,
        italic = true,
        undercurl = true,
        ctermfg = 5,
        cterm = { italic = true },
    })
    expect.equality(result.overlap, {
        fg = 0xABCDEF,
        bg = 0x445566,
        sp = 0xA1B2C3,
        bold = true,
        italic = true,
        undercurl = true,
        blend = 11,
        ctermfg = 5,
        ctermbg = 4,
        cterm = { bold = true, italic = true },
    })
end

T["preserves string highlight projection and supports mixed definitions"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            vim.api.nvim_set_hl(0, "DirectTrackSource", { fg = "#030303", bg = "#234567", italic = true })
            vim.api.nvim_set_hl(0, "DirectHandleSource", { fg = "#010101", bg = "#123456", bold = true })
            vim.api.nvim_set_hl(0, "DirectMarkSource", { fg = "#654321", bg = "#020202", italic = true })
            vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#345678" })
            require("scrollbar").setup(config)
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            return {
                track = get("ScrollbarTrack"),
                handle = get("ScrollbarHandle"),
                pressed = get("ScrollbarHandlePressed"),
                string_mark = get("ScrollbarSearch"),
                string_overlap = get("ScrollbarSearchHandle"),
                table_mark = get("ScrollbarError"),
                table_overlap = get("ScrollbarErrorHandle"),
            }
        end,
        base_config({
            track = { highlight = "DirectTrackSource" },
            handle = { blend = 27, highlight = "DirectHandleSource" },
            marks = {
                Search = { highlight = "DirectMarkSource" },
                Error = { highlight = { fg = "#fedcba", underline = true } },
            },
        })
    )

    expect.equality(result.track, { bg = 0x234567 })
    expect.equality(result.handle, { bg = 0x123456, blend = 27 })
    expect.equality(result.pressed, { bg = 0x345678, blend = 27 })
    expect.equality(result.string_mark, { fg = 0x654321 })
    expect.equality(result.string_overlap, { fg = 0x654321, bg = 0x123456, blend = 27 })
    expect.equality(result.table_mark, { fg = 0xFEDCBA, underline = true, cterm = { underline = true } })
    expect.equality(result.table_overlap, {
        fg = 0xFEDCBA,
        bg = 0x123456,
        blend = 27,
        underline = true,
        cterm = { underline = true },
    })
end

T["regenerates direct definitions on ColorScheme and respects set_highlights false"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local scrollbar = require("scrollbar")
        vim.api.nvim_set_hl(0, "ConfiguredTrackSource", { bg = "#102030" })
        vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#405060" })
        scrollbar.setup(config.enabled)
        vim.api.nvim_set_hl(0, "ScrollbarTrack", { bg = "#000000" })
        vim.api.nvim_set_hl(0, "ScrollbarHandle", { bg = "#000000" })
        vim.api.nvim_set_hl(0, "ScrollbarHandlePressed", { bg = "#000000" })
        vim.api.nvim_set_hl(0, "ScrollbarSearch", { fg = "#000000" })
        vim.cmd("doautocmd ColorScheme")
        local regenerated_track = vim.api.nvim_get_hl(0, { name = "ScrollbarTrack", link = false })
        local regenerated_handle = vim.api.nvim_get_hl(0, { name = "ScrollbarHandle", link = false })
        local regenerated_pressed = vim.api.nvim_get_hl(0, { name = "ScrollbarHandlePressed", link = false })
        local regenerated_mark = vim.api.nvim_get_hl(0, { name = "ScrollbarSearch", link = false })

        vim.api.nvim_set_hl(0, "ScrollbarTrack", { bg = "#123456" })
        vim.api.nvim_set_hl(0, "ScrollbarHandle", { bg = "#334455", bold = true })
        vim.api.nvim_set_hl(0, "ScrollbarHandlePressed", { bg = "#445566" })
        vim.api.nvim_set_hl(0, "ScrollbarSearch", { fg = "#556677", italic = true })
        scrollbar.setup(config.disabled)
        vim.cmd("doautocmd ColorScheme")
        return {
            regenerated_track = regenerated_track,
            regenerated_handle = regenerated_handle,
            regenerated_pressed = regenerated_pressed,
            regenerated_mark = regenerated_mark,
            disabled_track = vim.api.nvim_get_hl(0, { name = "ScrollbarTrack", link = false }),
            disabled_handle = vim.api.nvim_get_hl(0, { name = "ScrollbarHandle", link = false }),
            disabled_pressed = vim.api.nvim_get_hl(0, { name = "ScrollbarHandlePressed", link = false }),
            disabled_mark = vim.api.nvim_get_hl(0, { name = "ScrollbarSearch", link = false }),
        }
    end, {
        enabled = base_config({
            track = { highlight = "ConfiguredTrackSource" },
            handle = { highlight = { bg = "#112233" } },
            marks = { Search = { highlight = { fg = "#abcdef" } } },
        }),
        disabled = base_config({
            set_highlights = false,
            track = { highlight = { bg = "#ffffff" } },
            handle = { highlight = { bg = "#ffffff" } },
            marks = { Search = { highlight = { fg = "#ffffff" } } },
        }),
    })

    expect.equality(result.regenerated_track.bg, 0x102030)
    expect.equality(result.regenerated_handle.bg, 0x112233)
    expect.equality(result.regenerated_handle.blend, 30)
    expect.equality(result.regenerated_pressed, { bg = 0x405060, blend = 30 })
    expect.equality(result.regenerated_mark, { fg = 0xABCDEF })
    expect.equality(result.disabled_track, { bg = 0x123456 })
    expect.equality(result.disabled_handle, { bg = 0x334455, bold = true, cterm = { bold = true } })
    expect.equality(result.disabled_pressed, { bg = 0x445566 })
    expect.equality(result.disabled_mark, { fg = 0x556677, italic = true, cterm = { italic = true } })
end

return T
