local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.shared.stack"] = nil
        end,
    },
})

local function stack()
    return require("scrollbar.shared.stack")
end

local function scrollbar(overrides)
    return vim.tbl_extend("force", {
        relative = "window",
        side = "E",
        origin = 80,
        col = 0,
        width = 1,
        zindex = 50,
    }, overrides or {})
end

local function minimap(overrides)
    return vim.tbl_extend("force", {
        relative = "window",
        side = "E",
        origin = 80,
        col = 0,
        width = 16,
        zindex = 50,
        stack = "inner",
    }, overrides or {})
end

local function resolve(renderer, own)
    local origin, zindex = stack().resolve(renderer, 1000, own)
    return { origin = origin, zindex = zindex }
end

T["keeps the own origin without another footprint"] = function()
    expect.equality(resolve("minimap", minimap()), { zindex = 50 })
    expect.equality(resolve("scrollbar", scrollbar()), { zindex = 50 })
end

T["inner places the minimap at the inward edge of an east scrollbar"] = function()
    stack().publish("scrollbar", 1000, scrollbar({ width = 3, col = -1 }))

    expect.equality(resolve("minimap", minimap()), { origin = 76, zindex = 50 })
    expect.equality(resolve("scrollbar", scrollbar({ width = 3, col = -1 })), { zindex = 50 })
end

T["outer places the scrollbar at the inward edge of an east minimap"] = function()
    stack().publish("minimap", 1000, minimap({ stack = "outer", col = -2 }))

    expect.equality(resolve("scrollbar", scrollbar()), { origin = 62, zindex = 50 })
    expect.equality(resolve("minimap", minimap({ stack = "outer", col = -2 })), { zindex = 50 })
end

T["west inward edges add the width"] = function()
    stack().publish("scrollbar", 1000, scrollbar({ side = "W", origin = 4, col = 1, width = 2 }))
    expect.equality(resolve("minimap", minimap({ side = "W", origin = 0 })), { origin = 7, zindex = 50 })

    stack().publish("scrollbar", 1000, nil)
    stack().publish("minimap", 1000, minimap({ side = "W", origin = 0, stack = "outer", col = 1 }))
    expect.equality(resolve("scrollbar", scrollbar({ side = "W", origin = 4 })), { origin = 17, zindex = 50 })
end

T["does not stack a pair on different sides or with mixed relative modes"] = function()
    stack().publish("scrollbar", 1000, scrollbar({ side = "W" }))
    expect.equality(resolve("minimap", minimap()), { zindex = 50 })

    stack().publish("scrollbar", 1000, scrollbar({ relative = "editor" }))
    expect.equality(resolve("minimap", minimap()), { zindex = 50 })

    stack().publish("scrollbar", 1000, scrollbar())
    expect.equality(stack().resolve("minimap", 1001, minimap()), nil)
end

T["breaks equal z-index ties for above and below"] = function()
    stack().publish("scrollbar", 1000, scrollbar())
    expect.equality(resolve("minimap", minimap({ stack = "above" })), { zindex = 50 })
    expect.equality(resolve("minimap", minimap({ stack = "below" })), { zindex = 49 })

    stack().publish("minimap", 1000, minimap({ stack = "above" }))
    expect.equality(resolve("scrollbar", scrollbar()), { zindex = 49 })
    stack().publish("minimap", 1000, minimap({ stack = "below" }))
    expect.equality(resolve("scrollbar", scrollbar()), { zindex = 50 })
end

T["raises the top float when both z-indexes are 1"] = function()
    stack().publish("scrollbar", 1000, scrollbar({ zindex = 1 }))
    expect.equality(resolve("minimap", minimap({ stack = "above", zindex = 1 })), { zindex = 2 })
    expect.equality(resolve("minimap", minimap({ stack = "below", zindex = 1 })), { zindex = 1 })
end

T["keeps different explicit z-indexes"] = function()
    stack().publish("scrollbar", 1000, scrollbar({ zindex = 60 }))
    expect.equality(resolve("minimap", minimap({ stack = "above", zindex = 40 })), { zindex = 40 })
    expect.equality(resolve("minimap", minimap({ stack = "below", zindex = 70 })), { zindex = 70 })
end

T["does not change z-indexes in side-by-side modes"] = function()
    stack().publish("scrollbar", 1000, scrollbar())
    expect.equality(resolve("minimap", minimap({ stack = "outer" })).zindex, 50)
    stack().publish("minimap", 1000, minimap({ stack = "outer" }))
    expect.equality(resolve("scrollbar", scrollbar()).zindex, 50)
end

T["repositions the other renderer only when a footprint changes"] = function()
    local calls = {}
    stack().register("minimap", function(source_win)
        calls[#calls + 1] = source_win
    end)

    stack().publish("scrollbar", 1000, scrollbar())
    stack().publish("scrollbar", 1000, scrollbar())
    expect.equality(calls, { 1000 })

    stack().publish("scrollbar", 1000, scrollbar({ width = 2 }))
    expect.equality(calls, { 1000, 1000 })

    stack().publish("scrollbar", 1000, nil)
    stack().publish("scrollbar", 1000, nil)
    expect.equality(calls, { 1000, 1000, 1000 })

    stack().publish("scrollbar", 1000, scrollbar(), { notify = false })
    expect.equality(calls, { 1000, 1000, 1000 })
    expect.equality(stack().footprint("scrollbar", 1000), scrollbar())

    stack().publish("minimap", 1000, minimap())
    expect.equality(calls, { 1000, 1000, 1000 })
end

T["stops nested repositions and survives reposition errors"] = function()
    local scrollbar_calls = 0
    local minimap_calls = 0
    stack().register("scrollbar", function()
        scrollbar_calls = scrollbar_calls + 1
    end)
    stack().register("minimap", function(source_win)
        minimap_calls = minimap_calls + 1
        stack().publish("minimap", source_win, minimap({ width = minimap_calls }))
        error("reposition failed")
    end)

    stack().publish("scrollbar", 1000, scrollbar())
    expect.equality(minimap_calls, 1)
    expect.equality(scrollbar_calls, 0)
    expect.equality(stack().footprint("minimap", 1000).width, 1)

    stack().publish("scrollbar", 1000, scrollbar({ width = 2 }))
    expect.equality(minimap_calls, 2)
end

T["clear removes one renderer and reset removes everything"] = function()
    local calls = {}
    stack().register("minimap", function(source_win)
        calls[#calls + 1] = source_win
    end)
    stack().publish("scrollbar", 1000, scrollbar(), { notify = false })
    stack().publish("scrollbar", 1001, scrollbar(), { notify = false })
    stack().publish("minimap", 1000, minimap())

    stack().clear("scrollbar")
    table.sort(calls)
    expect.equality(calls, { 1000, 1001 })
    expect.equality(stack().windows("scrollbar"), {})
    expect.equality(stack().windows("minimap"), { 1000 })

    stack().reset()
    expect.equality(stack().windows("minimap"), {})
    stack().publish("scrollbar", 1000, scrollbar())
    expect.equality(#calls, 2)
end

return T
