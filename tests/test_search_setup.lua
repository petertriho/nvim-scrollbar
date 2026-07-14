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

T["configuration rejects a non-boolean incsearch option without mutation"] = function()
    local child = new_child()
    helpers.setup_search(child, false)
    local result = child.lua_get([[(function()
        local config = require("scrollbar.config").get()
        local before = vim.deepcopy(config.providers.search)
        local ok, err = pcall(require("scrollbar.config").set, { providers = { search = { incsearch = "yes" } } })
        return {
            ok = ok,
            error = err,
            before = before,
            after = require("scrollbar.config").get().providers.search,
        }
    end)()]])

    expect.equality(result.ok, false)
    expect.no_equality(result.error:match("incsearch must be a boolean"), nil)
    expect.equality(result.after, result.before)
end

T["a rejected legacy reconfiguration leaves the managed provider active"] = function()
    local child = new_child()
    helpers.setup_search(child, false)
    local result = child.lua_get([[(function()
        local config = require("scrollbar.config").get()
        local before = vim.deepcopy(config.providers.search)
        local ok, err = pcall(require("scrollbar.config").set, { providers = { search = { live = true } } })
        return {
            ok = ok,
            error = err,
            before = before,
            after = require("scrollbar.config").get().providers.search,
        }
    end)()]])

    expect.equality(result.ok, false)
    expect.no_equality(result.error:match("unknown option 'providers.search.live'"), nil)
    expect.equality(result.after, result.before)
    helpers.set_lines(child, { "start", "active", "active" })
    helpers.accept_search(child, "/", "active")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
end

T["providers.search=true normalizes configuration and scans an existing search"] = function()
    local child = new_child()
    helpers.set_lines(child, { "foo", "Foo" })
    helpers.activate_search(child, "Foo")
    helpers.setup_search_config(child, true)

    expect.equality(child.lua_get([[require("scrollbar.config").get().providers.search]]), {
        backend = "worker",
    })
    expect.equality(helpers.mark_lines(child), { 1 })
    expect.equality(
        #child.api.nvim_get_autocmds({ group = "ScrollbarProvider_search_events", event = "CmdlineLeave" }),
        1
    )
end

T["production setup starts one shared search worker"] = function()
    local child = new_child()
    child.lua([[
        package.loaded["scrollbar.test.jobstarts"] = 0
        local jobstart = vim.fn.jobstart
        rawset(vim.fn, "jobstart", function(...)
            package.loaded["scrollbar.test.jobstarts"] = package.loaded["scrollbar.test.jobstarts"] + 1
            return jobstart(...)
        end)
    ]])

    helpers.setup_search_default(child, true)
    expect.equality(helpers.wait_for_worker_status(child, "ready"), true)
    helpers.set_lines(child, { "start", "production", "production" })
    helpers.accept_search(child, "/", "production")

    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
    expect.equality(child.lua_get([=[package.loaded["scrollbar.test.jobstarts"]]=]), 1)
    expect.equality(child.lua_get([[require("scrollbar.providers.search_worker").status().state]]), "ready")
end

T["providers.search.backend=sync disables child startup"] = function()
    local child = new_child()
    child.lua([[
        package.loaded["scrollbar.test.jobstarts"] = 0
        local jobstart = vim.fn.jobstart
        rawset(vim.fn, "jobstart", function(...)
            package.loaded["scrollbar.test.jobstarts"] = package.loaded["scrollbar.test.jobstarts"] + 1
            return jobstart(...)
        end)
    ]])

    helpers.setup_search_default_config(child, { incsearch = false, backend = "sync" })
    helpers.set_lines(child, { "start", "synchronous", "synchronous" })
    helpers.accept_search(child, "/", "synchronous")

    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
    expect.equality(child.lua_get([=[package.loaded["scrollbar.test.jobstarts"]]=]), 0)
    expect.equality(child.lua_get([[require("scrollbar.providers.search_worker").status().state]]), "disposed")
end

T["repeated provider manager setup is idempotent"] = function()
    local child = new_child()
    helpers.setup_search_config(child, true)
    helpers.setup_search(child, false)

    expect.equality(child.lua_get([[require("scrollbar.config").get().providers.search]]), {
        incsearch = false,
        backend = "worker",
    })
    expect.equality(
        #child.api.nvim_get_autocmds({ group = "ScrollbarProvider_search_events", event = "CmdlineLeave" }),
        1
    )
end

T["table search configuration processes accepted searches"] = function()
    local child = new_child()
    helpers.setup_search_config(child, { incsearch = false })
    helpers.set_lines(child, { "start", "root", "root" })
    helpers.accept_search(child, "/", "root")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
end

T["unregister disposes events and clears provider marks"] = function()
    local child = new_child()
    helpers.setup_search_config(child, true)
    helpers.set_lines(child, { "search", "search" })
    helpers.accept_search(child, "/", "search")
    expect.equality(helpers.wait_for_mark_lines(child, { 0, 1 }), true)

    expect.equality(child.lua_get([[require("scrollbar.providers").unregister("search")]]), true)
    expect.equality(helpers.search_marks(child), nil)
    expect.equality(
        pcall(child.api.nvim_get_autocmds, { group = "ScrollbarProvider_search_events", event = "CmdlineLeave" }),
        false
    )
end

return T
