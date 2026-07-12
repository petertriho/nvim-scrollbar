local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.store"] = nil
            require("scrollbar.config").set({
                marks = {
                    Custom = { text = "!", column = 1, priority = 1, highlight = "WarningMsg" },
                },
            })
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
    vim.notify = function(message, level)
        table.insert(notifications, { message = message, level = level })
    end
    MiniTest.finally(function()
        vim.notify = original
    end)
    return notifications
end

T["isolates providers and buffers and returns copied snapshots"] = function()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one", "two", "three" })
    local second = new_buffer({ "one", "two" })
    local marks = { { line = 1, type = "Custom", text = "x" } }

    local ok, changed = store.set("alpha", first, marks)
    expect.equality(ok, true)
    expect.equality(changed, { [first] = true })
    expect.equality(select(2, store.set("beta", first, { { line = 2, type = "Search" } })), { [first] = true })
    expect.equality(select(2, store.set("alpha", second, { { line = 0, type = "Custom" } })), { [second] = true })

    marks[1].line = 0
    local snapshot = store.get(first)
    snapshot.alpha[1].line = 0
    snapshot.beta = nil

    expect.equality(store.get(first), {
        alpha = { { line = 1, type = "Custom", text = "x" } },
        beta = { { line = 2, type = "Search" } },
    })
    expect.equality(store.get(second), {
        alpha = { { line = 0, type = "Custom" } },
    })
end

T["replaces lists atomically and reports only changed buffers"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })

    expect.equality(select(2, store.set("alpha", bufnr, { { line = 0, type = "Custom" } })), { [bufnr] = true })
    expect.equality(select(2, store.set("alpha", bufnr, { { line = 0, type = "Custom" } })), {})
    expect.equality(select(2, store.set("alpha", bufnr, { { line = 2, type = "Search" } })), { [bufnr] = true })
    expect.equality(store.get(bufnr), {
        alpha = { { line = 2, type = "Search" } },
    })
end

T["clears one entry, a provider, or a buffer with targeted change reporting"] = function()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one", "two" })
    local second = new_buffer({ "one", "two" })

    store.set("alpha", first, { { line = 0, type = "Custom" } })
    store.set("alpha", second, { { line = 0, type = "Custom" } })
    store.set("beta", first, { { line = 1, type = "Search" } })

    expect.equality(store.clear("beta", first), { [first] = true })
    expect.equality(store.clear("beta", first), {})
    expect.equality(store.clear_provider("alpha"), { [first] = true, [second] = true })
    expect.equality(store.get(first), {})
    expect.equality(store.get(second), {})

    store.set("alpha", first, { { line = 0, type = "Custom" } })
    store.set("beta", first, { { line = 1, type = "Search" } })
    expect.equality(store.clear_buffer(first), { [first] = true })
    expect.equality(store.clear_buffer(first), {})
end

T["validates complete lists against the current config and buffer bounds"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local invalid_lists = {
        false,
        { [1] = { line = 0, type = "Custom" }, [3] = { line = 1, type = "Custom" } },
        { "mark" },
        { { line = "0", type = "Custom" } },
        { { line = 0.5, type = "Custom" } },
        { { line = -1, type = "Custom" } },
        { { line = 2, type = "Custom" } },
        { { line = 0, type = "Missing" } },
        { { line = 0, type = "Custom", extra = true } },
        { { line = 0, type = "Custom", text = 1 } },
        { { line = 0, type = "Custom", text = "\n" } },
        { { line = 0, type = "Custom", text = "" } },
    }

    for index, marks in ipairs(invalid_lists) do
        local ok, changed = store.set("invalid-" .. index, bufnr, marks)
        expect.equality(ok, false)
        expect.equality(changed, {})
        expect.equality(store.get(bufnr), {})
    end
    expect.equality(#notifications, #invalid_lists)

    require("scrollbar.config").set({
        marks = {
            Runtime = { text = "r", column = 1, priority = 1, highlight = "Normal" },
        },
    })
    local ok, changed = store.set("alpha", bufnr, { { line = 1, type = "Runtime" } })
    expect.equality(ok, true)
    expect.equality(changed, { [bufnr] = true })
end

T["clears an existing entry when any replacement mark is invalid"] = function()
    capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })

    local ok, changed = store.set("alpha", bufnr, {
        { line = 1, type = "Custom" },
        { line = 2, type = "Custom" },
    })

    expect.equality(ok, false)
    expect.equality(changed, { [bufnr] = true })
    expect.equality(store.get(bufnr), {})
