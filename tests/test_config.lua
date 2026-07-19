local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.presets"] = nil
        end,
    },
})

local function set(overrides)
    return require("scrollbar.config").set(overrides)
end

local function expect_invalid(overrides, pattern)
    local ok, err = pcall(set, overrides)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

local function layer_kinds(column)
    local result = {}
    for index, layer in ipairs(column) do
        result[index] = layer.kind
    end
    return result
end

T["normalizes a fresh one-column default without setup-only state"] = function()
    local first = set({
        visibility = "active",
        layout = { columns = { { "track", "marks", "thumb" } } },
        thumb = { text = "#" },
        marks = { Search = { text = "x" }, Mark = { text = "X" } },
        providers = { search = { incsearch = true, backend = "sync" }, marks = { numbers = true } },
    })

    expect.equality(first.visibility, "active")
    expect.equality(first.layout.width, 1)
    expect.equality(layer_kinds(first.layout.columns[1]), { "track", "marks", "thumb" })
    expect.equality(first.thumb.text, "#")
    expect.equality(first.marks.Search.text, { "x" })
    expect.equality(first.marks.Mark.text, { "X" })
    expect.equality(first.providers.search, { incsearch = true, backend = "sync" })
    expect.equality(first.providers.marks, { letters = true, numbers = true })
    expect.equality(rawget(first, "preset"), nil)
    expect.equality(rawget(first, "presets"), nil)

    first.layout.columns[1][1].priority = 99
    first.marks.Mark.text[1] = "changed"
    first.providers.marks.numbers = true

    local second = set()
    expect.equality(second.visibility, "all")
    expect.equality(second.float.placement.gutter, "avoid")
    expect.equality(second.float.placement.gutter_position, "inner")
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
    expect.equality(second.providers.marks, { letters = true, numbers = false })
end

T["resolves presets before root overrides and replaces lists atomically"] = function()
    local result = set({
        preset = "vscode",
        presets = {
            vscode = {
                thumb = { text = "V" },
                marks = { Search = { text = { "v", "V" } } },
            },
        },
        layout = { columns = { { "marks", "thumb" } } },
        thumb = { blend = 42 },
        marks = { Search = { text = { "R" } } },
    })

    expect.equality(result.layout.width, 1)
    expect.equality(layer_kinds(result.layout.columns[1]), { "marks", "thumb" })
    expect.equality(result.thumb.text, "V")
    expect.equality(result.thumb.blend, 42)
    expect.equality(result.marks.Search.text, { "R" })
end

