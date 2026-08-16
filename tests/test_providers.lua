local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.renderer"] = nil
            package.loaded["scrollbar.store"] = nil
            package.loaded["scrollbar.providers"] = nil
            require("scrollbar.config").set({
                scrollbar = {
                    marks = {
                        Custom = { text = "!", priority = 1, highlight = "WarningMsg" },
                    },
                },
            })
        end,
        post_case = function()
            local providers = package.loaded["scrollbar.providers"]
            if providers then
                providers.dispose()
            end
        end,
    },
})

local function new_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)
    return bufnr
end

local function show_buffer(bufnr)
    local previous = vim.api.nvim_get_current_win()
    vim.cmd("botright new")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    MiniTest.finally(function()
        if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_close(winid, true)
        end
        if vim.api.nvim_win_is_valid(previous) then
            vim.api.nvim_set_current_win(previous)
        end
    end)
    return winid
end

local function capture_notifications()
    local notifications = {}
    local original = vim.notify
    rawset(vim, "notify", function(message, level)
        table.insert(notifications, { message = message, level = level })
    end)
    MiniTest.finally(function()
        rawset(vim, "notify", original)
    end)
    return notifications
end

local function expect_registration_error(provider, message)
    local ok, err = pcall(require("scrollbar.providers").register, provider)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):find(message, 1, true), nil)
end

T["validates refresh ownership registration shapes"] = function()
    local providers = require("scrollbar.providers")
    local refresh = function()
        return {}
    end

    local valid = {
        { name = "no-refresh", private_option = true },
        { name = "buffer-manager", refresh_owner = { buffer = "manager" }, refresh = refresh },
        { name = "buffer-provider", refresh_owner = { buffer = "provider" }, refresh = refresh },
        { name = "window-manager", refresh_owner = { window = "manager" }, refresh_window = refresh },
        { name = "window-provider", refresh_owner = { window = "provider" }, refresh_window = refresh },
        {
            name = "dual-manager",
            refresh_owner = { buffer = "manager", window = "manager" },
            refresh = refresh,
            refresh_window = refresh,
        },
        {
            name = "dual-mixed",
            refresh_owner = { buffer = "manager", window = "provider" },
            refresh = refresh,
            refresh_window = refresh,
        },
        {
            name = "dual-mixed-reverse",
            refresh_owner = { buffer = "provider", window = "manager" },
            refresh = refresh,
            refresh_window = refresh,
        },
        {
            name = "dual-provider",
            refresh_owner = { buffer = "provider", window = "provider" },
            refresh = refresh,
            refresh_window = refresh,
        },
    }
    for _, provider in ipairs(valid) do
        providers.register(provider)
        expect.equality(providers.get(provider.name), provider)
    end

    expect_registration_error(
        { name = "non-table", refresh_owner = "manager", refresh = refresh },
        "provider 'non-table' refresh_owner must be a table"
    )
    expect_registration_error(
        { name = "unknown-scope", refresh_owner = { buffers = "manager" }, refresh = refresh },
        "provider 'unknown-scope' refresh_owner has unknown scope 'buffers'"
    )
    local table_scope = {}
    expect_registration_error(
        { name = "non-string-scope", refresh_owner = { [table_scope] = "manager" }, refresh = refresh },
        "provider 'non-string-scope' refresh_owner has unknown scope '<table>'"
    )
    expect_registration_error(
        { name = "multiple-scopes", refresh_owner = { z = "manager", a = "manager" }, refresh = refresh },
        "provider 'multiple-scopes' refresh_owner has unknown scope 'a'"
    )
    expect_registration_error(
        { name = "invalid-owner", refresh_owner = { buffer = "plugin" }, refresh = refresh },
        "provider 'invalid-owner' refresh_owner.buffer must be 'manager' or 'provider'"
    )
    expect_registration_error(
        { name = "invalid-window-owner", refresh_owner = { window = false }, refresh_window = refresh },
        "provider 'invalid-window-owner' refresh_owner.window must be 'manager' or 'provider'"
    )
    expect_registration_error(
        { name = "missing-buffer", refresh = refresh },
        "provider 'missing-buffer' refresh requires refresh_owner.buffer"
    )
    expect_registration_error(
        { name = "missing-window", refresh_window = refresh },
        "provider 'missing-window' refresh_window requires refresh_owner.window"
    )
    expect_registration_error({
        name = "partial-dual",
        refresh_owner = { buffer = "manager" },
        refresh = refresh,
        refresh_window = refresh,
    }, "provider 'partial-dual' refresh_window requires refresh_owner.window")
    expect_registration_error({
        name = "partial-dual-reverse",
        refresh_owner = { window = "provider" },
        refresh = refresh,
        refresh_window = refresh,
    }, "provider 'partial-dual-reverse' refresh requires refresh_owner.buffer")
    expect_registration_error(
        { name = "extra-buffer", refresh_owner = { buffer = "manager" } },
        "provider 'extra-buffer' refresh_owner.buffer requires refresh"
    )
    expect_registration_error(
        { name = "extra-window", refresh_owner = { window = "provider" } },
        "provider 'extra-window' refresh_owner.window requires refresh_window"
    )

    for _, field in ipairs({ "setup", "refresh", "refresh_window", "dispose" }) do
        local provider = { name = "invalid-" .. field, [field] = true }
        expect_registration_error(provider, "provider 'invalid-" .. field .. "' " .. field .. " must be a function")
    end
end

