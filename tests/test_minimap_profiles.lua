local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.minimap.config"] = nil
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

local function lua_profile(options)
    return vim.tbl_extend("error", { match = { filetypes = { "lua" } } }, options)
end

T["compiles profile variants with settled precedence"] = function()
    local root = config().set({
        width = 100,
        profiles = {
            {
                match = { filetypes = { "lua" } },
                width = 40,
                marks = false,
            },
            {
                match = { buftypes = { "quickfix" } },
                placement = { anchor = "NW" },
            },
        },
    })
    local variants = config().get_variants()

    expect.equality(#variants, 3)
    expect.equality(variants[1].id, 0)
    expect.equality(variants[1].config, root)
    expect.equality(variants[2].id, 1)
    expect.equality(variants[2].config.width, 40)
    expect.equality(next(variants[2].config.marks), nil)
    expect.equality(variants[2].config.placement.relative, "window")
    expect.equality(variants[2].config.placement.anchor, "NE")
    expect.equality(variants[3].id, 2)
    expect.equality(variants[3].config.width, 100)
    expect.equality(variants[3].config.placement.anchor, "NW")
    expect.no_equality(next(variants[3].config.marks), nil)

    for _, variant in ipairs(variants) do
        expect.equality(rawget(variant.config, "match"), nil)
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
                width = 30,
            },
            {
                match = { buftypes = { "quickfix" } },
                width = 50,
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
                width = 30,
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
                width = 30,
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
    expect_invalid({ profiles = { {} } }, "minimap%.profiles%[1%]%.match is required")
    expect_invalid({ profiles = { { match = "lua" } } }, "minimap%.profiles%[1%]%.match must be a table")
    expect_invalid({ profiles = { { match = {} } } }, "minimap%.profiles%[1%].match must contain at least one matcher")
    expect_invalid({ profiles = { { match = { filetypes = {} } } } }, "filetypes must contain at least one value")
    expect_invalid({ profiles = { { match = { buftypes = { "", false } } } } }, "buftypes%[2%] must be a string")
    expect_invalid({ profiles = { { match = { when = true } } } }, "when must be a function")
    expect_invalid({ profiles = { { match = { filetypes = { "lua" }, extra = true } } } }, "unknown option")
    expect_invalid(
        { profiles = { { match = { when = function() end }, preset = 1 } } },
        "minimap%.profiles%[1%]%.preset: the minimap has no presets"
    )
    expect_invalid(
        { profiles = { { match = { when = function() end }, preset = "missing" } } },
        "minimap%.profiles%[1%]%.preset: the minimap has no presets"
    )
end

T["profiles reject global and disallowed nested keys"] = function()
    expect_invalid(
        { profiles = { lua_profile({ background_blend = 40 }) } },
        "minimap%.profiles%[1%]%.background_blend is a global option and cannot be set in a profile"
    )
    expect_invalid(
        { profiles = { lua_profile({ enabled = true }) } },
        "minimap%.profiles%[1%]%.enabled is a global option and cannot be set in a profile"
    )
    expect_invalid(
        { profiles = { lua_profile({ placement = { gutter = "inside" } }) } },
        "unknown option 'minimap%.profiles%[1%]%.placement%.gutter'"
    )
    expect_invalid(
        { profiles = { lua_profile({ placement = { extra = true } }) } },
        "unknown option 'minimap%.profiles%[1%]%.placement%.extra'"
    )
    expect_invalid(
        { profiles = { lua_profile({ float = { blend = 20 } }) } },
        "unknown option 'minimap%.profiles%[1%]%.float'"
    )
    expect_invalid(
        { profiles = { lua_profile({ config = { width = 20 } }) } },
        "unknown option 'minimap%.profiles%[1%]%.config'"
    )
    expect_invalid(
        { profiles = { lua_profile({ syntax_highlighting = true }) } },
        "unknown option 'minimap%.profiles%[1%]%.syntax_highlighting'"
    )
    expect_invalid(
        { profiles = { lua_profile({ show_cursor_row = true }) } },
        "unknown option 'minimap%.profiles%[1%]%.show_cursor_row'"
    )
    expect_invalid(
        { profiles = { lua_profile({ providers = { cursor = false } }) } },
        "unknown option 'minimap%.profiles%[1%]%.providers'"
    )
end

T["profiles accept cursor hiding and blend while inheriting background_blend"] = function()
    config().set({
        background_blend = 35,
        profiles = {
            lua_profile({ blend = 20, hide_on_cursor = false }),
        },
    })

    local profile = config().get_variants()[2].config
    expect.equality(profile.background_blend, 35)
    expect.equality(profile.blend, 20)
    expect.equality(profile.hide_on_cursor, false)
end

T["profiles accept and validate glyphs"] = function()
    config().set({
        profiles = {
            lua_profile({ glyph = "#" }),
            {
                match = { filetypes = { "markdown" } },
                glyph = "▌",
            },
        },
    })

    local variants = config().get_variants()
    expect.equality(variants[2].config.glyph, "#")
    expect.equality(variants[3].config.glyph, "▌")

    expect_invalid(
        { profiles = { lua_profile({ glyph = "" }) } },
        "minimap%.profiles%[1%]%.glyph must be a non%-empty string"
    )
    expect_invalid(
        { profiles = { lua_profile({ glyph = "ab" }) } },
        "minimap%.profiles%[1%]%.glyph must be a single%-width glyph"
    )
    expect_invalid(
        { profiles = { lua_profile({ content_glyphs = { both = "x" } }) } },
        "unknown option 'minimap%.profiles%[1%]%.content_glyphs'"
    )
end

T["profile marks deep merge onto root overrides and preserve hidden types"] = function()
    config().set({
        marks = {
            Error = { priority = 0 },
        },
        profiles = {
            lua_profile({ marks = { Warn = false } }),
        },
    })
    local variants = config().get_variants()
    local root_marks = variants[1].config.marks
    local profile_marks = variants[2].config.marks

    expect.equality(root_marks.Error, {
        priority = 0,
        highlight = "DiagnosticVirtualTextError",
        group = "ScrollbarMinimapError",
    })
    expect.equality(root_marks.Warn.priority, 3)
    expect.equality(profile_marks.Error, {
        priority = 0,
        highlight = "DiagnosticVirtualTextError",
        group = "ScrollbarMinimapProfile1.Error",
    })
    expect.equality(profile_marks.Warn, nil)
    expect.equality(profile_marks.Hint, {
        priority = 5,
        highlight = "DiagnosticVirtualTextHint",
        group = "ScrollbarMinimapProfile1.Hint",
    })
end

T["profile marks can re-show a type that the root hid"] = function()
    config().set({
        marks = { Search = false },
        profiles = {
            lua_profile({ marks = { Search = { highlight = "IncSearch" } } }),
        },
    })
    local variants = config().get_variants()

    expect.equality(variants[1].config.marks.Search, nil)
    expect.equality(variants[2].config.marks.Search, {
        priority = 1,
        highlight = "IncSearch",
        group = "ScrollbarMinimapProfile1.Search",
    })
end

T["profile marks = false gives an empty marks table"] = function()
    config().set({
        marks = { Error = { priority = 0 } },
        profiles = {
            lua_profile({ marks = false }),
        },
    })
    local variants = config().get_variants()

    expect.equality(variants[2].config.marks, {})
    expect.no_equality(next(variants[1].config.marks), nil)
end

T["profile mark overrides are validated against the registry"] = function()
    expect_invalid(
        { profiles = { lua_profile({ marks = { Custom = {} } }) } },
        "minimap%.profiles%[1%]%.marks%.Custom: unknown mark type 'Custom'"
    )
    expect_invalid(
        { profiles = { lua_profile({ marks = { Cursor = false } }) } },
        "minimap%.profiles%[1%]%.marks%.Cursor: the minimap draws the cursor"
    )
    expect_invalid(
        { profiles = { lua_profile({ marks = { Error = { priority = -1 } } }) } },
        "minimap%.profiles%[1%]%.marks%.Error%.priority must be a non%-negative integer"
    )
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
