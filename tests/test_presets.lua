local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.presets"] = nil
        end,
    },
})

local function get(name)
    return require("scrollbar.presets").get(name, "scrollbar.preset")
end

local GIT_TYPES = {
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
}
local DIAGNOSTIC_TYPES = { "Error", "Warn", "Info", "Hint" }

local function expect_invalid(fn, pattern)
    local ok, err = pcall(fn)
    expect.equality(ok, false)
    if tostring(err):match(pattern) == nil then
        error(string.format("error %q does not match %q", tostring(err), pattern))
    end
end

T["returns exact isolated built-in presentation definitions"] = function()
    local builtins = {
        vscode = {
            layout = {
                direction = "auto",
                columns = {
                    {
                        "track",
                        {
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
                        { types = { "Error", "Warn", "Info", "Hint" } },
                        "thumb",
                    },
                },
            },
            thumb = { blend = 20 },
        },
        zed = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", { types = GIT_TYPES }, "thumb" },
                    { "track", "marks", "thumb" },
                    { "track", { types = DIAGNOSTIC_TYPES }, "thumb" },
                },
            },
            thumb = { blend = 20 },
        },
        intellij = {
            layout = {
                direction = "auto",
                columns = {
                    { { types = GIT_TYPES } },
                    { "track", "thumb", "marks", { types = DIAGNOSTIC_TYPES } },
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
                    { { types = { "Error", "Warn", "Info", "Hint" } } },
                },
            },
            thumb = { blend = 20 },
        },
        search = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", "thumb", { types = { "Cursor", "Search" } } },
                },
            },
            thumb = { blend = 20 },
        },
        navigate = {
            layout = {
                direction = "auto",
                columns = {
                    { "track", "thumb", { types = { "Cursor" } } },
                    { { types = { "Mark" }, max_width = 8 } },
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
                columns = { { "track", "thumb" }, { "marks" } },
            },
            thumb = { blend = 20 },
        },
        sublime = {
            layout = {
                direction = "auto",
                columns = { { "thumb", { types = { "Search" } } } },
            },
            thumb = { blend = 60 },
        },
        emacs = {
            placement = { anchor = "NW", gutter = "outer" },
            layout = {
                direction = "auto",
                columns = {
                    { { types = { "Error", "Warn", "Info", "Hint" } } },
                    { "track", "thumb" },
                },
            },
            thumb = { blend = 0 },
        },
        xcode = {
            layout = { direction = "auto", columns = { { "thumb" } } },
            thumb = { blend = 25 },
        },
    }

    for name, expected in pairs(builtins) do
        expect.equality(get(name), expected)
    end

    local vscode = get("vscode")
    vscode.layout.columns[1][1] = "changed"
    vscode.thumb.blend = 99
    expect.equality(get("vscode").layout.columns[1][1], "track")
    expect.equality(get("vscode").thumb.blend, 20)

    for name, expected in pairs(builtins) do
        local first = get(name)
        first.layout.columns[1][1] = "changed"
        expect.equality(get(name), expected)
    end

    local names = vim.tbl_keys(builtins)
    table.sort(names)
    expect.equality(require("scrollbar.presets").names(), names)
end

T["every built-in compiles as a root preset and as a profile preset"] = function()
    local config = require("scrollbar.config")
    for _, name in ipairs(require("scrollbar.presets").names()) do
        local root = config.set({ scrollbar = { preset = name } })
        expect.equality(root.thumb.blend, get(name).thumb.blend)

        config.set({ scrollbar = { profiles = { { match = { filetypes = { "lua" } }, preset = name } } } })
        local variants = config.get_variants()
        expect.equality(variants[2].config.thumb.blend, get(name).thumb.blend)
        expect.equality(variants[2].config.layout.width, #get(name).layout.columns)
    end
end

T["root options override the root preset and keep unset preset values"] = function()
    local result = require("scrollbar.config").set({
        scrollbar = {
            preset = "emacs",
            placement = { gutter = "overlap" },
            thumb = { text = "V" },
            layout = { columns = { { "marks" } } },
        },
    })

    expect.equality(result.placement.anchor, "NW")
    expect.equality(result.placement.gutter, "overlap")
    expect.equality(result.thumb.text, "V")
    expect.equality(result.thumb.blend, 0)
    expect.equality(result.layout.width, 1)
    expect.equality(result.layout.catchall_lane, 1)
end

T["replaces dense and known empty lists atomically"] = function()
    local merge = require("scrollbar.schema").merge
    local result = merge({
        layout = {
            columns = { { "track" }, { "thumb" } },
            descriptor = { types = { "Error", "Warn" } },
        },
        marks = { Search = { text = { "-", "=" } } },
        list = { "prompt", "terminal" },
        map = { a = 1, b = 2 },
    }, {
        layout = {
            columns = { { "marks" } },
            descriptor = { types = { "Search" } },
        },
        marks = { Search = { text = {} } },
        list = { "help" },
        map = { b = false },
    })

    expect.equality(result.layout.columns, { { "marks" } })
    expect.equality(result.layout.descriptor.types, { "Search" })
    expect.equality(result.marks.Search.text, {})
    expect.equality(result.list, { "help" })
    expect.equality(result.map, { a = 1, b = false })
end

T["rejects unknown and malformed preset names"] = function()
    expect_invalid(function()
        get("missing")
    end, "scrollbar.preset: unknown preset 'missing' %(built%-in presets: eclipse, emacs,")
    expect_invalid(function()
        get(1)
    end, "scrollbar.preset must be a string")
    expect_invalid(function()
        require("scrollbar.config").set({ scrollbar = { presets = {} } })
    end, "unknown option 'scrollbar.presets'")
end

return T
