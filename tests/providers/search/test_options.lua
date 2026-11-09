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

return T
