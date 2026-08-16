local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

T["coalesces repeated invalidations and renders the latest state"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
        local latest = 0
        local rendered = {}
        local scheduler = require("scrollbar.scheduler")

        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    update = { interval_ms = 10 },
                },
            }),
            renderer = {
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function()
                    return false
                end,
                render = function()
                    table.insert(rendered, latest)
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        latest = 1
        scheduler.invalidate_window(winid)
        latest = 2
        scheduler.invalidate_window(winid)
        latest = 3
        scheduler.invalidate_window(winid)

        assert(vim.wait(1000, function()
            return #rendered == 1
        end))
        vim.wait(40)
        scheduler.dispose()
        return rendered
    end)

    expect.equality(result, { 3 })
end

T["requeues work arriving during a flush without losing the final state"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
        local latest = 1
        local rendered = {}
        local scheduler = require("scrollbar.scheduler")

        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    update = { interval_ms = 5 },
                },
            }),
            renderer = {
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function()
                    return false
                end,
                render = function()
                    table.insert(rendered, latest)
                    if #rendered == 1 then
                        latest = 2
                        scheduler.invalidate_window(winid)
                    end
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        scheduler.invalidate_window(winid)
        assert(vim.wait(1000, function()
            return #rendered == 2
        end))
        vim.wait(30)
        scheduler.dispose()
        return rendered
    end)

    expect.equality(result, { 1, 2 })
end

T["subscribes only to mark store events and unsubscribes on dispose"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local winid = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two" })

        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function(target_buf)
                    if target_buf == nil or target_buf == bufnr then
                        return { winid }
                    end
                    return {}
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
                is_buffer_eligible = function(target_buf)
                    return target_buf == bufnr
                end,
                is_owned_buffer = function()
                    return false
                end,
                is_owned_window = function()
                    return false
                end,
                render = function() end,
            },
        })

        local buffer_invalidations = {}
        local window_invalidations = {}
        local original_invalidate_buffer = scheduler.invalidate_buffer
        local original_invalidate_window = scheduler.invalidate_window
        rawset(scheduler, "invalidate_buffer", function(target_buf)
            table.insert(buffer_invalidations, target_buf)
            return original_invalidate_buffer(target_buf)
        end)
        rawset(scheduler, "invalidate_window", function(source_win)
            table.insert(window_invalidations, source_win)
            return original_invalidate_window(source_win)
        end)

        local store = require("scrollbar.store")
        local providers = require("scrollbar.providers")
        providers.register({ name = "marks" })
        providers.register({ name = "window-marks" })
        providers.register({ name = "minimap-only-event", targets = { minimap = true } })
        store.set_minimap_spans("semantic", bufnr, {
            { line = 0, start_col = 0, end_col = 1, highlight = "Comment", priority = 1 },
        })
        store.set_minimap_points("point", winid, {
            { line = 0, col = 0, highlight = "Cursor", priority = 1 },
        })
        local after_minimap = {
            buffer = vim.deepcopy(buffer_invalidations),
            window = vim.deepcopy(window_invalidations),
            dirty = scheduler.status().dirty_windows,
        }

        store.set("marks", bufnr, { { line = 0, type = "Misc" } })
        store.set_window("window-marks", winid, { { line = 1, type = "Misc" } })
        store.set("minimap-only-event", bufnr, { { line = 0, type = "Misc" } })
        local after_marks = {
            buffer = vim.deepcopy(buffer_invalidations),
            window = vim.deepcopy(window_invalidations),
            dirty = scheduler.status().dirty_windows,
        }

        scheduler.dispose()
        store.set("marks", bufnr, { { line = 1, type = "Misc" } })
        store.set_window("window-marks", winid, { { line = 0, type = "Misc" } })
        return {
            after_minimap = after_minimap,
            after_marks = after_marks,
            after_dispose = {
                buffer = buffer_invalidations,
                window = window_invalidations,
            },
            winid = winid,
            bufnr = bufnr,
        }
    end)

    expect.equality(result.after_minimap, { buffer = {}, window = {}, dirty = {} })
    expect.equality(result.after_marks, {
        buffer = { result.bufnr },
        window = { result.winid },
        dirty = { result.winid },
    })
    expect.equality(result.after_dispose, {
        buffer = { result.bufnr },
        window = { result.winid },
    })
end

T["uses one source-window snapshot to validate every pending window in a flush"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        local third = vim.api.nvim_get_current_win()
        local sources = { first, second, third }
        local enumerations = 0
        local rendered = {}
        local scheduler = require("scrollbar.scheduler")

        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function()
                    enumerations = enumerations + 1
                    return sources
                end,
                is_source_window = function(winid)
                    return vim.tbl_contains(sources, winid)
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function()
                    return false
                end,
                render = function(winid)
                    table.insert(rendered, winid)
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        scheduler.invalidate_all()
        enumerations = 0
        scheduler.flush()
        scheduler.dispose()
        return {
            enumerations = enumerations,
            rendered = rendered,
            sources = sources,
        }
    end)

    table.sort(result.sources)
    expect.equality(result.enumerations, 1)
    expect.equality(result.rendered, result.sources)
