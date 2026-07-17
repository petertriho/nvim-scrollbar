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

local function root_config(overrides)
    return require("scrollbar.presets").merge({
        set_highlights = false,
        render = { interval_ms = 1000, geometry = "line" },
        mouse = { enabled = true },
        thumb = { text = "H", hide_if_all_visible = false },
        providers = {
            cursor = false,
            diagnostic = false,
            search = false,
            marks = false,
            gitsigns = false,
            mini_diff = false,
            ale = false,
            coc = false,
        },
        excluded_buftypes = {},
        excluded_filetypes = {},
    }, overrides or {})
end

T["exposes only the public root orchestration API"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local scrollbar = require("scrollbar")
        scrollbar.setup(config)
        local keys = vim.tbl_keys(scrollbar)
        table.sort(keys)
        return {
            keys = keys,
            commands = {
                hide = vim.fn.exists(":ScrollbarHide"),
                refresh = vim.fn.exists(":ScrollbarRefresh"),
                show = vim.fn.exists(":ScrollbarShow"),
                toggle = vim.fn.exists(":ScrollbarToggle"),
            },
            handlers_load = pcall(require, "scrollbar.handlers"),
        }
    end, root_config())

    expect.equality(result.keys, { "hide", "refresh", "setup", "show", "toggle" })
    expect.equality(result.commands, { hide = 2, refresh = 2, show = 2, toggle = 2 })
    expect.equality(result.handlers_load, false)
end

T["validates before disposing the active runtime"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local scrollbar = require("scrollbar")
        scrollbar.setup(config)
        require("scrollbar.scheduler").flush()
        local source_win = vim.api.nvim_get_current_win()
        local before = assert(require("scrollbar.renderer").get_state(source_win))
        local ok = pcall(scrollbar.setup, { render = { interval_ms = -1 } })
        local after = require("scrollbar.renderer").get_state(source_win)
        return {
            ok = ok,
            same_float = after ~= nil and after.float_win == before.float_win,
            float_valid = vim.api.nvim_win_is_valid(before.float_win),
            scheduler_setup = require("scrollbar.scheduler").status().setup,
        }
    end, root_config())

    expect.equality(result, {
        ok = false,
        same_float = true,
        float_valid = true,
        scheduler_setup = true,
    })
end

T["preserves custom providers while reconciling only root-owned built-ins"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local providers = require("scrollbar.providers")
        local calls = { before = 0, after = 0, cursor = 0 }
        local before = {
            name = "before",
            setup = function()
                calls.before = calls.before + 1
            end,
            refresh = function()
                return {}
            end,
        }
        local custom_cursor = {
            name = "cursor",
            setup = function()
                calls.cursor = calls.cursor + 1
            end,
            refresh = function()
                return {}
            end,
        }
        providers.register(before)
        providers.register(custom_cursor)

        local scrollbar = require("scrollbar")
        scrollbar.setup(config)
        local after = {
            name = "after",
            setup = function()
                calls.after = calls.after + 1
            end,
            refresh = function()
                return {}
            end,
        }
        providers.register(after)
        scrollbar.setup(config)

        local first = {
            before = providers.get("before") == before,
            after = providers.get("after") == after,
            cursor = providers.get("cursor") == custom_cursor,
            calls = vim.deepcopy(calls),
        }

        local disabled = vim.deepcopy(config)
        disabled.providers.cursor = false
        scrollbar.setup(disabled)
        first.cursor_after_disable = providers.get("cursor") == custom_cursor
        first.cursor_calls_after_disable = calls.cursor
        return first
    end, root_config({ providers = { cursor = true } }))

    expect.equality(result, {
        before = true,
        after = true,
        cursor = true,
        cursor_after_disable = true,
        calls = { before = 2, after = 2, cursor = 2 },
        cursor_calls_after_disable = 3,
    })
end

