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

local function minimap()
    return require("scrollbar.minimap.config")
end

local function set(overrides)
    return minimap().set(overrides)
end

local function expect_invalid(overrides, pattern)
    local ok, err = pcall(set, overrides)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

local function with_groups(specs)
    for mark_type, spec in pairs(specs) do
        spec.group = "ScrollbarMinimap" .. mark_type
    end
    return specs
end

local FULL_OVERLAY_TYPES = with_groups({
    Error = { priority = 2, highlight = "DiagnosticVirtualTextError" },
    GitAdd = { priority = 7, highlight = "GitSignsAdd" },
    GitChange = { priority = 7, highlight = "GitSignsChange" },
    GitDelete = { priority = 7, highlight = "GitSignsDelete" },
    Hint = { priority = 5, highlight = "DiagnosticVirtualTextHint" },
    Info = { priority = 4, highlight = "DiagnosticVirtualTextInfo" },
    Mark = { priority = 1, highlight = "Special" },
    MiniDiffAdd = { priority = 7, highlight = "MiniDiffSignAdd" },
    MiniDiffChange = { priority = 7, highlight = "MiniDiffSignChange" },
    MiniDiffDelete = { priority = 7, highlight = "MiniDiffSignDelete" },
    Misc = { priority = 6, highlight = "Normal" },
    Search = { priority = 1, highlight = "Search" },
    SignifyAdd = { priority = 7, highlight = "SignifySignAdd" },
    SignifyChange = { priority = 7, highlight = "SignifySignChange" },
    SignifyDelete = { priority = 7, highlight = "SignifySignDelete" },
    VGitAdd = { priority = 7, highlight = "GitSignsAdd" },
    VGitChange = { priority = 7, highlight = "GitSignsChange" },
    VGitDelete = { priority = 7, highlight = "GitSignsDelete" },
    Warn = { priority = 3, highlight = "DiagnosticVirtualTextWarn" },
})

