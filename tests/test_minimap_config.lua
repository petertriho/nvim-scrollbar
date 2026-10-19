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

local function minimap()
    return require("scrollbar.minimap.config")
end

local function top()
    return require("scrollbar.config")
end

local function set(overrides)
    return minimap().set(overrides)
end

local function expect_error(fn, overrides, pattern)
    local ok, err = pcall(fn, overrides)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

local function expect_invalid(overrides, pattern)
    expect_error(set, overrides, pattern)
end

local function expect_top_invalid(overrides, pattern)
    expect_error(top().set, overrides, pattern)
end

local function with_groups(specs)
    for mark_type, spec in pairs(specs) do
        spec.group = "ScrollbarMinimap" .. mark_type
    end
    return specs
end

local FULL_MARKS = with_groups({
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

local DEFAULT_EXCLUDED_FILETYPES = {
    ["blink-cmp-menu"] = true,
    dropbar_menu = true,
    dropbar_menu_fzf = true,
    DressingInput = true,
    cmp_docs = true,
    cmp_menu = true,
    noice = true,
    prompt = true,
    TelescopePrompt = true,
}

T["defaults to disabled with sensible defaults"] = function()
    local result = set()

    expect.equality(result.enabled, false)
    expect.equality(result.show, true)
    expect.equality(result.visibility, "all")
    expect.equality(result.set_highlights, true)
    expect.equality(result.max_lines, false)
    expect.equality(result.autohide, false)
    expect.equality(result.throttle_ms, 50)
    expect.equality(result.backend, "worker")
    expect.equality(result.background_blend, false)
    expect.equality(result.width, 16)
    expect.equality(result.height, false)
    expect.equality(result.placement, {
        relative = "window",
        anchor = "NE",
        row = 0,
        col = 0,
        zindex = 50,
        stack = "inner",
    })
    expect.equality(result.blend, 0)
    expect.equality(result.hide_on_cursor, true)
    expect.equality(result.mouse, true)
    expect.equality(result.viewport, true)
    expect.equality(result.scale, "fixed")
    expect.equality(result.encoding, "braille")
    expect.equality(result.columns_per_dot, 4)
    expect.equality(result.exclude, {
        buftypes = { terminal = true },
        filetypes = DEFAULT_EXCLUDED_FILETYPES,
    })
    expect.equality(result.marks, FULL_MARKS)
    for _, removed in ipairs({
        "preset",
        "presets",
        "profiles",
        "update",
        "float",
        "background",
        "overlays",
        "providers",
        "show_viewport",
        "content_glyph",
        "glyph",
        "excluded_buftypes",
        "excluded_filetypes",
    }) do
        expect.equality(rawget(result, removed), nil)
    end
end

T["defaults core minimap providers on and integrations and semantics off"] = function()
    top().set({ minimap = { enabled = true } })
    local plan = top().get_provider_plan()

    for _, name in ipairs({ "cursor", "diagnostic", "search", "marks" }) do
        expect.equality(plan[name].consumers.minimap, true)
    end
    expect.equality(plan.search.options, { backend = "worker" })
    expect.equality(plan.marks.options, { letters = true, numbers = false })
    for _, name in ipairs({
        "gitsigns",
        "mini_diff",
        "signify",
        "vgit",
        "ale",
        "coc",
        "treesitter",
        "lsp_semantic_tokens",
    }) do
        expect.equality(plan[name].consumers, { scrollbar = false, minimap = false })
        expect.equality(plan[name].options, false)
    end
end

T["get lazily initializes and returns the same active config"] = function()
    local first = minimap().get()
    expect.equality(first.enabled, false)

    local second = minimap().get()
    expect.equality(second, first)
end

T["accepts the complete valid schema and deep copies inputs"] = function()
    local excluded_filetypes = { TelescopePrompt = { scrollbar = false } }
    local custom_highlight = { fg = "#abcdef" }
    top().set({
        set_highlights = false,
        exclude = {
            buftypes = { nofile = { scrollbar = false } },
            filetypes = excluded_filetypes,
        },
        marks = {
            CustomReview = { text = "!", priority = 8, highlight = custom_highlight },
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
        minimap = {
            enabled = true,
            show = false,
            visibility = "active",
            max_lines = 5000,
            autohide = { delay_ms = 250 },
            throttle_ms = 0,
            backend = "sync",
            background_blend = 65,
            width = 120,
            height = 40,
            placement = {
                relative = "window",
                anchor = "SW",
                row = -1,
                col = 2,
                zindex = 90,
                stack = "below",
            },
            blend = 35,
            hide_on_cursor = false,
            mouse = false,
            viewport = false,
            scale = "fit",
            encoding = "block",
            columns_per_dot = 2,
            marks = {
                Error = { priority = 0 },
                Hint = false,
            },
        },
    })
    local result = top().get_minimap()

    expect.equality(result.enabled, true)
    expect.equality(result.show, false)
    expect.equality(result.visibility, "active")
    expect.equality(result.set_highlights, false)
    expect.equality(result.max_lines, 5000)
    expect.equality(result.autohide, { delay_ms = 250 })
    expect.equality(result.throttle_ms, 0)
    expect.equality(result.backend, "sync")
    expect.equality(result.background_blend, 65)
    expect.equality(result.width, 120)
    expect.equality(result.height, 40)
    expect.equality(
        result.placement,
        { relative = "window", anchor = "SW", row = -1, col = 2, zindex = 90, stack = "below" }
    )
    expect.equality(result.blend, 35)
    expect.equality(result.hide_on_cursor, false)
    expect.equality(result.mouse, false)
    expect.equality(result.viewport, false)
    expect.equality(result.scale, "fit")
    expect.equality(result.encoding, "block")
    expect.equality(result.columns_per_dot, 2)
    expect.equality(result.exclude.buftypes, { terminal = true, nofile = true })
    expect.equality(result.exclude.filetypes, DEFAULT_EXCLUDED_FILETYPES)
    expect.equality(result.marks.Error, {
        priority = 0,
        highlight = "DiagnosticVirtualTextError",
        group = "ScrollbarMinimapError",
    })
    expect.equality(result.marks.Hint, nil)
    expect.equality(result.marks.Warn, {
        priority = 3,
        highlight = "DiagnosticVirtualTextWarn",
        group = "ScrollbarMinimapWarn",
    })
    expect.equality(result.marks.CustomReview, {
        priority = 8,
        highlight = { fg = "#abcdef" },
        group = "ScrollbarMinimapCustomReview",
    })

    local plan = top().get_provider_plan()
    expect.equality(plan.search.options, { incsearch = true, backend = "sync" })
    expect.equality(plan.marks.options, { letters = false, numbers = true })
    expect.equality(plan.treesitter.consumers, { scrollbar = false, minimap = true })
    expect.equality(plan.lsp_semantic_tokens.consumers, { scrollbar = false, minimap = true })
    expect.equality(plan.cursor.options, false)

    excluded_filetypes.TelescopePrompt = false
    custom_highlight.fg = "#000000"
    expect.equality(result.exclude.filetypes.TelescopePrompt, true)
    expect.equality(result.marks.CustomReview.highlight, { fg = "#abcdef" })
end

T["rejects unknown and removed top-level keys"] = function()
    for _, key in ipairs({
        "unknown",
        "handle",
        "layout",
        "presets",
        "providers",
        "set_highlights",
        "update",
        "float",
        "background",
        "overlays",
        "show_viewport",
        "content_glyph",
        "glyph",
        "excluded_buftypes",
        "excluded_filetypes",
        "syntax_highlighting",
        "show_cursor_row",
        "content_glyphs",
    }) do
        expect_invalid({ [key] = {} }, "unknown option 'minimap%." .. key .. "'")
    end
    expect_invalid({ glyph = "#" }, "unknown option 'minimap%.glyph' %(use 'encoding'")
    expect_invalid({ preset = "default" }, "minimap%.preset: unknown preset 'default'")
    expect_invalid({ preset = 1 }, "minimap%.preset must be a string")
end

T["rejects unknown nested keys"] = function()
    expect_invalid({ autohide = { extra = true } }, "unknown option 'minimap%.autohide%.extra'")
    expect_invalid({ placement = { extra = true } }, "unknown option 'minimap%.placement%.extra'")
    expect_invalid({ placement = { gutter = "overlap" } }, "unknown option 'minimap%.placement%.gutter'")
    expect_invalid(
        { placement = { gutter_position = "inner" } },
        "unknown option 'minimap%.placement%.gutter_position'"
    )
    expect_invalid({ marks = { Error = { text = "!" } } }, "unknown option 'minimap%.marks%.Error%.text'")
    expect_top_invalid({ providers = { custom = true } }, "unknown option 'providers%.custom'")
    expect_top_invalid({ providers = { search = { extra = true } } }, "unknown option 'providers%.search%.extra'")
end

T["rejects invalid scalar and enum values"] = function()
    expect_invalid({ enabled = "yes" }, "minimap%.enabled must be a boolean")
    expect_invalid({ show = 1 }, "minimap%.show must be a boolean")
    expect_invalid({ visibility = "current" }, "minimap%.visibility must be one of")
    expect_invalid({ max_lines = 0 }, "minimap%.max_lines must be false or a positive integer")
    expect_invalid({ max_lines = -1 }, "minimap%.max_lines must be false or a positive integer")
    expect_invalid({ width = 0 }, "minimap%.width must be a positive integer")
    expect_invalid({ width = "wide" }, "minimap%.width must be a positive integer")
    expect_invalid({ width = false }, "minimap%.width must be a positive integer")
    expect_invalid({ height = -5 }, "minimap%.height must be false or a positive integer")
    expect_invalid({ backend = "remote" }, "minimap%.backend must be one of")
    expect_invalid({ throttle_ms = -1 }, "minimap%.throttle_ms must be a non%-negative integer")
    expect_invalid({ autohide = "yes" }, "minimap%.autohide must be a boolean or table")
    expect_invalid({ autohide = { delay_ms = 0 } }, "minimap%.autohide%.delay_ms must be a positive integer")
    for _, blend in ipairs({ true, -1, 1.5, 101 }) do
        expect_invalid(
            { background_blend = blend },
            "minimap%.background_blend must be false or an integer between 0 and 100"
        )
    end
    expect_invalid({ placement = { zindex = 0 } }, "minimap%.placement%.zindex must be a positive integer")
    expect_invalid({ blend = -1 }, "minimap%.blend must be an integer between 0 and 100")
    expect_invalid({ blend = 101 }, "minimap%.blend must be an integer between 0 and 100")
    expect_invalid({ hide_on_cursor = 1 }, "minimap%.hide_on_cursor must be a boolean")
    expect_invalid({ placement = { anchor = "C" } }, "minimap%.placement%.anchor must be one of")
    expect_invalid({ placement = { relative = "screen" } }, "minimap%.placement%.relative must be one of")
    expect_invalid({ placement = { row = 1.5 } }, "minimap%.placement%.row must be an integer")
    expect_invalid(
        { placement = { stack = "beside" } },
        "minimap%.placement%.stack must be one of: above, below, inner, outer"
    )
    expect_invalid({ placement = { stack = false } }, "minimap%.placement%.stack must be one of")
    expect_invalid({ mouse = 1 }, "minimap%.mouse must be a boolean")
    expect_invalid({ mouse = { enabled = false } }, "minimap%.mouse must be a boolean")
    expect_invalid({ viewport = "yes" }, "minimap%.viewport must be a boolean")
    expect_invalid({ scale = "scroll" }, "minimap%.scale must be one of: fit, fixed")
    expect_invalid({ encoding = "half" }, "minimap%.encoding must be one of: block, braille")
    expect_invalid({ columns_per_dot = 0 }, "minimap%.columns_per_dot must be a positive integer")
    expect_invalid({ columns_per_dot = 1.5 }, "minimap%.columns_per_dot must be a positive integer")
    expect_top_invalid({ providers = { search = "yes" } }, "providers%.search must be a boolean or table")
    expect_top_invalid({ providers = { marks = { letters = "yes" } } }, "providers%.marks%.letters must be a boolean")
    expect_top_invalid(
        { providers = { treesitter = { minimap = 1 } } },
        "providers%.treesitter%.minimap must be a boolean"
    )
    expect_top_invalid(
        { providers = { treesitter = { scrollbar = true } } },
        "providers%.treesitter%.scrollbar: provider 'treesitter' does not support the scrollbar"
    )
end

T["rejects malformed table values"] = function()
    expect_invalid({ placement = false }, "minimap%.placement must be a table")
    expect_invalid({ marks = true }, "minimap%.marks must be false or a table")
    expect_top_invalid({ exclude = { buftypes = "terminal" } }, "exclude%.buftypes must be a dense list")
    expect_top_invalid({ exclude = { filetypes = { "lua", false } } }, "exclude%.filetypes%[2%] must be a string")
    expect_top_invalid(
        { exclude = { buftypes = { [1] = "terminal", [3] = "nofile" } } },
        "exclude%.buftypes must be a dense list"
    )
    expect_top_invalid(
        { exclude = { filetypes = { lua = { minimap = 1 } } } },
        "exclude%.filetypes%.lua%.minimap must be a boolean"
    )
end

T["accepts every scale and encoding"] = function()
    for _, scale in ipairs({ "fixed", "fit" }) do
        expect.equality(set({ scale = scale }).scale, scale)
    end
    for _, encoding in ipairs({ "braille", "block" }) do
        expect.equality(set({ encoding = encoding }).encoding, encoding)
    end
    expect.equality(set({ columns_per_dot = 1 }).columns_per_dot, 1)
end

T["rejects malformed mark override maps and specs"] = function()
    expect_invalid({ marks = { "Error" } }, "minimap%.marks has invalid mark type 1")
    expect_invalid({ marks = { [1] = false } }, "minimap%.marks has invalid mark type 1")
    expect_invalid({ marks = { ["not-a-type"] = false } }, 'minimap%.marks has invalid mark type "not%-a%-type"')
    expect_invalid({ marks = "Error" }, "minimap%.marks must be false or a table")
    expect_invalid({ marks = { Error = true } }, "minimap%.marks%.Error must be false or a table")
    for _, priority in ipairs({ -1, 1.5, math.huge }) do
        expect_invalid(
            { marks = { Error = { priority = priority } } },
            "minimap%.marks%.Error%.priority must be a non%-negative integer"
        )
    end
    expect_invalid(
        { marks = { Error = { highlight = "" } } },
        "minimap%.marks%.Error%.highlight must be a non%-empty string or table"
    )
    expect_invalid(
        { marks = { Error = { highlight = false } } },
        "minimap%.marks%.Error%.highlight must be a non%-empty string or table"
    )
    expect_invalid(
        { marks = { CustomReview = { priority = 8, highlight = "Special" } } },
        "minimap%.marks%.CustomReview: unknown mark type 'CustomReview'%. Define it in the top%-level marks table"
    )
end

T["custom mark types come from the top-level registry with complete specs"] = function()
    expect_top_invalid(
        { marks = { CustomReview = { priority = 8, highlight = "Special" } } },
        "marks%.CustomReview%.text is required for a new mark type"
    )
    expect_top_invalid(
        { marks = { CustomReview = { text = "!", highlight = "Special" } } },
        "marks%.CustomReview%.priority is required for a new mark type"
    )

    top().set({
        marks = {
            CustomReview = { text = "!", priority = 8, highlight = "Special" },
            Future_mark = { text = "f", priority = 9, highlight = { fg = "#abcdef" } },
        },
    })
    local result = top().get_minimap()
    expect.equality(result.marks.CustomReview, {
        priority = 8,
        highlight = "Special",
        group = "ScrollbarMinimapCustomReview",
    })
    expect.equality(result.marks.Future_mark, {
        priority = 9,
        highlight = { fg = "#abcdef" },
        group = "ScrollbarMinimapFuture_mark",
    })
end

T["rejects mark overrides for static minimap groups and the cursor"] = function()
    for _, mark_type in ipairs({ "Base", "Content", "Viewport" }) do
        expect_invalid(
            { marks = { [mark_type] = { priority = 1, highlight = "Special" } } },
            "minimap%.marks%." .. mark_type .. ": conflicts with the static ScrollbarMinimap" .. mark_type .. " group"
        )
    end
    expect_invalid(
        { marks = { Cursor = false } },
        "minimap%.marks%.Cursor: the minimap draws the cursor with ScrollbarMinimapCursor"
    )
    expect_invalid({ marks = { Cursor = {} } }, "providers%.cursor = { minimap = false }")

    -- A registered type with a static minimap name stays out of the minimap only.
    top().set({ marks = { Content = { text = "c", priority = 1, highlight = "Special" } } })
    expect.equality(top().get_minimap().marks.Content, nil)
    expect.no_equality(top().get().marks.Content, nil)
end

T["partial overrides inherit registry specs and false hides only selected types"] = function()
    local result = set({
        marks = {
            Error = { priority = 0 },
            Hint = false,
        },
    })

    expect.equality(result.marks.Error, {
        priority = 0,
        highlight = "DiagnosticVirtualTextError",
        group = "ScrollbarMinimapError",
    })
    expect.equality(result.marks.Hint, nil)
    expect.equality(result.marks.Warn, FULL_MARKS.Warn)
    expect.equality(result.marks.Cursor, nil)
end

T["false hides every mark type"] = function()
    expect.equality(set({ marks = false }).marks, {})
end

T["root and profile overrides can re-show types that the registry hides"] = function()
    top().set({
        marks = { Search = false, Hint = false },
        minimap = {
            marks = { Search = {} },
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    marks = { Hint = {} },
                },
            },
        },
    })
    local root = top().get_minimap()
    local profile = minimap().get_variants()[2].config

    expect.equality(root.marks.Search, FULL_MARKS.Search)
    expect.equality(root.marks.Hint, nil)
    expect.equality(profile.marks.Hint, {
        priority = 5,
        highlight = "DiagnosticVirtualTextHint",
        group = "ScrollbarMinimapProfile1.Hint",
    })
    expect.equality(profile.marks.Search.priority, 1)
end

T["a profile table re-shows a type that the root hid"] = function()
    set({
        marks = { Warn = false },
        profiles = {
            { match = { filetypes = { "lua" } }, marks = { Warn = {} } },
            { match = { filetypes = { "text" } }, width = 20 },
        },
    })
    local variants = minimap().get_variants()

    expect.equality(variants[1].config.marks.Warn, nil)
    expect.equality(variants[2].config.marks.Warn, {
        priority = 3,
        highlight = "DiagnosticVirtualTextWarn",
        group = "ScrollbarMinimapProfile1.Warn",
    })
    expect.equality(variants[3].config.marks.Warn, nil)
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
        marks = { Error = { priority = 0 } },
        profiles = {
            { match = { filetypes = { "lua" } }, width = 60 },
        },
    })

    local result = set()
    expect.equality(result.enabled, false)
    expect.equality(result.width, 16)
    expect.equality(result.backend, "worker")
    expect.equality(result.marks, FULL_MARKS)
    expect.equality(#minimap().get_variants(), 1)
    expect.equality(rawget(result, "profiles"), nil)
end

T["compiles profile variants with first-match precedence"] = function()
    local root = set({
        width = 80,
        height = false,
        profiles = {
            {
                match = { filetypes = { "lua" } },
                width = 60,
                height = 30,
            },
            {
                match = { buftypes = { "nofile" } },
                width = 40,
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
        expect.equality(rawget(variant.config, "match"), nil)
        expect.equality(rawget(variant.config, "profiles"), nil)
    end
end

T["rejects malformed profile matchers and options"] = function()
    expect_invalid({ profiles = "lua" }, "minimap%.profiles must be a dense list")
    expect_invalid(
        { profiles = { [2] = { match = { when = function() end } } } },
        "minimap%.profiles must be a dense list"
    )
    expect_invalid({ profiles = { "lua" } }, "minimap%.profiles%[1%] must be a table")
    expect_invalid({ profiles = { {} } }, "minimap%.profiles%[1%]%.match is required")
    expect_invalid({ profiles = { { match = "lua" } } }, "minimap%.profiles%[1%]%.match must be a table")
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
        { profiles = { { match = { when = function() end }, preset = "default" } } },
        "minimap%.profiles%[1%]%.preset: unknown preset 'default'"
    )
    expect_invalid(
        { profiles = { { match = { filetypes = { "lua" } }, width = 0 } } },
        "minimap%.profiles%[1%]%.width must be a positive integer"
    )
end

T["profiles reject global options with a dedicated error"] = function()
    for _, global in ipairs({
        { enabled = false },
        { show = false },
        { visibility = "active" },
        { autohide = true },
        { max_lines = 100 },
        { throttle_ms = 50 },
        { backend = "sync" },
        { background_blend = 40 },
        { profiles = {} },
    }) do
        local key = next(global)
        local profile = vim.tbl_extend("error", { match = { filetypes = { "lua" } } }, global)
        expect_invalid(
            { profiles = { profile } },
            "minimap%.profiles%[1%]%." .. key .. " is a global option and cannot be set in a profile"
        )
    end
end

T["profiles reject removed and shared options"] = function()
    for _, key in ipairs({
        "config",
        "set_highlights",
        "exclude",
        "providers",
        "update",
        "float",
        "background",
        "overlays",
        "excluded_filetypes",
        "syntax_highlighting",
    }) do
        expect_invalid(
            { profiles = { { match = { filetypes = { "lua" } }, [key] = {} } } },
            "unknown option 'minimap%.profiles%[1%]%." .. key .. "'"
        )
    end
end

T["accepts every placement.stack value"] = function()
    for _, stack in ipairs({ "inner", "outer", "above", "below" }) do
        expect.equality(set({ placement = { stack = stack } }).placement.stack, stack)
    end
end

T["profiles allow display-only overrides"] = function()
    local result = set({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                width = 60,
                height = 30,
                placement = { anchor = "NW", zindex = 70, stack = "outer" },
                blend = 20,
                hide_on_cursor = false,
                marks = false,
                viewport = false,
                mouse = false,
                scale = "fit",
                encoding = "block",
                columns_per_dot = 8,
            },
        },
    })
    local profile = minimap().get_variants()[2].config
    expect.equality(profile.width, 60)
    expect.equality(profile.height, 30)
    expect.equality(
        profile.placement,
        { relative = "window", anchor = "NW", row = 0, col = 0, zindex = 70, stack = "outer" }
    )
    expect.equality(result.placement.stack, "inner")
    expect.equality(profile.blend, 20)
    expect.equality(profile.hide_on_cursor, false)
    expect.equality(profile.marks, {})
    expect.equality(profile.viewport, false)
    expect.equality(profile.mouse, false)
    expect.equality(profile.scale, "fit")
    expect.equality(profile.encoding, "block")
    expect.equality(profile.columns_per_dot, 8)
    expect.equality(result.scale, "fixed")
    expect.equality(result.width, 16)
    expect.equality(result.marks, FULL_MARKS)
end

T["profile variants inherit root global options"] = function()
    local root = set({
        visibility = "active",
        autohide = { delay_ms = 300 },
        throttle_ms = 5,
        background_blend = 35,
        profiles = {
            {
                match = { filetypes = { "lua" } },
                width = 40,
            },
        },
    })
    local profile = minimap().get_variants()[2].config

    expect.equality(profile.visibility, "active")
    expect.equality(profile.autohide, { delay_ms = 300 })
    expect.equality(profile.throttle_ms, 5)
    expect.equality(profile.background_blend, 35)
    expect.equality(profile.exclude, root.exclude)
    expect.equality(profile.width, 40)
end

T["commits root and variants atomically on profile failure"] = function()
    local before = set({
        width = 100,
        profiles = {
            { match = { filetypes = { "lua" } }, width = 60 },
        },
    })
    local before_variants = minimap().get_variants()

    expect_invalid({
        profiles = {
            { match = { filetypes = { "lua" } }, width = 0 },
            { match = { buftypes = { "nofile" } }, height = -1 },
        },
    }, "minimap%.profiles%[1%]%.width must be a positive integer")
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
            { match = { filetypes = { "markdown" } }, width = 10 },
            {
                match = { filetypes = { "lua" }, buftypes = { "nofile" } },
                width = 50,
            },
            { match = { filetypes = { "lua" } }, width = 70 },
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
                width = 40,
            },
        },
    })

    expect.equality(minimap().select(winid).variant_id, 0)
    expect.equality(minimap().select(winid).variant_id, 0)
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1][1]:match("minimap profile 1 matcher failed"), nil)
    failure = "second"
    expect.equality(minimap().select(winid).variant_id, 0)
    expect.equality(#notifications, 2)
    failure = nil
    expect.equality(minimap().select(winid).variant_id, 1)
    vim.notify = original_notify
end

T["integrates with the top-level scrollbar dispatcher"] = function()
    local config = top()

    config.set({})
    expect.equality(config.get_minimap().enabled, false)
    expect.equality(config.get_minimap().width, 16)
    expect.equality(config.get_minimap().backend, "worker")

    config.set({ providers = { treesitter = true }, minimap = { enabled = true, width = 100 } })
    expect.equality(config.get_minimap().enabled, true)
    expect.equality(config.get_minimap().width, 100)
    expect.equality(config.get_provider_plan().treesitter.consumers, { scrollbar = false, minimap = true })

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
    local config = top()
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
                { match = { filetypes = { "lua" } }, width = 40 },
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

T["provider plan applies per-renderer targets from one table"] = function()
    local config = top()
    config.set({
        providers = {
            cursor = { scrollbar = false },
            diagnostic = { minimap = false },
            search = { incsearch = true, backend = "sync" },
        },
        minimap = { enabled = true },
    })

    local plan = config.get_provider_plan()
    expect.equality(plan.cursor.consumers, { scrollbar = false, minimap = true })
    expect.equality(plan.cursor.options, true)
    expect.equality(plan.diagnostic.consumers, { scrollbar = true, minimap = false })
    expect.equality(plan.search.consumers, { scrollbar = true, minimap = true })
    expect.equality(plan.search.options, { incsearch = true, backend = "sync" })
    expect.equality(plan.search.targets, { scrollbar = true, minimap = true })
    expect.equality(plan.search.execution, "parent")
end

T["invalid provider options fail setup atomically"] = function()
    local config = top()
    local before_scrollbar = config.set({
        providers = { search = { backend = "worker" } },
        scrollbar = {
            profiles = {
                { match = { filetypes = { "lua" } }, preset = "minimal" },
            },
        },
        minimap = {
            enabled = true,
            profiles = {
                { match = { filetypes = { "lua" } }, width = 40 },
            },
        },
    })
    local before_scrollbar_variants = config.get_variants()
    local before_minimap = config.get_minimap()
    local before_minimap_variants = minimap().get_variants()
    local before_plan = config.get_provider_plan()
    expect.equality(before_plan.search.options, { backend = "worker" })

    local ok, err = pcall(config.set, {
        ---@diagnostic disable-next-line: assign-type-mismatch
        providers = { search = { backend = "remote" } },
        scrollbar = { visibility = "active" },
        minimap = { enabled = true, width = 80 },
    })

    expect.equality(ok, false)
    expect.no_equality(tostring(err):match("providers%.search%.backend must be one of"), nil)
    expect.equality(config.get(), before_scrollbar)
    expect.equality(config.get_variants(), before_scrollbar_variants)
    expect.equality(config.get_minimap(), before_minimap)
    expect.equality(minimap().get_variants(), before_minimap_variants)
    expect.equality(config.get_provider_plan(), before_plan)
end

T["disabled minimap contributes no provider demand"] = function()
    local config = top()
    local ok = pcall(config.set, {
        providers = {
            cursor = { scrollbar = false },
            search = { backend = "sync" },
        },
        minimap = { enabled = false },
    })

    expect.equality(ok, true)
    local plan = config.get_provider_plan()
    expect.equality(plan.cursor.consumers, { scrollbar = false, minimap = false })
    expect.equality(plan.cursor.options, false)
    expect.equality(plan.search.consumers, { scrollbar = true, minimap = false })
    expect.equality(plan.search.options, { backend = "sync" })
end

T["minimap marks resolve from the deep-copied registry independently of scrollbar overrides"] = function()
    local config = top()
    local registry_highlight = { fg = "#123456", bold = true }
    config.set({
        marks = {
            CustomReview = { text = "!", priority = 8, highlight = registry_highlight },
        },
        scrollbar = {
            marks = {
                CustomReview = { priority = 99, highlight = "Ignored" },
                Search = false,
            },
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    marks = { CustomReview = false },
                },
            },
        },
    })

    registry_highlight.fg = "#000000"
    local marks = config.get_minimap().marks
    expect.equality(marks.Cursor, nil)
    expect.equality(marks.CustomReview, {
        priority = 8,
        highlight = { fg = "#123456", bold = true },
        group = "ScrollbarMinimapCustomReview",
    })
    expect.equality(marks.Search, FULL_MARKS.Search)
    expect.equality(config.get().marks.CustomReview.priority, 99)
    expect.equality(config.get().marks.Search, nil)
