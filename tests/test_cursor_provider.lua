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

T["cursor movement replaces only the event buffer mark and invalidates every source window"] = function()
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
        invalidate_buffer = function(bufnr)
            vim.list_extend(invalidated_windows, source_windows(bufnr))
        end,
    })

    local other_before = store.get(other)
    invalidated_windows = {}
    vim.api.nvim_win_set_cursor(target_win, { 2, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = target })

    expect.equality(store.get(target), {
        cursor = { { line = 1, type = "Cursor" } },
    })
    expect.equality(store.get(other), other_before)
    expect.equality(invalidated_windows, source_windows(target))

    invalidated_windows = {}
    vim.api.nvim_win_set_cursor(target_win, { 1, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = target })
    expect.equality(store.get(target).cursor, { { line = 0, type = "Cursor" } })
    expect.equality(invalidated_windows, source_windows(target))
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
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })
    invalidated = {}
    vim.api.nvim_win_set_cursor(excluded_win, { 2, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = excluded })

    expect.equality(store.get(excluded), {})
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
    expect.equality(store.get(target).cursor, { { line = 0, type = "Cursor" } })

    providers.dispose()

    expect.equality(store.get(target), {})
    expect.equality(pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarProvider_cursor_events" }), false)
end

return T