T["validates targets and minimap refresh ownership shapes"] = function()
    local providers = require("scrollbar.providers")
    local refresh = function()
        return {}
    end
    local private = { enabled = true }
    local valid = {
        { name = "legacy-private", private_option = private },
        { name = "scrollbar-target", targets = { scrollbar = true } },
        { name = "minimap-target", targets = { minimap = true } },
        { name = "dual-target", targets = { scrollbar = true, minimap = true } },
        {
            name = "minimap-buffer-manager",
            targets = { minimap = true },
            refresh_owner = { minimap_buffer = "manager" },
            refresh_minimap = refresh,
        },
        {
            name = "minimap-window-provider",
            targets = { minimap = true },
            refresh_owner = { minimap_window = "provider" },
            refresh_minimap_window = refresh,
        },
    }
    for _, provider in ipairs(valid) do
        providers.register(provider)
        expect.equality(providers.get(provider.name), provider)
    end
    local legacy_private = assert(providers.get("legacy-private"))
    expect.equality(rawget(legacy_private, "private_option"), private)

    expect_registration_error(
        { name = "targets-scalar", targets = true },
        "provider 'targets-scalar' targets must be a table"
    )
    expect_registration_error(
        { name = "targets-empty", targets = {} },
        "provider 'targets-empty' targets must enable at least one target"
    )
    expect_registration_error(
        { name = "targets-false", targets = { scrollbar = false, minimap = false } },
        "provider 'targets-false' targets must enable at least one target"
    )
    expect_registration_error(
        { name = "targets-unknown", targets = { z = true, a = true } },
        "provider 'targets-unknown' targets has unknown target 'a'"
    )
    expect_registration_error(
        { name = "targets-scrollbar-type", targets = { scrollbar = 1 } },
        "provider 'targets-scrollbar-type' targets.scrollbar must be a boolean"
    )
    expect_registration_error(
        { name = "targets-minimap-type", targets = { minimap = "yes" } },
        "provider 'targets-minimap-type' targets.minimap must be a boolean"
    )
    expect_registration_error({
        name = "unknown-minimap-scope",
        refresh_owner = { minimap_buffers = "manager" },
        refresh = refresh,
    }, "provider 'unknown-minimap-scope' refresh_owner has unknown scope 'minimap_buffers'")
    expect_registration_error({
        name = "missing-minimap-buffer-owner",
        targets = { minimap = true },
        refresh_minimap = refresh,
    }, "provider 'missing-minimap-buffer-owner' refresh_minimap requires refresh_owner.minimap_buffer")
    expect_registration_error({
        name = "missing-minimap-window-owner",
        targets = { minimap = true },
        refresh_minimap_window = refresh,
    }, "provider 'missing-minimap-window-owner' refresh_minimap_window requires refresh_owner.minimap_window")
    expect_registration_error({
        name = "extra-minimap-buffer-owner",
        targets = { minimap = true },
        refresh_owner = { minimap_buffer = "manager" },
    }, "provider 'extra-minimap-buffer-owner' refresh_owner.minimap_buffer requires refresh_minimap")
    expect_registration_error({
        name = "extra-minimap-window-owner",
        targets = { minimap = true },
        refresh_owner = { minimap_window = "provider" },
    }, "provider 'extra-minimap-window-owner' refresh_owner.minimap_window requires refresh_minimap_window")
    expect_registration_error({
        name = "scrollbar-only-minimap-buffer",
        refresh_owner = { minimap_buffer = "manager" },
        refresh_minimap = refresh,
    }, "provider 'scrollbar-only-minimap-buffer' refresh_minimap requires targets.minimap")
    expect_registration_error({
        name = "scrollbar-only-minimap-window",
        targets = { scrollbar = true },
        refresh_owner = { minimap_window = "manager" },
        refresh_minimap_window = refresh,
    }, "provider 'scrollbar-only-minimap-window' refresh_minimap_window requires targets.minimap")

    for _, field in ipairs({ "refresh_minimap", "refresh_minimap_window" }) do
        expect_registration_error({
            name = "invalid-" .. field,
            targets = { minimap = true },
            [field] = true,
        }, "provider 'invalid-" .. field .. "' " .. field .. " must be a function")
    end
end

T["registers before setup and initially refreshes eligible loaded buffers"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one", "two" })
    local ignored = new_buffer({ "ignored" })
    local calls = { setup = 0, refresh = {} }

    providers.register({
        name = "custom",
        refresh_owner = { buffer = "provider" },
        setup = function()
            calls.setup = calls.setup + 1
        end,
        refresh = function(bufnr)
            table.insert(calls.refresh, bufnr)
            return { { line = 1, type = "Custom" } }
        end,
    })

    expect.equality(calls, { setup = 0, refresh = {} })

    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    expect.equality(calls, { setup = 1, refresh = { target } })
    expect.equality(require("scrollbar.store").get(target), {
        custom = { { line = 1, type = "Custom" } },
    })
    expect.equality(require("scrollbar.store").get(ignored), {})
end

T["keeps providers without targets scrollbar-only"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local calls = { setup = 0, refresh = 0 }
    local context

    providers.register({
        name = "legacy-target",
        refresh_owner = { buffer = "provider" },
        setup = function(provider_context)
            calls.setup = calls.setup + 1
            context = provider_context
        end,
        refresh = function()
            calls.refresh = calls.refresh + 1
            return {}
        end,
    })
    providers.setup({
        consumer_policies = {
            scrollbar = {
                is_buffer_eligible = function()
                    return false
                end,
                source_windows = function()
                    return {}
                end,
                is_source_window = function()
                    return false
                end,
            },
            minimap = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function()
                    return {}
                end,
                is_source_window = function()
                    return false
                end,
            },
        },
    })

    expect.equality(calls, { setup = 1, refresh = 0 })
    expect.equality(context.is_buffer_eligible(target), false)
    expect.equality(providers.refresh(target, { consumer = "minimap" }), false)
    expect.equality(calls.refresh, 0)
end

T["registers after setup and immediately sets up and refreshes"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local calls = {}

    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })
    providers.register({
        name = "late",
        refresh_owner = { buffer = "provider" },
        setup = function()
            table.insert(calls, "setup")
        end,
        refresh = function(bufnr)
            table.insert(calls, "refresh:" .. bufnr)
            return { { line = 0, type = "Custom" } }
        end,
    })

    expect.equality(calls, { "setup", "refresh:" .. target })
    expect.equality(require("scrollbar.store").get(target), {
        late = { { line = 0, type = "Custom" } },
    })
end