end

T["rate limits warnings by provider, buffer, and signature until success"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one" })
    local second = new_buffer({ "one" })
    local invalid_line = { { line = 1, type = "Custom" } }

    store.set("alpha", first, invalid_line)
    store.set("alpha", first, invalid_line)
    expect.equality(#notifications, 1)

    store.set("alpha", first, { { line = 0, type = "Missing" } })
    store.set("beta", first, invalid_line)
    store.set("alpha", second, invalid_line)
    expect.equality(#notifications, 4)

    local ok = store.set("alpha", first, { { line = 0, type = "Custom" } })
    expect.equality(ok, true)
    store.set("alpha", first, invalid_line)
    expect.equality(#notifications, 5)
    expect.equality(notifications[1].level, vim.log.levels.WARN)
    expect.no_equality(notifications[1].message:match("provider 'alpha'.*buffer " .. first), nil)
end

T["removes marks when a buffer is deleted"] = function()
    local store = require("scrollbar.store")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one" })
    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })

    vim.api.nvim_buf_delete(bufnr, { force = true })

    expect.equality(store.get(bufnr), {})
    expect.equality(store.clear_buffer(bufnr), {})
end

T["isolates window marks and removes them when a window closes"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })
    local first = show_buffer(bufnr)
    local second = show_buffer(bufnr)
    local marks = { { line = 0, type = "Custom", text = "x" } }

    expect.equality(select(2, store.set_window("alpha", first, marks)), { [first] = true })
    expect.equality(select(2, store.set_window("alpha", second, { { line = 2, type = "Custom" } })), {
        [second] = true,
    })
    expect.equality(select(2, store.set_window("alpha", first, marks)), {})

    marks[1].line = 1
    local snapshot = store.get_window(first)
    snapshot.alpha[1].line = 2
    expect.equality(store.get_window(first), {
        alpha = { { line = 0, type = "Custom", text = "x" } },
    })
    expect.equality(store.get_window(second), {
        alpha = { { line = 2, type = "Custom" } },
    })

    vim.api.nvim_win_close(first, true)
    expect.equality(store.get_window(first), {})
    expect.equality(store.get_window(second), {
        alpha = { { line = 2, type = "Custom" } },
    })
end

T["validates and clears window marks with targeted change reporting"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local first = show_buffer(bufnr)
    local second = show_buffer(bufnr)

    store.set_window("alpha", first, { { line = 0, type = "Custom" } })
    store.set_window("alpha", second, { { line = 1, type = "Custom" } })
    store.set_window("beta", first, { { line = 1, type = "Search" } })

    expect.equality(store.clear_window("beta", first), { [first] = true })
    expect.equality(store.clear_window("beta", first), {})
    expect.equality(store.clear_window_provider("alpha"), { [first] = true, [second] = true })
    expect.equality(store.get_window(first), {})
    expect.equality(store.get_window(second), {})

    local ok, changed = store.set_window("invalid", first, { { line = 2, type = "Custom" } })
    expect.equality(ok, false)
    expect.equality(changed, {})
    store.set_window("invalid", first, { { line = 2, type = "Custom" } })
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1].message:match("provider 'invalid'.*window " .. first), nil)

    ok = store.set_window("invalid", first, { { line = 1, type = "Custom" } })
    expect.equality(ok, true)
    store.set_window("invalid", first, { { line = 2, type = "Custom" } })
    expect.equality(#notifications, 2)
end

return T
