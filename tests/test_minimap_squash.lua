local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.minimap.squash"] = nil
            package.loaded["scrollbar.minimap.semantic"] = nil
        end,
    },
})

local function grid_of(options)
    return vim.tbl_extend("force", {
        width = 4,
        first_row = 0,
        row_count = 1,
        scale_lines = 1,
        scale_dots = 1,
        columns_per_dot = 1,
        encoding = "braille",
    }, options or {})
end

local function squash(lines, options, highlights, first_line)
    return require("scrollbar.minimap.squash").squash(lines, first_line or 0, grid_of(options), highlights)
end

local function braille(mask)
    return vim.fn.nr2char(0x2800 + mask)
end

local function row_chars(grid, row)
    local chars = {}
    for col = 1, #grid[row] do
        chars[col] = grid[row][col].char
    end
    return table.concat(chars)
end

local function row_highlights(grid, row)
    local groups = {}
    for col = 1, #grid[row] do
        groups[col] = grid[row][col].hl_group
    end
    return groups
end

local function semantic_highlights(lines, spans)
    return require("scrollbar.minimap.semantic").compose(lines, spans)
end

T["returns a blank grid of the requested shape for empty source"] = function()
    local grid = squash({}, { width = 3, row_count = 2 })

    expect.equality(#grid, 2)
    expect.equality(#grid[1], 3)
    expect.equality(row_chars(grid, 1), "   ")
    expect.equality(row_chars(grid, 2), "   ")
    expect.equality(grid[1][1].hl_group, nil)
end

T["sets one Braille dot for each line and dot column"] = function()
    local grid = squash({ "x ", " x", "x ", " x" }, { width = 1 })

    expect.equality(row_chars(grid, 1), braille(0x01 + 0x10 + 0x04 + 0x80))
end

T["fills every dot of a full cell"] = function()
    local grid = squash({ "xx", "xx", "xx", "xx" }, { width = 1 })

    expect.equality(row_chars(grid, 1), braille(0xFF))
end

T["block encoding draws a full block for any dot"] = function()
    local grid = squash({ "x", "", "", "", "", "", "", "  x" }, { width = 2, row_count = 2, encoding = "block" })

    expect.equality(row_chars(grid, 1), "█ ")
    expect.equality(row_chars(grid, 2), " █")
end

T["the fixed scale gives each line one dot row"] = function()
    local lines = {}
    for line = 1, 8 do
        lines[line] = line == 5 and "x" or ""
    end
    local grid = squash(lines, { width = 1, row_count = 2 })

    expect.equality(row_chars(grid, 1), " ")
    expect.equality(row_chars(grid, 2), braille(0x01))
end

T["the fit scale merges the lines of each dot row"] = function()
    local lines = {}
    for line = 1, 16 do
        lines[line] = ""
    end
    lines[5] = "x"
    lines[16] = " x"
    local grid = squash(lines, { width = 1, scale_lines = 16, scale_dots = 4 })

    expect.equality(row_chars(grid, 1), braille(0x02 + 0x80))
end

T["every line belongs to exactly one dot row"] = function()
    local squash_module = require("scrollbar.minimap.squash")
    for _, ratio in ipairs({ { 1, 1 }, { 5, 4 }, { 6, 4 }, { 100, 80 }, { 997, 160 } }) do
        local scale = { scale_lines = ratio[1], scale_dots = ratio[2] }
        for line = 0, ratio[1] - 1 do
            local dot = squash_module.line_dot(line, scale)
            expect.equality(squash_module.dot_first_line(dot, scale) <= line, true)
            expect.equality(squash_module.dot_first_line(dot + 1, scale) > line, true)
        end
    end
end

T["each dot column covers columns_per_dot display columns"] = function()
    local grid = squash({ "a   b   c" }, { width = 2, columns_per_dot = 4 })

    expect.equality(row_chars(grid, 1), braille(0x01 + 0x08) .. braille(0x01))
end

T["clips display columns past the grid"] = function()
    local grid = squash({ "abcd", "    efgh" }, { width = 2 })

    expect.equality(row_chars(grid, 1), braille(0x01 + 0x08) .. braille(0x01 + 0x08))
    expect.equality(row_chars(squash({ "    x" }, { width = 2 }), 1), "  ")
end

T["preserves indentation as leading blank cells"] = function()
    local grid = squash({ "    ab" }, { width = 3 })

    expect.equality(row_chars(grid, 1), "  " .. braille(0x01 + 0x08))
end

T["a slice squashes the same rows as the whole map"] = function()
    local squash_module = require("scrollbar.minimap.squash")
    local lines = {}
    for line = 1, 37 do
        lines[line] = string.rep(" ", line % 7) .. string.rep("x", line % 5)
    end
    for _, scale in ipairs({ { 1, 1 }, { 37, 16 } }) do
        local whole_grid = grid_of({ row_count = 10, scale_lines = scale[1], scale_dots = scale[2] })
        local whole = squash_module.squash(lines, 0, whole_grid)
        local slice_grid = grid_of({ first_row = 3, row_count = 4, scale_lines = scale[1], scale_dots = scale[2] })
        local first, last = squash_module.line_range(slice_grid, #lines)
        local slice = squash_module.squash({ unpack(lines, first + 1, last) }, first, slice_grid)
        for row = 1, 4 do
            expect.equality(row_chars(slice, row), row_chars(whole, row + 3))
        end
    end
end

T["line_range clamps the slice lines to the buffer"] = function()
    local squash_module = require("scrollbar.minimap.squash")

    expect.equality({ squash_module.line_range(grid_of({ first_row = 2, row_count = 3 }), 100) }, { 8, 20 })
    expect.equality({ squash_module.line_range(grid_of({ first_row = 2, row_count = 3 }), 10) }, { 8, 10 })
    expect.equality({ squash_module.line_range(grid_of({ first_row = 5, row_count = 3 }), 10) }, { 10, 10 })
end

T["fully blank buffer produces a fully blank grid"] = function()
    local grid = squash({ "", "   " }, { width = 4, row_count = 3 })

    expect.equality(#grid, 3)
    for row = 1, 3 do
        expect.equality(row_chars(grid, row), "    ")
        for col = 1, 4 do
            expect.equality(grid[row][col].hl_group, nil)
        end
    end
end

T["wide and multibyte characters use display columns"] = function()
    expect.equality(row_chars(squash({ "中文" }, { width = 2, encoding = "block" }), 1), "██")
    expect.equality(row_chars(squash({ "😀😀😀😀" }, { width = 4, encoding = "block" }), 1), "████")
    expect.equality(row_chars(squash({ "a😀b" }, { width = 2 }), 1), braille(0x09) .. braille(0x09))
end

T["tabs use their actual starting display column"] = function()
    local grid = squash({ "a\tb" }, { width = 5 })

    expect.equality(row_chars(grid, 1), braille(0x01) .. "   " .. braille(0x01))
end

T["combining sequences do not advance an extra display column"] = function()
    local grid = squash({ "áb" }, { width = 1 })

    expect.equality(row_chars(grid, 1), braille(0x09))
end

T["semantic byte spans convert to display columns and color only occupied cells"] = function()
    local source = { "a😀 b" }
    local highlights = semantic_highlights(source, {
        semantic = {
            { line = 0, start_col = 1, end_col = 5, highlight = "Emoji", priority = 10 },
            { line = 0, start_col = 5, end_col = 6, highlight = "Whitespace", priority = 20 },
        },
    })
    local grid = squash(source, { width = 3 }, highlights)

    expect.equality(row_chars(grid, 1), braille(0x09) .. braille(0x01) .. braille(0x01))
    expect.equality(row_highlights(grid, 1), { "Emoji", "Emoji", nil })
end

T["semantic composition uses priority then provider and list order"] = function()
    local source = { "abcd" }
    local highlights = semantic_highlights(source, {
        beta = {
            { line = 0, start_col = 0, end_col = 4, highlight = "Beta", priority = 5 },
        },
        alpha = {
            { line = 0, start_col = 0, end_col = 4, highlight = "AlphaFirst", priority = 5 },
            { line = 0, start_col = 0, end_col = 4, highlight = "AlphaSecond", priority = 5 },
        },
        high = {
            { line = 0, start_col = 1, end_col = 2, highlight = "High", priority = 6 },
        },
    })
    local grid = squash(source, { width = 2 }, highlights)

    expect.equality(row_highlights(grid, 1), { "High", "AlphaFirst" })
end

T["semantic priority is preserved across merged source lines"] = function()
    local source = { "a", "a" }
    local highlights = semantic_highlights(source, {
        first = {
            { line = 0, start_col = 0, end_col = 1, highlight = "Lower", priority = 1 },
        },
        second = {
            { line = 1, start_col = 0, end_col = 1, highlight = "Higher", priority = 2 },
        },
    })
    local grid = squash(source, { width = 1 }, highlights)

    expect.equality(row_chars(grid, 1), braille(0x03))
    expect.equality(row_highlights(grid, 1), { "Higher" })
end

T["semantic highlights of a slice use the lines of the slice"] = function()
    local source = { "", "", "", "", "a", "b" }
    local slice = { unpack(source, 5) }
    local highlights = require("scrollbar.minimap.semantic").compose(slice, {
        semantic = {
            { line = 5, start_col = 0, end_col = 1, highlight = "Second", priority = 1 },
        },
    }, 4)
    local grid = squash(slice, { width = 1, first_row = 1 }, highlights, 4)

    expect.equality(row_chars(grid, 1), braille(0x03))
    expect.equality(row_highlights(grid, 1), { "Second" })
end

T["legacy unordered highlights keep first-source precedence across merged lines"] = function()
    local highlights = {
        [1] = { { hl_group = "First", col_start = 1, col_end = 1 } },
        [2] = { { hl_group = "Second", col_start = 1, col_end = 1 } },
    }
    local grid = squash({ "a", "a" }, { width = 1 }, highlights)

    expect.equality(row_highlights(grid, 1), { "First" })
end

T["horizontal merge keeps highlights on their owning target cell"] = function()
    local highlights = {
        [1] = { { hl_group = "String", col_start = 1, col_end = 4 } },
    }
    local grid = squash({ "abcdefgh" }, { width = 2, columns_per_dot = 2 }, highlights)

    expect.equality(row_chars(grid, 1), braille(0x09) .. braille(0x09))
    expect.equality(grid[1][1].hl_group, "String")
    expect.equality(grid[1][2].hl_group, nil)
end

T["repeated calls with the same input produce identical output"] = function()
    local source = { "abc", "def", "abcdefghi", "         ", "    x" }
    local highlights = {
        [3] = { { hl_group = "Keyword", col_start = 1, col_end = 9 } },
    }

    expect.equality(
        squash(source, { width = 6, row_count = 2 }, highlights),
        squash(source, { width = 6, row_count = 2 }, highlights)
    )
end

return T