T["registers configured built-ins once and removes disabled root-owned providers"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local scrollbar = require("scrollbar")
        local providers = require("scrollbar.providers")
        scrollbar.setup(config)
        local first_cursor = providers.get("cursor")
        local first_diagnostic = providers.get("diagnostic")
        scrollbar.setup(config)
        local repeated_cursor = providers.get("cursor")
        local cursor_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_cursor_events" })
        local diagnostic_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_diagnostic_events" })

        local disabled = vim.deepcopy(config)
        disabled.providers.cursor = false
        scrollbar.setup(disabled)
        return {
            cursor_registered = first_cursor ~= nil,
            diagnostic_registered = first_diagnostic ~= nil,
            cursor_reused = repeated_cursor == first_cursor,
            cursor_autocmds = #cursor_autocmds,
            diagnostic_autocmds = #diagnostic_autocmds,
            cursor_removed = providers.get("cursor") == nil,
            diagnostic_preserved = providers.get("diagnostic") == first_diagnostic,
        }
    end, root_config({ providers = { cursor = true, diagnostic = true } }))

    expect.equality(result, {
        cursor_registered = true,
        diagnostic_registered = true,
        cursor_reused = true,
        cursor_autocmds = 4,
        diagnostic_autocmds = 1,
        cursor_removed = true,
        diagnostic_preserved = true,
    })
end

T["registers both marks modes and fully removes the disabled builtin"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        vim.api.nvim_buf_set_mark(0, "a", 2, 0, {})

        local scrollbar = require("scrollbar")
        local providers = require("scrollbar.providers")
        local store = require("scrollbar.store")
        local disabled_by_default = vim.deepcopy(config)
        scrollbar.setup(disabled_by_default)
        local default_registered = providers.get("marks") ~= nil
        local default_group_exists = pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarProvider_marks_events" })
        local default_marks = store.get(vim.api.nvim_get_current_buf()).marks

        local collapsed = vim.deepcopy(config)
        collapsed.providers.marks = true
        scrollbar.setup(collapsed)
        local first = providers.get("marks")
        local collapsed_marks = store.get(vim.api.nvim_get_current_buf()).marks

        local expanded = vim.deepcopy(config)
        expanded.providers.marks = { numbers = true }
        scrollbar.setup(expanded)
        local repeated = providers.get("marks")

        scrollbar.setup(disabled_by_default)
        local group_exists = pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarProvider_marks_events" })
        return {
            default_registered = default_registered,
            default_group_exists = default_group_exists,
            default_marks = default_marks,
            collapsed_registered = first ~= nil,
            collapsed_marks = collapsed_marks,
            table_mode_reused = repeated == first,
            removed = providers.get("marks") == nil,
            marks_cleared = store.get(vim.api.nvim_get_current_buf()).marks == nil,
            group_exists = group_exists,
        }
    end, root_config())

    expect.equality(result, {
        default_registered = false,
        default_group_exists = false,
        collapsed_registered = true,
        collapsed_marks = { { line = 1, type = "Mark", text = "a" } },
        table_mode_reused = true,
        removed = true,
        marks_cleared = true,
        group_exists = false,
    })
end

T["configured cursor and diagnostics publish only through the central store"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        local bufnr = vim.api.nvim_get_current_buf()
        require("scrollbar").setup(config)

        local namespace = vim.api.nvim_create_namespace("ScrollbarRootDiagnosticTest")
        vim.diagnostic.set(namespace, bufnr, {
            {
                lnum = 2,
                col = 0,
                severity = vim.diagnostic.severity.ERROR,
                message = "root diagnostic",
            },
        })
        local store = require("scrollbar.store")
        local snapshot = store.get(bufnr)
        local legacy_variable = pcall(vim.api.nvim_buf_get_var, bufnr, "scrollbar_marks")
        vim.diagnostic.reset(namespace, bufnr)
        return {
            cursor = store.get_window(vim.api.nvim_get_current_win()).cursor,
            diagnostic = snapshot.diagnostic,
            legacy_variable = legacy_variable,
        }
    end, root_config({ providers = { cursor = true, diagnostic = true } }))

    expect.equality(result, {
        cursor = { { line = 1, type = "Cursor" } },
        diagnostic = { { line = 2, type = "Error" } },
        legacy_variable = false,
    })
