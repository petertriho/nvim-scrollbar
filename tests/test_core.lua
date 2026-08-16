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
        update = { interval_ms = 1000 },
        render = { geometry = "line" },
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
        scrollbar.setup({ scrollbar = config })
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
        scrollbar.setup({ scrollbar = config })
        require("scrollbar.scheduler").flush()
        local source_win = vim.api.nvim_get_current_win()
        local before = assert(require("scrollbar.renderer").get_state(source_win))
        local ok = pcall(scrollbar.setup, { scrollbar = { update = { interval_ms = -1 } } })
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
            refresh_owner = { buffer = "provider" },
            setup = function()
                calls.before = calls.before + 1
            end,
            refresh = function()
                return {}
            end,
        }
        local custom_cursor = {
            name = "cursor",
            refresh_owner = { buffer = "provider" },
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
        scrollbar.setup({ scrollbar = config })
        local after = {
            name = "after",
            refresh_owner = { buffer = "provider" },
            setup = function()
                calls.after = calls.after + 1
            end,
            refresh = function()
                return {}
            end,
        }
        providers.register(after)
        scrollbar.setup({ scrollbar = config })

        local first = {
            before = providers.get("before") == before,
            after = providers.get("after") == after,
            cursor = providers.get("cursor") == custom_cursor,
            calls = vim.deepcopy(calls),
        }

        local disabled = vim.deepcopy(config)
        disabled.providers.cursor = false
        scrollbar.setup({ scrollbar = disabled })
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
        scrollbar.setup({ scrollbar = config })
        local first_cursor = providers.get("cursor")
        local first_diagnostic = providers.get("diagnostic")
        scrollbar.setup({ scrollbar = config })
        local repeated_cursor = providers.get("cursor")
        local cursor_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_cursor_events" })
        local diagnostic_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_diagnostic_events" })

        local disabled = vim.deepcopy(config)
        disabled.providers.cursor = false
        scrollbar.setup({ scrollbar = disabled })
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
        cursor_autocmds = 2,
        diagnostic_autocmds = 1,
        cursor_removed = true,
        diagnostic_preserved = true,
    })
end

T["reconciles shared and reserved builtins from union demand"] = function()
    local child = new_child()
    local result = child.lua_func(function(scrollbar_config)
        local scrollbar = require("scrollbar")
        local providers = require("scrollbar.providers")

        local function minimap_config(enabled, requested)
            return {
                enabled = enabled,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
                providers = vim.tbl_extend("force", {
                    cursor = false,
                    diagnostic = false,
                    search = false,
                    marks = false,
                    gitsigns = false,
                    mini_diff = false,
                    signify = false,
                    vgit = false,
                    ale = false,
                    coc = false,
                    treesitter = false,
                    lsp_semantic_tokens = false,
                }, requested or {}),
            }
        end

        scrollbar.setup({
            scrollbar = scrollbar_config,
            minimap = minimap_config(true, { diagnostic = true }),
        })
        local minimap_only = providers.get("diagnostic")

        local both = vim.deepcopy(scrollbar_config)
        both.providers.diagnostic = true
        scrollbar.setup({
            scrollbar = both,
            minimap = minimap_config(true, { diagnostic = true }),
        })
        local shared = providers.get("diagnostic")
        local diagnostic_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_diagnostic_events" })

        scrollbar.setup({
            scrollbar = scrollbar_config,
            minimap = minimap_config(true, { treesitter = true, lsp_semantic_tokens = true }),
        })
        local treesitter = providers.get("treesitter")
        local lsp = providers.get("lsp_semantic_tokens")
        local spans = require("scrollbar.store").get_minimap_spans(vim.api.nvim_get_current_buf())

        scrollbar.setup({
            scrollbar = scrollbar_config,
            minimap = minimap_config(false, {
                diagnostic = true,
                treesitter = true,
                lsp_semantic_tokens = true,
            }),
        })
        return {
            minimap_only_registered = minimap_only ~= nil,
            minimap_target = minimap_only and minimap_only.targets and minimap_only.targets.minimap,
            shared_reused = shared == minimap_only,
            diagnostic_autocmds = #diagnostic_autocmds,
            treesitter_targets = treesitter and treesitter.targets,
            lsp_targets = lsp and lsp.targets,
            semantic_spans = spans,
            diagnostic_removed = providers.get("diagnostic") == nil,
            treesitter_removed = providers.get("treesitter") == nil,
            lsp_removed = providers.get("lsp_semantic_tokens") == nil,
        }
    end, root_config())

    expect.equality(result, {
        minimap_only_registered = true,
        minimap_target = true,
        shared_reused = true,
        diagnostic_autocmds = 1,
        treesitter_targets = { scrollbar = false, minimap = true },
        lsp_targets = { scrollbar = false, minimap = true },
        semantic_spans = {},
        diagnostic_removed = true,
        treesitter_removed = true,
        lsp_removed = true,
    })
end

