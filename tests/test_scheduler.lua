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
                set_highlights = false,
                render = { interval_ms = 10 },
            }),
            renderer = {
                source_windows = function()
                    return { winid }
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
                set_highlights = false,
                render = { interval_ms = 5 },
            }),
            renderer = {
                source_windows = function()
                    return { winid }
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
            set_highlights = false,
            render = { interval_ms = 1000 },
            mouse = { enabled = false },
            excluded_buftypes = {},
            excluded_filetypes = {},
        })
        local renderer = require("scrollbar.renderer")
        local rendered = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = active_config,
            renderer = {
                source_windows = renderer.source_windows,
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

T["wires provider context invalidations directly and never refreshes providers on scroll"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local active_config = require("scrollbar.config").set({
            set_highlights = false,
            render = { interval_ms = 5 },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                gitsigns = false,
                ale = false,
                coc = false,
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

        providers.dispose()
        scheduler.dispose()
        return {
            direct_renders = direct_renders,
            scroll_renders = scroll_renders,
            refreshes = refreshes,
        }
    end)

    expect.equality(result.direct_renders, result.scroll_renders)
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
            visibility = "all",
            set_highlights = false,
            render = { interval_ms = 1000 },
            float = { placement = { relative = "editor" } },
            mouse = { enabled = false },
        })
        local real_renderer = require("scrollbar.renderer")
        local rendered = {}
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = active_config,
            renderer = {
                source_windows = real_renderer.source_windows,
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
            set_highlights = false,
            render = { interval_ms = 5 },
            mouse = { enabled = false },
            excluded_buftypes = {},
            excluded_filetypes = {},
        })
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local renders = 0
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = active_config,
            renderer = {
                source_windows = renderer.source_windows,
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

T["refreshes colorscheme state and fully disposes timer and autocmd ownership"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
        local rendered = 0
        local colors = 0
        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({
            config = require("scrollbar.config").set({
                set_highlights = false,
                render = { interval_ms = 1000 },
            }),
            renderer = {
                source_windows = function()
                    return { winid }
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
    expect.equality(result.events.WinResized, true)
    expect.equality(result.events.VimResized, true)
    expect.equality(result.events.WinScrolled, true)
    expect.equality(result.events.OptionSet, true)
    expect.equality(result.events.ColorScheme, true)
    expect.equality(result.events.WinClosed, true)
    expect.equality(result.events.BufWipeout, true)
    expect.equality(result.option_patterns.wrap, true)
    expect.equality(result.option_patterns.foldmethod, true)
    expect.equality(result.rendered, 1)
    expect.equality(result.colors, 1)
    expect.equality(result.disposed.setup, false)
    expect.equality(result.disposed.timer_active, false)
    expect.equality(result.disposed.timer_closed, true)
    expect.equality(result.disposed.dirty_windows, {})
    expect.equality(result.disposed.augroup_id, nil)
    expect.equality(result.group_exists, false)
end

return T
