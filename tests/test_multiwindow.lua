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
            thumb = { text = "H", hide_if_all_visible = false },
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

T["same-buffer vertical splits avoid and update their own live gutters"] = function()
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
        vim.cmd("vsplit")
        local second = vim.api.nvim_get_current_win()

        local function set_gutter(winid, signcolumn)
            vim.api.nvim_set_option_value("number", false, { win = winid })
            vim.api.nvim_set_option_value("relativenumber", false, { win = winid })
            vim.api.nvim_set_option_value("numberwidth", 4, { win = winid })
            vim.api.nvim_set_option_value("foldcolumn", "0", { win = winid })
            vim.api.nvim_set_option_value("signcolumn", signcolumn, { win = winid })
            vim.api.nvim_set_option_value("statuscolumn", "", { win = winid })
        end
        set_gutter(first, "yes:1")
        set_gutter(second, "yes:2")
        local first_base_textoff = vim.fn.getwininfo(first)[1].textoff
        local second_base_textoff = vim.fn.getwininfo(second)[1].textoff

        require("scrollbar.config").set({
            set_highlights = false,
            render = { interval_ms = 0, geometry = "line" },
            float = {
                hide_on_cursor = false,
                placement = { relative = "window", anchor = "NW", row = 0, col = 0, gutter = "avoid" },
            },
            mouse = { enabled = false },
            thumb = { text = "H", hide_if_all_visible = false },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                marks = false,
                gitsigns = false,
                mini_diff = false,
                signify = false,
                vgit = false,
                ale = false,
                coc = false,
            },
            excluded_buftypes = {},
            excluded_filetypes = {},
        })
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local first_state = assert(renderer.render(first))
        local second_state = assert(renderer.render(second))
        local first_textoff = vim.fn.getwininfo(first)[1].textoff
        local second_textoff = vim.fn.getwininfo(second)[1].textoff
        local first_before = vim.api.nvim_win_get_config(first_state.float_win)
        local second_before = vim.api.nvim_win_get_config(second_state.float_win)

        vim.api.nvim_set_option_value("signcolumn", "yes:3", { win = first })
        local first_moved_base_textoff = vim.fn.getwininfo(first)[1].textoff - first_state.width
        local first_moved = assert(renderer.render(first))
        local second_unchanged = assert(renderer.render(second))
        local first_moved_textoff = vim.fn.getwininfo(first)[1].textoff
        local first_after = vim.api.nvim_win_get_config(first_moved.float_win)
        local second_after = vim.api.nvim_win_get_config(second_unchanged.float_win)

        return {
            source_buf = source_buf,
            buffers = {
                vim.api.nvim_win_get_buf(first),
                vim.api.nvim_win_get_buf(second),
            },
            base_textoff = { first_base_textoff, second_base_textoff, first_moved_base_textoff },
            textoff = { first_textoff, second_textoff, first_moved_textoff },
            widths = { first_state.width, second_state.width, first_moved.width, second_unchanged.width },
            columns = { first_before.col, second_before.col, first_after.col, second_after.col },
            distinct_resources = first_state.float_win ~= second_state.float_win
                and first_state.float_buf ~= second_state.float_buf,
            same_resources = first_moved.float_win == first_state.float_win
                and first_moved.float_buf == first_state.float_buf
                and second_unchanged.float_win == second_state.float_win
                and second_unchanged.float_buf == second_state.float_buf,
            ownership = {
                assert(renderer.get_state_by_float(first_state.float_win)).source_win,
                assert(renderer.get_state_by_float(second_state.float_win)).source_win,
            },
            windows = { first, second },
        }
    end)

    expect.equality(result.buffers, { result.source_buf, result.source_buf })
    expect.equality(result.base_textoff[1] > 0, true)
    expect.equality(result.base_textoff[2] > result.base_textoff[1], true)
    expect.equality(result.base_textoff[3] > result.base_textoff[2], true)
    expect.equality(result.textoff, {
        result.base_textoff[1] + result.widths[1],
        result.base_textoff[2] + result.widths[2],
        result.base_textoff[3] + result.widths[3],
    })
    expect.equality(result.columns, {
        result.base_textoff[1],
        result.base_textoff[2],
        result.base_textoff[3],
        result.base_textoff[2],
    })
    expect.equality(result.distinct_resources, true)
    expect.equality(result.same_resources, true)
    expect.equality(result.ownership, result.windows)
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
            layout = { direction = "ltr", columns = { { "marks" }, { "thumb" } } },
            mouse = { enabled = false },
            thumb = { text = "H", hide_if_all_visible = false },
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
            layout = { direction = "ltr", columns = { { "marks" }, { "thumb" } } },
            mouse = { enabled = false },
            thumb = { text = "H", hide_if_all_visible = false },
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
                hide_on_cursor = false,
                placement = { relative = "window", anchor = "NW", row = 0, col = 0 },
            },
            layout = {
                columns = {
                    { "track", "thumb", { kind = "marks", types = { "Mark" }, max_width = 6 } },
                },
            },
            mouse = { enabled = false },
            thumb = { text = "H", hide_if_all_visible = false },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                marks = true,
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