T["activates providers after both store consumers are ready"] = function()
    local child = new_child()
    local result = child.lua_func(function(scrollbar_config)
        local bufnr = vim.api.nvim_get_current_buf()
        local winid = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two" })
        local observed = {}

        require("scrollbar.providers").register({
            name = "lifecycle-ready",
            targets = { scrollbar = true, minimap = true },
            setup = function(context)
                observed.before = {
                    scrollbar_setup = require("scrollbar.scheduler").status().setup,
                    minimap_setup = require("scrollbar.minimap.scheduler").status().setup,
                    scrollbar_dirty = require("scrollbar.scheduler").status().dirty_windows,
                    minimap_dirty = require("scrollbar.minimap.scheduler").status().dirty_windows,
                }
                context.set_marks(bufnr, { { line = 0, type = "Misc" } })
                observed.after_marks = {
                    scrollbar_dirty = require("scrollbar.scheduler").status().dirty_windows,
                    minimap_dirty = require("scrollbar.minimap.scheduler").status().dirty_windows,
                }
                context.set_minimap_spans(bufnr, {
                    { line = 0, start_col = 0, end_col = 1, highlight = "Comment", priority = 1 },
                })
            end,
        })

        require("scrollbar").setup({
            scrollbar = scrollbar_config,
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
                providers = {
                    cursor = false,
                    diagnostic = false,
                    search = false,
                    marks = false,
                    gitsigns = false,
                    mini_diff = false,
                    signify = false,
                    vgit = false,
                    ale = false,
                    coc = false,
                    treesitter = false,
                    lsp_semantic_tokens = false,
                },
            },
        })
        observed.winid = winid
        return observed
    end, root_config())

    expect.equality(result.before, {
        scrollbar_setup = true,
        minimap_setup = true,
        scrollbar_dirty = {},
        minimap_dirty = {},
    })
    expect.equality(result.after_marks, {
        scrollbar_dirty = { result.winid },
        minimap_dirty = { result.winid },
    })
end

T["repeated setup keeps one store callback and disabled minimap installs none"] = function()
    local child = new_child()
    local result = child.lua_func(function(scrollbar_config)
        local bufnr = vim.api.nvim_get_current_buf()
        local winid = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one", "two" })
        scrollbar_config.providers.cursor = true
        local scrollbar = require("scrollbar")
        local minimap_config = {
            enabled = true,
            set_highlights = false,
            backend = "sync",
            width = 4,
            height = 4,
            providers = {
                cursor = true,
                diagnostic = false,
                search = false,
                marks = false,
                gitsigns = false,
                mini_diff = false,
                signify = false,
                vgit = false,
                ale = false,
                coc = false,
                treesitter = false,
                lsp_semantic_tokens = false,
            },
        }
        scrollbar.setup({ scrollbar = scrollbar_config, minimap = minimap_config })
        scrollbar.setup({ scrollbar = scrollbar_config, minimap = minimap_config })

        local scrollbar_scheduler = require("scrollbar.scheduler")
        local minimap_scheduler = require("scrollbar.minimap.scheduler")
        local calls = { scrollbar = 0, minimap = 0 }
        local scrollbar_invalidate = scrollbar_scheduler.invalidate_buffer
        local minimap_invalidate = minimap_scheduler.invalidate_buffer
        rawset(scrollbar_scheduler, "invalidate_buffer", function(target_buf)
            calls.scrollbar = calls.scrollbar + 1
            return scrollbar_invalidate(target_buf)
        end)
        rawset(minimap_scheduler, "invalidate_buffer", function(target_buf)
            calls.minimap = calls.minimap + 1
            return minimap_invalidate(target_buf)
        end)

        local store = require("scrollbar.store")
        store.set("cursor", bufnr, { { line = 0, type = "Cursor" } })
        local repeated = vim.deepcopy(calls)

        local disabled = vim.deepcopy(minimap_config)
        disabled.enabled = false
        scrollbar.setup({ scrollbar = scrollbar_config, minimap = disabled })
        calls = { scrollbar = 0, minimap = 0 }
        store.set("cursor", bufnr, { { line = 1, type = "Cursor" } })
        return {
            repeated = repeated,
            disabled = calls,
            minimap_scheduler_setup = minimap_scheduler.status().setup,
            minimap_worker_state = require("scrollbar.minimap.worker").status().state,
            winid = winid,
        }
    end, root_config())

    expect.equality(result.repeated, { scrollbar = 1, minimap = 1 })
    expect.equality(result.disabled, { scrollbar = 1, minimap = 0 })
    expect.equality(result.minimap_scheduler_setup, false)
    expect.equality(result.minimap_worker_state, "disposed")
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
        scrollbar.setup({ scrollbar = disabled_by_default })
        local default_registered = providers.get("marks") ~= nil
        local default_group_exists = pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarProvider_marks_events" })
        local default_marks = store.get(vim.api.nvim_get_current_buf()).marks

        local collapsed = vim.deepcopy(config)
        collapsed.providers.marks = true
        scrollbar.setup({ scrollbar = collapsed })
        local first = providers.get("marks")
        local collapsed_marks = store.get(vim.api.nvim_get_current_buf()).marks

        local expanded = vim.deepcopy(config)
        expanded.providers.marks = { numbers = true }
        scrollbar.setup({ scrollbar = expanded })
        local repeated = providers.get("marks")

        scrollbar.setup({ scrollbar = disabled_by_default })
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

