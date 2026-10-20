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

T["mapping preserves document rows when the content fits"] = function()
    expect.equality(layout.map_position(-1, 5, 8), 0)
    expect.equality(layout.map_position(2, 5, 8), 2)
    expect.equality(layout.map_position(4, 5, 8), 4)
    expect.equality(layout.map_position(5, 5, 8), 4)
    expect.equality(layout.map_position(7, 8, 8), 7)
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

T["normalized geometry aligns marks when all lines are visible"] = function()
    local geometry = layout.normalized({
        height = 8,
        line_count = 5,
        top_line = 0,
        bottom_line = 4,
        marks = { mark(0), mark(4) },
    })

    expect.equality(geometry.mark_rows, { 0, 4 })
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

T["normalized geometry accepts cached mark rows while recomputing the viewport handle"] = function()
    local marks = { mark(0), mark(50), mark(99) }
    local mark_rows = layout.normalized_mark_rows({ height = 10, line_count = 100, marks = marks })
    local first = layout.normalized({
        height = 10,
        line_count = 100,
        top_line = 0,
        bottom_line = 9,
        marks = marks,
        mark_rows = mark_rows,
    })
    local second = layout.normalized({
        height = 10,
        line_count = 100,
        top_line = 80,
        bottom_line = 89,
        marks = marks,
        mark_rows = mark_rows,
    })

    expect.equality(first.mark_rows, mark_rows)
    expect.equality(second.mark_rows, mark_rows)
    expect.equality(second.handle.first_row > first.handle.first_row, true)
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
    expect.equality(result.geometry.mark_rows, { 0, 3, 4 })
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

