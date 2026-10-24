local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.config.presets"] = nil
        end,
    },
})

local function set_top(overrides)
    return require("scrollbar.config").set(overrides)
end

local function set(overrides)
    return set_top({ scrollbar = overrides })
end

local function expect_invalid_top(overrides, pattern)
    local ok, err = pcall(set_top, overrides)
    expect.equality(ok, false)
    if tostring(err):match(pattern) == nil then
        error(string.format("error %q does not match %q", tostring(err), pattern))
    end
end

local function expect_invalid(overrides, pattern)
    expect_invalid_top({ scrollbar = overrides }, pattern)
end

local function layer_kinds(column)
    local result = {}
    for index, layer in ipairs(column) do
        result[index] = layer.kind
    end
    return result
end

local function plan()
    return require("scrollbar.config").get_provider_plan()
end

T["normalizes a fresh one-column default without setup-only state"] = function()
    local first = set_top({
        providers = { search = { incsearch = true, backend = "sync" }, marks = { numbers = true } },
        scrollbar = {
            visibility = "active",
            layout = { columns = { { "track", "marks", "thumb" } } },
            thumb = { text = "#" },
            marks = { Search = { text = "x" }, Mark = { text = "X" } },
        },
    })

    expect.equality(first.visibility, "active")
    expect.equality(first.layout.width, 1)
    expect.equality(layer_kinds(first.layout.columns[1]), { "track", "marks", "thumb" })
    expect.equality(first.thumb.text, "#")
    expect.equality(first.marks.Search.text, { "x" })
    expect.equality(first.marks.Mark.text, { "X" })
    expect.equality(plan().search.options, { incsearch = true, backend = "sync" })
    expect.equality(plan().marks.options, { letters = true, numbers = true })
    expect.equality(rawget(first, "preset"), nil)
    expect.equality(rawget(first, "profiles"), nil)

    first.layout.columns[1][1].priority = 99
    first.marks.Mark.text[1] = "changed"

    local second = set()
    expect.equality(second.enabled, true)
    expect.equality(second.show, true)
    expect.equality(second.visibility, "all")
    expect.equality(second.autohide, false)
    expect.equality(second.throttle_ms, 16)
    expect.equality(second.unit, "line")
    expect.equality(second.mouse, true)
    expect.equality(second.hide_on_cursor, true)
    expect.equality(second.placement, {
        relative = "window",
        anchor = "NE",
        row = 0,
        col = 0,
        gutter = "inner",
        zindex = 50,
    })
    expect.equality(second.layout.direction, "auto")
    expect.equality(second.layout.width, 1)
    expect.equality(layer_kinds(second.layout.columns[1]), { "track", "thumb", "marks" })
    expect.equality(second.layout.columns[1][1].priority, 1)
    expect.equality(second.layout.thumb, { first_column = 1, last_column = 1, width = 1 })
    expect.equality(second.layout.catchall_lane, 1)
    expect.equality(second.thumb, {
        text = " ",
        blend = 30,
        highlight = "PmenuThumb",
        hide_if_all_visible = true,
    })
    expect.equality(second.marks.Mark, { text = {}, priority = 1, highlight = "Special" })
    expect.equality(plan().marks.options, { letters = true, numbers = false })
    expect.equality(plan().search.options, { backend = "worker" })
end

T["applies the root preset below root options and replaces lists atomically"] = function()
    local result = set({
        preset = "vscode",
        layout = { columns = { { "marks", "thumb" } } },
        thumb = { text = "V" },
        marks = { Search = { text = { "R" } } },
    })

    expect.equality(result.layout.width, 1)
    expect.equality(layer_kinds(result.layout.columns[1]), { "marks", "thumb" })
    expect.equality(result.thumb.text, "V")
    expect.equality(result.thumb.blend, 20)
    expect.equality(result.marks.Search.text, { "R" })
end

T["compiles auto ltr and rtl directions for east and west anchors"] = function()
    local columns = {
        { "track" },
        { { types = { "Search" } } },
        { "thumb" },
    }
    local function kinds(direction, anchor)
        local result = set({
            placement = { anchor = anchor },
            layout = { direction = direction, columns = columns },
        })
        local physical = {}
        for index, column in ipairs(result.layout.columns) do
            physical[index] = layer_kinds(column)[1]
        end
        return physical, result.layout.inward
    end

    expect.equality({ kinds("auto", "NE") }, { { "track", "marks", "thumb" }, "left" })
    expect.equality({ kinds("auto", "NW") }, { { "thumb", "marks", "track" }, "right" })
    expect.equality({ kinds("ltr", "NE") }, { { "track", "marks", "thumb" }, "left" })
    expect.equality({ kinds("ltr", "NW") }, { { "track", "marks", "thumb" }, "right" })
    expect.equality({ kinds("rtl", "NE") }, { { "thumb", "marks", "track" }, "left" })
    expect.equality({ kinds("rtl", "NW") }, { { "thumb", "marks", "track" }, "right" })
end

