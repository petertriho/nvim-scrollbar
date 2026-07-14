local MiniTest = MiniTest
local expect = MiniTest.expect

local layout = require("scrollbar.layout")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
        end,
    },
})

local function config(overrides)
    return require("scrollbar.config").set(overrides)
end

local function compose(options)
    local marks = options.marks or {}
    return layout.compose({
        config = options.config,
        height = options.height or 2,
        line_count = options.line_count,
        container_width = options.container_width,
        compact_search = options.compact_search,
        geometry = {
            total_extent = 100,
            viewport_start = 0,
            viewport_end = 10,
            mark_rows = options.mark_rows or {},
            handle = options.handle or { first_row = 1, last_row = 1 },
        },
        marks = marks,
    })
end

T["expands built-in marks westward in source order with exact ownership"] = function()
    local active_config = config({
        float = { width = 3, placement = { anchor = "NW" } },
        handle = { column = 3, width = 1 },
        marks = { Mark = { column = 2 } },
        providers = { marks = { max_width = 6 } },
    })
    local input = {
        config = active_config,
        height = 1,
        container_width = 6,
        geometry = {
            total_extent = 100,
            viewport_start = 0,
            viewport_end = 10,
            mark_rows = { 0, 0, 0 },
            handle = { first_row = 1, last_row = 1 },
        },
        marks = {
            { provider = "marks", line = 30, type = "Mark", text = "c" },
            { provider = "marks", line = 10, type = "Mark", text = "z" },
            { provider = "marks", line = 10, type = "Mark", text = "a" },
        },
    }

    local layer = layout.mark_layer(input)
    local result = layout.compose(input)

    expect.equality(layer.width, 4)
    expect.equality(layer.column_offset, 0)
    expect.equality(result.width, 4)
    expect.equality(result.rows, { " azc" })
    expect.equality(result.hitmap[1][2].line, 10)
    expect.equality(result.hitmap[1][2].lines, { 10 })
    expect.equality(result.hitmap[1][3].line, 10)
    expect.equality(result.hitmap[1][3].lines, { 10 })
    expect.equality(result.hitmap[1][4].line, 30)
    expect.equality(result.hitmap[1][4].lines, { 30 })
end

T["expands eastward inward and translates ordinary marks and the handle"] = function()
    local result = compose({
        config = config({
            float = { width = 3, placement = { anchor = "NE" } },
            handle = { text = "H", column = 3, width = 1 },
            marks = {
                Mark = { column = 2 },
                Search = { text = { "s", "S" }, column = 2 },
            },
            providers = { marks = { max_width = 6 } },
        }),
        height = 2,
        container_width = 6,
        handle = { first_row = 1, last_row = 1 },
        marks = {
            { provider = "marks", line = 40, type = "Mark", text = "d" },
            { provider = "marks", line = 10, type = "Mark", text = "a" },
            { provider = "marks", line = 30, type = "Mark", text = "c" },
            { provider = "marks", line = 20, type = "Mark", text = "b" },
            { provider = "search", line = 50, type = "Search" },
            { provider = "search", line = 60, type = "Search" },
        },
        mark_rows = { 0, 0, 0, 0, 1, 1 },
    })

    expect.equality(result.width, 5)
    expect.equality(result.rows, { "abcd ", "   SH" })
    expect.equality(result.handle, { first_row = 1, last_row = 1, column = 5, width = 1 })
    expect.equality(result.hitmap[1][1].line, 10)
    expect.equality(result.hitmap[1][4].line, 40)
    expect.equality(result.hitmap[2][4].provider, "search")
    expect.equality(result.hitmap[2][4].lines, { 50, 60 })
    expect.equality(result.hitmap[2][5], { handle = true })
end

T["keeps boolean marks mode identical to ordinary collapsed composition"] = function()
    local options = {
        height = 1,
        handle = { first_row = 1, last_row = 1 },
        marks = {
            { provider = "marks", line = 20, type = "Mark", text = "b" },
            { provider = "marks", line = 10, type = "Mark", text = "a" },
        },
        mark_rows = { 0, 0 },
    }
    local disabled = vim.tbl_extend("force", options, {
        config = config({ float = { width = 2 }, providers = { marks = false } }),
    })
    local collapsed = vim.tbl_extend("force", options, {
        config = config({ float = { width = 2 }, providers = { marks = true } }),
    })

    local ordinary = compose(disabled)
    local result = compose(collapsed)

    expect.equality(result, ordinary)
    expect.equality(result.width, 2)
    expect.equality(result.rows, { "a " })
    expect.equality(result.hitmap[1][1].lines, { 10, 20 })
