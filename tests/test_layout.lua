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
        -- Tighten the sweep interval: consecutive passes otherwise share a
        -- sweep window and legitimately issue zero measurements.
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
    expect.equality(result.second.during, 1)
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
            layout_module.track_row_to_line(source_win, row, height, "screen", total_extent)
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
        -- Tighten the uniform verify interval so the silent fold change is
        -- observed deterministically on the next screen pass.
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
        -- Tighten the digest interval: consecutive standalone calls otherwise
        -- share a digest window and legitimately reuse the cached digest
        -- (wired setups clear it immediately on OptionSet instead).
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
    -- 'number' cannot change vertical extents; a uniform window keeps its
    -- verified extent without re-measuring.
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
        local compact = require("scrollbar.providers.search_compact")
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

return T