T["activates custom minimap targets and publishes manager-owned outputs"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two" })
    local winid = show_buffer(target)
    local calls = { setup = 0, buffer = 0, window = 0 }

    providers.register({
        name = "minimap-manager",
        targets = { minimap = true },
        refresh_owner = { minimap_buffer = "manager", minimap_window = "manager" },
        setup = function()
            calls.setup = calls.setup + 1
        end,
        refresh_minimap = function(bufnr)
            expect.equality(bufnr, target)
            calls.buffer = calls.buffer + 1
            return { { line = 1, start_col = 0, end_col = 2, highlight = "Search", priority = 4 } }
        end,
        refresh_minimap_window = function(refreshed_win)
            expect.equality(refreshed_win, winid)
            calls.window = calls.window + 1
            return { { line = 1, col = 2, highlight = "Cursor", priority = 7 } }
        end,
    })
    providers.setup({
        consumer_policies = {
            minimap = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function(bufnr)
                    if bufnr == nil or bufnr == target then
                        return { winid }
                    end
                    return {}
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
            },
        },
    })

    expect.equality(calls, { setup = 1, buffer = 1, window = 1 })
    expect.equality(store.get(target), {})
    expect.equality(store.get_minimap_spans(target), {
        ["minimap-manager"] = {
            { line = 1, start_col = 0, end_col = 2, highlight = "Search", priority = 4 },
        },
    })
    expect.equality(store.get_window(winid), {})
    expect.equality(store.get_minimap_points(winid), {
        ["minimap-manager"] = {
            { line = 1, col = 2, highlight = "Cursor", priority = 7 },
        },
    })

    vim.api.nvim_exec_autocmds("TextChanged", { buffer = target })
    vim.api.nvim_exec_autocmds("WinEnter", { buffer = target })
    expect.equality(calls, { setup = 1, buffer = 2, window = 2 })
end

T["scopes provider-owned publication and policy queries to requested consumer unions"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local scrollbar_buffer = new_buffer({ "scrollbar" })
    local minimap_buffer = new_buffer({ "minimap" })
    local scrollbar_window = show_buffer(scrollbar_buffer)
    local minimap_window = show_buffer(minimap_buffer)
    local context

    providers.register({
        name = "dual-context",
        targets = { scrollbar = true, minimap = true },
        setup = function(provider_context)
            context = provider_context
        end,
    })
    providers.setup({
        consumer_policies = {
            scrollbar = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == scrollbar_buffer
                end,
                source_windows = function(bufnr)
                    if bufnr == nil or bufnr == scrollbar_buffer then
                        return { scrollbar_window }
                    end
                    return {}
                end,
                is_source_window = function(winid)
                    return winid == scrollbar_window
                end,
            },
            minimap = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == minimap_buffer
                end,
                source_windows = function(bufnr)
                    if bufnr == nil or bufnr == minimap_buffer then
                        return { minimap_window }
                    end
                    return {}
                end,
                is_source_window = function(winid)
                    return winid == minimap_window
                end,
            },
        },
    })

    expect.equality(context.source_windows(), { scrollbar_window, minimap_window })
    expect.equality(context.is_buffer_eligible(scrollbar_buffer), true)
    expect.equality(context.is_buffer_eligible(minimap_buffer), true)
    expect.equality(context.is_source_window(scrollbar_window), true)
    expect.equality(context.is_source_window(minimap_window), true)

    expect.equality(context.set_marks(scrollbar_buffer, { { line = 0, type = "Custom", text = "s" } }), true)
    expect.equality(context.set_marks(minimap_buffer, { { line = 0, type = "Custom", text = "m" } }), true)
    expect.equality(
        context.set_minimap_spans(scrollbar_buffer, {
            { line = 0, start_col = 0, end_col = 1, highlight = "Search", priority = 1 },
        }),
        false
    )
    expect.equality(
        context.set_minimap_spans(minimap_buffer, {
            { line = 0, start_col = 0, end_col = 1, highlight = "Search", priority = 1 },
        }),
        true
    )
    expect.equality(context.set_window_marks(scrollbar_window, { { line = 0, type = "Custom" } }), true)
    expect.equality(context.set_window_marks(minimap_window, { { line = 0, type = "Custom" } }), true)
    expect.equality(
        context.set_minimap_points(scrollbar_window, {
            { line = 0, col = 0, highlight = "Cursor", priority = 1 },
        }),
        false
    )
    expect.equality(
        context.set_minimap_points(minimap_window, {
            { line = 0, col = 0, highlight = "Cursor", priority = 1 },
        }),
        true
    )

    expect.equality(store.get(scrollbar_buffer)["dual-context"], { { line = 0, type = "Custom", text = "s" } })
    expect.equality(store.get(minimap_buffer)["dual-context"], { { line = 0, type = "Custom", text = "m" } })
    expect.equality(store.get_minimap_spans(scrollbar_buffer), {})
    expect.equality(store.get_minimap_spans(minimap_buffer)["dual-context"], {
        { line = 0, start_col = 0, end_col = 1, highlight = "Search", priority = 1 },
    })
    expect.equality(store.get_window(scrollbar_window)["dual-context"], { { line = 0, type = "Custom" } })
    expect.equality(store.get_window(minimap_window)["dual-context"], { { line = 0, type = "Custom" } })
    expect.equality(store.get_minimap_points(scrollbar_window), {})
    expect.equality(store.get_minimap_points(minimap_window)["dual-context"], {
        { line = 0, col = 0, highlight = "Cursor", priority = 1 },
    })

    expect.equality(context.clear_marks(), true)
    expect.equality(context.clear_window_marks(), true)
    expect.equality(store.get(scrollbar_buffer), {})
    expect.equality(store.get(minimap_buffer), {})
    expect.no_equality(store.get_minimap_spans(minimap_buffer)["dual-context"], nil)
    expect.no_equality(store.get_minimap_points(minimap_window)["dual-context"], nil)
    expect.equality(context.clear_minimap_spans(), true)
    expect.equality(context.clear_minimap_points(), true)
    expect.equality(store.get_minimap_spans(minimap_buffer), {})
    expect.equality(store.get_minimap_points(minimap_window), {})
end