end

T["configured Mark text replaces literal names in collapsed and expanded modes"] = function()
    local marks = {
        { provider = "marks", line = 10, type = "Mark", text = "a" },
        { provider = "marks", line = 20, type = "Mark", text = "b" },
    }
    local collapsed = compose({
        config = config({
            float = { width = 2 },
            marks = { Mark = { text = { "m", "M" } } },
            providers = { marks = true },
        }),
        height = 1,
        handle = { first_row = 1, last_row = 1 },
        marks = marks,
        mark_rows = { 0, 0 },
    })
    local expanded = compose({
        config = config({
            float = { width = 2 },
            marks = { Mark = { text = { "m", "M" } } },
            providers = { marks = { max_width = 4 } },
        }),
        height = 1,
        container_width = 4,
        handle = { first_row = 1, last_row = 1 },
        marks = marks,
        mark_rows = { 0, 0 },
    })

    expect.equality(collapsed.rows, { "M " })
    expect.equality(expanded.rows, { "mm " })
end

T["keeps custom Mark providers collapsed when built-in marks expansion is enabled"] = function()
    local result = compose({
        config = config({
            float = { width = 2 },
            handle = { column = 2, width = 1 },
            providers = { marks = { max_width = 5 } },
        }),
        height = 1,
        container_width = 5,
        handle = { first_row = 1, last_row = 1 },
        marks = {
            { provider = "custom", line = 20, type = "Mark", text = "Y" },
            { provider = "custom", line = 10, type = "Mark", text = "X" },
        },
        mark_rows = { 0, 0 },
    })

    expect.equality(result.width, 2)
    expect.equality(result.rows, { "X " })
    expect.equality(result.hitmap[1][1].provider, "custom")
    expect.equality(result.hitmap[1][1].lines, { 10, 20 })
end

T["caps expanded width and truncates only the source-ordered tail"] = function()
    local marks = {}
    local mark_rows = {}
    for index, letter in ipairs({ "f", "e", "d", "c", "b", "a" }) do
        marks[index] = { provider = "marks", line = 70 - index * 10, type = "Mark", text = letter }
        mark_rows[index] = 0
    end
    local capped = compose({
        config = config({
            float = { width = 2, placement = { anchor = "NW" } },
            handle = { column = 2, width = 1 },
            providers = { marks = { max_width = 4 } },
        }),
        height = 1,
        container_width = 10,
        handle = { first_row = 1, last_row = 1 },
        marks = marks,
        mark_rows = mark_rows,
    })
    local container_limited = compose({
        config = config({
            float = { width = 2, placement = { anchor = "NW" } },
            handle = { column = 2, width = 1 },
            providers = { marks = { max_width = 6 } },
        }),
        height = 1,
        container_width = 3,
        handle = { first_row = 1, last_row = 1 },
        marks = marks,
        mark_rows = mark_rows,
    })
    local default_container = compose({
        config = config({
            float = { width = 2, placement = { anchor = "NW" } },
            handle = { column = 2, width = 1 },
            providers = { marks = { max_width = 6 } },
        }),
        height = 1,
        handle = { first_row = 1, last_row = 1 },
        marks = marks,
        mark_rows = mark_rows,
    })
    local base_preserved = compose({
        config = config({
            float = { width = 4, placement = { anchor = "NW" } },
            handle = { column = 4, width = 1 },
            providers = { marks = { max_width = 6 } },
        }),
        height = 1,
        container_width = 2,
        handle = { first_row = 1, last_row = 1 },
        marks = marks,
        mark_rows = mark_rows,
    })

    expect.equality(capped.width, 4)
    expect.equality(capped.rows, { "abcd" })
    expect.equality(capped.hitmap[1][4].line, 40)
    expect.equality(container_limited.width, 3)
    expect.equality(container_limited.rows, { "abc" })
    expect.equality(default_container.width, 2)
    expect.equality(default_container.rows, { "ab" })
    expect.equality(base_preserved.width, 4)
    expect.equality(base_preserved.rows, { "abcd" })
end

