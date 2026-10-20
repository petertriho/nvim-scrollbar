local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local FORMATTER = [[
    vim.api.nvim_create_autocmd("BufWritePre", {
        buffer = 0,
        callback = function()
            vim.api.nvim_buf_set_lines(0, 0, 1, false, { "formatted" })
        end,
    })
]]

local function new_child(before_setup)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.lua([[
        vim.cmd("edit " .. vim.fn.fnameescape(vim.fn.tempname() .. ".txt"))
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two" })
    ]])
    if before_setup ~= nil then
        child.lua(before_setup)
    end
    child.lua([[require("scrollbar.text_tick").setup()]])
    return child
end

---Run `code` in the child and return how much the text tick and changedtick increased.
local function increases(child, code)
    return child.lua_get(string.format(
        [[(function()
            local text_tick = require("scrollbar.text_tick")
            local text, changed = text_tick.get(0), vim.b.changedtick
            %s
            return { text = text_tick.get(0) - text, changed = vim.b.changedtick - changed }
        end)()]],
        code
    ))
end

T["a write of a modified buffer keeps the text tick"] = function()
    local child = new_child()
    expect.equality(increases(child, [[vim.cmd("silent write")]]), { text = 0, changed = 1 })
end

T["a write of an unmodified buffer keeps the text tick"] = function()
    local child = new_child()
    child.lua([[vim.cmd("silent write")]])
    expect.equality(increases(child, [[vim.cmd("silent write")]]), { text = 0, changed = 0 })
end

T["a text change increases the text tick"] = function()
    local child = new_child()
    expect.equality(
        increases(child, [[vim.api.nvim_buf_set_lines(0, 0, 1, false, { "changed" })]]),
        { text = 1, changed = 1 }
    )
end

T["a change from a later BufWritePre autocmd increases the text tick"] = function()
    local child = new_child()
    child.lua(FORMATTER)
    expect.equality(increases(child, [[vim.cmd("silent write")]]), { text = 2, changed = 2 })
end

T["a change from an earlier BufWritePre autocmd increases the text tick"] = function()
    local child = new_child(FORMATTER)
    expect.equality(increases(child, [[vim.cmd("silent write")]]), { text = 1, changed = 2 })
end

T["dispose forgets the writes"] = function()
    local child = new_child()
    child.lua([[vim.cmd("silent write")]])
    local result = child.lua_get([[(function()
        local text_tick = require("scrollbar.text_tick")
        local before = text_tick.get(0)
        text_tick.dispose()
        return { before = before, after = text_tick.get(0), changed = vim.b.changedtick }
    end)()]])
    expect.equality(result.after, result.changed)
    expect.equality(result.after, result.before + 1)
end

return T