T["normalizes typed lanes catch-all routing and optional components"] = function()
    local result = set({
        layout = {
            columns = {
                { { types = { "Future", "Error" } } },
                { { types = { "Future", "Error" } }, "marks" },
                { "track" },
            },
        },
    })

    expect.equality(result.layout.width, 3)
    expect.equality(result.layout.thumb, false)
    expect.equality(#result.layout.lanes, 2)
    expect.equality(result.layout.lanes[1].columns, { 1, 2 })
    expect.equality(result.layout.lanes[1].types, { "Error", "Future" })
    expect.equality(result.layout.lanes[1].first_column, 1)
    expect.equality(result.layout.lanes[1].last_column, 2)
    expect.equality(result.layout.lanes[2].catch_all, true)
    expect.equality(result.layout.routes.Error, 1)
    expect.equality(result.layout.routes.Future, 1)
    expect.equality(result.layout.catchall_lane, 2)

    local thumb_only = set({ layout = { columns = { { "thumb" }, { "thumb" } } } })
    expect.equality(thumb_only.layout.thumb, { first_column = 1, last_column = 2, width = 2 })
    expect.equality(thumb_only.layout.catchall_lane, false)

    local track_only = set({ layout = { columns = { { "track" } } } })
    expect.equality(track_only.layout.thumb, false)
    expect.equality(track_only.layout.lanes, {})
end

T["normalizes named-mark lane width and stack priorities"] = function()
    local result = set({
        layout = {
            columns = {
                { "track", { types = { "Mark" }, max_width = 5 }, "thumb" },
                { "track", { types = { "Mark" } }, "thumb" },
            },
        },
    })

    expect.equality(result.layout.lanes[1].columns, { 1, 2 })
    expect.equality(result.layout.lanes[1].max_width, 5)
    expect.equality(result.layout.columns[1][1].priority, 1)
    expect.equality(result.layout.columns[1][2].priority, 2)
    expect.equality(result.layout.columns[1][3].priority, 3)
end

T["accepts the complete typed runtime schema"] = function()
    local track_highlight = { bg = "#010203", bold = true }
    local thumb_highlight = { bg = "#112233", blend = 10 }
    local mark_highlight = { fg = "#abcdef", bold = true, cterm = { italic = true } }
    local result = set_top({
        set_highlights = false,
        exclude = { buftypes = { "terminal", "nofile" }, filetypes = { "prompt" } },
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
            coc = false,
        },
        marks = {
            Search = { text = { "-", "=" }, priority = 9, highlight = "Search" },
            Custom = { text = "!", priority = 0, highlight = mark_highlight },
        },
        scrollbar = {
            show = false,
            visibility = "active",
            max_lines = 1000,
            hide_if_all_visible = true,
            autohide = { delay_ms = 750 },
            throttle_ms = 0,
            unit = "screenline",
            placement = {
                relative = "editor",
                anchor = "SW",
                row = -2,
                col = 3,
                gutter = "overlap",
                zindex = 60,
            },
            hide_on_cursor = false,
            layout = {
                direction = "rtl",
                columns = {
                    { "track", "thumb" },
                    { { types = { "Custom", "Search" } }, "marks" },
                },
            },
            track = { highlight = track_highlight },
            mouse = false,
            thumb = {
                text = "#",
                blend = 0,
                highlight = thumb_highlight,
                hide_if_all_visible = false,
            },
        },
    })

    expect.equality(result.show, false)
    expect.equality(result.set_highlights, false)
    expect.equality(result.max_lines, 1000)
    expect.equality(result.autohide, { delay_ms = 750 })
    expect.equality(result.throttle_ms, 0)
    expect.equality(result.unit, "screenline")
    expect.equality(result.placement.row, -2)
    expect.equality(result.placement.gutter, "overlap")
    expect.equality(result.placement.zindex, 60)
    expect.equality(result.hide_on_cursor, false)
    expect.equality(result.mouse, false)
    expect.equality(result.layout.direction, "rtl")
    expect.equality(result.layout.width, 2)
    expect.equality(result.track.highlight, track_highlight)
    expect.equality(result.thumb.highlight, thumb_highlight)
    expect.equality(result.marks.Custom.text, { "!" })
    expect.equality(result.marks.Custom.highlight, mark_highlight)
    expect.equality(result.exclude, {
        buftypes = { terminal = true, nofile = true },
        filetypes = { prompt = true },
    })
    expect.equality(plan().marks.options, { letters = false, numbers = true })
    expect.equality(plan().gitsigns.options, true)
    expect.equality(plan().cursor.options, false)

    result.track.highlight.bg = "#000000"
    result.thumb.highlight.bg = "#000000"
    result.marks.Custom.highlight.cterm.italic = false
    expect.equality(track_highlight.bg, "#010203")
    expect.equality(thumb_highlight.bg, "#112233")
    expect.equality(mark_highlight.cterm.italic, true)
end

T["accepts autohide as a boolean"] = function()
    expect.equality(set({ autohide = true }).autohide, { delay_ms = 1000 })
    expect.equality(set({ autohide = false }).autohide, false)
    expect_invalid({ autohide = "yes" }, "scrollbar.autohide must be a boolean or table")
end