T["uses existing priorities for expanded collisions without backfilling"] = function()
    local result = compose({
        config = config({
            float = { width = 2, placement = { anchor = "NW" } },
            handle = { column = 2, width = 1 },
            marks = { Error = { text = "E", column = 2, priority = 0 } },
            providers = { marks = { max_width = 4 } },
        }),
        height = 1,
        container_width = 4,
        handle = { first_row = 1, last_row = 1 },
        marks = {
            { provider = "marks", line = 10, type = "Mark", text = "a" },
            { provider = "marks", line = 20, type = "Mark", text = "b" },
            { provider = "marks", line = 30, type = "Mark", text = "c" },
            { provider = "diagnostic", line = 15, type = "Error" },
        },
        mark_rows = { 0, 0, 0, 0 },
    })

    expect.equality(result.rows, { "aEc" })
    expect.equality(result.hitmap[1][1].line, 10)
    expect.equality(result.hitmap[1][2].provider, "diagnostic")
    expect.equality(result.hitmap[1][3].line, 30)
end

T["keeps ordinary glyphs clipped to the base width during expansion"] = function()
    local result = compose({
        config = config({
            float = { width = 2, placement = { anchor = "NW" } },
            handle = { column = 2, width = 1 },
            marks = { Search = { text = "ABC", column = 2 } },
            providers = { marks = { max_width = 5 } },
        }),
        height = 2,
        container_width = 5,
        handle = { first_row = 2, last_row = 2 },
        marks = {
            { provider = "marks", line = 10, type = "Mark", text = "a" },
            { provider = "marks", line = 20, type = "Mark", text = "b" },
            { provider = "marks", line = 30, type = "Mark", text = "c" },
            { provider = "marks", line = 40, type = "Mark", text = "d" },
            { provider = "search", line = 50, type = "Search" },
        },
        mark_rows = { 0, 0, 0, 0, 1 },
    })

    expect.equality(result.width, 4)
    expect.equality(result.rows, { "abcd", " A  " })
    expect.equality(result.hitmap[2][2].provider, "search")
    expect.equality(result.hitmap[2][3], { handle = false })
end