T["simultaneous windows render selected profile layouts geometry and filtering"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        local function fill(bufnr)
            local lines = {}
            for index = 1, 100 do
                lines[index] = "line " .. index
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        end

        local first_buf = vim.api.nvim_get_current_buf()
        fill(first_buf)
        vim.bo[first_buf].filetype = "lua"
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local second_buf = vim.api.nvim_create_buf(true, false)
        fill(second_buf)
        vim.bo[second_buf].filetype = "markdown"
        vim.api.nvim_win_set_buf(second, second_buf)
        vim.api.nvim_win_set_height(second, 4)
        vim.api.nvim_set_current_win(first)

        local store = require("scrollbar.store")
        store.set("test", first_buf, {
            { line = 10, type = "Error" },
            { line = 20, type = "Search" },
        })
        store.set("marks", second_buf, {
            { line = 40, type = "Error" },
            { line = 0, type = "Mark", text = "a" },
            { line = 10, type = "Mark", text = "b" },
            { line = 20, type = "Mark", text = "c" },
        })

        require("scrollbar").setup({
            set_highlights = false,
            render = { interval_ms = 0 },
            float = { hide_on_cursor = false },
            mouse = { enabled = false },
            thumb = { text = "H", hide_if_all_visible = false },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                marks = false,
                gitsigns = false,
                mini_diff = false,
                signify = false,
                vgit = false,
                ale = false,
                coc = false,
            },
            excluded_buftypes = {},
            excluded_filetypes = {},
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    preset = "review",
                    config = {
                        render = { geometry = "screen" },
                        float = { placement = { anchor = "NW" } },
                    },
                },
                {
                    match = { filetypes = { "markdown" } },
                    preset = "navigate",
                    config = {
                        render = { geometry = "line" },
                        float = { placement = { anchor = "SE" } },
                    },
                },
            },
        })
        require("scrollbar.scheduler").flush()

        local function rendered_types(state)
            local types = {}
            for _, row in ipairs(state.hitmap) do
                for _, cell in ipairs(row) do
                    if cell.type ~= nil then
                        types[cell.type] = true
                    end
                end
            end
            return types
        end

        local renderer = require("scrollbar.renderer")
        local first_state = assert(renderer.get_state(first))
        local second_state = assert(renderer.get_state(second))
        return {
            first = {
                variant_id = first_state.variant_id,
                width = first_state.width,
                mode = first_state.geometry.mode,
                anchor = first_state.float_config.anchor,
                types = rendered_types(first_state),
            },
            second = {
                variant_id = second_state.variant_id,
                width = second_state.width,
                mode = second_state.geometry.mode,
                anchor = second_state.float_config.anchor,
                types = rendered_types(second_state),
            },
        }
    end)

    expect.equality(result.first, {
        variant_id = 1,
        width = 3,
        mode = "screen",
        anchor = "NW",
        types = { Error = true },
    })
    expect.equality(result.second.variant_id, 2)
    expect.equality(result.second.mode, "line")
    expect.equality(result.second.anchor, "SE")
    expect.equality(result.second.width > 2, true)
    expect.equality(result.second.types, { Mark = true })
