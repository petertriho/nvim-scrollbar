local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function live_child(live)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, live)
    return child
end

local function accepted_baseline(child)
    helpers.set_lines(child, { "start", "accepted", "preview", "preview" })
    helpers.accept_search(child, "/", "accepted")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["live=false neither previews nor replaces accepted results on cancellation"] = function()
    local child = live_child(false)
    helpers.set_lines(child, { "alpha", "beta beta", "alpha" })
    helpers.accept_search(child, "/", "beta")
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 1 }), true)

    local capture = helpers.inspect_during_cmdline(child, "/", "alpha")
    expect.equality(capture.lines, { 1, 1 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 1 }), true)
end

T["live mode previews forward searches and restores accepted results on cancellation"] = function()
    local child = live_child(true)
    accepted_baseline(child)

    local capture = helpers.inspect_during_cmdline(child, "/", "preview")
    expect.equality(capture.mode, "c")
    expect.equality(capture.lines, { 2, 3 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["live mode previews backward searches and restores accepted results"] = function()
    local child = live_child(true)
    accepted_baseline(child)

    expect.equality(helpers.inspect_during_cmdline(child, "?", "preview").lines, { 2, 3 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["invalid live patterns hide preview and cancellation restores accepted results"] = function()
    local child = live_child(true)
    accepted_baseline(child)

    expect.equality(helpers.inspect_during_cmdline(child, "/", [[\(]]).lines, nil)
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["accepted live searches commit preview results"] = function()
    local child = live_child(true)
    accepted_baseline(child)
    helpers.accept_search(child, "/", "preview")
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 3 }), true)
end

return T
