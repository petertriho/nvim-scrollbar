--- Helpers for the tests that drive a child Neovim.

local helpers = require("tests.helpers")

local M = {}

--- Fill the current buffer of `child` with the lines "line 1" to
--- "line `count`".
---@param child table
---@param count integer
M.set_numbered_lines = function(child, count)
    local lines = {}
    for index = 1, count do
        lines[index] = "line " .. index
    end
    helpers.set_lines(child, lines)
end

return M