end

T["delegates targeted membership and owned-buffer events to renderer policy"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local source = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local other = vim.api.nvim_get_current_win()
        local membership_calls = {}
        local enumerations = 0
        local owned_buffer_calls = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function()
                    enumerations = enumerations + 1
                    return { source }
                end,
                is_source_window = function(winid)
                    table.insert(membership_calls, winid)
                    return winid == source
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function(bufnr)
                    table.insert(owned_buffer_calls, bufnr)
                    return bufnr == vim.api.nvim_get_current_buf()
                end,
                is_owned_window = function()
                    return false
                end,
                render = function() end,
            },
        })

        local source_accepted = scheduler.invalidate_window(source)
        local other_accepted = scheduler.invalidate_window(other)
        local enumerations_before_flush = enumerations
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = vim.api.nvim_get_current_buf() })
        local dirty_after_owned_event = vim.deepcopy(scheduler.status().dirty_windows)
        scheduler.flush()
        scheduler.dispose()
        return {
            source = source,
            other = other,
            source_accepted = source_accepted,
            other_accepted = other_accepted,
            membership_calls = membership_calls,
            enumerations_before_flush = enumerations_before_flush,
            enumerations = enumerations,
            owned_buffer_calls = owned_buffer_calls,
            dirty_after_owned_event = dirty_after_owned_event,
        }
    end)

    expect.equality(result.source_accepted, true)
    expect.equality(result.other_accepted, false)
    expect.equality(result.membership_calls, { result.source, result.other })
    expect.equality(result.enumerations_before_flush, 0)
    expect.equality(result.enumerations, 2)
    expect.equality(#result.owned_buffer_calls > 0, true)
    expect.equality(result.dirty_after_owned_event, { result.source })
end

T["ignores closed and floating windows and scopes buffer invalidation"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        local first_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(first_buf, 0, -1, false, { "first" })

        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local second_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(second_buf, 0, -1, false, { "second" })
        vim.api.nvim_win_set_buf(second, second_buf)

        vim.cmd("split")
        local closed = vim.api.nvim_get_current_win()
        vim.api.nvim_win_close(closed, true)

        local float_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_var(float_buf, "scrollbar_owned", true)
        local float_win = vim.api.nvim_open_win(float_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 1,
            height = 1,
            style = "minimal",
        })
        vim.api.nvim_win_set_var(float_win, "scrollbar_owned", true)

        local active_config = require("scrollbar.config").set({
            scrollbar = {
                set_highlights = false,
                update = { interval_ms = 1000 },
                mouse = { enabled = false },
                excluded_buftypes = {},
                excluded_filetypes = {},
            },
        })
        local renderer = require("scrollbar.renderer")
        local rendered = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = active_config,
            renderer = {
                source_windows = renderer.source_windows,
                is_source_window = renderer.is_source_window,
                is_buffer_eligible = renderer.is_buffer_eligible,
                is_owned_buffer = renderer.is_owned_buffer,
                is_owned_window = renderer.is_owned_window,
                render = function(winid)
                    table.insert(rendered, winid)
                end,
            },
        })

        local buffer_count = scheduler.invalidate_buffer(first_buf)
        local closed_accepted = scheduler.invalidate_window(closed)
        local float_accepted = scheduler.invalidate_window(float_win)
        scheduler.flush()
        local status = scheduler.status()
        scheduler.dispose()
        vim.api.nvim_win_close(float_win, true)

        return {
            first = first,
            second = second,
            rendered = rendered,
            buffer_count = buffer_count,
            closed_accepted = closed_accepted,
            float_accepted = float_accepted,
            dirty = status.dirty_windows,
        }
    end)

    expect.equality(result.rendered, { result.first })
    expect.equality(result.buffer_count, 1)
    expect.equality(result.closed_accepted, false)
    expect.equality(result.float_accepted, false)
    expect.equality(result.dirty, {})
    expect.no_equality(result.first, result.second)
end

