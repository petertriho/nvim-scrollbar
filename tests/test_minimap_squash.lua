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
    local grid = squash({}, 3, 2)

    expect.equality(#grid, 2)
    expect.equality(#grid[1], 3)
    expect.equality(grid[1][1].char, " ")
    expect.equality(grid[1][1].hl_group, nil)
    expect.equality(grid[2][3].char, " ")
end

T["returns max_line_width 0 for empty source"] = function()
    local _, max_line_width = squash({}, 3, 2)
    expect.equality(max_line_width, 0)
end

T["half-block pairing table covers all four combinations"] = function()
    -- 8 source lines -> logical_height 8 -> 4 terminal rows.
    -- line1=filled, line2=empty      => top filled, bottom empty   => ▀
    -- line3=empty, line4=filled      => top empty,   bottom filled => ▄
    -- line5=filled, line6=filled     => filled + filled            => █
    -- line7=empty, line8=empty       => empty + empty              => " "
    local source = { "x", "", "", "x", "x", "x", "", "" }
    local grid = squash(source, 1, 4)

    expect.equality(#grid, 4)
    expect.equality(row_chars(grid, 1), "▀")
    expect.equality(row_chars(grid, 2), "▄")
    expect.equality(row_chars(grid, 3), "█")
    expect.equality(row_chars(grid, 4), " ")
end

T["target_height controls terminal rows not doubled"] = function()
    local grid = squash({ "x" }, 1, 5)

    expect.equality(#grid, 5)
    expect.equality(row_chars(grid, 1), "▀")
    expect.equality(row_chars(grid, 2), " ")
    expect.equality(row_chars(grid, 3), " ")
    expect.equality(row_chars(grid, 4), " ")
    expect.equality(row_chars(grid, 5), " ")
end

T["preserves indentation as leading blank cells at ratio 1"] = function()
    local grid = squash({ "    ab" }, 6, 1)

    expect.equality(#grid, 1)
    expect.equality(row_chars(grid, 1), "    ▀▀")
end

T["binary density ignores run length: single char and long run both fill"] = function()
    expect.equality(row_chars(squash({ "a" }, 1, 1), 1), "▀")
    expect.equality(row_chars(squash({ "abcdefghi" }, 1, 1), 1), "▀")
end

T["vertical merge is binary OR across source lines sharing a logical row"] = function()
    -- 4 source lines, height 1 => logical_height 2, v_ratio 2.
    -- logical row 1 owns source {1,2}, logical row 2 owns source {3,4}.
    expect.equality(row_chars(squash({ "a", "", "", "" }, 1, 1), 1), "▀")
    expect.equality(row_chars(squash({ "", "a", "", "" }, 1, 1), 1), "▀")
    expect.equality(row_chars(squash({ "", "a", "x", "" }, 1, 1), 1), "█")
end

T["vertical merge with mismatched widths pairs into half-blocks"] = function()
    -- line1 fills cols 1-2; line2 fills cols 1-8. v_ratio 1, paired.
    local grid = squash({ "ab      ", "abcdefgh" }, 8, 1)

    expect.equality(#grid, 1)
    expect.equality(row_chars(grid, 1), "██▄▄▄▄▄▄")
end

T["horizontal merge aggregates source columns at ratio 2"] = function()
    -- run of 2 at cols 1-2, run of 4 at cols 7-10, target width 5 => h_ratio 2.
    local grid = squash({ "ab    cdef" }, 5, 1)

    expect.equality(#grid, 1)
    expect.equality(row_chars(grid, 1), "▀  ▀▀")
end

T["returns max_line_width of the longest source line"] = function()
    local grid, max_line_width = squash({ "abc", "defghi" }, 3, 2)

    expect.equality(max_line_width, 6)
    -- line1 (3 wide) pairs with line2 (6 wide): col3 maps to source cols
    -- 5-6 where only the bottom row (line2) has content.
    expect.equality(row_chars(grid, 1), "██▄")
    expect.equality(row_chars(grid, 2), "   ")
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

T["single line buffer with excess height emits blank trailing rows"] = function()
    local grid = squash({ "abc" }, 2, 3)

    expect.equality(#grid, 3)
    expect.equality(row_chars(grid, 1), "▀▀")
    expect.equality(row_chars(grid, 2), "  ")
    expect.equality(row_chars(grid, 3), "  ")
end

T["very wide line collapses without truncating content density"] = function()
    local grid = squash({ "abcdefghijklmnopqrstuvwxyz0123456789ABCD" }, 4, 1)

    expect.equality(#grid, 1)
    expect.equality(row_chars(grid, 1), "▀▀▀▀")
end

T["multi-byte wide chars contribute their display width to density"] = function()
    local grid = squash({ "中文" }, 4, 1) -- 2 chars, 4 display cols

    expect.equality(row_chars(grid, 1), "▀▀▀▀")
end

T["emoji width follows strdisplaywidth"] = function()
    local grid = squash({ "😀😀😀😀" }, 8, 1) -- 4 chars, 8 display cols

    expect.equality(row_chars(grid, 1), "▀▀▀▀▀▀▀▀")
end

T["mixed ascii and wide chars share the same display column space"] = function()
    local grid = squash({ "a😀b" }, 4, 1) -- 1+2+1 = 4 display cols

    expect.equality(row_chars(grid, 1), "▀▀▀▀")
end

T["tabs use their actual starting display column"] = function()
    local grid = squash({ "a\tb" }, 9, 1)

    expect.equality(row_chars(grid, 1), "▀       ▀")
end

T["combining sequences do not advance an extra display column"] = function()
    local grid = squash({ "áb" }, 2, 1)

    expect.equality(row_chars(grid, 1), "▀▀")
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

    expect.equality(row_chars(grid, 1), "▀▀▀ ▀")
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

T["higher-priority semantic spans override top logical row precedence"] = function()
    local source = { "a", "a" }
    local highlights = semantic_highlights(source, {
        top = {
            { line = 0, start_col = 0, end_col = 1, highlight = "TopLow", priority = 1 },
        },
        bottom = {
            { line = 1, start_col = 0, end_col = 1, highlight = "BottomHigh", priority = 2 },
        },
    })
    local grid = squash(source, 1, 1, highlights)

    expect.equality(row_chars(grid, 1), "█")
    expect.equality(row_highlights(grid, 1), { "BottomHigh" })
end

T["hl_group propagates to every covered cell at ratio 1"] = function()
    local highlights = {
        [1] = { { hl_group = "String", col_start = 1, col_end = 3 } },
    }
    local grid = squash({ "abc" }, 3, 1, highlights)

    expect.equality(row_chars(grid, 1), "▀▀▀")
    expect.equality(row_highlights(grid, 1), { "String", "String", "String" })
end

T["hl_group pairing prefers the top logical row when both have highlights"] = function()
    local highlights = {
        [1] = { { hl_group = "Top", col_start = 1, col_end = 3 } },
        [2] = { { hl_group = "Bottom", col_start = 1, col_end = 3 } },
    }
    local grid = squash({ "abc", "abc" }, 3, 1, highlights)

    expect.equality(row_chars(grid, 1), "███")
    expect.equality(row_highlights(grid, 1), { "Top", "Top", "Top" })
end

T["hl_group pairing falls back to the bottom row when top has no highlight"] = function()
    local highlights = {
        [2] = { { hl_group = "Bottom", col_start = 1, col_end = 3 } },
    }
    local grid = squash({ "abc", "abc" }, 3, 1, highlights)

    expect.equality(row_chars(grid, 1), "███")
    expect.equality(row_highlights(grid, 1), { "Bottom", "Bottom", "Bottom" })
end

T["hl_group on the bottom row tints the lower half where top is empty"] = function()
    local highlights = {
        [2] = { { hl_group = "Bottom", col_start = 1, col_end = 3 } },
    }
    -- top line only fills col 1; bottom line fills all three.
    local grid = squash({ "a  ", "xyz" }, 3, 1, highlights)

    expect.equality(row_chars(grid, 1), "█▄▄")
    expect.equality(row_highlights(grid, 1), { "Bottom", "Bottom", "Bottom" })
end

T["hl_group horizontal merge keeps the highlight on its owning target cell"] = function()
    local highlights = {
        [1] = { { hl_group = "String", col_start = 1, col_end = 4 } },
    }
    local grid = squash({ "abcdefgh" }, 2, 1, highlights)

    expect.equality(row_chars(grid, 1), "▀▀")
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
    expect.equality(#first_grid, #second_grid)
    for row = 1, #first_grid do
        expect.equality(row_chars(first_grid, row), row_chars(second_grid, row))
        for col = 1, #first_grid[row] do
            expect.equality(first_grid[row][col].hl_group, second_grid[row][col].hl_group)
        end
    end
end

T["odd source line count fills top half of the final paired row"] = function()
    -- 3 source lines, height 2 => logical_height 4, v_ratio 1.
    -- logical[1]=line1, [2]=line2, [3]=line3, [4]=empty (no source line 4).
    local grid = squash({ "x", "x", "x" }, 1, 2)

    expect.equality(#grid, 2)
    expect.equality(row_chars(grid, 1), "█") -- line1 + line2
    expect.equality(row_chars(grid, 2), "▀") -- line3 + empty
end

return T
