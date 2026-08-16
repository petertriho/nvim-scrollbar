local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.minimap.config"] = nil
            package.loaded["scrollbar.minimap.presets"] = nil
        end,
    },
})

local function config()
    return require("scrollbar.minimap.config")
end

local function expect_invalid(overrides, pattern)
    local ok, err = pcall(config().set, overrides)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

T["compiles profile variants with settled precedence"] = function()
    local root = config().set({
        width = 100,
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = {
                    width = 40,
                    overlays = { enabled = false },
                },
            },
            {
                match = { buftypes = { "quickfix" } },
                config = {
                    float = { placement = { anchor = "NW" } },
                },
            },
        },
    })
    local variants = config().get_variants()

    expect.equality(#variants, 3)
    expect.equality(variants[1].id, 0)
    expect.equality(variants[1].config, root)
    expect.equality(variants[2].id, 1)
    expect.equality(variants[2].config.width, 40)
    expect.equality(variants[2].config.overlays.enabled, false)
    expect.equality(variants[2].config.float.placement.relative, "window")
    expect.equality(variants[2].config.float.placement.anchor, "NE")
    expect.equality(variants[3].id, 2)
    expect.equality(variants[3].config.width, 100)
    expect.equality(variants[3].config.float.placement.anchor, "NW")

    for _, variant in ipairs(variants) do
        expect.equality(rawget(variant.config, "preset"), nil)
        expect.equality(rawget(variant.config, "presets"), nil)
        expect.equality(rawget(variant.config, "profiles"), nil)
    end
end

T["selects variants by filetype, buftype, and when predicate"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "lua"
    vim.bo[bufnr].buftype = ""

    config().set({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { width = 30 },
            },
            {
                match = { buftypes = { "quickfix" } },
                config = { width = 50 },
            },
        },
    })
    expect.equality(config().select(winid).variant_id, 1)

    vim.bo[bufnr].filetype = ""
    vim.bo[bufnr].buftype = "quickfix"
    expect.equality(config().select(winid).variant_id, 2)

    vim.bo[bufnr].buftype = ""
    expect.equality(config().select(winid).variant_id, 0)
end

T["builds callback context with the source window's metadata"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "lua"
    vim.bo[bufnr].buftype = "nofile"
    vim.api.nvim_buf_set_name(bufnr, "/tmp/minimap_context.lua")

    local received
    config().set({
        profiles = {
            {
                match = {
                    when = function(ctx)
                        received = ctx
                        return true
                    end,
                },
                config = { width = 30 },
            },
        },
    })

    config().select(winid)
    expect.equality(received, {
        winid = winid,
        bufnr = bufnr,
        filetype = "lua",
        buftype = "nofile",
        bufname = "/tmp/minimap_context.lua",
    })
end

T["falls back to root config on predicate errors and notifies once per distinct error"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "lua"

    local notifications = {}
    local original_notify = vim.notify
    rawset(vim, "notify", function(message, level)
        notifications[#notifications + 1] = { message, level }
    end)
    MiniTest.finally(function()
        rawset(vim, "notify", original_notify)
    end)

    ---@type string?
    local failure = "boom"
    config().set({
        profiles = {
            {
                match = {
                    when = function()
                        if failure then
                            error(failure)
                        end
                        return true
                    end,
                },
                config = { width = 30 },
            },
        },
    })

    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(#notifications, 1)
    failure = "second"
    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(#notifications, 2)
    failure = nil
    expect.equality(config().select(winid).variant_id, 1)
end

T["validates profile schema"] = function()
    expect_invalid({ profiles = "lua" }, "minimap.profiles must be a dense list")
    expect_invalid(
        { profiles = { [2] = { match = { when = function() end } } } },
        "minimap.profiles must be a dense list"
    )
    expect_invalid({ profiles = { {} } }, "minimap%.profiles%[1%].match must be a table")
    expect_invalid({ profiles = { { match = {} } } }, "minimap%.profiles%[1%].match must contain at least one matcher")
    expect_invalid({ profiles = { { match = { filetypes = {} } } } }, "filetypes must contain at least one value")
    expect_invalid({ profiles = { { match = { buftypes = { "", false } } } } }, "buftypes%[2%] must be a string")
    expect_invalid({ profiles = { { match = { when = true } } } }, "when must be a function")
    expect_invalid({ profiles = { { match = { filetypes = { "lua" }, extra = true } } } }, "unknown option")
    expect_invalid({ profiles = { { match = { when = function() end }, preset = 1 } } }, "preset must be a string")
    expect_invalid(
        { profiles = { { match = { when = function() end }, preset = "missing" } } },
        "unknown minimap preset 'missing'"
    )
end

T["profile config rejects disallowed nested keys"] = function()
    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { background = { blend = 40 } },
            },
        },
    }, "unknown option")

    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { float = { placement = { gutter = "inside" } } },
            },
        },
    }, "float.placement.gutter must be one of: avoid, overlap")

    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { float = { extra = true } },
            },
        },
    }, "unknown option")

    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { enabled = true },
            },
        },
    }, "unknown option")

    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { syntax_highlighting = true },
            },
        },
    }, "unknown option")

    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { show_cursor_row = true },
            },
        },
    }, "unknown option")

    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { providers = { cursor = false } },
            },
        },
    }, "unknown option")
end

T["profile config accepts cursor hiding and full-float blend"] = function()
    config().set({
        background = { blend = 35 },
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { float = { blend = 20, hide_on_cursor = false } },
            },
        },
    })

    local profile = config().get_variants()[2].config
    expect.equality(profile.background.blend, 35)
    expect.equality(profile.float.blend, 20)
    expect.equality(profile.float.hide_on_cursor, false)
end

T["profile config accepts and validates content glyphs"] = function()
    config().set({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { content_glyph = "#" },
            },
            {
                match = { filetypes = { "markdown" } },
                config = { content_glyph = "▌" },
            },
        },
    })

    local variants = config().get_variants()
    expect.equality(variants[2].config.content_glyph, "#")
    expect.equality(variants[3].config.content_glyph, "▌")

    expect_invalid({
        profiles = {
            { match = { filetypes = { "lua" } }, config = { content_glyph = "" } },
        },
    }, "minimap%.content_glyph must be a non%-empty string")
    expect_invalid({
        profiles = {
            { match = { filetypes = { "lua" } }, config = { content_glyph = "ab" } },
        },
    }, "minimap%.content_glyph must be a single%-width glyph")
    expect_invalid({
        profiles = {
            { match = { filetypes = { "lua" } }, config = { content_glyphs = { both = "x" } } },
        },
    }, "unknown option 'minimap%.profiles%[1%]%.config%.content_glyphs'")
end

T["select returns the root variant for the root config when no profiles match"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "txt"

    config().set({ width = 80 })
    local selection = config().select(winid)
    expect.equality(selection.variant_id, 0)
    expect.equality(selection.config.width, 80)
end

return T