T["compiles auto ltr and rtl directions for east and west anchors"] = function()
    local columns = {
        { "track" },
        { { kind = "marks", types = { "Search" } } },
        { "thumb" },
    }
    local function kinds(direction, anchor)
        local result = set({
            float = { placement = { anchor = anchor } },
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
                { { kind = "marks", types = { "Future", "Error" } } },
                { { kind = "marks", types = { "Future", "Error" } }, "marks" },
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
                { "track", { kind = "marks", types = { "Mark" }, max_width = 5 }, "thumb" },
                { "track", { kind = "marks", types = { "Mark" } }, "thumb" },
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
    local result = set({
        show = false,
        visibility = "active",
        set_highlights = false,
        max_lines = 1000,
        hide_if_all_visible = true,
        autohide = { enabled = true, delay_ms = 750 },
        render = { interval_ms = 0, geometry = "screen" },
        float = {
            zindex = 60,
            hide_on_cursor = false,
            placement = {
                relative = "editor",
                anchor = "SW",
                row = -2,
                col = 3,
                gutter = "overlap",
                gutter_position = "outer",
            },
        },
        layout = {
            direction = "rtl",
            columns = {
                { "track", "thumb" },
                { { kind = "marks", types = { "Custom", "Search" } }, "marks" },
            },
        },
        track = { highlight = track_highlight },
        mouse = { enabled = false },
        thumb = {
            text = "#",
            blend = 0,
            highlight = thumb_highlight,
            hide_if_all_visible = false,
        },
        marks = {
            Search = { text = { "-", "=" }, priority = 9, highlight = "Search" },
            Custom = { text = "!", priority = 0, highlight = mark_highlight },
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
            coc = false,
        },
        excluded_buftypes = { "terminal", "nofile" },
        excluded_filetypes = { "prompt" },
    })

    expect.equality(result.max_lines, 1000)
    expect.equality(result.float.placement.row, -2)
    expect.equality(result.float.placement.gutter, "overlap")
    expect.equality(result.float.placement.gutter_position, "outer")
    expect.equality(result.layout.direction, "rtl")
    expect.equality(result.layout.width, 2)
    expect.equality(result.track.highlight, track_highlight)
    expect.equality(result.thumb.highlight, thumb_highlight)
    expect.equality(result.marks.Custom.text, { "!" })
    expect.equality(result.marks.Custom.highlight, mark_highlight)
    expect.equality(result.providers.marks, { letters = false, numbers = true })

    result.track.highlight.bg = "#000000"
    result.thumb.highlight.bg = "#000000"
    result.marks.Custom.highlight.cterm.italic = false
    expect.equality(track_highlight.bg, "#010203")
    expect.equality(thumb_highlight.bg, "#112233")
    expect.equality(mark_highlight.cterm.italic, true)
end

T["rejects removed coordinate options and unknown keys"] = function()
    expect_invalid({ float = { width = 2 } }, "unknown option 'float.width'")
    expect_invalid({ handle = {} }, "unknown option 'handle'")
    expect_invalid({ thumb = { column = 1 } }, "unknown option 'thumb.column'")
    expect_invalid({ thumb = { width = 1 } }, "unknown option 'thumb.width'")
    expect_invalid({ marks = { Search = { column = 1 } } }, "unknown option 'marks.Search.column'")
    expect_invalid({ providers = { marks = { max_width = 4 } } }, "unknown option 'providers.marks.max_width'")
    expect_invalid({ throttle_ms = 10 }, "unknown option 'throttle_ms'")
    expect_invalid({ layout = { rows = {} } }, "unknown option 'layout.rows'")
    expect_invalid({ float = { placement = { win = 1 } } }, "unknown option 'float.placement.win'")
    expect_invalid({ marks = { Search = { gui = "bold" } } }, "unknown option 'marks.Search.gui'")
end

T["rejects malformed layouts and invalid lane spans"] = function()
    expect_invalid({ layout = { direction = "inside" } }, "layout.direction must be one of")
    expect_invalid({ layout = { columns = {} } }, "layout.columns must contain at least one column")
    expect_invalid(
        { layout = { columns = { [1] = { "track" }, [3] = { "thumb" } } } },
        "layout.columns must be a dense list"
    )
    expect_invalid({ layout = { columns = { {} } } }, "layout.columns%[1%] must contain at least one layer")
    expect_invalid(
        { layout = { columns = { { "unknown" } } } },
        "must be 'track', 'thumb', 'marks', or a mark descriptor"
    )
    expect_invalid({ layout = { columns = { { { types = { "Error" } } } } } }, "kind must be 'marks'")
    expect_invalid(
        { layout = { columns = { { { kind = "marks", extra = true } } } } },
        "unknown option 'layout.columns%[1%]%[1%].extra'"
    )
    expect_invalid(
        { layout = { columns = { { { kind = "marks", types = {} } } } } },
        "types must contain at least one type"
    )
    expect_invalid(
        { layout = { columns = { { { kind = "marks", types = { "Error", 2 } } } } } },
        "types%[2%] must be a string"
    )
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
                { { kind = "marks", types = { "Error" } } },
                { "track" },
                { { kind = "marks", types = { "Error" } } },
            },
        },
    }, "mark type 'Error' must occupy one contiguous lane")
    expect_invalid({
        layout = { columns = { { { kind = "marks", types = { "Search" }, max_width = 3 } } } },
    }, "max_width is valid only for a lane explicitly selecting Mark")
    expect_invalid({
        layout = {
            columns = {
                { { kind = "marks", types = { "Mark" }, max_width = 1 } },
                { { kind = "marks", types = { "Mark" } } },
            },
        },
    }, "max_width must be greater than or equal to its base lane width")
end

T["rejects invalid scalar provider mark and text options"] = function()
    expect_invalid({ visibility = "current" }, "visibility must be one of")
    expect_invalid({ render = { geometry = "fold" } }, "render.geometry must be one of")
    expect_invalid({ float = { placement = { anchor = "C" } } }, "float.placement.anchor must be one of")
    expect_invalid({ show = 1 }, "show must be a boolean")
    expect_invalid({ autohide = { delay_ms = 0 } }, "autohide.delay_ms must be a positive integer")
    expect_invalid({ thumb = { text = "" } }, "thumb.text must have positive display width")
    expect_invalid({ thumb = { blend = 101 } }, "thumb.blend must be between 0 and 100")
    expect_invalid({ marks = { Search = { text = {} } } }, "marks.Search.text must contain at least one variant")
    expect_invalid({ marks = { Search = { priority = -1 } } }, "marks.Search.priority must be a non%-negative integer")
    expect_invalid(
        { marks = { Search = { highlight = "" } } },
        "marks.Search.highlight must be a non%-empty string or table"
    )
    expect_invalid({ providers = { cursor = {} } }, "providers.cursor must be a boolean")
    expect_invalid({ providers = { search = "yes" } }, "providers.search must be a boolean or table")
    expect_invalid({ providers = { marks = "yes" } }, "providers.marks must be a boolean or table")
    expect_invalid({ providers = { marks = { letters = "yes" } } }, "providers.marks.letters must be a boolean")
end

T["failed setup preserves active config"] = function()
    local config = require("scrollbar.config")
    local before = set({
        visibility = "active",
        float = { placement = { gutter = "overlap" } },
        layout = { columns = { { "track" }, { "marks" } } },
    })

    expect_invalid(
        { float = { placement = { gutter = "inside" } } },
        "float.placement.gutter must be one of: avoid, overlap"
    )
    expect.equality(config.get(), before)
    expect_invalid(
        { float = { placement = { gutter_position = "middle" } } },
        "float.placement.gutter_position must be one of: inner, outer"
    )
    expect.equality(config.get(), before)
    expect_invalid({ excluded_filetypes = { "lua", false } }, "excluded_filetypes%[2%] must be a string")
    expect.equality(config.get(), before)
end

return T
