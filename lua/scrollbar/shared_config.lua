--- Top-level configuration shared by the scrollbar and the minimap: the
--- highlight policy, the mark-type registry, and the exclusion lists.

local const = require("scrollbar.const")
local schema = require("scrollbar.schema")

local M = {}

local DEFAULT_MARKS = {
    Cursor = { text = { "•" }, priority = 0, highlight = "Normal" },
    Mark = { text = {}, priority = 1, highlight = "Special" },
    Search = { text = { "-", "=" }, priority = 1, highlight = "Search" },
    Error = { text = { "-", "=" }, priority = 2, highlight = "DiagnosticVirtualTextError" },
    Warn = { text = { "-", "=" }, priority = 3, highlight = "DiagnosticVirtualTextWarn" },
    Info = { text = { "-", "=" }, priority = 4, highlight = "DiagnosticVirtualTextInfo" },
    Hint = { text = { "-", "=" }, priority = 5, highlight = "DiagnosticVirtualTextHint" },
    Misc = { text = { "-", "=" }, priority = 6, highlight = "Normal" },
    GitAdd = { text = { "┃" }, priority = 7, highlight = "GitSignsAdd" },
    GitChange = { text = { "┃" }, priority = 7, highlight = "GitSignsChange" },
    GitDelete = { text = { "▁" }, priority = 7, highlight = "GitSignsDelete" },
    MiniDiffAdd = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignAdd" },
    MiniDiffChange = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignChange" },
    MiniDiffDelete = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignDelete" },
    SignifyAdd = { text = { "┃" }, priority = 7, highlight = "SignifySignAdd" },
    SignifyChange = { text = { "┃" }, priority = 7, highlight = "SignifySignChange" },
    SignifyDelete = { text = { "▁" }, priority = 7, highlight = "SignifySignDelete" },
    VGitAdd = { text = { "┃" }, priority = 7, highlight = "GitSignsAdd" },
    VGitChange = { text = { "┃" }, priority = 7, highlight = "GitSignsChange" },
    VGitDelete = { text = { "▁" }, priority = 7, highlight = "GitSignsDelete" },
}

local DEFAULT_EXCLUDE = {
    buftypes = { "terminal" },
    filetypes = {
        "blink-cmp-menu",
        "dropbar_menu",
        "dropbar_menu_fzf",
        "DressingInput",
        "cmp_docs",
        "cmp_menu",
        "noice",
        "prompt",
        "TelescopePrompt",
    },
}

local MARK_KEYS = { text = true, priority = true, highlight = true }
local V1_MARK_COLOR = "v1 option: put an nvim_set_hl() table in 'highlight'. " .. const.V1_MIGRATION
local describe_mark_key = schema.hinter({
    color = V1_MARK_COLOR,
    color_nr = V1_MARK_COLOR,
    gui = V1_MARK_COLOR,
    cterm = V1_MARK_COLOR,
})
local TARGET_KEYS = { scrollbar = true, minimap = true }

---@param mark_type any
---@param path string
local function validate_type_name(mark_type, path)
    if type(mark_type) ~= "string" or not mark_type:match(schema.TYPE_NAME_PATTERN) then
        schema.invalid(string.format("%s has invalid mark type %s", path, vim.inspect(mark_type)))
    end
end

---@param spec table
---@param path string
---@param mark_type string
---@return ScrollbarMarkTypeConfig
local function validate_mark_spec(spec, path, mark_type)
    for _, field in ipairs({ "text", "priority", "highlight" }) do
        if spec[field] == nil then
            schema.invalid(string.format("%s.%s is required for a new mark type", path, field))
        end
    end
    return {
        text = schema.text_variants(spec.text, path .. ".text", mark_type == "Mark"),
        priority = schema.integer(spec.priority, path .. ".priority", 0),
        highlight = schema.highlight(spec.highlight, path .. ".highlight"),
    }
end

---@param value any
---@return ScrollbarMarkRegistry
local function normalize_marks(value)
    if value == nil then
        value = {}
    end
    schema.table(value, "marks")

    local specs = vim.deepcopy(DEFAULT_MARKS)
    local hidden = {}
    for mark_type, entry in pairs(value) do
        validate_type_name(mark_type, "marks")
        local path = "marks." .. mark_type
        if entry == false then
            if specs[mark_type] == nil then
                schema.invalid(string.format("%s: cannot hide unknown mark type '%s'", path, mark_type))
            end
            hidden[mark_type] = true
        elseif type(entry) == "table" then
            schema.check_keys(entry, MARK_KEYS, path, describe_mark_key)
            specs[mark_type] = schema.merge(specs[mark_type], entry)
        else
            schema.invalid(path .. " must be false or a table")
        end
    end

    for mark_type, spec in pairs(specs) do
        specs[mark_type] = validate_mark_spec(spec, "marks." .. mark_type, mark_type)
    end
    return { specs = specs, hidden = hidden }
end

