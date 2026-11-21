--- Helpers that the renderer, layout, and mouse tests share.

local MiniTest = MiniTest
local helpers = require("tests.helpers")

local M = {}

-- Installs these modules in the child:
--
-- - `require("scrollbar.test.fill_lines")(count)` sets the lines of the
--   current buffer to "line 1" through "line <count>", and returns these
--   lines.
-- - `require("scrollbar.test.text_height_counter")()` counts the calls of
--   `nvim_win_text_height` until `restore()`.
-- - `require("scrollbar.test.set_config")(scrollbar, shared)` sets
--   `scrollbar` as the scrollbar block over the test baseline. The sections
--   of `shared` replace the sections of the baseline.
local function install_child_modules()
    package.loaded["scrollbar.test.fill_lines"] = function(count)
        local lines = {}
        for index = 1, count do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        return lines
    end

    package.loaded["scrollbar.test.set_config"] = function(scrollbar, shared)
        local options = vim.tbl_extend("force", {
            set_highlights = false,
            providers = { cursor = false, diagnostic = false, search = false },
            exclude = { buftypes = {}, filetypes = {} },
        }, shared or {})
        options.scrollbar = scrollbar
        return require("scrollbar.config").set(options)
    end

    package.loaded["scrollbar.test.text_height_counter"] = function()
        local calls = 0
        local original = vim.api.nvim_win_text_height
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.api.nvim_win_text_height = function(...)
            calls = calls + 1
            return original(...)
        end
        return {
            count = function()
                return calls
            end,
            delta = function(since)
                return calls - since
            end,
            restore = function()
                vim.api.nvim_win_text_height = original
            end,
        }
    end
end

--- A child Neovim with the modules of `install_child_modules`. The child
--- stops at the end of the case.
M.new_child = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.lua_func(install_child_modules)
    return child
end

return M