T["screen geometry cache hits issue zero nvim_win_text_height calls beyond the canary"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local function wrap_win_text_height_counter()
            local calls = 0
            local original = vim.api.nvim_win_text_height
            ---@diagnostic disable-next-line: duplicate-set-field
            vim.api.nvim_win_text_height = function(...)
                calls = calls + 1
                return original(...)
            end
            return {
                count = function()
                    return calls
                end,
                restore = function()
                    vim.api.nvim_win_text_height = original
                end,
            }
        end

        local lines = {}
        for index = 1, 200 do
            if index % 25 == 0 then
                lines[index] = string.rep("x", 200)
            else
                lines[index] = "line " .. index
            end
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.foldmethod = "manual"
        vim.cmd("normal! 30,80fold")

        local layout_module = require("scrollbar.layout")
        -- Tighten the sweep interval. Otherwise, consecutive passes share a
        -- sweep window and correctly issue zero measurements.
        layout_module.screen_extent_sweep_interval_ms = 0
        local source_win = vim.api.nvim_get_current_win()
        local marks = {}
        for index = 0, 199, 13 do
            marks[#marks + 1] = { line = index, type = "Search" }
        end

        local counter = wrap_win_text_height_counter()
        local function call_screen()
            local before = counter.count()
            local geometry = layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
            return {
                during = counter.count() - before,
                total_extent = geometry.total_extent,
            }
        end

        local first = call_screen()
        local second = call_screen()
        counter.restore()
        layout_module.screen_extent_sweep_interval_ms = nil
        return { first = first, second = second }
    end)

    expect.equality(result.first.during > 1, true)
    -- The canary sweep measures the one chunk as 4 sub-spans of 64 lines,
    -- and rows_between measures the last line of the buffer separately.
    expect.equality(result.second.during, 5)
end

T["renderer clear_source_cache clears the screen-geometry cache"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local function wrap_win_text_height_counter()
            local calls = 0
            local original = vim.api.nvim_win_text_height
            ---@diagnostic disable-next-line: duplicate-set-field
            vim.api.nvim_win_text_height = function(...)
                calls = calls + 1
                return original(...)
            end
            return {
                count = function()
                    return calls
                end,
                restore = function()
                    vim.api.nvim_win_text_height = original
                end,
            }
        end

        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local layout_module = require("scrollbar.layout")
        local renderer = require("scrollbar.renderer")
        local source_win = vim.api.nvim_get_current_win()
        local marks = {
            { line = 0, type = "Search" },
            { line = 199, type = "Search" },
        }

        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        local counter = wrap_win_text_height_counter()
        call_screen()
        local after_first = counter.count()
        call_screen()
        local after_warm = counter.count()
        renderer.dispose()
        local before_post_clear = counter.count()
        call_screen()
        local after_post_clear = counter.count()
        counter.restore()
        return {
            warm_calls = after_warm - after_first,
            cleared_calls = after_post_clear - before_post_clear,
        }
    end)

    expect.equality(result.warm_calls, 0)
    expect.equality(result.cleared_calls >= 1, true)
end

T["track_row_to_line issues zero text-height calls in uniform windows"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local function wrap_win_text_height_counter()
            local calls = 0
            local original = vim.api.nvim_win_text_height
            ---@diagnostic disable-next-line: duplicate-set-field
            vim.api.nvim_win_text_height = function(...)
                calls = calls + 1
                return original(...)
            end
            return {
                count = function()
                    return calls
                end,
                restore = function()
                    vim.api.nvim_win_text_height = original
                end,
            }
        end

        local lines = {}
        for index = 1, 400 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local height = vim.api.nvim_win_get_height(source_win)
        local total_extent = vim.api.nvim_win_text_height(source_win, {}).all

        local counter = wrap_win_text_height_counter()
        local function call_track(row)
            local before = counter.count()
            layout_module.track_row_to_line(source_win, row, height, "screenline", total_extent)
            return counter.count() - before
        end

        for row = 0, height - 1 do
            call_track(row)
        end
        local baseline = counter.count()
        local repeat_delta = call_track(0)
        local another_delta = call_track(math.floor(height / 2))
        local final_delta = call_track(height - 1)
        counter.restore()
        return {
            baseline = baseline,
            repeat_delta = repeat_delta,
            another_delta = another_delta,
            final_delta = final_delta,
        }
    end)

    expect.equality(result.baseline, 1)
    expect.equality(result.repeat_delta, 0)
    expect.equality(result.another_delta, 0)
    expect.equality(result.final_delta, 0)
end

local COUNTER_FACTORY_CODE = [=[
    local calls = 0
    local original = vim.api.nvim_win_text_height
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.api.nvim_win_text_height = function(...)
        calls = calls + 1
        return original(...)
    end
    return {
        count = function()
            return calls
        end,
        delta = function(since)
            return calls - since
        end,
        restore = function()
            vim.api.nvim_win_text_height = original
        end,
    }
]=]

T["screen geometry cache invalidates on fold close without an autocmd"] = function()
    local child = new_child()
    local result = child.lua_func(function(factory_code)
        local layout_module = require("scrollbar.layout")
        -- Tighten the uniform verify interval, so that the next screen pass
        -- always observes the silent fold change.
        layout_module.screen_extent_verify_interval_ms = 0
        local counter = loadstring(factory_code)()
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.foldmethod = "manual"
        vim.cmd("30,80fold")
        vim.cmd("30,80foldopen")

        local source_win = vim.api.nvim_get_current_win()
        local marks = { { line = 0, type = "Search" }, { line = 199, type = "Search" } }
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        local g1 = call_screen()
        local warm_calls = counter.count()
        vim.cmd("30,80foldclose")
        local g2 = call_screen()
        local g2_calls = counter.delta(warm_calls)
        counter.restore()
        layout_module.screen_extent_verify_interval_ms = nil
        return {
            g1_extent = g1.total_extent,
            g2_extent = g2.total_extent,
            g2_calls = g2_calls,
        }
    end, COUNTER_FACTORY_CODE)

    expect.equality(result.g2_extent < result.g1_extent, true)
    expect.equality(result.g2_calls > 1, true)
end

T["screen geometry cache invalidates on window option change"] = function()
    local child = new_child()
    local result = child.lua_func(function(factory_code)
        local counter = loadstring(factory_code)()
        vim.o.columns = 30
        -- Tighten the digest interval. Otherwise, consecutive standalone calls
        -- share a digest window and correctly reuse the cached digest. Wired
        -- setups clear the cached digest immediately on OptionSet instead.
        require("scrollbar.layout").screen_extent_digest_interval_ms = 0
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        lines[50] = string.rep("x", 200)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.wrap = false

        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local marks = { { line = 0, type = "Search" }, { line = 99, type = "Search" } }
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        local g1 = call_screen()
        local warm_calls = counter.count()
        vim.wo.wrap = true
        local g2 = call_screen()
        local wrap_calls = counter.delta(warm_calls)
        counter.restore()
        require("scrollbar.layout").screen_extent_digest_interval_ms = nil
        return {
            g1_extent = g1.total_extent,
            g2_extent = g2.total_extent,
            wrap_calls = wrap_calls,
        }
    end, COUNTER_FACTORY_CODE)

    expect.equality(result.g2_extent > result.g1_extent, true)
    expect.equality(result.wrap_calls > 1, true)
end

T["screen geometry skips measurements on layout-only option changes"] = function()
    local child = new_child()
    local result = child.lua_func(function(factory_code)
        local counter = loadstring(factory_code)()
        local lines = {}
        for index = 1, 50 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.number = false

        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local marks = { { line = 0, type = "Search" }, { line = 49, type = "Search" } }
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        local g1 = call_screen()
        local warm_calls = counter.count()
        vim.wo.number = true
        local g2 = call_screen()
        local number_calls = counter.delta(warm_calls)
        counter.restore()
        return {
            g1_extent = g1.total_extent,
            g2_extent = g2.total_extent,
            number_calls = number_calls,
        }
    end, COUNTER_FACTORY_CODE)

    expect.equality(result.g2_extent == result.g1_extent, true)
    -- 'number' cannot change vertical extents. A uniform window keeps its
    -- verified extent and does not measure it again.
    expect.equality(result.number_calls, 0)
end

T["screen geometry recomputes viewport without measurements on scroll"] = function()
    local child = new_child()
    local result = child.lua_func(function(factory_code)
        local counter = loadstring(factory_code)()
        local lines = {}
        for index = 1, 400 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local marks = { { line = 0, type = "Search" }, { line = 399, type = "Search" } }
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        vim.api.nvim_win_set_cursor(source_win, { 1, 0 })
        vim.cmd("normal! zt")
        local g1 = call_screen()
        local warm_calls = counter.count()
        vim.api.nvim_win_set_cursor(source_win, { 200, 0 })
        vim.cmd("normal! zt")
        local g2 = call_screen()
        local g2_calls = counter.delta(warm_calls)
        counter.restore()
        return {
            g1_viewport_start = g1.viewport_start,
            g2_viewport_start = g2.viewport_start,
            g2_calls = g2_calls,
        }
    end, COUNTER_FACTORY_CODE)

    expect.equality(result.g2_viewport_start ~= result.g1_viewport_start, true)
    expect.equality(result.g2_calls, 0)
end

T["screen geometry tracks text growth without measurements in uniform windows"] = function()
    local child = new_child()
    local result = child.lua_func(function(factory_code)
        local counter = loadstring(factory_code)()
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.wrap = false
        vim.wo.foldmethod = "manual"

        local layout_module = require("scrollbar.layout")
        local source_buf = vim.api.nvim_get_current_buf()
        local source_win = vim.api.nvim_get_current_win()
        local marks = { { line = 0, type = "Search" }, { line = 199, type = "Search" } }
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        local g1 = call_screen()
        local warm_calls = counter.count()
        local appended = {}
        for index = 1, 100 do
            appended[index] = "appended " .. index
        end
        vim.api.nvim_buf_set_lines(source_buf, 200, -1, false, appended)
        local g2 = call_screen()
        local g2_calls = counter.delta(warm_calls)
        counter.restore()
        return {
            g1_extent = g1.total_extent,
            g2_extent = g2.total_extent,
            g2_calls = g2_calls,
        }
    end, COUNTER_FACTORY_CODE)

    expect.equality(result.g2_extent > result.g1_extent, true)
    -- Uniform manual-fold nowrap windows update extents by arithmetic.
    expect.equality(result.g2_calls, 0)
end

T["screen geometry handles window resize without measurements in uniform windows"] = function()
    local child = new_child()
    local result = child.lua_func(function(factory_code)
        local counter = loadstring(factory_code)()
        local lines = {}
        for index = 1, 400 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local marks = { { line = 0, type = "Search" }, { line = 399, type = "Search" } }
        local original_height = vim.api.nvim_win_get_height(source_win)
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        local g1 = call_screen()
        local warm_calls = counter.count()
        vim.api.nvim_win_set_height(source_win, original_height - 4)
        local g2 = call_screen()
        local g2_calls = counter.delta(warm_calls)
        counter.restore()
        return {
            g1_last_row = g1.handle.last_row,
            g2_last_row = g2.handle.last_row,
            g2_calls = g2_calls,
        }
    end, COUNTER_FACTORY_CODE)

    expect.equality(result.g2_last_row < result.g1_last_row, true)
    expect.equality(result.g2_calls, 0)
end

T["M.screen projects compact_search rows aligned with equivalent expanded marks"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 30 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 10)

        local layout_module = require("scrollbar.layout")
        local compact = require("scrollbar.providers.search.compact")
        local match_lines = { 0, 5, 10, 15, 20, 25 }
        local reference_marks = {}
        for index, line in ipairs(match_lines) do
            reference_marks[index] = { line = line, type = "Search" }
        end

        local expanded = layout_module.screen({
            source_win = source_win,
            height = 10,
            marks = reference_marks,
        })
        local projected = layout_module.screen({
            source_win = source_win,
            height = 10,
            marks = {},
            compact_search = compact.encode(match_lines),
        })

        return {
            mark_rows = expanded.mark_rows,
            compact_mark_rows = projected.compact_mark_rows,
            has_compact_field = projected.compact_mark_rows ~= nil,
        }
    end)

    expect.equality(result.has_compact_field, true)
    expect.equality(result.compact_mark_rows, result.mark_rows)