T["defaults to disabled with sensible defaults"] = function()
    local result = set()

    expect.equality(result.enabled, false)
    expect.equality(result.visibility, "all")
    expect.equality(result.set_highlights, true)
    expect.equality(result.max_lines, false)
    expect.equality(result.autohide.enabled, false)
    expect.equality(result.autohide.delay_ms, 1000)
    expect.equality(result.float.zindex, 50)
    expect.equality(result.float.blend, 0)
    expect.equality(result.float.placement.relative, "window")
    expect.equality(result.float.placement.anchor, "NE")
    expect.equality(result.float.placement.row, 0)
    expect.equality(result.float.placement.col, 0)
    expect.equality(result.float.placement.gutter, "overlap")
    expect.equality(result.float.placement.gutter_position, "inner")
    expect.equality(result.width, 16)
    expect.equality(result.height, false)
    expect.equality(result.mouse.enabled, true)
    expect.equality(result.backend, "worker")
    expect.equality(result.update.interval_ms, 50)
    expect.equality(result.update.events[1], "BufEnter")
    expect.equality(#result.update.events, 16)
    expect.equality(result.excluded_buftypes, {})
    expect.equality(result.excluded_filetypes, {})
    expect.equality(result.overlays.enabled, true)
    expect.equality(result.overlays.types, FULL_OVERLAY_TYPES)
    expect.equality(result.show_viewport, true)
    expect.equality(result.content_glyphs, { top = "▀", bottom = "▄", both = "█" })
    expect.equality(rawget(result, "preset"), nil)
    expect.equality(rawget(result, "presets"), nil)
    expect.equality(rawget(result, "profiles"), nil)
    expect.equality(rawget(result, "syntax_highlighting"), nil)
    expect.equality(rawget(result, "show_cursor_row"), nil)
end

T["defaults core minimap providers on and integrations and semantics off"] = function()
    local providers = set().providers

    expect.equality(providers.cursor, true)
    expect.equality(providers.diagnostic, true)
    expect.equality(providers.search, { backend = "worker" })
    expect.equality(providers.marks, { letters = true, numbers = false })
    expect.equality(providers.gitsigns, false)
    expect.equality(providers.mini_diff, false)
    expect.equality(providers.signify, false)
    expect.equality(providers.vgit, false)
    expect.equality(providers.ale, false)
    expect.equality(providers.coc, false)
    expect.equality(providers.treesitter, false)
    expect.equality(providers.lsp_semantic_tokens, false)
end

T["get lazily initializes and returns the same active config"] = function()
    local first = minimap().get()
    expect.equality(first.enabled, false)

    local second = minimap().get()
    expect.equality(second, first)
end

T["accepts the complete valid schema and deep copies inputs"] = function()
    local excluded_buftypes = { "terminal" }
    local excluded_filetypes = { "TelescopePrompt" }
    local result = set({
        enabled = true,
        visibility = "active",
        set_highlights = false,
        max_lines = 5000,
        autohide = { enabled = true, delay_ms = 250 },
        float = {
            zindex = 90,
            blend = 35,
            placement = {
                relative = "window",
                anchor = "SW",
                row = -1,
                col = 2,
                gutter = "avoid",
                gutter_position = "outer",
            },
        },
        width = 120,
        height = 40,
        mouse = { enabled = false },
        backend = "sync",
        update = { events = { "BufEnter", "CursorMoved" }, interval_ms = 0 },
        excluded_buftypes = excluded_buftypes,
        excluded_filetypes = excluded_filetypes,
        overlays = {
            enabled = false,
            types = {
                Error = { priority = 0 },
                CustomReview = { priority = 8, highlight = "Special" },
            },
        },
        providers = {
            cursor = false,
            diagnostic = false,
            search = { incsearch = true, backend = "sync" },
            marks = { letters = false, numbers = true },
            gitsigns = true,
            mini_diff = true,
            signify = true,
            vgit = true,
            ale = true,
            coc = true,
            treesitter = true,
            lsp_semantic_tokens = true,
        },
        show_viewport = false,
        content_glyphs = { top = "▘", bottom = "▖", both = "▌" },
    })

    expect.equality(result.enabled, true)
    expect.equality(result.visibility, "active")
    expect.equality(result.set_highlights, false)
    expect.equality(result.max_lines, 5000)
    expect.equality(result.autohide.delay_ms, 250)
    expect.equality(result.float.zindex, 90)
    expect.equality(result.float.blend, 35)
    expect.equality(result.float.placement.anchor, "SW")
    expect.equality(result.float.placement.gutter, "avoid")
    expect.equality(result.float.placement.gutter_position, "outer")
    expect.equality(result.width, 120)
    expect.equality(result.height, 40)
    expect.equality(result.mouse.enabled, false)
    expect.equality(result.backend, "sync")
    expect.equality(result.update.events, { "BufEnter", "CursorMoved" })
    expect.equality(result.update.interval_ms, 0)
    expect.equality(result.excluded_buftypes, { "terminal" })
    expect.equality(result.excluded_filetypes, { "TelescopePrompt" })
    expect.equality(result.overlays.enabled, false)
    expect.equality(result.overlays.types.Error, {
        priority = 0,
        highlight = "DiagnosticVirtualTextError",
        group = "ScrollbarMinimapError",
    })
    expect.equality(result.overlays.types.Warn, FULL_OVERLAY_TYPES.Warn)
    expect.equality(result.overlays.types.CustomReview, {
        priority = 8,
        highlight = "Special",
        group = "ScrollbarMinimapCustomReview",
    })
    expect.equality(result.providers.search, { incsearch = true, backend = "sync" })
    expect.equality(result.providers.marks, { letters = false, numbers = true })
    expect.equality(result.providers.treesitter, true)
    expect.equality(result.providers.lsp_semantic_tokens, true)
    expect.equality(result.show_viewport, false)
    expect.equality(result.content_glyphs, { top = "▘", bottom = "▖", both = "▌" })

    excluded_buftypes[1] = "mutated"
    excluded_filetypes[1] = "mutated"
    expect.equality(result.excluded_buftypes, { "terminal" })
    expect.equality(result.excluded_filetypes, { "TelescopePrompt" })
end

T["rejects unknown top-level keys"] = function()
    expect_invalid({ unknown = true }, "unknown option 'minimap%.unknown'")
    expect_invalid({ handle = {} }, "unknown option 'minimap%.handle'")
    expect_invalid({ layout = {} }, "unknown option 'minimap%.layout'")
    expect_invalid({ marks = {} }, "unknown option 'minimap%.marks'")
end

T["rejects removed minimap options and unknown provider names"] = function()
    expect_invalid({ syntax_highlighting = true }, "unknown option 'minimap%.syntax_highlighting'")
    expect_invalid({ show_cursor_row = true }, "unknown option 'minimap%.show_cursor_row'")
    expect_invalid({ providers = { custom = true } }, "unknown option 'minimap%.providers%.custom'")
end

T["rejects unknown nested keys"] = function()
    expect_invalid({ autohide = { extra = true } }, "unknown option 'minimap%.autohide%.extra'")
    expect_invalid({ update = { extra = true } }, "unknown option 'minimap%.update%.extra'")
    expect_invalid({ float = { extra = true } }, "unknown option 'minimap%.float%.extra'")
    expect_invalid({ float = { placement = { extra = true } } }, "unknown option 'minimap%.float%.placement%.extra'")
    expect_invalid({ mouse = { extra = true } }, "unknown option 'minimap%.mouse%.extra'")
    expect_invalid({ overlays = { extra = true } }, "unknown option 'minimap%.overlays%.extra'")
    expect_invalid({ providers = { search = { extra = true } } }, "unknown option 'minimap%.providers%.search%.extra'")
end

T["rejects invalid scalar and enum values"] = function()
    expect_invalid({ enabled = "yes" }, "minimap%.enabled must be a boolean")
    expect_invalid({ visibility = "current" }, "minimap%.visibility must be one of")
    expect_invalid({ set_highlights = 1 }, "minimap%.set_highlights must be a boolean")
    expect_invalid({ max_lines = 0 }, "minimap%.max_lines must be false or a positive integer")
    expect_invalid({ max_lines = -1 }, "minimap%.max_lines must be false or a positive integer")
    expect_invalid({ width = 0 }, "minimap%.width must be false or a positive integer")
    expect_invalid({ width = "wide" }, "minimap%.width must be false or a positive integer")
    expect_invalid({ height = -5 }, "minimap%.height must be false or a positive integer")
    expect_invalid({ backend = "remote" }, "minimap%.backend must be one of")
    expect_invalid({ autohide = { enabled = "yes" } }, "minimap%.autohide%.enabled must be a boolean")
    expect_invalid({ autohide = { delay_ms = 0 } }, "minimap%.autohide%.delay_ms must be a positive integer")
    expect_invalid({ float = { zindex = 0 } }, "minimap%.float%.zindex must be a positive integer")
    expect_invalid({ float = { blend = -1 } }, "minimap%.float%.blend must be a non%-negative integer")
    expect_invalid({ float = { blend = 101 } }, "minimap%.float%.blend must be at most 100")
    expect_invalid({ float = { placement = { anchor = "C" } } }, "minimap%.float%.placement%.anchor must be one of")
    expect_invalid(
        { float = { placement = { relative = "screen" } } },
        "minimap%.float%.placement%.relative must be one of"
    )
    expect_invalid(
        { float = { placement = { gutter = "inside" } } },
        "minimap%.float%.placement%.gutter must be one of"
    )
    expect_invalid(
        { float = { placement = { gutter_position = "middle" } } },
        "minimap%.float%.placement%.gutter_position must be one of"
    )
    expect_invalid({ float = { placement = { row = 1.5 } } }, "minimap%.float%.placement%.row must be an integer")
    expect_invalid({ mouse = { enabled = 1 } }, "minimap%.mouse%.enabled must be a boolean")
    expect_invalid({ overlays = { enabled = 1 } }, "minimap%.overlays%.enabled must be a boolean")
    expect_invalid({ providers = { search = "yes" } }, "minimap%.providers%.search must be a boolean or table")
    expect_invalid(
        { providers = { marks = { letters = "yes" } } },
        "minimap%.providers%.marks%.letters must be a boolean"
    )
    expect_invalid({ providers = { treesitter = {} } }, "minimap%.providers%.treesitter must be a boolean")
    expect_invalid({ show_viewport = "yes" }, "minimap%.show_viewport must be a boolean")
end

T["rejects malformed table values"] = function()
    expect_invalid({ autohide = false }, "minimap%.autohide must be a table")
    expect_invalid({ update = false }, "minimap%.update must be a table")
    expect_invalid({ float = false }, "minimap%.float must be a table")
    expect_invalid({ float = { placement = false } }, "minimap%.float%.placement must be a table")
    expect_invalid({ mouse = false }, "minimap%.mouse must be a table")
    expect_invalid({ overlays = false }, "minimap%.overlays must be a table")
    expect_invalid({ excluded_buftypes = "terminal" }, "minimap%.excluded_buftypes must be a dense list")
    expect_invalid({ excluded_filetypes = { "lua", false } }, "minimap%.excluded_filetypes%[2%] must be a string")
    expect_invalid(
        { excluded_buftypes = { [1] = "terminal", [3] = "nofile" } },
        "minimap%.excluded_buftypes must be a dense list"
    )
    expect_invalid({ content_glyphs = false }, "minimap%.content_glyphs must be a table")
    expect_invalid({ content_glyphs = { top = 1 } }, "minimap%.content_glyphs%.top must be a non%-empty string")
    expect_invalid(
        { content_glyphs = { top = "▘", bottom = "▖", both = "█", bogus = "x" } },
        "unknown option 'minimap%.content_glyphs%.bogus'"
    )
    expect_invalid({ content_glyphs = { top = "ab" } }, "minimap%.content_glyphs%.top must be a single%-width glyph")
end

T["rejects malformed update events lists"] = function()
    expect_invalid({ update = { events = {} } }, "minimap%.update%.events must contain at least one event")
    expect_invalid({ update = { events = "BufEnter" } }, "minimap%.update%.events must be a dense list")
    expect_invalid({ update = { events = { "BufEnter", false } } }, "minimap%.update%.events%[2%] must be a string")
    expect_invalid(
        { update = { events = { "NotAnEvent" } } },
        "minimap%.update%.events%[1%] unknown event 'NotAnEvent'"
    )
    expect_invalid(
        { update = { events = { "BufEnter", "BufEnter" } } },
        "minimap%.update%.events%[2%] duplicate event 'BufEnter'"
    )
    expect_invalid({ update = { interval_ms = -1 } }, "minimap%.update%.interval_ms must be a non%-negative integer")
end

T["accepts scrollbar-shared events outside the minimap default set"] = function()
    local result = set({ update = { events = { "OptionSet", "TabEnter" } } })
    expect.equality(result.update.events, { "OptionSet", "TabEnter" })
end

T["rejects malformed overlay type maps and specs"] = function()
    expect_invalid({ overlays = { types = { "Error" } } }, "minimap%.overlays%.types keys must be valid mark types")
    expect_invalid({ overlays = { types = { [1] = false } } }, "minimap%.overlays%.types keys must be valid mark types")
    expect_invalid(
        { overlays = { types = { ["not-a-type"] = false } } },
        "minimap%.overlays%.types keys must be valid mark types"
    )
    expect_invalid({ overlays = { types = "Error" } }, "minimap%.overlays%.types must be a table")
    expect_invalid(
        { overlays = { types = { Error = true } } },
        "minimap%.overlays%.types%.Error must be false or a table"
    )
    expect_invalid(
        { overlays = { types = { Error = { text = "!" } } } },
        "unknown option 'minimap%.overlays%.types%.Error%.text'"
    )
    expect_invalid(
        { overlays = { types = { Error = { priority = -1 } } } },
        "minimap%.overlays%.types%.Error%.priority must be a non%-negative integer"
    )
    expect_invalid(
        { overlays = { types = { Error = { priority = 1.5 } } } },
        "minimap%.overlays%.types%.Error%.priority must be a non%-negative integer"
    )
    expect_invalid(
        { overlays = { types = { Error = { priority = math.huge } } } },
        "minimap%.overlays%.types%.Error%.priority must be a non%-negative integer"
    )
    expect_invalid(
        { overlays = { types = { Error = { highlight = "" } } } },
        "minimap%.overlays%.types%.Error%.highlight must be a non%-empty string or table"
    )
    expect_invalid(
        { overlays = { types = { Error = { highlight = false } } } },
        "minimap%.overlays%.types%.Error%.highlight must be a non%-empty string or table"
    )
end

T["requires complete specs only for custom overlay types without fallbacks"] = function()
    expect_invalid(
        { overlays = { types = { CustomReview = { priority = 8 } } } },
        "minimap%.overlays%.types%.CustomReview%.highlight is required"
    )
    expect_invalid(
        { overlays = { types = { CustomReview = { highlight = "Special" } } } },
        "minimap%.overlays%.types%.CustomReview%.priority is required"
    )

    local result = set({
        overlays = {
            types = {
                CustomReview = { priority = 8, highlight = "Special" },
                Future_mark = { priority = 9, highlight = { fg = "#abcdef" } },
            },
        },
    })
    expect.equality(result.overlays.types.CustomReview, {
        priority = 8,
        highlight = "Special",
        group = "ScrollbarMinimapCustomReview",
    })
    expect.equality(result.overlays.types.Future_mark, {
        priority = 9,
        highlight = { fg = "#abcdef" },
        group = "ScrollbarMinimapFuture_mark",
    })
end

T["rejects overlay types that collide with static minimap groups"] = function()
    for _, mark_type in ipairs({ "Base", "Content", "Viewport", "Cursor" }) do
        expect_invalid({
            overlays = {
                types = {
                    [mark_type] = { priority = 1, highlight = "Special" },
                },
            },
        }, "conflicts with the static ScrollbarMinimap" .. mark_type .. " group")
    end
end

T["partial overrides inherit fallbacks and false removes only selected types"] = function()
    local result = set({
        overlays = {
            types = {
                Error = { priority = 0 },
                Hint = false,
            },
        },
    })

    expect.equality(result.overlays.types.Error, {
        priority = 0,
        highlight = "DiagnosticVirtualTextError",
        group = "ScrollbarMinimapError",
    })
    expect.equality(result.overlays.types.Hint, nil)
    expect.equality(result.overlays.types.Warn, FULL_OVERLAY_TYPES.Warn)
end

T["root and profile layers can re-enable preset tombstones"] = function()
    local root = set({
        preset = "disabled",
        presets = {
            disabled = { overlays = { types = { Search = false, Hint = false } } },
        },
        overlays = { types = { Search = {} } },
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { overlays = { types = { Hint = {} } } },
            },
        },
    })
    local profile = minimap().get_variants()[2].config

    expect.equality(root.overlays.types.Search, FULL_OVERLAY_TYPES.Search)
    expect.equality(root.overlays.types.Hint, nil)
    expect.equality(profile.overlays.types.Hint, {
        priority = 5,
        highlight = "DiagnosticVirtualTextHint",
        group = "ScrollbarMinimapProfile1.Hint",
    })