end

T["repeated setup replaces all owned runtime resources without duplication"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local orphan_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_var(orphan_buf, "scrollbar_owned", true)
        local orphan_win = vim.api.nvim_open_win(orphan_buf, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 1,
            height = 1,
        })
        vim.api.nvim_win_set_var(orphan_win, "scrollbar_owned", true)

        local scrollbar = require("scrollbar")
        scrollbar.setup(config)
        require("scrollbar.scheduler").flush()
        local source_win = vim.api.nvim_get_current_win()
        local first = assert(require("scrollbar.renderer").get_state(source_win))
        local first_group = require("scrollbar.scheduler").status().augroup_id

        scrollbar.setup(config)
        require("scrollbar.scheduler").flush()
        local second = assert(require("scrollbar.renderer").get_state(source_win))
        local second_group = require("scrollbar.scheduler").status().augroup_id
        local mappings = vim.api.nvim_buf_get_keymap(second.float_buf, "n")
        local owned_buffers = 0
        local owned_windows = 0
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            local ok, owned = pcall(vim.api.nvim_buf_get_var, bufnr, "scrollbar_owned")
            if ok and owned == true then
                owned_buffers = owned_buffers + 1
            end
        end
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if require("scrollbar.renderer").is_owned_window(winid) then
                owned_windows = owned_windows + 1
            end
        end

        return {
            old_float_closed = not vim.api.nvim_win_is_valid(first.float_win),
            old_buffer_deleted = not vim.api.nvim_buf_is_valid(first.float_buf),
            orphan_float_closed = not vim.api.nvim_win_is_valid(orphan_win),
            orphan_buffer_deleted = not vim.api.nvim_buf_is_valid(orphan_buf),
            new_float = second.float_win ~= first.float_win,
            scheduler_group_replaced = first_group ~= second_group,
            scheduler_autocmds = #vim.api.nvim_get_autocmds({ group = second_group }),
            provider_manager_autocmds = #vim.api.nvim_get_autocmds({ group = "ScrollbarProviderManager" }),
            mouse_autocmds = #vim.api.nvim_get_autocmds({ group = "ScrollbarMouse" }),
            mappings = #mappings,
            owned_buffers = owned_buffers,
            owned_windows = owned_windows,
            float_is_provider_eligible = require("scrollbar.providers").refresh(second.float_buf),
        }
    end, root_config())

    expect.equality(result.old_float_closed, true)
    expect.equality(result.old_buffer_deleted, true)
    expect.equality(result.orphan_float_closed, true)
    expect.equality(result.orphan_buffer_deleted, true)
    expect.equality(result.new_float, true)
    expect.equality(result.scheduler_group_replaced, true)
    expect.equality(result.scheduler_autocmds > 0, true)
    expect.equality(result.provider_manager_autocmds, 6)
    expect.equality(result.mouse_autocmds, 4)
    expect.equality(result.mappings, 3)
    expect.equality(result.owned_buffers, 1)
    expect.equality(result.owned_windows, 1)
    expect.equality(result.float_is_provider_eligible, false)
end