T["reveals only navigation sources and keeps other invalidations render-only"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        local first_buf = vim.api.nvim_get_current_buf()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local second_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(second, second_buf)
        local float_buf = vim.api.nvim_create_buf(false, true)
        local float_win = vim.api.nvim_open_win(float_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 1,
            height = 1,
            style = "minimal",
        })

        local rendered = {}
        local revealed = {}
        local concealed = {}
        local visible = true
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    autohide = { enabled = true, delay_ms = 1000 },
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function(bufnr)
                    if bufnr == first_buf then
                        return { first }
                    end
                    if bufnr == second_buf then
                        return { second }
                    end
                    return bufnr == nil and { first, second } or {}
                end,
                is_source_window = function(winid)
                    return winid == first or winid == second
                end,
                is_buffer_eligible = function(bufnr)
                    return bufnr == first_buf or bufnr == second_buf
                end,
                is_owned_buffer = function(bufnr)
                    return bufnr == float_buf
                end,
                reveal = function(winid)
                    table.insert(revealed, winid)
                    return true
                end,
                conceal = function(winid)
                    table.insert(concealed, winid)
                    return true
                end,
                render = function(winid)
                    table.insert(rendered, winid)
                end,
                is_visible = function()
                    return visible
                end,
                is_owned_window = function(winid)
                    return winid == float_win
                end,
            },
        })

        vim.api.nvim_set_current_win(first)
        scheduler.flush()
        rendered = {}
        revealed = {}
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = first_buf })
        scheduler.invalidate_window(first)
        scheduler.flush()
        local cursor_revealed = vim.deepcopy(revealed)
        local cursor_rendered = vim.deepcopy(rendered)

        revealed = {}
        rendered = {}
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = first_buf })
        scheduler.flush()
        local text_revealed = vim.deepcopy(revealed)
        local text_rendered = vim.deepcopy(rendered)

        revealed = {}
        rendered = {}
        local original_v = vim.v
        rawset(vim, "v", { event = { all = true } })
        vim.api.nvim_exec_autocmds("WinScrolled", {})
        rawset(vim, "v", original_v)
        scheduler.flush()
        local all_revealed = vim.deepcopy(revealed)
        local all_rendered = vim.deepcopy(rendered)

        revealed = {}
        vim.api.nvim_set_current_win(float_win)
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = float_buf })
        local owned_revealed = vim.deepcopy(revealed)
        vim.api.nvim_set_current_win(first)

        visible = false
        revealed = {}
        vim.api.nvim_exec_autocmds("CursorMovedI", { buffer = first_buf })
        scheduler.flush()
        local hidden_revealed = vim.deepcopy(revealed)
        scheduler.dispose()
        vim.api.nvim_win_close(float_win, true)

        return {
            first = first,
            second = second,
            cursor_revealed = cursor_revealed,
            cursor_rendered = cursor_rendered,
            text_revealed = text_revealed,
            text_rendered = text_rendered,
            all_revealed = all_revealed,
            all_rendered = all_rendered,
            owned_revealed = owned_revealed,
            hidden_revealed = hidden_revealed,
            concealed = concealed,
        }
    end)

    expect.equality(result.cursor_revealed, { result.first })
    expect.equality(result.cursor_rendered, { result.first })
    expect.equality(result.text_revealed, {})
    expect.equality(result.text_rendered, { result.first })
    expect.equality(result.all_revealed, { result.first, result.second })
    expect.equality(result.all_rendered, { result.first, result.second })
    expect.equality(result.owned_revealed, {})
    expect.equality(result.hidden_revealed, {})
    expect.equality(result.concealed, {})
end

T["keeps independent deadlines and rejects stale callbacks"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local timers = {}
        local uv = vim.uv or vim.loop
        local original_new_timer = uv.new_timer
        uv.new_timer = function()
            local timer = { closed = false, starts = 0 }
            function timer:start(timeout, _, callback)
                self.timeout = timeout
                self.callback = callback
                self.starts = self.starts + 1
            end
            function timer:stop()
                self.stopped = true
            end
            function timer:close()
                self.closed = true
            end
            function timer:is_closing()
                return self.closed
            end
            table.insert(timers, timer)
            return timer
        end

        local concealed = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    autohide = { enabled = true, delay_ms = 50 },
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function()
                    return { first, second }
                end,
                is_source_window = function(winid)
                    return winid == first or winid == second
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function()
                    return false
                end,
                reveal = function()
                    return true
                end,
                conceal = function(winid)
                    table.insert(concealed, winid)
                    return true
                end,
                render = function() end,
                is_visible = function()
                    return true
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        vim.api.nvim_set_current_win(first)
        vim.api.nvim_exec_autocmds("CursorMoved", {})
        local first_timer = assert(timers[2], "first source timer was not created")
        local stale_callback = first_timer.callback

        vim.api.nvim_set_current_win(second)
        vim.api.nvim_exec_autocmds("CursorMoved", {})
        local second_timer = assert(timers[3], "second source timer was not created")

        vim.api.nvim_set_current_win(first)
        vim.api.nvim_exec_autocmds("CursorMoved", {})
        local latest_callback = first_timer.callback
        stale_callback()
        vim.wait(20)
        local after_stale = vim.deepcopy(concealed)

        second_timer.callback()
        assert(vim.wait(100, function()
            return #concealed == 1
        end))
        local after_second = vim.deepcopy(concealed)

        latest_callback()
        assert(vim.wait(100, function()
            return #concealed == 2
        end))
        scheduler.dispose()
        uv.new_timer = original_new_timer

        return {
            first = first,
            second = second,
            after_stale = after_stale,
            after_second = after_second,
            final = concealed,
            first_starts = first_timer.starts,
        }
    end)

    expect.equality(result.after_stale, {})
    expect.equality(result.after_second, { result.second })
    expect.equality(result.final, { result.second, result.first })
    expect.equality(result.first_starts, 2)
