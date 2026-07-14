local MiniTest = MiniTest
local expect = MiniTest.expect

local original_coc_action
local original_ale_buffer_info

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            local providers = package.loaded["scrollbar.providers"]
            if providers then
                providers.dispose()
            end

            original_coc_action = rawget(vim.fn, "CocActionAsync")
            original_ale_buffer_info = vim.g.ale_buffer_info
            rawset(vim.fn, "CocActionAsync", nil)
            vim.g.ale_buffer_info = nil
            package.preload["gitsigns"] = nil
            package.loaded["gitsigns"] = nil

            for _, module in ipairs({
                "scrollbar.config",
                "scrollbar.store",
                "scrollbar.providers",
                "scrollbar.providers.gitsigns",
                "scrollbar.providers.ale",
                "scrollbar.providers.coc",
            }) do
                package.loaded[module] = nil
            end
            require("scrollbar.config").set({})
        end,
        post_case = function()
            local providers = package.loaded["scrollbar.providers"]
            if providers then
                providers.dispose()
            end
            rawset(vim.fn, "CocActionAsync", original_coc_action)
            vim.g.ale_buffer_info = original_ale_buffer_info
            package.preload["gitsigns"] = nil
            package.loaded["gitsigns"] = nil
        end,
    },
})

local function new_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/nvim-scrollbar-test-" .. bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)
    return bufnr
end

local function show_in_two_windows(first, second)
    local original_win = vim.api.nvim_get_current_win()
    local original_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(original_win, first)
    vim.cmd("vsplit")
    local second_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(second_win, second)

    MiniTest.finally(function()
        if vim.api.nvim_win_is_valid(second_win) and #vim.api.nvim_list_wins() > 1 then
            vim.api.nvim_win_close(second_win, true)
        end
        if vim.api.nvim_win_is_valid(original_win) then
            vim.api.nvim_set_current_win(original_win)
            if vim.api.nvim_buf_is_valid(original_buf) then
                vim.api.nvim_win_set_buf(original_win, original_buf)
            end
        end
    end)

    return { original_win, second_win }
end

local function sorted(values)
    table.sort(values)
    return values
end

T["gitsigns fans out fallback updates, clears marks, and disposes its augroup"] = function()
    local first = new_buffer({ "1", "2", "3", "4" })
    local second = new_buffer({ "1", "2", "3", "4" })
    local windows = show_in_two_windows(first, second)
    local hunks = { [first] = {}, [second] = {} }
    local calls = {}
    package.preload["gitsigns"] = function()
        return {
            get_hunks = function(bufnr)
                table.insert(calls, bufnr)
                return hunks[bufnr]
            end,
        }
    end

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    local invalidated = {}
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        source_windows = function()
            return windows
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    calls = {}
    invalidated = {}
    hunks[first] = { { type = "add", added = { start = 2, count = 2 } } }
    hunks[second] = { { type = "delete", added = { start = 3, count = 0 } } }
    vim.api.nvim_exec_autocmds("User", { pattern = "GitSignsUpdate" })

    expect.equality(sorted(calls), sorted({ first, second }))
    expect.equality(require("scrollbar.store").get(first).gitsigns, {
        { line = 1, type = "GitAdd" },
        { line = 2, type = "GitAdd" },
    })
    expect.equality(require("scrollbar.store").get(second).gitsigns, {
        { line = 2, type = "GitDelete" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    invalidated = {}
    hunks[first] = {}
    hunks[second] = {}
    vim.api.nvim_exec_autocmds("User", { pattern = "GitSignsUpdate" })
    expect.equality(require("scrollbar.store").get(first).gitsigns, {})
    expect.equality(require("scrollbar.store").get(second).gitsigns, {})
    expect.equality(sorted(invalidated), sorted({ first, second }))

    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "GitSignsUpdate" }), 1)
    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "GitSignsUpdate" }), 0)
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
end

T["gitsigns bounds change marks to the surviving added range"] = function()
    local target = new_buffer({ "1", "2", "3", "4", "5" })
    local hunks = {}
    package.preload["gitsigns"] = function()
        return {
            get_hunks = function()
                return hunks
            end,
        }
    end

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    hunks = {
        { type = "change", added = { start = 2, count = 1 }, removed = { count = 1 } },
    }
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).gitsigns, {
        { line = 1, type = "GitChange" },
    })

    hunks = {
        { type = "change", added = { start = 2, count = 3 }, removed = { count = 1 } },
    }
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).gitsigns, {
        { line = 1, type = "GitChange" },
        { line = 2, type = "GitAdd" },
        { line = 3, type = "GitAdd" },
    })

    hunks = {
        { type = "change", added = { start = 2, count = 1 }, removed = { count = 3 } },
    }
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).gitsigns, {
        { line = 1, type = "GitChange" },
    })
end

