local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.config.presets"] = nil
            package.loaded["scrollbar.minimap.config"] = nil
        end,
    },
})

local function presets()
    return require("scrollbar.config.presets")
end

local function set_minimap(options)
    require("scrollbar.config").set({
        set_highlights = false,
        minimap = vim.tbl_extend("force", { enabled = true }, options),
    })
    return require("scrollbar.minimap.config").get()
end

local function expect_invalid(options, pattern)
    local ok, err = pcall(set_minimap, options)
    expect.equality(ok, false)
    if tostring(err):match(pattern) == nil then
        error(string.format("error %q does not match %q", tostring(err), pattern))
    end
end

local BUILTINS = {
    vscode = { scale = "fixed", encoding = "braille", columns_per_dot = 4, width = 15, viewport = true },
    sublime = {
        scale = "fixed",
        encoding = "braille",
        columns_per_dot = 2,
        width = 20,
        viewport = true,
        marks = false,
    },
    zed = { scale = "fixed", encoding = "braille", columns_per_dot = 4, width = 10, viewport = true },
    xcode = { scale = "fixed", encoding = "block", columns_per_dot = 4, width = 12, viewport = true },
    overview = { scale = "fit", encoding = "braille", columns_per_dot = 4, width = 10, viewport = true },
    compact = { scale = "fixed", encoding = "braille", columns_per_dot = 8, width = 8, viewport = true },
    minimal = {
        scale = "fixed",
        encoding = "braille",
        columns_per_dot = 4,
        width = 12,
        viewport = true,
        marks = false,
    },
    blocks = { scale = "fit", encoding = "block", columns_per_dot = 4, width = 16, viewport = true },
}

T["returns exact isolated built-in minimap presets"] = function()
    expect.equality(
        presets().names("minimap"),
        { "blocks", "compact", "minimal", "overview", "sublime", "vscode", "xcode", "zed" }
    )
    for name, expected in pairs(BUILTINS) do
        local preset = presets().get("minimap", name, "minimap.preset")
        expect.equality(preset, expected)
        preset.width = 99
        expect.equality(presets().get("minimap", name, "minimap.preset"), expected)
    end
end

T["minimap presets set only the grid, the width, the band, and hidden marks"] = function()
    local allowed = {
        scale = true,
        encoding = true,
        columns_per_dot = true,
        width = true,
        viewport = true,
        marks = true,
    }
    for _, name in ipairs(presets().names("minimap")) do
        for key, value in pairs(presets().get("minimap", name, "minimap.preset")) do
            expect.equality(allowed[key], true)
            if key == "marks" then
                expect.equality(value, false)
            end
        end
    end
end

T["scrollbar and minimap presets with the same name are separate"] = function()
    local scrollbar = presets().get("scrollbar", "vscode", "scrollbar.preset")
    local minimap = presets().get("minimap", "vscode", "minimap.preset")

    expect.no_equality(scrollbar.layout, nil)
    expect.equality(minimap.layout, nil)
    expect.equality(scrollbar.width, nil)
end

T["unknown minimap presets list the built-in names"] = function()
    expect_invalid(
        { preset = "atom" },
        "minimap%.preset: unknown preset 'atom' %(built%-in presets: "
            .. "blocks, compact, minimal, overview, sublime, vscode, xcode, zed%)"
    )
    expect_invalid({ preset = "review" }, "minimap%.preset: unknown preset 'review'")
end

T["a root preset sets the grid and keeps the other defaults"] = function()
    local config = set_minimap({ preset = "overview" })

    expect.equality(config.scale, "fit")
    expect.equality(config.encoding, "braille")
    expect.equality(config.columns_per_dot, 4)
    expect.equality(config.width, 10)
    expect.equality(config.viewport, true)
    expect.equality(config.height, false)
    expect.equality(config.blend, 0)
    expect.equality(config.mouse, true)
    expect.equality(config.placement.anchor, "NE")
    expect.no_equality(next(config.marks), nil)
    expect.equality(rawget(config, "preset"), nil)
end

T["root options win over the root preset"] = function()
    local config = set_minimap({ preset = "compact", width = 12, encoding = "block" })

    expect.equality(config.width, 12)
    expect.equality(config.encoding, "block")
    expect.equality(config.columns_per_dot, 8)
end

T["presets with marks false hide every overlay"] = function()
    expect.equality(set_minimap({ preset = "minimal" }).marks, {})
    expect.equality(set_minimap({ preset = "sublime" }).marks, {})
end

T["a marks table replaces the marks false of a preset"] = function()
    local config = set_minimap({ preset = "minimal", marks = { Error = { priority = 1 } } })

    expect.equality(config.marks.Error.priority, 1)
    expect.no_equality(config.marks.Warn, nil)
end

T["a preset does not change global minimap options"] = function()
    local config = set_minimap({ preset = "blocks", backend = "sync", throttle_ms = 10 })

    expect.equality(config.enabled, true)
    expect.equality(config.backend, "sync")
    expect.equality(config.throttle_ms, 10)
    expect.equality(config.width, 16)
    expect.equality(config.encoding, "block")
    expect.equality(config.scale, "fit")
end

return T