end

T["holds deadlines and closes source timers with their lifecycle"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local timers = {}
        local uv = vim.uv or vim.loop
        local original_new_timer = uv.new_timer
        uv.new_timer = function()
            local timer = { closed = false, starts = 0 }
            function timer:start(_, _, callback)
                self.callback = callback
                self.starts = self.starts + 1
            end
            function timer:stop()
                self.stopped = true
            end
            function timer:close()
                self.closed = true
            end
            function timer:is_closing()
                return self.closed
            end
            table.insert(timers, timer)
            return timer
        end

        local concealed = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    autohide = { enabled = true, delay_ms = 50 },
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function()
                    local windows = {}
                    for _, winid in ipairs({ first, second }) do
                        if vim.api.nvim_win_is_valid(winid) then
                            table.insert(windows, winid)
                        end
                    end
                    return windows
                end,
                is_source_window = function(winid)
                    return winid == first or winid == second
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function()
                    return false
                end,
                reveal = function()
                    return true
                end,
                conceal = function(winid)
                    table.insert(concealed, winid)
                    return true
                end,
                render = function() end,
                is_visible = function()
                    return true
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        vim.api.nvim_set_current_win(first)
        vim.api.nvim_exec_autocmds("CursorMoved", {})
        local first_timer = assert(timers[2], "first source timer was not created")
        local before_hold = first_timer.callback
        assert(scheduler.hold_window(first))
        before_hold()
        vim.wait(20)
        local held_concealed = vim.deepcopy(concealed)

        vim.api.nvim_exec_autocmds("CursorMovedI", {})
        local starts_while_held = first_timer.starts
        assert(scheduler.resume_window(first))
        first_timer.callback()
        assert(vim.wait(100, function()
            return #concealed == 1
        end))

        vim.api.nvim_win_close(first, true)
        local source_timer_closed = first_timer.closed
        vim.api.nvim_set_current_win(second)
        vim.api.nvim_exec_autocmds("CursorMoved", {})
        local second_timer = assert(timers[3], "second source timer was not created")
        scheduler.dispose()
        local render_timer_closed = timers[1].closed
        local second_timer_closed = second_timer.closed
        uv.new_timer = original_new_timer

        return {
            first = first,
            held_concealed = held_concealed,
            final_concealed = concealed,
            starts_while_held = starts_while_held,
            final_starts = first_timer.starts,
            source_timer_closed = source_timer_closed,
            render_timer_closed = render_timer_closed,
            second_timer_closed = second_timer_closed,
        }
    end)

    expect.equality(result.held_concealed, {})
    expect.equality(result.final_concealed, { result.first })
    expect.equality(result.starts_while_held, 1)
    expect.equality(result.final_starts, 2)
    expect.equality(result.source_timer_closed, true)
    expect.equality(result.render_timer_closed, true)
    expect.equality(result.second_timer_closed, true)
end