end

T["failed setup preserves active config"] = function()
    local before = set({ width = 100, height = 30 })

    expect_invalid({ visibility = "current" }, "minimap%.visibility must be one of")
    expect.equality(minimap().get(), before)

    expect_invalid({ backend = "remote" }, "minimap%.backend must be one of")
    expect.equality(minimap().get(), before)
end

T["normalizes fresh state without leaking prior setup-only values"] = function()
    set({
        enabled = true,
        width = 100,
        backend = "sync",
        overlays = { types = { Error = { priority = 0 } } },
        profiles = {
            { match = { filetypes = { "lua" } }, config = { width = 60 } },
        },
    })

    local result = set()
    expect.equality(result.enabled, false)
    expect.equality(result.width, 16)
    expect.equality(result.backend, "worker")
    expect.equality(result.overlays.types, FULL_OVERLAY_TYPES)
    expect.equality(rawget(result, "preset"), nil)
    expect.equality(rawget(result, "presets"), nil)
    expect.equality(rawget(result, "profiles"), nil)
end

T["presets resolve and merge with root overrides"] = function()
    local result = set({
        preset = "compact",
        presets = {
            compact = {
                width = 40,
                overlays = { enabled = false },
                float = { placement = { anchor = "NW" } },
            },
        },
        height = 20,
    })

    expect.equality(result.width, 40)
    expect.equality(result.height, 20)
    expect.equality(result.overlays.enabled, false)
    expect.equality(result.float.placement.anchor, "NW")
    expect.equality(result.float.placement.relative, "window")
