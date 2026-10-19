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

local BUILTINS = {
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

local M = {}

--- Built-in preset names, sorted.
---@return string[]
M.names = function()
    local names = vim.tbl_keys(BUILTINS)
    table.sort(names)
    return names
end

--- Return a copy of the built-in preset `name`. Presets contain only
--- appearance options and are merged like any other appearance layer.
---@param name any
---@param path string
---@return table
M.get = function(name, path)
    if type(name) ~= "string" then
        schema.invalid(path .. " must be a string")
    end
    local preset = BUILTINS[name]
    if preset == nil then
        schema.invalid(
            string.format("%s: unknown preset '%s' (built-in presets: %s)", path, name, table.concat(M.names(), ", "))
        )
    end
    return vim.deepcopy(preset)
end

return M
