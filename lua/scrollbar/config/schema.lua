--- Shared validation, merge, and profile-selection helpers for the scrollbar
--- and minimap configuration modules.

local M = {}

M.TYPE_NAME_PATTERN = "^[%a_][%w_]*$"

---@param message string
M.invalid = function(message)
    error("[nvim-scrollbar] " .. message, 0)
end

local invalid = M.invalid

---@param value any
---@return boolean
M.is_integer = function(value)
    return type(value) == "number" and value > -math.huge and value < math.huge and value == math.floor(value)
end

local is_integer = M.is_integer

---@param path string
---@param key any
---@return string
M.join = function(path, key)
    if type(key) == "number" then
        return string.format("%s[%d]", path, key)
    end
    if path == "" then
        return tostring(key)
    end
    return path .. "." .. tostring(key)
end

local join = M.join

---@param value table
---@return boolean
M.is_dense_list = function(value)
    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if not is_integer(key) or key < 1 then
            return false
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    return count > 0 and count == maximum
end

local is_dense_list = M.is_dense_list

---@param value any
---@param path string
---@return integer
M.dense_count = function(value, path)
    if type(value) ~= "table" then
        invalid(path .. " must be a dense list")
    end

    local count = 0
    local maximum = 0
    for key in pairs(value) do
        count = count + 1
        if not is_integer(key) or key < 1 then
            invalid(path .. " must be a dense list")
        end
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then
        invalid(path .. " must be a dense list")
    end
    return count
end

local dense_count = M.dense_count

local function check_keys_at(value, spec, path, relative, describe)
    for key, child in pairs(value) do
        local child_spec = spec[key]
        if child_spec == nil then
            child_spec = spec["*"]
        end
        local child_path = join(path, key)
        local child_relative = join(relative, key)
        if child_spec == nil then
            local message = describe and describe(child_relative, child_path) or nil
            invalid(message or string.format("unknown option '%s'", child_path))
        end
        if type(child_spec) == "table" and type(child) == "table" then
            check_keys_at(child, child_spec, child_path, child_relative, describe)
        end
    end
end

--- Reject keys that `spec` does not allow, recursively. A spec maps each
--- allowed key to `true` (leaf) or to a nested spec. The nested spec applies
--- only when the value is a table, so `false | true | table` options share one
--- entry. The `["*"]` key allows any key and applies its nested spec to each
--- table value.
---@param value any
---@param spec table
---@param path string
---@param describe? fun(relative: string, path: string): string? Message for a rejected key. `relative` is the key path below `path`, such as `"autohide.enabled"`.
M.check_keys = function(value, spec, path, describe)
    if type(value) == "table" then
        check_keys_at(value, spec, path, "", describe)
    end
end

--- Build a `check_keys` describer that names the replacement of a removed
--- option. `hints` maps a relative key path to the replacement text.
---@param hints table<string, string>
---@param describe? fun(relative: string, path: string): string? Checked before the hints
---@return fun(relative: string, path: string): string?
M.hinter = function(hints, describe)
    return function(relative, path)
        local message = describe and describe(relative, path) or nil
        if message == nil and hints[relative] ~= nil then
            message = string.format("unknown option '%s' (%s)", path, hints[relative])
        end
        return message
    end
end

---@param value any
---@param path string
M.boolean = function(value, path)
    if type(value) ~= "boolean" then
        invalid(path .. " must be a boolean")
    end
    return value
end

---@param value any
---@param path string
---@param minimum? integer
---@param maximum? integer
---@return integer
M.integer = function(value, path, minimum, maximum)
    if not is_integer(value) or (minimum ~= nil and value < minimum) or (maximum ~= nil and value > maximum) then
        if minimum == 0 and maximum ~= nil then
            invalid(string.format("%s must be an integer between 0 and %d", path, maximum))
        elseif minimum == 0 then
            invalid(path .. " must be a non-negative integer")
        elseif minimum == 1 then
            invalid(path .. " must be a positive integer")
        end
        invalid(path .. " must be an integer")
    end
    return value
end

---@param value any
---@param path string
---@return false|integer
M.positive_or_false = function(value, path)
    if value == false then
        return false
    end
    if not is_integer(value) or value < 1 then
        invalid(path .. " must be false or a positive integer")
    end
    return value
end

---@param value any
---@param path string
---@param values string[]
---@return string
M.enum = function(value, path, values)
    for _, allowed in ipairs(values) do
        if value == allowed then
            return value
        end
    end
    local names = vim.deepcopy(values)
    table.sort(names)
    invalid(string.format("%s must be one of: %s", path, table.concat(names, ", ")))
    return value
