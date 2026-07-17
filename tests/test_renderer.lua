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
    return require("scrollbar.presets").merge({
        show = true,
        set_highlights = false,
        render = { interval_ms = 0, geometry = "line" },
        float = { placement = { relative = "window", anchor = "NE", row = 0, col = 0 } },
        layout = {
            columns = {
                { "track", "marks" },
                { "track", "thumb" },
            },
        },
        mouse = { enabled = false },
        thumb = { text = "H", hide_if_all_visible = false },
        marks = { Misc = { text = "M" } },
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
        local set_extmark = vim.api.nvim_buf_set_extmark
        local extmark_options = {}
        rawset(vim.api, "nvim_buf_set_extmark", function(...)
            local arguments = { ... }
            local options = arguments[5]
            if options.hl_group ~= nil then
                extmark_options[#extmark_options + 1] = {
                    hl_group = options.hl_group,
                    hl_mode = options.hl_mode,
                    priority = options.priority,
                }
            end
            return set_extmark(...)
        end)
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
        rawset(vim.api, "nvim_buf_set_extmark", set_extmark)
        return {
            first = first_state,
            second = second_state,
            first_lines = vim.api.nvim_buf_get_lines(first_state.float_buf, 0, -1, false),
            second_lines = vim.api.nvim_buf_get_lines(second_state.float_buf, 0, -1, false),
            float_extmarks = float_extmarks,
            source_extmarks = source_extmarks,
            extmark_options = extmark_options,
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
    local extmark_groups = {}
    for _, extmark in ipairs(result.float_extmarks) do
        extmark_groups[extmark[4].hl_group] = {
            priority = extmark[4].priority,
        }
    end
    expect.equality(extmark_groups.ScrollbarTrack, { priority = 1 })
    expect.equality(extmark_groups.ScrollbarMisc, { priority = 2 })
    for _, options in ipairs(result.extmark_options) do
        expect.equality(options.hl_mode, "combine")
        expect.equality(type(options.priority), "number")
    end
    expect.equality(result.source_extmarks, {})
    expect.equality(result.float_filetype, "scrollbar")
    expect.equality(result.float_buftype, "nofile")
    expect.equality(result.float_modifiable, false)
    expect.equality(result.winhighlight, "Normal:ScrollbarBase,NormalNC:ScrollbarBase,EndOfBuffer:ScrollbarBase")
    expect.equality(result.lookup, result.first.source_win)
end

T["switches canonical Thumb spans to pressed groups without losing priorities"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            local lines = {}
            for index = 1, 100 do
                lines[index] = "line " .. index
            end
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            local source_win = vim.api.nvim_get_current_win()
            require("scrollbar.config").set(config)
            assert(
                require("scrollbar.store").set("test", vim.api.nvim_get_current_buf(), { { line = 0, type = "Misc" } })
            )
            local renderer = require("scrollbar.renderer")
            renderer.setup()
            local state = assert(renderer.render(source_win))
            local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
            local function groups()
                local found = {}
                for _, extmark in
                    ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true }))
                do
                    local details = extmark[4]
                    found[details.hl_group] = details.priority
                end
                return found
            end
            local resting = groups()
            assert(renderer.set_handle_pressed(state.float_win, true))
            local pressed = groups()
            assert(renderer.set_handle_pressed(state.float_win, false))
            local restored = groups()
            return { resting = resting, pressed = pressed, restored = restored }
        end,
        renderer_config({
            layout = { columns = { { "track", "thumb", "marks" } } },
        })
    )

    expect.equality(result.resting.ScrollbarThumb, 2)
    expect.equality(result.resting.ScrollbarMiscThumb, 3)
    expect.equality(result.pressed.ScrollbarThumbPressed, 2)
    expect.equality(result.pressed.ScrollbarMiscThumbPressed, 3)
    expect.equality(result.pressed.ScrollbarThumb, nil)
    expect.equality(result.pressed.ScrollbarMiscThumb, nil)
    expect.equality(result.restored, result.resting)
end

