local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.store"] = nil
            package.loaded["scrollbar.providers"] = nil
            require("scrollbar.config").set({
                marks = {
                    Custom = { text = "!", column = 1, priority = 1, highlight = "WarningMsg" },
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
    local failed_group
    local good_setup = 0

    providers.register({
        name = "bad-setup",
        setup = function(context)
            failed_group = context.create_augroup("partial")
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
    }
    providers.setup(options)

    expect.equality(good_setup, 1)
    expect.equality(require("scrollbar.store").get(target), {
        ["good-setup"] = { { line = 0, type = "Custom" } },
    })
    expect.equality(pcall(vim.api.nvim_get_autocmds, { group = failed_group }), false)
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1].message:match("provider 'bad%-setup' setup failed.*setup exploded"), nil)

    providers.setup(options)
    expect.equality(good_setup, 2)
    expect.equality(#notifications, 1)
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
            context.config.float.width = 99
            expect.equality(rawget(context, "renderer"), nil)

            local windows = context.source_windows(target)
            expect.equality(windows, { 22, 11 })
            windows[1] = 99

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
        invalidate_buffer = function(bufnr)
            table.insert(invalidated_buffers, bufnr)
        end,
        invalidate_window = function(winid)
            table.insert(invalidated_windows, winid)
        end,
    })

    expect.equality(root_config.show, true)
    expect.equality(root_config.float.width, 1)
    expect.equality(source_result, { 22, 11 })
    expect.equality(require("scrollbar.store").get(target), {})
    expect.equality(invalidated_buffers, { target, target, target })
    expect.equality(invalidated_windows, { 22 })
end

return T
