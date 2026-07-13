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
        assert(store.set_window("test", first, { { line = 0, type = "Misc" } }))
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
            second_lines = vim.api.nvim_buf_get_lines(second_state.float_buf, 0, -1, false),
            float_extmarks = float_extmarks,
            source_extmarks = source_extmarks,
            float_filetype = vim.bo[first_state.float_buf].filetype,
            float_buftype = vim.bo[first_state.float_buf].buftype,
            float_modifiable = vim.bo[first_state.float_buf].modifiable,
            winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = first_state.float_win }),
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
    expect.equality(result.first_lines[1]:sub(1, 1), "M")
    expect.equality(result.first_lines[#result.first_lines]:sub(1, 1), "M")
    expect.no_equality(result.second_lines[1]:sub(1, 1), "M")
    expect.equality(result.second_lines[#result.second_lines]:sub(1, 1), "M")
    expect.equality(#result.float_extmarks > 0, true)
    expect.equality(result.float_extmarks[1][4].virt_text, nil)
    expect.equality(result.source_extmarks, {})
    expect.equality(result.float_filetype, "scrollbar")
    expect.equality(result.float_buftype, "nofile")
    expect.equality(result.float_modifiable, false)
    expect.equality(result.winhighlight, "Normal:ScrollbarTrack,NormalNC:ScrollbarTrack,EndOfBuffer:ScrollbarTrack")
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
        for _, winid in ipairs(renderer.source_windows()) do
            renderer.render(winid)
        end
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

T["requires and clears per-window reveals when autohide is enabled"] = function()
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

        base_config.autohide = { enabled = true, delay_ms = 500 }
        require("scrollbar.config").set(base_config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local initially_hidden = renderer.render(first) == nil and renderer.render(second) == nil
        assert(renderer.reveal(first))
        local first_state = assert(renderer.render(first))
        local only_first = renderer.get_state(second) == nil and renderer.render(second) == nil

        assert(renderer.reveal(second))
        local second_state = assert(renderer.render(second))
        local first_float = first_state.float_win
        local first_buffer = first_state.float_buf
        assert(renderer.conceal(first))
        local independent_conceal = renderer.get_state(first) == nil
            and renderer.get_state(second) == second_state
            and not vim.api.nvim_win_is_valid(first_float)
            and not vim.api.nvim_buf_is_valid(first_buffer)

        local second_float = second_state.float_win
        renderer.hide()
        renderer.show()
        local hide_cleared = not vim.api.nvim_win_is_valid(second_float)
            and renderer.render(first) == nil
            and renderer.render(second) == nil

        assert(renderer.reveal(first))
        local reset_state = assert(renderer.render(first))
        local reset_float = reset_state.float_win
        renderer.setup()
        local setup_cleared = not vim.api.nvim_win_is_valid(reset_float) and renderer.render(first) == nil

        return {
            initially_hidden = initially_hidden,
            only_first = only_first,
            independent_conceal = independent_conceal,
            hide_cleared = hide_cleared,
            setup_cleared = setup_cleared,
        }
    end, renderer_config())

    expect.equality(result, {
        initially_hidden = true,
        only_first = true,
        independent_conceal = true,
        hide_cleared = true,
        setup_cleared = true,
    })
end

T["retains line caches only across transient concealment"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local source_buf = vim.api.nvim_get_current_buf()
        base_config.autohide = { enabled = true, delay_ms = 500 }
        require("scrollbar.config").set(base_config)
        assert(require("scrollbar.store").set("test", source_buf, { { line = 100, type = "Misc" } }))

        local layout = require("scrollbar.layout")
        local original_mark_layer = layout.mark_layer
        local builds = 0
        rawset(layout, "mark_layer", function(input)
            builds = builds + 1
            return original_mark_layer(input)
        end)

        local renderer = require("scrollbar.renderer")
        renderer.setup()
        assert(renderer.reveal(source_win))
        local first = assert(renderer.render(source_win))
        local first_float = first.float_win
        local first_buffer = first.float_buf
        local after_first = builds

        assert(renderer.conceal(source_win))
        assert(renderer.reveal(source_win))
        local second = assert(renderer.render(source_win))
        local after_conceal = builds

        renderer.hide()
        renderer.show()
        assert(renderer.reveal(source_win))
        renderer.render(source_win)
        local after_hide = builds
        rawset(layout, "mark_layer", original_mark_layer)

        return {
            after_first = after_first,
            after_conceal = after_conceal,
            after_hide = after_hide,
            float_recreated = second.float_win ~= first_float and not vim.api.nvim_win_is_valid(first_float),
            buffer_recreated = second.float_buf ~= first_buffer and not vim.api.nvim_buf_is_valid(first_buffer),
        }
    end, renderer_config())

    expect.equality(result, {
        after_first = 1,
        after_conceal = 1,
        after_hide = 2,
        float_recreated = true,
        buffer_recreated = true,
    })
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

T["renders compact built-in search exactly and invalidates it by revision"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(base_config)
            local lines = {}
            for index = 1, 100 do
                lines[index] = "line " .. index
            end
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            vim.cmd("split")
            local source_win = vim.api.nvim_get_current_win()
            vim.api.nvim_win_set_height(source_win, 10)
            local source_buf = vim.api.nvim_win_get_buf(source_win)
            local store = require("scrollbar.store")
            local compact = require("scrollbar.providers.search_compact")
            local renderer = require("scrollbar.renderer")
            assert(store.set("alpha", source_buf, { { line = 20, type = "Search", text = "A" } }))

            local matches = { 10, 10, 11, 99 }
            local ordinary_marks = vim.tbl_map(function(line)
                return { line = line, type = "Search" }
            end, matches)
            local cases = {}
            for _, mode in ipairs({ "line", "screen" }) do
                local active = vim.deepcopy(base_config)
                active.render.geometry = mode
                require("scrollbar.config").set(active)
                renderer.setup()

                assert(store.set("search", source_buf, ordinary_marks))
                local ordinary = assert(renderer.render(source_win))
                local expected = {
                    rows = vim.deepcopy(ordinary.rows),
                    highlights = vim.deepcopy(ordinary.highlights),
                    hitmap = vim.deepcopy(ordinary.hitmap),
                }

                local before = store._get_snapshot(source_buf).revision
                assert(store._set_search_compact(source_buf, compact.encode(matches)))
                local compact_state = assert(renderer.render(source_win))
                local after = store._get_snapshot(source_buf).revision
                local no_op_changed = select(2, store._set_search_compact(source_buf, compact.encode(matches)))
                cases[mode] = {
                    equivalent = vim.deep_equal(expected, {
                        rows = compact_state.rows,
                        highlights = compact_state.highlights,
                        hitmap = compact_state.hitmap,
                    }),
                    revision_advanced = after == before + 1,
                    no_op = next(no_op_changed) == nil and store._get_snapshot(source_buf).revision == after,
                }
            end

            local previous_rows = vim.deepcopy(assert(renderer.get_state(source_win)).rows)
            assert(store._set_search_compact(source_buf, compact.encode({ 50, 50, 50 })))
            local invalidated = assert(renderer.render(source_win))
            cases.changed = not vim.deep_equal(previous_rows, invalidated.rows)
            return cases
        end,
        renderer_config({
            marks = {
                Search = { text = { "-", "=", "#" }, column = 1 },
                Misc = { text = "M", column = 1 },
            },
        })
    )

    for _, mode in ipairs({ "line", "screen" }) do
        expect.equality(result[mode].equivalent, true)
        expect.equality(result[mode].revision_advanced, true)
        expect.equality(result[mode].no_op, true)
    end
    expect.equality(result.changed, true)
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

T["caches line mark work while keeping handle geometry current and invalidating exact inputs"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 240 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 8)
        local source_buf = vim.api.nvim_win_get_buf(source_win)

        local scrollbar_config = require("scrollbar.config")
        scrollbar_config.set(base_config)
        local store = require("scrollbar.store")
        local buffer_marks = { { line = 120, type = "Misc", text = "A" } }
        assert(store.set("buffer", source_buf, buffer_marks))
        assert(store.set_window("window", source_win, { { line = 30, type = "Misc", text = "W" } }))

        local layout = require("scrollbar.layout")
        local original_mark_layer = layout.mark_layer
        local builds = 0
        local mark_tables = {}
        rawset(layout, "mark_layer", function(input)
            builds = builds + 1
            mark_tables[builds] = input.marks
            return original_mark_layer(input)
        end)

        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local initial = assert(renderer.render(source_win))
        local initial_handle = vim.deepcopy(initial.handle)
        local after_initial = builds

        vim.api.nvim_win_call(source_win, function()
            vim.api.nvim_win_set_cursor(0, { 180, 0 })
            vim.cmd("normal! zt")
        end)
        local scrolled = assert(renderer.render(source_win))
        local after_scroll = builds

        assert(store.set("buffer", source_buf, buffer_marks))
        renderer.render(source_win)
        local after_noop = builds

        assert(store.set("buffer", source_buf, { { line = 121, type = "Misc", text = "B" } }))
        renderer.render(source_win)
        local after_buffer_marks = builds

        assert(store.set_window("window", source_win, { { line = 31, type = "Misc", text = "V" } }))
        renderer.render(source_win)
        local after_window_marks = builds

        vim.api.nvim_buf_set_lines(source_buf, -1, -1, false, { "extra" })
        renderer.render(source_win)
        local after_line_count = builds

        vim.api.nvim_win_set_height(source_win, 7)
        renderer.render(source_win)
        local after_resize = builds
        local resize_reused_flattened = rawequal(mark_tables[after_resize], mark_tables[after_line_count])

        local changed_config = vim.deepcopy(base_config)
        changed_config.marks.Misc.text = "N"
        scrollbar_config.set(changed_config)
        renderer.render(source_win)
        local after_config = builds
        local config_reused_flattened = rawequal(mark_tables[after_config], mark_tables[after_resize])

        local replacement_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(replacement_buf, 0, -1, false, lines)
        assert(store.set("buffer", replacement_buf, { { line = 20, type = "Misc", text = "R" } }))
        vim.api.nvim_win_set_buf(source_win, replacement_buf)
        renderer.render(source_win)
        local after_replacement = builds

        renderer.dispose(source_win)
        renderer.render(source_win)
        local after_dispose = builds
        rawset(layout, "mark_layer", original_mark_layer)

        return {
            after_initial = after_initial,
            after_scroll = after_scroll,
            after_noop = after_noop,
            after_buffer_marks = after_buffer_marks,
            after_window_marks = after_window_marks,
            after_line_count = after_line_count,
            after_resize = after_resize,
            after_config = after_config,
            after_replacement = after_replacement,
            after_dispose = after_dispose,
            handle_moved = scrolled.handle.first_row > initial_handle.first_row,
            resize_reused_flattened = resize_reused_flattened,
            config_reused_flattened = config_reused_flattened,
        }
    end, renderer_config())

    expect.equality(result, {
        after_initial = 1,
        after_scroll = 1,
        after_noop = 1,
        after_buffer_marks = 2,
        after_window_marks = 3,
        after_line_count = 4,
        after_resize = 5,
        after_config = 6,
        after_replacement = 7,
        after_dispose = 8,
        handle_moved = true,
        resize_reused_flattened = true,
        config_reused_flattened = true,
    })
end

T["screen renders reuse flattened marks but always repeat text-height measurements"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = string.rep("x", index % 20 + 1)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local source_buf = vim.api.nvim_get_current_buf()
        local active_config = vim.deepcopy(base_config)
        active_config.render.geometry = "screen"
        require("scrollbar.config").set(active_config)
        assert(require("scrollbar.store").set("test", source_buf, {
            { line = 10, type = "Misc" },
            { line = 150, type = "Misc" },
        }))

        local layout = require("scrollbar.layout")
        local original_screen = layout.screen
        local mark_tables = {}
        rawset(layout, "screen", function(input)
            table.insert(mark_tables, input.marks)
            return original_screen(input)
        end)
        local original_text_height = vim.api.nvim_win_text_height
        local measurements = 0
        vim.api.nvim_win_text_height = function(...)
            measurements = measurements + 1
            return original_text_height(...)
        end

        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local first_measurements = measurements
        vim.api.nvim_win_call(source_win, function()
            vim.api.nvim_win_set_cursor(0, { 150, 0 })
            vim.cmd("normal! zt")
        end)
        renderer.render(source_win)
        local second_measurements = measurements - first_measurements

        rawset(layout, "screen", original_screen)
        vim.api.nvim_win_text_height = original_text_height
        return {
            same_marks = rawequal(mark_tables[1], mark_tables[2]),
            first_measurements = first_measurements,
            second_measurements = second_measurements,
        }
    end, renderer_config())

    expect.equality(result.same_marks, true)
    expect.equality(result.first_measurements > 0, true)
    expect.equality(result.second_measurements > 0, true)
end

T["configures owned state once and reapplies only changed float configuration"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 8)

        local scrollbar_config = require("scrollbar.config")
        scrollbar_config.set(base_config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local option_calls = { buftype = 0, wrap = 0 }
        local config_calls = 0
        local set_option_value = vim.api.nvim_set_option_value
        local win_set_config = vim.api.nvim_win_set_config
        rawset(vim.api, "nvim_set_option_value", function(name, value, options)
            if option_calls[name] ~= nil then
                option_calls[name] = option_calls[name] + 1
            end
            return set_option_value(name, value, options)
        end)
        rawset(vim.api, "nvim_win_set_config", function(...)
            config_calls = config_calls + 1
            return win_set_config(...)
        end)

        local first = assert(renderer.render(source_win))
        local after_create = {
            buftype = option_calls.buftype,
            wrap = option_calls.wrap,
            config = config_calls,
        }
        renderer.render(source_win)
        local after_unchanged = {
            buftype = option_calls.buftype,
            wrap = option_calls.wrap,
            config = config_calls,
        }

        vim.api.nvim_win_set_height(source_win, 6)
        renderer.render(source_win)
        local after_height = config_calls

        local changed = vim.deepcopy(base_config)
        changed.float.width = 3
        changed.float.placement.row = 1
        changed.mouse.enabled = true
        scrollbar_config.set(changed)
        renderer.render(source_win)
        local changed_state = assert(renderer.get_state(source_win))
        local changed_config = vim.api.nvim_win_get_config(changed_state.float_win)
        local after_options = {
            buftype = option_calls.buftype,
            wrap = option_calls.wrap,
        }
        local after_changed = config_calls

        win_set_config(changed_state.float_win, {
            relative = "editor",
            anchor = "NW",
            row = 0,
            col = 0,
            width = 1,
            height = 1,
        })
        renderer.render(source_win)
        local restored_config = vim.api.nvim_win_get_config(changed_state.float_win)
        local after_restore = config_calls

        local replacement_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(replacement_buf, 0, -1, false, lines)
        vim.api.nvim_win_set_buf(source_win, replacement_buf)
        local replacement = assert(renderer.render(source_win))

        rawset(vim.api, "nvim_set_option_value", set_option_value)
        rawset(vim.api, "nvim_win_set_config", win_set_config)
        return {
            after_create = after_create,
            after_unchanged = after_unchanged,
            after_height = after_height,
            after_options = after_options,
            after_changed = after_changed,
            changed_config = changed_config,
            after_restore = after_restore,
            restored_config = restored_config,
            replaced = replacement.float_win ~= first.float_win
                and replacement.float_buf ~= first.float_buf
                and not vim.api.nvim_win_is_valid(first.float_win)
                and not vim.api.nvim_buf_is_valid(first.float_buf),
            replacement_options = {
                buftype = option_calls.buftype,
                wrap = option_calls.wrap,
            },
        }
    end, renderer_config())

    expect.equality(result.after_create, { buftype = 1, wrap = 1, config = 0 })
    expect.equality(result.after_unchanged, result.after_create)
    expect.equality(result.after_height, 1)
    expect.equality(result.after_options, { buftype = 1, wrap = 1 })
    expect.equality(result.after_changed, 2)
    expect.equality(result.changed_config.width, 3)
    expect.equality(result.changed_config.height, 6)
    expect.equality(result.changed_config.row, 1)
    expect.equality(result.changed_config.focusable, true)
    expect.equality(result.changed_config.mouse, true)
    expect.equality(result.after_restore, 3)
    expect.equality(result.restored_config.anchor, "NE")
    expect.equality(result.restored_config.width, 3)
    expect.equality(result.restored_config.height, 6)
    expect.equality(result.restored_config.row, 1)
    expect.equality(result.restored_config.focusable, true)
    expect.equality(result.restored_config.mouse, true)
    expect.equality(result.replaced, true)
    expect.equality(result.replacement_options, { buftype = 2, wrap = 2 })
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
        renderer.render(second)
        local show_recreated = renderer.get_state(second) ~= nil
        renderer.toggle()
        local toggle_hidden = renderer.get_state(second) == nil and not renderer.is_visible()
        renderer.toggle()
        renderer.render(second)
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