T["rejects removed options and unknown keys"] = function()
    expect_invalid({ float = { zindex = 2 } }, "unknown option 'scrollbar.float'")
    expect_invalid({ render = { geometry = "line" } }, "unknown option 'scrollbar.render'")
    expect_invalid({ update = { interval_ms = 1 } }, "unknown option 'scrollbar.update'")
    expect_invalid({ presets = {} }, "unknown option 'scrollbar.presets'")
    expect_invalid({ providers = {} }, "unknown option 'scrollbar.providers'")
    expect_invalid({ excluded_filetypes = {} }, "unknown option 'scrollbar.excluded_filetypes'")
    expect_invalid({ set_highlights = false }, "unknown option 'scrollbar.set_highlights'")
    expect_invalid({ handle = {} }, "unknown option 'scrollbar.handle'")
    expect_invalid({ thumb = { column = 1 } }, "unknown option 'scrollbar.thumb.column'")
    expect_invalid({ thumb = { width = 1 } }, "unknown option 'scrollbar.thumb.width'")
    expect_invalid({ marks = { Search = { column = 1 } } }, "unknown option 'scrollbar.marks.Search.column'")
    expect_invalid({ layout = { rows = {} } }, "unknown option 'scrollbar.layout.rows'")
    expect_invalid({ placement = { win = 1 } }, "unknown option 'scrollbar.placement.win'")
    expect_invalid(
        { placement = { gutter_position = "inner" } },
        "unknown option 'scrollbar.placement.gutter_position'"
    )
    expect_invalid({ marks = { Search = { gui = "bold" } } }, "unknown option 'scrollbar.marks.Search.gui'")
    expect_invalid({ autohide = { enabled = true } }, "unknown option 'scrollbar.autohide.enabled'")
    expect_invalid_top({ providers = { marks = { max_width = 4 } } }, "unknown option 'providers.marks.max_width'")
    expect_invalid_top({ marks = { Search = { gui = "bold" } } }, "unknown option 'marks.Search.gui'")
end

T["names the replacement of a removed option"] = function()
    local lua = { match = { filetypes = { "lua" } } }
    expect_invalid(
        { update = { interval_ms = 1 } },
        "unknown option 'scrollbar%.update' %(use 'throttle_ms' and 'events'%)$"
    )
    expect_invalid({ autohide = { enabled = true } }, "%(use 'autohide = true' or 'autohide = { delay_ms = n }'%)$")
    expect_invalid(
        { profiles = { vim.tbl_extend("force", lua, { config = {} }) } },
        "unknown option 'scrollbar%.profiles%[1%]%.config' %(set the options directly in the profile%)$"
    )
    expect_invalid(
        { profiles = { vim.tbl_extend("force", lua, { thumb = { show = true } }) } },
        "unknown option 'scrollbar%.profiles%[1%]%.thumb%.show'$"
    )
    expect_invalid_top(
        { minimap = { show_viewport = false } },
        "unknown option 'minimap%.show_viewport' %(use 'viewport'%)$"
    )
    expect_invalid_top(
        { minimap = { profiles = { vim.tbl_extend("force", lua, { content_glyph = "x" }) } } },
        "unknown option 'minimap%.profiles%[1%]%.content_glyph' %(use 'encoding'%)$"
    )
    expect_invalid_top(
        { minimap = { placement = { gutter = "overlap" } } },
        "%(the minimap always overlaps the gutter%)$"
    )
end

T["points a v1 option to the migration guide and the v1 branch"] = function()
    local guide = "See https://github%.com/petertriho/nvim%-scrollbar/blob/main/docs/migration%.md, "
        .. "or pin the 'v1' branch to keep v1%)$"
    expect_invalid_top(
        { handle = { color = "#ffffff" } },
        "unknown option 'handle' %(v1 option: use 'scrollbar%.thumb'%. " .. guide
    )
    expect_invalid_top(
        { handlers = { gitsigns = true } },
        "unknown option 'handlers' %(v1 option: use 'providers'%. " .. guide
    )
    expect_invalid_top({ show = true }, "unknown option 'show' %(v1 option: use 'scrollbar%.show'%. " .. guide)
    expect_invalid_top(
        { marks = { Search = { color = "#ff9e64" } } },
        "unknown option 'marks%.Search%.color' %(v1 option: put an nvim_set_hl%(%) table in 'highlight'%. " .. guide
    )
end

T["rejects malformed layouts and invalid lane spans"] = function()
    expect_invalid({ layout = { direction = "inside" } }, "scrollbar.layout.direction must be one of")
    expect_invalid({ layout = { columns = {} } }, "scrollbar.layout.columns must contain at least one column")
    expect_invalid(
        { layout = { columns = { [1] = { "track" }, [3] = { "thumb" } } } },
        "scrollbar.layout.columns must be a dense list"
    )
    expect_invalid({ layout = { columns = { {} } } }, "layout.columns%[1%] must contain at least one layer")
    expect_invalid(
        { layout = { columns = { { "unknown" } } } },
        "must be 'track', 'thumb', 'marks', or a mark descriptor"
    )
    expect_invalid(
        { layout = { columns = { { { kind = "marks", types = { "Error" } } } } } },
        "unknown option 'scrollbar.layout.columns%[1%]%[1%].kind'"
    )
    expect_invalid({ layout = { columns = { { { max_width = 2 } } } } }, "types is required in a mark descriptor")
    expect_invalid(
        { layout = { columns = { { { types = { "Error" }, extra = true } } } } },
        "unknown option 'scrollbar.layout.columns%[1%]%[1%].extra'"
    )
    expect_invalid({ layout = { columns = { { { types = {} } } } } }, "types must contain at least one type")
    expect_invalid({ layout = { columns = { { { types = { "Error", 2 } } } } } }, "types%[2%] must be a string")
    expect_invalid(
        { layout = { columns = { { "thumb" }, { "track" }, { "thumb" } } } },
        "thumb must occupy one contiguous span"
    )
    expect_invalid(
        { layout = { columns = { { "marks" }, { "track" }, { "marks" } } } },
        "catch%-all marks must occupy one contiguous lane"
    )
    expect_invalid({
        layout = {
            columns = {
                { { types = { "Error" } } },
                { "track" },
                { { types = { "Error" } } },
            },
        },
    }, "mark type 'Error' must occupy one contiguous lane")
    expect_invalid({
        layout = { columns = { { { types = { "Search" }, max_width = 3 } } } },
    }, "max_width is valid only for a lane explicitly selecting Mark")
    expect_invalid({
        layout = {
            columns = {
                { { types = { "Mark" }, max_width = 1 } },
                { { types = { "Mark" } } },
            },
        },
    }, "max_width must be greater than or equal to its base lane width")
