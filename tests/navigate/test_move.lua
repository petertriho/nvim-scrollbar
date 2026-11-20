local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    local lines = {}
    for index = 1, 100 do
        lines[index] = "    line " .. index
    end
    helpers.set_lines(child, lines)
    return child
end

local function move(child, line, jumplist)
    return child.lua(
        [[
        local line, jumplist = ...
        local win = vim.api.nvim_get_current_win()
        return require("scrollbar.navigate.move").line(win, vim.api.nvim_win_get_buf(win), line, jumplist)
    ]],
        { line, jumplist }
    )
end

T["moves to the line start and centers the line"] = function()
    local child = new_child()
    expect.equality(move(child, 49), true)
    expect.equality(child.api.nvim_win_get_cursor(0), { 50, 0 })
    local top = child.fn.line("w0")
    local bottom = child.fn.line("w$")
    expect.equality(math.abs((top + bottom) / 2 - 50) <= 1, true)
end

T["clamps the line to the buffer"] = function()
    local child = new_child()
    move(child, 500)
    expect.equality(child.api.nvim_win_get_cursor(0), { 100, 0 })
    move(child, -3)
    expect.equality(child.api.nvim_win_get_cursor(0), { 1, 0 })
end

T["opens the folds at the line"] = function()
    local child = new_child()
    child.cmd("40,60fold")
    expect.equality(child.fn.foldclosed(50), 40)
    move(child, 49)
    expect.equality(child.fn.foldclosed(50), -1)
end

T["adds a jumplist entry only when asked"] = function()
    local child = new_child()
    child.api.nvim_win_set_cursor(0, { 10, 0 })
    move(child, 59)
    child.type_keys("<C-o>")
    -- Without an entry, <C-o> does not return to line 10.
    expect.no_equality(child.api.nvim_win_get_cursor(0)[1], 10)

    child.api.nvim_win_set_cursor(0, { 20, 0 })
    move(child, 79, true)
    expect.equality(child.api.nvim_win_get_cursor(0), { 80, 0 })
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0)[1], 20)
end

return T