end

T["top-level mark validation is atomic"] = function()
    local config = top()
    local before_scrollbar = config.set({
        scrollbar = { visibility = "active" },
        minimap = { enabled = true, width = 80 },
    })
    local before_minimap = config.get_minimap()

    local ok, err = pcall(config.set, {
        scrollbar = { visibility = "all" },
        minimap = { marks = { CustomReview = { priority = 1 } } },
    })
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match("unknown mark type 'CustomReview'"), nil)
    expect.equality(config.get(), before_scrollbar)
    expect.equality(config.get_minimap(), before_minimap)
end

T["top-level validation rejects cross-subsystem public group collisions atomically"] = function()
    local config = top()
    local before_scrollbar = config.set({
        scrollbar = { visibility = "active" },
        minimap = { enabled = true },
    })
    local before_minimap = config.get_minimap()

    for _, mark_type in ipairs({ "Track", "Handle", "SearchThumb", "MinimapSearch" }) do
        local ok, err = pcall(config.set, {
            marks = {
                [mark_type] = { text = "!", priority = 1, highlight = "Special" },
            },
            minimap = { enabled = true },
        })
        expect.equality(ok, false)
        expect.no_equality(tostring(err):match("highlight group"), nil)
        expect.equality(config.get(), before_scrollbar)
        expect.equality(config.get_minimap(), before_minimap)
    end
end

T["a disabled minimap claims no public groups"] = function()
    local config = top()
    local ok, err = pcall(config.set, {
        marks = {
            MinimapSearch = { text = "!", priority = 1, highlight = "Special" },
        },
    })
    expect.equality(ok, true, tostring(err))
    expect.no_equality(config.get().marks.MinimapSearch, nil)
end

return T
