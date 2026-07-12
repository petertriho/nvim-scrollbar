local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

T["root setup preserves independent floats for two views of one buffer"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_buf = vim.api.nvim_get_current_buf()
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.api.nvim_win_call(first, function()
            vim.api.nvim_win_set_cursor(first, { 1, 0 })
            vim.cmd("normal! zt")
        end)
        vim.api.nvim_win_call(second, function()
            vim.api.nvim_win_set_cursor(second, { 180, 0 })
            vim.cmd("normal! zt")
        end)

        require("scrollbar").setup({
            set_highlights = false,
            render = { interval_ms = 1000, geometry = "line" },
            mouse = { enabled = false },
            handle = { text = "H", hide_if_all_visible = false },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                gitsigns = false,
                ale = false,
                coc = false,
            },
            excluded_buftypes = {},
            excluded_filetypes = {},
        })
        require("scrollbar.scheduler").flush()

        local renderer = require("scrollbar.renderer")
        local first_state = assert(renderer.get_state(first))
        local second_state = assert(renderer.get_state(second))
        local renderer_namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
        return {
            distinct_floats = first_state.float_win ~= second_state.float_win,
            distinct_buffers = first_state.float_buf ~= second_state.float_buf,
            distinct_handles = first_state.handle.first_row ~= second_state.handle.first_row,
            source_extmarks = vim.api.nvim_buf_get_extmarks(source_buf, renderer_namespace, 0, -1, {}),
        }
    end)

    expect.equality(result, {
        distinct_floats = true,
        distinct_buffers = true,
        distinct_handles = true,
        source_extmarks = {},
    })
end

T["cursor marks stay local to each view of one buffer"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_cursor(first, { 1, 0 })
        vim.api.nvim_win_set_cursor(second, { 180, 0 })

        require("scrollbar").setup({
            set_highlights = false,
            render = { interval_ms = 0, geometry = "line" },
            float = { width = 2 },
            mouse = { enabled = false },
            handle = { text = "H", column = 2, width = 1, hide_if_all_visible = false },
            providers = {
                cursor = true,
                diagnostic = false,
                search = false,
                gitsigns = false,
                ale = false,
                coc = false,
            },
            excluded_buftypes = {},
            excluded_filetypes = {},
        })
        require("scrollbar.scheduler").flush()

        local function cursor_lines(state)
            local found = {}
            for _, row in ipairs(state.hitmap) do
                for _, cell in ipairs(row) do
                    if cell.provider == "cursor" then
                        found[cell.line] = true
                    end
                end
            end
            local result_lines = {}
            for line in pairs(found) do
                table.insert(result_lines, line)
            end
            table.sort(result_lines)
            return result_lines
        end

        local renderer = require("scrollbar.renderer")
        return {
            first = cursor_lines(assert(renderer.get_state(first))),
            second = cursor_lines(assert(renderer.get_state(second))),
        }
    end)

    expect.equality(result, {
        first = { 0 },
        second = { 179 },
    })
end

return T
