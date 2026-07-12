local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local layout = require("scrollbar.layout")

local T = MiniTest.new_set()

local function mark(line)
    return { line = line, type = "Search" }
end

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

T["normalized mapping clamps document boundaries"] = function()
    expect.equality(layout.map_position(-1, 100, 10), 0)
    expect.equality(layout.map_position(0, 100, 10), 0)
    expect.equality(layout.map_position(50, 100, 10), 4)
    expect.equality(layout.map_position(99, 100, 10), 9)
    expect.equality(layout.map_position(100, 100, 10), 9)
end

T["normalized geometry handles empty and one-line documents"] = function()
    local empty = layout.normalized({
        height = 6,
        line_count = 0,
        top_line = 0,
        bottom_line = 0,
        marks = { mark(0) },
    })
    local one_line = layout.normalized({
        height = 6,
        line_count = 1,
        top_line = 0,
        bottom_line = 0,
        marks = { mark(0) },
    })

    expect.equality(empty.mark_rows, { 0 })
    expect.equality(empty.handle, { first_row = 0, last_row = 5 })
    expect.equality(one_line.mark_rows, { 0 })
    expect.equality(one_line.handle, { first_row = 0, last_row = 5 })
end

T["normalized geometry fills the track when all lines are visible"] = function()
    local geometry = layout.normalized({
        height = 8,
        line_count = 5,
        top_line = 0,
        bottom_line = 4,
        marks = { mark(0), mark(4) },
    })

    expect.equality(geometry.mark_rows, { 0, 7 })
    expect.equality(geometry.handle, { first_row = 0, last_row = 7 })
end

T["normalized geometry keeps a minimum one-row handle for large documents"] = function()
    local geometry = layout.normalized({
        height = 10,
        line_count = 1000000000,
        top_line = 500000000,
        bottom_line = 500000000,
        marks = { mark(0), mark(999999999) },
    })

    expect.equality(geometry.mark_rows, { 0, 9 })
    expect.equality(geometry.handle.first_row, geometry.handle.last_row)
end

T["screen geometry keeps same-buffer window views independent"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local first_win = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second_win = vim.api.nvim_get_current_win()

        vim.api.nvim_win_call(first_win, function()
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            vim.cmd("normal! zt")
        end)
        vim.api.nvim_win_call(second_win, function()
            vim.api.nvim_win_set_cursor(0, { 180, 0 })
            vim.cmd("normal! zt")
        end)

        local child_layout = require("scrollbar.layout")
        local marks = {
            { line = 0, type = "Search" },
            { line = 199, type = "Search" },
        }
        return {
            first = child_layout.screen({
                source_win = first_win,
                height = vim.api.nvim_win_get_height(first_win),
                marks = marks,
            }),
            second = child_layout.screen({
                source_win = second_win,
                height = vim.api.nvim_win_get_height(second_win),
                marks = marks,
            }),
            first_height = vim.api.nvim_win_get_height(first_win),
            second_height = vim.api.nvim_win_get_height(second_win),
        }
    end)

    expect.equality(result.first.mark_rows, { 0, result.first_height - 1 })
    expect.equality(result.second.mark_rows, { 0, result.second_height - 1 })
    expect.equality(result.first.handle.first_row, 0)
    expect.equality(result.second.handle.first_row > result.first.handle.first_row, true)
end

T["screen geometry uses the renderer-owned text track height"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        vim.o.showtabline = 2
        vim.o.laststatus = 2
        vim.o.cmdheight = 0
        vim.o.tabline = "TABLINE"
        vim.o.statusline = "STATUSLINE"
        vim.wo.winbar = "WINBAR"

        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local raw_height = vim.api.nvim_win_get_height(source_win)
        local track_height = raw_height - 1
        local geometry = require("scrollbar.layout").screen({
            source_win = source_win,
            height = track_height,
            marks = {
                { line = 0, type = "Search" },
                { line = 199, type = "Search" },
            },
        })
        return {
            raw_height = raw_height,
            track_height = track_height,
            geometry = geometry,
        }
    end)

    expect.equality(result.geometry.mark_rows, { 0, result.track_height - 1 })
    expect.equality(result.geometry.viewport_end, result.track_height - 1)
    expect.equality(result.geometry.handle.last_row < result.raw_height, true)
end

