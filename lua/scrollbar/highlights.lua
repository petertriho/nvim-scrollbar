local const = require("scrollbar.config.const")
local overlap = require("scrollbar.overlap")

local M = {}
local GENERATED_PREFIX = const.NAME_PREFIX .. "Generated."

M.get_highlight_name = function(mark_type, thumb, pressed, prefix)
    return string.format(
        "%s%s%s%s",
        prefix or const.NAME_PREFIX,
        mark_type,
        thumb and const.NAME_SUFFIX or "",
        pressed and const.NAME_PRESSED_SUFFIX or ""
    )
end

---@param active_config ScrollbarConfig
---@param variant_id integer
---@param automatic boolean
---@return ScrollbarHighlightGroups
M.get_highlight_groups = function(active_config, variant_id, automatic)
    local prefix = automatic and variant_id > 0 and (const.NAME_PREFIX .. "Profile" .. variant_id .. ".")
        or const.NAME_PREFIX
    local marks = {}
    for mark_type in pairs(active_config.marks) do
        marks[mark_type] = {
            mark = M.get_highlight_name(mark_type, false, false, prefix),
            thumb = M.get_highlight_name(mark_type, true, false, prefix),
            thumb_pressed = M.get_highlight_name(mark_type, true, true, prefix),
            tint = M.get_highlight_name(mark_type .. "Tint", false, false, prefix),
        }
    end
    local show_through = active_config.overlap.show_through
    return {
        base = M.get_highlight_name("Base", false, false, prefix),
        surface = show_through and M.surface_name(show_through) or nil,
        track = M.get_highlight_name("Track", false, false, prefix),
        thumb = M.get_highlight_name("", true, false, prefix),
        thumb_pressed = M.get_highlight_name("", true, true, prefix),
        marks = marks,
    }
end

---The blend-only group under a mark that has no track or thumb below it.
---@param blend integer
---@return string
M.surface_name = function(blend)
    return GENERATED_PREFIX .. "Surface" .. blend
end

M.get_legacy_highlight_name = function(mark_type, thumb, pressed)
    return string.format(
        "%s%s%s%s",
        const.NAME_PREFIX,
        mark_type,
        thumb and const.LEGACY_NAME_SUFFIX or "",
        pressed and const.NAME_PRESSED_SUFFIX or ""
    )
end

M.to_hex_color = function(rgb_color)
    return string.format("#%06x", rgb_color)
end

---@param name string
---@return vim.api.keyset.get_hl_info?
local function get_highlight(name)
    -- nvim_get_hl gives an empty table for a group that does not exist, and creates the group. Check first, so that a
    -- missing group selects the fallback group.
    local exists_ok, exists = pcall(vim.fn.hlexists, name)
    if not exists_ok or exists == 0 then
        return nil
    end
    local ok, highlight = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    return ok and highlight or nil
end

---@param property "fg" | "bg"
M.highlight_to_hex_color = function(hl, property, fallback_hl, fallback_hex)
    local highlight = get_highlight(hl) or get_highlight(fallback_hl)

    local hex_color = fallback_hex
    if highlight ~= nil then
        local color = highlight[property]
        if color then
            local hex_ok
            hex_ok, hex_color = pcall(M.to_hex_color, color)
            if not hex_ok then
                hex_color = fallback_hex
            end
        end
    end
    return hex_color
end

local function background_highlight(source, blend, fallback_hl, fallback_hex)
    if type(source) == "table" then
        local highlight = vim.deepcopy(source)
        if blend ~= nil and highlight.blend == nil then
            highlight.blend = blend
        end
        return highlight
    end

    local highlight = {
        bg = M.highlight_to_hex_color(source, "bg", fallback_hl, fallback_hex),
    }
    if blend ~= nil then
        highlight.blend = blend
    end
    return highlight
end

---@param highlight ScrollbarHighlight
---@param blend integer
local function thumb_highlight(highlight, blend)
    return background_highlight(highlight, blend, "PmenuThumb", "#ffffff")
end

