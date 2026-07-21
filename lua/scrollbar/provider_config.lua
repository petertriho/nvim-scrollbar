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

M.SCROLLBAR_NAMES = {
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
}

M.MINIMAP_NAMES = vim.deepcopy(M.ORDER)

local OPTION_KIND = {
    search = "search",
    marks = "marks",
}

local SPECS = {
    cursor = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    diagnostic = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    search = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    marks = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    gitsigns = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    mini_diff = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    signify = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    vgit = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    ale = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    coc = { targets = { scrollbar = true, minimap = true }, execution = "parent" },
    treesitter = { targets = { scrollbar = false, minimap = true }, execution = "worker" },
    lsp_semantic_tokens = { targets = { scrollbar = false, minimap = true }, execution = "parent" },
}

local NESTED_KEYS = {
    search = { incsearch = true, backend = true },
    marks = { letters = true, numbers = true },
}

local function invalid(message)
    error("[scrollbar.nvim] " .. message, 3)
end

local function validate_boolean(value, path)
    if type(value) ~= "boolean" then
        invalid(path .. " must be a boolean")
    end
end

local function name_lookup(names)
    local result = {}
    for _, name in ipairs(names) do
        result[name] = true
    end
    return result
end

---@param providers any
---@param names string[]
---@param path string
M.validate_shape = function(providers, names, path)
    if type(providers) ~= "table" then
        return
    end

    local allowed = name_lookup(names)
    for name in pairs(providers) do
        if not allowed[name] then
            invalid(string.format("unknown option '%s.%s'", path, tostring(name)))
        end
    end

    for name, allowed_keys in pairs(NESTED_KEYS) do
        local value = providers[name]
        if type(value) == "table" then
            for key in pairs(value) do
                if not allowed_keys[key] then
                    invalid(string.format("unknown option '%s.%s.%s'", path, name, tostring(key)))
                end
            end
        end
    end
end

local function normalize_search(value, path)
    if value == false then
        return false
    end
    if value == true then
        return { backend = "worker" }
    end
    if type(value) ~= "table" then
        invalid(path .. " must be a boolean or table")
    end

    local result = vim.deepcopy(value)
    if result.backend == nil then
        result.backend = "worker"
    end
    if result.incsearch ~= nil then
        validate_boolean(result.incsearch, path .. ".incsearch")
    end
    if result.backend ~= "sync" and result.backend ~= "worker" then
        invalid(path .. ".backend must be one of: sync, worker")
    end
    return result
end

local function normalize_marks(value, path)
    if value == false then
        return false
    end
    if value == true then
        return { letters = true, numbers = false }
    end
    if type(value) ~= "table" then
        invalid(path .. " must be a boolean or table")
    end

    local result = vim.deepcopy(value)
    if result.letters == nil then
        result.letters = true
    end
    if result.numbers == nil then
        result.numbers = false
    end
    validate_boolean(result.letters, path .. ".letters")
    validate_boolean(result.numbers, path .. ".numbers")
    return result
end

---@param providers table
---@param names string[]
---@param path string
---@return table, table<string, "boolean"|"table">
M.normalize = function(providers, names, path)
    if type(providers) ~= "table" then
        invalid(path .. " must be a table")
    end
    M.validate_shape(providers, names, path)

    local result = {}
    local requests = {}
    for _, name in ipairs(names) do
        local value = providers[name]
        requests[name] = type(value) == "table" and "table" or "boolean"
        if OPTION_KIND[name] == "search" then
            result[name] = normalize_search(value, path .. "." .. name)
        elseif OPTION_KIND[name] == "marks" then
            result[name] = normalize_marks(value, path .. "." .. name)
        else
            validate_boolean(value, path .. "." .. name)
            result[name] = value
        end
    end
    return result, requests
end

local function enabled(value)
    return value ~= nil and value ~= false
end

---@param scrollbar table
---@param scrollbar_requests table<string, "boolean"|"table">
---@param minimap table
---@param minimap_requests table<string, "boolean"|"table">
---@return ScrollbarEffectiveProviderPlan
M.compile_plan = function(scrollbar, scrollbar_requests, minimap, minimap_requests)
    local plan = {}
    for _, name in ipairs(M.ORDER) do
        local spec = SPECS[name]
        local scrollbar_enabled = spec.targets.scrollbar and enabled(scrollbar.providers[name])
        local minimap_enabled = minimap.enabled and spec.targets.minimap and enabled(minimap.providers[name])
        local options = false

        if OPTION_KIND[name] ~= nil then
            if
                scrollbar_enabled
                and minimap_enabled
                and scrollbar_requests[name] == "table"
                and minimap_requests[name] == "table"
                and not vim.deep_equal(scrollbar.providers[name], minimap.providers[name])
            then
                invalid(
                    string.format(
                        "conflicting provider options at 'scrollbar.providers.%s' and 'minimap.providers.%s'",
                        name,
                        name
                    )
                )
            end
            local selected
            local use_scrollbar = scrollbar_enabled
                and (scrollbar_requests[name] == "table" or not (minimap_enabled and minimap_requests[name] == "table"))
            if use_scrollbar then
                selected = scrollbar.providers[name]
            elseif minimap_enabled then
                selected = minimap.providers[name]
            end
            if selected ~= nil then
                options = vim.deepcopy(selected)
            end
        elseif scrollbar_enabled or minimap_enabled then
            options = true
        end

        plan[name] = {
            consumers = { scrollbar = scrollbar_enabled, minimap = minimap_enabled },
            options = options,
            targets = vim.deepcopy(spec.targets),
            execution = spec.execution,
        }
    end
    return plan
end

return M
