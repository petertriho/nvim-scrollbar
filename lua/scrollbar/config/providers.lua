local schema = require("scrollbar.config.schema")

local M = {}

M.ORDER = {
    "cursor",
    "diagnostic",
    "search",
    "marks",
    "gitsigns",
    "mini_diff",
    "signify",
    "vgit",
    "ale",
    "coc",
    "qflist",
    "loclist",
    "treesitter",
    "lsp_semantic_tokens",
}

local BOTH = { scrollbar = true, minimap = true }
local MINIMAP_ONLY = { scrollbar = false, minimap = true }

local SPECS = {
    cursor = { targets = BOTH, execution = "parent", default = true },
    diagnostic = { targets = BOTH, execution = "parent", default = true },
    search = { targets = BOTH, execution = "parent", default = true },
    marks = { targets = BOTH, execution = "parent", default = true },
    gitsigns = { targets = BOTH, execution = "parent", default = false },
    mini_diff = { targets = BOTH, execution = "parent", default = false },
    signify = { targets = BOTH, execution = "parent", default = false },
    vgit = { targets = BOTH, execution = "parent", default = false },
    ale = { targets = BOTH, execution = "parent", default = false },
    coc = { targets = BOTH, execution = "parent", default = false },
    qflist = { targets = BOTH, execution = "parent", default = false },
    loclist = { targets = BOTH, execution = "parent", default = false },
    treesitter = { targets = MINIMAP_ONLY, execution = "worker", default = true },
    lsp_semantic_tokens = { targets = MINIMAP_ONLY, execution = "parent", default = false },
}

local TARGET_KEYS = { scrollbar = true, minimap = true }

local KEYS = {
    search = { incsearch = true, backend = true, scrollbar = true, minimap = true },
    marks = { letters = true, numbers = true, scrollbar = true, minimap = true },
    qflist = { types = true, scrollbar = true, minimap = true },
    loclist = { types = true, scrollbar = true, minimap = true },
}

-- The entry types that Vim documents for the entries of a quickfix list or a
-- location list: error, warning, info, and note.
local LIST_ENTRY_TYPES = { E = true, W = true, I = true, N = true }

---@param value any
---@param path string
---@return table<string, string|false>
local function normalize_list_types(value, path)
    if value == nil then
        return {}
    end
    schema.table(value, path)
    local result = {}
    for letter, mark_type in pairs(value) do
        local entry_path = schema.join(path, letter)
        if not LIST_ENTRY_TYPES[letter] then
            schema.invalid(string.format("unknown option '%s'. The keys are E, W, I, and N", entry_path))
        end
        if mark_type ~= false and (type(mark_type) ~= "string" or not mark_type:match(schema.TYPE_NAME_PATTERN)) then
            schema.invalid(entry_path .. " must be false or a mark type name")
        end
        result[letter] = mark_type
    end
    return result
end

---@param name string
---@param value table Provider options without renderer keys
---@param path string
---@return ScrollbarProviderOption
local function normalize_options(name, value, path)
    if name == "search" then
        local result = { backend = value.backend == nil and "worker" or value.backend }
        schema.enum(result.backend, path .. ".backend", { "sync", "worker" })
        if value.incsearch ~= nil then
            result.incsearch = schema.boolean(value.incsearch, path .. ".incsearch")
        end
        return result
    end
    if name == "marks" then
        local result = {
            letters = value.letters == nil or value.letters,
            numbers = value.numbers == true,
        }
        if value.letters ~= nil then
            schema.boolean(value.letters, path .. ".letters")
        end
        if value.numbers ~= nil then
            schema.boolean(value.numbers, path .. ".numbers")
        end
        return result
    end
    if name == "qflist" or name == "loclist" then
        return { types = normalize_list_types(value.types, path .. ".types") }
    end
    return true
end

