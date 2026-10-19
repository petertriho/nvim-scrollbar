-- Warns the users whose configuration breaks when v2 replaces v1 on the main
-- branch. The v1 branch and the v1.0.0 tag do not contain this file, so a
-- pinned v1 never shows the warning.

local M = {}

local MESSAGE = table.concat({
    "nvim-scrollbar: on 2026-11-16, v2 replaces v1 on the main branch, and your configuration needs changes.",
    'To keep v1, pin the "v1" branch. To migrate, see https://github.com/petertriho/nvim-scrollbar/issues/121',
    "To hide this message, set vim.g.scrollbar_v2_notice = false",
}, "\n")

-- v2 rejects the v1 options of setup().
local function has_options(config)
    local path = vim.api.nvim_get_runtime_file("lua/scrollbar/config.lua", false)[1]
    if path == nil then
        return false
    end
    local ok, defaults = pcall(dofile, path)
    return ok and not vim.deep_equal(config.get(), defaults.get())
end

-- v2 removes the scrollbar.handlers modules. Without options, setup() loads
-- only the cursor and diagnostic handlers, so another loaded handler module
-- comes from the user configuration.
local function uses_handlers()
    for _, name in ipairs({ "gitsigns", "search", "ale" }) do
        if package.loaded["scrollbar.handlers." .. name] ~= nil then
            return true
        end
    end
    local handlers = package.loaded["scrollbar.handlers"]
    return handlers ~= nil and #handlers.handlers > 0
end

M.check = function()
    local config = package.loaded["scrollbar.config"]
    if vim.g.scrollbar_v2_notice == false or config == nil then
        return
    end
    if vim.fn.has("nvim-0.11") == 0 or has_options(config) or uses_handlers() then
        vim.notify(MESSAGE, vim.log.levels.WARN)
    end
end

return M