---The background of a tint: the foreground of the mark, or else its
---background.
---@param mark vim.api.keyset.highlight
---@param blend integer
---@return vim.api.keyset.highlight
local function tint_highlight(mark, blend)
    local color = mark.fg or mark.bg
    local link = mark.link
    if color == nil and type(link) == "string" then
        local linked = get_highlight(link)
        color = linked and (linked.fg or linked.bg)
    end
    if color == nil then
        color = M.highlight_to_hex_color("Normal", "fg", "Normal", "#ffffff")
    end
    return { bg = color, blend = blend }
end

local function mark_highlight(properties)
    if type(properties.highlight) == "table" then
        return vim.deepcopy(properties.highlight)
    end

    return {
        fg = M.highlight_to_hex_color(properties.highlight, "fg", "Normal", "#000000"),
    }
end

local function generated_name(public_name)
    return GENERATED_PREFIX .. public_name:sub(#const.NAME_PREFIX + 1)
end

local function set_default_link(name, target)
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
end

local function set_root_highlight(public_name, definition)
    local private_name = generated_name(public_name)
    vim.api.nvim_set_hl(0, private_name, definition)
    set_default_link(public_name, private_name)
end

--- The definition of a public group that a user or a colorscheme sets. The
--- default link of the plugin to `private_name`, an empty group, and a missing
--- group give nil. `:hi clear` leaves an empty group, and the default link
--- applies to it.
---@param public_name string
---@param private_name string
---@return vim.api.keyset.highlight?
M.external_definition = function(public_name, private_name)
    local definition = get_highlight(public_name)
    if definition == nil or vim.api.nvim_get_hl(0, { name = public_name }).link == private_name then
        return nil
    end
    -- With `default`, nvim_set_hl would keep the earlier definition of a derived group.
    definition.default = nil
    if next(definition) == nil then
        return nil
    end
    -- With link = false, the other keys of nvim_get_hl are valid keys of nvim_set_hl
    return definition --[[@as vim.api.keyset.highlight]]
end

---@class ScrollbarHighlightEntry
---@field key string
---@field name string
---@field source any The options that select the definition
---@field generate fun(final: table<string, vim.api.keyset.highlight>): vim.api.keyset.highlight

---@class ScrollbarVariantHighlights
---@field sources table<string, any>
---@field final table<string, vim.api.keyset.highlight>

--- The groups of one variant. An overlap entry comes after the thumb entry and
--- the mark entry that it merges.
---@param active_config ScrollbarConfig
---@return ScrollbarHighlightEntry[]
local function variant_entries(active_config)
    local groups = active_config.highlights
    local track = active_config.track
    local thumb = active_config.thumb
    local base_blend = overlap.base_blend(active_config)
    local surface_blend = overlap.surface_blend(active_config)
    local thumb_blend = overlap.thumb_blend(active_config)
    local entries = {
        {
            key = "base",
            name = groups.base,
            source = base_blend,
            generate = function()
                -- A profile keeps the colors of a user definition of the
                -- public base group.
                local external = M.external_definition("ScrollbarBase", generated_name("ScrollbarBase"))
                return overlap.with_blend(external or {}, base_blend)
            end,
        },
        {
            key = "track",
            name = groups.track,
            source = { track.highlight, surface_blend },
            generate = function()
                return background_highlight(track.highlight, surface_blend, "PmenuSbar", "#000000")
            end,
        },
        {
            key = "thumb",
            name = groups.thumb,
            source = { thumb.highlight, thumb_blend },
            generate = function()
                return thumb_highlight(thumb.highlight, thumb_blend)
            end,
        },
        {
            key = "thumb_pressed",
            name = groups.thumb_pressed,
            source = thumb_blend,
            generate = function()
                return background_highlight("PmenuSel", thumb_blend, "PmenuThumb", "#ffffff")
            end,
        },
    }
    local tint = active_config.overlap.marks == "tint"
    for mark_type, properties in pairs(active_config.marks) do
        local mark_groups = groups.marks[mark_type]
        -- A mark type cannot contain a dot, so the keys are unique.
        local key = "marks." .. mark_type
        entries[#entries + 1] = {
            key = key,
            name = mark_groups.mark,
            source = properties.highlight,
            generate = function()
                return mark_highlight(properties)
            end,
        }
        entries[#entries + 1] = {
            key = key .. ".thumb",
            name = mark_groups.thumb,
            source = { thumb.highlight, thumb_blend, properties.highlight },
            generate = function(final)
                return vim.tbl_deep_extend("force", {}, final.thumb, final[key])
            end,
        }
        entries[#entries + 1] = {
            key = key .. ".thumb_pressed",
            name = mark_groups.thumb_pressed,
            source = { thumb_blend, properties.highlight },
            generate = function(final)
                return vim.tbl_deep_extend("force", {}, final.thumb_pressed, final[key])
            end,
        }
        if tint then
            entries[#entries + 1] = {
                key = key .. ".tint",
                name = mark_groups.tint,
                source = { surface_blend, properties.highlight },
                generate = function(final)
                    return tint_highlight(final[key], surface_blend)
                end,
            }
        end
    end
    return entries
end

--- Set the groups of one variant. The final definition of a root group is the
--- user or colorscheme definition of the public group, or else the generated
--- definition. The overlap groups merge the final definitions, so a mark keeps
--- its color over the thumb. A profile copies the final definition of a root
--- group when it has the same options for the group as the root, so an option
--- in the profile wins.
---@param active_config ScrollbarConfig
---@param root? ScrollbarVariantHighlights Nil for the root itself
---@return ScrollbarVariantHighlights
local function set_variant_highlights(active_config, root)
    local sources = {}
    local final = {}
    for _, entry in ipairs(variant_entries(active_config)) do
        sources[entry.key] = entry.source
        if root == nil then
            -- The private group keeps the generated definition. The public group links to it again when the external
            -- definition goes away.
            local generated = entry.generate(final)
            set_root_highlight(entry.name, generated)
            final[entry.key] = M.external_definition(entry.name, generated_name(entry.name)) or generated
        else
            local root_final = root.final[entry.key]
            if root_final ~= nil and vim.deep_equal(entry.source, root.sources[entry.key]) then
                final[entry.key] = vim.deepcopy(root_final)
            else
                final[entry.key] = entry.generate(final)
            end
            vim.api.nvim_set_hl(0, entry.name, final[entry.key])
        end
    end
    if root == nil then
        local groups = active_config.highlights
        set_default_link(M.get_legacy_highlight_name("", true), groups.thumb)
        set_default_link(M.get_legacy_highlight_name("", true, true), groups.thumb_pressed)
        for mark_type in pairs(active_config.marks) do
            local mark_groups = groups.marks[mark_type]
            set_default_link(M.get_legacy_highlight_name(mark_type, true), mark_groups.thumb)
            set_default_link(M.get_legacy_highlight_name(mark_type, true, true), mark_groups.thumb_pressed)
        end
    end
    return { sources = sources, final = final }
end

--- Define the groups that carry only a blend. The renderer needs them also
--- when `set_highlights` is false, because they hold no colors to customize.
---@param config_module table
local function set_blend_groups(config_module)
    for _, variant in ipairs(config_module.get_variants()) do
        if variant.config.hide_on_cursor == "row" then
            vim.api.nvim_set_hl(0, overlap.CLEAR_GROUP, overlap.blend_only(100))
        end
        local show_through = variant.config.overlap.show_through
        if show_through then
            vim.api.nvim_set_hl(0, M.surface_name(show_through), overlap.blend_only(show_through))
        end
    end
end

M.set_highlights = function()
    local config = require("scrollbar.config")
    local active_config = config.get()
    set_blend_groups(config)
    if not active_config.set_highlights then
        return
    end

    set_default_link("ScrollbarFloatBorder", "FloatBorder")
    set_default_link("ScrollbarFloatTitle", "FloatTitle")
    set_default_link("ScrollbarFloatFooter", "FloatFooter")
    local root = set_variant_highlights(active_config, nil)
    for _, variant in ipairs(config.get_variants()) do
        if variant.id > 0 then
            set_variant_highlights(variant.config, root)
        end
    end
end

return M
