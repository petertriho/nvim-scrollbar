local MiniTest = MiniTest
local expect = MiniTest.expect

local layout = require("scrollbar.layout")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.presets"] = nil
        end,
    },
})

local function config(overrides)
    return require("scrollbar.config").set({ scrollbar = overrides })
end

local function compose(options)
    return layout.compose({
        config = options.config,
        height = options.height or 1,
        line_count = options.line_count,
        container_width = options.container_width,
        compact_search = options.compact_search,
        geometry = {
            total_extent = 100,
            viewport_start = 0,
            viewport_end = 10,
            mark_rows = options.mark_rows or {},
            compact_mark_rows = options.compact_mark_rows,
            handle = options.handle or { first_row = 1, last_row = 1 },
        },
        marks = options.marks or {},
    })
end

T["composes the default track thumb and catch-all stack"] = function()
    local result = compose({
        config = config({ thumb = { text = "H" }, marks = { Search = { text = "S" } } }),
        handle = { first_row = 0, last_row = 0 },
        marks = { { provider = "search", line = 10, type = "Search" } },
        mark_rows = { 0 },
    })

    expect.equality(result.rows, { "S" })
    expect.equality(result.width, 1)
    expect.equality(result.highlights[1], {
        { start_col = 0, end_col = 1, highlight = "ScrollbarTrack", priority = 1 },
        { start_col = 0, end_col = 1, highlight = "ScrollbarThumb", priority = 2 },
        { start_col = 0, end_col = 1, highlight = "ScrollbarSearchThumb", priority = 3 },
    })
    expect.equality(result.hitmap[1][1].track, true)
    expect.equality(result.hitmap[1][1].thumb, true)
    expect.equality(result.hitmap[1][1].provider, "search")
    expect.equality(result.hitmap[1][1].line, 10)
    expect.equality(result.handle, { first_row = 0, last_row = 0, column = 1, width = 1 })
end

T["honors marks above and below the thumb and explicit track order"] = function()
    local marks_below = compose({
        config = config({
            layout = { columns = { { "track", "marks", "thumb" } } },
            thumb = { text = "H" },
            marks = { Search = { text = "S" } },
        }),
        handle = { first_row = 0, last_row = 0 },
        marks = { { provider = "search", line = 10, type = "Search" } },
        mark_rows = { 0 },
    })
    local track_above = compose({
        config = config({
            layout = { columns = { { "thumb", "marks", "track" } } },
            thumb = { text = "H" },
            marks = { Search = { text = "S" } },
        }),
        handle = { first_row = 0, last_row = 0 },
        marks = { { provider = "search", line = 10, type = "Search" } },
        mark_rows = { 0 },
    })

    expect.equality(marks_below.rows, { "H" })
    expect.equality(marks_below.hitmap[1][1], { track = true, thumb = true })
    expect.equality(track_above.rows, { "S" })
    expect.equality(track_above.highlights[1], {
        { start_col = 0, end_col = 1, highlight = "ScrollbarThumb", priority = 1 },
        { start_col = 0, end_col = 1, highlight = "ScrollbarSearchThumb", priority = 2 },
        { start_col = 0, end_col = 1, highlight = "ScrollbarTrack", priority = 3 },
    })
end