T["renders track only in declared columns over a transparent float base"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            local lines = {}
            for index = 1, 100 do
                lines[index] = "line " .. index
            end
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            local source_win = vim.api.nvim_get_current_win()
            require("scrollbar.config").set(config)
            assert(require("scrollbar.store").set("test", vim.api.nvim_get_current_buf(), {
                { line = 0, type = "Misc" },
            }))
            local renderer = require("scrollbar.renderer")
            renderer.setup()
            local state = assert(renderer.render(source_win))
            local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
            local groups = {}
            for _, extmark in
                ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, { 0, -1 }, {
                    details = true,
                }))
            do
                groups[extmark[4].hl_group] = {
                    start_col = extmark[3],
                    end_col = extmark[4].end_col,
                    priority = extmark[4].priority,
                }
            end
            return {
                groups = groups,
                row = vim.api.nvim_buf_get_lines(state.float_buf, 0, 1, false)[1],
                winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = state.float_win }),
            }
        end,
        renderer_config({
            layout = { columns = { { "track" }, { "marks" }, { "thumb" } } },
        })
    )

    expect.equality(result.row, " MH")
    expect.equality(result.groups.ScrollbarTrack, { start_col = 0, end_col = 1, priority = 1 })
    expect.equality(result.groups.ScrollbarMisc, { start_col = 1, end_col = 2, priority = 1 })
    expect.equality(result.groups.ScrollbarThumb, { start_col = 2, end_col = 3, priority = 1 })
    expect.equality(result.winhighlight, "Normal:ScrollbarBase,NormalNC:ScrollbarBase,EndOfBuffer:ScrollbarBase")
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
        handle_hidden.thumb.hide_if_all_visible = true
        scrollbar_config.set(handle_hidden)
        renderer.setup()
        local state = assert(renderer.render(source_win))
        local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
        local extmarks = vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true })
        local has_handle_highlight = false
        for _, extmark in ipairs(extmarks) do
            if extmark[4].hl_group == "ScrollbarThumb" then
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
                Search = { text = { "-", "=", "#" } },
                Misc = { text = "M" },
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

T["grows and shrinks expanded floats in place while pinning base cells for every anchor"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 8)
        local source_buf = vim.api.nvim_win_get_buf(source_win)
        local store = require("scrollbar.store")
        assert(store.set("test", source_buf, { { line = 100, type = "Misc" } }))

        local scrollbar_config = require("scrollbar.config")
        local renderer = require("scrollbar.renderer")
        local cases = {}

        local function cell_screen_column(state, row, column)
            vim.api.nvim__redraw({ flush = true })
            vim.api.nvim__redraw({ flush = true })
            return vim.fn.screenpos(state.float_win, row + 1, column).col
        end

        local function screen_column(state, predicate)
            for row, cells in ipairs(state.hitmap) do
                for column, cell in ipairs(cells) do
                    if predicate(cell) then
                        return cell_screen_column(state, row - 1, column)
                    end
                end
            end
        end

        local function rows_are_padded(state)
            for _, row in ipairs(vim.api.nvim_buf_get_lines(state.float_buf, 0, -1, false)) do
                if vim.fn.strdisplaywidth(row) ~= state.width then
                    return false
                end
            end
            return true
        end

        for _, anchor in ipairs({ "NW", "NE", "SW", "SE" }) do
            local active = vim.deepcopy(base_config)
            active.float.hide_on_cursor = false
            active.float.placement.anchor = anchor
            active.layout.columns = {
                { "track", { kind = "marks", types = { "Mark" }, max_width = 6 } },
                { "track", "marks", "thumb" },
            }
            scrollbar_config.set(active)
            renderer.setup()

            assert(store.set("marks", source_buf, { { line = 0, type = "Mark", text = "a" } }))
            local initial = assert(renderer.render(source_win))
            local float_win = initial.float_win
            local float_buf = initial.float_buf
            local initial_width = initial.width
            local initial_float_width = vim.api.nvim_win_get_config(float_win).width
            local initial_handle_column = cell_screen_column(initial, initial.handle.first_row, initial.handle.column)
            local initial_mark_column = screen_column(initial, function(cell)
                return cell.provider == "test"
            end)
            local events = {}
            vim.api.nvim_buf_attach(float_buf, false, {
                on_lines = function(_, _, _, first, last, new_last)
                    table.insert(events, { first = first, last = last, new_last = new_last })
                end,
            })

            assert(store.set("marks", source_buf, {
                { line = 0, type = "Mark", text = "a" },
                { line = 1, type = "Mark", text = "b" },
                { line = 2, type = "Mark", text = "c" },
                { line = 3, type = "Mark", text = "d" },
            }))
            local grown = assert(renderer.render(source_win))
            local grown_width = grown.width
            local grown_float = vim.api.nvim_win_get_config(grown.float_win)
            local grown_handle_column = cell_screen_column(grown, grown.handle.first_row, grown.handle.column)
            local grown_mark_column = screen_column(grown, function(cell)
                return cell.provider == "test"
            end)
            local grown_rows_padded = rows_are_padded(grown)
            local grow_events = events

            events = {}
            assert(store.set("marks", source_buf, { { line = 0, type = "Mark", text = "a" } }))
            local shrunk = assert(renderer.render(source_win))
            local shrunk_width = shrunk.width
            local shrunk_float = vim.api.nvim_win_get_config(shrunk.float_win)
            local shrunk_handle_column = cell_screen_column(shrunk, shrunk.handle.first_row, shrunk.handle.column)
            local shrunk_mark_column = screen_column(shrunk, function(cell)
                return cell.provider == "test"
            end)

            cases[anchor] = {
                widths = { initial_width, grown_width, shrunk_width },
                float_widths = { initial_float_width, grown_float.width, shrunk_float.width },
                same_resources = grown.float_win == float_win
                    and shrunk.float_win == float_win
                    and grown.float_buf == float_buf
                    and shrunk.float_buf == float_buf,
                resources_valid = vim.api.nvim_win_is_valid(float_win) and vim.api.nvim_buf_is_valid(float_buf),
                handle_columns = { initial_handle_column, grown_handle_column, shrunk_handle_column },
                mark_columns = { initial_mark_column, grown_mark_column, shrunk_mark_column },
                rows_padded = grown_rows_padded and rows_are_padded(shrunk),
                dimensions_replaced = vim.deep_equal(grow_events, {
                    { first = 0, last = grown.height, new_last = grown.height },
                }) and vim.deep_equal(events, {
                    { first = 0, last = shrunk.height, new_last = shrunk.height },
                }),
            }
        end
        return cases
    end, renderer_config())

    for _, anchor in ipairs({ "NW", "NE", "SW", "SE" }) do
        local case = result[anchor]
        expect.equality(case.widths, { 2, 5, 2 })
        expect.equality(case.float_widths, case.widths)
        expect.equality(case.same_resources, true)
        expect.equality(case.resources_valid, true)
        expect.equality(case.handle_columns, {
            case.handle_columns[1],
            case.handle_columns[1],
            case.handle_columns[1],
        })
        expect.equality(case.mark_columns, { case.mark_columns[1], case.mark_columns[1], case.mark_columns[1] })
        expect.equality(case.rows_padded, true)
        expect.equality(case.dimensions_replaced, true)
    end