T["uses the effective plan only for manager-owned builtins"] = function()
    local providers = require("scrollbar.providers")
    local scrollbar_buffer = new_buffer({ "scrollbar" })
    local minimap_buffer = new_buffer({ "minimap" })
    local calls = { builtin_setup = 0, builtin_refresh = {}, custom_setup = 0 }
    local policies = {
        scrollbar = {
            is_buffer_eligible = function(bufnr)
                return bufnr == scrollbar_buffer
            end,
            source_windows = function()
                return {}
            end,
            is_source_window = function()
                return false
            end,
        },
        minimap = {
            is_buffer_eligible = function(bufnr)
                return bufnr == minimap_buffer
            end,
            source_windows = function()
                return {}
            end,
            is_source_window = function()
                return false
            end,
        },
    }

    providers._register_builtin({
        name = "search",
        targets = { scrollbar = true, minimap = true },
        refresh_owner = { buffer = "provider" },
        setup = function(context)
            calls.builtin_setup = calls.builtin_setup + 1
            expect.equality(context.config.providers.search, { backend = "sync" })
        end,
        refresh = function(bufnr)
            table.insert(calls.builtin_refresh, bufnr)
            return {}
        end,
    })
    providers.register({
        name = "custom-planned",
        targets = { minimap = true },
        setup = function()
            calls.custom_setup = calls.custom_setup + 1
        end,
    })
    providers.setup({
        provider_plan = {
            search = {
                consumers = { scrollbar = false, minimap = true },
                options = { backend = "sync" },
                targets = { scrollbar = true, minimap = true },
                execution = "parent",
            },
            ["custom-planned"] = {
                consumers = { scrollbar = false, minimap = false },
                options = false,
                targets = { scrollbar = false, minimap = true },
                execution = "parent",
            },
        },
        consumer_policies = policies,
    })

    expect.equality(calls, {
        builtin_setup = 1,
        builtin_refresh = { minimap_buffer },
        custom_setup = 1,
    })

    providers.setup({
        provider_plan = {
            search = {
                consumers = { scrollbar = false, minimap = false },
                options = false,
                targets = { scrollbar = true, minimap = true },
                execution = "parent",
            },
        },
        consumer_policies = policies,
    })
    expect.equality(calls, {
        builtin_setup = 1,
        builtin_refresh = { minimap_buffer },
        custom_setup = 2,
    })
end

T["filters manual refreshes by consumer and channel without changing old signatures"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local calls = { marks = 0, spans = 0, window_marks = 0, points = 0 }

    providers.register({
        name = "filtered",
        targets = { scrollbar = true, minimap = true },
        refresh_owner = {
            buffer = "provider",
            minimap_buffer = "provider",
            window = "provider",
            minimap_window = "provider",
        },
        refresh = function()
            calls.marks = calls.marks + 1
            return {}
        end,
        refresh_minimap = function()
            calls.spans = calls.spans + 1
            return {}
        end,
        refresh_window = function()
            calls.window_marks = calls.window_marks + 1
            return {}
        end,
        refresh_minimap_window = function()
            calls.points = calls.points + 1
            return {}
        end,
    })
    providers.setup({
        consumer_policies = {
            scrollbar = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
            },
            minimap = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
            },
        },
    })
    expect.equality(calls, { marks = 1, spans = 1, window_marks = 1, points = 1 })
    calls = { marks = 0, spans = 0, window_marks = 0, points = 0 }

    expect.equality(providers.refresh(target), true)
    expect.equality(calls, { marks = 1, spans = 1, window_marks = 0, points = 0 })
    calls.marks, calls.spans = 0, 0
    expect.equality(providers.refresh(target, { consumer = "scrollbar" }), true)
    expect.equality(calls, { marks = 1, spans = 0, window_marks = 0, points = 0 })
    calls.marks, calls.spans = 0, 0
    expect.equality(providers.refresh(target, { consumer = "minimap" }), true)
    expect.equality(calls, { marks = 1, spans = 1, window_marks = 0, points = 0 })
    calls.marks, calls.spans = 0, 0
    expect.equality(providers.refresh(target, { channel = "minimap_spans" }), true)
    expect.equality(calls, { marks = 0, spans = 1, window_marks = 0, points = 0 })
    calls.marks, calls.spans = 0, 0
    expect.equality(providers.refresh(target, { consumer = "scrollbar", channel = "minimap_spans" }), false)
    expect.equality(calls, { marks = 0, spans = 0, window_marks = 0, points = 0 })

    expect.equality(providers.refresh_window(winid), true)
    expect.equality(calls, { marks = 0, spans = 0, window_marks = 1, points = 1 })
    calls.window_marks, calls.points = 0, 0
    expect.equality(providers.refresh_window(winid, { consumer = "scrollbar" }), true)
    expect.equality(calls, { marks = 0, spans = 0, window_marks = 1, points = 0 })
    calls.window_marks, calls.points = 0, 0
    expect.equality(providers.refresh_window(winid, { consumer = "minimap" }), true)
    expect.equality(calls, { marks = 0, spans = 0, window_marks = 1, points = 1 })
    calls.window_marks, calls.points = 0, 0
    expect.equality(providers.refresh_window(winid, { channel = "minimap_points" }), true)
    expect.equality(calls, { marks = 0, spans = 0, window_marks = 0, points = 1 })
    calls.window_marks, calls.points = 0, 0
    expect.equality(providers.refresh_window(winid, { consumer = "scrollbar", channel = "minimap_points" }), false)
    expect.equality(calls, { marks = 0, spans = 0, window_marks = 0, points = 0 })
end

T["applies consumer eligibility to consumer-filtered mark refreshes"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local scrollbar_buffer = new_buffer({ "scrollbar" })
    local minimap_buffer = new_buffer({ "minimap" })
    local scrollbar_window = show_buffer(scrollbar_buffer)
    local minimap_window = show_buffer(minimap_buffer)
    local calls = { buffers = {}, windows = {} }

    providers.register({
        name = "consumer-policy",
        targets = { scrollbar = true, minimap = true },
        refresh_owner = { buffer = "provider", window = "provider" },
        refresh = function(bufnr)
            table.insert(calls.buffers, bufnr)
            return {}
        end,
        refresh_window = function(winid)
            table.insert(calls.windows, winid)
            return {}
        end,
    })
    providers.setup({
        consumer_policies = {
            scrollbar = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == scrollbar_buffer
                end,
                source_windows = function()
                    return { scrollbar_window }
                end,
                is_source_window = function(winid)
                    return winid == scrollbar_window
                end,
            },
            minimap = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == minimap_buffer
                end,
                source_windows = function()
                    return { minimap_window }
                end,
                is_source_window = function(winid)
                    return winid == minimap_window
                end,
            },
        },
    })
    calls = { buffers = {}, windows = {} }
    store.set("consumer-policy", minimap_buffer, { { line = 0, type = "Custom" } })
    store.set_window("consumer-policy", minimap_window, { { line = 0, type = "Custom" } })

    expect.equality(providers.refresh(minimap_buffer, { consumer = "scrollbar", channel = "marks" }), false)
    expect.equality(store.get(minimap_buffer)["consumer-policy"], { { line = 0, type = "Custom" } })
    expect.equality(providers.refresh(minimap_buffer, { consumer = "minimap", channel = "marks" }), true)
    expect.equality(calls.buffers, { minimap_buffer })
    expect.equality(providers.refresh_window(minimap_window, { consumer = "scrollbar", channel = "marks" }), false)
    expect.equality(store.get_window(minimap_window)["consumer-policy"], { { line = 0, type = "Custom" } })
    expect.equality(providers.refresh_window(minimap_window, { consumer = "minimap", channel = "marks" }), true)
    expect.equality(calls.windows, { minimap_window })