---@param spec table
---@param value any
---@param target "scrollbar"|"minimap"
---@param path string
---@param name string
---@return boolean
local function target_flag(spec, value, target, path, name)
    if value == nil then
        return spec.targets[target]
    end
    schema.boolean(value, path)
    if value and not spec.targets[target] then
        schema.invalid(string.format("%s: provider '%s' does not support the %s", path, name, target))
    end
    return value
end

--- Normalize the top-level `providers` table into one request per built-in.
---@param value any
---@return table<string, ScrollbarProviderRequest>
M.normalize = function(value)
    if value == nil then
        value = {}
    end
    schema.table(value, "providers")
    for name in pairs(value) do
        if SPECS[name] == nil then
            schema.invalid(string.format("unknown option '%s'", schema.join("providers", name)))
        end
    end

    local result = {}
    for _, name in ipairs(M.ORDER) do
        local spec = SPECS[name]
        local path = "providers." .. name
        local entry = value[name]
        if entry == nil then
            entry = spec.default
        end

        ---@type ScrollbarProviderRequest
        local request
        if entry == false then
            request = { options = false, scrollbar = false, minimap = false }
        elseif entry == true then
            request = {
                options = normalize_options(name, {}, path),
                scrollbar = spec.targets.scrollbar,
                minimap = spec.targets.minimap,
            }
        elseif type(entry) == "table" then
            schema.check_keys(entry, KEYS[name] or TARGET_KEYS, path)
            local scrollbar = target_flag(spec, entry.scrollbar, "scrollbar", path .. ".scrollbar", name)
            local minimap = target_flag(spec, entry.minimap, "minimap", path .. ".minimap", name)
            local options = normalize_options(name, schema.without(entry, { "scrollbar", "minimap" }), path)
            if not scrollbar and not minimap then
                options = false
            end
            request = { options = options, scrollbar = scrollbar, minimap = minimap }
        else
            schema.invalid(path .. " must be a boolean or table")
        end
        result[name] = request
    end
    return result
end

--- Check that each mark type in the `types` map of a list provider is in the
--- mark registry. The registry is known only after the top-level `marks`
--- table is normalized.
---@param requests table<string, ScrollbarProviderRequest>
---@param registry ScrollbarMarkRegistry
M.check_mark_types = function(requests, registry)
    for _, name in ipairs(M.ORDER) do
        local options = requests[name].options
        if type(options) == "table" and type(options.types) == "table" then
            local letters = vim.tbl_keys(options.types)
            table.sort(letters)
            for _, letter in ipairs(letters) do
                local mark_type = options.types[letter]
                if mark_type ~= false and registry.specs[mark_type] == nil then
                    schema.invalid(
                        string.format(
                            "providers.%s.types.%s: unknown mark type '%s'. Define it in the top-level marks table",
                            name,
                            letter,
                            mark_type
                        )
                    )
                end
            end
        end
    end
end

--- Combine provider requests with renderer enablement. A provider is active
--- when at least one enabled renderer requests it.
---@param requests table<string, ScrollbarProviderRequest>
---@param scrollbar_enabled boolean
---@param minimap_enabled boolean
---@return ScrollbarEffectiveProviderPlan
M.compile_plan = function(requests, scrollbar_enabled, minimap_enabled)
    local plan = {}
    for _, name in ipairs(M.ORDER) do
        local spec = SPECS[name]
        local request = requests[name]
        local consumers = {
            scrollbar = scrollbar_enabled and request.options ~= false and request.scrollbar,
            minimap = minimap_enabled and request.options ~= false and request.minimap,
        }
        plan[name] = {
            consumers = consumers,
            -- vim.deepcopy gives the `true` option of a provider without options back unchanged
            ---@diagnostic disable-next-line: param-type-mismatch
            options = (consumers.scrollbar or consumers.minimap) and vim.deepcopy(request.options) or false,
            targets = vim.deepcopy(spec.targets),
            execution = spec.execution,
        }
    end
    return plan
end

return M
