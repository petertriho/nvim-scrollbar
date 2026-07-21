--- Minimap preset resolver. Mirrors `lua/scrollbar/presets.lua` with
--- minimap-specific allowed fields. The preset chain (extends) and deep-merge
--- logic are duplicated deliberately so the minimap subsystem stays
--- independent of the scrollbar preset module (plan non-goal: no shared runtime
--- modules between subsystems in v1).

local ALLOWED_FIELDS = {
    extends = true,
    width = true,
    height = true,
    float = true,
    overlays = true,
    show_viewport = true,
    autohide = true,
    visibility = true,
}

local NESTED_FIELDS = {
    autohide = { enabled = true, delay_ms = true },
    float = { zindex = true, placement = true },
    ["float.placement"] = {
        relative = true,
        anchor = true,
        row = true,
        col = true,
        gutter = true,
        gutter_position = true,
    },
    overlays = { enabled = true, types = true },
}

local BUILTINS = {
    -- Starter preset: a typical east-anchored window-relative minimap
    -- with a narrow width, viewport tint, and overlays on.
    default = {
        width = 16,
        height = false,
        float = {
            placement = {
                relative = "window",
                anchor = "NE",
                row = 0,
                col = 0,
                gutter = "overlap",
                gutter_position = "inner",
            },
        },
        overlays = { enabled = true },
        show_viewport = true,
    },
}

local function invalid(message)
    error("[scrollbar.nvim] " .. message, 3)
end

local function path_string(path)
    local parts = {}
    for _, part in ipairs(path) do
        parts[#parts + 1] = tostring(part)
    end
    return table.concat(parts, ".")
end

local function is_dense_list(value)
    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            return false
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    return count > 0 and count == maximum
end

local function is_atomic_list(path, value)
    if is_dense_list(value) then
        return true
    end

    local name = path_string(path)
    return name == "excluded_buftypes" or name == "excluded_filetypes" or name == "update.events"
end

local function merge_at(base, overlay, path)
    if type(overlay) ~= "table" then
        return overlay
    end
    if is_atomic_list(path, overlay) then
        return vim.deepcopy(overlay)
    end

    local result = type(base) == "table" and vim.deepcopy(base) or {}
    for key, value in pairs(overlay) do
        local child_path = vim.list_extend(vim.deepcopy(path), { key })
        result[key] = merge_at(result[key], value, child_path)
    end
    return result
end

local function valid_name(name)
    return type(name) == "string" and name:match("^[%a_][%w_-]*$") ~= nil
end

local function validate_allowed_fields(name, value, allowed, path)
    for key in pairs(value) do
        if not allowed[key] then
            invalid(string.format("minimap preset '%s' cannot set '%s.%s'", name, path, tostring(key)))
        end
    end
end

local function validate_definition(name, definition)
    if type(definition) ~= "table" then
        invalid(string.format("minimap preset '%s' must be a table", tostring(name)))
    end

    for key in pairs(definition) do
        if not ALLOWED_FIELDS[key] then
            invalid(string.format("minimap preset '%s' cannot set '%s'", name, tostring(key)))
        end
    end

    if definition.extends ~= nil then
        if type(definition.extends) ~= "string" then
            invalid(string.format("minimap preset '%s'.extends must be a string", name))
        end
        if not valid_name(definition.extends) then
            invalid(string.format("minimap preset '%s'.extends must be a valid preset name", name))
        end
    end

    for _, field in ipairs({ "float", "overlays", "autohide" }) do
        if definition[field] ~= nil and type(definition[field]) ~= "table" then
            invalid(string.format("minimap preset '%s'.%s must be a table", name, field))
        end
    end

    if definition.float ~= nil then
        for key in pairs(definition.float) do
            if key ~= "placement" then
                invalid(string.format("minimap preset '%s' cannot set 'float.%s'", name, tostring(key)))
            end
        end
        if definition.float.placement ~= nil and type(definition.float.placement) ~= "table" then
            invalid(string.format("minimap preset '%s'.float.placement must be a table", name))
        end
        if definition.float.placement ~= nil then
            validate_allowed_fields(
                name,
                definition.float.placement,
                NESTED_FIELDS["float.placement"],
                "float.placement"
            )
        end
    end

    if definition.overlays ~= nil then
        validate_allowed_fields(name, definition.overlays, NESTED_FIELDS.overlays, "overlays")
    end

    if definition.autohide ~= nil then
        validate_allowed_fields(name, definition.autohide, NESTED_FIELDS.autohide, "autohide")
    end

    for _, field in ipairs({ "width", "height" }) do
        if definition[field] ~= nil then
            local value = definition[field]
            if value ~= false and (type(value) ~= "number" or value <= 0 or value ~= math.floor(value)) then
                invalid(string.format("minimap preset '%s'.%s must be false or a positive integer", name, field))
            end
        end
    end

    for _, field in ipairs({ "show_viewport" }) do
        if definition[field] ~= nil and type(definition[field]) ~= "boolean" then
            invalid(string.format("minimap preset '%s'.%s must be a boolean", name, field))
        end
    end
end

local M = {}

---@param base table
---@param overlay table
---@return table
M.merge = function(base, overlay)
    return merge_at(base, overlay, {})
end

---@param options? table
---@return table
M.resolve = function(options)
    options = options or {}
    if type(options) ~= "table" then
        invalid("minimap configuration must be a table")
    end

    local definitions = options.presets or {}
    if type(definitions) ~= "table" then
        invalid("minimap presets must be a table")
    end

    definitions = vim.deepcopy(definitions)
    for name, definition in pairs(definitions) do
        if not valid_name(name) then
            invalid(
                "minimap preset names must start with a letter or underscore and contain only letters, numbers, underscores, or hyphens"
            )
        end
        validate_definition(name, definition)
    end

    local resolved = {}
    local resolving = {}
    local function resolve_name(name)
        if resolved[name] ~= nil then
            return resolved[name]
        end
        if resolving[name] then
            invalid(string.format("minimap preset cycle includes '%s'", name))
        end

        local definition = definitions[name]
        local builtin = BUILTINS[name]
        if definition == nil and builtin == nil then
            invalid(string.format("unknown minimap preset '%s'", name))
        end

        resolving[name] = true
        local result = {}
        if definition ~= nil and definition.extends ~= nil then
            local parent = definition.extends
            if definitions[parent] == nil and BUILTINS[parent] == nil then
                invalid(string.format("unknown parent minimap preset '%s' for preset '%s'", parent, name))
            end
            result = M.merge(result, resolve_name(parent))
        end
        if builtin ~= nil then
            result = M.merge(result, builtin)
        end
        if definition ~= nil then
            local body = vim.deepcopy(definition)
            body.extends = nil
            result = M.merge(result, body)
        end
        resolving[name] = nil
        resolved[name] = vim.deepcopy(result)
        return result
    end

    for name in pairs(definitions) do
        resolve_name(name)
    end

    local selected = options.preset
    if selected ~= nil and not valid_name(selected) then
        invalid("minimap preset must be a valid preset name")
    end

    local result = selected ~= nil and resolve_name(selected) or {}
    local root = vim.deepcopy(options)
    root.preset = nil
    root.presets = nil
    return M.merge(result, root)
end

return M
