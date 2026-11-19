local config = require("scrollbar.minimap.config")
local highlights = require("scrollbar.highlights")

local M = {}
local PREFIX = "ScrollbarMinimap"
local GENERATED_PREFIX = PREFIX .. "Generated."
local RESOLVED_PREFIX = PREFIX .. "Resolved."
local resolved_cache = {}
local resolved_count = 0
-- The static groups that a source window without focus can use in place of
-- the active group. The plugin never writes them, so they apply only when a
-- user or a colorscheme defines them.
local STATIC_INACTIVE = {
    "ScrollbarMinimapContent",
    "ScrollbarMinimapViewport",
    "ScrollbarMinimapCursor",
}
-- The replacement map of each variant, keyed by the variant configuration.
-- See `scrollbar.highlights`.
local inactive_maps = setmetatable({}, { __mode = "k" })
-- The public inactive groups that had a user or colorscheme definition at the
-- last call of `M.set`.
local last_defined = {}

---@param spec ScrollbarMinimapMarkSpec
local function definition(spec)
    local source = spec.highlight
    if type(source) == "table" then
        return vim.deepcopy(source)
    end
    return highlights.mark_definition(source, spec.highlight_channel)
end

---@param spec ScrollbarMinimapMarkSpec
local function inactive_definition(spec)
    local source = spec.inactive_highlight
    if type(source) == "table" then
        return vim.deepcopy(source)
    end
    -- The caller checks that the mark sets `inactive_highlight`.
    ---@cast source string
    return highlights.mark_definition(source, spec.inactive_highlight_channel or spec.highlight_channel)
end

---The sources that select the inactive definition of a mark.
---@param spec ScrollbarMinimapMarkSpec
local function inactive_source(spec)
    return { spec.highlight, spec.highlight_channel, spec.inactive_highlight, spec.inactive_highlight_channel }
end

