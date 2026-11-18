local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

T["match-affecting option changes refresh marks in both directions"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, false)
    helpers.set_lines(child, { "foo", "Foo" })
    helpers.activate_search(child, "foo")
    child.api.nvim_exec_autocmds("SafeState", {})
    expect.equality(helpers.mark_lines(child), { 0 })

    child.o.ignorecase = true
    expect.equality(helpers.wait_for_mark_lines(child, { 0, 1 }), true)
    child.o.ignorecase = false
    expect.equality(helpers.wait_for_mark_lines(child, { 0 }), true)
end

for _, backend in ipairs({ "sync", "worker" }) do
    T[backend .. " star and hash ignore smartcase as Neovim does"] = function()
        local child = helpers.new_child()
        MiniTest.finally(function()
            helpers.stop_child(child)
        end)
        if backend == "worker" then
            helpers.setup_search_worker(child, false)
            expect.equality(helpers.start_search_worker(child), true)
        else
            helpers.setup_search(child, false)
        end
        child.o.ignorecase = true
        child.o.smartcase = true
        helpers.set_lines(child, { "Foo", "foo", "FOO", "food", "Foo" })

        child.type_keys("*")
        expect.equality(helpers.wait_for_mark_lines(child, { 0, 1, 2, 4 }), true)
        child.type_keys("n")
        expect.equality(helpers.wait_for_mark_lines(child, { 0, 1, 2, 4 }), true)

        -- A typed search of the same pattern uses smartcase. `<lt>` types `<`.
        helpers.accept_search(child, "/", [[\<lt>Foo\>]])
        expect.equality(helpers.wait_for_mark_lines(child, { 0, 4 }), true)

        child.api.nvim_win_set_cursor(0, { 5, 0 })
        child.type_keys("#")
        expect.equality(helpers.wait_for_mark_lines(child, { 0, 1, 2, 4 }), true)

        child.api.nvim_win_set_cursor(0, { 1, 0 })
        child.type_keys("g*")
        expect.equality(helpers.wait_for_mark_lines(child, { 0, 1, 2, 3, 4 }), true)

        -- The check of smartcase keeps the substitute pattern.
        child.cmd("silent! 1s/Foo/Foo/")
        expect.equality(helpers.wait_for_mark_lines(child, { 0, 4 }), true)
        expect.equality(child.fn.getreg("/"), "Foo")
    end
end

return T
