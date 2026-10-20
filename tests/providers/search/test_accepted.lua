local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_search_child(search_config)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    if search_config ~= nil then
        helpers.setup_search_config(child, search_config)
    else
        helpers.setup_search(child, false)
    end
    return child
end

T["default managed setup processes accepted searches"] = function()
    local child = new_search_child()
    helpers.set_lines(child, { "start", "direct", "direct" })
    helpers.accept_search(child, "/", "direct")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
end

T["providers.search=true processes later accepted searches"] = function()
    local child = new_search_child(true)
    helpers.set_lines(child, { "start", "roottrue", "roottrue" })
    helpers.accept_search(child, "/", "roottrue")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
end

T["accepted forward searches refresh marks"] = function()
    local child = new_search_child()
    helpers.set_lines(child, { "alpha", "beta", "alpha" })
    helpers.accept_search(child, "/", "alpha")
    expect.equality(helpers.wait_for_mark_lines(child, { 0, 2 }), true)
end

T["accepted backward searches refresh marks"] = function()
    local child = new_search_child()
    helpers.set_lines(child, { "alpha", "beta", "alpha" })
    child.api.nvim_win_set_cursor(0, { 3, 0 })
    helpers.accept_search(child, "?", "beta")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["SafeState synchronizes a changed accepted register pattern"] = function()
    local child = new_search_child()
    helpers.set_lines(child, { "old old", "unique" })
    helpers.activate_search(child, "unique")
    child.fn.setreg("/", "old")
    child.api.nvim_exec_autocmds("SafeState", {})
    expect.equality(helpers.mark_lines(child), { 0, 0 })
end

T["SafeState detects a normal search that does not move the cursor"] = function()
    local child = new_search_child()
    helpers.set_lines(child, { "old old", "unique" })
    helpers.activate_search(child, "old")
    child.api.nvim_win_set_cursor(0, { 2, 0 })
    local cursor = child.api.nvim_win_get_cursor(0)
    child.lua([[pcall(vim.cmd, "normal! *")]])
    expect.equality(child.api.nvim_win_get_cursor(0), cursor)
    child.api.nvim_exec_autocmds("SafeState", {})
    expect.equality(helpers.mark_lines(child), { 1 })
end

return T