end

T["M.screen maps an unsorted compact blob like ordinary marks on folded and wrapped lines"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 200 do
            lines[index] = index % 7 == 0 and string.rep("wrapped ", 40) or ("line " .. index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 10)
        vim.wo[source_win].wrap = true
        vim.wo[source_win].foldmethod = "manual"
        vim.cmd("51,80fold")

        local layout_module = require("scrollbar.layout")
        local compact = require("scrollbar.providers.search.compact")
        -- Unsorted, with duplicates that are not adjacent, a folded line, a
        -- wrapped line, and a line after the end of the buffer.
        local match_lines = { 150, 10, 10, 60, 199, 250, 0, 60, 120, 10, 13 }
        local reference_marks = {}
        for index, line in ipairs(match_lines) do
            reference_marks[index] = { line = line, type = "Search" }
        end

        local reference = layout_module.screen({
            source_win = source_win,
            height = 10,
            marks = reference_marks,
        })
        local presorted = layout_module.screen({
            source_win = source_win,
            height = 10,
            marks = { { line = 13, type = "Search" }, { line = 60, type = "Search" } },
            marks_sorted = true,
            compact_search = compact.encode(match_lines),
        })
        local unsorted = layout_module.screen({
            source_win = source_win,
            height = 10,
            marks = {},
            compact_search = compact.encode(match_lines),
        })

        local distinct = {}
        for _, row in ipairs(reference.mark_rows) do
            distinct[row] = true
        end
        return {
            reference = reference.mark_rows,
            presorted = presorted.compact_mark_rows,
            unsorted = unsorted.compact_mark_rows,
            distinct_rows = vim.tbl_count(distinct),
        }
    end)

    expect.equality(result.distinct_rows > 3, true)
    expect.equality(result.presorted, result.reference)
    expect.equality(result.unsorted, result.reference)
