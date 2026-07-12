local const = require("scrollbar.const")

local M = {}

M.get_highlight_name = function(mark_type, handle)
    return string.format("%s%s%s", const.NAME_PREFIX, mark_type, handle and const.NAME_SUFFIX or "")
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

local function handle_highlight(properties)
    if type(properties.highlight) == "table" then
        local highlight = vim.deepcopy(properties.highlight)
        if highlight.blend == nil then
            highlight.blend = properties.blend
        end
        return highlight
    end

    return {
        bg = M.highlight_to_hex_color(properties.highlight, "background", "CursorColumn", "#ffffff"),
        blend = properties.blend,
    }
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
    local handle = handle_highlight(active_config.handle)

    vim.api.nvim_set_hl(0, M.get_highlight_name("", true), handle)
    for mark_type, properties in pairs(active_config.marks) do
        local mark = mark_highlight(properties)
        vim.api.nvim_set_hl(0, M.get_highlight_name(mark_type, false), mark)
        vim.api.nvim_set_hl(0, M.get_highlight_name(mark_type, true), vim.tbl_deep_extend("force", {}, handle, mark))
    end
end

return M
