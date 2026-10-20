--- Top-level configuration shared by the scrollbar and the minimap: the
--- highlight policy, the mark-type registry, and the exclusion lists.

local const = require("scrollbar.config.const")
local schema = require("scrollbar.config.schema")

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

-- Autocmd events with a dedicated handler in both schedulers. Any other event
-- in the `events` option of a renderer renders every window. Provider updates
-- arrive through the store instead.
local EVENTS = {
    "BufEnter",
    "BufWinEnter",
    "WinEnter",
    "TabEnter",
    "TermEnter",
    "CmdwinLeave",
    "CursorMoved",
    "CursorMovedI",
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "TextChangedT",
    "WinScrolled",
    "WinResized",
    "VimResized",
    "OptionSet",
    "ColorScheme",
    "WinClosed",
    "BufDelete",
    "BufWipeout",
    "TabClosed",
}
local HANDLED_EVENTS = {}
for _, event in ipairs(EVENTS) do
    HANDLED_EVENTS[event] = true
end
M.EVENTS = EVENTS
M.HANDLED_EVENTS = HANDLED_EVENTS

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

-- Lowercase autocmd event names mapped to their canonical spelling. Neovim
-- matches event names case-insensitively, but the schedulers dispatch on the
-- canonical name.
---@type table<string, string>?
local canonical_events

---@param event string
---@param path string
---@return string
local function canonical_event(event, path)
    if canonical_events == nil then
        canonical_events = {}
        for _, name in ipairs(vim.fn.getcompletion("", "event")) do
            canonical_events[name:lower()] = name
        end
    end
    local name = canonical_events[event:lower()]
    if name ~= nil then
        return name
    end
    schema.invalid(string.format("%s: unknown autocmd event '%s'", path, event))
    return event
end

local EVENT_ENTRY_KEYS = { pattern = true }
local EVENT_LIST_ENTRY_KEYS = { event = true, pattern = true }

---@param value any
---@param path string
---@return false|string[]
local function event_pattern(value, path)
    if value == nil then
        return false
    end
    if type(value) == "string" then
        if value == "" then
            schema.invalid(path .. " must not be empty")
        end
        return { value }
    end
    if type(value) ~= "table" then
        schema.invalid(path .. " must be a string or a dense list of strings")
    end
    if schema.dense_count(value, path) == 0 then
        schema.invalid(path .. " must contain at least one pattern")
    end
    local patterns = schema.string_list(value, path)
    for index, pattern in ipairs(patterns) do
        if pattern == "" then
            schema.invalid(string.format("%s[%d] must not be empty", path, index))
        end
    end
    return patterns
end

---@param item any
---@param path string
---@return string event
---@return false|string[] pattern
local function event_list_entry(item, path)
    if type(item) == "string" then
        return canonical_event(item, path), false
    end
    if type(item) ~= "table" then
        schema.invalid(path .. " must be an event name or a table with 'event' and 'pattern'")
    end
    schema.check_keys(item, EVENT_LIST_ENTRY_KEYS, path)
    if type(item.event) ~= "string" then
        schema.invalid(path .. ".event must be a string")
    end
    return canonical_event(item.event, path .. ".event"), event_pattern(item.pattern, path .. ".pattern")
end

--- Resolve the `events` option of one renderer. A list replaces `defaults`. A
--- table keyed by event name merges with `defaults`: `true` adds the event,
--- `false` removes it, and a table sets its pattern. A list entry is an event
--- name or `{ event, pattern }`. Any autocmd event is valid, once. The result
--- lists the handled events in the order of `EVENTS`, then the other events
--- sorted.
---@param value any
---@param defaults string[]
---@param path string
---@return ScrollbarEventConfig[]
M.resolve_events = function(value, defaults, path)
    -- `false` selects the default pattern of the scheduler for the event.
    ---@type table<string, false|string[]>
    local enabled = {}
    if value == nil then
        for _, event in ipairs(defaults) do
            enabled[event] = false
        end
    elseif type(value) ~= "table" then
        schema.invalid(path .. " must be a dense list or a table keyed by event name")
    elseif next(value) == nil or schema.is_dense_list(value) then
        for index = 1, #value do
            local item_path = schema.join(path, index)
            local name, pattern = event_list_entry(value[index], item_path)
            if enabled[name] ~= nil then
                schema.invalid(string.format("%s duplicates event '%s'", item_path, name))
            end
            enabled[name] = pattern
        end
    else
        for _, event in ipairs(defaults) do
            enabled[event] = false
        end
        local seen = {}
        for event, entry in pairs(value) do
            if type(event) ~= "string" then
                schema.invalid(path .. " must be a dense list or a table keyed by event name, not both")
            end
            local entry_path = path .. "." .. event
            local name = canonical_event(event, entry_path)
            if seen[name] then
                schema.invalid(string.format("%s duplicates event '%s'", entry_path, name))
            end
            seen[name] = true
            if entry == true then
                enabled[name] = false
            elseif entry == false then
                enabled[name] = nil
            elseif type(entry) == "table" then
                schema.check_keys(entry, EVENT_ENTRY_KEYS, entry_path)
                enabled[name] = event_pattern(entry.pattern, entry_path .. ".pattern")
            else
                schema.invalid(entry_path .. " must be a boolean or table")
            end
        end
    end

    local names = {}
    for _, event in ipairs(EVENTS) do
        if enabled[event] ~= nil then
            names[#names + 1] = event
        end
    end
    local others = {}
    for event in pairs(enabled) do
        if not HANDLED_EVENTS[event] then
            others[#others + 1] = event
        end
    end
    table.sort(others)
    vim.list_extend(names, others)
    if #names == 0 then
        schema.invalid(path .. " must contain at least one event")
    end

    local result = {}
    for index, event in ipairs(names) do
        result[index] = { event = event, pattern = enabled[event] }
    end
    return result
end

---@class ScrollbarResolveMarksOptions
---@field fields string[] Spec fields that the renderer uses
---@field reject? table<string, string> Mark types that the renderer rejects, with the reason

--- Apply the layered `marks` overrides of one renderer to the registry.
--- `false` hides every type. A type set to `false` is hidden. A table merges
--- onto the registry spec. A type that the registry hides stays hidden unless
--- an override table shows it again.
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
