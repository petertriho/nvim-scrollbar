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
            require("scrollbar").setup({ scrollbar = {
                set_highlights = false,
                update = { interval_ms = 0 },
                providers = {
                    cursor = false,
                    diagnostic = false,
                    gitsigns = false,
                    search = false,
                    ale = false,
                    coc = false,
                },
            } })
        ]])
    end)
    expect.equality(child.fn.exists(":ScrollbarToggle"), 2)
    expect.equality(child.fn.exists(":ScrollbarShow"), 2)
    expect.equality(child.fn.exists(":ScrollbarHide"), 2)
    expect.equality(child.fn.exists(":ScrollbarRefresh"), 2)
end

T["enables accepted search and leaves Coc disabled by default"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = {
                set_highlights = false,
                update = { interval_ms = 0 },
                mouse = { enabled = false },
            },
        })

        local config = require("scrollbar.config").get()
        local providers = require("scrollbar.providers")
        return {
            search = config.providers.search,
            coc = config.providers.coc,
            search_registered = providers.get("search") ~= nil,
            coc_registered = providers.get("coc") ~= nil,
        }
    end)

    expect.equality(result, {
        search = { backend = "worker" },
        coc = false,
        search_registered = true,
        coc_registered = false,
    })
end

return T