end

T["rejects invalid scalar provider mark and text options"] = function()
    expect_invalid({ visibility = "current" }, "scrollbar.visibility must be one of")
    expect_invalid({ unit = "fold" }, "scrollbar.unit must be one of")
    expect_invalid({ placement = { anchor = "C" } }, "scrollbar.placement.anchor must be one of")
    expect_invalid(
        { placement = { gutter = "avoid" } },
        "scrollbar.placement.gutter must be one of: inner, outer, overlap"
    )
    expect_invalid({ placement = { zindex = 0 } }, "scrollbar.placement.zindex must be a positive integer")
    expect_invalid({ show = 1 }, "scrollbar.show must be a boolean")
    expect_invalid({ enabled = "yes" }, "scrollbar.enabled must be a boolean")
    expect_invalid({ mouse = { enabled = true } }, "scrollbar.mouse must be a boolean")
    expect_invalid({ throttle_ms = -1 }, "scrollbar.throttle_ms must be a non%-negative integer")
    expect_invalid({ autohide = { delay_ms = 0 } }, "scrollbar.autohide.delay_ms must be a positive integer")
    expect_invalid({ thumb = { text = "" } }, "scrollbar.thumb.text must have positive display width")
    expect_invalid({ thumb = { blend = 101 } }, "scrollbar.thumb.blend must be an integer between 0 and 100")
    expect_invalid(
        { marks = { Search = { priority = -1 } } },
        "scrollbar.marks.Search.priority must be a non%-negative integer"
    )
    expect_invalid(
        { marks = { Search = { highlight = "" } } },
        "scrollbar.marks.Search.highlight must be a non%-empty string or table"
    )
    expect_invalid_top({ providers = { cursor = "yes" } }, "providers.cursor must be a boolean or table")
    expect_invalid_top({ providers = { cursor = { incsearch = true } } }, "unknown option 'providers.cursor.incsearch'")
    expect_invalid_top({ providers = { search = "yes" } }, "providers.search must be a boolean or table")
    expect_invalid_top({ providers = { search = { backend = "fast" } } }, "providers.search.backend must be one of")
    expect_invalid_top({ providers = { marks = "yes" } }, "providers.marks must be a boolean or table")
    expect_invalid_top({ providers = { marks = { letters = "yes" } } }, "providers.marks.letters must be a boolean")
    expect_invalid_top({ providers = { unknown = true } }, "unknown option 'providers.unknown'")
end

T["rejects an empty text override"] = function()
    expect_invalid_top({ marks = { Search = { text = {} } } }, "marks.Search.text must contain at least one variant")
    expect_invalid(
        { marks = { Search = { text = {} } } },
        "scrollbar.marks.Search.text must contain at least one variant"
    )
end

T["failed setup preserves active config"] = function()
    local config = require("scrollbar.config")
    local before = set({
        visibility = "active",
        placement = { gutter = "overlap" },
        layout = { columns = { { "track" }, { "marks" } } },
    })
    local before_plan = config.get_provider_plan()
    local before_minimap = config.get_minimap()

    expect_invalid(
        { placement = { gutter = "inside" } },
        "scrollbar.placement.gutter must be one of: inner, outer, overlap"
    )
    expect.equality(config.get(), before)
    expect_invalid_top({ exclude = { filetypes = { "lua", false } } }, "exclude.filetypes%[2%] must be a string")
    expect.equality(config.get(), before)
    expect_invalid_top({ providers = { gitsigns = true }, minimap = { width = 0 } }, "minimap.width")
    expect.equality(config.get(), before)
    expect.equality(config.get_provider_plan(), before_plan)
    expect.equality(config.get_minimap(), before_minimap)
end

T["top-level dispatch accepts only the documented sections"] = function()
    expect_invalid_top({ float = { width = 2 } }, "unknown option 'float'")
    expect_invalid_top(
        { thumb = { text = "x" } },
        "unknown option 'thumb' %(scrollbar options go in the 'scrollbar' block%)"
    )
    expect_invalid_top({ visibility = "active" }, "scrollbar options go in the 'scrollbar' block")
    expect_invalid_top({ scrollbar = { visibility = "active" }, extra = true }, "unknown option 'extra'")
    expect_invalid_top({ set_highlights = "no" }, "set_highlights must be a boolean")
    expect_invalid_top({ scrollbar = "no" }, "scrollbar must be a table")

    local result = set_top({ set_highlights = false })
    expect.equality(result.set_highlights, false)
    expect.equality(require("scrollbar.config").get_minimap().set_highlights, false)
