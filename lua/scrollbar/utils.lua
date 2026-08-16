local const = require("scrollbar.const")

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
        }
    end
    return {
        base = "ScrollbarBase",
        track = M.get_highlight_name("Track", false, false, prefix),
        thumb = M.get_highlight_name("", true, false, prefix),
        thumb_pressed = M.get_highlight_name("", true, true, prefix),
        marks = marks,
    }
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

M.highlight_to_hex_color = function(hl, property, fallback_hl, fallback_hex)
    local highlight_ok, highlight = pcall(vim.api.nvim_get_hl_by_name, hl, true)

    if not highlight_ok then
        highlight_ok, highlight = pcall(vim.api.nvim_get_hl_by_name, fallback_hl, true)
    end

    local hex_color = fallback_hex
    if highlight_ok then
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
        bg = M.highlight_to_hex_color(source, "background", fallback_hl, fallback_hex),
    }
    if blend ~= nil then
        highlight.blend = blend
    end
    return highlight
end

local function thumb_highlight(properties)
    return background_highlight(properties.highlight, properties.blend, "PmenuThumb", "#ffffff")
end

local function mark_highlight(properties)
    if type(properties.highlight) == "table" then
        return vim.deepcopy(properties.highlight)
    end

    return {
        fg = M.highlight_to_hex_color(properties.highlight, "foreground", "Normal", "#000000"),
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

---@param active_config ScrollbarConfig
---@param root boolean
local function set_variant_highlights(active_config, root)
    local groups = active_config.highlights
    local track = background_highlight(active_config.track.highlight, nil, "PmenuSbar", "#000000")
    local thumb = thumb_highlight(active_config.thumb)
    local pressed = background_highlight("PmenuSel", active_config.thumb.blend, "PmenuThumb", "#ffffff")

    if root then
        set_root_highlight(groups.track, track)
        set_root_highlight(groups.thumb, thumb)
        set_root_highlight(groups.thumb_pressed, pressed)
    else
        vim.api.nvim_set_hl(0, groups.track, track)
        vim.api.nvim_set_hl(0, groups.thumb, thumb)
        vim.api.nvim_set_hl(0, groups.thumb_pressed, pressed)
    end
    for mark_type, properties in pairs(active_config.marks) do
        local mark_groups = groups.marks[mark_type]
        local mark = mark_highlight(properties)
        local overlap = vim.tbl_deep_extend("force", {}, thumb, mark)
        local pressed_overlap = vim.tbl_deep_extend("force", {}, pressed, mark)
        if root then
            set_root_highlight(mark_groups.mark, mark)
            set_root_highlight(mark_groups.thumb, overlap)
            set_root_highlight(mark_groups.thumb_pressed, pressed_overlap)
        else
            vim.api.nvim_set_hl(0, mark_groups.mark, mark)
            vim.api.nvim_set_hl(0, mark_groups.thumb, overlap)
            vim.api.nvim_set_hl(0, mark_groups.thumb_pressed, pressed_overlap)
        end
    end
    if root then
        set_default_link(M.get_legacy_highlight_name("", true), groups.thumb)
        set_default_link(M.get_legacy_highlight_name("", true, true), groups.thumb_pressed)
        for mark_type in pairs(active_config.marks) do
            local mark_groups = groups.marks[mark_type]
            set_default_link(M.get_legacy_highlight_name(mark_type, true), mark_groups.thumb)
            set_default_link(M.get_legacy_highlight_name(mark_type, true, true), mark_groups.thumb_pressed)
        end
    end
end

M.set_highlights = function()
    local config = require("scrollbar.config")
    local active_config = config.get()
    if not active_config.set_highlights then
        return
    end

    set_root_highlight(active_config.highlights.base, {})
    for _, variant in ipairs(config.get_variants()) do
        set_variant_highlights(variant.config, variant.id == 0)
    end
end

return M
