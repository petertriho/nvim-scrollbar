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

return T