T["routes explicit types before the catch-all lane"] = function()
    local result = compose({
        config = config({
            layout = {
                columns = {
                    { { kind = "marks", types = { "Error", "Future" } } },
                    { "marks" },
                },
            },
            marks = {
                Search = { text = "S" },
                Error = { text = "E" },
                Future = { text = "F", priority = 0, highlight = "Normal" },
            },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
            { provider = "custom", line = 30, type = "Future" },
        },
        mark_rows = { 0, 0, 0 },
    })

    expect.equality(result.rows, { "FS" })
    expect.equality(result.hitmap[1][1].type, "Future")
    expect.equality(result.hitmap[1][2].type, "Search")
end

T["uses numeric priority within a lane and stack order across lanes"] = function()
    local same_lane = compose({
        config = config({
            layout = { columns = { { { kind = "marks", types = { "Search", "Error" } } } } },
            marks = { Search = { text = "S", priority = 5 }, Error = { text = "E", priority = 1 } },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })
    local separate_layers = compose({
        config = config({
            layout = {
                columns = {
                    {
                        { kind = "marks", types = { "Error" } },
                        { kind = "marks", types = { "Search" } },
                    },
                },
            },
            marks = { Search = { text = "S", priority = 99 }, Error = { text = "E", priority = 0 } },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })

    expect.equality(same_lane.rows, { "E" })
    expect.equality(separate_layers.rows, { "S" })
    expect.equality(separate_layers.hitmap[1][1].type, "Search")
end

T["clips ordinary text to its lane and suppresses multi-cell glyphs atomically"] = function()
    local clipped = compose({
        config = config({
            layout = {
                columns = {
                    { { kind = "marks", types = { "Search" } } },
                    { { kind = "marks", types = { "Search" } } },
                    { "track" },
                },
            },
            marks = { Search = { text = "ABC" } },
        }),
        marks = { { provider = "search", line = 10, type = "Search" } },
        mark_rows = { 0 },
    })
    local atomic = compose({
        config = config({
            layout = {
                columns = {
                    { { kind = "marks", types = { "Search" } } },
                    {
                        { kind = "marks", types = { "Search" } },
                        { kind = "marks", types = { "Error" } },
                    },
                },
            },
            marks = { Search = { text = "界" }, Error = { text = "E" } },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })

    expect.equality(clipped.rows, { "AB " })
    expect.equality(atomic.rows, { " E" })
    expect.equality(atomic.hitmap[1][1], { track = false, thumb = false })
    expect.equality(atomic.hitmap[1][2].type, "Error")
end

T["does not leak a multi-cell glyph across different column layer profiles"] = function()
    local result = compose({
        config = config({
            layout = {
                columns = {
                    { "track", "thumb", { kind = "marks", types = { "Search" } } },
                    { { kind = "marks", types = { "Search" } } },
                },
            },
            marks = { Search = { text = "界" } },
        }),
        handle = { first_row = 0, last_row = 0 },
        marks = { { provider = "search", line = 10, type = "Search" } },
        mark_rows = { 0 },
    })

    expect.equality(result.rows, { "  " })
    expect.equality(result.highlights[1], {
        { start_col = 0, end_col = 1, highlight = "ScrollbarTrack", priority = 1 },
        { start_col = 0, end_col = 1, highlight = "ScrollbarThumb", priority = 2 },
    })
    expect.equality(result.hitmap[1][1], { track = true, thumb = true })
    expect.equality(result.hitmap[1][2], { track = false, thumb = false })
end

T["keeps compact search exactly equivalent to ordinary search marks"] = function()
    local active_config = config({
        layout = { columns = { { "marks" }, { "track" } } },
        marks = { Search = { text = { "-", "=", "#" } } },
    })
    local ordinary = compose({
        config = active_config,
        height = 2,
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "search", line = 10, type = "Search" },
            { provider = "search", line = 11, type = "Search" },
            { provider = "alpha", line = 20, type = "Search", text = "A" },
            { provider = "search", line = 99, type = "Search" },
        },
        mark_rows = { 0, 0, 0, 0, 1 },
    })
    local compact = compose({
        config = active_config,
        height = 2,
        line_count = 100,
        compact_search = require("scrollbar.providers.search_compact").encode({ 10, 10, 11, 99 }),
        marks = { { provider = "alpha", line = 20, type = "Search", text = "A" } },
        mark_rows = { 0 },
    })

    expect.equality(compact, ordinary)
    expect.equality(compact.rows, { "A ", "- " })
    expect.equality(compact.hitmap[1][1].lines, { 10, 10, 11, 20 })
end

T["screen compact search via compact_mark_rows stays equivalent to ordinary marks"] = function()
    local active_config = config({
        layout = { columns = { { "marks" }, { "track" } } },
        marks = { Search = { text = { "-", "=", "#" } } },
    })
    local ordinary = compose({
        config = active_config,
        height = 2,
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "search", line = 10, type = "Search" },
            { provider = "search", line = 11, type = "Search" },
            { provider = "alpha", line = 20, type = "Search", text = "A" },
            { provider = "search", line = 99, type = "Search" },
        },
        mark_rows = { 0, 0, 0, 0, 1 },
    })
    local compact = compose({
        config = active_config,
        height = 2,
        compact_search = require("scrollbar.providers.search_compact").encode({ 10, 10, 11, 99 }),
        compact_mark_rows = { 0, 0, 0, 1 },
        marks = { { provider = "alpha", line = 20, type = "Search", text = "A" } },
        mark_rows = { 0 },
    })

    expect.equality(compact, ordinary)
    expect.equality(compact.rows, { "A ", "- " })
    expect.equality(compact.hitmap[1][1].lines, { 10, 10, 11, 20 })
end

T["supports optional components and inert transparent cells"] = function()
    local result = compose({
        config = config({
            layout = { columns = { { "marks" }, { "thumb" }, { "track" } } },
            thumb = { text = "H" },
        }),
        handle = { first_row = 0, last_row = 0 },
    })
    local mark_only = compose({
        config = config({ layout = { columns = { { "marks" } } } }),
    })

    expect.equality(result.rows, { " H " })
    expect.equality(result.hitmap[1][1], { track = false, thumb = false })
    expect.equality(result.hitmap[1][2], { track = false, thumb = true })
    expect.equality(result.hitmap[1][3], { track = true, thumb = false })
    expect.equality(mark_only.handle, false)
    expect.equality(mark_only.hitmap[1][1], { track = false, thumb = false })
end

T["preserves deterministic ties density variants and exact line ownership"] = function()
    local active_config = config({
        layout = { columns = { { { kind = "marks", types = { "Alpha", "Beta" } } } } },
        marks = {
            Alpha = { text = { "a", "A" }, priority = 3, highlight = "Normal" },
            Beta = { text = "B", priority = 3, highlight = "Normal" },
        },
    })
    local marks = {
        { provider = "zeta", line = 20, type = "Beta" },
        { provider = "omega", line = 30, type = "Alpha", text = "O" },
        { provider = "alpha", line = 40, type = "Alpha", text = "P" },
        { provider = "alpha", line = 10, type = "Alpha", text = "Q" },
    }
    local first = compose({ config = active_config, marks = marks, mark_rows = { 0, 0, 0, 0 } })
    local second = compose({
        config = active_config,
        marks = { marks[4], marks[3], marks[2], marks[1] },
        mark_rows = { 0, 0, 0, 0 },
    })

    expect.equality(first.rows, { "Q" })
    expect.equality(second, first)
    expect.equality(first.hitmap[1][1].provider, "alpha")
    expect.equality(first.hitmap[1][1].line, 10)
    expect.equality(first.hitmap[1][1].lines, { 10, 30, 40 })
end

T["expands only built-in named marks to the lane cap and container"] = function()
    local active_config = config({
        layout = {
            columns = {
                { { kind = "marks", types = { "Mark" }, max_width = 4 } },
                { "thumb" },
            },
        },
        thumb = { text = "H" },
    })
    local marks = {
        { provider = "marks", line = 40, type = "Mark", text = "d" },
        { provider = "marks", line = 10, type = "Mark", text = "a" },
        { provider = "marks", line = 30, type = "Mark", text = "c" },
        { provider = "marks", line = 20, type = "Mark", text = "b" },
    }
    local expanded = compose({
        config = active_config,
        container_width = 5,
        handle = { first_row = 0, last_row = 0 },
        marks = marks,
        mark_rows = { 0, 0, 0, 0 },
    })
    local limited = compose({
        config = active_config,
        container_width = 3,
        handle = { first_row = 0, last_row = 0 },
        marks = marks,
        mark_rows = { 0, 0, 0, 0 },
    })
    local collapsed = compose({
        config = config({
            layout = { columns = { { { kind = "marks", types = { "Mark" } } }, { "thumb" } } },
            thumb = { text = "H" },
        }),
        container_width = 5,
        handle = { first_row = 0, last_row = 0 },
        marks = marks,
        mark_rows = { 0, 0, 0, 0 },
    })

    expect.equality(expanded.width, 5)
    expect.equality(expanded.rows, { "abcdH" })
    expect.equality(expanded.hitmap[1][1].line, 10)
    expect.equality(expanded.hitmap[1][4].line, 40)
    expect.equality(limited.width, 3)
    expect.equality(limited.rows, { "abH" })
    expect.equality(collapsed.width, 2)
    expect.equality(collapsed.rows, { "aH" })
end

T["treats max_width as lane-local while preserving unrelated declared columns"] = function()
    local active_config = config({
        layout = {
            columns = {
                { { kind = "marks", types = { "Search" } } },
                { { kind = "marks", types = { "Mark" }, max_width = 4 } },
                { { kind = "marks", types = { "Mark" } } },
                { "thumb" },
            },
        },
        thumb = { text = "H" },
        marks = { Search = { text = "S" } },
    })
    local marks = {
        { provider = "search", line = 5, type = "Search" },
        { provider = "marks", line = 10, type = "Mark", text = "a" },
        { provider = "marks", line = 20, type = "Mark", text = "b" },
        { provider = "marks", line = 30, type = "Mark", text = "c" },
        { provider = "marks", line = 40, type = "Mark", text = "d" },
        { provider = "marks", line = 50, type = "Mark", text = "e" },
    }
    local full = compose({
        config = active_config,
        container_width = 8,
        handle = { first_row = 0, last_row = 0 },
        marks = marks,
        mark_rows = { 0, 0, 0, 0, 0, 0 },
    })
    local limited = compose({
        config = active_config,
        container_width = 5,
        handle = { first_row = 0, last_row = 0 },
        marks = marks,
        mark_rows = { 0, 0, 0, 0, 0, 0 },
    })

    expect.equality(full.width, 6)
    expect.equality(full.rows, { "abScdH" })
    expect.equality(full.hitmap[1][5].line, 40)
    expect.equality(limited.width, 5)
    expect.equality(limited.rows, { "aSbcH" })
end

T["keeps custom Mark sources collapsed while named marks use dynamic cells"] = function()
    local result = compose({
        config = config({
            layout = {
                columns = {
                    { { kind = "marks", types = { "Mark" }, max_width = 4 } },
                    { "track" },
                },
            },
        }),
        container_width = 5,
        marks = {
            { provider = "custom", line = 5, type = "Mark", text = "X" },
            { provider = "marks", line = 10, type = "Mark", text = "a" },
            { provider = "marks", line = 20, type = "Mark", text = "b" },
            { provider = "marks", line = 30, type = "Mark", text = "c" },
        },
        mark_rows = { 0, 0, 0, 0 },
    })

    expect.equality(result.width, 4)
    expect.equality(result.rows, { "abX " })
    expect.equality(result.hitmap[1][3].provider, "custom")
    expect.equality(result.hitmap[1][3].lines, { 5 })
end

T["pins declared cells while expanding inward for every direction and anchor"] = function()
    local function rendered(direction, anchor)
        return compose({
            config = config({
                float = { placement = { anchor = anchor } },
                layout = {
                    direction = direction,
                    columns = {
                        { { kind = "marks", types = { "Search" } } },
                        { { kind = "marks", types = { "Mark" }, max_width = 4 } },
                        { "thumb" },
                    },
                },
                thumb = { text = "H" },
                marks = { Search = { text = "S" } },
            }),
            container_width = 6,
            handle = { first_row = 0, last_row = 0 },
            marks = {
                { provider = "search", line = 5, type = "Search" },
                { provider = "marks", line = 10, type = "Mark", text = "a" },
                { provider = "marks", line = 20, type = "Mark", text = "b" },
                { provider = "marks", line = 30, type = "Mark", text = "c" },
                { provider = "marks", line = 40, type = "Mark", text = "d" },
            },
            mark_rows = { 0, 0, 0, 0, 0 },
        }).rows[1]
    end

    expect.equality(rendered("auto", "NE"), "abcSdH")
    expect.equality(rendered("auto", "SE"), "abcSdH")
    expect.equality(rendered("auto", "NW"), "HaSbcd")
    expect.equality(rendered("auto", "SW"), "HaSbcd")
    expect.equality(rendered("ltr", "NE"), "abcSdH")
    expect.equality(rendered("ltr", "SE"), "abcSdH")
    expect.equality(rendered("ltr", "NW"), "SaHbcd")
    expect.equality(rendered("ltr", "SW"), "SaHbcd")
    expect.equality(rendered("rtl", "NE"), "abcHdS")
    expect.equality(rendered("rtl", "SE"), "abcHdS")
    expect.equality(rendered("rtl", "NW"), "HaSbcd")
    expect.equality(rendered("rtl", "SW"), "HaSbcd")
end

T["composes precomputed mark layers identically and caches glyph parsing"] = function()
    local active_config = config({
        layout = {
            columns = {
                { { kind = "marks", types = { "Search" } } },
                { { kind = "marks", types = { "Search" } }, "thumb" },
            },
        },
        thumb = { text = "界" },
        marks = { Search = { text = "á" } },
    })
    local input = {
        config = active_config,
        height = 1,
        geometry = {
            total_extent = 100,
            viewport_start = 0,
            viewport_end = 10,
            mark_rows = { 0 },
            handle = { first_row = 1, last_row = 1 },
        },
        marks = { { provider = "search", line = 10, type = "Search" } },
    }

    local direct = layout.compose(input)
    local cached = layout.compose(vim.tbl_extend("force", input, { mark_layer = layout.mark_layer(input) }))
    expect.equality(cached, direct)

    layout.clear_cache()
    local calls = { strchars = 0, strcharpart = 0, strdisplaywidth = 0, char2nr = 0 }
    local originals = {}
    for name in pairs(calls) do
        originals[name] = vim.fn[name]
        vim.fn[name] = function(...)
            calls[name] = calls[name] + 1
            return originals[name](...)
        end
    end
    layout.compose(input)
    local first = vim.deepcopy(calls)
    layout.compose(input)
    local second = vim.deepcopy(calls)
    for name, original in pairs(originals) do
        vim.fn[name] = original
    end

    expect.equality(second, first)
    expect.equality(first.strchars > 0, true)
end

return T
