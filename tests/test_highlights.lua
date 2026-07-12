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

T["applies full highlight tables and merges overlaps with mark precedence"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            require("scrollbar").setup(config)
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            return {
                handle = get("ScrollbarHandle"),
                mark = get("ScrollbarSearch"),
                overlap = get("ScrollbarSearchHandle"),
            }
        end,
        base_config({
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
            vim.api.nvim_set_hl(0, "DirectHandleSource", { fg = "#010101", bg = "#123456", bold = true })
            vim.api.nvim_set_hl(0, "DirectMarkSource", { fg = "#654321", bg = "#020202", italic = true })
            require("scrollbar").setup(config)
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            return {
                handle = get("ScrollbarHandle"),
                string_mark = get("ScrollbarSearch"),
                string_overlap = get("ScrollbarSearchHandle"),
                table_mark = get("ScrollbarError"),
                table_overlap = get("ScrollbarErrorHandle"),
            }
        end,
        base_config({
            handle = { blend = 27, highlight = "DirectHandleSource" },
            marks = {
                Search = { highlight = "DirectMarkSource" },
                Error = { highlight = { fg = "#fedcba", underline = true } },
            },
        })
    )

    expect.equality(result.handle, { bg = 0x123456, blend = 27 })
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
        scrollbar.setup(config.enabled)
        vim.api.nvim_set_hl(0, "ScrollbarHandle", { bg = "#000000" })
        vim.api.nvim_set_hl(0, "ScrollbarSearch", { fg = "#000000" })
        vim.cmd("doautocmd ColorScheme")
        local regenerated_handle = vim.api.nvim_get_hl(0, { name = "ScrollbarHandle", link = false })
        local regenerated_mark = vim.api.nvim_get_hl(0, { name = "ScrollbarSearch", link = false })

        vim.api.nvim_set_hl(0, "ScrollbarHandle", { bg = "#334455", bold = true })
        vim.api.nvim_set_hl(0, "ScrollbarSearch", { fg = "#556677", italic = true })
        scrollbar.setup(config.disabled)
        return {
            regenerated_handle = regenerated_handle,
            regenerated_mark = regenerated_mark,
            disabled_handle = vim.api.nvim_get_hl(0, { name = "ScrollbarHandle", link = false }),
            disabled_mark = vim.api.nvim_get_hl(0, { name = "ScrollbarSearch", link = false }),
        }
    end, {
        enabled = base_config({
            handle = { highlight = { bg = "#112233" } },
            marks = { Search = { highlight = { fg = "#abcdef" } } },
        }),
        disabled = base_config({
            set_highlights = false,
            handle = { highlight = { bg = "#ffffff" } },
            marks = { Search = { highlight = { fg = "#ffffff" } } },
        }),
    })

    expect.equality(result.regenerated_handle.bg, 0x112233)
    expect.equality(result.regenerated_handle.blend, 30)
    expect.equality(result.regenerated_mark, { fg = 0xABCDEF })
    expect.equality(result.disabled_handle, { bg = 0x334455, bold = true, cterm = { bold = true } })
    expect.equality(result.disabled_mark, { fg = 0x556677, italic = true, cterm = { italic = true } })
end

return T
