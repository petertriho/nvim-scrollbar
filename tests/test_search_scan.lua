local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function scan(lines, pattern, options)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, false)

    return child.lua_func(function(input)
        vim.o.ignorecase = input.ignorecase or false
        vim.o.smartcase = input.smartcase or false
        vim.api.nvim_buf_set_lines(0, 0, -1, false, input.lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.fn.setreg("/", input.pattern)
        vim.fn.search(input.pattern, "cw")
        local view = vim.fn.winsaveview()
        require("scrollbar.handlers.search").refresh()
        local marks = require("scrollbar.utils").get_scrollbar_marks(0).search
        return {
            lines = vim.tbl_map(function(mark)
                return mark.line
            end, marks),
            view_preserved = vim.deep_equal(view, vim.fn.winsaveview()),
        }
    end, {
        lines = lines,
        pattern = pattern,
        ignorecase = options and options.ignorecase,
        smartcase = options and options.smartcase,
    })
end

T["preserves the complete window view while scanning"] = function()
    local result = scan({ "foo", "middle", "foo" }, "foo")
    expect.equality(result.view_preserved, true)
end

T["returns zero-based marks for every match"] = function()
    expect.equality(scan({ "foo foo", "middle", "foo" }, "foo").lines, { 0, 0, 2 })
end

T["terminates for zero-width patterns"] = function()
    expect.equality(scan({ "one", "two", "three" }, "^").lines, { 0, 1, 2 })
end

T["supports escaped Vim alternation"] = function()
    expect.equality(scan({ "foo bar", "none" }, [[foo\|bar]]).lines, { 0, 0 })
end

T["uses starting lines for multiline matches"] = function()
    expect.equality(scan({ "foo", "middle", "bar", "foo bar" }, [[foo\_.\{-}bar]]).lines, { 0, 3 })
end

T["pattern case atoms override case options"] = function()
    expect.equality(scan({ "foo", "Foo" }, [[\CFoo]], { ignorecase = true }).lines, { 1 })
end

T["honors ignorecase"] = function()
    expect.equality(scan({ "foo", "Foo" }, "foo", { ignorecase = true }).lines, { 0, 1 })
end

T["honors smartcase"] = function()
    expect.equality(scan({ "foo", "Foo" }, "Foo", { ignorecase = true, smartcase = true }).lines, { 1 })
end

return T