end

---@param value any
---@param path string
---@return string
M.text = function(value, path)
    if type(value) ~= "string" then
        invalid(path .. " must be a string")
    end
    if value:find("%c") then
        invalid(path .. " must not contain control characters")
    end

    local ok, width = pcall(vim.fn.strdisplaywidth, value)
    if not ok or width <= 0 then
        invalid(path .. " must have positive display width")
    end
    return value
end

---@param value any
---@param path string
---@param allow_empty boolean
---@return string[]
M.text_variants = function(value, path, allow_empty)
    if type(value) == "string" then
        value = { value }
    elseif type(value) ~= "table" then
        invalid(path .. " must be a string or dense list of strings")
    end

    local count = dense_count(value, path)
    if count == 0 and not allow_empty then
        invalid(path .. " must contain at least one variant")
    end
    for index = 1, count do
        M.text(value[index], join(path, index))
    end
    return vim.deepcopy(value)
end

---@param value any
---@param path string
---@return ScrollbarHighlight
M.highlight = function(value, path)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if type(value) == "table" then
        return vim.deepcopy(value)
    end
    invalid(path .. " must be a non-empty string or table")
    return value
end

---@param value any
---@param path string
---@return table
M.table = function(value, path)
    if type(value) ~= "table" then
        invalid(path .. " must be a table")
    end
    return value
end

---@param value any
---@param path string
---@return string[] values
---@return table<string, true> lookup
M.string_list = function(value, path)
    local count = dense_count(value, path)
    local values = {}
    local lookup = {}
    for index = 1, count do
        local item = value[index]
        if type(item) ~= "string" then
            invalid(string.format("%s[%d] must be a string", path, index))
        end
        values[index] = item
        lookup[item] = true
    end
    return values, lookup
end

--- `false` disables the feature, `true` selects `defaults`, and a table
--- overrides fields of `defaults`.
---@param value any
---@param path string
---@param defaults table
---@return false|table
M.feature = function(value, path, defaults)
    if value == false then
        return false
    end
    if value == true then
        return vim.deepcopy(defaults)
    end
    if type(value) ~= "table" then
        invalid(path .. " must be a boolean or table")
    end
    return vim.tbl_extend("force", vim.deepcopy(defaults), value)
end

