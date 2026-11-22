local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")

local M = {}

-- The pinned plugins of `make test-deps`. Only the children of the
-- integration tests add them to their runtimepath.
M.DEPS = { "deps/snacks.nvim", "deps/telescope.nvim", "deps/plenary.nvim" }

--- A child with the pinned pickers, the glance marks, and a file buffer
--- with the line text "  text <n>". Line 61 has an unsaved edit. The messages
--- of `vim.notify` go to `_G.notes` as `{ message, level }`.
---@param top? table Top-level overrides of the configuration
---@return table child
---@return { source_win: integer, source_buf: integer }
M.new_child = function(top)
    for _, path in ipairs(M.DEPS) do
        if vim.fn.isdirectory(path) == 0 then
            MiniTest.skip(path .. " is missing. Run `make test-deps`.")
        end
    end
    local child = navigate.new_child()
    child.o.lines = 40
    child.o.columns = 120
    child.lua(
        [[
        for _, path in ipairs(...) do
            vim.opt.runtimepath:prepend(vim.fn.fnamemodify(path, ":p"))
        end
        -- A write of the buffer clears the marks, so the file exists first.
        _G.lines = {}
        for index = 1, 200 do
            _G.lines[index] = "  text " .. index
        end
        local file = vim.fn.tempname() .. ".txt"
        vim.fn.writefile(_G.lines, file)
        vim.cmd("edit " .. vim.fn.fnameescape(file))
    ]],
        { M.DEPS }
    )
    local result = navigate.setup(child, { marks = navigate.GLANCE_MARKS, full = true, config = navigate.config(top) })
    child.lua([[
        _G.notes = {}
        vim.notify = function(message, level)
            table.insert(_G.notes, { message, level })
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, _G.lines)
        vim.api.nvim_buf_set_lines(0, 60, 61, false, { "  unsaved 61" })
        require("snacks").setup({ picker = { enabled = true } })
        require("telescope").setup({})
    ]])
    return child, result
end

--- Wait until the child evaluates `expression` to true. A timeout raises an
--- error.
---@param child table
---@param expression string Lua expression that the child evaluates
M.wait_for = function(child, expression)
    local deadline = vim.uv.hrtime() + 5e9
    repeat
        if child.lua_get(expression) == true then
            return
        end
        vim.uv.sleep(20)
    until vim.uv.hrtime() > deadline
    error("timeout: " .. expression)
end

return M
