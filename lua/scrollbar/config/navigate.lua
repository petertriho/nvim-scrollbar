--- Options of the features that move to and inspect the marks: `scrollbar.jump`
--- and `scrollbar.hover` in the scrollbar block, and the top-level `peek` and
--- `glance` blocks. Profiles do not change them.

local frame = require("scrollbar.navigate.frame")
local schema = require("scrollbar.config.schema")
local window_config = require("scrollbar.config.window")

local invalid = schema.invalid

local M = {}

M.JUMP_DEFAULTS = {
    labels = "asdfghjklqwertyuiopzxcvbnm",
    offset = 0,
}

local HOVER_DEFAULTS = { delay_ms = 300 }

--- Keys of the scrollbar block that only its root accepts.
M.SCROLLBAR_KEYS = {
    jump = { labels = true, offset = true },
    hover = { delay_ms = true },
}

local PEEK_DEFAULTS = {
    frame = "scrollbar",
    window = {},
}

local PEEK_KEYS = {
    frame = true,
    -- `scrollbar.config.window` validates the keys of `window`.
    window = { ["*"] = true },
}

local GLANCE_DEFAULTS = {
    frame = "cursor",
    list = {
        entries = "line",
        width = 0.4,
        side = "right",
    },
    keys = {
        list = {
            jump = "<CR>",
            jump_split = false,
            jump_vsplit = false,
            next = false,
            previous = false,
            focus_preview = "<Tab>",
            quickfix = false,
            close = { "q", "<Esc>" },
        },
        preview = {
            jump_split = false,
            jump_vsplit = false,
            next = false,
            previous = false,
            focus_list = false,
            close = false,
        },
    },
    window = {},
}

local GLANCE_PANES = { "list", "preview" }

-- The actions of each pane, in the order of the errors about a key that two
-- actions of a pane share.
local GLANCE_ACTIONS = {
    list = { "jump", "jump_split", "jump_vsplit", "next", "previous", "focus_preview", "quickfix", "close" },
    preview = { "jump_split", "jump_vsplit", "next", "previous", "focus_list", "close" },
}

---@param actions string[]
---@return table<string, true>
local function action_spec(actions)
    local result = {}
    for _, action in ipairs(actions) do
        result[action] = true
    end
    return result
end

local GLANCE_KEYS = {
    frame = true,
    list = { entries = true, width = true, side = true },
    keys = {
        list = action_spec(GLANCE_ACTIONS.list),
        preview = action_spec(GLANCE_ACTIONS.preview),
    },
    window = { ["*"] = true },
}

-- `nvim_open_win` keys that the peek float and the glance panes set.
local FLOAT_KEYS = {
    "relative",
    "win",
    "bufpos",
    "anchor",
    "row",
    "col",
    "width",
    "height",
    "focusable",
    "hide",
    "style",
    "external",
    "split",
    "vertical",
    "noautocmd",
    "fixed",
}

---@param owner string
---@param hints table<string, string>
---@return ScrollbarWindowSpec
local function window_spec(owner, hints)
    local owned = {}
    for _, key in ipairs(FLOAT_KEYS) do
        owned[key] = hints[key] or true
    end
    return {
        owned_keys = owned,
        owner = owner,
        renderer_keys = false,
        keep_winborder = true,
        text_area_options = true,
    }
end

---@param option string
---@return table<string, string>
local function frame_hints(option)
    local hint = string.format("use '%s'", option)
    return { relative = hint, row = hint, col = hint, width = hint, height = hint }
end

local PEEK_WINDOW_SPEC = window_spec("the peek float", frame_hints("peek.frame"))

local GLANCE_WINDOW_SPEC = window_spec("the glance window", frame_hints("glance.frame"))

---@param value any
---@param path string
---@return ScrollbarJumpConfig
M.jump = function(value, path)
    local jump = schema.table(value, path)
    local labels_path = path .. ".labels"
    local labels = jump.labels
    if type(labels) ~= "string" or labels == "" then
        invalid(labels_path .. " must be a non-empty string")
    end
    local seen = {}
    for index = 1, #labels do
        local label = labels:sub(index, index)
        -- The uppercase letter of each label opens the peek, so a label must
        -- have one.
        if not label:match("^[a-z]$") then
            invalid(labels_path .. " must contain only lowercase ASCII letters")
        end
        if seen[label] then
            invalid(string.format("%s contains duplicate label '%s'", labels_path, label))
        end
        seen[label] = true
    end
    return { labels = labels, offset = schema.integer(jump.offset, path .. ".offset") }