---@param path string[]
---@return boolean
local function is_atomic_path(path)
    local last = path[#path]
    return last == "columns" or last == "types" or last == "text"
end

local function merge_at(base, overlay, path)
    if type(overlay) ~= "table" then
        return overlay
    end
    if is_dense_list(overlay) or is_atomic_path(path) then
        return vim.deepcopy(overlay)
    end

    local result = type(base) == "table" and vim.deepcopy(base) or {}
    for key, value in pairs(overlay) do
        path[#path + 1] = key
        result[key] = merge_at(result[key], value, path)
        path[#path] = nil
    end
    return result
end

--- Deep-merge `overlay` onto `base`. Non-empty dense lists, layout columns,
--- selector types, and mark text replace atomically. Scalars and `false`
--- replace the base value.
---@param base any
---@param overlay any
---@return any
M.merge = function(base, overlay)
    if overlay == nil then
        return vim.deepcopy(base)
    end
    return merge_at(base, overlay, {})
end

---@param value table
---@param keys string[]
---@return table
M.without = function(value, keys)
    local result = vim.deepcopy(value)
    for _, key in ipairs(keys) do
        result[key] = nil
    end
    return result
end

local MATCH_KEYS = { filetypes = true, buftypes = true, when = true, floats = true }

---@param value any
---@param path string
---@param kinds table<string, true|string> Kinds that `floats` can name. A string is the reason why the block rejects the kind
---@return true|table<string, true>
local function float_matcher(value, path, kinds)
    if value == true then
        return true
    end
    if type(value) ~= "table" then
        invalid(path .. " must be true or a dense list of float kinds")
    end
    local count = dense_count(value, path)
    if count == 0 then
        invalid(path .. " must contain at least one kind")
    end
    local lookup = {}
    for index = 1, count do
        local item_path = join(path, index)
        local name = value[index]
        if type(name) ~= "string" then
            invalid(item_path .. " must be a string")
        end
        local allowed = kinds[name]
        if allowed == nil then
            local names = vim.tbl_keys(kinds)
            table.sort(names)
            invalid(string.format("%s must be one of: %s", item_path, table.concat(names, ", ")))
        elseif allowed ~= true then
            invalid(string.format("%s '%s' %s", item_path, name, allowed))
        end
        lookup[name] = true
    end
    return lookup
end

---@param value any
---@param path string
---@param float_kinds? table<string, true|string> Kinds that `floats` can name. A string is the reason why the block rejects the kind
---@return ScrollbarCompiledMatcher
M.matcher = function(value, path, float_kinds)
    if type(value) ~= "table" then
        invalid(path .. " must be a table")
    end
    M.check_keys(value, MATCH_KEYS, path)
    if value.filetypes == nil and value.buftypes == nil and value.when == nil and value.floats == nil then
        invalid(path .. " must contain at least one matcher")
    end

    ---@type ScrollbarCompiledMatcher
    local matcher = {
        filetypes = false,
        filetype_lookup = false,
        buftypes = false,
        buftype_lookup = false,
        when = false,
        floats = false,
    }
    local function names(field)
        local field_path = path .. "." .. field
        if dense_count(value[field], field_path) == 0 then
            invalid(field_path .. " must contain at least one value")
        end
        return M.string_list(value[field], field_path)
    end
    if value.filetypes ~= nil then
        matcher.filetypes, matcher.filetype_lookup = names("filetypes")
    end
    if value.buftypes ~= nil then
        matcher.buftypes, matcher.buftype_lookup = names("buftypes")
    end
    if value.when ~= nil then
        if type(value.when) ~= "function" then
            invalid(path .. ".when must be a function")
        end
        matcher.when = value.when
    end
    if value.floats ~= nil then
        matcher.floats = float_matcher(value.floats, path .. ".floats", float_kinds or {})
    end
    return matcher
end

--- Whether the `match.floats` value of a profile admits a source window of
--- `kind`.
---@param floats false|true|table<string, true>
---@param kind? ScrollbarSourceKind Nil is a normal window
---@return boolean
local function kind_matches(floats, kind)
    if kind == nil or kind == "normal" then
        return floats == false
    end
    return floats == true or (floats ~= false and floats[kind] == true)
end

---@class ScrollbarProfileSelector
---@field label string Name used in matcher failure notifications
---@field notified table<string, true>

---@param label string
---@return ScrollbarProfileSelector
M.selector = function(label)
    return { label = label, notified = {} }
end

--- Return the first compiled variant whose matcher accepts `source_win`, or
--- the root variant. A matcher error selects the root for this call and
--- notifies once per variant and message.
---
--- A floating source window matches only the profiles with `match.floats`,
--- and a normal window matches only the profiles without it.
---@generic T
---@param selector ScrollbarProfileSelector
---@param compiled { id: integer, matcher: false|ScrollbarCompiledMatcher, config: T }[]
---@param source_win integer
---@param kind? ScrollbarSourceKind Kind of the source window. Nil is a normal window
---@return { config: T, variant_id: integer }
M.select = function(selector, compiled, source_win, kind)
    local root = compiled[1].config
    if #compiled == 1 then
        return { config = root, variant_id = 0 }
    end

    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local filetype = vim.bo[source_buf].filetype
    local buftype = vim.bo[source_buf].buftype
    local context

    for index = 2, #compiled do
        local variant = compiled[index]
        local matcher = variant.matcher
        assert(matcher ~= false, "compiled profile matcher unavailable")
        ---@cast matcher ScrollbarCompiledMatcher
        local filetype_lookup = matcher.filetype_lookup
        local buftype_lookup = matcher.buftype_lookup
        if
            kind_matches(matcher.floats, kind)
            and (filetype_lookup == false or filetype_lookup[filetype])
            and (buftype_lookup == false or buftype_lookup[buftype])
        then
            local when = matcher.when
            if when == false then
                return { config = variant.config, variant_id = variant.id }
            end
            context = context
                or {
                    winid = source_win,
                    bufnr = source_buf,
                    filetype = filetype,
                    buftype = buftype,
                    bufname = vim.api.nvim_buf_get_name(source_buf),
                }
            local ok, matched = pcall(when, context)
            if not ok then
                local message = tostring(matched)
                local key = variant.id .. "\0" .. message
                if not selector.notified[key] then
                    selector.notified[key] = true
                    vim.notify(
                        string.format(
                            "[nvim-scrollbar] %s profile %d matcher failed: %s",
                            selector.label,
                            variant.id,
                            message
                        ),
                        vim.log.levels.ERROR
                    )
                end
                return { config = root, variant_id = 0 }
            end
            if matched then
                return { config = variant.config, variant_id = variant.id }
            end
        end
    end
    return { config = root, variant_id = 0 }
end

return M