end

T["minimap slice defaults to disabled and round-trips through config"] = function()
    local config = require("scrollbar.config")
    config.set({})

    expect.equality(config.get_minimap().enabled, false)

    config.set({ minimap = { enabled = true } })
    expect.equality(config.get_minimap().enabled, true)

    config.set({ minimap = { enabled = false } })
    expect.equality(config.get_minimap().enabled, false)

    ---@diagnostic disable-next-line: assign-type-mismatch
    expect_invalid_top({ minimap = { enabled = "yes" } }, "minimap.enabled must be a boolean")
    ---@diagnostic disable-next-line: assign-type-mismatch
    expect_invalid_top({ minimap = "not a table" }, "minimap must be a table")
end

T["provider targets"] = MiniTest.new_set()

T["provider targets"]["true requests every renderer that supports the provider"] = function()
    set_top({ minimap = { enabled = true }, providers = { gitsigns = true, treesitter = true } })
    expect.equality(plan().gitsigns.consumers, { scrollbar = true, minimap = true })
    expect.equality(plan().gitsigns.options, true)
    expect.equality(plan().treesitter.consumers, { scrollbar = false, minimap = true })
    expect.equality(plan().treesitter.targets, { scrollbar = false, minimap = true })
    expect.equality(plan().coc.consumers, { scrollbar = false, minimap = false })
    expect.equality(plan().coc.options, false)
end

T["provider targets"]["a table can keep a provider out of one renderer"] = function()
    set_top({
        minimap = { enabled = true },
        providers = {
            diagnostic = { minimap = false },
            coc = { scrollbar = false },
            search = { incsearch = true, minimap = false },
            marks = { numbers = true, scrollbar = true },
        },
    })
    expect.equality(plan().diagnostic.consumers, { scrollbar = true, minimap = false })
    expect.equality(plan().diagnostic.options, true)
    expect.equality(plan().coc.consumers, { scrollbar = false, minimap = true })
    expect.equality(plan().search.consumers, { scrollbar = true, minimap = false })
    expect.equality(plan().search.options, { incsearch = true, backend = "worker" })
    expect.equality(plan().marks.consumers, { scrollbar = true, minimap = true })
    expect.equality(plan().marks.options, { letters = true, numbers = true })
end

T["provider targets"]["both renderer flags false turn the provider off"] = function()
    set_top({ minimap = { enabled = true }, providers = { cursor = { scrollbar = false, minimap = false } } })
    expect.equality(plan().cursor.consumers, { scrollbar = false, minimap = false })
    expect.equality(plan().cursor.options, false)
end

T["provider targets"]["minimap-only providers reject scrollbar = true"] = function()
    expect_invalid_top(
        { providers = { treesitter = { scrollbar = true } } },
        "providers.treesitter.scrollbar: provider 'treesitter' does not support the scrollbar"
    )
    expect_invalid_top({ providers = { lsp_semantic_tokens = { scrollbar = true } } }, "does not support the scrollbar")
    expect_invalid_top(
        { providers = { gitsigns = { minimap = "yes" } } },
        "providers.gitsigns.minimap must be a boolean"
    )

    set_top({ minimap = { enabled = true }, providers = { treesitter = { scrollbar = false } } })
    expect.equality(plan().treesitter.consumers, { scrollbar = false, minimap = true })
end

T["provider targets"]["a disabled renderer requests no providers"] = function()
    set_top({ providers = { gitsigns = true, treesitter = true } })
    expect.equality(plan().gitsigns.consumers, { scrollbar = true, minimap = false })
    expect.equality(plan().treesitter.consumers, { scrollbar = false, minimap = false })
    expect.equality(plan().treesitter.options, false)

    set_top({ scrollbar = { enabled = false }, providers = { gitsigns = true } })
    for name, entry in pairs(plan()) do
        expect.equality({ name, entry.consumers.scrollbar }, { name, false })
        expect.equality({ name, entry.options }, { name, false })
    end

    set_top({ scrollbar = { enabled = false }, minimap = { enabled = true }, providers = { gitsigns = true } })
    expect.equality(plan().gitsigns.consumers, { scrollbar = false, minimap = true })
    expect.equality(plan().gitsigns.options, true)
end

T["exclude"] = MiniTest.new_set()

T["exclude"]["defaults apply to both renderers"] = function()
    local config = require("scrollbar.config")
    local result = set_top({})
    expect.equality(result.exclude.buftypes, { terminal = true })
    expect.equality(result.exclude.filetypes.TelescopePrompt, true)
    expect.equality(result.exclude.filetypes.noice, true)
    expect.equality(config.get_minimap().exclude, result.exclude)
end

T["exclude"]["a keyed table merges with the defaults"] = function()
    local config = require("scrollbar.config")
    local result = set_top({
        exclude = {
            filetypes = { NvimTree = true, noice = false, markdown = { scrollbar = false } },
            buftypes = { terminal = { minimap = false }, quickfix = true },
        },
    })
    local minimap = config.get_minimap()

    expect.equality(result.exclude.filetypes.NvimTree, true)
    expect.equality(result.exclude.filetypes.TelescopePrompt, true)
    expect.equality(result.exclude.filetypes.noice, nil)
    expect.equality(result.exclude.filetypes.markdown, nil)
    expect.equality(minimap.exclude.filetypes.NvimTree, true)
    expect.equality(minimap.exclude.filetypes.noice, nil)
    expect.equality(minimap.exclude.filetypes.markdown, true)
    expect.equality(result.exclude.buftypes, { terminal = true, quickfix = true })
    expect.equality(minimap.exclude.buftypes, { quickfix = true })
