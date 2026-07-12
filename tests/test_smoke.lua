local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

T["loads and sets up in a clean child process"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    expect.no_error(function()
        child.lua([[
            require("scrollbar").setup({
                set_highlights = false,
                render = { interval_ms = 0 },
                providers = {
                    cursor = false,
                    diagnostic = false,
                    gitsigns = false,
                    search = false,
                    ale = false,
                    coc = false,
                },
            })
        ]])
    end)
    expect.equality(child.fn.exists(":ScrollbarToggle"), 2)
    expect.equality(child.fn.exists(":ScrollbarShow"), 2)
    expect.equality(child.fn.exists(":ScrollbarHide"), 2)
    expect.equality(child.fn.exists(":ScrollbarRefresh"), 2)
end

return T