end

T["two views of one buffer select independently and profile switches replace rendered state"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local wide = false

        require("scrollbar").setup({
            set_highlights = false,
            render = { interval_ms = 0 },
            float = { hide_on_cursor = false },
            mouse = { enabled = false },
            thumb = { text = "H", hide_if_all_visible = false },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                marks = false,
                gitsigns = false,
                mini_diff = false,
                signify = false,
                vgit = false,
                ale = false,
                coc = false,
            },
            excluded_buftypes = {},
            excluded_filetypes = {},
            profiles = {
                {
                    match = {
                        when = function(context)
                            return context.winid == first and wide
                        end,
                    },
                    preset = "review",
                    config = { float = { placement = { anchor = "NW" } } },
                },
                {
                    match = {
                        when = function(context)
                            return context.winid == first
                        end,
                    },
                    preset = "minimal",
                },
                {
                    match = {
                        when = function(context)
                            return context.winid == second
                        end,
                    },
                    preset = "gvim",
                },
            },
        })
        local renderer = require("scrollbar.renderer")
        renderer.render(first)
        renderer.render(second)
        local first_before = assert(renderer.get_state(first))
        local second_state = assert(renderer.get_state(second))
        local float_win = first_before.float_win
        local before = {
            first_id = first_before.variant_id,
            first_width = first_before.width,
            second_id = second_state.variant_id,
            second_width = second_state.width,
        }

        wide = true
        renderer.render(first)
        local first_after = assert(renderer.get_state(first))
        return {
            before = before,
            after = {
                variant_id = first_after.variant_id,
                width = first_after.width,
                anchor = first_after.float_config.anchor,
                same_float = first_after.float_win == float_win,
                row_width = vim.fn.strdisplaywidth(first_after.rows[1]),
                hit_width = #first_after.hitmap[1],
            },
        }
    end)

    expect.equality(result, {
        before = { first_id = 2, first_width = 1, second_id = 3, second_width = 2 },
        after = {
            variant_id = 1,
            width = 3,
            anchor = "NW",
            same_float = true,
            row_width = 3,
            hit_width = 3,
        },
    })
end

T["editor-relative profiles render only for the active source beside window-relative profiles"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        local first = vim.api.nvim_get_current_win()
        vim.bo.filetype = "lua"
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local second_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_win_set_buf(second, second_buf)
        vim.bo[second_buf].filetype = "text"
        vim.api.nvim_set_current_win(first)

        require("scrollbar").setup({
            set_highlights = false,
            render = { interval_ms = 0 },
            float = { hide_on_cursor = false },
            mouse = { enabled = false },
            thumb = { hide_if_all_visible = false },
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                marks = false,
                gitsigns = false,
                mini_diff = false,
                signify = false,
                vgit = false,
                ale = false,
                coc = false,
            },
            excluded_buftypes = {},
            excluded_filetypes = {},
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    config = { float = { placement = { relative = "editor" } } },
                },
            },
        })
        local renderer = require("scrollbar.renderer")
        renderer.render(first)
        renderer.render(second)
        local active_first = {
            first = renderer.get_state(first) ~= nil,
            second = renderer.get_state(second) ~= nil,
        }

        vim.api.nvim_set_current_win(second)
        renderer.render(first)
        renderer.render(second)
        return {
            active_first = active_first,
            active_second = {
                first = renderer.get_state(first) ~= nil,
                second = renderer.get_state(second) ~= nil,
            },
        }
    end)

    expect.equality(result, {
        active_first = { first = true, second = true },
        active_second = { first = false, second = true },
    })
end

return T