end

T["exclude"]["a dense list replaces the defaults and an empty list clears them"] = function()
    local config = require("scrollbar.config")
    local result = set_top({ exclude = { filetypes = { "NvimTree" } } })
    expect.equality(result.exclude.filetypes, { NvimTree = true })
    expect.equality(config.get_minimap().exclude.filetypes, { NvimTree = true })
    expect.equality(result.exclude.buftypes, { terminal = true })

    result = set_top({ exclude = { buftypes = {}, filetypes = {} } })
    expect.equality(result.exclude, { buftypes = {}, filetypes = {} })
    expect.equality(config.get_minimap().exclude, { buftypes = {}, filetypes = {} })
end

T["exclude"]["rejects malformed entries"] = function()
    -- selene: allow(mixed_table)
    expect_invalid_top(
        { exclude = { filetypes = { "a", b = true } } },
        "exclude.filetypes must be a dense list or a table keyed by name, not both"
    )
    expect_invalid_top(
        { exclude = { filetypes = { lua = "yes" } } },
        "exclude.filetypes.lua must be a boolean or table"
    )
    expect_invalid_top(
        { exclude = { filetypes = { lua = { other = true } } } },
        "unknown option 'exclude.filetypes.lua.other'"
    )
    expect_invalid_top(
        { exclude = { filetypes = "lua" } },
        "exclude.filetypes must be a dense list or a table keyed by name"
    )
    expect_invalid_top({ exclude = { windows = {} } }, "unknown option 'exclude.windows'")
end

local ALL_EVENTS = {
    "BufEnter",
    "BufWinEnter",
    "WinEnter",
    "TabEnter",
    "TermEnter",
    "CmdwinLeave",
    "CursorMoved",
    "CursorMovedI",
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "TextChangedT",
    "WinScrolled",
    "WinResized",
    "VimResized",
    "OptionSet",
    "ColorScheme",
    "WinClosed",
    "BufDelete",
    "BufWipeout",
    "TabClosed",
}

local function event_names(events)
    return vim.tbl_map(function(spec)
        return spec.event
    end, events)
end

T["events"] = MiniTest.new_set()

T["events"]["defaults to every supported event"] = function()
    expect.equality(event_names(set({}).events), ALL_EVENTS)
end

T["events"]["a keyed table merges with the defaults"] = function()
    local result = set({ events = { CursorMovedI = false, OptionSet = false, WinClosed = true } })
    local expected = vim.tbl_filter(function(event)
        return event ~= "CursorMovedI" and event ~= "OptionSet"
    end, ALL_EVENTS)
    expect.equality(event_names(result.events), expected)
end

T["events"]["a dense list replaces the defaults in the supported order"] = function()
    local result = set({ events = { "WinScrolled", "TextChanged", "BufEnter" } })
    expect.equality(event_names(result.events), { "BufEnter", "TextChanged", "WinScrolled" })
end

T["events"]["accepts any autocmd event and canonicalizes its name"] = function()
    local result = set({ events = { "FocusGained", "winscrolled", "BufLeave" } })
    expect.equality(event_names(result.events), { "WinScrolled", "BufLeave", "FocusGained" })

    result = set({ events = { focusgained = true, OptionSet = false } })
    local expected = vim.tbl_filter(function(event)
        return event ~= "OptionSet"
    end, ALL_EVENTS)
    table.insert(expected, "FocusGained")
    expect.equality(event_names(result.events), expected)
end

T["events"]["sets patterns in list entries and keyed entries"] = function()
    local result = set({
        events = {
            "WinScrolled",
            { event = "user", pattern = "GitSignsUpdate" },
            { event = "OptionSet", pattern = { "spell", "wrap" } },
            { event = "BufLeave" },
        },
    })
    expect.equality(result.events, {
        { event = "WinScrolled", pattern = false },
        { event = "OptionSet", pattern = { "spell", "wrap" } },
        { event = "BufLeave", pattern = false },
        { event = "User", pattern = { "GitSignsUpdate" } },
    })

    result = set({ events = { User = { pattern = { "A", "B" } }, TextChanged = { pattern = "*.lua" }, BufEnter = {} } })
    local by_event = {}
    for _, spec in ipairs(result.events) do
        by_event[spec.event] = spec.pattern
    end
    expect.equality(by_event.User, { "A", "B" })
    expect.equality(by_event.TextChanged, { "*.lua" })
    expect.equality(by_event.BufEnter, false)
    expect.equality(by_event.WinScrolled, false)
end

