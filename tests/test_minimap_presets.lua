local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.minimap.presets"] = nil
        end,
    },
})

local function resolve(options)
    return require("scrollbar.minimap.presets").resolve(options)
end

local function expect_invalid(options, pattern)
    local ok, err = pcall(resolve, options)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

T["resolves the built-in default starter preset"] = function()
    local result = resolve({ preset = "default" })
    expect.equality(result.width, 16)
    expect.equality(result.height, false)
    expect.equality(result.float.placement.relative, "window")
    expect.equality(result.float.placement.anchor, "NE")
    expect.equality(result.float.placement.row, 0)
    expect.equality(result.float.placement.col, 0)
    expect.equality(result.float.placement.gutter, "overlap")
    expect.equality(result.float.placement.gutter_position, "inner")
    expect.equality(result.overlays.enabled, true)
    expect.equality(result.show_viewport, true)
    expect.equality(rawget(result, "show_cursor_row"), nil)
    expect.equality(result.preset, nil)
    expect.equality(result.presets, nil)
end

T["built-in preset resolution returns deep copies immune to mutation"] = function()
    local first = resolve({ preset = "default" })
    first.width = 999
    first.float.placement.anchor = "SW"
    local second = resolve({ preset = "default" })
    expect.equality(second.width, 16)
    expect.equality(second.float.placement.anchor, "NE")
end

T["supports extends inheritance from the default preset"] = function()
    local result = resolve({
        preset = "child",
        presets = {
            child = {
                extends = "default",
                width = 40,
            },
        },
    })
    expect.equality(result.width, 40)
    expect.equality(result.height, false)
    expect.equality(result.float.placement.anchor, "NE")
    expect.equality(result.show_viewport, true)
end

T["applies root overrides on top of preset values"] = function()
    local result = resolve({
        preset = "default",
        width = 60,
        show_viewport = false,
    })
    expect.equality(result.width, 60)
    expect.equality(result.show_viewport, false)
    expect.equality(result.float.placement.anchor, "NE")
end

T["rejects removed minimap preset fields"] = function()
    expect_invalid(
        { presets = { invalid = { background = { blend = 40 } } } },
        "minimap preset 'invalid' cannot set 'background'"
    )
    expect_invalid(
        { presets = { invalid = { float = { hide_on_cursor = false } } } },
        "minimap preset 'invalid' cannot set 'float.hide_on_cursor'"
    )
    expect_invalid(
        { presets = { invalid = { float = { blend = 20 } } } },
        "minimap preset 'invalid' cannot set 'float.blend'"
    )
    expect_invalid(
        { presets = { invalid = { syntax_highlighting = true } } },
        "minimap preset 'invalid' cannot set 'syntax_highlighting'"
    )
    expect_invalid(
        { presets = { invalid = { show_cursor_row = true } } },
        "minimap preset 'invalid' cannot set 'show_cursor_row'"
    )
    expect_invalid(
        { presets = { invalid = { providers = { cursor = false } } } },
        "minimap preset 'invalid' cannot set 'providers'"
    )
end

T["rejects unknown preset names"] = function()
    expect_invalid({ preset = "missing" }, "unknown minimap preset 'missing'")
end

T["rejects cycles in extends chains"] = function()
    expect_invalid(
        { presets = { first = { extends = "second" }, second = { extends = "first" } } },
        "minimap preset cycle"
    )
end

T["rejects malformed preset definitions"] = function()
    expect_invalid({ presets = { [1] = {} } }, "minimap preset names must")
    expect_invalid({ presets = { invalid = true } }, "minimap preset 'invalid' must be a table")
    expect_invalid({ presets = { invalid = { extends = 1 } } }, "minimap preset 'invalid'.extends must be a string")
    expect_invalid(
        { presets = { invalid = { unknown_field = true } } },
        "minimap preset 'invalid' cannot set 'unknown_field'"
    )
    expect_invalid(
        { presets = { invalid = { float = { zindex = 80 } } } },
        "minimap preset 'invalid' cannot set 'float.zindex'"
    )
    expect_invalid(
        { presets = { invalid = { float = { placement = { zindex = 80 } } } } },
        "minimap preset 'invalid' cannot set 'float.placement.zindex'"
    )
end

T["rejects bad preset values"] = function()
    expect_invalid(
        { presets = { invalid = { width = "wide" } } },
        "minimap preset 'invalid'.width must be false or a positive integer"
    )
    expect_invalid(
        { presets = { invalid = { height = -1 } } },
        "minimap preset 'invalid'.height must be false or a positive integer"
    )
    expect_invalid(
        { presets = { invalid = { show_viewport = 1 } } },
        "minimap preset 'invalid'.show_viewport must be a boolean"
    )
end

T["resolves custom inheritance independently of declaration order"] = function()
    local result = resolve({
        preset = "grandchild",
        presets = {
            grandchild = { extends = "child", width = 30 },
            base = { width = 100, height = 20 },
            child = { extends = "base", width = 60 },
        },
    })
    expect.equality(result.width, 30)
    expect.equality(result.height, 20)
end

T["deep merges keyed overlay specs and preserves tombstones"] = function()
    local merge = require("scrollbar.minimap.presets").merge
    local result = merge({
        overlays = {
            enabled = true,
            types = {
                Error = { priority = 2, highlight = "Error" },
                Warn = { priority = 3, highlight = "Warn" },
                Hint = { priority = 5, highlight = "Hint" },
            },
        },
    }, {
        overlays = {
            enabled = false,
            types = {
                Error = { priority = 0 },
                Warn = false,
            },
        },
    })
    expect.equality(result.overlays.enabled, false)
    expect.equality(result.overlays.types, {
        Error = { priority = 0, highlight = "Error" },
        Warn = false,
        Hint = { priority = 5, highlight = "Hint" },
    })
end

T["later layers can re-enable a tombstoned overlay"] = function()
    local merge = require("scrollbar.minimap.presets").merge
    local result = merge({
        overlays = { types = { Search = false } },
    }, {
        overlays = { types = { Search = { highlight = "Search" } } },
    })
    expect.equality(result.overlays.types.Search, { highlight = "Search" })
end

T["keeps every resolver call setup-local"] = function()
    expect.equality(resolve({ preset = "local", presets = { ["local"] = { width = 42 } } }).width, 42)
    expect_invalid({ preset = "local" }, "unknown minimap preset 'local'")
end

return T