end

T["uniform probe finds a silent fold in every slice below the viewport"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local layout_module = require("scrollbar.layout")
        layout_module.screen_extent_verify_interval_ms = 0
        -- 1003 lines below the viewport make four slices of 250 lines and a
        -- remainder of 3 lines.
        local lines = {}
        for index = 1, 2023 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.foldmethod = "manual"
        vim.wo.wrap = false
        local source_win = vim.api.nvim_get_current_win()
        local height = 20
        local function total_extent()
            return layout_module.screen({ source_win = source_win, height = height, marks = {} }).total_extent
        end
        local function show_line_1001()
            vim.fn.winrestview({ topline = 1001, lnum = 1001 })
        end

        -- Return the number of probes after the first probe that find a fold
        -- of `first`..`last` (one-based), or nil.
        local function probes_to_find(first, last)
            vim.cmd("normal! zE")
            layout_module.clear_screen_cache(source_win)
            show_line_1001()
            total_extent()
            vim.cmd(string.format("%d,%dfold", first, last))
            show_line_1001()
            local truth = vim.api.nvim_win_text_height(source_win, {}).all
            for probe = 1, 8 do
                if total_extent() == truth then
                    return probe
                end
            end
            return nil
        end

        local found = {
            first_slice = probes_to_find(1031, 1060),
            second_slice = probes_to_find(1281, 1310),
            last_slice = probes_to_find(1781, 1810),
            remainder = probes_to_find(2022, 2023),
        }
        layout_module.screen_extent_verify_interval_ms = nil
        return found
    end)

    for _, slice in ipairs({ "first_slice", "second_slice", "last_slice", "remainder" }) do
        expect.equality({ slice, result[slice] ~= nil and result[slice] <= 4 }, { slice, true })
    end