T["wires provider context invalidations directly and never refreshes providers on scroll"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local active_config = require("scrollbar.config").set({
            scrollbar = {
                set_highlights = false,
                update = { interval_ms = 5 },
                providers = {
                    cursor = false,
                    diagnostic = false,
                    search = false,
                    gitsigns = false,
                    ale = false,
                    coc = false,
                },
            },
        })
        local winid = vim.api.nvim_get_current_win()
        local bufnr = vim.api.nvim_get_current_buf()
        local rendered = {}
        local refreshes = 0
        local context
        local scheduler = require("scrollbar.scheduler")
        local renderer = {
            source_windows = function(target_buf)
                if target_buf == nil or target_buf == bufnr then
                    return { winid }
                end
                return {}
            end,
            is_source_window = function(source_win)
                return source_win == winid
            end,
            is_buffer_eligible = function(target_buf)
                return target_buf == bufnr
            end,
            is_owned_buffer = function()
                return false
            end,
            render = function(source_win)
                table.insert(rendered, source_win)
            end,
            is_owned_window = function()
                return false
            end,
        }
        scheduler.setup({ config = active_config, renderer = renderer })

        local providers = require("scrollbar.providers")
        providers.register({
            name = "scheduler-test",
            refresh_owner = { buffer = "provider" },
            setup = function(provider_context)
                context = provider_context
            end,
            refresh = function()
                refreshes = refreshes + 1
                return {}
            end,
        })
        providers.setup({
            config = active_config,
            invalidate_buffer = scheduler.invalidate_buffer,
            invalidate_window = scheduler.invalidate_window,
            source_windows = renderer.source_windows,
            is_source_window = renderer.is_source_window,
            is_buffer_eligible = function(target_buf)
                return target_buf == bufnr
            end,
        })
        assert(vim.wait(1000, function()
            return #rendered == 1
        end))

        rendered = {}
        refreshes = 0
        context.invalidate_buffer(bufnr)
        context.invalidate_window(winid)
        assert(vim.wait(1000, function()
            return #rendered == 1
        end))
        local direct_renders = vim.deepcopy(rendered)

        rendered = {}
        vim.api.nvim_exec_autocmds("WinScrolled", {})
        assert(vim.wait(1000, function()
            return #rendered == 1
        end))
        local scroll_renders = vim.deepcopy(rendered)

        rendered = {}
        vim.o.showtabline = vim.o.showtabline == 2 and 1 or 2
        assert(vim.wait(1000, function()
            return #rendered == 1
        end))
        local option_renders = vim.deepcopy(rendered)

        providers.dispose()
        scheduler.dispose()
        return {
            direct_renders = direct_renders,
            scroll_renders = scroll_renders,
            option_renders = option_renders,
            refreshes = refreshes,
        }
    end)

    expect.equality(result.direct_renders, result.scroll_renders)
    expect.equality(result.direct_renders, result.option_renders)
    expect.equality(#result.direct_renders, 1)
    expect.equality(result.refreshes, 0)
end

T["honors editor-relative active ownership through renderer source windows"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()

        local active_config = require("scrollbar.config").set({
            scrollbar = {
                visibility = "all",
                set_highlights = false,
                update = { interval_ms = 1000 },
                float = { placement = { relative = "editor" } },
                mouse = { enabled = false },
            },
        })
        local real_renderer = require("scrollbar.renderer")
        local rendered = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = active_config,
            renderer = {
                source_windows = real_renderer.source_windows,
                is_source_window = real_renderer.is_source_window,
                is_buffer_eligible = real_renderer.is_buffer_eligible,
                is_owned_buffer = real_renderer.is_owned_buffer,
                is_owned_window = real_renderer.is_owned_window,
                render = function(winid)
                    table.insert(rendered, winid)
                end,
            },
        })

        scheduler.invalidate_all()
        scheduler.flush()
        local initial = vim.deepcopy(rendered)
        rendered = {}

        local inactive_accepted = scheduler.invalidate_window(first)
        vim.api.nvim_set_current_win(first)
        scheduler.flush()
        local after_enter = vim.deepcopy(rendered)
        scheduler.dispose()

        return {
            first = first,
            second = second,
            initial = initial,
            inactive_accepted = inactive_accepted,
            after_enter = after_enter,
        }
    end)

    expect.equality(result.initial, { result.second })
    expect.equality(result.inactive_accepted, false)
    expect.equality(result.after_enter, { result.first })
end

T["does not requeue from renderer-owned float autocmds"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local active_config = require("scrollbar.config").set({
            scrollbar = {
                set_highlights = false,
                update = { interval_ms = 5 },
                float = { placement = { anchor = "NW" } },
                mouse = { enabled = false },
                excluded_buftypes = {},
                excluded_filetypes = {},
            },
        })
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local renders = 0
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = active_config,
            renderer = {
                source_windows = renderer.source_windows,
                is_source_window = renderer.is_source_window,
                is_buffer_eligible = renderer.is_buffer_eligible,
                is_owned_buffer = renderer.is_owned_buffer,
                is_owned_window = renderer.is_owned_window,
                render = function(winid)
                    renders = renders + 1
                    renderer.render(winid)
                end,
            },
        })

        scheduler.invalidate_all()
        assert(vim.wait(1000, function()
            return renders == 1 and renderer.get_state(vim.api.nvim_get_current_win()) ~= nil
        end))
        vim.wait(50)
        local status = scheduler.status()
        scheduler.dispose()
        renderer.dispose()
        return {
            renders = renders,
            timer_active = status.timer_active,
            dirty = status.dirty_windows,
        }
    end)

    expect.equality(result, {
        renders = 1,
        timer_active = false,
        dirty = {},
    })
end

