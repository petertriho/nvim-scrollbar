--- The `floats` option of a block. It tells which floating windows are source
--- windows. The built-in kinds are the windows of the snacks.nvim picker and
--- the Telescope picker. A `when` matcher admits other floats, which get the
--- kind `"custom"`. Every float is off by default.

local schema = require("scrollbar.config.schema")

local invalid = schema.invalid

local M = {}

--- The built-in pickers and the key and kind of each of their windows, in the
--- order of validation.
local PICKERS = {
    { name = "snacks", windows = { { "list", "snacks_list" }, { "preview", "snacks_preview" } } },
    { name = "telescope", windows = { { "results", "telescope_results" }, { "preview", "telescope_preview" } } },
}

local KEYS = {
    snacks = { list = true, preview = true },
    telescope = { results = true, preview = true },
    when = true,
}

-- The snacks list buffer holds only the visible rows, and the minimap draws
-- the buffer text.
local MINIMAP_SNACKS_LIST = "is not supported. The minimap cannot draw the snacks list, "
    .. "because its buffer holds only the visible rows"

--- Kinds that a block does not support, with the reason.
---@type table<"scrollbar"|"minimap", table<string, string>>
local UNSUPPORTED = {
    scrollbar = {},
    minimap = { snacks_list = MINIMAP_SNACKS_LIST },
}

--- The built-in kinds, in a stable order.
M.KINDS = { "snacks_list", "snacks_preview", "telescope_results", "telescope_preview" }

---@param block "scrollbar"|"minimap"
---@return table<string, true|string> kinds Each kind that `match.floats` names. A string is the reason why the block rejects the kind
M.match_kinds = function(block)
    ---@type table<string, true|string>
    local result = { custom = true }
    for _, kind in ipairs(M.KINDS) do
        result[kind] = UNSUPPORTED[block][kind] or true
    end
    return result
end

---@param block "scrollbar"|"minimap"
---@param picker { name: string, windows: string[][] }
---@param value boolean
---@param kinds table<ScrollbarFloatKind, boolean>
local function set_picker(block, picker, value, kinds)
    for _, window in ipairs(picker.windows) do
        local kind = window[2]
        if UNSUPPORTED[block][kind] == nil then
            kinds[kind] = value
        end
    end
end

---@param value any
---@param path string Error path of the option, such as `"scrollbar.floats"`
---@param block "scrollbar"|"minimap"
---@return ScrollbarFloatsConfig
M.normalize = function(value, path, block)
    ---@type table<ScrollbarFloatKind, boolean>
    local kinds = {}
    for _, kind in ipairs(M.KINDS) do
        kinds[kind] = false
    end
    local when = false

    if value == true then
        for _, picker in ipairs(PICKERS) do
            set_picker(block, picker, true, kinds)
        end
    elseif type(value) == "table" then
        schema.check_keys(value, KEYS, path)
        for _, picker in ipairs(PICKERS) do
            local picker_path = path .. "." .. picker.name
            local option = value[picker.name]
            if type(option) == "boolean" then
                set_picker(block, picker, option, kinds)
            elseif type(option) == "table" then
                for _, window in ipairs(picker.windows) do
                    local key, kind = window[1], window[2]
                    local key_path = picker_path .. "." .. key
                    local reason = UNSUPPORTED[block][kind]
                    if option[key] ~= nil and reason ~= nil then
                        invalid(key_path .. " " .. reason)
                    end
                    if option[key] ~= nil then
                        kinds[kind] = schema.boolean(option[key], key_path)
                    end
                end
            elseif option ~= nil then
                invalid(picker_path .. " must be a boolean or table")
            end
        end
        if value.when ~= nil then
            if type(value.when) ~= "function" then
                invalid(path .. ".when must be a function")
            end
            when = value.when
        end
    elseif value ~= false then
        invalid(path .. " must be a boolean or table")
    end

    local enabled = when ~= false
    for _, kind in ipairs(M.KINDS) do
        enabled = enabled or kinds[kind]
    end
    return { enabled = enabled, kinds = kinds, when = when }
end

return M
