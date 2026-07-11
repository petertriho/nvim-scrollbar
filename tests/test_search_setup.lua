local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

T["direct setup rejects a non-boolean live option without mutation"] = function()
    local child = new_child()
    helpers.setup_search(child, false)
    local result = child.lua_get([[(function()
        local config = require("scrollbar.config").get()
        local before = vim.deepcopy(config.handlers.search)
        local ok, err = pcall(require("scrollbar.handlers.search").setup, { live = "yes" })
        return { ok = ok, error = err, before = before, after = config.handlers.search }
    end)()]])

    expect.equality(result.ok, false)
    expect.no_equality(result.error:match("live must be a boolean"), nil)
    expect.equality(result.after, result.before)
end

T["root setup rejects a non-boolean live option without mutation"] = function()
    local child = new_child()
    helpers.setup_search(child, false)
    local result = child.lua_get([[(function()
        local config = require("scrollbar.config").get()
        local before = vim.deepcopy(config.handlers.search)
        local ok, err = pcall(require("scrollbar").setup, { handlers = { search = { live = "yes" } } })
        return { ok = ok, error = err, before = before, after = config.handlers.search }
    end)()]])

    expect.equality(result.ok, false)
    expect.no_equality(result.error:match("live must be a boolean"), nil)
    expect.equality(result.after, result.before)
end

T["handlers.search=true normalizes configuration and scans an existing search"] = function()
    local child = new_child()
    helpers.set_lines(child, { "foo", "Foo" })
    helpers.activate_search(child, "Foo")
    helpers.setup_root_search(child, true)

    expect.equality(child.lua_get([[require("scrollbar.config").get().handlers.search]]), { live = false })
    expect.equality(helpers.mark_lines(child), { 1 })
    expect.equality(#child.api.nvim_get_autocmds({ group = "scrollbar_search", event = "CmdlineLeave" }), 1)
end

T["repeated setup is idempotent across root and direct entry points"] = function()
    local child = new_child()
    helpers.setup_root_search(child, true)
    helpers.setup_search(child, false)

    expect.equality(child.lua_get([[require("scrollbar.config").get().handlers.search]]), { live = false })
    expect.equality(#child.api.nvim_get_autocmds({ group = "scrollbar_search", event = "CmdlineLeave" }), 1)
end

T["root table search setup processes accepted searches"] = function()
    local child = new_child()
    helpers.setup_root_search(child, { live = false })
    helpers.set_lines(child, { "start", "root", "root" })
    helpers.accept_search(child, "/", "root")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
end

return T