T["reconciles dynamic source-policy transitions through scheduler enumeration"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local presets = require("scrollbar.presets")
        local config = require("scrollbar.config")
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        local source_win = vim.api.nvim_get_current_win()
        local source_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, { "one", "two", "three" })

        local function start(overrides)
            scheduler.dispose()
            renderer.dispose()
            local active = config.set({
                scrollbar = presets.merge({
                    show = true,
                    set_highlights = false,
                    update = { interval_ms = 1000 },
                    mouse = { enabled = false },
                    thumb = { hide_if_all_visible = false },
                    excluded_buftypes = {},
                    excluded_filetypes = {},
                }, overrides or {}),
            })
            renderer.setup()
            scheduler.setup({ config = active, renderer = renderer })
            scheduler.invalidate_all()
            scheduler.flush()
        end

        local function closed(state)
            return renderer.get_state(state.source_win) == nil
                and not vim.api.nvim_win_is_valid(state.float_win)
                and not vim.api.nvim_buf_is_valid(state.float_buf)
        end

        vim.api.nvim_set_current_win(source_win)
        start({ excluded_filetypes = { "blocked" } })
        local filetype_state = assert(renderer.get_state(source_win))
        vim.bo[source_buf].filetype = "blocked"
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = source_buf })
        scheduler.flush()
        local filetype_closed = closed(filetype_state)
        vim.bo[source_buf].filetype = ""

        start({ max_lines = 3 })
        local max_lines_state = assert(renderer.get_state(source_win))
        vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "four" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = source_buf })
        scheduler.flush()
        local max_lines_closed = closed(max_lines_state)
        vim.api.nvim_buf_set_lines(source_buf, 3, -1, false, {})

        start()
        local owned_state = assert(renderer.get_state(source_win))
        local owned_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_var(owned_buf, "scrollbar_owned", true)
        vim.api.nvim_win_set_buf(source_win, owned_buf)
        vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = owned_buf })
        scheduler.flush()
        local owned_closed = closed(owned_state)
        vim.api.nvim_win_set_buf(source_win, source_buf)
        vim.api.nvim_set_current_win(source_win)

        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        start({ float = { placement = { relative = "editor" } } })
        local editor_state = assert(renderer.get_state(second))
        vim.api.nvim_set_current_win(source_win)
        vim.api.nvim_exec_autocmds("WinEnter", { buffer = source_buf })
        local editor_closed = closed(editor_state)
        vim.api.nvim_win_close(second, true)

        vim.api.nvim_set_current_win(source_win)
        start({ visibility = "active" })
        local active_state = assert(renderer.get_state(source_win))
        local user_buf = vim.api.nvim_create_buf(false, true)
        local user_float = vim.api.nvim_open_win(user_buf, true, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 1,
            height = 1,
            style = "minimal",
        })
        vim.api.nvim_exec_autocmds("WinEnter", { buffer = user_buf })
        local user_float_closed = closed(active_state)

        scheduler.dispose()
        renderer.dispose()
        vim.api.nvim_win_close(user_float, true)
        return {
            filetype = filetype_closed,
            max_lines = max_lines_closed,
            owned = owned_closed,
            editor = editor_closed,
            user_float = user_float_closed,
        }
    end)

    expect.equality(result, {
        filetype = true,
        max_lines = true,
        owned = true,
        editor = true,
        user_float = true,
    })
end

T["rerenders every source when editor chrome options change"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local rendered = {}
        local owned = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function()
                    return { first, second }
                end,
                is_source_window = function(winid)
                    return winid == first or winid == second
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function(bufnr)
                    local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, "scrollbar_owned")
                    return ok and value == true
                end,
                render = function(winid)
                    table.insert(rendered, winid)
                end,
                is_owned_window = function(winid)
                    return owned[winid] == true
                end,
            },
        })

        local captures = {}
        local changes = {
            winbar = function()
                vim.api.nvim_set_option_value("winbar", "WINBAR", { win = second })
            end,
            showtabline = function()
                vim.o.showtabline = vim.o.showtabline == 2 and 1 or 2
            end,
            laststatus = function()
                vim.o.laststatus = vim.o.laststatus == 3 and 2 or 3
            end,
            cmdheight = function()
                vim.o.cmdheight = vim.o.cmdheight == 0 and 1 or 0
            end,
            numberwidth = function()
                local value = vim.api.nvim_get_option_value("numberwidth", { win = second })
                vim.api.nvim_set_option_value("numberwidth", value == 4 and 5 or 4, { win = second })
            end,
            statuscolumn = function()
                local value = vim.api.nvim_get_option_value("statuscolumn", { win = second })
                vim.api.nvim_set_option_value("statuscolumn", value == "%l " and "%l  " or "%l ", { win = second })
            end,
        }
        for _, name in ipairs({ "winbar", "showtabline", "laststatus", "cmdheight", "numberwidth", "statuscolumn" }) do
            rendered = {}
            changes[name]()
            scheduler.flush()
            captures[name] = vim.deepcopy(rendered)
        end

        local float_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_var(float_buf, "scrollbar_owned", true)
        local float_win = vim.api.nvim_open_win(float_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 1,
            height = 1,
            style = "minimal",
        })
        vim.api.nvim_win_set_var(float_win, "scrollbar_owned", true)
        owned[float_win] = true
        vim.api.nvim_set_current_win(float_win)
        rendered = {}
        vim.api.nvim_set_option_value("winbar", "FLOAT", { win = float_win })
        local owned_flushed = scheduler.flush()
        local owned_renders = vim.deepcopy(rendered)

        scheduler.dispose()
        vim.api.nvim_win_close(float_win, true)
        return {
            first = first,
            second = second,
            captures = captures,
            owned_flushed = owned_flushed,
            owned_renders = owned_renders,
        }
    end)

    local expected = { result.first, result.second }
    table.sort(expected)
    expect.equality(result.captures.winbar, expected)
    expect.equality(result.captures.showtabline, expected)
    expect.equality(result.captures.laststatus, expected)
    expect.equality(result.captures.cmdheight, expected)
    expect.equality(result.captures.numberwidth, expected)
    expect.equality(result.captures.statuscolumn, expected)
    expect.equality(result.owned_flushed, false)
    expect.equality(result.owned_renders, {})
