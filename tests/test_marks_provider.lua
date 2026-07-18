local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.renderer"] = nil
            package.loaded["scrollbar.store"] = nil
            package.loaded["scrollbar.providers"] = nil
            package.loaded["scrollbar.providers.marks"] = nil
            require("scrollbar.config").set({
                max_lines = false,
                excluded_buftypes = {},
                excluded_filetypes = { "scrollbar-excluded" },
                providers = { marks = true },
            })
            for byte = string.byte("A"), string.byte("Z") do
                pcall(vim.api.nvim_del_mark, string.char(byte))
            end
            for byte = string.byte("0"), string.byte("9") do
                pcall(vim.api.nvim_del_mark, string.char(byte))
            end
        end,
        post_case = function()
            local providers = package.loaded["scrollbar.providers"]
            if providers then
                providers.dispose()
            end
            for byte = string.byte("A"), string.byte("Z") do
                pcall(vim.api.nvim_del_mark, string.char(byte))
            end
            for byte = string.byte("0"), string.byte("9") do
                pcall(vim.api.nvim_del_mark, string.char(byte))
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

local function setup_provider(options)
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.marks"))
    providers.setup(options)
    return providers
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

local function has_complete_mark_set_events()
    local version = vim.version()
    return version.major > 0 or version.minor > 12 or (version.minor == 12 and version.patch >= 2)
end

local function await_mark_reconciliation(bufnr, predicate)
    if not has_complete_mark_set_events() then
        vim.api.nvim_exec_autocmds("SafeState", { buffer = bufnr })
        return true
    end
    return vim.wait(1000, predicate)
end

T["collects letter marks with literal names in source order by default"] = function()
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two", "three", "four", "five" })
    local foreign = new_buffer({ "alpha", "beta" })

    vim.api.nvim_buf_set_mark(target, "c", 1, 0, {})
    vim.api.nvim_buf_set_mark(target, "b", 3, 0, {})
    vim.api.nvim_buf_set_mark(target, "a", 3, 0, {})
    vim.api.nvim_buf_set_mark(target, "Z", 5, 0, {})
    vim.api.nvim_buf_set_mark(target, "A", 3, 0, {})
    vim.api.nvim_buf_set_mark(foreign, "B", 1, 0, {})
    vim.api.nvim_buf_set_mark(target, "1", 3, 0, {})
    vim.api.nvim_buf_set_mark(target, "'", 4, 0, {})

    setup_provider()

    expect.equality(store.get(target).marks, {
        { line = 0, type = "Mark", text = "c" },
        { line = 2, type = "Mark", text = "A" },
        { line = 2, type = "Mark", text = "a" },
        { line = 2, type = "Mark", text = "b" },
        { line = 4, type = "Mark", text = "Z" },
    })
end

T["collects numbered marks independently from letter marks"] = function()
    local config = require("scrollbar.config")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two", "three" })
    vim.api.nvim_buf_set_mark(target, "a", 1, 0, {})
    vim.api.nvim_buf_set_mark(target, "A", 2, 0, {})
    vim.api.nvim_buf_set_mark(target, "1", 3, 0, {})
    local active_config = config.set({
        max_lines = false,
        excluded_buftypes = {},
        excluded_filetypes = {},
        providers = { marks = { letters = false, numbers = true } },
    })

    setup_provider({ config = active_config })

    expect.equality(store.get(target).marks, { { line = 2, type = "Mark", text = "1" } })
end

T["text changes move marks while unchanged and empty refreshes preserve revisions"] = function()
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two", "three", "four" })
    vim.api.nvim_buf_set_mark(target, "a", 2, 0, {})
    vim.api.nvim_buf_set_mark(target, "A", 4, 0, {})
    local providers = setup_provider()
    local initial_revision = store._get_snapshot(target).revision

    providers.refresh(target)
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = target })
    expect.equality(store._get_snapshot(target).revision, initial_revision)

    vim.api.nvim_buf_set_lines(target, 0, 0, false, { "zero" })
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = target })
    expect.equality(store.get(target).marks, {
        { line = 2, type = "Mark", text = "a" },
        { line = 4, type = "Mark", text = "A" },
    })
    expect.equality(store._get_snapshot(target).revision, initial_revision + 1)

    vim.api.nvim_buf_del_mark(target, "a")
    vim.api.nvim_del_mark("A")
    providers.refresh(target)
    local cleared_revision = store._get_snapshot(target).revision
    expect.equality(store.get(target), {})

    providers.refresh(target)
    expect.equality(store._get_snapshot(target).revision, cleared_revision)
end

T["owned buffer events clear excluded and oversized state"] = function()
    local config = require("scrollbar.config")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two", "three" })
    vim.api.nvim_buf_set_mark(target, "a", 2, 0, {})
    local active_config = config.set({
        max_lines = 3,
        excluded_buftypes = {},
        excluded_filetypes = { "scrollbar-excluded" },
        providers = { marks = true },
    })
    setup_provider({ config = active_config })
    expect.equality(store.get(target).marks, { { line = 1, type = "Mark", text = "a" } })

    vim.bo[target].filetype = "scrollbar-excluded"
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = target })
    expect.equality(store.get(target), {})

    vim.bo[target].filetype = ""
    vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = target })
    expect.equality(store.get(target).marks, { { line = 1, type = "Mark", text = "a" } })

    vim.api.nvim_buf_set_lines(target, -1, -1, false, { "four" })
    vim.api.nvim_exec_autocmds("TextChangedT", { buffer = target })
    expect.equality(store.get(target), {})
end