T["events"]["rejects malformed patterns"] = function()
    expect_invalid({ events = { { pattern = "GitSignsUpdate" } } }, "scrollbar%.events%[1%]%.event must be a string$")
    expect_invalid(
        { events = { { event = "User", patterns = "A" } } },
        "unknown option 'scrollbar%.events%[1%]%.patterns'$"
    )
    expect_invalid({ events = { User = { event = "User" } } }, "unknown option 'scrollbar%.events%.User%.event'$")
    expect_invalid(
        { events = { User = { pattern = 1 } } },
        "scrollbar%.events%.User%.pattern must be a string or a dense list of strings$"
    )
    expect_invalid(
        { events = { User = { pattern = {} } } },
        "scrollbar%.events%.User%.pattern must contain at least one pattern$"
    )
    expect_invalid({ events = { User = { pattern = "" } } }, "scrollbar%.events%.User%.pattern must not be empty$")
    expect_invalid(
        { events = { { event = "User", pattern = { "A", "" } } } },
        "scrollbar%.events%[1%]%.pattern%[2%] must not be empty$"
    )
    expect_invalid(
        { events = { "User", { event = "User", pattern = "A" } } },
        "scrollbar%.events%[2%] duplicates event 'User'$"
    )
end

T["events"]["profiles inherit the root events"] = function()
    set({ events = { "WinScrolled" }, profiles = { { match = { filetypes = { "lua" } }, mouse = false } } })
    expect.equality(
        require("scrollbar.config").get_variants()[2].config.events,
        { { event = "WinScrolled", pattern = false } }
    )
end

T["events"]["rejects malformed values"] = function()
    expect_invalid({ events = "WinScrolled" }, "scrollbar%.events must be a dense list or a table keyed by event name$")
    expect_invalid(
        { events = { "WinScrolled", 1 } },
        "scrollbar%.events%[2%] must be an event name or a table with 'event' and 'pattern'$"
    )
    expect_invalid(
        { events = { "WinScrolled", "NotAnEvent" } },
        "scrollbar%.events%[2%]: unknown autocmd event 'NotAnEvent'$"
    )
    expect_invalid(
        { events = { NotAnEvent = true } },
        "scrollbar%.events%.NotAnEvent: unknown autocmd event 'NotAnEvent'$"
    )
    expect_invalid(
        { events = { "WinScrolled", "winscrolled" } },
        "scrollbar%.events%[2%] duplicates event 'WinScrolled'$"
    )
    expect_invalid(
        { events = { FocusGained = true, focusgained = false } },
        "scrollbar%.events%.[Ff]ocus[Gg]ained duplicates event 'FocusGained'$"
    )
    expect_invalid({ events = { WinScrolled = "yes" } }, "scrollbar%.events%.WinScrolled must be a boolean or table$")
    -- selene: allow(mixed_table)
    expect_invalid(
        { events = { "WinScrolled", OptionSet = false } },
        "scrollbar%.events must be a dense list or a table keyed by event name, not both$"
    )
    expect_invalid({ events = {} }, "scrollbar%.events must contain at least one event$")
    local all_off = {}
    for _, event in ipairs(ALL_EVENTS) do
        all_off[event] = false
    end
    expect_invalid({ events = all_off }, "scrollbar%.events must contain at least one event$")
    expect_invalid(
        { profiles = { { match = { filetypes = { "lua" } }, events = { "WinScrolled" } } } },
        "scrollbar%.profiles%[1%]%.events is a global option and cannot be set in a profile"
    )
end

T["mark registry"] = MiniTest.new_set()

T["mark registry"]["top-level entries override defaults and register new types"] = function()
    local config = require("scrollbar.config")
    local result = set_top({
        minimap = { enabled = true },
        marks = {
            Error = { highlight = { fg = "#ff0000" } },
            Custom = { text = "x", priority = 9, highlight = "Title" },
        },
    })
    expect.equality(result.marks.Error, { text = { "-", "=" }, priority = 2, highlight = { fg = "#ff0000" } })
    expect.equality(result.marks.Custom, { text = { "x" }, priority = 9, highlight = "Title" })
    local minimap = config.get_minimap()
    expect.equality(minimap.marks.Error.highlight, { fg = "#ff0000" })
    expect.equality(minimap.marks.Error.priority, 2)
    ---@diagnostic disable-next-line: undefined-field
    expect.equality(minimap.marks.Error.text, nil)
    expect.equality(minimap.marks.Custom.priority, 9)
    expect.equality(minimap.marks.Cursor, nil)
    expect.equality(config.get_mark_types().Custom, true)
end

T["mark registry"]["a new type needs text priority and highlight"] = function()
    expect_invalid_top(
        { marks = { Custom = { priority = 1, highlight = "Title" } } },
        "marks.Custom.text is required for a new mark type"
    )
    expect_invalid_top(
        { marks = { Custom = { text = "x", highlight = "Title" } } },
        "marks.Custom.priority is required for a new mark type"
    )
    expect_invalid_top(
        { marks = { Custom = { text = "x", priority = 1 } } },
        "marks.Custom.highlight is required for a new mark type"
    )
    expect_invalid_top({ marks = { ["bad-name"] = {} } }, "marks has invalid mark type")
    expect_invalid_top({ marks = { Error = "red" } }, "marks.Error must be false or a table")
    expect_invalid_top({ marks = { Unknown = false } }, "marks.Unknown: cannot hide unknown mark type 'Unknown'")
end

T["mark registry"]["top-level false hides a type in both renderers but keeps it registered"] = function()
    local config = require("scrollbar.config")
    local result = set_top({ minimap = { enabled = true }, marks = { Hint = false } })
    expect.equality(result.marks.Hint, nil)
    expect.equality(config.get_minimap().marks.Hint, nil)
    expect.equality(config.get_mark_types().Hint, true)
end