T["public commands change visibility globally across every owned window"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()

        require("scrollbar").setup(config)
        require("scrollbar.scheduler").flush()
        local renderer = require("scrollbar.renderer")
        local initially_visible = renderer.get_state(first) ~= nil and renderer.get_state(second) ~= nil

        vim.cmd("ScrollbarHide")
        local hidden = renderer.get_state(first) == nil and renderer.get_state(second) == nil
        vim.api.nvim_set_current_win(first)
        vim.cmd("ScrollbarShow")
        require("scrollbar.scheduler").flush()
        local shown = renderer.get_state(first) ~= nil and renderer.get_state(second) ~= nil

        vim.cmd("ScrollbarToggle")
        local toggled_hidden = renderer.get_state(first) == nil and renderer.get_state(second) == nil
        vim.api.nvim_set_current_win(second)
        vim.cmd("ScrollbarToggle")
        require("scrollbar.scheduler").flush()
        local toggled_shown = renderer.get_state(first) ~= nil and renderer.get_state(second) ~= nil
        return {
            initially_visible = initially_visible,
            hidden = hidden,
            shown = shown,
            toggled_hidden = toggled_hidden,
            toggled_shown = toggled_shown,
        }
    end, root_config())

    expect.equality(result, {
        initially_visible = true,
        hidden = true,
        shown = true,
        toggled_hidden = true,
        toggled_shown = true,
    })
end

T["autohide commands preserve global master visibility and temporary reveals"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()

        require("scrollbar").setup(config)
        local scheduler = require("scrollbar.scheduler")
        local renderer = require("scrollbar.renderer")
        scheduler.flush()
        local startup_hidden = renderer.is_visible()
            and renderer.get_state(first) == nil
            and renderer.get_state(second) == nil

        vim.api.nvim_set_current_win(first)
        scheduler.flush()
        vim.api.nvim_exec_autocmds("CursorMoved", {})
        scheduler.flush()
        local navigation_scoped = renderer.get_state(first) ~= nil and renderer.get_state(second) == nil
        assert(vim.wait(500, function()
            return renderer.get_state(first) == nil
        end))
        local expired = renderer.is_visible() and renderer.get_state(first) == nil

        vim.cmd("ScrollbarHide")
        vim.api.nvim_set_current_win(second)
        vim.api.nvim_exec_autocmds("CursorMovedI", {})
        scheduler.flush()
        local hide_blocked = not renderer.is_visible()
            and renderer.get_state(first) == nil
            and renderer.get_state(second) == nil

        vim.cmd("ScrollbarShow")
        scheduler.flush()
        local show_revealed = renderer.is_visible()
            and renderer.get_state(first) ~= nil
            and renderer.get_state(second) ~= nil
        assert(vim.wait(500, function()
            return renderer.get_state(first) == nil and renderer.get_state(second) == nil
        end))

        vim.cmd("ScrollbarToggle")
        local toggle_disabled = not renderer.is_visible()
        vim.cmd("ScrollbarToggle")
        local toggle_enabled_before_flush = renderer.is_visible()
            and renderer.get_state(first) == nil
            and renderer.get_state(second) == nil
        scheduler.flush()
        local toggle_revealed = renderer.get_state(first) ~= nil and renderer.get_state(second) ~= nil
        assert(vim.wait(500, function()
            return renderer.get_state(first) == nil and renderer.get_state(second) == nil
        end))

        vim.cmd("ScrollbarRefresh")
        scheduler.flush()
        local refresh_hidden = renderer.is_visible()
            and renderer.get_state(first) == nil
            and renderer.get_state(second) == nil

        return {
            startup_hidden = startup_hidden,
            navigation_scoped = navigation_scoped,
            expired = expired,
            hide_blocked = hide_blocked,
            show_revealed = show_revealed,
            toggle_disabled = toggle_disabled,
            toggle_enabled_before_flush = toggle_enabled_before_flush,
            toggle_revealed = toggle_revealed,
            refresh_hidden = refresh_hidden,
        }
    end, root_config({ autohide = { enabled = true, delay_ms = 30 } }))

    expect.equality(result, {
        startup_hidden = true,
        navigation_scoped = true,
        expired = true,
        hide_blocked = true,
        show_revealed = true,
        toggle_disabled = true,
        toggle_enabled_before_flush = true,
        toggle_revealed = true,
        refresh_hidden = true,
    })
end