end

T["uses window and editor placement containers and resolves width per source window height"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(second, 4)
        local source_buf = vim.api.nvim_get_current_buf()
        assert(require("scrollbar.store").set("marks", source_buf, {
            { line = 0, type = "Mark", text = "a" },
            { line = 10, type = "Mark", text = "b" },
            { line = 20, type = "Mark", text = "c" },
        }))

        local active = vim.deepcopy(base_config)
        active.float.hide_on_cursor = false
        active.float.placement.anchor = "NW"
        active.layout.columns = {
            { "track", { kind = "marks", types = { "Mark" }, max_width = 8 } },
            { "track", "marks", "thumb" },
        }
        local scrollbar_config = require("scrollbar.config")
        scrollbar_config.set(active)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local tall = assert(renderer.render(first))
        local short = assert(renderer.render(second))
        local per_height = { tall = tall.width, short = short.width }

        vim.cmd("only")
        vim.cmd("vsplit")
        local narrow_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_width(narrow_win, 4)
        local narrow_width = vim.api.nvim_win_get_width(narrow_win)
        local dense_marks = {}
        for index = 1, 8 do
            dense_marks[index] = { line = index - 1, type = "Mark", text = string.char(96 + index) }
        end
        assert(require("scrollbar.store").set("marks", source_buf, dense_marks))
        local narrow = assert(renderer.render(narrow_win))
        local narrow_state_width = narrow.width

        vim.api.nvim_win_set_width(narrow_win, 6)
        local wider_width = vim.api.nvim_win_get_width(narrow_win)
        local wider = assert(renderer.render(narrow_win))
        local wider_state_width = wider.width

        local editor = vim.deepcopy(active)
        editor.float.placement.relative = "editor"
        scrollbar_config.set(editor)
        renderer.setup()
        vim.api.nvim_set_current_win(narrow_win)
        local editor_state = assert(renderer.render(narrow_win))

        return {
            per_height = per_height,
            window = {
                narrow = narrow_state_width,
                narrow_container = narrow_width,
                wider = wider_state_width,
                wider_container = wider_width,
                same_resources = narrow.float_win == wider.float_win and narrow.float_buf == wider.float_buf,
            },
            editor = {
                width = editor_state.width,
                container = vim.o.columns,
                float_width = vim.api.nvim_win_get_config(editor_state.float_win).width,
            },
        }
    end, renderer_config())

    expect.equality(result.per_height, { tall = 3, short = 4 })
    expect.equality(result.window.narrow, math.min(8, result.window.narrow_container))
    expect.equality(result.window.wider, math.min(8, result.window.wider_container))
    expect.equality(result.window.same_resources, true)
    expect.equality(result.editor.width, math.min(9, result.editor.container))
    expect.equality(result.editor.float_width, result.editor.width)