end

---@param value any
---@param path string
---@return false|ScrollbarHoverConfig
M.hover = function(value, path)
    local hover = schema.feature(value, path, HOVER_DEFAULTS)
    if hover then
        schema.integer(hover.delay_ms, path .. ".delay_ms", 0)
    end
    return hover
end

--- A preset name or a frame function. The frame module resolves a preset
--- when the float opens, so setup does not load the recipes.
---@param value any
---@param path string
---@return ScrollbarFrameValue
local function frame_value(value, path)
    if type(value) == "function" then
        return value
    end
    for _, preset in ipairs(frame.PRESETS) do
        if value == preset then
            return value
        end
    end
    invalid(path .. ' must be "scrollbar", "cursor", "center", or a function')
    return value
end

---@param value any
---@param path string
---@return table
local function block(value, path)
    if value == nil then
        return {}
    end
    return schema.table(value, path)
end

---@param value any Top-level `peek` table
---@return ScrollbarPeekConfig
M.peek = function(value)
    value = block(value, "peek")
    schema.check_keys(value, PEEK_KEYS, "peek")
    local merged = schema.merge(PEEK_DEFAULTS, value)
    return {
        frame = frame_value(merged.frame, "peek.frame"),
        window = window_config.normalize(merged.window, "peek.window", PEEK_WINDOW_SPEC),
    }
end

---@param value any
---@param path string
---@return string[]
local function key_list(value, path)
    if value == false then
        return {}
    end
    if type(value) == "string" then
        value = { value }
    elseif type(value) ~= "table" then
        invalid(path .. " must be false, a string, or a dense list of strings")
    end
    local count = schema.dense_count(value, path)
    local result = {}
    for index = 1, count do
        local lhs = value[index]
        if type(lhs) ~= "string" or lhs == "" then
            invalid(string.format("%s[%d] must be a non-empty string", path, index))
        end
        result[index] = lhs
    end
    return result
end

--- The list options. The list frame must leave room for the preview, so a
--- part of the frame width is less than 1.
---@param value table Merged `glance.list`
---@return ScrollbarGlanceListConfig
local function glance_list(value)
    local width = value.width
    if not frame.is_size(width) or width == 1 then
        invalid("glance.list.width must be a number greater than 0 and less than 1, or a whole number greater than 1")
    end
    return {
        entries = schema.enum(value.entries, "glance.list.entries", { "line", "mark", "type" }),
        width = width,
        side = schema.enum(value.side, "glance.list.side", { "right", "left" }),
    }
end

--- The keys of each pane. Two actions of one pane cannot share a key. Two
--- panes can, because only one pane has focus.
---@param value table Merged `glance.keys`
---@return ScrollbarGlanceKeys
local function glance_keys(value)
    local result = {}
    for _, pane in ipairs(GLANCE_PANES) do
        local pane_path = "glance.keys." .. pane
        local keys = {}
        local owners = {}
        for _, action in ipairs(GLANCE_ACTIONS[pane]) do
            local path = pane_path .. "." .. action
            keys[action] = key_list(value[pane][action], path)
            for _, lhs in ipairs(keys[action]) do
                local code = vim.keycode(lhs)
                local owner = owners[code]
                if owner ~= nil then
                    invalid(string.format("%s: '%s' is also a key of %s.%s", path, lhs, pane_path, owner))
                end
                owners[code] = action
            end
        end
        result[pane] = keys
    end
    return result
end

---@param value any Top-level `glance` table
---@return ScrollbarGlanceConfig
M.glance = function(value)
    value = block(value, "glance")
    schema.check_keys(value, GLANCE_KEYS, "glance")
    if value.keys ~= nil then
        schema.table(value.keys, "glance.keys")
        for _, pane in ipairs(GLANCE_PANES) do
            if value.keys[pane] ~= nil then
                schema.table(value.keys[pane], "glance.keys." .. pane)
            end
        end
    end
    if value.list ~= nil and type(value.list) ~= "table" then
        invalid("glance.list must be a table: set the entries with glance.list.entries")
    end
    local merged = schema.merge(GLANCE_DEFAULTS, value)
    return {
        frame = frame_value(merged.frame, "glance.frame"),
        list = glance_list(merged.list),
        keys = glance_keys(merged.keys),
        window = window_config.normalize(merged.window, "glance.window", GLANCE_WINDOW_SPEC),
    }
end

return M