end

T["refreshes colorscheme state and fully disposes timer and autocmd ownership"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
        local rendered = 0
        local colors = 0
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                scrollbar = {
                    set_highlights = false,
                    update = { interval_ms = 1000 },
                },
            }),
            renderer = {
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
                is_buffer_eligible = function()
                    return true
                end,
                is_owned_buffer = function()
                    return false
                end,
                render = function()
                    rendered = rendered + 1
                end,
                is_owned_window = function()
                    return false
                end,
            },
            on_colorscheme = function()
                colors = colors + 1
            end,
        })

        local active = scheduler.status()
        local autocmds = vim.api.nvim_get_autocmds({ group = active.augroup_id })
        local events = {}
        local option_patterns = {}
        for _, autocmd in ipairs(autocmds) do
            events[autocmd.event] = true
            if autocmd.event == "OptionSet" then
                option_patterns[autocmd.pattern] = true
            end
        end

        scheduler.invalidate_window(winid)
        local queued = scheduler.status()
        vim.api.nvim_exec_autocmds("ColorScheme", {})
        scheduler.flush()
        scheduler.dispose()
        local disposed = scheduler.status()
        local group_exists = pcall(vim.api.nvim_get_autocmds, { group = active.augroup_id })
        vim.api.nvim_exec_autocmds("WinScrolled", {})
        vim.wait(20)

        return {
            winid = winid,
            events = events,
            option_patterns = option_patterns,
            queued = queued,
            disposed = disposed,
            group_exists = group_exists,
            rendered = rendered,
            colors = colors,
        }
    end)

    expect.equality(result.queued.timer_active, true)
    expect.equality(result.queued.dirty_windows, { result.winid })
    expect.equality(result.events.BufEnter, true)
    expect.equality(result.events.BufWinEnter, true)
    expect.equality(result.events.TextChanged, true)
    expect.equality(result.events.CursorMoved, true)
    expect.equality(result.events.CursorMovedI, true)
    expect.equality(result.events.WinEnter, true)
    expect.equality(result.events.WinResized, true)
    expect.equality(result.events.VimResized, true)
    expect.equality(result.events.WinScrolled, true)
    expect.equality(result.events.OptionSet, true)
    expect.equality(result.events.ColorScheme, true)
    expect.equality(result.events.WinClosed, true)
    expect.equality(result.events.BufWipeout, true)
    expect.equality(result.option_patterns.foldcolumn, true)
    expect.equality(result.option_patterns.foldmethod, true)
    expect.equality(result.option_patterns.number, true)
    expect.equality(result.option_patterns.numberwidth, true)
    expect.equality(result.option_patterns.relativenumber, true)
    expect.equality(result.option_patterns.signcolumn, true)
    expect.equality(result.option_patterns.statuscolumn, true)
    expect.equality(result.option_patterns.wrap, true)
    expect.equality(result.rendered, 1)
    expect.equality(result.colors, 1)
    expect.equality(result.disposed.setup, false)
    expect.equality(result.disposed.timer_active, false)
    expect.equality(result.disposed.timer_closed, true)
    expect.equality(result.disposed.dirty_windows, {})
    expect.equality(result.disposed.augroup_id, nil)
    expect.equality(result.group_exists, false)
end