end

T["caches line mark work while keeping handle geometry current and invalidating exact inputs"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 240 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("vsplit")
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
        local container_widths = {}
        rawset(layout, "mark_layer", function(input)
            builds = builds + 1
            mark_tables[builds] = input.marks
            container_widths[builds] = input.container_width
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

        local old_width = vim.api.nvim_win_get_width(source_win)
        vim.api.nvim_win_set_width(source_win, old_width - 1)
        renderer.render(source_win)
        local after_container = builds
        local container_changed = container_widths[after_container] ~= container_widths[after_line_count]

        vim.api.nvim_win_set_height(source_win, 7)
        renderer.render(source_win)
        local after_resize = builds
        local resize_reused_flattened = rawequal(mark_tables[after_resize], mark_tables[after_container])

        local changed_config = vim.deepcopy(base_config)
        changed_config.float.placement.anchor = "NW"
        scrollbar_config.set(changed_config)
        renderer.render(source_win)
        local after_config = builds
        local config_reused_flattened = rawequal(mark_tables[after_config], mark_tables[after_resize])

        local visual_config = vim.deepcopy(changed_config)
        visual_config.track = { highlight = "Normal" }
        visual_config.thumb.highlight = "Normal"
        visual_config.marks.Misc.highlight = "WarningMsg"
        visual_config.render.interval_ms = 99
        visual_config.providers.marks = { numbers = true }
        scrollbar_config.set(visual_config)
        renderer.render(source_win)
        local after_visual_config = builds

        local changed_text = vim.deepcopy(visual_config)
        changed_text.marks.Misc.text = "Z"
        scrollbar_config.set(changed_text)
        renderer.render(source_win)
        local after_mark_text = builds

        local changed_priority = vim.deepcopy(changed_text)
        changed_priority.marks.Misc.priority = 9
        scrollbar_config.set(changed_priority)
        renderer.render(source_win)
        local after_mark_priority = builds

        local changed_layout = vim.deepcopy(changed_priority)
        changed_layout.layout.columns = {
            { "track", { kind = "marks", types = { "Mark" }, max_width = 4 } },
            { "track", "marks", "thumb" },
        }
        scrollbar_config.set(changed_layout)
        renderer.render(source_win)
        local after_layout = builds

        local changed_cap = vim.deepcopy(changed_layout)
        changed_cap.layout.columns[1][2].max_width = 5
        scrollbar_config.set(changed_cap)
        renderer.render(source_win)
        local after_expansion_cap = builds

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
            after_container = after_container,
            after_resize = after_resize,
            after_config = after_config,
            after_visual_config = after_visual_config,
            after_mark_text = after_mark_text,
            after_mark_priority = after_mark_priority,
            after_layout = after_layout,
            after_expansion_cap = after_expansion_cap,
            after_replacement = after_replacement,
            after_dispose = after_dispose,
            handle_moved = scrolled.handle.first_row > initial_handle.first_row,
            container_changed = container_changed,
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
        after_container = 5,
        after_resize = 6,
        after_config = 7,
        after_visual_config = 7,
        after_mark_text = 8,
        after_mark_priority = 9,
        after_layout = 10,
        after_expansion_cap = 11,
        after_replacement = 12,
        after_dispose = 13,
        handle_moved = true,
        container_changed = true,
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
        local original_compose = layout.compose
        local compose_inputs = {}
        rawset(layout, "compose", function(input)
            table.insert(compose_inputs, {
                container_width = input.container_width,
                has_mark_layer = input.mark_layer ~= nil,
            })
            return original_compose(input)
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
        rawset(layout, "compose", original_compose)
        vim.api.nvim_win_text_height = original_text_height
        return {
            same_marks = rawequal(mark_tables[1], mark_tables[2]),
            first_measurements = first_measurements,
            second_measurements = second_measurements,
            compose_inputs = compose_inputs,
            source_width = vim.api.nvim_win_get_width(source_win),
        }
    end, renderer_config())

    expect.equality(result.same_marks, true)
    expect.equality(result.first_measurements > 0, true)
    expect.equality(result.second_measurements > 0, true)
    expect.equality(result.compose_inputs, {
        { container_width = result.source_width, has_mark_layer = false },
        { container_width = result.source_width, has_mark_layer = false },
    })
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
        base_config.float.hide_on_cursor = false
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
        changed.layout.columns = {
            { "track", "marks" },
            { "track" },
            { "track", "thumb" },
        }
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

T["hides on cursor overlap and restores the same resources only on transitions"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()

        require("scrollbar.config").set(base_config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local cursor = { row = 3, col = 7 }
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        local set_config = vim.api.nvim_win_set_config
        local redraw = vim.api.nvim__redraw
        local config_calls = 0
        local redraw_calls = 0
        local position_resolved = false
        rawset(vim.fn, "screenrow", function()
            return cursor.row
        end)
        rawset(vim.fn, "screencol", function()
            return cursor.col
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            return position_resolved and { 1, 5 } or { 1, 8 }
        end)
        rawset(vim.api, "nvim_win_set_config", function(...)
            config_calls = config_calls + 1
            return set_config(...)
        end)
        rawset(vim.api, "nvim__redraw", function(options)
            redraw_calls = redraw_calls + 1
            position_resolved = true
            return redraw(options)
        end)

        local hidden = assert(renderer.render(source_win))
        local hidden_config = vim.api.nvim_win_get_config(hidden.float_win)
        local hidden_by_cursor = hidden.hidden_by_cursor
        local after_hide = config_calls
        renderer.render(source_win)
        local after_hidden_steady = config_calls

        cursor.col = 5
        local restored = assert(renderer.render(source_win))
        local restored_config = vim.api.nvim_win_get_config(restored.float_win)
        local after_restore = config_calls
        renderer.render(source_win)
        local after_visible_steady = config_calls

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        rawset(vim.api, "nvim_win_set_config", set_config)
        rawset(vim.api, "nvim__redraw", redraw)
        return {
            hidden_by_cursor = hidden_by_cursor,
            hidden_config = hidden_config.hide,
            restored_by_cursor = restored.hidden_by_cursor,
            restored_config = restored_config.hide,
            same_float = hidden.float_win == restored.float_win,
            same_buffer = hidden.float_buf == restored.float_buf,
            resources_valid = vim.api.nvim_win_is_valid(restored.float_win)
                and vim.api.nvim_buf_is_valid(restored.float_buf),
            redraw_calls = redraw_calls,
            calls = {
                after_hide = after_hide,
                after_hidden_steady = after_hidden_steady,
                after_restore = after_restore,
                after_visible_steady = after_visible_steady,
            },
        }
    end, renderer_config())

    expect.equality(result, {
        hidden_by_cursor = true,
        hidden_config = true,
        restored_by_cursor = false,
        restored_config = false,
        same_float = true,
        same_buffer = true,
        resources_valid = true,
        redraw_calls = 1,
        calls = {
            after_hide = 0,
            after_hidden_steady = 0,
            after_restore = 1,
            after_visible_steady = 1,
        },
    })
end

T["uses the full expanded width for cursor hiding"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local source_buf = vim.api.nvim_get_current_buf()
        base_config.float.placement.anchor = "NW"
        base_config.layout.columns = {
            { "track", { kind = "marks", types = { "Mark" }, max_width = 6 } },
            { "track", "marks", "thumb" },
        }
        require("scrollbar.config").set(base_config)
        assert(require("scrollbar.store").set("marks", source_buf, {
            { line = 0, type = "Mark", text = "a" },
            { line = 1, type = "Mark", text = "b" },
            { line = 2, type = "Mark", text = "c" },
            { line = 3, type = "Mark", text = "d" },
        }))
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local cursor_col = 9
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            return 2
        end)
        rawset(vim.fn, "screencol", function()
            return cursor_col
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            return { 1, 5 }
        end)

        local hidden = assert(renderer.render(source_win))
        local hidden_by_cursor = hidden.hidden_by_cursor
        local expanded_width = hidden.width
        local float_width = vim.api.nvim_win_get_config(hidden.float_win).width
        cursor_col = 11
        local restored = assert(renderer.render(source_win))

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return {
            width = expanded_width,
            float_width = float_width,
            hidden = hidden_by_cursor,
            restored = not restored.hidden_by_cursor,
            same_resources = hidden.float_win == restored.float_win and hidden.float_buf == restored.float_buf,
        }
    end, renderer_config())

    expect.equality(result, {
        width = 5,
        float_width = 5,
        hidden = true,
        restored = true,
        same_resources = true,
    })
end

T["skips disabled cursor work and keeps unavailable coordinates visible"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local scrollbar_config = require("scrollbar.config")
        local renderer = require("scrollbar.renderer")

        local calls = { row = 0, col = 0, position = 0 }
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            calls.row = calls.row + 1
            return 0
        end)
        rawset(vim.fn, "screencol", function()
            calls.col = calls.col + 1
            return 0
        end)
        rawset(vim.api, "nvim_win_get_position", function(...)
            calls.position = calls.position + 1
            return get_position(...)
        end)

        local disabled_config = vim.deepcopy(base_config)
        disabled_config.float.hide_on_cursor = false
        scrollbar_config.set(disabled_config)
        renderer.setup()
        local disabled = assert(renderer.render(source_win))
        local disabled_hide = vim.api.nvim_win_get_config(disabled.float_win).hide
        local disabled_calls = vim.deepcopy(calls)

        calls = { row = 0, col = 0, position = 0 }
        scrollbar_config.set(base_config)
        renderer.setup()
        local unavailable = assert(renderer.render(source_win))
        local unavailable_calls = vim.deepcopy(calls)

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return {
            disabled_hide = disabled_hide,
            disabled_calls = disabled_calls,
            unavailable_hide = vim.api.nvim_win_get_config(unavailable.float_win).hide,
            unavailable_calls = unavailable_calls,
        }
    end, renderer_config())

    expect.equality(result, {
        disabled_hide = false,
        disabled_calls = { row = 0, col = 0, position = 0 },
        unavailable_hide = false,
        unavailable_calls = { row = 1, col = 1, position = 0 },
    })
end

T["uses reported float bounds across widths placements anchors and clipping"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        local scrollbar_config = require("scrollbar.config")
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local cursor = { row = 1, col = 1 }
        local position = { 0, 0 }
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            return cursor.row
        end)
        rawset(vim.fn, "screencol", function()
            return cursor.col
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            return position
        end)

        local cases = {}
        for _, case in ipairs({
            {
                name = "window_north_west",
                placement = { relative = "window", anchor = "NW", row = 2, col = -3 },
                position = { 4, 6 },
                cursor = { row = 5, col = 9 },
                hidden = true,
            },
            {
                name = "window_south_east_clipped",
                placement = { relative = "window", anchor = "SE", row = -2, col = 3 },
                position = { -2, -1 },
                cursor = { row = 1, col = 1 },
                hidden = true,
            },
            {
                name = "editor_north_east",
                placement = { relative = "editor", anchor = "NE", row = 3, col = -4 },
                position = { 7, 10 },
                cursor = { row = 8, col = 13 },
                hidden = true,
            },
            {
                name = "editor_south_west_out_of_bounds",
                placement = { relative = "editor", anchor = "SW", row = -3, col = 4 },
                position = { 100, 100 },
                cursor = { row = 1, col = 1 },
                hidden = false,
            },
        }) do
            local active = vim.deepcopy(base_config)
            active.layout.columns = {
                { "track", "marks" },
                { "track" },
                { "track", "thumb" },
            }
            active.float.placement = case.placement
            scrollbar_config.set(active)
            position = case.position
            cursor = case.cursor
            local state = assert(renderer.render(source_win), case.name)
            local float = vim.api.nvim_win_get_config(state.float_win)
            cases[case.name] = {
                hidden = state.hidden_by_cursor,
                config_hide = float.hide,
                relative = float.relative,
                anchor = float.anchor,
                width = float.width,
            }
        end

        position = { 4, 6 }
        cursor = { row = 5, col = 10 }
        local boundary = assert(renderer.render(source_win))
        cases.right_boundary = {
            hidden = boundary.hidden_by_cursor,
            config_hide = vim.api.nvim_win_get_config(boundary.float_win).hide,
        }

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return cases
    end, renderer_config())

    expect.equality(result.window_north_west, {
        hidden = true,
        config_hide = true,
        relative = "win",
        anchor = "NW",
        width = 3,
    })
    expect.equality(result.window_south_east_clipped, {
        hidden = true,
        config_hide = true,
        relative = "win",
        anchor = "SE",
        width = 3,
    })
    expect.equality(result.editor_north_east, {
        hidden = true,
        config_hide = true,
        relative = "editor",
        anchor = "NE",
        width = 3,
    })
    expect.equality(result.editor_south_west_out_of_bounds, {
        hidden = false,
        config_hide = false,
        relative = "editor",
        anchor = "SW",
        width = 3,
    })
    expect.equality(result.right_boundary, { hidden = false, config_hide = false })