T["composes one- and multi-column marks into fixed-width rows"] = function()
    local one_column = compose({
        config = config({ marks = { Search = { text = "-" } } }),
        height = 1,
        handle = { first_row = 1, last_row = 1 },
        marks = { { provider = "search", line = 10, type = "Search" } },
        mark_rows = { 0 },
    })
    local result = compose({
        config = config({
            float = { width = 4 },
            handle = { column = 4, width = 1 },
            marks = {
                Search = { text = "-", column = 1 },
                Error = { text = "E", column = 3 },
            },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })

    expect.equality(one_column.rows, { "-" })
    expect.equality(result.rows[1], "- E ")
    expect.equality(vim.fn.strdisplaywidth(result.rows[1]), 4)
    expect.equality(result.highlights[1], {
        { start_col = 0, end_col = 1, highlight = "ScrollbarSearch" },
        { start_col = 2, end_col = 3, highlight = "ScrollbarError" },
    })
end

T["uses deterministic type, provider, and source-line ties"] = function()
    local tied_types = config({
        float = { width = 2 },
        handle = { column = 2, width = 1 },
        marks = {
            Alpha = { text = "A", column = 1, priority = 3, highlight = "Normal" },
            Beta = { text = "B", column = 1, priority = 3, highlight = "Normal" },
        },
    })
    local first = compose({
        config = tied_types,
        marks = {
            { provider = "zeta", line = 20, type = "Beta" },
            { provider = "omega", line = 30, type = "Alpha", text = "O" },
            { provider = "alpha", line = 40, type = "Alpha", text = "P" },
            { provider = "alpha", line = 10, type = "Alpha", text = "Q" },
        },
        mark_rows = { 0, 0, 0, 0 },
    })
    local second = compose({
        config = tied_types,
        marks = {
            { provider = "alpha", line = 10, type = "Alpha", text = "Q" },
            { provider = "alpha", line = 40, type = "Alpha", text = "P" },
            { provider = "omega", line = 30, type = "Alpha", text = "O" },
            { provider = "zeta", line = 20, type = "Beta" },
        },
        mark_rows = { 0, 0, 0, 0 },
    })

    expect.equality(first.rows[1], "Q ")
    expect.equality(second.rows[1], first.rows[1])
    expect.equality(first.hitmap[1][1].provider, "alpha")
    expect.equality(first.hitmap[1][1].line, 10)
    expect.equality(first.hitmap[1][1].lines, { 10, 30, 40 })
end

T["resolves same and partial range overlaps by priority"] = function()
    local same_range = compose({
        config = config({
            float = { width = 2 },
            handle = { column = 2, width = 1 },
            marks = {
                Search = { text = "S", column = 1, priority = 5 },
                Error = { text = "E", column = 1, priority = 1 },
            },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })
    local result = compose({
        config = config({
            float = { width = 4 },
            handle = { column = 4, width = 1 },
            marks = {
                Search = { text = "abc", column = 1, priority = 5 },
                Error = { text = "XY", column = 2, priority = 1 },
            },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })

    expect.equality(same_range.rows[1], "E ")
    expect.equality(result.rows[1], "aXY ")
    expect.equality(result.hitmap[1][1].type, "Search")
    expect.equality(result.hitmap[1][2].type, "Error")
    expect.equality(result.hitmap[1][3].type, "Error")
end

T["selects capped density variants for rendered row buckets"] = function()
    local result = compose({
        config = config({
            float = { width = 2 },
            handle = { column = 2, width = 1 },
            marks = { Search = { text = { "-", "=" }, column = 1 } },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "search", line = 11, type = "Search" },
            { provider = "search", line = 12, type = "Search" },
        },
        mark_rows = { 0, 0, 0 },
    })

    expect.equality(result.rows[1], "= ")
    expect.equality(result.hitmap[1][1].lines, { 10, 11, 12 })
end

T["compact search is exactly equivalent for duplicates density collisions and click targets"] = function()
    local active_config = config({
        float = { width = 2 },
        handle = { column = 2, width = 1 },
        marks = { Search = { text = { "-", "=", "#" }, column = 1 } },
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
        marks = {
            { provider = "alpha", line = 20, type = "Search", text = "A" },
        },
        mark_rows = { 0 },
    })

    expect.equality(compact, ordinary)
    expect.equality(compact.rows, { "A ", "- " })
    expect.equality(compact.hitmap[1][1].line, 20)
    expect.equality(compact.hitmap[1][1].lines, { 10, 10, 11, 20 })
end

T["marks over the handle use combined highlights without erasing uncovered handle cells"] = function()
    local result = compose({
        config = config({
            float = { width = 3 },
            handle = { text = "#", column = 1, width = 3 },
            marks = { Search = { text = "-", column = 2 } },
        }),
        height = 1,
        handle = { first_row = 0, last_row = 0 },
        marks = { { provider = "search", line = 42, type = "Search" } },
        mark_rows = { 0 },
    })

    expect.equality(result.rows, { "#-#" })
    expect.equality(result.highlights[1], {
        { start_col = 0, end_col = 1, highlight = "ScrollbarHandle" },
        { start_col = 1, end_col = 2, highlight = "ScrollbarSearchHandle" },
        { start_col = 2, end_col = 3, highlight = "ScrollbarHandle" },
    })
    expect.equality(result.hitmap[1][1], { handle = true })
    expect.equality(result.hitmap[1][2].handle, true)
    expect.equality(result.hitmap[1][2].line, 42)
    expect.equality(result.hitmap[1][3], { handle = true })
    expect.equality(result.handle, { first_row = 0, last_row = 0, column = 1, width = 3 })
end

T["clips at the right display boundary and pads every row"] = function()
    local result = compose({
        config = config({
            float = { width = 3 },
            handle = { column = 1, width = 1 },
            marks = { Search = { text = "ab", column = 3 } },
        }),
        height = 1,
        handle = { first_row = 1, last_row = 1 },
        marks = { { provider = "search", line = 9, type = "Search" } },
        mark_rows = { 0 },
    })
    local wide_boundary = compose({
        config = config({
            float = { width = 3 },
            handle = { column = 1, width = 1 },
            marks = { Search = { text = "界", column = 3 } },
        }),
        height = 1,
        handle = { first_row = 1, last_row = 1 },
        marks = { { provider = "search", line = 9, type = "Search" } },
        mark_rows = { 0 },
    })

    expect.equality(result.rows, { "  a" })
    expect.equality(vim.fn.strdisplaywidth(result.rows[1]), 3)
    expect.equality(result.highlights[1], {
        { start_col = 2, end_col = 3, highlight = "ScrollbarSearch" },
    })
    expect.equality(wide_boundary.rows, { "   " })
    expect.equality(wide_boundary.highlights, { {} })
end

T["keeps multibyte multi-cell glyph bytes and display-cell hits distinct"] = function()
    local result = compose({
        config = config({
            float = { width = 4 },
            handle = { column = 1, width = 1 },
            marks = { Search = { text = "界x", column = 2 } },
        }),
        height = 1,
        handle = { first_row = 1, last_row = 1 },
        marks = { { provider = "search", line = 88, type = "Search" } },
        mark_rows = { 0 },
    })

    expect.equality(result.rows, { " 界x" })
    expect.equality(vim.fn.strdisplaywidth(result.rows[1]), 4)
    expect.equality(result.highlights[1], {
        { start_col = 1, end_col = 5, highlight = "ScrollbarSearch" },
    })
    expect.equality(result.hitmap[1][2].start_col, 2)
    expect.equality(result.hitmap[1][2].end_col, 3)
    expect.equality(result.hitmap[1][3].line, 88)
    expect.equality(result.hitmap[1][4].line, 88)
end

T["suppresses a multi-cell glyph atomically when one cell loses a collision"] = function()
    local result = compose({
        config = config({
            float = { width = 3 },
            handle = { column = 3, width = 1 },
            marks = {
                Search = { text = "界", column = 1, priority = 5 },
                Error = { text = "X", column = 2, priority = 1 },
            },
        }),
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "diagnostic", line = 20, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })

    expect.equality(result.rows[1], " X ")
    expect.equality(result.hitmap[1][1], { handle = false })
    expect.equality(result.hitmap[1][2].type, "Error")
end

T["assigns exact ownership independently for every visible display column"] = function()
    local result = compose({
        config = config({
            float = { width = 4 },
            handle = { column = 4, width = 1 },
            marks = {
                Search = { text = "S", column = 1 },
                Error = { text = "EE", column = 2 },
            },
        }),
        marks = {
            { provider = "search", line = 12, type = "Search" },
            { provider = "diagnostic", line = 77, type = "Error" },
        },
        mark_rows = { 0, 0 },
    })

    expect.equality(result.hitmap[1][1].provider, "search")
    expect.equality(result.hitmap[1][1].line, 12)
    expect.equality(result.hitmap[1][2].provider, "diagnostic")
    expect.equality(result.hitmap[1][2].line, 77)
    expect.equality(result.hitmap[1][3].line, 77)
    expect.equality(result.hitmap[1][4], { handle = false })
end

T["composes precomputed expanded mark layers exactly like the direct pipeline"] = function()
    local active_config = config({
        float = { width = 4 },
        handle = { text = "界", column = 3, width = 2 },
        marks = {
            Search = { text = { "-", "=" }, column = 1, priority = 2 },
            Error = { text = "EE", column = 2, priority = 1 },
        },
        providers = { marks = { max_width = 6 } },
    })
    local input = {
        config = active_config,
        height = 3,
        container_width = 6,
        geometry = {
            total_extent = 100,
            viewport_start = 40,
            viewport_end = 60,
            mark_rows = { 0, 0, 2, 0, 0, 0 },
            handle = { first_row = 1, last_row = 2 },
        },
        marks = {
            { provider = "search", line = 10, type = "Search" },
            { provider = "search", line = 11, type = "Search" },
            { provider = "diagnostic", line = 90, type = "Error" },
            { provider = "marks", line = 20, type = "Mark", text = "a" },
            { provider = "marks", line = 30, type = "Mark", text = "b" },
            { provider = "marks", line = 40, type = "Mark", text = "c" },
        },
    }

    local direct = layout.compose(input)
    local cached_input = vim.tbl_extend("force", input, { mark_layer = layout.mark_layer(input) })
    local cached = layout.compose(cached_input)

    expect.equality(cached, direct)
    expect.equality(cached.width, 6)
end

T["caches parsed glyphs and display widths by text"] = function()
    local active_config = config({
        float = { width = 4 },
        handle = { text = "界", column = 3, width = 2 },
        marks = { Search = { text = "á", column = 1 } },
    })
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

    local input = {
        config = active_config,
        height = 1,
        geometry = {
            total_extent = 100,
            viewport_start = 0,
            viewport_end = 10,
            mark_rows = { 0 },
            handle = { first_row = 0, last_row = 0 },
        },
        marks = { { provider = "search", line = 10, type = "Search" } },
    }
    layout.compose(input)
    local first = vim.deepcopy(calls)
    layout.compose(input)
    local second = vim.deepcopy(calls)

    for name, original in pairs(originals) do
        vim.fn[name] = original
    end

    expect.equality(second, first)
    expect.equality(first.strchars > 0, true)
    expect.equality(first.strdisplaywidth > 0, true)
end

return T
