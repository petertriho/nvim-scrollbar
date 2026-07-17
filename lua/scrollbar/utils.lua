local const = require("scrollbar.const")

local M = {}

M.get_highlight_name = function(mark_type, thumb, pressed)
    return string.format(
        "%s%s%s%s",
        const.NAME_PREFIX,
        mark_type,
        thumb and const.NAME_SUFFIX or "",
        pressed and const.NAME_PRESSED_SUFFIX or ""
    )
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

M.set_highlights = function()
    local active_config = require("scrollbar.config").get()
    local track = background_highlight(active_config.track.highlight, nil, "PmenuSbar", "#000000")
    local thumb = thumb_highlight(active_config.thumb)
    local pressed = background_highlight("PmenuSel", active_config.thumb.blend, "PmenuThumb", "#ffffff")

    vim.api.nvim_set_hl(0, "ScrollbarBase", {})
    vim.api.nvim_set_hl(0, "ScrollbarTrack", track)
    vim.api.nvim_set_hl(0, M.get_highlight_name("", true), thumb)
    vim.api.nvim_set_hl(0, M.get_highlight_name("", true, true), pressed)
    vim.api.nvim_set_hl(0, M.get_legacy_highlight_name("", true), thumb)
    vim.api.nvim_set_hl(0, M.get_legacy_highlight_name("", true, true), pressed)
    for mark_type, properties in pairs(active_config.marks) do
        local mark = mark_highlight(properties)
        local overlap = vim.tbl_deep_extend("force", {}, thumb, mark)
        local pressed_overlap = vim.tbl_deep_extend("force", {}, pressed, mark)
        vim.api.nvim_set_hl(0, M.get_highlight_name(mark_type, false), mark)
        vim.api.nvim_set_hl(0, M.get_highlight_name(mark_type, true), overlap)
        vim.api.nvim_set_hl(0, M.get_highlight_name(mark_type, true, true), pressed_overlap)
        vim.api.nvim_set_hl(0, M.get_legacy_highlight_name(mark_type, true), overlap)
        vim.api.nvim_set_hl(0, M.get_legacy_highlight_name(mark_type, true, true), pressed_overlap)
    end
end

return M