end

T["transfers cursor hiding between source windows on WinEnter"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()

        local active_config = require("scrollbar.config").set(base_config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            return 3
        end)
        rawset(vim.fn, "screencol", function()
            return 3
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            return { 2, 2 }
        end)

        local first_state = assert(renderer.render(first))
        local second_state = assert(renderer.render(second))
        local initial = {
            first = first_state.hidden_by_cursor,
            second = second_state.hidden_by_cursor,
        }

        local scheduler = require("scrollbar.scheduler")
        scheduler.setup({ config = active_config, renderer = renderer })
        vim.api.nvim_set_current_win(first)
        scheduler.flush()
        local transferred = {
            first = assert(renderer.get_state(first)).hidden_by_cursor,
            second = assert(renderer.get_state(second)).hidden_by_cursor,
            same_first = assert(renderer.get_state(first)).float_win == first_state.float_win,
            same_second = assert(renderer.get_state(second)).float_win == second_state.float_win,
        }
        scheduler.dispose()

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return { initial = initial, transferred = transferred }
    end, renderer_config())

    expect.equality(result, {
        initial = { first = false, second = true },
        transferred = { first = true, second = false, same_first = true, same_second = true },
    })
end

T["performs cursor position work only for the current source window"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        require("scrollbar.config").set(base_config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local calls = { row = 0, col = 0, position = 0 }
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            calls.row = calls.row + 1
            return 1
        end)
        rawset(vim.fn, "screencol", function()
            calls.col = calls.col + 1
            return 1
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            calls.position = calls.position + 1
            return { 0, 0 }
        end)

        renderer.render(first)
        local after_inactive = vim.deepcopy(calls)
        renderer.render(second)
        local after_current = vim.deepcopy(calls)
        renderer.render(first)
        local after_second_inactive = vim.deepcopy(calls)

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return {
            first = first,
            second = second,
            current = vim.api.nvim_get_current_win(),
            after_inactive = after_inactive,
            after_current = after_current,
            after_second_inactive = after_second_inactive,
        }
    end, renderer_config())

    expect.equality(result.current, result.second)
    expect.no_equality(result.first, result.second)
    expect.equality(result.after_inactive, { row = 0, col = 0, position = 0 })
    expect.equality(result.after_current, { row = 1, col = 1, position = 1 })
    expect.equality(result.after_second_inactive, result.after_current)
