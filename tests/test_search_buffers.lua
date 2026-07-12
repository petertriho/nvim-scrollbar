local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function search_child(pattern, lines)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, false)
    helpers.set_lines(child, lines)
    helpers.accept_search(child, "/", pattern)
    return child
end

T["TextChanged refreshes accepted search marks"] = function()
    local child = search_child("beta", { "alpha", "beta", "alpha" })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    child.api.nvim_buf_set_lines(0, 1, 2, false, { "beta beta" })
    child.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    expect.equality(helpers.mark_lines(child), { 1, 1 })
end

T["TextChangedI refreshes stale accepted search marks"] = function()
    local child = search_child("preview", { "start", "accepted", "preview", "preview" })
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 3 }), true)
    child.lua([[
        require("scrollbar.store").set("search", vim.api.nvim_get_current_buf(), {
            { line = 0, type = "Search" },
        })
    ]])
    child.api.nvim_exec_autocmds("TextChangedI", { buffer = 0 })
    expect.equality(helpers.mark_lines(child), { 2, 3 })
end

T["BufWinEnter scans the entered buffer but not hidden buffers eagerly"] = function()
    local child = search_child("preview", { "start", "accepted", "preview", "preview" })
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 3 }), true)
    local buffers = child.lua_get([[(function()
        local hidden = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(hidden, 0, -1, false, { "preview" })
        local entered = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(entered, 0, -1, false, { "start", "preview preview" })
        vim.api.nvim_win_set_buf(0, entered)
        return { hidden = hidden, entered = entered }
    end)()]])
    expect.equality(helpers.mark_lines(child), { 1, 1 })
    expect.equality(helpers.search_marks(child, buffers.hidden), nil)
end

T["TextChanged replaces stale marks in the visible entered buffer"] = function()
    local child = search_child("preview", { "preview preview" })
    expect.equality(helpers.wait_for_mark_lines(child, { 0, 0 }), true)
    local entered = child.api.nvim_create_buf(true, false)
    child.api.nvim_buf_set_lines(entered, 0, -1, false, { "start", "preview preview" })
    child.api.nvim_win_set_buf(0, entered)
    expect.equality(helpers.mark_lines(child), { 1, 1 })
    child.api.nvim_buf_set_lines(0, 1, 2, false, { "preview" })
    child.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    expect.equality(helpers.mark_lines(child), { 1 })
end

T["pattern signatures are isolated per buffer"] = function()
    local child = search_child("preview", { "preview", "preview" })
    expect.equality(helpers.wait_for_mark_lines(child, { 0, 1 }), true)

    local buffers = child.lua_get([[(function()
        vim.cmd("vsplit")
        local first = vim.api.nvim_get_current_buf()
        local second = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(second, 0, -1, false, { "preview", "preview" })
        vim.api.nvim_win_set_buf(0, second)
        vim.bo[second].iskeyword = "@,48-57,_"
        return { first = first, second = second }
    end)()]])
    expect.equality(helpers.mark_lines(child, buffers.second), { 0, 1 })

    child.lua_func(function(first)
        require("scrollbar.store").set("search", first, { { line = 0, type = "Search" } })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = first })
    end, buffers.first)

    expect.equality(helpers.mark_lines(child, buffers.first), { 0 })
end

return T
