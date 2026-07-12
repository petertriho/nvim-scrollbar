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

M.set_highlights = function()
    local active_config = require("scrollbar.config").get()
    local handle_color =
        M.highlight_to_hex_color(active_config.handle.highlight, "background", "CursorColumn", "#ffffff")

    vim.api.nvim_set_hl(0, M.get_highlight_name("", true), {
        bg = handle_color,
        blend = active_config.handle.blend,
    })
    for mark_type, properties in pairs(active_config.marks) do
        local type_color = M.highlight_to_hex_color(properties.highlight, "foreground", "Normal", "#000000")
        vim.api.nvim_set_hl(0, M.get_highlight_name(mark_type, false), { fg = type_color })
        vim.api.nvim_set_hl(0, M.get_highlight_name(mark_type, true), {
            fg = type_color,
            bg = handle_color,
            blend = active_config.handle.blend,
        })
    end
end

return M
