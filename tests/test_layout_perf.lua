local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local COUNTER_FACTORY_CODE = [=[
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
]=]

T["wrapped text edits keep extent accurate through the chunk table"] = function()
    local child = helpers.new_child()
    local result = child.lua_func(function(factory_code)
        local counter = loadstring(factory_code)()
        local columns = 60
        local layout_module = require("scrollbar.layout")
        vim.o.columns = columns
        local lines = {}
        for index = 1, 400 do
            lines[index] = "line " .. index
        end
        -- long lines wrap at 60 columns -> non-uniform
        for index = 60, 400, 40 do
            lines[index] = string.rep("w", 150)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_buf = vim.api.nvim_get_current_buf()
        local source_win = vim.api.nvim_get_current_win()

        local marks = {}
        for index = 0, 399, 7 do
            marks[#marks + 1] = { line = index, type = "Search" }
        end
        local function geometry()
            return layout_module.screen({
                source_win = source_win,
                height = vim.api.nvim_win_get_height(source_win),
                marks = marks,
            })
        end

        -- warm the extent layer, chunk table, and prefix memo
        geometry()
        geometry()
        local extents = {}

        -- sequential edits across the buffer, verifying against the raw
        -- full-buffer measurement every time
        for step = 1, 6 do
            local row = 40 * step
            if step % 2 == 0 then
                vim.api.nvim_buf_set_lines(source_buf, row, row, false, { "inserted " .. step })
            else
                vim.api.nvim_buf_set_text(source_buf, row, 0, row, 4, { string.rep("x", 90) })
            end
            local computed = geometry().total_extent
            local reference = vim.api.nvim_win_text_height(source_win, {}).all
            extents[#extents + 1] = computed == reference
        end
        counter.restore()
        return { extents = extents }
    end, COUNTER_FACTORY_CODE)

    expect.equality(#result.extents, 6)
    for _, accurate in ipairs(result.extents) do
        expect.equality(accurate, true)
    end
end

T["mark walks after edits stay bounded instead of rescanning from row zero"] = function()
    local child = helpers.new_child()
    local result = child.lua_func(function(factory_code)
        local counter = loadstring(factory_code)()
        local columns = 60
        vim.o.columns = columns
        local layout_module = require("scrollbar.layout")
        local lines = {}
        local line_count = 5000
        for index = 1, line_count do
            lines[index] = "line " .. index
        end
        for index = 80, line_count, 40 do
            lines[index] = string.rep("w", 150)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_buf = vim.api.nvim_get_current_buf()
        local source_win = vim.api.nvim_get_current_win()

        local marks = {}
        for index = 0, line_count - 1, 2 do
            marks[#marks + 1] = { line = index, type = "Search" }
        end
        local function geometry()
            return layout_module.screen({
                source_win = source_win,
                height = 20,
                marks = marks,
            })
        end

        -- Warm the prefix memo with a full walk.
        geometry()
        geometry()
        local before_edit = counter.count()
        -- One edit near the end: only the affected chunk's memo entries are
        -- rebuilt (~500 marks); a full rewalk would remeasure every mark
        -- (2500+ calls), and the historical regression rescanned from row
        -- zero per mark (seconds).
        vim.api.nvim_buf_set_text(source_buf, 4500, 0, 4500, 4, { string.rep("q", 200) })
        local started = vim.uv.hrtime()
        geometry()
        local elapsed_ms = (vim.uv.hrtime() - started) / 1e6
        local edit_calls = counter.delta(before_edit)
        counter.restore()
        return { edit_calls = edit_calls, mark_count = #marks, elapsed_ms = elapsed_ms }
    end, COUNTER_FACTORY_CODE)

    expect.equality(result.edit_calls > 0, true)
    expect.equality(result.edit_calls <= 1000, true)
    expect.equality(result.elapsed_ms < 200, true)
end

return T