T["show defers exactly one render per source window to the scheduler"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")

        local scrollbar = require("scrollbar")
        scrollbar.setup(config)
        local scheduler = require("scrollbar.scheduler")
        scheduler.flush()
        scrollbar.hide()

        local renderer = require("scrollbar.renderer")
        local render = renderer.render
        local renders = {}
        rawset(renderer, "render", function(winid)
            table.insert(renders, winid)
            return render(winid)
        end)

        scrollbar.show()
        local before_flush = {
            renders = #renders,
            states = #vim.tbl_filter(function(winid)
                return renderer.get_state(winid) ~= nil
            end, renderer.source_windows()),
            queued = #scheduler.status().dirty_windows,
        }
        scheduler.flush()
        local after_flush = vim.deepcopy(renders)
        local second_flush = scheduler.flush()
        rawset(renderer, "render", render)

        return {
            before_flush = before_flush,
            after_flush = after_flush,
            second_flush = second_flush,
            sources = renderer.source_windows(),
        }
    end, root_config())

    table.sort(result.sources)
    expect.equality(result.before_flush, { renders = 0, states = 0, queued = #result.sources })
    expect.equality(result.after_flush, result.sources)
    expect.equality(result.second_flush, false)
end

T["public refresh recollects displayed buffers through providers and schedules rendering"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("vsplit")
        local providers = require("scrollbar.providers")
        local refreshes = 0
        local window_refreshes = 0
        providers.register({
            name = "custom",
            refresh = function()
                refreshes = refreshes + 1
                return { { line = refreshes, type = "Misc" } }
            end,
            refresh_window = function()
                window_refreshes = window_refreshes + 1
                return { { line = window_refreshes, type = "Misc" } }
            end,
        })

        local scrollbar = require("scrollbar")
        scrollbar.setup(config)
        require("scrollbar.scheduler").flush()
        refreshes = 0
        window_refreshes = 0
        vim.cmd("ScrollbarRefresh")
        local queued = require("scrollbar.scheduler").status().dirty_windows
        require("scrollbar.scheduler").flush()
        local bufnr = vim.api.nvim_get_current_buf()
        return {
            refreshes = refreshes,
            window_refreshes = window_refreshes,
            marks = require("scrollbar.store").get(bufnr).custom,
            queued = #queued,
            source_windows = #require("scrollbar.renderer").source_windows(bufnr),
        }
    end, root_config())

    expect.equality(result.refreshes, 1)
    expect.equality(result.window_refreshes, 2)
    expect.equality(result.marks, { { line = 1, type = "Misc" } })
    expect.equality(result.queued, result.source_windows)
    expect.equality(result.source_windows, 2)
end

T["root setup enables both diff providers and refresh clears disabled mini.diff data"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local mini_data = { hunks = { { type = "change", buf_start = 2, buf_count = 1 } } }
        rawset(package.preload, "mini.diff", function()
            return {
                get_buf_data = function()
                    return mini_data
                end,
            }
        end)
        rawset(package.preload, "gitsigns", function()
            return {
                get_hunks = function()
                    return { { type = "add", added = { start = 1, count = 1 } } }
                end,
            }
        end)

        require("scrollbar").setup(config)
        local bufnr = vim.api.nvim_get_current_buf()
        local before = require("scrollbar.store").get(bufnr)
        mini_data = nil
        vim.cmd("ScrollbarRefresh")
        local after = require("scrollbar.store").get(bufnr)
        return {
            before = before,
            after = after,
            mini_registered = require("scrollbar.providers").get("mini_diff") ~= nil,
        }
    end, root_config({ providers = { gitsigns = true, mini_diff = true } }))

    expect.equality(result.before.gitsigns, { { line = 0, type = "GitAdd" } })
    expect.equality(result.before.mini_diff, { { line = 1, type = "MiniDiffChange" } })
    expect.equality(result.after.gitsigns, { { line = 0, type = "GitAdd" } })
    expect.equality(result.after.mini_diff, {})
    expect.equality(result.mini_registered, true)
end

return T
