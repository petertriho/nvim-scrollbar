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

local function squash(...)
    return require("scrollbar.minimap.squash").squash(...)
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
    local grid, max_line_width = squash({}, 3, 2)

    expect.equality(#grid, 2)
    expect.equality(#grid[1], 3)
    expect.equality(row_chars(grid, 1), "   ")
    expect.equality(row_chars(grid, 2), "   ")
    expect.equality(grid[1][1].hl_group, nil)
    expect.equality(max_line_width, 0)
end

T["maps source lines directly to target rows when no vertical squash is needed"] = function()
    local grid = squash({ "x", "", " y" }, 2, 3)

    expect.equality(#grid, 3)
    expect.equality(row_chars(grid, 1), "█ ")
    expect.equality(row_chars(grid, 2), "  ")
    expect.equality(row_chars(grid, 3), " █")
end

T["emits blank trailing rows when target height exceeds source height"] = function()
    local grid = squash({ "abc" }, 2, 3)

    expect.equality(#grid, 3)
    expect.equality(row_chars(grid, 1), "██")
    expect.equality(row_chars(grid, 2), "  ")
    expect.equality(row_chars(grid, 3), "  ")
end

T["merges every source line owned by a target row using binary OR"] = function()
    local grid = squash({ "a  ", " b ", "  c", "" }, 3, 1)

    expect.equality(row_chars(grid, 1), "███")
end

T["uses floor boundaries to assign each source line to exactly one row"] = function()
    local grid = squash({ "a ", " b", "a ", " b", "a " }, 2, 2)

    expect.equality(row_chars(grid, 1), "██")
    expect.equality(row_chars(grid, 2), "██")
end

T["vertical merge preserves content from mismatched source widths"] = function()
    local grid = squash({ "ab      ", "abcdefgh" }, 8, 1)

    expect.equality(row_chars(grid, 1), "████████")
end

T["preserves indentation as leading blank cells"] = function()
    local grid = squash({ "    ab" }, 6, 1)

    expect.equality(row_chars(grid, 1), "    ██")
end

T["binary density ignores run length"] = function()
    expect.equality(row_chars(squash({ "a" }, 1, 1), 1), "█")
    expect.equality(row_chars(squash({ "abcdefghi" }, 1, 1), 1), "█")
end

T["horizontal merge aggregates only its owned source columns"] = function()
    local grid = squash({ "ab    cdef" }, 5, 1)

    expect.equality(row_chars(grid, 1), "█  ██")
end

T["returns max_line_width of the longest source line"] = function()
    local grid, max_line_width = squash({ "abc", "defghi" }, 3, 2)

    expect.equality(max_line_width, 6)
    expect.equality(row_chars(grid, 1), "██ ")
    expect.equality(row_chars(grid, 2), "███")
end

T["fully blank buffer produces a fully blank grid"] = function()
    local grid, max_line_width = squash({ "", "   " }, 4, 3)

    expect.equality(#grid, 3)
    for row = 1, 3 do
        expect.equality(row_chars(grid, row), "    ")
        for col = 1, 4 do
            expect.equality(grid[row][col].hl_group, nil)
        end
    end
    expect.equality(max_line_width, 3)
end

T["very wide line collapses without truncating content density"] = function()
    local grid = squash({ "abcdefghijklmnopqrstuvwxyz0123456789ABCD" }, 4, 1)

    expect.equality(row_chars(grid, 1), "████")
end

T["wide and multibyte characters use display columns"] = function()
    expect.equality(row_chars(squash({ "中文" }, 4, 1), 1), "████")
    expect.equality(row_chars(squash({ "😀😀😀😀" }, 8, 1), 1), "████████")
    expect.equality(row_chars(squash({ "a😀b" }, 4, 1), 1), "████")
end

T["tabs use their actual starting display column"] = function()
    local grid = squash({ "a\tb" }, 9, 1)

    expect.equality(row_chars(grid, 1), "█       █")
end

T["combining sequences do not advance an extra display column"] = function()
    local grid = squash({ "áb" }, 2, 1)

    expect.equality(row_chars(grid, 1), "██")
end

T["semantic byte spans convert to display columns and color only occupied cells"] = function()
    local source = { "a😀 b" }
    local highlights = semantic_highlights(source, {
        semantic = {
            { line = 0, start_col = 1, end_col = 5, highlight = "Emoji", priority = 10 },
            { line = 0, start_col = 5, end_col = 6, highlight = "Whitespace", priority = 20 },
        },
    })
    local grid = squash(source, 5, 1, highlights)

    expect.equality(row_chars(grid, 1), "███ █")
    expect.equality(row_highlights(grid, 1), { nil, "Emoji", "Emoji", nil, nil })
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
    local grid = squash(source, 4, 1, highlights)

    expect.equality(row_highlights(grid, 1), { "AlphaFirst", "High", "AlphaFirst", "AlphaFirst" })
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
    local grid = squash(source, 1, 1, highlights)

    expect.equality(row_chars(grid, 1), "█")
    expect.equality(row_highlights(grid, 1), { "Higher" })
end

T["legacy unordered highlights keep first-source precedence across merged lines"] = function()
    local highlights = {
        [1] = { { hl_group = "First", col_start = 1, col_end = 1 } },
        [2] = { { hl_group = "Second", col_start = 1, col_end = 1 } },
    }
    local grid = squash({ "a", "a" }, 1, 1, highlights)

    expect.equality(row_highlights(grid, 1), { "First" })
end

T["horizontal merge keeps highlights on their owning target cell"] = function()
    local highlights = {
        [1] = { { hl_group = "String", col_start = 1, col_end = 4 } },
    }
    local grid = squash({ "abcdefgh" }, 2, 1, highlights)

    expect.equality(row_chars(grid, 1), "██")
    expect.equality(grid[1][1].hl_group, "String")
    expect.equality(grid[1][2].hl_group, nil)
end

T["repeated calls with the same input produce identical output"] = function()
    local source = { "abc", "def", "abcdefghi", "         ", "    x" }
    local highlights = {
        [3] = { { hl_group = "Keyword", col_start = 1, col_end = 9 } },
    }
    local first_grid, first_width = squash(source, 6, 3, highlights)
    local second_grid, second_width = squash(source, 6, 3, highlights)

    expect.equality(first_width, second_width)
    expect.equality(first_grid, second_grid)
end

return T