end

T["presets support extends chains"] = function()
    local result = set({
        preset = "child",
        presets = {
            parent = { width = 50, show_viewport = false },
            child = { extends = "parent", height = 25 },
        },
    })

    expect.equality(result.width, 50)
    expect.equality(result.height, 25)
    expect.equality(result.show_viewport, false)
end

T["presets reject unknown fields and invalid values"] = function()
    expect_invalid({
        preset = "bad",
        presets = { bad = { enabled = true } },
    }, "minimap preset 'bad' cannot set 'enabled'")
    expect_invalid({
        preset = "bad",
        presets = { bad = { width = 0 } },
    }, "minimap preset 'bad'%.width must be false or a positive integer")
    expect_invalid({
        preset = "bad",
        presets = { bad = { float = { zindex = "high" } } },
    }, "minimap preset 'bad' cannot set 'float%.zindex'")
    expect_invalid({
        preset = "missing",
    }, "unknown minimap preset 'missing'")
    expect_invalid({
        preset = "bad",
        presets = { bad = "not a table" },
    }, "minimap preset 'bad' must be a table")
end

T["compiles profile variants with first-match precedence"] = function()
    local root = set({
        width = 80,
        height = false,
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { width = 60, height = 30 },
            },
            {
                match = { buftypes = { "nofile" } },
                config = { width = 40 },
            },
        },
    })
    local variants = minimap().get_variants()

    expect.equality(root.width, 80)
    expect.equality(#variants, 3)
    expect.equality(variants[1].id, 0)
    expect.equality(variants[1].config, root)
    expect.equality(variants[2].id, 1)
    expect.equality(variants[2].config.width, 60)
    expect.equality(variants[2].config.height, 30)
    expect.equality(variants[3].id, 2)
    expect.equality(variants[3].config.width, 40)
    expect.equality(variants[3].config.height, false)

    for _, variant in ipairs(variants) do
        expect.equality(rawget(variant.config, "preset"), nil)
        expect.equality(rawget(variant.config, "presets"), nil)
        expect.equality(rawget(variant.config, "profiles"), nil)
    end
end

T["rejects malformed profile matchers and configs"] = function()
    expect_invalid({ profiles = "lua" }, "minimap%.profiles must be a dense list")
    expect_invalid(
        { profiles = { [2] = { match = { when = function() end } } } },
        "minimap%.profiles must be a dense list"
    )
    expect_invalid({ profiles = { {} } }, "minimap%.profiles%[1%]%.match must be a table")
    expect_invalid({ profiles = { { match = {} } } }, "minimap%.profiles%[1%]%.match must contain at least one matcher")
    expect_invalid(
        { profiles = { { match = { filetypes = {} } } } },
        "match%.filetypes must contain at least one value"
    )
    expect_invalid({ profiles = { { match = { buftypes = { "", false } } } } }, "match%.buftypes%[2%] must be a string")
    expect_invalid({ profiles = { { match = { when = true } } } }, "match%.when must be a function")
    expect_invalid(
        { profiles = { { match = { filetypes = { "lua" }, extra = true } } } },
        "unknown option 'minimap%.profiles%[1%]%.match%.extra'"
    )
    expect_invalid(
        { profiles = { { match = { when = function() end }, preset = 1 } } },
        "minimap%.profiles%[1%]%.preset must be a string"
    )
    expect_invalid(
        { profiles = { { match = { filetypes = { "lua" } }, config = { width = 0 } } } },
        "minimap%.width must be false or a positive integer"
    )
end

T["profile config whitelist rejects behavior and eligibility fields"] = function()
    local rejected = {
        { enabled = false },
        { set_highlights = false },
        { max_lines = 100 },
        { autohide = { enabled = true } },
        { backend = "sync" },
        { syntax_highlighting = true },
        { update = { interval_ms = 50 } },
        { excluded_filetypes = { "lua" } },
        { visibility = "active" },
        { preset = "compact" },
        { presets = {} },
        { profiles = {} },
    }
    for _, unsafe in ipairs(rejected) do
        expect_invalid({ profiles = { { match = { filetypes = { "lua" } }, config = unsafe } } }, "profile")
    end
end

T["profile config whitelist allows display-only overrides"] = function()
    local result = set({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = {
                    width = 60,
                    height = 30,
                    float = { placement = { anchor = "NW" } },
                    overlays = { enabled = false },
                    show_viewport = false,
                    mouse = { enabled = false },
                },
            },
        },
    })
    local variants = minimap().get_variants()
    expect.equality(variants[2].config.width, 60)
    expect.equality(variants[2].config.height, 30)
    expect.equality(variants[2].config.float.placement.anchor, "NW")
    expect.equality(variants[2].config.overlays.enabled, false)
    expect.equality(variants[2].config.show_viewport, false)
    expect.equality(variants[2].config.mouse.enabled, false)
    expect.equality(result.width, 16)
