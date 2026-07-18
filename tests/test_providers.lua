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
                marks = {
                    Custom = { text = "!", priority = 1, highlight = "WarningMsg" },
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

T["registers before setup and initially refreshes eligible loaded buffers"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one", "two" })
    local ignored = new_buffer({ "ignored" })
    local calls = { setup = 0, refresh = {} }

    providers.register({
        name = "custom",
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
    local good_setup = 0

    providers.register({
        name = "bad-setup",
        setup = function(context)
            failed_group = context.create_augroup("partial")
            context.set_window_marks(winid, { { line = 0, type = "Custom" } })
            error("setup exploded")
        end,
    })
    providers.register({
        name = "good-setup",
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
        refresh = function()
            if should_fail then
                error("refresh exploded")
            end
            return { { line = 0, type = "Custom", text = "b" } }
        end,
    })
    providers.register({
        name = "good-refresh",
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

T["isolates dispose failures while still releasing resources and marks"] = function()
    local notifications = capture_notifications()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local cleaned = 0

    providers.register({
        name = "bad-dispose",
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

T["refreshes refresh-only providers on buffer entry and content changes"] = function()
    local providers = require("scrollbar.providers")
    local target = new_buffer({ "one" })
    local simple_refreshes = 0
    local managed_refreshes = 0

    providers.register({
        name = "simple",
        refresh = function()
            simple_refreshes = simple_refreshes + 1
            return {}
        end,
    })
    providers.register({
        name = "managed",
        setup = function() end,
        refresh = function()
            managed_refreshes = managed_refreshes + 1
            return {}
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    vim.api.nvim_exec_autocmds("BufEnter", { buffer = target })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = target })

    expect.equality(simple_refreshes, 3)
    expect.equality(managed_refreshes, 1)
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
