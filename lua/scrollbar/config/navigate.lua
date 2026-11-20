--- Options of the features that move to and inspect the marks: `scrollbar.jump`
--- and `scrollbar.hover` in the scrollbar block, and the top-level `peek` and
--- `glance` blocks. Profiles do not change them.

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
    position = "scrollbar",
    context = 5,
    width = 0.6,
    window = {},
}

local PEEK_KEYS = {
    position = true,
    context = true,
    width = true,
    -- `scrollbar.config.window` validates the keys of `window`.
    window = { ["*"] = true },
}

local GLANCE_DEFAULTS = {
    list = "line",
    height = 18,
    keys = {
        jump = "<CR>",
        close = { "q", "<Esc>" },
        preview = "<Tab>",
    },
    window = {},
}

local GLANCE_KEYS = {
    list = true,
    height = true,
    keys = { jump = true, close = true, preview = true },
    window = { ["*"] = true },
}

-- The order of the actions in errors about a key that two actions share.
local GLANCE_ACTIONS = { "jump", "preview", "close" }

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

local PEEK_WINDOW_SPEC = window_spec("the peek float", {
    width = "use 'peek.width'",
    height = "use 'peek.context'",
})

local GLANCE_WINDOW_SPEC = window_spec("the glance window", {
    height = "use 'glance.height'",
})

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

---@param value any
---@param path string
---@return number
local function fraction(value, path)
    if type(value) ~= "number" or value ~= value or value <= 0 or value > 1 then
        invalid(path .. " must be a number greater than 0 and at most 1")
    end
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
        position = schema.enum(merged.position, "peek.position", { "scrollbar", "cursor", "center" }),
        context = schema.integer(merged.context, "peek.context", 0),
        width = fraction(merged.width, "peek.width"),
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

---@param value table Merged `glance.keys`
---@return ScrollbarGlanceKeys
local function glance_keys(value)
    local result = {}
    local owners = {}
    for _, action in ipairs(GLANCE_ACTIONS) do
        local path = "glance.keys." .. action
        result[action] = key_list(value[action], path)
        for _, lhs in ipairs(result[action]) do
            local code = vim.keycode(lhs)
            local owner = owners[code]
            if owner ~= nil then
                invalid(string.format("%s: '%s' is also a key of glance.keys.%s", path, lhs, owner))
            end
            owners[code] = action
        end
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
    end
    local merged = schema.merge(GLANCE_DEFAULTS, value)
    return {
        list = schema.enum(merged.list, "glance.list", { "line", "mark", "type" }),
        height = schema.integer(merged.height, "glance.height", 1),
        keys = glance_keys(merged.keys),
        window = window_config.normalize(merged.window, "glance.window", GLANCE_WINDOW_SPEC),
    }
end

return M
