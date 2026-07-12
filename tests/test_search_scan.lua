local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function scan(lines, pattern, options, backend)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    if backend == "worker" then
        helpers.setup_search_worker(child, false)
    else
        helpers.setup_search(child, false)
    end

    return child.lua_func(function(input)
        vim.o.ignorecase = input.ignorecase or false
        vim.o.smartcase = input.smartcase or false
        vim.api.nvim_buf_set_lines(0, 0, -1, false, input.lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.fn.setreg("/", input.pattern)
        vim.fn.search(input.pattern, "cw")
        local view = vim.fn.winsaveview()
        require("scrollbar.providers").refresh(vim.api.nvim_get_current_buf())
        vim.wait(1000, function()
            return require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search ~= nil
        end)
        local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
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

for _, active_backend in ipairs({ "sync", "worker" }) do
    local backend = active_backend

    T[backend .. " preserves the complete window view while scanning"] = function()
        local result = scan({ "foo", "middle", "foo" }, "foo", nil, backend)
        expect.equality(result.view_preserved, true)
    end

    T[backend .. " returns zero-based marks for every match"] = function()
        expect.equality(scan({ "foo foo", "middle", "foo" }, "foo", nil, backend).lines, { 0, 0, 2 })
    end

    T[backend .. " terminates for zero-width patterns"] = function()
        expect.equality(scan({ "one", "two", "three" }, "^", nil, backend).lines, { 0, 1, 2 })
    end

    T[backend .. " supports escaped Vim alternation"] = function()
        expect.equality(scan({ "foo bar", "none" }, [[foo\|bar]], nil, backend).lines, { 0, 0 })
    end

    T[backend .. " uses starting lines for multiline matches"] = function()
        expect.equality(scan({ "foo", "middle", "bar", "foo bar" }, [[foo\_.\{-}bar]], nil, backend).lines, { 0, 3 })
    end

    T[backend .. " pattern case atoms override case options"] = function()
        expect.equality(scan({ "foo", "Foo" }, [[\CFoo]], { ignorecase = true }, backend).lines, { 1 })
    end

    T[backend .. " honors ignorecase"] = function()
        expect.equality(scan({ "foo", "Foo" }, "foo", { ignorecase = true }, backend).lines, { 0, 1 })
    end

    T[backend .. " honors smartcase"] = function()
        expect.equality(scan({ "foo", "Foo" }, "Foo", { ignorecase = true, smartcase = true }, backend).lines, { 1 })
    end
end

return T
