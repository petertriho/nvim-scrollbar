local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

local function renderer_config(overrides)
    return vim.tbl_deep_extend("force", {
        show = true,
        set_highlights = false,
        render = { interval_ms = 0, geometry = "line" },
        float = { width = 2, placement = { relative = "window", anchor = "NE", row = 0, col = 0 } },
        mouse = { enabled = false },
        handle = { text = "H", column = 2, width = 1, hide_if_all_visible = false },
        marks = { Misc = { text = "M", column = 1 } },
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
    }, overrides or {})
end

T["keeps same-buffer source windows independent and writes only float buffers"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.api.nvim_win_call(first, function()
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
            vim.cmd("normal! zt")
        end)
        vim.api.nvim_win_call(second, function()
            vim.api.nvim_win_set_cursor(0, { 180, 0 })
            vim.cmd("normal! zt")
        end)

        require("scrollbar.config").set(config)
        local store = require("scrollbar.store")
        assert(store.set("test", vim.api.nvim_win_get_buf(first), { { line = 199, type = "Misc" } }))
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(first)
        renderer.render(second)

        local first_state = assert(renderer.get_state(first))
        local second_state = assert(renderer.get_state(second))
        local first_again = assert(renderer.render(first))
        local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
        local float_extmarks =
            vim.api.nvim_buf_get_extmarks(first_state.float_buf, namespace, 0, -1, { details = true })
        local source_extmarks =
            vim.api.nvim_buf_get_extmarks(first_state.source_buf, namespace, 0, -1, { details = true })
        return {
            first = first_state,
            second = second_state,
            first_lines = vim.api.nvim_buf_get_lines(first_state.float_buf, 0, -1, false),
            float_extmarks = float_extmarks,
            source_extmarks = source_extmarks,
            float_filetype = vim.bo[first_state.float_buf].filetype,
            float_buftype = vim.bo[first_state.float_buf].buftype,
            float_modifiable = vim.bo[first_state.float_buf].modifiable,
            lookup = assert(renderer.get_state_by_float(first_state.float_win)).source_win,
            reused_float = first_again.float_win,
            reused_buffer = first_again.float_buf,
        }
    end, renderer_config())

    expect.no_equality(result.first.float_win, result.second.float_win)
    expect.no_equality(result.first.float_buf, result.second.float_buf)
    expect.equality(result.reused_float, result.first.float_win)
    expect.equality(result.reused_buffer, result.first.float_buf)
    expect.equality(result.first.handle.first_row, 0)
    expect.equality(result.second.handle.first_row > result.first.handle.first_row, true)
    expect.equality(result.first_lines[#result.first_lines]:sub(1, 1), "M")
    expect.equality(#result.float_extmarks > 0, true)
    expect.equality(result.float_extmarks[1][4].virt_text, nil)
    expect.equality(result.source_extmarks, {})
    expect.equality(result.float_filetype, "scrollbar")
    expect.equality(result.float_buftype, "nofile")
    expect.equality(result.float_modifiable, false)
    expect.equality(result.lookup, result.first.source_win)
end

T["enforces visibility and editor-relative single ownership"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.renderer")
        local scrollbar_config = require("scrollbar.config")

        scrollbar_config.set(base_config)
        renderer.setup()
        renderer.render(first)
        renderer.render(second)
        local all_count = #renderer.source_windows()
        local all_owned = renderer.get_state(first) ~= nil and renderer.get_state(second) ~= nil

        local active_config = vim.deepcopy(base_config)
        active_config.visibility = "active"
        scrollbar_config.set(active_config)
        renderer.setup()
        renderer.render(first)
        renderer.render(second)
        local active_owned = renderer.get_state(first) == nil and renderer.get_state(second) ~= nil

        local editor_config = vim.deepcopy(base_config)
        editor_config.visibility = "all"
        editor_config.float.placement.relative = "editor"
        scrollbar_config.set(editor_config)
        renderer.setup()
        renderer.render(first)
        renderer.render(second)
        local editor_second_float = assert(renderer.get_state(second)).float_win
        vim.api.nvim_set_current_win(first)
        renderer.render(first)
        local editor_sources = renderer.source_windows()
        local editor_first_owned = renderer.get_state(first) ~= nil
        local editor_second_owned = renderer.get_state(second) ~= nil
        local editor_second_float_valid = vim.api.nvim_win_is_valid(editor_second_float)
        local user_float_buf = vim.api.nvim_create_buf(false, true)
        local user_float = vim.api.nvim_open_win(user_float_buf, true, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 1,
            height = 1,
            style = "minimal",
        })
        local editor_sources_from_user_float = renderer.source_windows()
        vim.api.nvim_win_close(user_float, true)
        vim.api.nvim_set_current_win(first)

        local initially_hidden = vim.deepcopy(base_config)
        initially_hidden.show = false
        initially_hidden.visibility = "all"
        initially_hidden.float.placement.relative = "window"
        scrollbar_config.set(initially_hidden)
        renderer.setup()
        renderer.render(first)
        local setup_hidden = renderer.get_state(first) == nil
        renderer.show()
        local explicit_show = renderer.get_state(first) ~= nil and renderer.get_state(second) ~= nil

        return {
            all_count = all_count,
            all_owned = all_owned,
            active_owned = active_owned,
            editor_first_owned = editor_first_owned,
            editor_second_owned = editor_second_owned,
            editor_second_float_valid = editor_second_float_valid,
            editor_sources = editor_sources,
            editor_sources_from_user_float = editor_sources_from_user_float,
            setup_hidden = setup_hidden,
            explicit_show = explicit_show,
        }
    end, renderer_config())

    expect.equality(result.all_count, 2)
    expect.equality(result.all_owned, true)
    expect.equality(result.active_owned, true)
    expect.equality(result.editor_first_owned, true)
    expect.equality(result.editor_second_owned, false)
    expect.equality(result.editor_second_float_valid, false)
    expect.equality(#result.editor_sources, 1)
    expect.equality(result.editor_sources_from_user_float, {})
    expect.equality(result.setup_hidden, true)
    expect.equality(result.explicit_show, true)
end

T["resolves every anchor and restores protected float configuration"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 80 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local source_width = vim.api.nvim_win_get_width(source_win)
        local source_height = vim.api.nvim_win_get_height(source_win)
        local renderer = require("scrollbar.renderer")
        local scrollbar_config = require("scrollbar.config")
        local anchors = {}

        for _, anchor in ipairs({ "NW", "NE", "SW", "SE" }) do
            local anchor_config = vim.deepcopy(base_config)
            anchor_config.float.placement = {
                relative = "window",
                anchor = anchor,
                row = 2,
                col = -3,
            }
            scrollbar_config.set(anchor_config)
            renderer.setup()
            local state = assert(renderer.render(source_win))
            anchors[anchor] = vim.api.nvim_win_get_config(state.float_win)
        end

        local editor_config = vim.deepcopy(base_config)
        editor_config.float.placement = {
            relative = "editor",
            anchor = "SE",
            row = -2,
            col = -4,
        }
        scrollbar_config.set(editor_config)
        renderer.setup()
        local state = assert(renderer.render(source_win))
        local editor = vim.api.nvim_win_get_config(state.float_win)

        vim.api.nvim_win_set_config(state.float_win, {
            relative = "editor",
            anchor = "NW",
            row = 7,
            col = 9,
            width = 1,
            height = 1,
            focusable = true,
            mouse = true,
            zindex = 99,
        })
        renderer.render(source_win)
        local protected = vim.api.nvim_win_get_config(state.float_win)

        return {
            anchors = anchors,
            editor = editor,
            protected = protected,
            source_win = source_win,
            source_width = source_width,
            source_height = source_height,
            source_top = vim.fn.win_screenpos(source_win)[1] - 1,
            editor_width = vim.o.columns,
        }
    end, renderer_config())

    expect.equality(result.anchors.NW.row, 2)
    expect.equality(result.anchors.NW.col, -3)
    expect.equality(result.anchors.NE.row, 2)
    expect.equality(result.anchors.NE.col, result.source_width - 3)
    expect.equality(result.anchors.SW.row, result.source_height + 2)
    expect.equality(result.anchors.SW.col, -3)
    expect.equality(result.anchors.SE.row, result.source_height + 2)
    expect.equality(result.anchors.SE.col, result.source_width - 3)
    expect.equality(result.anchors.NE.win, result.source_win)
    expect.equality(result.editor.relative, "editor")
    expect.equality(result.editor.row, result.source_top + result.source_height - 2)
    expect.equality(result.editor.col, result.editor_width - 4)
    expect.equality(result.protected.anchor, "SE")
    expect.equality(result.protected.row, result.source_top + result.source_height - 2)
    expect.equality(result.protected.col, result.editor_width - 4)
    expect.equality(result.protected.width, 2)
    expect.equality(result.protected.focusable, false)
    expect.equality(result.protected.mouse, false)
    expect.equality(result.protected.zindex, 50)
end

T["aligns editor-relative tracks with active split text rows"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        vim.o.showtabline = 2
        vim.o.laststatus = 2
        vim.o.cmdheight = 0
        vim.o.tabline = "TABLINE"
        vim.o.statusline = "STATUSLINE"

        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local scrollbar_config = require("scrollbar.config")
        local renderer = require("scrollbar.renderer")
        local cases = {}
        for _, split_command in ipairs({ "split", "vsplit" }) do
            vim.cmd("only")
            vim.cmd(split_command)
            local source_win = vim.api.nvim_get_current_win()
            vim.api.nvim_set_option_value("winbar", "WINBAR", { win = source_win })
            local raw_height = vim.api.nvim_win_get_height(source_win)
            local source_position = vim.fn.win_screenpos(source_win)
            local text_top = source_position[1]
            local text_bottom = text_top + raw_height - 1

            local placements = {}
            for _, placement in ipairs({
                { anchor = "NE", row = 2 },
                { anchor = "SE", row = -2 },
            }) do
                local active = vim.deepcopy(base_config)
                active.float.placement = {
                    relative = "editor",
                    anchor = placement.anchor,
                    row = placement.row,
                    col = -3,
                }
                scrollbar_config.set(active)
                renderer.setup()
                local state = assert(renderer.render(source_win))
                placements[placement.anchor] = {
                    config = vim.api.nvim_win_get_config(state.float_win),
                    height = state.height,
                }
            end

            cases[split_command] = {
                source_win = source_win,
                text_top = text_top,
                text_bottom = text_bottom,
                raw_height = raw_height,
                placements = placements,
                owned_sources = renderer.source_windows(),
            }
        end
        return { cases = cases, columns = vim.o.columns }
    end, renderer_config())

    for _, split_command in ipairs({ "split", "vsplit" }) do
        local case = result.cases[split_command]
        expect.equality(case.placements.NE.config.relative, "editor")
        expect.equality(case.placements.NE.config.row, case.text_top + 2)
        expect.equality(case.placements.SE.config.row, case.text_bottom - 2)
        expect.equality(case.placements.NE.config.col, result.columns - 3)
        expect.equality(case.placements.SE.config.col, result.columns - 3)
        expect.equality(case.placements.NE.height, case.raw_height - 1)
        expect.equality(case.placements.SE.height, case.raw_height - 1)
        expect.equality(case.placements.NE.config.row >= case.text_top, true)
        expect.equality(case.placements.SE.config.row <= case.text_bottom, true)
        expect.equality(case.owned_sources, { case.source_win })
    end
end

T["keeps window-relative tracks inside source text rows"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        vim.o.showtabline = 2
        vim.o.laststatus = 2
        vim.o.cmdheight = 0
        vim.o.tabline = "TABLINE"
        vim.o.statusline = "STATUSLINE"

        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local scrollbar_config = require("scrollbar.config")
        local renderer = require("scrollbar.renderer")

        local function render(anchor, winbar)
            vim.api.nvim_set_option_value("winbar", winbar, { win = source_win })
            local active = vim.deepcopy(base_config)
            active.float.placement.anchor = anchor
            scrollbar_config.set(active)
            renderer.setup()
            local raw_height = vim.api.nvim_win_get_height(source_win)
            local state = assert(renderer.render(source_win))
            vim.cmd("redraw")
            local source_position = vim.fn.win_screenpos(source_win)
            local float_configuration = vim.api.nvim_win_get_config(state.float_win)
            return {
                raw_height = raw_height,
                state = state,
                float_config = float_configuration,
                float_bottom = anchor:sub(1, 1) == "S" and source_position[1] + float_configuration.row - 1
                    or source_position[1] + float_configuration.row + state.height - 1,
                statusline_row = source_position[1] + raw_height,
            }
        end

        local north = render("NE", "WINBAR")
        local south = render("SE", "WINBAR")
        local control = render("NE", "")

        vim.api.nvim_set_option_value("winbar", "WINBAR", { win = source_win })
        scrollbar_config.set(base_config)
        renderer.setup()
        local get_height = vim.api.nvim_win_get_height
        vim.api.nvim_win_get_height = function(winid)
            if winid == source_win then
                return 1
            end
            return get_height(winid)
        end
        renderer.render(source_win)
        vim.api.nvim_win_get_height = get_height

        return {
            north = north,
            south = south,
            control = control,
            tiny_raw_height = 1,
            tiny_has_state = renderer.get_state(source_win) ~= nil,
        }
    end, renderer_config())

    expect.equality(result.north.state.height, result.north.raw_height - 1)
    expect.equality(#result.north.state.rows, result.north.state.height)
    expect.equality(#result.north.state.hitmap, result.north.state.height)
    expect.equality(result.north.float_config.row, 0)
    expect.equality(result.north.float_config.height, result.north.state.height)
    expect.equality(result.north.float_bottom < result.north.statusline_row, true)
    expect.equality(result.south.state.height, result.south.raw_height - 1)
    expect.equality(result.south.float_config.row, result.south.state.height)
    expect.equality(result.south.float_bottom < result.south.statusline_row, true)
    expect.equality(result.control.state.height, result.control.raw_height)
    expect.equality(result.tiny_raw_height, 1)
    expect.equality(result.tiny_has_state, false)
end

T["applies exclusions, limits, all-visible rules, and owned-window filtering"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local source_win = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.renderer")
        local scrollbar_config = require("scrollbar.config")

        local excluded_filetype = vim.deepcopy(base_config)
        excluded_filetype.excluded_filetypes = { "renderer-test" }
        vim.bo.filetype = "renderer-test"
        scrollbar_config.set(excluded_filetype)
        renderer.setup()
        renderer.render(source_win)
        local filetype_hidden = renderer.get_state(source_win) == nil
        vim.bo.filetype = ""

        local excluded_buftype = vim.deepcopy(base_config)
        excluded_buftype.excluded_buftypes = { "nofile" }
        vim.bo.buftype = "nofile"
        scrollbar_config.set(excluded_buftype)
        renderer.setup()
        renderer.render(source_win)
        local buftype_hidden = renderer.get_state(source_win) == nil
        vim.bo.buftype = ""

        local limited = vim.deepcopy(base_config)
        limited.max_lines = 2
        scrollbar_config.set(limited)
        renderer.setup()
        renderer.render(source_win)
        local max_lines_hidden = renderer.get_state(source_win) == nil

        local all_visible = vim.deepcopy(base_config)
        all_visible.hide_if_all_visible = true
        scrollbar_config.set(all_visible)
        renderer.setup()
        renderer.render(source_win)
        local all_visible_hidden = renderer.get_state(source_win) == nil

        local handle_hidden = vim.deepcopy(base_config)
        handle_hidden.hide_if_all_visible = false
        handle_hidden.handle.hide_if_all_visible = true
        scrollbar_config.set(handle_hidden)
        renderer.setup()
        local state = assert(renderer.render(source_win))
        local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
        local extmarks = vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true })
        local has_handle_highlight = false
        for _, extmark in ipairs(extmarks) do
            if extmark[4].hl_group == "ScrollbarHandle" then
                has_handle_highlight = true
            end
        end
        local owned_render = renderer.render(state.float_win)
        local handle_float = state.float_win
        vim.bo.filetype = "renderer-test"
        local changed_exclusion = vim.deepcopy(base_config)
        changed_exclusion.excluded_filetypes = { "renderer-test" }
        scrollbar_config.set(changed_exclusion)
        renderer.render(source_win)

        return {
            filetype_hidden = filetype_hidden,
            buftype_hidden = buftype_hidden,
            max_lines_hidden = max_lines_hidden,
            all_visible_hidden = all_visible_hidden,
            handle = state.handle,
            has_handle_highlight = has_handle_highlight,
            owned_rendered = owned_render ~= nil,
            owned_in_sources = vim.tbl_contains(renderer.source_windows(), state.float_win),
            exclusion_cleanup = renderer.get_state(source_win) == nil and not vim.api.nvim_win_is_valid(handle_float),
        }
    end, renderer_config())

    expect.equality(result.filetype_hidden, true)
    expect.equality(result.buftype_hidden, true)
    expect.equality(result.max_lines_hidden, true)
    expect.equality(result.all_visible_hidden, true)
    expect.equality(result.handle.first_row, -1)
    expect.equality(result.handle.last_row, -1)
    expect.equality(result.has_handle_highlight, false)
    expect.equality(result.owned_rendered, false)
    expect.equality(result.owned_in_sources, false)
    expect.equality(result.exclusion_cleanup, true)
end

T["aligns short-buffer marks without shrinking the track"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four", "five" })
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 10)
        local source_buf = vim.api.nvim_win_get_buf(source_win)
        assert(require("scrollbar.store").set("test", source_buf, {
            { line = 0, type = "Misc" },
            { line = 2, type = "Misc" },
            { line = 4, type = "Misc" },
        }))

        local scrollbar_config = require("scrollbar.config")
        local renderer = require("scrollbar.renderer")
        local cases = {}
        for _, mode in ipairs({ "line", "screen" }) do
            local active = vim.deepcopy(base_config)
            active.render.geometry = mode
            scrollbar_config.set(active)
            renderer.setup()
            local state = assert(renderer.render(source_win))
            cases[mode] = {
                height = state.height,
                float_height = vim.api.nvim_win_get_config(state.float_win).height,
                handle = state.handle,
                mark_lines = {
                    state.hitmap[1][1].line,
                    state.hitmap[3][1].line,
                    state.hitmap[5][1].line,
                },
                trailing_empty = state.hitmap[6][1].line == nil,
            }
        end
        return cases
    end, renderer_config())

    for _, mode in ipairs({ "line", "screen" }) do
        local case = result[mode]
        expect.equality(case.height, 10)
        expect.equality(case.float_height, case.height)
        expect.equality(case.mark_lines, { 0, 2, 4 })
        expect.equality(case.trailing_empty, true)
        expect.equality(case.handle, { first_row = 0, last_row = 9, column = 2, width = 1 })
    end
end

T["updates only dirty rows and fully replaces rows when dimensions change"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 8)

        require("scrollbar.config").set(config)
        local store = require("scrollbar.store")
        local source_buf = vim.api.nvim_win_get_buf(source_win)
        assert(store.set("test", source_buf, { { line = 60, type = "Misc", text = "A" } }))
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local state = assert(renderer.render(source_win))

        local mark_row
        for row, cells in ipairs(state.hitmap) do
            if cells[1].line == 60 then
                mark_row = row - 1
            end
        end

        local events = {}
        vim.api.nvim_buf_attach(state.float_buf, false, {
            on_lines = function(_, _, _, first, last, new_last)
                table.insert(events, { first = first, last = last, new_last = new_last })
            end,
        })

        assert(store.set("test", source_buf, { { line = 60, type = "Misc", text = "B" } }))
        renderer.render(source_win)
        local dirty_events = vim.deepcopy(events)

        events = {}
        local old_height = state.height
        vim.api.nvim_win_set_height(source_win, old_height - 2)
        renderer.render(source_win)
        local dimension_events = vim.deepcopy(events)

        return {
            mark_row = mark_row,
            dirty_events = dirty_events,
            dimension_events = dimension_events,
            old_height = old_height,
            new_height = assert(renderer.get_state(source_win)).height,
        }
    end, renderer_config())

    expect.equality(result.dirty_events, {
        { first = result.mark_row, last = result.mark_row + 1, new_last = result.mark_row + 1 },
    })
    expect.equality(#result.dimension_events, 1)
    expect.equality(result.dimension_events[1].first, 0)
    expect.equality(result.dimension_events[1].last, result.old_height)
    expect.equality(result.dimension_events[1].new_last, result.new_height)
end

T["cleans resources for lifecycle events, hide, toggle, and setup reset"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        require("scrollbar.config").set(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local close_state = assert(renderer.render(first))
        local closed_float = close_state.float_win
        local closed_buffer = close_state.float_buf
        vim.api.nvim_win_close(first, true)
        local window_cleanup = renderer.get_state(first) == nil
            and not vim.api.nvim_win_is_valid(closed_float)
            and not vim.api.nvim_buf_is_valid(closed_buffer)

        local reset_state = assert(renderer.render(second))
        local reset_float = reset_state.float_win
        renderer.setup()
        local setup_cleanup = renderer.get_state(second) == nil and not vim.api.nvim_win_is_valid(reset_float)

        local hidden_state = assert(renderer.render(second))
        local hidden_float = hidden_state.float_win
        renderer.hide()
        local hide_cleanup = renderer.get_state(second) == nil and not vim.api.nvim_win_is_valid(hidden_float)
        renderer.show()
        local show_recreated = renderer.get_state(second) ~= nil
        renderer.toggle()
        local toggle_hidden = renderer.get_state(second) == nil and not renderer.is_visible()
        renderer.toggle()
        local toggle_shown = renderer.get_state(second) ~= nil and renderer.is_visible()

        local source_buffer = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(source_buffer, 0, -1, false, { "source", "buffer" })
        vim.api.nvim_win_set_buf(second, source_buffer)
        local buffer_state = assert(renderer.render(second))
        local buffer_float = buffer_state.float_win
        vim.api.nvim_win_set_buf(second, vim.api.nvim_create_buf(true, false))
        vim.api.nvim_buf_delete(source_buffer, { force = true })
        local buffer_cleanup = renderer.get_state(second) == nil and not vim.api.nvim_win_is_valid(buffer_float)

        vim.cmd("tabnew")
        local tab_source = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local tab_state = assert(renderer.render(tab_source))
        local tab_float = tab_state.float_win
        vim.cmd("tabclose")
        local tab_cleanup = renderer.get_state(tab_source) == nil and not vim.api.nvim_win_is_valid(tab_float)

        return {
            window_cleanup = window_cleanup,
            setup_cleanup = setup_cleanup,
            hide_cleanup = hide_cleanup,
            show_recreated = show_recreated,
            toggle_hidden = toggle_hidden,
            toggle_shown = toggle_shown,
            buffer_cleanup = buffer_cleanup,
            tab_cleanup = tab_cleanup,
        }
    end, renderer_config())

    expect.equality(result, {
        window_cleanup = true,
        setup_cleanup = true,
        hide_cleanup = true,
        show_recreated = true,
        toggle_hidden = true,
        toggle_shown = true,
        buffer_cleanup = true,
        tab_cleanup = true,
    })
end

return T
