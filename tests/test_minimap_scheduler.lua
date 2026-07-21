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

local function reset_config(child)
    child.lua([[
        package.loaded["scrollbar.minimap.config"] = nil
        package.loaded["scrollbar.minimap.scheduler"] = nil
        require("scrollbar.config").set({ scrollbar = {} })
        require("scrollbar.minimap.config").set({})
    ]])
end

T["setup registers an independent augroup and dispose tears it down"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").get(),
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
        local group_name = vim.api.nvim_get_autocmds({ group = augroup_id })[1].group_name
        scheduler.dispose()
        local group_exists = pcall(vim.api.nvim_get_autocmds, { group = augroup_id })
        return {
            augroup_id = augroup_id,
            group_name = group_name,
            group_exists_after_dispose = group_exists,
            timer_closed = scheduler.status().timer_closed,
        }
    end)

    expect.equality(result.group_name, "ScrollbarMinimapScheduler")
    expect.no_equality(result.augroup_id, nil)
    expect.equality(result.group_exists_after_dispose, false)
    expect.equality(result.timer_closed, true)
end

T["coalesces repeated invalidations and renders the latest state"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
        local latest = 0
        local rendered = {}
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({ update = { interval_ms = 10 } }),
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
    reset_config(child)
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
        local latest = 1
        local rendered = {}
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({ update = { interval_ms = 5 } }),
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

T["routes mark span and point store events and unsubscribes on dispose"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local bufnr = vim.api.nvim_get_current_buf()
        local winid = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two" })

        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({ update = { interval_ms = 1000 } }),
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
        providers.register({ name = "marks", targets = { minimap = true } })
        providers.register({ name = "semantic", targets = { minimap = true } })
        providers.register({ name = "window-marks", targets = { minimap = true } })
        providers.register({ name = "point", targets = { minimap = true } })
        providers.register({ name = "scrollbar-only-event" })
        store.set("marks", bufnr, { { line = 0, type = "Misc" } })
        store.set_minimap_spans("semantic", bufnr, {
            { line = 0, start_col = 0, end_col = 1, highlight = "Comment", priority = 1 },
        })
        store.set_window("window-marks", winid, { { line = 1, type = "Misc" } })
        store.set_minimap_points("point", winid, {
            { line = 0, col = 0, highlight = "Cursor", priority = 1 },
        })
        store.set("scrollbar-only-event", bufnr, { { line = 0, type = "Misc" } })
        local before_dispose = {
            buffer = vim.deepcopy(buffer_invalidations),
            window = vim.deepcopy(window_invalidations),
            dirty = scheduler.status().dirty_windows,
        }

        scheduler.dispose()
        store.set("marks", bufnr, { { line = 1, type = "Misc" } })
        store.set_minimap_spans("semantic", bufnr, {
            { line = 1, start_col = 0, end_col = 1, highlight = "Comment", priority = 1 },
        })
        store.set_window("window-marks", winid, { { line = 0, type = "Misc" } })
        store.set_minimap_points("point", winid, {
            { line = 1, col = 0, highlight = "Cursor", priority = 1 },
        })
        return {
            before_dispose = before_dispose,
            after_dispose = {
                buffer = buffer_invalidations,
                window = window_invalidations,
            },
            winid = winid,
            bufnr = bufnr,
        }
    end)

    expect.equality(result.before_dispose, {
        buffer = { result.bufnr, result.bufnr },
        window = { result.winid, result.winid },
        dirty = { result.winid },
    })
    expect.equality(result.after_dispose, {
        buffer = { result.bufnr, result.bufnr },
        window = { result.winid, result.winid },
    })
end

T["store publications invalidate matching buffer windows and only the published window"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local shared_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(shared_buf, 0, -1, false, { "one", "two" })
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.cmd("vnew")
        local other = vim.api.nvim_get_current_win()
        local other_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(other_buf, 0, -1, false, { "other" })

        local sources = { first, second, other }
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({ update = { interval_ms = 1000 } }),
            renderer = {
                source_windows = function(bufnr)
                    if bufnr == nil then
                        return sources
                    end
                    local matching = {}
                    for _, winid in ipairs(sources) do
                        if vim.api.nvim_win_get_buf(winid) == bufnr then
                            matching[#matching + 1] = winid
                        end
                    end
                    return matching
                end,
                is_source_window = function(winid)
                    return vim.tbl_contains(sources, winid)
                end,
                is_buffer_eligible = function(bufnr)
                    return bufnr == shared_buf or bufnr == other_buf
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

        local store = require("scrollbar.store")
        require("scrollbar.providers").register({ name = "diagnostic", targets = { minimap = true } })
        store.set("diagnostic", shared_buf, { { line = 0, type = "Misc" } })
        local after_buffer = scheduler.status().dirty_windows
        scheduler.flush()

        store.set_window("diagnostic", first, { { line = 1, type = "Misc" } })
        local after_window = scheduler.status().dirty_windows
        scheduler.dispose()
        return {
            first = first,
            second = second,
            other = other,
            after_buffer = after_buffer,
            after_window = after_window,
        }
    end)

    local expected_buffer = { result.first, result.second }
    table.sort(expected_buffer)
    expect.equality(result.after_buffer, expected_buffer)
    expect.equality(result.after_window, { result.first })
    expect.equality(vim.tbl_contains(result.after_buffer, result.other), false)
end

T["flush enumerates source windows once and renders all eligible dirty windows"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        local third = vim.api.nvim_get_current_win()
        local sources = { first, second, third }
        local enumerations = 0
        local rendered = {}
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({ update = { interval_ms = 1000 } }),
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
    table.sort(result.rendered)
    expect.equality(result.enumerations, 1)
    expect.equality(result.rendered, result.sources)
end

T["default update events register the minimap autocmd set"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local config = require("scrollbar.minimap.config").get()
        local scheduler = require("scrollbar.minimap.scheduler")
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

        -- Defaults from minimap config: drops OptionSet, TabEnter, TermEnter, CmdwinLeave.
        local expected = {
            "BufEnter",
            "BufWinEnter",
            "WinEnter",
            "CursorMoved",
            "CursorMovedI",
            "TextChanged",
            "TextChangedI",
            "TextChangedP",
            "TextChangedT",
            "WinScrolled",
            "WinResized",
            "VimResized",
            "ColorScheme",
            "WinClosed",
            "BufDelete",
            "BufWipeout",
        }
        local unexpected = {
            "OptionSet",
            "TabEnter",
            "TermEnter",
            "CmdwinLeave",
            "TabClosed",
        }
        local missing = {}
        for _, event in ipairs(expected) do
            if not event_set[event] then
                missing[#missing + 1] = event
            end
        end
        local present_unexpected = {}
        for _, event in ipairs(unexpected) do
            if event_set[event] then
                present_unexpected[#present_unexpected + 1] = event
            end
        end
        return {
            missing = missing,
            present_unexpected = present_unexpected,
        }
    end)

    expect.equality(result.missing, {})
    expect.equality(result.present_unexpected, {})
end

T["narrower update events list registers fewer autocmds"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local scheduler = require("scrollbar.minimap.scheduler")

        local function count_events(events)
            local config = require("scrollbar.minimap.config").set({ update = { events = events } })
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
                local evt = autocmd.event
                if type(evt) == "string" then
                    evt = { evt }
                end
                for _, e in ipairs(evt) do
                    event_set[e] = true
                end
            end
            scheduler.dispose()
            return vim.tbl_count(event_set)
        end

        local default_count = count_events({
            "BufEnter",
            "BufWinEnter",
            "WinEnter",
            "WinScrolled",
            "WinResized",
            "VimResized",
            "CursorMoved",
            "CursorMovedI",
            "TextChanged",
            "TextChangedI",
            "TextChangedP",
            "TextChangedT",
            "WinClosed",
            "BufDelete",
            "BufWipeout",
            "ColorScheme",
        })
        local narrow_count = count_events({ "BufEnter", "CursorMoved" })
        return {
            default_count = default_count,
            narrow_count = narrow_count,
        }
    end)

    expect.equality(result.default_count, 16)
    expect.equality(result.narrow_count, 2)
end

T["interval_ms coalesces repeated invalidations into one flush"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
        local renders = 0
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({ update = { interval_ms = 50 } }),
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
                    renders = renders + 1
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        for _ = 1, 5 do
            scheduler.invalidate_window(winid)
        end
        assert(vim.wait(500, function()
            return renders == 1
        end))
        vim.wait(80)
        scheduler.dispose()
        return renders
    end)

    expect.equality(result, 1)
end

T["autohide hide-timer restarts on activity when minimap.autohide.enabled = true"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local winid = vim.api.nvim_get_current_win()
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

        local visible = true
        local revealed = {}
        local concealed = {}
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({
                autohide = { enabled = true, delay_ms = 50 },
                update = { interval_ms = 1000 },
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
                reveal = function(w)
                    table.insert(revealed, w)
                    return true
                end,
                conceal = function(w)
                    table.insert(concealed, w)
                    return true
                end,
                render = function() end,
                is_visible = function()
                    return visible
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        vim.api.nvim_exec_autocmds("CursorMoved", {})
        -- The first activity creates a hide timer. With three new_timer calls
        -- expected (1 main flush timer + 1 hide timer), the hide timer is the
        -- second timer created.
        local hide_timer = timers[2]
        local starts_after_first = hide_timer.starts

        vim.api.nvim_exec_autocmds("CursorMoved", {})
        local starts_after_second = hide_timer.starts

        hide_timer.callback()
        assert(vim.wait(100, function()
            return #concealed == 1
        end))

        scheduler.dispose()
        uv.new_timer = original_new_timer
        return {
            starts_after_first = starts_after_first,
            starts_after_second = starts_after_second,
            concealed = concealed,
            revealed = revealed,
        }
    end)

    expect.equality(result.starts_after_first, 1)
    expect.equality(result.starts_after_second, 2)
    expect.equality(#result.concealed, 1)
    expect.equality(#result.revealed, 2)
end

T["dispose stops all timers including pending hide timers"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local timers = {}
        local uv = vim.uv or vim.loop
        local original_new_timer = uv.new_timer
        uv.new_timer = function()
            local timer = { closed = false }
            function timer:start(_, _, callback)
                self.callback = callback
            end
            function timer:stop() end
            function timer:close()
                self.closed = true
            end
            function timer:is_closing()
                return self.closed
            end
            table.insert(timers, timer)
            return timer
        end

        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({
                autohide = { enabled = true, delay_ms = 100 },
                update = { interval_ms = 1000 },
            }),
            renderer = {
                source_windows = function()
                    return { first, second }
                end,
                is_source_window = function(w)
                    return w == first or w == second
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
                conceal = function()
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
        vim.api.nvim_set_current_win(second)
        vim.api.nvim_exec_autocmds("CursorMoved", {})
        local closed = {}
        for _, timer in ipairs(timers) do
            table.insert(closed, timer.closed)
        end
        scheduler.dispose()
        local closed_after = {}
        for _, timer in ipairs(timers) do
            table.insert(closed_after, timer.closed)
        end
        uv.new_timer = original_new_timer
        return {
            closed_before_dispose = closed,
            closed_after_dispose = closed_after,
        }
    end)

    -- Before dispose, only hide timers exist; the main timer is not closed.
    for _, state in ipairs(result.closed_before_dispose) do
        expect.equality(state, false)
    end
    -- After dispose, every timer is closed.
    for _, state in ipairs(result.closed_after_dispose) do
        expect.equality(state, true)
    end
end

T["invalidate_buffer walks source windows for the buffer"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        local first_buf = vim.api.nvim_get_current_buf()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local second_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(second, second_buf)
        local scheduler = require("scrollbar.minimap.scheduler")
        local first_dirty = {}
        local second_dirty = {}
        scheduler.setup({
            config = require("scrollbar.minimap.config").set({ update = { interval_ms = 1000 } }),
            renderer = {
                source_windows = function(bufnr)
                    if bufnr == nil then
                        return { first, second }
                    end
                    if bufnr == first_buf then
                        return { first }
                    end
                    if bufnr == second_buf then
                        return { second }
                    end
                    return {}
                end,
                is_source_window = function(w)
                    return w == first or w == second
                end,
                is_buffer_eligible = function(b)
                    return b == first_buf or b == second_buf
                end,
                is_owned_buffer = function()
                    return false
                end,
                render = function(w)
                    if w == first then
                        table.insert(first_dirty, w)
                    elseif w == second then
                        table.insert(second_dirty, w)
                    end
                end,
                is_owned_window = function()
                    return false
                end,
            },
        })

        local first_count = scheduler.invalidate_buffer(first_buf)
        local second_count = scheduler.invalidate_buffer(second_buf)
        scheduler.flush()
        scheduler.dispose()
        return {
            first = first,
            second = second,
            first_count = first_count,
            second_count = second_count,
            first_dirty = first_dirty,
            second_dirty = second_dirty,
        }
    end)

    expect.equality(result.first_count, 1)
    expect.equality(result.second_count, 1)
    expect.equality(result.first_dirty, { result.first })
    expect.equality(result.second_dirty, { result.second })
end

T["scheduler augroup is independent of the scrollbar scheduler augroup"] = function()
    local child = new_child()
    reset_config(child)
    local result = child.lua_func(function()
        local minimap_scheduler = require("scrollbar.minimap.scheduler")
        local scrollbar_scheduler = require("scrollbar.scheduler")

        local minimap_renderer = {
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
        }

        minimap_scheduler.setup({
            config = require("scrollbar.minimap.config").get(),
            renderer = minimap_renderer,
        })
        local minimap_augroup = minimap_scheduler.status().augroup_id

        scrollbar_scheduler.setup({
            config = require("scrollbar.config").set({ scrollbar = { set_highlights = false } }),
            renderer = minimap_renderer,
        })
        local scrollbar_augroup = scrollbar_scheduler.status().augroup_id

        -- Disposing one leaves the other intact.
        minimap_scheduler.dispose()
        local scrollbar_group_exists = pcall(vim.api.nvim_get_autocmds, { group = scrollbar_augroup })
        scrollbar_scheduler.dispose()
        return {
            minimap_augroup = minimap_augroup,
            scrollbar_augroup = scrollbar_augroup,
            scrollbar_group_exists = scrollbar_group_exists,
        }
    end)

    expect.no_equality(result.minimap_augroup, result.scrollbar_augroup)
    expect.equality(result.scrollbar_group_exists, true)
end

return T
