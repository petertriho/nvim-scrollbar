local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function incsearch_child(incsearch, native_incsearch)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.o.incsearch = native_incsearch
    helpers.setup_search(child, incsearch)
    return child
end

local function accepted_baseline(child)
    helpers.set_lines(child, { "start", "accepted", "preview", "preview" })
    helpers.accept_search(child, "/", "accepted")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["incsearch=false overrides the native option without changing it"] = function()
    local child = incsearch_child(false, true)
    helpers.set_lines(child, { "alpha", "beta beta", "alpha" })
    helpers.accept_search(child, "/", "beta")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 1 }), true)

    local capture = helpers.inspect_during_cmdline(child, "/", "alpha")
    expect.equality(capture.lines, { 1, 1 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 1 }), true)
    expect.equality(child.o.incsearch, true)
end

T["incsearch=true overrides the native option without changing it"] = function()
    local child = incsearch_child(true, false)
    accepted_baseline(child)

    local capture = helpers.inspect_during_cmdline(child, "/", "preview")
    expect.equality(capture.mode, "c")
    expect.equality(capture.lines, { 2, 3 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    expect.equality(child.o.incsearch, false)
end

T["omitted incsearch follows native changes without setup"] = function()
    local child = incsearch_child(nil, false)
    helpers.set_lines(child, { "alpha", "beta beta", "alpha" })
    helpers.accept_search(child, "/", "beta")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 1 }), true)

    expect.equality(helpers.inspect_during_cmdline(child, "/", "alpha").lines, { 1, 1 })
    child.o.incsearch = true
    expect.equality(helpers.inspect_during_cmdline(child, "/", "alpha").lines, { 0, 2 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 1 }), true)
end

T["incremental mode previews backward searches and restores accepted results"] = function()
    local child = incsearch_child(true, false)
    accepted_baseline(child)

    expect.equality(helpers.inspect_during_cmdline(child, "?", "preview").lines, { 2, 3 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["an empty incremental pattern retains accepted results"] = function()
    local child = incsearch_child(true, false)
    accepted_baseline(child)

    expect.equality(helpers.inspect_during_cmdline(child, "/", "").lines, { 1 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["invalid incremental patterns hide preview and cancellation restores accepted results"] = function()
    local child = incsearch_child(true, false)
    accepted_baseline(child)

    expect.equality(helpers.inspect_during_cmdline(child, "/", [[\(]]).lines, nil)
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["accepted incremental searches commit preview results"] = function()
    local child = incsearch_child(true, false)
    accepted_baseline(child)
    helpers.accept_search(child, "/", "preview")
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 3 }), true)
end

T["disabling native incsearch rejects a queued incremental request"] = function()
    local child = incsearch_child(nil, true)
    accepted_baseline(child)
    child.lua([[
        local state = { calls = {} }
        local searchpos = vim.fn.searchpos
        vim.fn.searchpos = function(pattern, flags, ...)
            table.insert(state.calls, { pattern = pattern, flags = flags })
            return searchpos(pattern, flags, ...)
        end
        package.loaded["scrollbar.test.search_scans"] = state
    ]])

    local result = child.lua_get([[(function()
        local changed
        for _, autocmd in ipairs(vim.api.nvim_get_autocmds({
            group = "ScrollbarProvider_search_events",
            event = "CmdlineChanged",
        })) do
            if type(autocmd.callback) == "function" then
                changed = autocmd.callback
                break
            end
        end
        assert(changed ~= nil, "CmdlineChanged callback is unavailable")

        local getcmdline = vim.fn.getcmdline
        rawset(vim.fn, "getcmdline", function()
            return "preview"
        end)
        changed()
        rawset(vim.fn, "getcmdline", getcmdline)
        vim.o.incsearch = false
        vim.wait(100)

        local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
        return {
            calls = package.loaded["scrollbar.test.search_scans"].calls,
            lines = marks and vim.tbl_map(function(mark)
                return mark.line
            end, marks) or nil,
        }
    end)()]])

    expect.equality(result.calls, {})
    expect.equality(result.lines, { 1 })
end

return T
