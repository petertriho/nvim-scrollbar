local BUILTINS = {
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
}

local ALLOWED_FIELDS = {
    extends = true,
    layout = true,
    track = true,
    thumb = true,
    marks = true,
    float = true,
}

local NESTED_FIELDS = {
    layout = { direction = true, columns = true },
    track = { highlight = true },
    thumb = { text = true, blend = true, highlight = true, hide_if_all_visible = true },
    mark = { text = true, priority = true, highlight = true },
    placement = { relative = true, anchor = true, row = true, col = true },
    layer = { kind = true, types = true, max_width = true },
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
    return name == "layout.columns"
        or name == "excluded_buftypes"
        or name == "excluded_filetypes"
        or name:match("^marks%.[^.]+%.text$") ~= nil
        or path[#path] == "types"
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
            invalid(string.format("preset '%s' cannot set '%s.%s'", name, path, tostring(key)))
        end
    end
end

local function validate_list(value, path)
    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
            invalid(path .. " must be a dense list")
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then
        invalid(path .. " must be a dense list")
    end
    return count
end

local function validate_definition(name, definition)
    if type(definition) ~= "table" then
        invalid(string.format("preset '%s' must be a table", tostring(name)))
    end

    for key in pairs(definition) do
        if not ALLOWED_FIELDS[key] then
            invalid(string.format("preset '%s' cannot set '%s'", name, tostring(key)))
        end
    end

    if definition.extends ~= nil then
        if type(definition.extends) ~= "string" then
            invalid(string.format("preset '%s'.extends must be a string", name))
        end
        if not valid_name(definition.extends) then
            invalid(string.format("preset '%s'.extends must be a valid preset name", name))
        end
    end

    for _, field in ipairs({ "layout", "track", "thumb", "marks", "float" }) do
        if definition[field] ~= nil and type(definition[field]) ~= "table" then
            invalid(string.format("preset '%s'.%s must be a table", name, field))
        end
    end

    if definition.float ~= nil then
        for key in pairs(definition.float) do
            if key ~= "placement" then
                invalid(string.format("preset '%s' cannot set 'float.%s'", name, tostring(key)))
            end
        end
        if definition.float.placement ~= nil and type(definition.float.placement) ~= "table" then
            invalid(string.format("preset '%s'.float.placement must be a table", name))
        end
        if definition.float.placement ~= nil then
            validate_allowed_fields(name, definition.float.placement, NESTED_FIELDS.placement, "float.placement")
        end
    end

    for _, field in ipairs({ "track", "thumb" }) do
        if definition[field] ~= nil then
            validate_allowed_fields(name, definition[field], NESTED_FIELDS[field], field)
        end
    end

    if definition.marks ~= nil then
        for mark_type, mark in pairs(definition.marks) do
            if type(mark_type) ~= "string" or mark_type:match("^[%a_][%w_]*$") == nil then
                invalid(string.format("preset '%s' has invalid mark type '%s'", name, tostring(mark_type)))
            end
            if type(mark) ~= "table" then
                invalid(string.format("preset '%s'.marks.%s must be a table", name, mark_type))
            end
            validate_allowed_fields(name, mark, NESTED_FIELDS.mark, "marks." .. mark_type)
        end
    end

    if definition.layout ~= nil then
        validate_allowed_fields(name, definition.layout, NESTED_FIELDS.layout, "layout")
        if definition.layout.columns ~= nil then
            if type(definition.layout.columns) ~= "table" then
                invalid(string.format("preset '%s'.layout.columns must be a dense list", name))
            end
            local column_count = validate_list(definition.layout.columns, "preset '" .. name .. "'.layout.columns")
            if column_count == 0 then
                invalid(string.format("preset '%s'.layout.columns must contain at least one column", name))
            end
            for column_index = 1, column_count do
                local column = definition.layout.columns[column_index]
                local column_path = string.format("preset '%s'.layout.columns[%d]", name, column_index)
                if type(column) ~= "table" then
                    invalid(column_path .. " must be a dense list")
                end
                local layer_count = validate_list(column, column_path)
                if layer_count == 0 then
                    invalid(column_path .. " must contain at least one layer")
                end
                for layer_index = 1, layer_count do
                    local layer = column[layer_index]
                    if type(layer) == "table" then
                        validate_allowed_fields(
                            name,
                            layer,
                            NESTED_FIELDS.layer,
                            string.format("layout.columns[%d][%d]", column_index, layer_index)
                        )
                    elseif type(layer) ~= "string" then
                        invalid(string.format("%s[%d] must be a string or mark descriptor", column_path, layer_index))
                    end
                end
            end
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
        invalid("configuration must be a table")
    end

    local definitions = options.presets or {}
    if type(definitions) ~= "table" then
        invalid("presets must be a table")
    end

    definitions = vim.deepcopy(definitions)
    for name, definition in pairs(definitions) do
        if not valid_name(name) then
            invalid(
                "preset names must start with a letter or underscore and contain only letters, numbers, underscores, or hyphens"
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
            invalid(string.format("preset cycle includes '%s'", name))
        end

        local definition = definitions[name]
        local builtin = BUILTINS[name]
        if definition == nil and builtin == nil then
            invalid(string.format("unknown preset '%s'", name))
        end

        resolving[name] = true
        local result = {}
        if definition ~= nil and definition.extends ~= nil then
            local parent = definition.extends
            if definitions[parent] == nil and BUILTINS[parent] == nil then
                invalid(string.format("unknown parent preset '%s' for preset '%s'", parent, name))
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
        invalid("preset must be a valid preset name")
    end

    local result = selected ~= nil and resolve_name(selected) or {}
    local root = vim.deepcopy(options)
    root.preset = nil
    root.presets = nil
    return M.merge(result, root)
end

return M