end

T["refreshes window providers initially, manually, and on disposal"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two" })
    local winid = show_buffer(target)
    local calls = {}
    local invalidated = {}
    local line = 0

    providers.register({
        name = "window",
        refresh_owner = { window = "manager" },
        refresh_window = function(refreshed_win)
            table.insert(calls, refreshed_win)
            return { { line = line, type = "Custom" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        source_windows = function(bufnr)
            if bufnr == nil or bufnr == target then
                return { winid }
            end
            return {}
        end,
        is_source_window = function(source_win)
            return source_win == winid
        end,
        invalidate_window = function(changed_win)
            table.insert(invalidated, changed_win)
        end,
    })

    expect.equality(calls, { winid })
    expect.equality(invalidated, { winid })
    expect.equality(store.get_window(winid), {
        window = { { line = 0, type = "Custom" } },
    })

    invalidated = {}
    providers.refresh_window(winid)
    expect.equality(calls, { winid, winid })
    expect.equality(invalidated, {})

    line = 1
    providers.refresh_window(winid)
    expect.equality(invalidated, { winid })
    expect.equality(store.get_window(winid), {
        window = { { line = 1, type = "Custom" } },
    })

    invalidated = {}
    expect.equality(providers.unregister("window"), true)
    expect.equality(store.get_window(winid), {})
    expect.equality(invalidated, { winid })
end

T["rejects duplicate provider names without replacing the original"] = function()
    local providers = require("scrollbar.providers")
    local original = { name = "duplicate" }
    providers.register(original)

    local ok, err = pcall(providers.register, { name = "duplicate" })

    expect.equality(ok, false)
    expect.no_equality(tostring(err):match("provider 'duplicate' is already registered"), nil)
    expect.equality(providers.unregister("duplicate"), true)
    expect.equality(providers.unregister("duplicate"), false)
end

T["unregister disposes resources, clears marks, and invalidates changed buffers"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local invalidated = {}
    local group
    local disposed = 0
    local cleaned = 0

    providers.register({
        name = "owned",
        refresh_owner = { buffer = "manager" },
        setup = function(context)
            group = context.create_augroup("events")
            vim.api.nvim_create_autocmd(
                "User",
                { group = group, pattern = "ScrollbarProviderTest", callback = function() end }
            )
            context.add_cleanup(function()
                cleaned = cleaned + 1
            end)
        end,
        refresh = function()
            return { { line = 0, type = "Custom" } }
        end,
        dispose = function()
            disposed = disposed + 1
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })
    invalidated = {}

    expect.equality(providers.unregister("owned"), true)

    expect.equality(disposed, 1)
    expect.equality(cleaned, 1)
    expect.equality(require("scrollbar.store").get(target), {})
    expect.equality(invalidated, { target })
    expect.equality(pcall(vim.api.nvim_get_autocmds, { group = group }), false)
end

T["isolates setup failures and releases partially created resources"] = function()
    local notifications = capture_notifications()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local failed_group
    local failed_refreshes = { buffer = 0, window = 0 }
    local good_setup = 0

    providers.register({
        name = "bad-setup",
        refresh_owner = { buffer = "manager", window = "manager" },
        setup = function(context)
            failed_group = context.create_augroup("partial")
            context.set_window_marks(winid, { { line = 0, type = "Custom" } })
            vim.api.nvim_exec_autocmds("BufEnter", { buffer = target })
            vim.api.nvim_exec_autocmds("WinEnter", { buffer = target })
            error("setup exploded")
        end,
        refresh = function()
            failed_refreshes.buffer = failed_refreshes.buffer + 1
            return {}
        end,
        refresh_window = function()
            failed_refreshes.window = failed_refreshes.window + 1
            return {}
        end,
    })
    providers.register({
        name = "good-setup",
        refresh_owner = { buffer = "provider" },
        setup = function()
            good_setup = good_setup + 1
        end,
        refresh = function()
            return { { line = 0, type = "Custom" } }
        end,
    })

    local options = {
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        source_windows = function()
            return { winid }
        end,
        is_source_window = function(source_win)
            return source_win == winid
        end,
    }
    providers.setup(options)

    expect.equality(good_setup, 1)
    expect.equality(require("scrollbar.store").get(target), {
        ["good-setup"] = { { line = 0, type = "Custom" } },
    })
    expect.equality(require("scrollbar.store").get_window(winid), {})
    expect.equality(failed_refreshes, { buffer = 0, window = 0 })
    expect.equality(pcall(vim.api.nvim_get_autocmds, { group = failed_group }), false)
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1].message:match("provider 'bad%-setup' setup failed.*setup exploded"), nil)

    providers.setup(options)
    expect.equality(good_setup, 2)
    expect.equality(#notifications, 1)
end

T["clears refresh-only window marks when the window becomes ineligible"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one" })
    local excluded = new_buffer({ "excluded" })
    local winid = show_buffer(target)
    local invalidated = {}

    providers.register({
        name = "window-lifecycle",
        refresh_owner = { window = "manager" },
        setup = function() end,
        refresh_window = function()
            return { { line = 0, type = "Custom" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        source_windows = function(bufnr)
            if bufnr == nil or bufnr == target then
                return { winid }
            end
            return {}
        end,
        is_source_window = function(source_win)
            return source_win == winid and vim.api.nvim_win_get_buf(source_win) == target
        end,
        invalidate_window = function(changed_win)
            table.insert(invalidated, changed_win)
        end,
    })
    expect.equality(store.get_window(winid)["window-lifecycle"], { { line = 0, type = "Custom" } })

    invalidated = {}
    vim.api.nvim_win_set_buf(winid, excluded)
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = excluded })

    expect.equality(store.get_window(winid), {})
    expect.equality(invalidated, { winid })
end

T["clears refresh-only marks before an eligible window changes buffers"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local first = new_buffer({ "one" })
    local second = new_buffer({ "two" })
    local winid = show_buffer(first)

    providers.register({
        name = "window-association",
        refresh_owner = { window = "manager" },
        refresh_window = function(refreshed_win)
            if vim.api.nvim_win_get_buf(refreshed_win) == first then
                return { { line = 0, type = "Custom" } }
            end
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        source_windows = function(bufnr)
            if bufnr == nil or bufnr == first or bufnr == second then
                return { winid }
            end
            return {}
        end,
        is_source_window = function(source_win)
            return source_win == winid
        end,
    })
    expect.equality(store.get_window(winid)["window-association"], { { line = 0, type = "Custom" } })

    vim.api.nvim_win_set_buf(winid, second)
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = second })

    expect.equality(store.get_window(winid), {})
end

T["clears only a failing refresher and resets warning suppression after recovery"] = function()
    local notifications = capture_notifications()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local should_fail = false

    providers.register({
        name = "bad-refresh",
        refresh_owner = { buffer = "manager" },
        refresh = function()
            if should_fail then
                error("refresh exploded")
            end
            return { { line = 0, type = "Custom", text = "b" } }
        end,
    })
    providers.register({
        name = "good-refresh",
        refresh_owner = { buffer = "manager" },
        refresh = function()
            return { { line = 0, type = "Custom", text = "g" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    should_fail = true
    providers.refresh(target)
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target), {
        ["good-refresh"] = { { line = 0, type = "Custom", text = "g" } },
    })
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1].message:match("provider 'bad%-refresh' refresh.*refresh exploded"), nil)

    should_fail = false
    providers.refresh(target)
    should_fail = true
    providers.refresh(target)
    expect.equality(#notifications, 2)
end

T["isolates failing window refreshes and resets warnings after recovery"] = function()
    local notifications = capture_notifications()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local should_fail = false

    providers.register({
        name = "bad-window-refresh",
        refresh_owner = { window = "manager" },
        refresh_window = function()
            if should_fail then
                error("window refresh exploded")
            end
            return { { line = 0, type = "Custom" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        source_windows = function()
            return { winid }
        end,
        is_source_window = function(source_win)
            return source_win == winid
        end,
    })

    should_fail = true
    providers.refresh_window(winid)
    providers.refresh_window(winid)
    expect.equality(store.get_window(winid), {})
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1].message:match("window refresh.*window refresh exploded"), nil)

    should_fail = false
    providers.refresh_window(winid)
    should_fail = true
    providers.refresh_window(winid)
    expect.equality(#notifications, 2)
end

T["isolates minimap callback failures from other providers and channels"] = function()
    local notifications = capture_notifications()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local fail = { marks = false, spans = false, points = false }

    providers.register({
        name = "multi-channel",
        targets = { scrollbar = true, minimap = true },
        refresh_owner = {
            buffer = "provider",
            minimap_buffer = "provider",
            minimap_window = "provider",
        },
        refresh = function()
            if fail.marks then
                error("marks exploded")
            end
            return { { line = 0, type = "Custom", text = "m" } }
        end,
        refresh_minimap = function()
            if fail.spans then
                error("spans exploded")
            end
            return { { line = 0, start_col = 0, end_col = 1, highlight = "Search", priority = 1 } }
        end,
        refresh_minimap_window = function()
            if fail.points then
                error("points exploded")
            end
            return { { line = 0, col = 0, highlight = "Cursor", priority = 1 } }
        end,
    })
    providers.register({
        name = "healthy-minimap",
        targets = { minimap = true },
        refresh_owner = { minimap_buffer = "provider", minimap_window = "provider" },
        refresh_minimap = function()
            return { { line = 0, start_col = 0, end_col = 1, highlight = "Visual", priority = 2 } }
        end,
        refresh_minimap_window = function()
            return { { line = 0, col = 0, highlight = "Visual", priority = 2 } }
        end,
    })
    providers.setup({
        consumer_policies = {
            scrollbar = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
            },
            minimap = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
            },
        },
    })

    fail.spans = true
    fail.points = true
    expect.equality(providers.refresh(target), true)
    expect.equality(providers.refresh_window(winid), true)
    expect.no_equality(store.get(target)["multi-channel"], nil)
    expect.equality(store.get_minimap_spans(target)["multi-channel"], nil)
    expect.no_equality(store.get_minimap_spans(target)["healthy-minimap"], nil)
    expect.equality(store.get_minimap_points(winid)["multi-channel"], nil)
    expect.no_equality(store.get_minimap_points(winid)["healthy-minimap"], nil)
    expect.equality(#notifications, 2)

    fail.spans = false
    fail.points = false
    providers.refresh(target)
    providers.refresh_window(winid)
    fail.marks = true
    providers.refresh(target)
    expect.equality(store.get(target)["multi-channel"], nil)
    expect.no_equality(store.get_minimap_spans(target)["multi-channel"], nil)
    expect.equality(#notifications, 3)
end

T["isolates dispose failures while still releasing resources and marks"] = function()
    local notifications = capture_notifications()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local cleaned = 0

    providers.register({
        name = "bad-dispose",
        refresh_owner = { buffer = "provider" },
        setup = function(context)
            context.add_cleanup(function()
                cleaned = cleaned + 1
            end)
        end,
        refresh = function()
            return { { line = 0, type = "Custom" } }
        end,
        dispose = function()
            error("dispose exploded")
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    expect.equality(providers.unregister("bad-dispose"), true)
    expect.equality(cleaned, 1)
    expect.equality(require("scrollbar.store").get(target), {})
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1].message:match("provider 'bad%-dispose' dispose failed.*dispose exploded"), nil)
end

T["clears every owned channel on unregister and dispose through store events"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local invalidated_buffers = {}
    local invalidated_windows = {}

    local function register(name)
        providers.register({
            name = name,
            targets = { scrollbar = true, minimap = true },
            setup = function(context)
                context.set_marks(target, { { line = 0, type = "Custom" } })
                context.set_minimap_spans(target, {
                    { line = 0, start_col = 0, end_col = 1, highlight = "Search", priority = 1 },
                })
                context.set_window_marks(winid, { { line = 0, type = "Custom" } })
                context.set_minimap_points(winid, {
                    { line = 0, col = 0, highlight = "Cursor", priority = 1 },
                })
            end,
        })
    end

    register("all-channels-unregister")
    providers.setup({
        consumer_policies = {
            scrollbar = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
            },
            minimap = {
                is_buffer_eligible = function(bufnr)
                    return bufnr == target
                end,
                source_windows = function()
                    return { winid }
                end,
                is_source_window = function(source_win)
                    return source_win == winid
                end,
            },
        },
        invalidate_buffer = function(bufnr)
            table.insert(invalidated_buffers, bufnr)
        end,
        invalidate_window = function(source_win)
            table.insert(invalidated_windows, source_win)
        end,
    })
    expect.equality(invalidated_buffers, { target })
    expect.equality(invalidated_windows, { winid })

    invalidated_buffers = {}
    invalidated_windows = {}
    providers.unregister("all-channels-unregister")
    expect.equality(store.get(target), {})
    expect.equality(store.get_minimap_spans(target), {})
    expect.equality(store.get_window(winid), {})
    expect.equality(store.get_minimap_points(winid), {})
    expect.equality(invalidated_buffers, { target })
    expect.equality(invalidated_windows, { winid })

    register("all-channels-dispose")
    invalidated_buffers = {}
    invalidated_windows = {}
    providers.dispose()
    expect.equality(store.get(target), {})
    expect.equality(store.get_minimap_spans(target), {})
    expect.equality(store.get_window(winid), {})
    expect.equality(store.get_minimap_points(winid), {})
    expect.equality(invalidated_buffers, { target })
    expect.equality(invalidated_windows, { winid })
end

T["dispatches automatic buffer refreshes by owner regardless of setup"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local calls = {
        ["manager-no-setup"] = 0,
        ["manager-setup"] = 0,
        ["provider-no-setup"] = 0,
        ["provider-setup"] = 0,
    }

    local function register(name, owner, with_setup)
        local provider = {
            name = name,
            refresh_owner = { buffer = owner },
            refresh = function()
                calls[name] = calls[name] + 1
                return {}
            end,
        }
        if with_setup then
            provider.setup = function() end
        end
        providers.register(provider)
    end
    register("manager-no-setup", "manager", false)
    register("manager-setup", "manager", true)
    register("provider-no-setup", "provider", false)
    register("provider-setup", "provider", true)

    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    vim.api.nvim_exec_autocmds("BufEnter", { buffer = target })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = target })

    expect.equality(calls, {
        ["manager-no-setup"] = 3,
        ["manager-setup"] = 3,
        ["provider-no-setup"] = 1,
        ["provider-setup"] = 1,
    })

    providers.refresh(target)
    expect.equality(calls, {
        ["manager-no-setup"] = 4,
        ["manager-setup"] = 4,
        ["provider-no-setup"] = 2,
        ["provider-setup"] = 2,
    })
end

T["dispatches automatic window refreshes by owner regardless of setup"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local calls = {
        ["manager-no-setup"] = 0,
        ["manager-setup"] = 0,
        ["provider-no-setup"] = 0,
        ["provider-setup"] = 0,
    }

    local function register(name, owner, with_setup)
        local provider = {
            name = name,
            refresh_owner = { window = owner },
            refresh_window = function()
                calls[name] = calls[name] + 1
                return {}
            end,
        }
        if with_setup then
            provider.setup = function() end
        end
        providers.register(provider)
    end
    register("manager-no-setup", "manager", false)
    register("manager-setup", "manager", true)
    register("provider-no-setup", "provider", false)
    register("provider-setup", "provider", true)

    providers.setup({
        source_windows = function()
            return { winid }
        end,
        is_source_window = function(source_win)
            return source_win == winid
        end,
    })
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = target })
    vim.api.nvim_exec_autocmds("WinEnter", { buffer = target })

    expect.equality(calls, {
        ["manager-no-setup"] = 3,
        ["manager-setup"] = 3,
        ["provider-no-setup"] = 1,
        ["provider-setup"] = 1,
    })

    providers.refresh_window(winid)
    expect.equality(calls, {
        ["manager-no-setup"] = 4,
        ["manager-setup"] = 4,
        ["provider-no-setup"] = 2,
        ["provider-setup"] = 2,
    })
end

T["keeps mixed dual-scope refresh ownership independent"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local calls = { buffer = 0, window = 0 }

    providers.register({
        name = "mixed",
        refresh_owner = { buffer = "manager", window = "provider" },
        setup = function() end,
        refresh = function()
            calls.buffer = calls.buffer + 1
            return {}
        end,
        refresh_window = function()
            calls.window = calls.window + 1
            return {}
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        source_windows = function()
            return { winid }
        end,
        is_source_window = function(source_win)
            return source_win == winid
        end,
    })

    expect.equality(calls, { buffer = 1, window = 1 })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = target })
    vim.api.nvim_exec_autocmds("WinEnter", { buffer = target })
    expect.equality(calls, { buffer = 2, window = 1 })

    providers.refresh(target)
    providers.refresh_window(winid)
    expect.equality(calls, { buffer = 3, window = 2 })
end

T["provides isolated config, store, window, and invalidation context operations"] = function()
    local providers = require("scrollbar.providers")
    local root_config = require("scrollbar.config").get()
    local target = new_buffer({ "one" })
    local source_result = { 22, 11 }
    local invalidated_buffers = {}
    local invalidated_windows = {}

    providers.register({
        name = "context",
        setup = function(context)
            context.config.show = false
            context.config.layout.columns[1][1].priority = 99
            expect.equality(rawget(context, "renderer"), nil)

            local windows = context.source_windows(target)
            expect.equality(windows, { 22, 11 })
            windows[1] = 99
            expect.equality(context.is_buffer_eligible(target), true)
            expect.equality(context.is_source_window(22), true)
            expect.equality(context.is_source_window(11), false)

            expect.equality(context.set_marks(target, { { line = 0, type = "Custom" } }), true)
            expect.equality(context.set_marks(target, { { line = 0, type = "Custom" } }), true)
            expect.equality(context.clear_marks(target), true)
            expect.equality(context.clear_marks(target), false)
            context.invalidate_buffer(target)
            context.invalidate_window(22)
        end,
    })
    providers.setup({
        config = root_config,
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        source_windows = function()
            return source_result
        end,
        is_source_window = function(winid)
            return winid == 22
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated_buffers, bufnr)
        end,
        invalidate_window = function(winid)
            table.insert(invalidated_windows, winid)
        end,
    })

    expect.equality(root_config.show, true)
    expect.equality(root_config.layout.width, 1)
    expect.equality(root_config.layout.columns[1][1].kind, "track")
    expect.equality(root_config.layout.columns[1][1].priority, 1)
    expect.equality(rawget(root_config, "preset"), nil)
    expect.equality(rawget(root_config, "presets"), nil)
    expect.equality(source_result, { 22, 11 })
    expect.equality(require("scrollbar.store").get(target), {})
    expect.equality(invalidated_buffers, { target, target, target })
    expect.equality(invalidated_windows, { 22 })
end

T["provides window-scoped store operations through provider contexts"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local invalidated = {}

    providers.register({
        name = "window-context",
        setup = function(context)
            expect.equality(context.set_window_marks(winid, { { line = 0, type = "Custom" } }), true)
            expect.equality(context.set_window_marks(winid, { { line = 0, type = "Custom" } }), true)
            expect.equality(context.clear_window_marks(winid), true)
            expect.equality(context.clear_window_marks(winid), false)
            expect.equality(context.set_window_marks(winid, { { line = 0, type = "Custom" } }), true)
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        source_windows = function()
            return { winid }
        end,
        is_source_window = function(source_win)
            return source_win == winid
        end,
        invalidate_window = function(changed_win)
            table.insert(invalidated, changed_win)
        end,
    })

    expect.equality(store.get_window(winid), {
        ["window-context"] = { { line = 0, type = "Custom" } },
    })
    expect.equality(invalidated, { winid, winid, winid })

    invalidated = {}
    providers.dispose()
    expect.equality(store.get_window(winid), {})
    expect.equality(invalidated, { winid })
end

T["silently clears valid ineligible direct publications before validation"] = function()
    local notifications = capture_notifications()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local buffer_allowed = true
    local window_allowed = true
    local invalidated_buffers = {}
    local invalidated_windows = {}
    local context

    providers.register({
        name = "guarded",
        setup = function(provider_context)
            context = provider_context
            assert(context.set_marks(target, { { line = 0, type = "Custom" } }))
            assert(context.set_window_marks(winid, { { line = 0, type = "Custom" } }))
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target and buffer_allowed
        end,
        is_source_window = function(source_win)
            return source_win == winid and window_allowed
        end,
        source_windows = function()
            return window_allowed and { winid } or {}
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated_buffers, bufnr)
        end,
        invalidate_window = function(source_win)
            table.insert(invalidated_windows, source_win)
        end,
    })
    invalidated_buffers = {}
    invalidated_windows = {}

    buffer_allowed = false
    window_allowed = false
    expect.equality(context.set_marks(target, "malformed"), false)
    expect.equality(context.set_window_marks(winid, "malformed"), false)
    expect.equality(context.set_marks(target, "malformed"), false)
    expect.equality(context.set_window_marks(winid, "malformed"), false)

    expect.equality(store.get(target), {})
    expect.equality(store.get_window(winid), {})
    expect.equality(invalidated_buffers, { target })
    expect.equality(invalidated_windows, { winid })
    expect.equality(notifications, {})

    expect.equality(context.set_marks(999999, {}), false)
    expect.equality(context.set_window_marks(999999, {}), false)
    expect.equality(#notifications, 2)

    buffer_allowed = true
    invalidated_buffers = {}
    expect.equality(context.set_marks(target, { { line = 9, type = "Custom" } }), true)
    expect.equality(store.get(target), { guarded = {} })
    expect.equality(context.set_marks(target, { { line = 9, type = "Custom" } }), true)
    expect.equality(invalidated_buffers, { target })
    expect.equality(context.set_marks(target, "malformed"), false)
    expect.equality(store.get(target), {})
    expect.equality(invalidated_buffers, { target, target })
    expect.equality(#notifications, 3)
end

T["skips pre-ineligible refreshes and rejects eligibility races"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one" })
    local winid = show_buffer(target)
    local buffer_allowed = true
    local window_allowed = true
    local buffer_race = false
    local window_race = false
    local buffer_calls = 0
    local window_calls = 0

    providers.register({
        name = "racing",
        refresh_owner = { buffer = "manager", window = "manager" },
        refresh = function()
            buffer_calls = buffer_calls + 1
            if buffer_race then
                buffer_allowed = false
            end
            return { { line = 0, type = "Custom" } }
        end,
        refresh_window = function()
            window_calls = window_calls + 1
            if window_race then
                window_allowed = false
            end
            return { { line = 0, type = "Custom" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target and buffer_allowed
        end,
        is_source_window = function(source_win)
            return source_win == winid and window_allowed
        end,
        source_windows = function()
            return window_allowed and { winid } or {}
        end,
    })
    expect.equality(buffer_calls, 1)
    expect.equality(window_calls, 1)

    buffer_allowed = false
    window_allowed = false
    expect.equality(providers.refresh(target), false)
    expect.equality(providers.refresh_window(winid), false)
    expect.equality(buffer_calls, 1)
    expect.equality(window_calls, 1)
    expect.equality(store.get(target), {})
    expect.equality(store.get_window(winid), {})

    buffer_allowed = true
    window_allowed = true
    buffer_race = true
    window_race = true
    expect.equality(providers.refresh(target), false)
    expect.equality(providers.refresh_window(winid), false)
    expect.equality(buffer_calls, 2)
    expect.equality(window_calls, 2)
    expect.equality(store.get(target), {})
    expect.equality(store.get_window(winid), {})
end

T["guards private compact search publication with buffer policy"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local compact = require("scrollbar.providers.search_compact")
    local target = new_buffer({ "one", "two" })
    local allowed = true
    local invalidated = {}
    local context

    providers.register({
        name = "search",
        setup = function(provider_context)
            context = provider_context
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target and allowed
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    local encoded = compact.encode({ 0, 1 })
    expect.equality(context._set_search_compact(target, encoded), true)
    expect.equality(context._set_search_compact(target, encoded), true)
    expect.equality(invalidated, { target })
    expect.equality(store._get_snapshot(target).compact_search, encoded)

    allowed = false
    expect.equality(context._set_search_compact(target, encoded), false)
    expect.equality(context._set_search_compact(target, encoded), false)
    expect.equality(invalidated, { target, target })
    expect.equality(store.get(target), {})
    expect.equality(store._get_snapshot(target).compact_search, nil)
end

return T