end

T["compose cache drops the entries of unreachable mark layers"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local layout_module = require("scrollbar.layout")
        local active_config = require("scrollbar.config").set({ scrollbar = { thumb = { text = "H" } } })
        layout_module.clear_cache()

        local function compose_cache()
            local index = 1
            while true do
                local name, value = debug.getupvalue(layout_module.compose, index)
                assert(name ~= nil, "compose_cache is not an upvalue of layout.compose")
                if name == "compose_cache" then
                    return value
                end
                index = index + 1
            end
        end
        local function entry_count()
            collectgarbage("collect")
            collectgarbage("collect")
            local count = 0
            for _ in pairs(compose_cache()) do
                count = count + 1
            end
            return count
        end
        local function input(row, mark_layer)
            return {
                config = active_config,
                height = 10,
                line_count = 100,
                geometry = {
                    total_extent = 100,
                    viewport_start = 0,
                    viewport_end = 9,
                    mark_rows = { row },
                    handle = { first_row = 1, last_row = 2 },
                },
                marks = { { line = row * 10, type = "Search" } },
                mark_layer = mark_layer,
            }
        end

        -- Each call without `mark_layer` resolves a new layer that nothing
        -- else holds.
        for index = 1, 200 do
            layout_module.compose(input(index % 10))
        end
        local after_rebuilds = entry_count()

        -- A layer that the caller still holds keeps its entry and its cached
        -- output.
        local held = layout_module.mark_layer(input(3))
        local first = layout_module.compose(input(3, held))
        local held_count = entry_count()
        local second = layout_module.compose(input(3, held))
        return {
            after_rebuilds = after_rebuilds,
            held_count = held_count,
            cache_hit = first == second,
        }
    end)

    expect.equality(result.after_rebuilds <= 1, true)
    expect.equality(result.held_count >= 1 and result.held_count <= 2, true)
    expect.equality(result.cache_hit, true)
end