T["screen geometry compresses closed folds without scanning buffer lines"] = function()
    local child = new_child()
    local geometry = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            "before",
            "{{{",
            "folded one",
            "folded two",
            "folded three",
            "folded four",
            "}}}",
            "after one",
            "after two",
            "after three",
        })
        vim.wo.foldmethod = "marker"
        vim.cmd("normal! zM")

        return require("scrollbar.layout").screen({
            source_win = vim.api.nvim_get_current_win(),
            height = vim.api.nvim_win_get_height(0),
            marks = {
                { line = 1, type = "Search" },
                { line = 3, type = "Search" },
                { line = 6, type = "Search" },
                { line = 7, type = "Search" },
            },
        })
    end)

    expect.equality(geometry.total_extent, 5)
    expect.equality(geometry.mark_rows[1], geometry.mark_rows[2])
    expect.equality(geometry.mark_rows[2], geometry.mark_rows[3])
    expect.equality(geometry.mark_rows[4] > geometry.mark_rows[3], true)
end

T["screen geometry includes virtual lines in mark and handle coordinates"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local namespace = vim.api.nvim_create_namespace("scrollbar-layout-test")
        vim.api.nvim_buf_set_extmark(0, namespace, 1, 0, {
            virt_lines = {
                { { "above one", "Normal" } },
                { { "above two", "Normal" } },
            },
            virt_lines_above = true,
        })
        vim.api.nvim_buf_set_extmark(0, namespace, 2, 0, {
            virt_lines = { { { "below", "Normal" } } },
        })

        local winid = vim.api.nvim_get_current_win()
        return {
            geometry = require("scrollbar.layout").screen({
                source_win = winid,
                height = vim.api.nvim_win_get_height(winid),
                marks = {
                    { line = 0, type = "Search" },
                    { line = 1, type = "Search" },
                    { line = 2, type = "Search" },
                },
            }),
            height = vim.api.nvim_win_get_height(winid),
        }
    end)

    expect.equality(result.geometry.total_extent, 6)
    expect.equality(result.geometry.mark_rows[1], 0)
    expect.equality(result.geometry.mark_rows[2] > result.geometry.mark_rows[1], true)
    expect.equality(result.geometry.mark_rows[3] < result.height - 1, true)
end

T["screen geometry accounts for wrapped topline offsets"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        vim.o.columns = 30
        vim.wo.wrap = true
        local lines = { string.rep("x", 1000) }
        for index = 2, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 900 })
        vim.cmd("redraw")

        local winid = vim.api.nvim_get_current_win()
        return {
            geometry = require("scrollbar.layout").screen({
                source_win = winid,
                height = vim.api.nvim_win_get_height(winid),
                marks = { { line = 0, type = "Search" } },
            }),
            view = vim.fn.winsaveview(),
        }
    end)

    expect.equality(result.view.topline, 1)
    expect.equality(result.view.skipcol > 0, true)
    expect.equality(result.geometry.viewport_start > 0, true)
    expect.equality(result.geometry.mark_rows[1], 0)
    expect.equality(result.geometry.handle.first_row > result.geometry.mark_rows[1], true)
end

T["screen geometry subtracts visible diff topfill from the viewport offset"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local left_win = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            "one",
            "two",
            "three",
            "four",
            "five",
            "six",
            "seven",
            "eight",
            "nine",
        })
        vim.cmd("vnew")
        local right_win = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "nine" })

        vim.api.nvim_win_call(left_win, function()
            vim.cmd("diffthis")
        end)
        vim.api.nvim_win_call(right_win, function()
            vim.cmd("diffthis")
            vim.api.nvim_win_set_cursor(0, { 2, 0 })
            vim.cmd("normal! zt")
            vim.api.nvim_feedkeys(vim.keycode("3<C-Y>"), "nx", false)
        end)
        vim.cmd("diffupdate")
        vim.cmd("redraw")

        local view = vim.api.nvim_win_call(right_win, vim.fn.winsaveview)
        local prefix = vim.api.nvim_win_text_height(right_win, { end_row = 1, end_vcol = 0 }).all
        local measured = vim.api.nvim_win_text_height(right_win, {})
        return {
            geometry = require("scrollbar.layout").screen({
                source_win = right_win,
                height = vim.api.nvim_win_get_height(right_win),
                marks = {},
            }),
            prefix = prefix,
            fill = measured.fill,
            view = view,
        }
    end)

    expect.equality(result.fill > 0, true)
    expect.equality(result.view.topfill > 0, true)
    expect.equality(result.geometry.viewport_start, result.prefix - result.view.topfill)
end

return T
