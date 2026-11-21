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
    picker = "builtin",
    entries = "line",
    builtin = {
        frame = "cursor",
        list = {
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
    },
}

--- The names that `glance.picker` accepts besides a function.
M.GLANCE_PICKERS = { "builtin", "snacks", "telescope" }

M.GLANCE_PICKER_MESSAGE = 'must be "builtin", "snacks", "telescope", or a function'

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
    picker = true,
    entries = true,
    builtin = {
        frame = true,
        list = { width = true, side = true },
        keys = {
            list = action_spec(GLANCE_ACTIONS.list),
            preview = action_spec(GLANCE_ACTIONS.preview),
        },
        window = { ["*"] = true },
    },
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

local GLANCE_WINDOW_SPEC = window_spec("the glance window", frame_hints("glance.builtin.frame"))

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
        -- The uppercase letter of each label is also a key. It peeks in
        -- `jump()` and jumps in `peek()`, so a label must have one.
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

--- The list options of the builtin frame. The list frame must leave room for
--- the preview, so a part of the frame width is less than 1.
---@param value table Merged `glance.builtin.list`
---@return ScrollbarGlanceListConfig
local function glance_list(value)
    local width = value.width
    if not frame.is_size(width) or width == 1 then
        invalid(
            "glance.builtin.list.width must be a number greater than 0 and less than 1, or a whole number greater than 1"
        )
    end
    return {
        width = width,
        side = schema.enum(value.side, "glance.builtin.list.side", { "right", "left" }),
    }
end

--- The keys of each pane. Two actions of one pane cannot share a key. Two
--- panes can, because only one pane has focus.
---@param value table Merged `glance.builtin.keys`
---@return ScrollbarGlanceKeys
local function glance_keys(value)
    local result = {}
    for _, pane in ipairs(GLANCE_PANES) do
        local pane_path = "glance.builtin.keys." .. pane
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

--- Whether `value` is a picker: a name of `GLANCE_PICKERS` or a function.
---@param value any
---@return boolean
M.is_glance_picker = function(value)
    return type(value) == "function" or vim.tbl_contains(M.GLANCE_PICKERS, value)
end

--- Check the tables of the builtin block before the merge, so that a wrong
--- type names its path instead of failing in the merge.
---@param value table Top-level `glance` table
local function check_builtin_tables(value)
    if value.builtin == nil then
        return
    end
    local builtin = schema.table(value.builtin, "glance.builtin")
    if builtin.list ~= nil then
        schema.table(builtin.list, "glance.builtin.list")
    end
    if builtin.keys ~= nil then
        schema.table(builtin.keys, "glance.builtin.keys")
        for _, pane in ipairs(GLANCE_PANES) do
            if builtin.keys[pane] ~= nil then
                schema.table(builtin.keys[pane], "glance.builtin.keys." .. pane)
            end
        end
    end
end

---@param value any Top-level `glance` table
---@return ScrollbarGlanceConfig
M.glance = function(value)
    value = block(value, "glance")
    schema.check_keys(value, GLANCE_KEYS, "glance")
    check_builtin_tables(value)
    local merged = schema.merge(GLANCE_DEFAULTS, value)
    if not M.is_glance_picker(merged.picker) then
        invalid("glance.picker " .. M.GLANCE_PICKER_MESSAGE)
    end
    local builtin = merged.builtin
    return {
        picker = merged.picker,
        entries = schema.enum(merged.entries, "glance.entries", { "line", "mark", "type" }),
        builtin = {
            frame = frame_value(builtin.frame, "glance.builtin.frame"),
            list = glance_list(builtin.list),
            keys = glance_keys(builtin.keys),
            window = window_config.normalize(builtin.window, "glance.builtin.window", GLANCE_WINDOW_SPEC),
        },
    }
end

return M
