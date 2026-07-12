local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.store"] = nil
            package.loaded["scrollbar.providers"] = nil
            package.loaded["scrollbar.providers.cursor"] = nil
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

T["cursor movement updates and invalidates only the event window"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two", "three" })
    local other = new_buffer({ "alpha", "beta" })
    local target_win = show_buffer(target)
    local second_target_win = show_buffer(target)
    local other_win = show_buffer(other)
    local invalidated_windows = {}

    vim.api.nvim_win_set_cursor(target_win, { 1, 0 })
    vim.api.nvim_win_set_cursor(second_target_win, { 3, 0 })
    vim.api.nvim_win_set_cursor(other_win, { 2, 0 })
    vim.api.nvim_set_current_win(target_win)

    providers.register(require("scrollbar.providers.cursor"))
    providers.setup({
        invalidate_window = function(winid)
            table.insert(invalidated_windows, winid)
        end,
    })

    expect.equality(store.get(target), {})
    expect.equality(store.get_window(target_win).cursor, { { line = 0, type = "Cursor" } })
    expect.equality(store.get_window(second_target_win).cursor, { { line = 2, type = "Cursor" } })
    local target_revision = store._get_window_snapshot(target_win).revision
    local second_revision = store._get_window_snapshot(second_target_win).revision
    local other_before = store.get_window(other_win)
    invalidated_windows = {}
    vim.api.nvim_win_set_cursor(target_win, { 2, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = target })

    expect.equality(store.get_window(target_win).cursor, { { line = 1, type = "Cursor" } })
    expect.equality(store.get_window(second_target_win).cursor, { { line = 2, type = "Cursor" } })
    expect.equality(store.get_window(other_win), other_before)
    expect.equality(invalidated_windows, { target_win })
    expect.equality(store._get_window_snapshot(target_win).revision, target_revision + 1)
    expect.equality(store._get_window_snapshot(second_target_win).revision, second_revision)

    invalidated_windows = {}
    vim.api.nvim_win_set_cursor(target_win, { 1, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = target })
    expect.equality(store.get_window(target_win).cursor, { { line = 0, type = "Cursor" } })
    expect.equality(store.get_window(second_target_win).cursor, { { line = 2, type = "Cursor" } })
    expect.equality(invalidated_windows, { target_win })
    expect.equality(store._get_window_snapshot(target_win).revision, target_revision + 2)
    expect.equality(store._get_window_snapshot(second_target_win).revision, second_revision)
end

T["cursor provider ignores excluded buffers"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local excluded = new_buffer({ "one", "two" }, "scrollbar-excluded")
    local excluded_win = show_buffer(excluded)
    local invalidated = {}

    vim.api.nvim_set_current_win(excluded_win)
    providers.register(require("scrollbar.providers.cursor"))
    providers.setup({
        invalidate_window = function(winid)
            table.insert(invalidated, winid)
        end,
    })
    invalidated = {}
    vim.api.nvim_win_set_cursor(excluded_win, { 2, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = excluded })

    expect.equality(store.get_window(excluded_win), {})
    expect.equality(invalidated, {})
end

T["cursor setup is idempotent and disposal removes events and marks"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two" })
    local target_win = show_buffer(target)

    vim.api.nvim_set_current_win(target_win)
    providers.register(require("scrollbar.providers.cursor"))
    providers.setup()
    local first_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_cursor_events" })

    providers.setup()
    local second_autocmds = vim.api.nvim_get_autocmds({ group = "ScrollbarProvider_cursor_events" })
    expect.equality(#second_autocmds, #first_autocmds)
    expect.equality(#second_autocmds > 0, true)
    expect.equality(store.get_window(target_win).cursor, { { line = 0, type = "Cursor" } })

    providers.dispose()

    expect.equality(store.get_window(target_win), {})
    expect.equality(pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarProvider_cursor_events" }), false)
end

T["entering a same-buffer split initializes its window cursor mark"] = function()
    local providers = require("scrollbar.providers")
    local store = require("scrollbar.store")
    local target = new_buffer({ "one", "two", "three" })
    local first = show_buffer(target)

    vim.api.nvim_set_current_win(first)
    vim.api.nvim_win_set_cursor(first, { 2, 0 })
    providers.register(require("scrollbar.providers.cursor"))
    providers.setup()

    vim.cmd("split")
    local second = vim.api.nvim_get_current_win()
    MiniTest.finally(function()
        if vim.api.nvim_win_is_valid(second) then
            vim.api.nvim_win_close(second, true)
        end
    end)

    expect.equality(store.get_window(second).cursor, { { line = 1, type = "Cursor" } })
end

return T