end

T["profile variants preserve setup-level providers"] = function()
    local root = set({
        providers = { cursor = false, search = { backend = "sync" } },
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { width = 40 },
            },
        },
    })
    local variants = minimap().get_variants()

    expect.equality(root.providers.cursor, false)
    expect.equality(root.providers.search, { backend = "sync" })
    expect.equality(variants[2].config.providers, root.providers)
end

T["commits root and variants atomically on profile failure"] = function()
    local before = set({
        width = 100,
        profiles = {
            { match = { filetypes = { "lua" } }, config = { width = 60 } },
        },
    })
    local before_variants = minimap().get_variants()

    expect_invalid({
        profiles = {
            { match = { filetypes = { "lua" } }, config = { width = 0 } },
            { match = { buftypes = { "nofile" } }, config = { height = -1 } },
        },
    }, "minimap%.width must be false or a positive integer")
    expect.equality(minimap().get(), before)
    expect.equality(minimap().get_variants(), before_variants)
end

T["selects first matching profile with AND semantics"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "lua"
    vim.bo[bufnr].buftype = "nofile"
    vim.api.nvim_buf_set_name(bufnr, "/tmp/minimap.lua")

    set({
        profiles = {
            { match = { filetypes = { "markdown" } }, config = { width = 10 } },
            {
                match = { filetypes = { "lua" }, buftypes = { "nofile" } },
                config = { width = 50 },
            },
            { match = { filetypes = { "lua" } }, config = { width = 70 } },
        },
    })

    local selected = minimap().select(winid)
    expect.equality(selected.variant_id, 2)
    expect.equality(selected.config.width, 50)

    vim.bo[bufnr].buftype = ""
    selected = minimap().select(winid)
    expect.equality(selected.variant_id, 3)
    expect.equality(selected.config.width, 70)

    vim.bo[bufnr].filetype = "text"
    selected = minimap().select(winid)
    expect.equality(selected.variant_id, 0)
    expect.equality(selected.config.width, 16)
end

T["predicate errors fall back to root and rate-limit notifications"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    ---@type string?
    local failure = "first"
    local notifications = {}
    local original_notify = vim.notify
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.notify = function(message, level)
        notifications[#notifications + 1] = { message, level }
    end

    set({
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
                config = { width = 40 },
            },
        },
    })

    expect.equality(minimap().select(winid).variant_id, 0)
    expect.equality(minimap().select(winid).variant_id, 0)
    expect.equality(#notifications, 1)
    failure = "second"
    expect.equality(minimap().select(winid).variant_id, 0)
    expect.equality(#notifications, 2)
    failure = nil
    expect.equality(minimap().select(winid).variant_id, 1)
    vim.notify = original_notify
end

T["integrates with the top-level scrollbar dispatcher"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")

    config.set({})
    expect.equality(config.get_minimap().enabled, false)
    expect.equality(config.get_minimap().width, 16)
    expect.equality(config.get_minimap().backend, "worker")

    config.set({ minimap = { enabled = true, width = 100, providers = { treesitter = true } } })
    expect.equality(config.get_minimap().enabled, true)
    expect.equality(config.get_minimap().width, 100)
    expect.equality(config.get_minimap().providers.treesitter, true)

    config.set({ minimap = { enabled = false } })
    expect.equality(config.get_minimap().enabled, false)

    ---@diagnostic disable-next-line: assign-type-mismatch
    local ok, err = pcall(config.set, { minimap = { enabled = "yes" } })
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match("minimap%.enabled must be a boolean"), nil)

    ---@diagnostic disable-next-line: assign-type-mismatch
    local ok2, err2 = pcall(config.set, { minimap = "not a table" })
    expect.equality(ok2, false)
    expect.no_equality(tostring(err2):match("minimap must be a table"), nil)
end

T["top-level validation commits both config slices atomically"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")
    local before_scrollbar = config.set({
        scrollbar = {
            visibility = "active",
            profiles = {
                { match = { filetypes = { "lua" } }, preset = "minimal" },
            },
        },
        minimap = {
            enabled = true,
            width = 80,
            profiles = {
                { match = { filetypes = { "lua" } }, config = { width = 40 } },
            },
        },
    })
    local before_scrollbar_variants = config.get_variants()
    local before_minimap = config.get_minimap()
    local before_minimap_variants = minimap().get_variants()

    local ok = pcall(config.set, {
        scrollbar = {
            visibility = "all",
            profiles = {
                { match = { filetypes = { "lua" } }, preset = "review" },
            },
        },
        minimap = { width = 0 },
    })

    expect.equality(ok, false)
    expect.equality(config.get(), before_scrollbar)
    expect.equality(config.get_variants(), before_scrollbar_variants)
    expect.equality(config.get_minimap(), before_minimap)
    expect.equality(minimap().get_variants(), before_minimap_variants)
end

T["provider plan unions consumers and lets one table beat true"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")
    config.set({
        scrollbar = {
            providers = {
                cursor = false,
                search = true,
            },
        },
        minimap = {
            enabled = true,
            providers = {
                cursor = true,
                search = { incsearch = true, backend = "sync" },
            },
        },
    })

    local plan = config.get_provider_plan()
    expect.equality(plan.cursor.consumers, { scrollbar = false, minimap = true })
    expect.equality(plan.search.consumers, { scrollbar = true, minimap = true })
    expect.equality(plan.search.options, { incsearch = true, backend = "sync" })
    expect.equality(plan.search.targets, { scrollbar = true, minimap = true })
    expect.equality(plan.search.execution, "parent")
end

T["provider plan accepts equal tables and atomically rejects conflicting tables"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")
    local before_scrollbar = config.set({
        scrollbar = {
            providers = { search = {} },
            profiles = {
                { match = { filetypes = { "lua" } }, preset = "minimal" },
            },
        },
        minimap = {
            enabled = true,
            providers = { search = { backend = "worker" } },
            profiles = {
                { match = { filetypes = { "lua" } }, config = { width = 40 } },
            },
        },
    })
    local before_scrollbar_variants = config.get_variants()
    local before_minimap = config.get_minimap()
    local before_minimap_variants = minimap().get_variants()
    local before_plan = config.get_provider_plan()
    expect.equality(before_plan.search.options, { backend = "worker" })

    local ok, err = pcall(config.set, {
        scrollbar = {
            visibility = "active",
            providers = { search = { backend = "sync" } },
        },
        minimap = {
            enabled = true,
            width = 80,
            providers = { search = { backend = "worker" } },
        },
    })

    expect.equality(ok, false)
    expect.no_equality(tostring(err):match("scrollbar%.providers%.search"), nil)
    expect.no_equality(tostring(err):match("minimap%.providers%.search"), nil)
    expect.equality(config.get(), before_scrollbar)
    expect.equality(config.get_variants(), before_scrollbar_variants)
    expect.equality(config.get_minimap(), before_minimap)
    expect.equality(minimap().get_variants(), before_minimap_variants)
    expect.equality(config.get_provider_plan(), before_plan)
end

T["disabled minimap contributes no provider demand"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")
    local ok = pcall(config.set, {
        scrollbar = {
            providers = {
                cursor = false,
                search = { backend = "sync" },
            },
        },
        minimap = {
            enabled = false,
            providers = {
                cursor = true,
                search = { backend = "worker" },
            },
        },
    })

    expect.equality(ok, true)
    local plan = config.get_provider_plan()
    expect.equality(plan.cursor.consumers, { scrollbar = false, minimap = false })
    expect.equality(plan.cursor.options, false)
    expect.equality(plan.search.consumers, { scrollbar = true, minimap = false })
    expect.equality(plan.search.options, { backend = "sync" })
end

T["default overlay specs use a root-first deep-copied scrollbar union without Cursor"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")
    local root_highlight = { fg = "#123456", bold = true }
    local profile_highlight = { fg = "#abcdef" }
    config.set({
        scrollbar = {
            marks = {
                CustomReview = { text = "!", priority = 8, highlight = root_highlight },
            },
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    config = {
                        marks = {
                            CustomReview = { text = "?", priority = 99, highlight = "Ignored" },
                            ProfileOnly = { text = "?", priority = 9, highlight = profile_highlight },
                        },
                    },
                },
                {
                    match = { filetypes = { "text" } },
                    config = {
                        marks = {
                            ProfileOnly = { text = "x", priority = 19, highlight = "IgnoredAgain" },
                            SecondOnly = { text = "s", priority = 10, highlight = "Question" },
                        },
                    },
                },
            },
        },
    })

    root_highlight.fg = "#000000"
    profile_highlight.fg = "#000000"
    local types = config.get_minimap().overlays.types
    expect.equality(types.Cursor, nil)
    expect.equality(types.CustomReview, {
        priority = 8,
        highlight = { fg = "#123456", bold = true },
        group = "ScrollbarMinimapCustomReview",
    })
    expect.equality(types.ProfileOnly, {
        priority = 9,
        highlight = { fg = "#abcdef" },
        group = "ScrollbarMinimapProfileOnly",
    })
    expect.equality(types.SecondOnly, {
        priority = 10,
        highlight = "Question",
        group = "ScrollbarMinimapSecondOnly",
    })
end

T["top-level overlay validation is atomic"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")
    local before_scrollbar = config.set({
        scrollbar = { visibility = "active" },
        minimap = { enabled = true, width = 80 },
    })
    local before_minimap = config.get_minimap()

    local ok, err = pcall(config.set, {
        scrollbar = { visibility = "all" },
        minimap = { overlays = { types = { CustomReview = { priority = 1 } } } },
    })
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match("CustomReview%.highlight is required"), nil)
    expect.equality(config.get(), before_scrollbar)
    expect.equality(config.get_minimap(), before_minimap)
end

T["top-level validation rejects cross-subsystem public group collisions atomically"] = function()
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.presets"] = nil
    local config = require("scrollbar.config")
    local before_scrollbar = config.set({
        scrollbar = { visibility = "active" },
        minimap = { enabled = true },
    })
    local before_minimap = config.get_minimap()

    for _, mark_type in ipairs({ "Track", "Handle", "SearchThumb", "MinimapSearch" }) do
        local ok, err = pcall(config.set, {
            scrollbar = {
                marks = {
                    [mark_type] = { text = "!", priority = 1, highlight = "Special" },
                },
            },
            minimap = { enabled = true },
        })
        expect.equality(ok, false)
        expect.no_equality(tostring(err):match("highlight group"), nil)
        expect.equality(config.get(), before_scrollbar)
        expect.equality(config.get_minimap(), before_minimap)
    end
end

return T