T["named-mark reconciliation moves and deletes uppercase marks across source buffers"] = function()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one", "two", "three" })
    local second = new_buffer({ "alpha", "beta", "gamma" })
    local first_win = show_buffer(first)
    show_buffer(first)
    show_buffer(second)
    vim.api.nvim_set_current_win(first_win)
    vim.api.nvim_buf_set_mark(first, "A", 2, 0, {})
    setup_provider()

    expect.equality(store.get(first).marks, { { line = 1, type = "Mark", text = "A" } })
    expect.equality(store.get(second), {})

    vim.api.nvim_buf_set_mark(second, "A", 3, 0, {})
    expect.equality(
        await_mark_reconciliation(second, function()
            return store.get(first).marks == nil and store.get(second).marks ~= nil
        end),
        true
    )
    expect.equality(store.get(first), {})
    expect.equality(store.get(second).marks, { { line = 2, type = "Mark", text = "A" } })

    vim.api.nvim_del_mark("A")
    expect.equality(
        await_mark_reconciliation(second, function()
            return store.get(second).marks == nil
        end),
        true
    )
    expect.equality(store.get(first), {})
    expect.equality(store.get(second), {})
end

T["mark reconciliation moves and deletes numbered marks across source buffers"] = function()
    local config = require("scrollbar.config")
    local store = require("scrollbar.store")
    local first = new_buffer({ "one", "two", "three" })
    local second = new_buffer({ "alpha", "beta", "gamma" })
    local first_win = show_buffer(first)
    show_buffer(second)
    vim.api.nvim_set_current_win(first_win)
    vim.api.nvim_buf_set_mark(first, "1", 2, 0, {})
    local active_config = config.set({
        max_lines = false,
        excluded_buftypes = {},
        excluded_filetypes = {},
        providers = { marks = { letters = false, numbers = true } },
    })
    setup_provider({ config = active_config })

    expect.equality(store.get(first).marks, { { line = 1, type = "Mark", text = "1" } })
    expect.equality(store.get(second), {})

    vim.api.nvim_buf_set_mark(second, "1", 3, 0, {})
    expect.equality(
        await_mark_reconciliation(second, function()
            return store.get(first).marks == nil and store.get(second).marks ~= nil
        end),
        true
    )
    expect.equality(store.get(first), {})
    expect.equality(store.get(second).marks, { { line = 2, type = "Mark", text = "1" } })

    vim.api.nvim_del_mark("1")
    expect.equality(
        await_mark_reconciliation(second, function()
            return store.get(second).marks == nil
        end),
        true
    )
    expect.equality(store.get(first), {})
    expect.equality(store.get(second), {})
end

T["does not load or publish an unloaded uppercase-mark target"] = function()
    local store = require("scrollbar.store")
    local visible = new_buffer({ "one", "two" })
    local unloaded = new_buffer({ "alpha", "beta" })
    local unloaded_name = vim.fn.tempname()
    vim.api.nvim_buf_set_name(unloaded, unloaded_name)
    vim.bo[unloaded].bufhidden = "hide"
    vim.api.nvim_buf_set_mark(unloaded, "U", 2, 0, {})
    vim.api.nvim_buf_delete(unloaded, { force = true, unload = true })
    expect.equality(vim.api.nvim_buf_is_loaded(unloaded), false)

    setup_provider()

    expect.equality(store.get(visible), {})
    expect.equality(vim.api.nvim_buf_is_loaded(unloaded), false)
end

T["owns the version-gated event path and disposes all state"] = function()
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two" })
    local target_win = show_buffer(target)
    vim.api.nvim_set_current_win(target_win)
    vim.api.nvim_buf_set_mark(target, "a", 1, 0, {})
    local providers = setup_provider()

    local function event_snapshot()
        local snapshot = {}
        for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_marks_events" })) do
            snapshot[autocmd.event] = autocmd.pattern
        end
        return snapshot
    end

    local first = event_snapshot()
    providers.setup()
    local second = event_snapshot()
    expect.equality(second, first)
    for _, event in ipairs({ "BufEnter", "BufWinEnter", "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }) do
        expect.equality(first[event] ~= nil, true)
    end
    if has_complete_mark_set_events() then
        expect.equality(first.MarkSet, "[a-zA-Z]")
        expect.equality(first.SafeState, nil)
    else
        expect.equality(first.MarkSet, nil)
        expect.equality(first.SafeState ~= nil, true)
    end
    expect.equality(store.get(target).marks, { { line = 0, type = "Mark", text = "a" } })

    providers.dispose()
    expect.equality(store.get(target), {})
    expect.equality(pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarProvider_marks_events" }), false)
end

T["numbered mark tracking retains SafeState reconciliation for ShaDa changes"] = function()
    local config = require("scrollbar.config")
    local active_config = config.set({
        max_lines = false,
        excluded_buftypes = {},
        excluded_filetypes = {},
        providers = { marks = { letters = false, numbers = true } },
    })
    setup_provider({ config = active_config })

    local events = {}
    for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_marks_events" })) do
        events[autocmd.event] = autocmd.pattern
    end

    if has_complete_mark_set_events() then
        expect.equality(events.MarkSet, "[0-9]")
    else
        expect.equality(events.MarkSet, nil)
    end
    expect.equality(events.SafeState ~= nil, true)
end

T["delegates buffer eligibility before collecting marks"] = function()
    local target = new_buffer({ "one" })
    local calls = 0
    local get_mark = vim.api.nvim_buf_get_mark
    rawset(vim.api, "nvim_buf_get_mark", function(...)
        calls = calls + 1
        return get_mark(...)
    end)
    MiniTest.finally(function()
        rawset(vim.api, "nvim_buf_get_mark", get_mark)
    end)

    setup_provider({
        is_buffer_eligible = function()
            return false
        end,
    })
    calls = 0
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = target })

    expect.equality(calls, 0)
    expect.equality(require("scrollbar.store").get(target), {})
end

return T