T["OPTION_PATTERNS list matches the mirrored copy in layout.lua"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        -- OPTION_PATTERNS is a module-local in both scheduler.lua and
        -- layout.lua (mirrored deliberately to avoid scheduler -> layout
        -- requiring layout from scheduler; see comment at layout.lua:76-79).
        -- The local is not directly reachable from any exported function, so
        -- walk the upvalue graph of every exported closure until we find it.
        local function find_upvalue_named(module, target)
            local seen = {}
            local queue = {}
            for _, value in pairs(module) do
                if type(value) == "function" and not seen[value] then
                    seen[value] = true
                    table.insert(queue, value)
                end
            end

            while #queue > 0 do
                local fn = table.remove(queue, 1)
                local index = 1
                while true do
                    local ok, name, value = pcall(debug.getupvalue, fn, index)
                    if not ok or name == nil then
                        break
                    end
                    if name == target then
                        return value
                    end
                    if type(value) == "function" and not seen[value] then
                        seen[value] = true
                        table.insert(queue, value)
                    end
                    index = index + 1
                end
            end
            return nil
        end

        local scheduler_patterns = find_upvalue_named(require("scrollbar.scheduler"), "OPTION_PATTERNS")
        local layout_patterns = find_upvalue_named(require("scrollbar.layout"), "EXTENT_OPTION_PATTERNS")

        local scheduler_set = {}
        for _, name in ipairs(scheduler_patterns or {}) do
            scheduler_set[name] = true
        end
        local missing_in_scheduler = {}
        for _, name in ipairs(layout_patterns or {}) do
            if not scheduler_set[name] then
                missing_in_scheduler[#missing_in_scheduler + 1] = name
            end
        end

        return {
            scheduler = scheduler_patterns,
            layout = layout_patterns,
            layout_covered = next(missing_in_scheduler) == nil,
        }
    end)

    expect.equality(#result.scheduler > 0, true)
    expect.equality(#result.layout > 0, true)
    -- The scheduler autocmd patterns must stay a superset of the layout
    -- extent-option subset so every extent-affecting change schedules a render.
    expect.equality(result.layout_covered, true)
end

T["default update events register the complete autocmd set"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local config = require("scrollbar.config").set({ scrollbar = {} })
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = config,
            renderer = {
                source_windows = function()
                    return {}
                end,
                is_source_window = function()
                    return false
                end,
                is_buffer_eligible = function()
                    return false
                end,
                is_owned_buffer = function()
                    return false
                end,
                is_owned_window = function()
                    return false
                end,
                render = function() end,
            },
        })
        local augroup_id = scheduler.status().augroup_id
        local autocmds = vim.api.nvim_get_autocmds({ group = augroup_id })
        local event_set = {}
        for _, autocmd in ipairs(autocmds) do
            local events = autocmd.event or {}
            if type(events) == "string" then
                events = { events }
            end
            for _, event in ipairs(events) do
                event_set[event] = true
            end
        end
        scheduler.dispose()

        local expected = {
            "BufEnter",
            "BufWinEnter",
            "WinEnter",
            "TabEnter",
            "TermEnter",
            "CmdwinLeave",
            "CursorMoved",
            "CursorMovedI",
            "TextChanged",
            "TextChangedI",
            "TextChangedP",
            "TextChangedT",
            "WinScrolled",
            "WinResized",
            "VimResized",
            "OptionSet",
            "ColorScheme",
            "WinClosed",
            "BufDelete",
            "BufWipeout",
            "TabClosed",
        }
        local missing = {}
        for _, event in ipairs(expected) do
            if not event_set[event] then
                missing[#missing + 1] = event
            end
        end
        return {
            missing = missing,
            event_count = vim.tbl_count(event_set),
            expected_count = #expected,
        }
    end)

    expect.equality(result.missing, {})
    expect.equality(result.event_count, result.expected_count)
end

T["narrower update events list registers fewer autocmds"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local scheduler = require("scrollbar.scheduler")

        local function count_events(events)
            local config = require("scrollbar.config").set({
                scrollbar = { update = { events = events } },
            })
            scheduler.setup({
                config = config,
                renderer = {
                    source_windows = function()
                        return {}
                    end,
                    is_source_window = function()
                        return false
                    end,
                    is_buffer_eligible = function()
                        return false
                    end,
                    is_owned_buffer = function()
                        return false
                    end,
                    is_owned_window = function()
                        return false
                    end,
                    render = function() end,
                },
            })
            local augroup_id = scheduler.status().augroup_id
            local autocmds = vim.api.nvim_get_autocmds({ group = augroup_id })
            local event_set = {}
            for _, autocmd in ipairs(autocmds) do
                local ev = autocmd.event or {}
                if type(ev) == "string" then
                    ev = { ev }
                end
                for _, event in ipairs(ev) do
                    event_set[event] = true
                end
            end
            scheduler.dispose()
            return vim.tbl_count(event_set)
        end

        local default_count = count_events({
            "BufEnter",
            "BufWinEnter",
            "WinEnter",
            "TabEnter",
            "TermEnter",
            "CmdwinLeave",
            "CursorMoved",
            "CursorMovedI",
            "TextChanged",
            "TextChangedI",
            "TextChangedP",
            "TextChangedT",
            "WinScrolled",
            "WinResized",
            "VimResized",
            "OptionSet",
            "ColorScheme",
            "WinClosed",
            "BufDelete",
            "BufWipeout",
            "TabClosed",
        })
        local narrow_count = count_events({ "BufEnter", "CursorMoved", "WinScrolled" })

        return {
            default_count = default_count,
            narrow_count = narrow_count,
        }
    end)

    expect.equality(result.default_count, 21)
    expect.equality(result.narrow_count, 3)
    expect.equality(result.narrow_count < result.default_count, true)
end

return T