T["screen geometry reuses the mark rows on a scroll in a folded window"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 3000 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.foldmethod = "manual"
        vim.cmd("101,200fold")

        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local marks = {}
        for line = 0, 2999, 7 do
            marks[#marks + 1] = { line = line, type = "Search" }
        end
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        vim.api.nvim_win_set_cursor(source_win, { 1, 0 })
        vim.cmd("normal! zt")
        local first = call_screen()
        local original = layout_module.map_position
        local calls = 0
        ---@diagnostic disable-next-line: duplicate-set-field
        layout_module.map_position = function(...)
            calls = calls + 1
            return original(...)
        end
        vim.api.nvim_win_set_cursor(source_win, { 1500, 0 })
        vim.cmd("normal! zt")
        local second = call_screen()
        layout_module.map_position = original
        return {
            moved = second.viewport_start ~= first.viewport_start,
            same_rows = rawequal(first.mark_rows, second.mark_rows),
            calls = calls,
        }
    end)

    expect.equality(result.moved, true)
    expect.equality(result.same_rows, true)
    -- The two calls map the handle. The mark rows come from the cache.
    expect.equality(result.calls, 2)
end

T["screen geometry follows a fold that moves to another chunk"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        -- 1100 lines make three chunks of 512 lines. The two folds are in the
        -- first two chunks, so that one sweep usually measures both changes.
        local lines = {}
        for index = 1, 1100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.foldmethod = "manual"
        vim.cmd("101,150fold")
        vim.cmd("601,650fold")
        vim.cmd("601foldopen")

        local layout_module = require("scrollbar.layout")
        layout_module.screen_extent_sweep_interval_ms = 0
        local source_win = vim.api.nvim_get_current_win()
        local height = vim.api.nvim_win_get_height(source_win)
        local marks = {}
        for line = 0, 1099, 7 do
            marks[#marks + 1] = { line = line, type = "Search" }
        end
        local function call_screen()
            return layout_module.screen({ source_win = source_win, height = height, marks = marks })
        end

        call_screen()
        -- The total extent does not change: one fold opens, and a fold of
        -- the same size in another chunk closes.
        vim.cmd("101foldopen")
        vim.cmd("601foldclose")
        local total = vim.api.nvim_win_text_height(source_win, {}).all
        -- The sweep has a time budget, so it can need more than one pass to
        -- measure every chunk.
        local geometry = call_screen()
        for _ = 1, 3 do
            if geometry.total_extent == total then
                break
            end
            geometry = call_screen()
        end
        layout_module.screen_extent_sweep_interval_ms = nil

        local wrong = 0
        for index, entry in ipairs(marks) do
            local prefix = entry.line == 0 and 0
                or vim.api.nvim_win_text_height(source_win, {
                    start_row = 0,
                    start_vcol = 0,
                    end_row = entry.line,
                    end_vcol = 0,
                }).all
            if geometry.mark_rows[index] ~= layout_module.map_position(prefix, total, height) then
                wrong = wrong + 1
            end
        end
        return { wrong = wrong, extent = geometry.total_extent, total = total }
    end)

    expect.equality(result.extent, result.total)
    expect.equality(result.wrong, 0)
end

T["screen geometry follows a fold that moves inside one chunk"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local layout_module = require("scrollbar.layout")
        layout_module.screen_extent_sweep_interval_ms = 0
        local source_win = vim.api.nvim_get_current_win()
        local height = vim.api.nvim_win_get_height(source_win)

        -- Two folds of the same size in different sub-spans of one chunk swap
        -- their state, so the height of the chunk does not change.
        local function wrong_rows(line_count, first_fold, second_fold)
            local lines = {}
            for index = 1, line_count do
                lines[index] = "line " .. index
            end
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            vim.wo.foldmethod = "manual"
            vim.cmd("normal! zE")
            vim.cmd(first_fold .. "fold")
            vim.cmd(second_fold .. "fold")
            vim.cmd(second_fold:match("^%d+") .. "foldopen")
            layout_module.clear_screen_cache(source_win)
            local marks = {}
            for line = 0, line_count - 1, 3 do
                marks[#marks + 1] = { line = line, type = "Search" }
            end
            local function call_screen()
                return layout_module.screen({ source_win = source_win, height = height, marks = marks })
            end

            call_screen()
            vim.cmd(first_fold:match("^%d+") .. "foldopen")
            vim.cmd(second_fold:match("^%d+") .. "foldclose")
            -- One sweep measures at least one chunk, so one render for each
            -- chunk measures every chunk.
            local geometry
            for _ = 1, math.ceil(line_count / 512) + 1 do
                geometry = call_screen()
            end

            local total = vim.api.nvim_win_text_height(source_win, {}).all
            local wrong = 0
            for index, entry in ipairs(marks) do
                local prefix = entry.line == 0 and 0
                    or vim.api.nvim_win_text_height(source_win, {
                        start_row = 0,
                        start_vcol = 0,
                        end_row = entry.line,
                        end_vcol = 0,
                    }).all
                if geometry.mark_rows[index] ~= layout_module.map_position(prefix, total, height) then
                    wrong = wrong + 1
                end
            end
            return wrong
        end

        local counts = {
            -- 1100 lines make three chunks. Both folds are in the first chunk.
            chunks = wrong_rows(1100, "101,150", "201,250"),
            -- 400 lines make one chunk.
            single = wrong_rows(400, "51,100", "201,250"),
        }
        layout_module.screen_extent_sweep_interval_ms = nil
        return counts
    end)

    expect.equality(result.chunks, 0)
    expect.equality(result.single, 0)
end

-- Apply `edit` to a wrapped 1100-line buffer with one closed fold, and count
-- the mark rows that differ from a fresh measurement. Each edit keeps the total
-- extent, so only the generation of the extent layer can invalidate the cached
-- mark rows.
local function rows_after_edit(foldmethod, edit)
    local child = new_child()
    return child.lua_func(function(method, name)
        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local width = vim.api.nvim_win_get_width(source_win)
        local lines = {}
        for index = 1, 1100 do
            lines[index] = "line " .. index
        end
        -- Line 300 wraps to 20 rows. Lines 401-430 fill one row each. Lines
        -- 701-710 make the closed fold.
        lines[300] = string.rep("x", width * 20)
        for index = 401, 430 do
            lines[index] = string.rep("a", width - 1)
        end
        for index = 701, 710 do
            lines[index] = "    indented " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.wrap = true
        vim.wo.foldmethod = method
        vim.wo.foldlevel = 0
        if method == "manual" then
            vim.cmd("701,710fold")
        end

        -- A large track height makes a shift of a few rows visible.
        local height = 100
        local marks = {}
        for line = 0, 1099 do
            marks[#marks + 1] = { line = line, type = "Search" }
        end
        local function call_screen()
            return layout_module.screen({ source_win = source_win, height = height, marks = marks })
        end

        local extent_before = call_screen().total_extent
        -- Lines 257-320 make one sub-span. Lines 300 and 315 swap their text.
        if name == "block" then
            local block = vim.api.nvim_buf_get_lines(0, 299, 315, false)
            block[1], block[16] = block[16], block[1]
            vim.api.nvim_buf_set_lines(0, 299, 315, false, block)
        elseif name == "two lines" then
            local long = vim.api.nvim_buf_get_lines(0, 299, 300, false)
            local short = vim.api.nvim_buf_get_lines(0, 314, 315, false)
            vim.api.nvim_buf_set_lines(0, 299, 300, false, short)
            vim.api.nvim_buf_set_lines(0, 314, 315, false, long)
        else
            -- The joined line wraps to the 30 rows of its lines.
            vim.cmd("401,430join")
        end
        local geometry = call_screen()

        local total = vim.api.nvim_win_text_height(source_win, {}).all
        local maximum_line = vim.api.nvim_buf_line_count(0) - 1
        local wrong = 0
        for index, entry in ipairs(marks) do
            local line = math.min(entry.line, maximum_line)
            local prefix = line == 0 and 0
                or vim.api.nvim_win_text_height(source_win, {
                    start_row = 0,
                    start_vcol = 0,
                    end_row = line,
                    end_vcol = 0,
                }).all
            if geometry.mark_rows[index] ~= layout_module.map_position(prefix, total, height) then
                wrong = wrong + 1
            end
        end
        return { wrong = wrong, extent_before = extent_before, total = total }
    end, foldmethod, edit)
end

local edit_cases = MiniTest.new_set({ parametrize = { { "manual" }, { "indent" } } })
T["screen geometry follows an edit that keeps the extent"] = edit_cases

edit_cases["that trades rows inside one sub-span"] = function(foldmethod)
    local result = rows_after_edit(foldmethod, "block")
    expect.equality(result.total, result.extent_before)
    expect.equality(result.wrong, 0)
end

edit_cases["on two lines of one sub-span before one render"] = function(foldmethod)
    local result = rows_after_edit(foldmethod, "two lines")
    expect.equality(result.total, result.extent_before)
    expect.equality(result.wrong, 0)
end

edit_cases["that joins lines"] = function(foldmethod)
    local result = rows_after_edit(foldmethod, "join")
    expect.equality(result.total, result.extent_before)
    expect.equality(result.wrong, 0)
end

T["screen geometry measures a lookup from its chunk start, not from a far anchor"] = function()
    local child = new_child()
    local longest = child.lua_func(function()
        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_get_current_buf()
        local height = vim.api.nvim_win_get_height(source_win)
        local line_count = 6000
        local lines = {}
        for index = 1, line_count do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.wo.foldmethod = "manual"
        for start = 101, line_count - 30, 200 do
            vim.cmd(string.format("%d,%dfold", start, start + 19))
        end
        -- Marks on every line arrive in ascending order. The anchor list is
        -- halved many times, so few anchors stay near the start of the buffer.
        local marks = {}
        for line = 0, line_count - 1 do
            marks[#marks + 1] = { line = line, type = "Search" }
        end
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = height,
                marks = marks,
                marks_sorted = true,
            })
        end
        call_screen()
        vim.fn.winrestview({ topline = 4001, lnum = 4005 })
        call_screen()
        -- An edit that keeps the line count rebuilds the chunk of the edit,
        -- so the viewport line loses its memo entry and its anchor.
        vim.api.nvim_buf_set_text(buf, 4004, 0, 4004, 0, { "x" })

        local result = 0
        local original = vim.api.nvim_win_text_height
        vim.api.nvim_win_text_height = function(winid, opts)
            if opts ~= nil and opts.start_row ~= nil and opts.end_row ~= nil then
                result = math.max(result, opts.end_row - opts.start_row)
            end
            return original(winid, opts)
        end
        local ok, err = pcall(call_screen)
        vim.api.nvim_win_text_height = original
        assert(ok, err)
        return result
    end)

    -- A lookup measures at most one chunk (CHUNK_LINES = 512).
    expect.equality(longest <= 512, true)
end

T["screen geometry keeps the chunk memo valid after a fold in an earlier chunk"] = function()
    local child = new_child()
    local wrong = child.lua_func(function()
        local layout_module = require("scrollbar.layout")
        local source_win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_get_current_buf()
        local line_count = 3000
        -- A track as high as the buffer maps each prefix row to its own row.
        local height = line_count + 1
        local lines = {}
        for index = 1, line_count do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.wo.foldmethod = "manual"
        for start = 101, line_count - 30, 200 do
            vim.cmd(string.format("%d,%dfold", start, start + 19))
        end
        local marks = {}
        for line = 0, line_count - 1, 5 do
            marks[#marks + 1] = { line = line, type = "Search" }
        end
        local function call_screen()
            return layout_module.screen({
                source_win = source_win,
                height = height,
                marks = marks,
                marks_sorted = true,
            })
        end

        layout_module.screen_extent_sweep_interval_ms = 1e9
        call_screen()
        -- A silent fold in the third chunk, before the sweep measures it.
        vim.cmd("1201,1261fold")
        -- An edit in the fifth chunk drops the memo of that chunk. The next
        -- render looks up the viewport line there again.
        vim.fn.winrestview({ topline = 2501, lnum = 2505 })
        vim.api.nvim_buf_set_text(buf, 2504, 0, 2504, 0, { "x" })
        call_screen()

        -- Let the sweep find the fold and rebase the later chunks.
        layout_module.screen_extent_sweep_interval_ms = 0
        local geometry
        for _ = 1, math.ceil(line_count / 512) + 2 do
            geometry = call_screen()
        end
        layout_module.screen_extent_sweep_interval_ms = nil

        local total = vim.api.nvim_win_text_height(source_win, {}).all
        local count = 0
        for index, entry in ipairs(marks) do
            local prefix = entry.line == 0 and 0
                or vim.api.nvim_win_text_height(source_win, {
                    start_row = 0,
                    start_vcol = 0,
                    end_row = entry.line,
                    end_vcol = 0,
                }).all
            if geometry.mark_rows[index] ~= layout_module.map_position(prefix, total, height) then
                count = count + 1
            end
        end
        return count
    end)

    expect.equality(wrong, 0)
end

return T
