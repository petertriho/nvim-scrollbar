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

T["window-local mark revisions rebuild only the affected static layer"] = function()
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

        local active_config = require("scrollbar.config").set({
            set_highlights = false,
            render = { interval_ms = 0, geometry = "line" },
            float = { width = 2 },
            mouse = { enabled = false },
            handle = { text = "H", column = 2, width = 1, hide_if_all_visible = false },
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
        local store = require("scrollbar.store")
        assert(store.set_window("test", first, { { line = 10, type = "Misc" } }))
        assert(store.set_window("test", second, { { line = 180, type = "Misc" } }))

        local layout = require("scrollbar.layout")
        local original_mark_layer = layout.mark_layer
        local builds = 0
        rawset(layout, "mark_layer", function(input)
            builds = builds + 1
            return original_mark_layer(input)
        end)

        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(first)
        renderer.render(second)
        local initial_builds = builds

        assert(store.set_window("test", first, { { line = 20, type = "Misc" } }))
        renderer.render(first)
        renderer.render(second)
        local after_first_change = builds

        renderer.render(first)
        renderer.render(second)
        rawset(layout, "mark_layer", original_mark_layer)
        return {
            config = active_config.render.geometry,
            initial_builds = initial_builds,
            after_first_change = after_first_change,
            final_builds = builds,
        }
    end)

    expect.equality(result, {
        config = "line",
        initial_builds = 2,
        after_first_change = 3,
        final_builds = 3,
    })
end

T["real named marks stay with their source buffer and resolve width per window height"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        local function fill(bufnr)
            local lines = {}
            for index = 1, 200 do
                lines[index] = "line " .. index
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        end

        local first_buf = vim.api.nvim_get_current_buf()
        fill(first_buf)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local second_buf = vim.api.nvim_create_buf(true, false)
        fill(second_buf)
        vim.api.nvim_win_set_buf(second, second_buf)
        vim.api.nvim_win_set_height(second, 4)

        vim.api.nvim_buf_set_mark(first_buf, "a", 1, 0, {})
        vim.api.nvim_buf_set_mark(first_buf, "A", 11, 0, {})
        vim.api.nvim_buf_set_mark(first_buf, "c", 21, 0, {})
        vim.api.nvim_buf_set_mark(second_buf, "b", 1, 0, {})
        vim.api.nvim_buf_set_mark(second_buf, "B", 11, 0, {})
        vim.api.nvim_buf_set_mark(second_buf, "d", 21, 0, {})

        require("scrollbar").setup({
            set_highlights = false,
            render = { interval_ms = 0, geometry = "line" },
            float = {
                width = 1,
                hide_on_cursor = false,
                placement = { relative = "window", anchor = "NW", row = 0, col = 0 },
            },
            mouse = { enabled = false },
            handle = { text = "H", column = 1, width = 1, hide_if_all_visible = false },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                marks = { max_width = 6 },
                gitsigns = false,
                ale = false,
                coc = false,
            },
            excluded_buftypes = {},
            excluded_filetypes = {},
        })
        require("scrollbar.scheduler").flush()

        local function rendered_marks(state)
            local marks = {}
            for row, cells in ipairs(state.hitmap) do
                for column, cell in ipairs(cells) do
                    if cell.provider == "marks" and cell.start_col == column then
                        marks[vim.fn.strcharpart(state.rows[row], column - 1, 1)] = cell.line
                    end
                end
            end
            return marks
        end

        local renderer = require("scrollbar.renderer")
        local first_state = assert(renderer.get_state(first))
        local second_state = assert(renderer.get_state(second))
        return {
            first = {
                source_buf = first_state.source_buf,
                height = first_state.height,
                width = first_state.width,
                marks = rendered_marks(first_state),
            },
            second = {
                source_buf = second_state.source_buf,
                height = second_state.height,
                width = second_state.width,
                marks = rendered_marks(second_state),
            },
            first_buf = first_buf,
            second_buf = second_buf,
        }
    end)

    expect.equality(result.first.source_buf, result.first_buf)
    expect.equality(result.second.source_buf, result.second_buf)
    expect.equality(result.first.marks, { a = 0, A = 10, c = 20 })
    expect.equality(result.second.marks, { b = 0, B = 10, d = 20 })
    expect.equality(result.first.height > result.second.height, true)
    expect.equality({ result.first.width, result.second.width }, { 2, 3 })
end

return T
