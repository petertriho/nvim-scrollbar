local schema = require("scrollbar.schema")

local DIAGNOSTIC_TYPES = { "Error", "Warn", "Info", "Hint" }
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

local SCROLLBAR = {
    vscode = {
        layout = {
            direction = "auto",
            columns = {
                {
                    "track",
                    { types = GIT_TYPES },
                    "thumb",
                },
                { "track", "marks", "thumb" },
                {
                    "track",
                    { types = DIAGNOSTIC_TYPES },
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
                {
                    "track",
                    { types = GIT_TYPES },
                    "thumb",
                },
                { "track", "marks", "thumb" },
                {
                    "track",
                    { types = DIAGNOSTIC_TYPES },
                    "thumb",
                },
            },
        },
        thumb = { blend = 20 },
    },
    intellij = {
        layout = {
            direction = "auto",
            columns = {
                { { types = GIT_TYPES } },
                {
                    "track",
                    "thumb",
                    "marks",
                    { types = DIAGNOSTIC_TYPES },
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
                { { types = GIT_TYPES } },
                { "track", "thumb" },
                { { types = DIAGNOSTIC_TYPES } },
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
                { { types = DIAGNOSTIC_TYPES } },
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

-- Minimap presets set only the grid, the width, and the viewport band. The
-- presets without overlays also set `marks = false`. They keep the
-- placement, the blend, the height, and the mouse of the user.
local MINIMAP = {
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

local CATALOGS = {
    scrollbar = SCROLLBAR,
    minimap = MINIMAP,
}

local M = {}

---@param renderer "scrollbar"|"minimap"
---@return table<string, table>
local function catalog(renderer)
    return assert(CATALOGS[renderer], "unknown preset renderer")
end

--- Built-in preset names of `renderer`, sorted.
---@param renderer "scrollbar"|"minimap"
---@return string[]
M.names = function(renderer)
    local names = vim.tbl_keys(catalog(renderer))
    table.sort(names)
    return names
end

--- Return a copy of the built-in `renderer` preset `name`. Presets contain
--- only appearance options and are merged like any other appearance layer.
---@param renderer "scrollbar"|"minimap"
---@param name any
---@param path string
---@return table
M.get = function(renderer, name, path)
    if type(name) ~= "string" then
        schema.invalid(path .. " must be a string")
    end
    local preset = catalog(renderer)[name]
    if preset == nil then
        local names = M.names(renderer)
        local listed = #names > 0 and table.concat(names, ", ") or "none"
        schema.invalid(string.format("%s: unknown preset '%s' (built-in presets: %s)", path, name, listed))
    end
    return vim.deepcopy(preset)
end

--- Layer the appearance sources in precedence order onto `defaults`: the
--- root preset, the root options, the profile preset, and the profile
--- options.
---@param renderer "scrollbar"|"minimap"
---@param defaults table
---@param root table Root options of the renderer block
---@param profile? { input: table, path: string }
---@return table
M.layered = function(renderer, defaults, root, profile)
    local result = {}
    if root.preset ~= nil then
        result = schema.merge(result, M.get(renderer, root.preset, renderer .. ".preset"))
    end
    result = schema.merge(result, schema.without(root, { "preset", "profiles" }))
    if profile ~= nil then
        if profile.input.preset ~= nil then
            result = schema.merge(result, M.get(renderer, profile.input.preset, profile.path .. ".preset"))
        end
        result = schema.merge(result, schema.without(profile.input, { "match", "preset" }))
    end
    return schema.merge(defaults, result)
end

return M