local function generated_name(public_name)
    return GENERATED_PREFIX .. public_name:sub(#PREFIX + 1)
end

local function set_default_link(name, target)
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
end

local function reset_resolved()
    resolved_cache = {}
    resolved_count = 0
end

---@return vim.api.keyset.highlight
local function resolved_definition(source)
    local ok, resolved = pcall(vim.api.nvim_get_hl, 0, { name = source, link = false })
    if not ok or type(resolved) ~= "table" then
        return {}
    end
    -- With link = false, the keys of nvim_get_hl are valid keys of nvim_set_hl
    return vim.deepcopy(resolved) --[[@as vim.api.keyset.highlight]]
end

local function resolved_name(mode)
    resolved_count = resolved_count + 1
    return string.format("%s%s%d", RESOLVED_PREFIX, mode == "base" and "Base" or "Layer", resolved_count)
end

--- The public inactive groups that a user or a colorscheme defines: the
--- static groups and the inactive groups of the root marks. The default link
--- of the plugin and an empty group do not count.
---@param root ScrollbarMinimapConfig
---@return table<string, true>
local function defined_inactive_groups(root)
    local defined = {}
    local function check(name)
        local public_name = highlights.inactive_name(name)
        if highlights.external_definition(public_name, generated_name(public_name)) ~= nil then
            defined[public_name] = true
        end
    end
    for _, name in ipairs(STATIC_INACTIVE) do
        check(name)
    end
    for mark_type in pairs(root.marks) do
        check(PREFIX .. mark_type)
    end
    for _, variant in ipairs(config.get_variants()) do
        for mark_type in pairs(variant.config.marks) do
            if root.marks[mark_type] == nil then
                check(PREFIX .. mark_type)
            end
        end
    end
    return defined
end

--- The mark types of a variant whose inactive color is on: the variant sets
--- `inactive_highlight`, or a user or a colorscheme defines the public
--- inactive group.
---@param variant_config ScrollbarMinimapConfig
---@param defined table<string, true>
---@return table<string, true>
local function inactive_marks(variant_config, defined)
    local result = {}
    for mark_type, spec in pairs(variant_config.marks) do
        if spec.inactive_highlight ~= nil or defined[highlights.inactive_name(PREFIX .. mark_type)] then
            result[mark_type] = true
        end
    end
    return result
end

---@param variant_config ScrollbarMinimapConfig
---@param marks table<string, true>
---@param defined table<string, true>
---@return table<string, string>?
local function inactive_replacements(variant_config, marks, defined)
    local map = {}
    for _, name in ipairs(STATIC_INACTIVE) do
        local inactive_name = highlights.inactive_name(name)
        if defined[inactive_name] then
            map[name] = inactive_name
        end
    end
    for mark_type in pairs(marks) do
        local group = variant_config.marks[mark_type].group
        map[group] = highlights.inactive_name(group)
    end
    if next(map) == nil then
        return nil
    end
    return map
end

---The replacement map of a variant for a source window without focus, or nil
---when the variant has no inactive group.
---@param variant_config ScrollbarMinimapConfig
---@return table<string, string>?
M.inactive_map = function(variant_config)
    return inactive_maps[variant_config]
end

M.set = function()
    reset_resolved()
    local root = config.get()
    local defined = defined_inactive_groups(root)
    last_defined = defined
    inactive_maps = setmetatable({}, { __mode = "k" })
    local variant_marks = {}
    for _, variant in ipairs(config.get_variants()) do
        local marks = inactive_marks(variant.config, defined)
        variant_marks[variant.id] = marks
        inactive_maps[variant.config] = inactive_replacements(variant.config, marks, defined)
    end
    if not root.set_highlights then
        return
    end

    set_default_link("ScrollbarMinimapBase", "Normal")
    set_default_link("ScrollbarMinimapContent", "Comment")
    set_default_link("ScrollbarMinimapViewport", "Visual")
    set_default_link("ScrollbarMinimapCursor", "Cursor")
    set_default_link("ScrollbarMinimapFloatBorder", "FloatBorder")
    set_default_link("ScrollbarMinimapFloatTitle", "FloatTitle")
    set_default_link("ScrollbarMinimapFloatFooter", "FloatFooter")

    -- The final definition of a root group is the user or colorscheme
    -- definition of the public group, or else the generated definition. A
    -- profile copies it when the profile has the same source as the root.
    local root_final = {}
    local root_inactive_final = {}
    local root_inactive = variant_marks[0]
    for mark_type, spec in pairs(root.marks) do
        local private_name = generated_name(spec.group)
        local generated = definition(spec)
        vim.api.nvim_set_hl(0, private_name, generated)
        set_default_link(spec.group, private_name)
        root_final[mark_type] = highlights.external_definition(spec.group, private_name) or generated
        if root_inactive[mark_type] then
            -- Without its own option, the inactive group copies the final
            -- active definition.
            local public_name = highlights.inactive_name(spec.group)
            local inactive_private = generated_name(public_name)
            local inactive_generated = spec.inactive_highlight ~= nil and inactive_definition(spec)
                or vim.deepcopy(root_final[mark_type])
            vim.api.nvim_set_hl(0, inactive_private, inactive_generated)
            set_default_link(public_name, inactive_private)
            root_inactive_final[mark_type] = highlights.external_definition(public_name, inactive_private)
                or inactive_generated
        end
    end
    for _, variant in ipairs(config.get_variants()) do
        if variant.id > 0 then
            local marks = variant_marks[variant.id]
            for mark_type, spec in pairs(variant.config.marks) do
                local root_spec = root.marks[mark_type]
                local final
                if
                    root_spec ~= nil
                    and vim.deep_equal(spec.highlight, root_spec.highlight)
                    and spec.highlight_channel == root_spec.highlight_channel
                then
                    final = vim.deepcopy(root_final[mark_type])
                else
                    final = definition(spec)
                end
                vim.api.nvim_set_hl(0, spec.group, final)
                if marks[mark_type] then
                    local inactive
                    if
                        root_inactive_final[mark_type] ~= nil
                        and vim.deep_equal(inactive_source(spec), inactive_source(root_spec))
                    then
                        inactive = vim.deepcopy(root_inactive_final[mark_type])
                    elseif spec.inactive_highlight ~= nil then
                        inactive = inactive_definition(spec)
                    else
                        inactive = vim.deepcopy(final)
                    end
                    vim.api.nvim_set_hl(0, highlights.inactive_name(spec.group), inactive)
                end
            end
        end
    end
end

--- Check the public inactive groups again, and set the groups again when the
--- set of defined groups changed. See `scrollbar.highlights.refresh_inactive`.
---@return boolean changed
M.refresh_inactive = function()
    if not vim.deep_equal(defined_inactive_groups(config.get()), last_defined) then
        M.set()
        return true
    end
    return false
end

---@param source string
---@param blend integer
---@param mode "base"|"layer"
---@return string
M.resolve = function(source, blend, mode)
    assert(mode == "base" or mode == "layer", "invalid minimap highlight resolution mode")

    local by_mode = resolved_cache[mode]
    if by_mode == nil then
        by_mode = {}
        resolved_cache[mode] = by_mode
    end
    local by_blend = by_mode[blend]
    if by_blend == nil then
        by_blend = {}
        by_mode[blend] = by_blend
    end
    if by_blend[source] ~= nil then
        return by_blend[source]
    end

    local resolved = resolved_definition(source)
    if mode == "layer" and (resolved.bg == nil or resolved.blend ~= nil) then
        by_blend[source] = source
        return source
    end

    resolved.blend = blend
    local name = resolved_name(mode)
    vim.api.nvim_set_hl(0, name, resolved)
    by_blend[source] = name
    return name
end

return M