---@param value any
---@param defaults string[]
---@param path string
---@return { scrollbar: table<string, true>, minimap: table<string, true> }
local function normalize_exclude_field(value, defaults, path)
    ---@type table<string, { scrollbar: boolean, minimap: boolean }>
    local entries = {}
    local function exclude_both(name)
        entries[name] = { scrollbar = true, minimap = true }
    end

    if value == nil then
        for _, name in ipairs(defaults) do
            exclude_both(name)
        end
    elseif type(value) ~= "table" then
        schema.invalid(path .. " must be a dense list or a table keyed by name")
    elseif next(value) == nil or schema.is_dense_list(value) then
        -- A list replaces the defaults, like every other dense list.
        for _, name in ipairs((schema.string_list(value, path))) do
            exclude_both(name)
        end
    else
        for _, name in ipairs(defaults) do
            exclude_both(name)
        end
        for name, entry in pairs(value) do
            if type(name) ~= "string" then
                schema.invalid(path .. " must be a dense list or a table keyed by name, not both")
            end
            local entry_path = path .. "." .. name
            if entry == true then
                exclude_both(name)
            elseif entry == false then
                entries[name] = nil
            elseif type(entry) == "table" then
                schema.check_keys(entry, TARGET_KEYS, entry_path)
                entries[name] = {
                    scrollbar = entry.scrollbar == nil or schema.boolean(entry.scrollbar, entry_path .. ".scrollbar"),
                    minimap = entry.minimap == nil or schema.boolean(entry.minimap, entry_path .. ".minimap"),
                }
            else
                schema.invalid(entry_path .. " must be a boolean or table")
            end
        end
    end

    local result = { scrollbar = {}, minimap = {} }
    for name, targets in pairs(entries) do
        if targets.scrollbar then
            result.scrollbar[name] = true
        end
        if targets.minimap then
            result.minimap[name] = true
        end
    end
    return result
end

---@param value any
---@return table<"scrollbar"|"minimap", ScrollbarExcludeConfig>
local function normalize_exclude(value)
    if value == nil then
        value = {}
    end
    schema.table(value, "exclude")
    schema.check_keys(value, { buftypes = true, filetypes = true }, "exclude")

    local buftypes = normalize_exclude_field(value.buftypes, DEFAULT_EXCLUDE.buftypes, "exclude.buftypes")
    local filetypes = normalize_exclude_field(value.filetypes, DEFAULT_EXCLUDE.filetypes, "exclude.filetypes")
    return {
        scrollbar = { buftypes = buftypes.scrollbar, filetypes = filetypes.scrollbar },
        minimap = { buftypes = buftypes.minimap, filetypes = filetypes.minimap },
    }
end

---@param overrides table Top-level setup options
---@return ScrollbarSharedConfig
M.normalize = function(overrides)
    local set_highlights = overrides.set_highlights
    if set_highlights == nil then
        set_highlights = true
    end
    return {
        set_highlights = schema.boolean(set_highlights, "set_highlights"),
        marks = normalize_marks(overrides.marks),
        exclude = normalize_exclude(overrides.exclude),
    }
end

---@class ScrollbarResolveMarksOptions
---@field fields string[] Spec fields that the renderer uses
---@field reject? table<string, string> Mark types that the renderer rejects, with the reason

--- Apply one renderer's layered `marks` overrides to the registry. `false`
--- hides every type. A type set to `false` is hidden. A table merges onto the
--- registry spec. A type that the registry hides stays hidden unless an
--- override table shows it again.
---@param registry ScrollbarMarkRegistry
---@param overrides any
---@param path string
---@param options ScrollbarResolveMarksOptions
---@return table<string, table>
M.resolve_marks = function(registry, overrides, path, options)
    local reject = options.reject or {}
    local result = {}
    if overrides == false then
        return result
    end
    if type(overrides) ~= "table" then
        schema.invalid(path .. " must be false or a table")
    end

    for mark_type, entry in pairs(overrides) do
        validate_type_name(mark_type, path)
        local entry_path = path .. "." .. mark_type
        if reject[mark_type] ~= nil then
            schema.invalid(entry_path .. ": " .. reject[mark_type])
        end
        if registry.specs[mark_type] == nil then
            schema.invalid(
                string.format(
                    "%s: unknown mark type '%s'. Define it in the top-level marks table",
                    entry_path,
                    mark_type
                )
            )
        end
        if entry ~= false and type(entry) ~= "table" then
            schema.invalid(entry_path .. " must be false or a table")
        end
    end

    for mark_type, spec in pairs(registry.specs) do
        if reject[mark_type] == nil then
            local entry = overrides[mark_type]
            local merged
            if entry == nil then
                merged = not registry.hidden[mark_type] and spec or nil
            elseif entry ~= false then
                merged = validate_mark_spec(schema.merge(spec, entry), path .. "." .. mark_type, mark_type)
            end
            if merged ~= nil then
                local selected = {}
                for _, field in ipairs(options.fields) do
                    selected[field] = vim.deepcopy(merged[field])
                end
                result[mark_type] = selected
            end
        end
    end
    return result
end

return M