T["ALE converts one-based lines and updates only each event buffer"] = function()
    local first = new_buffer({ "1", "2", "3" })
    local second = new_buffer({ "1", "2", "3" })
    vim.g.ale_buffer_info = {
        [tostring(first)] = {
            loclist = {
                { lnum = 1, type = "E" },
                { lnum = 3, type = "W" },
            },
        },
        [tostring(second)] = {
            loclist = {
                { lnum = 2, type = "E" },
            },
        },
    }

    local invalidated = {}
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.ale"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    expect.equality(require("scrollbar.store").get(first).ale, {
        { line = 0, type = "Error" },
        { line = 2, type = "Warn" },
    })
    expect.equality(require("scrollbar.store").get(second).ale, {
        { line = 1, type = "Error" },
    })

    invalidated = {}
    vim.g.ale_buffer_info = {
        [tostring(first)] = { loclist = {} },
        [tostring(second)] = {
            loclist = {
                { lnum = 2, type = "E" },
            },
        },
    }
    vim.api.nvim_set_current_buf(first)
    vim.api.nvim_exec_autocmds("User", { pattern = "ALELintPost" })

    expect.equality(require("scrollbar.store").get(first).ale, {})
    expect.equality(require("scrollbar.store").get(second).ale, {
        { line = 1, type = "Error" },
    })
    expect.equality(invalidated, { first })

    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "ALELintPost" }), 1)
    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "ALELintPost" }), 0)
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
end

T["Coc asynchronously replaces all URI diagnostics and preserves severity mapping"] = function()
    local first = new_buffer({ "1", "2", "3", "4" })
    local second = new_buffer({ "1", "2", "3", "4" })
    local callbacks = {}
    rawset(vim.fn, "CocActionAsync", function(action, callback)
        expect.equality(action, "diagnosticList")
        table.insert(callbacks, callback)
    end)

    local invalidated = {}
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.coc"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })
    expect.equality(#callbacks, 1)

    invalidated = {}
    callbacks[1](vim.NIL, {
        {
            severity = "Error",
            location = { uri = vim.uri_from_bufnr(first), range = { start = { line = 0 } } },
        },
        {
            severity = "Information",
            location = { uri = vim.uri_from_bufnr(first), range = { start = { line = 2 } } },
        },
        {
            severity = "Warning",
            location = { uri = vim.uri_from_bufnr(second), range = { start = { line = 1 } } },
        },
    })

    expect.equality(require("scrollbar.store").get(first).coc, {
        { line = 0, type = "Error" },
        { line = 2, type = "Info" },
    })
    expect.equality(require("scrollbar.store").get(second).coc, {
        { line = 1, type = "Warn" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    callbacks[1]("request failed", {})
    expect.equality(require("scrollbar.store").get(first).coc, {
        { line = 0, type = "Error" },
        { line = 2, type = "Info" },
    })

    vim.api.nvim_exec_autocmds("User", { pattern = "CocDiagnosticChange" })
    expect.equality(#callbacks, 2)
    invalidated = {}
    callbacks[2](vim.NIL, {
        {
            severity = "Hint",
            location = { uri = vim.uri_from_bufnr(second), range = { start = { line = 3 } } },
        },
    })

    expect.equality(require("scrollbar.store").get(first).coc, {})
    expect.equality(require("scrollbar.store").get(second).coc, {
        { line = 3, type = "Hint" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "CocDiagnosticChange" }), 0)
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
    expect.equality(
        pcall(callbacks[2], vim.NIL, {
            {
                severity = "Error",
                location = { uri = vim.uri_from_bufnr(first), range = { start = { line = 0 } } },
            },
        }),
        true
    )
    expect.equality(require("scrollbar.store").get(first), {})
end

T["Coc ignores diagnostic responses older than the latest request"] = function()
    local target = new_buffer({ "1", "2", "3" })
    local callbacks = {}
    rawset(vim.fn, "CocActionAsync", function(_, callback)
        table.insert(callbacks, callback)
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.coc"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })
    vim.api.nvim_exec_autocmds("User", { pattern = "CocDiagnosticChange" })
    expect.equality(#callbacks, 2)

    callbacks[2](vim.NIL, {
        {
            severity = "Warning",
            location = { uri = vim.uri_from_bufnr(target), range = { start = { line = 1 } } },
        },
    })
    callbacks[1](vim.NIL, {
        {
            severity = "Error",
            location = { uri = vim.uri_from_bufnr(target), range = { start = { line = 0 } } },
        },
    })

    expect.equality(require("scrollbar.store").get(target).coc, {
        { line = 1, type = "Warn" },
    })
end

T["missing optional dependencies leave runtime and provider setup usable"] = function()
    local target = new_buffer({ "one" })
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.register(require("scrollbar.providers.ale"))
    providers.register(require("scrollbar.providers.coc"))

    expect.equality(
        pcall(providers.setup, {
            is_buffer_eligible = function(bufnr)
                return bufnr == target
            end,
        }),
        true
    )
    expect.equality(require("scrollbar.store").get(target), {
        ale = {},
        coc = {},
        gitsigns = {},
    })
    vim.api.nvim_set_current_buf(target)
    expect.equality(pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "ALELintPost" }), true)
    expect.equality(pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "CocDiagnosticChange" }), true)
end

T["manager clears only gitsigns marks when its refresh fails"] = function()
    local target = new_buffer({ "one", "two" })
    local fail = false
    package.preload["gitsigns"] = function()
        return {
            get_hunks = function()
                if fail then
                    error("gitsigns exploded")
                end
                return { { type = "add", added = { start = 1, count = 1 } } }
            end,
        }
    end
    local original_notify = vim.notify
    rawset(vim, "notify", function() end)
    MiniTest.finally(function()
        rawset(vim, "notify", original_notify)
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.register({
        name = "other",
        refresh = function()
            return { { line = 1, type = "Error" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    fail = true
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target), {
        other = { { line = 1, type = "Error" } },
    })
end

return T