end

T["repairs external hide mutations from cursor overlap state"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.config").set(base_config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local cursor_col = 2
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            return 2
        end)
        rawset(vim.fn, "screencol", function()
            return cursor_col
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            return { 1, 5 }
        end)

        local state = assert(renderer.render(source_win))
        local corrupted_visible = vim.api.nvim_win_get_config(state.float_win)
        corrupted_visible.hide = true
        vim.api.nvim_win_set_config(state.float_win, corrupted_visible)
        renderer.render(source_win)
        local repaired_visible = vim.api.nvim_win_get_config(state.float_win).hide

        cursor_col = 6
        renderer.render(source_win)
        local corrupted_hidden = vim.api.nvim_win_get_config(state.float_win)
        corrupted_hidden.hide = false
        vim.api.nvim_win_set_config(state.float_win, corrupted_hidden)
        renderer.render(source_win)
        local repaired_hidden = vim.api.nvim_win_get_config(state.float_win).hide

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return {
            repaired_visible = repaired_visible,
            repaired_hidden = repaired_hidden,
            hidden_by_cursor = state.hidden_by_cursor,
        }
    end, renderer_config())

    expect.equality(result, {
        repaired_visible = false,
        repaired_hidden = true,
        hidden_by_cursor = true,
    })
end

T["resets cursor-hidden state across autohide concealment and recreation"] = function()
    local child = new_child()
    local result = child.lua_func(function(base_config)
        local lines = {}
        for index = 1, 120 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        base_config.autohide = { enabled = true, delay_ms = 500 }
        require("scrollbar.config").set(base_config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()

        local cursor_col = 6
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            return 2
        end)
        rawset(vim.fn, "screencol", function()
            return cursor_col
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            return { 1, 5 }
        end)

        assert(renderer.reveal(source_win))
        local hidden = assert(renderer.render(source_win))
        local old_float = hidden.float_win
        local old_buffer = hidden.float_buf
        assert(renderer.conceal(source_win))

        cursor_col = 2
        assert(renderer.reveal(source_win))
        local restored = assert(renderer.render(source_win))

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return {
            hidden = hidden.hidden_by_cursor,
            recreated_visible = not restored.hidden_by_cursor
                and vim.api.nvim_win_get_config(restored.float_win).hide == false,
            replaced = restored.float_win ~= old_float
                and restored.float_buf ~= old_buffer
                and not vim.api.nvim_win_is_valid(old_float)
                and not vim.api.nvim_buf_is_valid(old_buffer),
        }
    end, renderer_config())

    expect.equality(result, { hidden = true, recreated_visible = true, replaced = true })
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

        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        rawset(vim.fn, "screenrow", function()
            return 1
        end)
        rawset(vim.fn, "screencol", function()
            return 1
        end)
        rawset(vim.api, "nvim_win_get_position", function()
            return { 0, 0 }
        end)

        vim.api.nvim_set_current_win(first)
        local close_state = assert(renderer.render(first))
        local window_state_hidden = close_state.hidden_by_cursor
        local closed_float = close_state.float_win
        local closed_buffer = close_state.float_buf
        vim.api.nvim_win_close(first, true)
        local window_cleanup = renderer.get_state(first) == nil
            and not vim.api.nvim_win_is_valid(closed_float)
            and not vim.api.nvim_buf_is_valid(closed_buffer)

        local reset_state = assert(renderer.render(second))
        local reset_state_hidden = reset_state.hidden_by_cursor
        local reset_float = reset_state.float_win
        renderer.setup()
        local setup_cleanup = renderer.get_state(second) == nil and not vim.api.nvim_win_is_valid(reset_float)

        local hidden_state = assert(renderer.render(second))
        local hide_state_hidden = hidden_state.hidden_by_cursor
        local hidden_owned = renderer.is_owned_window(hidden_state.float_win)
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
        local buffer_state_hidden = buffer_state.hidden_by_cursor
        local buffer_float = buffer_state.float_win
        vim.api.nvim_win_set_buf(second, vim.api.nvim_create_buf(true, false))
        vim.api.nvim_buf_delete(source_buffer, { force = true })
        local buffer_cleanup = renderer.get_state(second) == nil and not vim.api.nvim_win_is_valid(buffer_float)

        vim.cmd("tabnew")
        local tab_source = vim.api.nvim_get_current_win()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local tab_state = assert(renderer.render(tab_source))
        local tab_state_hidden = tab_state.hidden_by_cursor
        local tab_float = tab_state.float_win
        vim.cmd("tabclose")
        local tab_cleanup = renderer.get_state(tab_source) == nil and not vim.api.nvim_win_is_valid(tab_float)

        local dispose_state = assert(renderer.render(second))
        local dispose_state_hidden = dispose_state.hidden_by_cursor
        local dispose_float = dispose_state.float_win
        local dispose_buffer = dispose_state.float_buf
        renderer.dispose()
        local dispose_cleanup = renderer.get_state(second) == nil
            and not vim.api.nvim_win_is_valid(dispose_float)
            and not vim.api.nvim_buf_is_valid(dispose_buffer)

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)

        return {
            window_state_hidden = window_state_hidden,
            window_cleanup = window_cleanup,
            reset_state_hidden = reset_state_hidden,
            setup_cleanup = setup_cleanup,
            hide_state_hidden = hide_state_hidden,
            hidden_owned = hidden_owned,
            hide_cleanup = hide_cleanup,
            show_recreated = show_recreated,
            toggle_hidden = toggle_hidden,
            toggle_shown = toggle_shown,
            buffer_state_hidden = buffer_state_hidden,
            buffer_cleanup = buffer_cleanup,
            tab_state_hidden = tab_state_hidden,
            tab_cleanup = tab_cleanup,
            dispose_state_hidden = dispose_state_hidden,
            dispose_cleanup = dispose_cleanup,
        }
    end, renderer_config())

    expect.equality(result, {
        window_state_hidden = true,
        window_cleanup = true,
        reset_state_hidden = true,
        setup_cleanup = true,
        hide_state_hidden = true,
        hidden_owned = true,
        hide_cleanup = true,
        show_recreated = true,
        toggle_hidden = true,
        toggle_shown = true,
        buffer_state_hidden = true,
        buffer_cleanup = true,
        tab_state_hidden = true,
        tab_cleanup = true,
        dispose_state_hidden = true,
        dispose_cleanup = true,
    })
end

return T