T["mark registry"]["renderer overrides hide types and show hidden types again"] = function()
    local config = require("scrollbar.config")
    local result = set_top({
        minimap = { enabled = true, marks = { Hint = { priority = 0 }, Search = false } },
        marks = { Hint = false },
        scrollbar = { marks = { Warn = false, Hint = {} } },
    })
    expect.equality(result.marks.Warn, nil)
    expect.equality(result.marks.Hint, { text = { "-", "=" }, priority = 5, highlight = "DiagnosticVirtualTextHint" })
    local minimap = config.get_minimap()
    expect.equality(minimap.marks.Warn ~= nil, true)
    expect.equality(minimap.marks.Search, nil)
    expect.equality(minimap.marks.Hint.priority, 0)
    expect.equality(config.get_mark_types().Warn, true)
    expect.equality(config.get_mark_types().Search, true)

    local hidden = set_top({ minimap = { enabled = true, marks = false }, scrollbar = { marks = false } })
    expect.equality(hidden.marks, {})
    expect.equality(config.get_minimap().marks, {})
end

T["mark registry"]["renderer overrides reject unknown and unsupported types"] = function()
    expect_invalid(
        { marks = { Nope = {} } },
        "scrollbar.marks.Nope: unknown mark type 'Nope'. Define it in the top%-level marks table"
    )
    expect_invalid({ marks = { Error = "red" } }, "scrollbar.marks.Error must be false or a table")
    expect_invalid({ marks = "none" }, "scrollbar.marks must be false or a table")
    expect_invalid_top(
        { minimap = { marks = { Cursor = false } } },
        "minimap.marks.Cursor: the minimap draws the cursor"
    )
    expect_invalid_top(
        { minimap = { marks = { Error = { text = "E" } } } },
        "unknown option 'minimap.marks.Error.text'"
    )
    expect_invalid_top({ minimap = { marks = { Nope = {} } } }, "minimap.marks.Nope: unknown mark type 'Nope'")
end

T["precedence"] = MiniTest.new_set()

T["precedence"]["a profile preset beats root layout and thumb blend"] = function()
    set({
        layout = { columns = { { "track", "thumb" }, { "marks" } } },
        thumb = { blend = 90, highlight = "Visual" },
        profiles = {
            { match = { filetypes = { "markdown" } }, preset = "sublime" },
            { match = { filetypes = { "lua" } }, preset = "minimal" },
        },
    })
    local variants = require("scrollbar.config").get_variants()

    expect.equality(variants[1].config.layout.width, 2)
    expect.equality(variants[1].config.thumb.blend, 90)
    expect.equality(variants[2].config.layout.width, 1)
    expect.equality(layer_kinds(variants[2].config.layout.columns[1]), { "thumb", "marks" })
    expect.equality(variants[2].config.thumb.blend, 60)
    expect.equality(variants[2].config.thumb.highlight, "Visual")
    expect.equality(layer_kinds(variants[3].config.layout.columns[1]), { "thumb" })
    expect.equality(variants[3].config.thumb.blend, 20)
end

T["precedence"]["a profile without a preset inherits the root preset and options"] = function()
    set({
        preset = "sublime",
        thumb = { text = "#" },
        profiles = {
            { match = { filetypes = { "lua" } }, thumb = { blend = 5 } },
        },
    })
    local variants = require("scrollbar.config").get_variants()

    expect.equality(layer_kinds(variants[2].config.layout.columns[1]), { "thumb", "marks" })
    expect.equality(variants[2].config.thumb.text, "#")
    expect.equality(variants[2].config.thumb.blend, 5)
end

T["precedence"]["profile keys beat the profile preset"] = function()
    set({
        thumb = { blend = 90 },
        profiles = {
            {
                match = { filetypes = { "lua" } },
                preset = "emacs",
                thumb = { blend = 15 },
                placement = { gutter = "inner" },
            },
        },
    })
    local profile = require("scrollbar.config").get_variants()[2].config

    expect.equality(profile.thumb.blend, 15)
    expect.equality(profile.placement.anchor, "NW")
    expect.equality(profile.placement.gutter, "inner")
end

T["precedence"]["profiles reject global keys and unknown presets"] = function()
    expect_invalid(
        { profiles = { { match = { filetypes = { "x" } }, visibility = "active" } } },
        "scrollbar.profiles%[1%].visibility is a global option and cannot be set in a profile"
    )
    expect_invalid(
        { profiles = { { match = { filetypes = { "x" } }, autohide = true } } },
        "scrollbar.profiles%[1%].autohide is a global option"
    )
    expect_invalid(
        { profiles = { { match = { filetypes = { "x" } }, config = {} } } },
        "unknown option 'scrollbar.profiles%[1%].config'"
    )
    expect_invalid(
        { profiles = { { match = { filetypes = { "x" } }, preset = "nope" } } },
        "scrollbar.profiles%[1%].preset: unknown preset 'nope'"
    )
    expect_invalid({ profiles = { { preset = "zed" } } }, "scrollbar.profiles%[1%].match is required")
    expect_invalid(
        { profiles = { { match = { filetypes = { "x" } }, thumb = { blend = 200 } } } },
        "scrollbar.profiles%[1%].thumb.blend must be an integer between 0 and 100"
    )
    expect_invalid_top(
        { minimap = { profiles = { { match = { filetypes = { "x" } }, backend = "sync" } } } },
        "minimap.profiles%[1%].backend is a global option"
    )
end

return T