T["scheduler-hosted text-change subscription reconciles marks through the default wiring"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        vim.api.nvim_buf_set_mark(0, "a", 2, 0, {})

        local scrollbar = require("scrollbar")
        local wired = vim.deepcopy(config)
        wired.providers.marks = true
        scrollbar.setup({ scrollbar = wired })
        local store = require("scrollbar.store")
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_exec_autocmds("BufEnter", { buffer = bufnr })
        local settled = vim.wait(300, function()
            return (store.get(bufnr).marks or {})[1] ~= nil
        end, 20)

        -- The marks provider rides the scheduler's TextChanged dispatch: its
        -- own augroup must not carry text-change rows in the wired setup.
        local standalone_text_rows = 0
        for _, autocmd in
            ipairs(vim.api.nvim_get_autocmds({
                event = { "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" },
            }))
        do
            if autocmd.group_name == "ScrollbarProvider_marks_events" then
                standalone_text_rows = standalone_text_rows + 1
            end
        end

        vim.api.nvim_buf_set_lines(0, 0, 0, false, { "inserted" })
        vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })
        local shifted = store.get(bufnr).marks
        return {
            settled = settled,
            standalone_text_rows = standalone_text_rows,
            shifted_line = shifted and shifted[1] and shifted[1].line or nil,
        }
    end, root_config())

    expect.equality(result.settled, true)
    expect.equality(result.standalone_text_rows, 0)
    expect.equality(result.shifted_line, 2)
end

T["configured cursor and diagnostics publish only through the central store"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        vim.api.nvim_win_set_cursor(0, { 2, 0 })
        local bufnr = vim.api.nvim_get_current_buf()
        require("scrollbar").setup({ scrollbar = config })

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
        scrollbar.setup({ scrollbar = config })
        require("scrollbar.scheduler").flush()
        local source_win = vim.api.nvim_get_current_win()
        local first = assert(require("scrollbar.renderer").get_state(source_win))
        local first_group = require("scrollbar.scheduler").status().augroup_id

        scrollbar.setup({ scrollbar = config })
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
    -- No built-in provider uses manager-owned refresh, so the manager
    -- registers no dispatch autocmds by default (they would be a per-keystroke
    -- registry walk that cannot dispatch anything).
    expect.equality(result.provider_manager_autocmds, 0)
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

        require("scrollbar").setup({ scrollbar = config })
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

        require("scrollbar").setup({ scrollbar = config })
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
        scrollbar.setup({ scrollbar = config })
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
        local manager_refreshes = 0
        local manager_window_refreshes = 0
        providers.register({
            name = "custom",
            refresh_owner = { buffer = "provider", window = "provider" },
            refresh = function()
                refreshes = refreshes + 1
                return { { line = refreshes, type = "Misc" } }
            end,
            refresh_window = function()
                window_refreshes = window_refreshes + 1
                return { { line = window_refreshes, type = "Misc" } }
            end,
        })
        providers.register({
            name = "manager-custom",
            refresh_owner = { buffer = "manager", window = "manager" },
            refresh = function()
                manager_refreshes = manager_refreshes + 1
                return { { line = manager_refreshes, type = "Misc" } }
            end,
            refresh_window = function()
                manager_window_refreshes = manager_window_refreshes + 1
                return { { line = manager_window_refreshes, type = "Misc" } }
            end,
        })

        local scrollbar = require("scrollbar")
        scrollbar.setup({ scrollbar = config })
        require("scrollbar.scheduler").flush()
        refreshes = 0
        window_refreshes = 0
        manager_refreshes = 0
        manager_window_refreshes = 0
        vim.cmd("ScrollbarRefresh")
        local queued = require("scrollbar.scheduler").status().dirty_windows
        require("scrollbar.scheduler").flush()
        local bufnr = vim.api.nvim_get_current_buf()
        return {
            refreshes = refreshes,
            window_refreshes = window_refreshes,
            manager_refreshes = manager_refreshes,
            manager_window_refreshes = manager_window_refreshes,
            marks = require("scrollbar.store").get(bufnr).custom,
            manager_marks = require("scrollbar.store").get(bufnr)["manager-custom"],
            queued = #queued,
            source_windows = #require("scrollbar.renderer").source_windows(bufnr),
        }
    end, root_config())

    expect.equality(result.refreshes, 1)
    expect.equality(result.window_refreshes, 2)
    expect.equality(result.manager_refreshes, 1)
    expect.equality(result.manager_window_refreshes, 2)
    expect.equality(result.marks, { { line = 1, type = "Misc" } })
    expect.equality(result.manager_marks, { { line = 1, type = "Misc" } })
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

        require("scrollbar").setup({ scrollbar = config })
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
