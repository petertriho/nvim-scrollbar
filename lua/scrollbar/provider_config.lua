local schema = require("scrollbar.schema")

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
    treesitter = { targets = MINIMAP_ONLY, execution = "worker", default = false },
    lsp_semantic_tokens = { targets = MINIMAP_ONLY, execution = "parent", default = false },
}

local TARGET_KEYS = { scrollbar = true, minimap = true }

local KEYS = {
    search = { incsearch = true, backend = true, scrollbar = true, minimap = true },
    marks = { letters = true, numbers = true, scrollbar = true, minimap = true },
}

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
            options = (consumers.scrollbar or consumers.minimap) and vim.deepcopy(request.options) or false,
            targets = vim.deepcopy(spec.targets),
            execution = spec.execution,
        }
    end
    return plan
end

return M
