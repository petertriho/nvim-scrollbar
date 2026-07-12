local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.store"] = nil
            package.loaded["scrollbar.providers"] = nil
            package.loaded["scrollbar.providers.diagnostic"] = nil
            require("scrollbar.config").set({
                excluded_buftypes = {},
                excluded_filetypes = { "scrollbar-excluded" },
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

local function new_buffer(lines, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = filetype or ""
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

local function source_windows(bufnr)
    local windows = {}
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(winid).relative == "" and vim.api.nvim_win_get_buf(winid) == bufnr then
            table.insert(windows, winid)
        end
    end
    table.sort(windows)
    return windows
end

local function diagnostic(namespace, bufnr, lnum, severity, message)
    vim.diagnostic.set(namespace, bufnr, {
        {
            lnum = lnum,
            col = 0,
            severity = severity,
            message = message,
        },
    })
end

T["DiagnosticChanged maps zero-based severities, replaces marks, and clears all source windows"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two", "three", "four" })
    local target_win = show_buffer(target)
    show_buffer(target)
    local namespace = vim.api.nvim_create_namespace("ScrollbarDiagnosticProviderTest")
    local invalidated_windows = {}

    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(target) then
            vim.diagnostic.reset(namespace, target)
        end
    end)
    vim.api.nvim_set_current_win(target_win)
    providers.register(require("scrollbar.providers.diagnostic"))
    providers.setup({
        invalidate_buffer = function(bufnr)
            vim.list_extend(invalidated_windows, source_windows(bufnr))
        end,
    })

    invalidated_windows = {}
    vim.diagnostic.set(namespace, target, {
        { lnum = 0, col = 0, severity = vim.diagnostic.severity.ERROR, message = "error" },
        { lnum = 1, col = 0, severity = vim.diagnostic.severity.WARN, message = "warn" },
        { lnum = 2, col = 0, severity = vim.diagnostic.severity.INFO, message = "info" },
        { lnum = 3, col = 0, severity = vim.diagnostic.severity.HINT, message = "hint" },
    })

    expect.equality(store.get(target), {
        diagnostic = {
            { line = 0, type = "Error" },
            { line = 1, type = "Warn" },
            { line = 2, type = "Info" },
            { line = 3, type = "Hint" },
        },
    })
    expect.equality(invalidated_windows, source_windows(target))

    invalidated_windows = {}
    diagnostic(namespace, target, 2, vim.diagnostic.severity.INFO, "replacement")
    expect.equality(store.get(target), {
        diagnostic = { { line = 2, type = "Info" } },
    })
    expect.equality(invalidated_windows, source_windows(target))

    invalidated_windows = {}
    vim.diagnostic.reset(namespace, target)
    expect.equality(store.get(target), {})
    expect.equality(invalidated_windows, source_windows(target))
end

T["diagnostic events update only their buffer"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two" })
    local other = new_buffer({ "alpha", "beta" })
    local namespace = vim.api.nvim_create_namespace("ScrollbarDiagnosticProviderIsolationTest")

    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(target) then
            vim.diagnostic.reset(namespace, target)
        end
        if vim.api.nvim_buf_is_valid(other) then
            vim.diagnostic.reset(namespace, other)
        end
    end)
    providers.register(require("scrollbar.providers.diagnostic"))
    providers.setup()

    diagnostic(namespace, target, 0, vim.diagnostic.severity.ERROR, "target")

    expect.equality(store.get(target), {
        diagnostic = { { line = 0, type = "Error" } },
    })
    expect.equality(store.get(other), {})
end

T["diagnostic provider ignores excluded buffers"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local excluded = new_buffer({ "one", "two" }, "scrollbar-excluded")
    local namespace = vim.api.nvim_create_namespace("ScrollbarDiagnosticProviderExcludedTest")
    local invalidated = {}

    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(excluded) then
            vim.diagnostic.reset(namespace, excluded)
        end
    end)
    providers.register(require("scrollbar.providers.diagnostic"))
    providers.setup({
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })
    invalidated = {}
    diagnostic(namespace, excluded, 1, vim.diagnostic.severity.WARN, "excluded")

    expect.equality(store.get(excluded), {})
    expect.equality(invalidated, {})
end

T["diagnostic setup is idempotent and disposal removes events and marks"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two" })
    local namespace = vim.api.nvim_create_namespace("ScrollbarDiagnosticProviderDisposeTest")

    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(target) then
            vim.diagnostic.reset(namespace, target)
        end
    end)
    providers.register(require("scrollbar.providers.diagnostic"))
    providers.setup()
    diagnostic(namespace, target, 0, vim.diagnostic.severity.HINT, "hint")
    local first_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_diagnostic_events" })

    providers.setup()
    local second_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_diagnostic_events" })
    expect.equality(#second_autocmds, #first_autocmds)
    expect.equality(#second_autocmds > 0, true)
    expect.equality(store.get(target), {
        diagnostic = { { line = 0, type = "Hint" } },
    })

    providers.dispose()

    expect.equality(store.get(target), {})
    expect.equality(pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarProvider_diagnostic_events" }), false)
end

return T
