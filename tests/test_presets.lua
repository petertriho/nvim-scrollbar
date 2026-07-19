local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.presets"] = nil
        end,
    },
})

local function resolve(options)
    return require("scrollbar.presets").resolve(options)
end

local function expect_invalid(options, pattern)
    local ok, err = pcall(resolve, options)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

T["resolves exact isolated built-in presentation definitions"] = function()
    local builtins = {
        vscode = {
            layout = {
                direction = "auto",
                columns = {
                    {
                        "track",
                        {
                            kind = "marks",
                            types = {
                                "GitAdd",
                                "GitChange",
                                "GitDelete",
                                "MiniDiffAdd",
                                "MiniDiffChange",
                                "MiniDiffDelete",
                                "SignifyAdd",
                                "SignifyChange",
                                "SignifyDelete",
                                "VGitAdd",
                                "VGitChange",
                                "VGitDelete",
                            },
                        },
                        "thumb",
                    },
                    { "track", "marks", "thumb" },
                    {
                        "track",
                        { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } },
                        "thumb",
                    },
                },
            },
            thumb = { blend = 20 },
        },
        zed = {
            layout = { direction = "auto", columns = { { "track", "thumb", "marks" } } },
            thumb = { blend = 20 },
        },
        intellij = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", "thumb" },
                    {
                        { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } },
                        "marks",
                    },
                },
            },
            thumb = { blend = 25 },
        },
        minimal = {
            layout = { direction = "auto", columns = { { "thumb" } } },
            thumb = { blend = 20 },
        },
        review = {
            layout = {
                direction = "auto",
                columns = {
                    {
                        {
                            kind = "marks",
                            types = {
                                "GitAdd",
                                "GitChange",
                                "GitDelete",
                                "MiniDiffAdd",
                                "MiniDiffChange",
                                "MiniDiffDelete",
                                "SignifyAdd",
                                "SignifyChange",
                                "SignifyDelete",
                                "VGitAdd",
                                "VGitChange",
                                "VGitDelete",
                            },
                        },
                    },
                    { "track", "thumb" },
                    { { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } } },
                },
            },
            thumb = { blend = 20 },
        },
        search = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", "thumb", { kind = "marks", types = { "Cursor", "Search" } } },
                },
            },
            thumb = { blend = 20 },
        },
        navigate = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", "thumb", { kind = "marks", types = { "Cursor" } } },
                    { { kind = "marks", types = { "Mark" }, max_width = 8 } },
                },
            },
            thumb = { blend = 20 },
        },
        gvim = {
            layout = {
                direction = "auto",
                columns = { { "track", "thumb" }, { "track", "thumb" } },
            },
            thumb = { blend = 0 },
        },
        eclipse = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", "thumb" },
                    { { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } } },
                    { { kind = "marks", types = { "Cursor", "Search", "Mark" } } },
                    { "marks" },
                },
            },
            thumb = { blend = 20 },
        },
        sublime = {
            layout = { direction = "auto", columns = { { "thumb", "marks" } } },
            thumb = { blend = 60 },
        },
        emacs = {
            float = { placement = { anchor = "NW", gutter = "avoid", gutter_position = "outer" } },
            layout = {
                direction = "auto",
                columns = {
                    { { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } } },
                    { "track", "thumb" },
                },
            },
            thumb = { blend = 0 },
        },
        xcode = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", "thumb" },
                    { { kind = "marks", types = { "Cursor", "Search", "Mark" } } },
                    { { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } } },
                },
            },
            thumb = { blend = 25 },
        },
    }

    for name, expected in pairs(builtins) do
        expect.equality(resolve({ preset = name }), expected)
    end

    local vscode = resolve({ preset = "vscode" })
    vscode.layout.columns[1][1] = "changed"
    vscode.thumb.blend = 99
    expect.equality(resolve({ preset = "vscode" }).layout.columns[1][1], "track")
    expect.equality(resolve({ preset = "vscode" }).thumb.blend, 20)

    for name, expected in pairs(builtins) do
        local first = resolve({ preset = name })
        first.layout.columns[1][1] = "changed"
        expect.equality(resolve({ preset = name }), expected)
    end
end

T["supports overlays inheritance and atomic layout replacement for every new built-in"] = function()
    local names = { "minimal", "review", "search", "navigate", "gvim", "eclipse", "sublime", "emacs", "xcode" }

    for _, name in ipairs(names) do
        local overlaid = resolve({
            preset = name,
            presets = { [name] = { thumb = { text = name } } },
        })
        expect.equality(overlaid.thumb.text, name)

        local inherited = resolve({
            preset = "child",
            presets = {
                child = {
                    extends = name,
                    layout = { columns = { { "marks" } } },
                },
            },
        })
        expect.equality(inherited.layout.columns, { { "marks" } })
        expect.equality(inherited.layout.direction, "auto")
    end
end

T["applies built-in overlays inheritance and root overrides deterministically"] = function()
    local result = resolve({
        preset = "child",
        presets = {
            child = {
                extends = "vscode",
                float = { placement = { gutter = "overlap", gutter_position = "outer" } },
                thumb = { blend = 30 },
                marks = { Search = { text = { "C" } } },
            },
            vscode = {
                thumb = { text = "V" },
                marks = { Search = { text = { "V", "S" } } },
            },
        },
        thumb = { blend = 40 },
        marks = { Search = { text = { "R" } } },
    })

    expect.equality(result.layout.columns[1][1], "track")
    expect.equality(result.float.placement.gutter, "overlap")
    expect.equality(result.float.placement.gutter_position, "outer")
    expect.equality(result.thumb, { text = "V", blend = 40 })
    expect.equality(result.marks.Search.text, { "R" })
    expect.equality(result.preset, nil)
    expect.equality(result.presets, nil)
end

T["resolves custom inheritance independently of declaration order"] = function()
    local options = {
        preset = "grandchild",
        presets = {
            grandchild = { extends = "child", thumb = { blend = 35 } },
            base = { track = { highlight = "Normal" }, thumb = { text = "B", blend = 10 } },
            child = { extends = "base", thumb = { text = "C" } },
        },
    }

    expect.equality(resolve(options), {
        track = { highlight = "Normal" },
        thumb = { text = "C", blend = 35 },
    })
end

T["replaces dense and known empty lists atomically"] = function()
    local merge = require("scrollbar.presets").merge
    local result = merge({
        layout = {
            columns = { { "track" }, { "thumb" } },
            descriptor = { types = { "Error", "Warn" } },
        },
        marks = { Search = { text = { "-", "=" } } },
        excluded_filetypes = { "prompt", "terminal" },
    }, {
        layout = {
            columns = { { "marks" } },
            descriptor = { types = { "Search" } },
        },
        marks = { Search = { text = {} } },
        excluded_filetypes = { "help" },
    })

    expect.equality(result.layout.columns, { { "marks" } })
    expect.equality(result.layout.descriptor.types, { "Search" })
    expect.equality(result.marks.Search.text, {})
    expect.equality(result.excluded_filetypes, { "help" })
end

T["rejects unknown names parents cycles malformed definitions and disallowed fields"] = function()
    expect_invalid({ preset = "missing" }, "unknown preset 'missing'")
    expect_invalid({ presets = { child = { extends = "missing" } } }, "unknown parent preset 'missing'")
    expect_invalid({ presets = { first = { extends = "second" }, second = { extends = "first" } } }, "preset cycle")
    expect_invalid({ presets = { [1] = {} } }, "preset names must")
    expect_invalid({ presets = { invalid = true } }, "preset 'invalid' must be a table")
    expect_invalid({ presets = { invalid = { extends = 1 } } }, "preset 'invalid'.extends must be a string")
    expect_invalid({ presets = { invalid = { providers = {} } } }, "preset 'invalid' cannot set 'providers'")
    expect_invalid(
        { presets = { invalid = { float = { zindex = 80 } } } },
        "preset 'invalid' cannot set 'float.zindex'"
    )
    expect_invalid(
        { presets = { invalid = { float = { placement = { zindex = 80 } } } } },
        "preset 'invalid' cannot set 'float.placement.zindex'"
    )
    expect_invalid({ presets = { invalid = { thumb = { column = 1 } } } }, "preset 'invalid' cannot set 'thumb.column'")
end

T["keeps every resolver call setup-local"] = function()
    expect.equality(resolve({ preset = "local", presets = { ["local"] = { thumb = { text = "L" } } } }).thumb.text, "L")
    expect_invalid({ preset = "local" }, "unknown preset 'local'")
end

return T
