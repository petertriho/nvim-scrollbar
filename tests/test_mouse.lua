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

local function mouse_config(overrides)
    return vim.tbl_deep_extend("force", {
        show = true,
        set_highlights = true,
        render = { interval_ms = 0, geometry = "line" },
        float = { width = 2, placement = { relative = "window", anchor = "NW", row = 0, col = 5 } },
        mouse = { enabled = true },
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

local function input_mouse(child, action, row, col)
    child.api.nvim_input_mouse("left", action, "", 0, row, col)
    vim.uv.sleep(30)
end

local function highlight_groups(child, float_buf)
    return child.lua_func(function(bufnr)
        local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
        local groups = {}
        for _, extmark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, namespace, 0, -1, { details = true })) do
            groups[extmark[4].hl_group] = true
        end
        return groups
    end, float_buf)
end

local function setup_single(child, options)
    options = options or {}
    local result = child.lua_func(function(opts)
        vim.o.mouse = "a"
        if opts.chrome then
            vim.o.showtabline = 2
            vim.o.laststatus = 2
            vim.o.cmdheight = 0
            vim.o.tabline = "TABLINE"
            vim.o.statusline = "STATUSLINE"
        end
        local lines = {}
        for index = 1, opts.line_count do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, opts.height)
        if opts.chrome then
            vim.api.nvim_set_option_value("winbar", "WINBAR", { win = source_win })
        end
        for _, fold in ipairs(opts.folds or {}) do
            vim.api.nvim_win_call(source_win, function()
                vim.cmd(string.format("%d,%dfold", fold[1], fold[2]))
            end)
        end

        local active_config = require("scrollbar.config").set(opts.config)
        local source_buf = vim.api.nvim_win_get_buf(source_win)
        if opts.marks and #opts.marks > 0 then
            assert(require("scrollbar.store").set("mouse-test", source_buf, opts.marks))
        end
        if opts.compact_search then
            local compact = require("scrollbar.providers.search_compact").encode(opts.compact_search)
            assert(require("scrollbar.store")._set_search_compact(source_buf, compact))
        end
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        local mouse = require("scrollbar.mouse")
        renderer.setup()
        if active_config.set_highlights then
            require("scrollbar.utils").set_highlights()
        end
        scheduler.setup({ config = active_config, renderer = renderer })
        mouse.setup({ config = active_config, renderer = renderer, scheduler = scheduler })
        local state = assert(renderer.render(source_win))
        vim.cmd("redraw")
        local position = vim.fn.win_screenpos(state.float_win)
        local source_position = vim.fn.win_screenpos(source_win)
        local raw_height = vim.api.nvim_win_get_height(source_win)
        local winbar_rows = vim.api.nvim_get_option_value("winbar", { win = source_win }) == "" and 0 or 1
        return {
            source_win = source_win,
            source_buf = source_buf,
            float_win = state.float_win,
            float_buf = state.float_buf,
            position = { source_position[1] - 1 + winbar_rows, position[2] - 1 },
            height = state.height,
            raw_height = raw_height,
            statusline_row = source_position[1] + raw_height - 1,
            handle = state.handle,
            hitmap = state.hitmap,
            geometry = state.geometry,
        }
    end, {
        line_count = options.line_count or 200,
        height = options.height or 10,
        config = options.config or mouse_config(),
        marks = options.marks or {},
        compact_search = options.compact_search,
        folds = options.folds or {},
        chrome = options.chrome or false,
    })
    vim.uv.sleep(30)
    return result
end

local function click(child, setup, row, display_col)
    local screen_row = setup.position[1] + row
    local screen_col = setup.position[2] + display_col - 1
    input_mouse(child, "press", screen_row, screen_col)
    input_mouse(child, "release", screen_row, screen_col)
end

local function drag(child, setup, press_row, release_row, display_col)
    local screen_col = setup.position[2] + display_col - 1
    input_mouse(child, "press", setup.position[1] + press_row, screen_col)
    input_mouse(child, "drag", setup.position[1] + release_row, screen_col)
    input_mouse(child, "release", setup.position[1] + release_row, screen_col)
end

local function reset_view(child, setup, line)
    local refreshed = child.lua_func(function(source_win, target_line)
        vim.api.nvim_set_current_win(source_win)
        vim.api.nvim_win_set_cursor(source_win, { target_line, 0 })
        vim.api.nvim_win_call(source_win, function()
            vim.cmd("normal! zt")
        end)
        local state = assert(require("scrollbar.renderer").render(source_win))
        vim.cmd("redraw")
        local position = vim.fn.win_screenpos(state.float_win)
        local source_position = vim.fn.win_screenpos(source_win)
        local raw_height = vim.api.nvim_win_get_height(source_win)
        local winbar_rows = vim.api.nvim_get_option_value("winbar", { win = source_win }) == "" and 0 or 1
        return {
            source_win = source_win,
            source_buf = state.source_buf,
            float_win = state.float_win,
            float_buf = state.float_buf,
            position = { source_position[1] - 1 + winbar_rows, position[2] - 1 },
            height = state.height,
            raw_height = raw_height,
            statusline_row = source_position[1] + raw_height - 1,
            handle = state.handle,
            hitmap = state.hitmap,
            geometry = state.geometry,
        }
    end, setup.source_win, line)
    vim.uv.sleep(30)
    return refreshed
end

T["keeps the handle pressed highlight through drag until release"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        config = mouse_config({
            marks = {
                Custom = { text = "!", column = 2, priority = 10, highlight = "Special" },
            },
        }),
        marks = { { line = 0, type = "Custom" } },
    })
    local screen_col = setup.position[2] + setup.handle.column - 1
    expect.equality(highlight_groups(child, setup.float_buf).ScrollbarCustomHandle, true)

    input_mouse(child, "press", setup.position[1] + setup.handle.first_row, screen_col)
    expect.equality(highlight_groups(child, setup.float_buf).ScrollbarCustomHandlePressed, true)

    input_mouse(child, "drag", setup.position[1] + setup.height - 1, screen_col)
    expect.equality(highlight_groups(child, setup.float_buf).ScrollbarHandlePressed, true)

    input_mouse(child, "release", setup.position[1] + setup.height - 1, screen_col)
    local released = highlight_groups(child, setup.float_buf)
    expect.equality(released.ScrollbarHandlePressed, nil)
    expect.equality(released.ScrollbarHandle, true)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
end

T["keeps corrected bottom-row clicks and drags above the statusline"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        line_count = 200,
        height = 10,
        chrome = true,
    })

    expect.equality(setup.height, setup.raw_height - 1)
    expect.equality(#setup.hitmap, setup.height)
    expect.equality(setup.position[1] + setup.height <= setup.statusline_row, true)

    local bottom_row = setup.position[1] + setup.height - 1
    input_mouse(child, "press", bottom_row, setup.position[2])
    local interaction = child.lua_get([[require("scrollbar.mouse").get_interaction()]])
    expect.equality(interaction.pressed_row, setup.height - 1)
    input_mouse(child, "release", bottom_row, setup.position[2])
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 200)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)

    setup = reset_view(child, setup, 1)
    drag(child, setup, setup.handle.first_row, setup.height - 1, setup.handle.column)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 200)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)

    input_mouse(child, "press", setup.statusline_row, setup.position[2])
    input_mouse(child, "release", setup.statusline_row, setup.position[2])
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
    expect.equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)
end

T["clicks an empty track cell proportionally and restores source focus"] = function()
    local child = new_child()
    local setup = child.lua_func(function(config)
        vim.o.mouse = "a"
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.cmd("split")
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 10)

        local active_config = require("scrollbar.config").set(config)
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        local mouse = require("scrollbar.mouse")
        renderer.setup()
        if active_config.set_highlights then
            require("scrollbar.utils").set_highlights()
        end
        scheduler.setup({ config = active_config, renderer = renderer })
        mouse.setup({ config = active_config, renderer = renderer, scheduler = scheduler })
        local state = assert(renderer.render(source_win))
        vim.cmd("redraw")
        local position = vim.fn.win_screenpos(state.float_win)
        return {
            source_win = source_win,
            float_win = state.float_win,
            float_buf = state.float_buf,
            row = position[1] + state.height - 2,
            col = position[2] - 1,
        }
    end, mouse_config())

    expect.equality(child.o.mouse, "a")
    input_mouse(child, "press", setup.row, setup.col)
    expect.equality(child.api.nvim_get_current_win(), setup.float_win)
    expect.no_equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)
    expect.equality(highlight_groups(child, setup.float_buf).ScrollbarHandlePressed, nil)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 1)
    input_mouse(child, "release", setup.row, setup.col)

    local result = child.lua_func(function(source_win, float_buf)
        local mappings = vim.api.nvim_buf_get_keymap(float_buf, "n")
        local lhs = {}
        for _, mapping in ipairs(mappings) do
            lhs[mapping.lhs] = true
        end
        local global_lhs = {}
        for _, mapping in ipairs(vim.api.nvim_get_keymap("n")) do
            global_lhs[mapping.lhs] = true
        end
        return {
            current_win = vim.api.nvim_get_current_win(),
            cursor = vim.api.nvim_win_get_cursor(source_win),
            left_mouse = lhs["<LeftMouse>"] == true,
            left_drag = lhs["<LeftDrag>"] == true,
            left_release = lhs["<LeftRelease>"] == true,
            global_left_mouse = global_lhs["<LeftMouse>"] == true,
            global_left_drag = global_lhs["<LeftDrag>"] == true,
            global_left_release = global_lhs["<LeftRelease>"] == true,
        }
    end, setup.source_win, setup.float_buf)

    expect.equality(result.current_win, setup.source_win)
    expect.equality(result.cursor[1], 200)
    expect.equality(result.left_mouse, true)
    expect.equality(result.left_drag, true)
    expect.equality(result.left_release, true)
    expect.equality(result.global_left_mouse, false)
    expect.equality(result.global_left_drag, false)
    expect.equality(result.global_left_release, false)

    local disposed_mappings = child.lua_func(function(float_buf)
        require("scrollbar.mouse").dispose()
        return vim.api.nvim_buf_get_keymap(float_buf, "n")
    end, setup.float_buf)
    expect.equality(disposed_mappings, {})
end

T["uses direct rows and clamps trailing space when short content fits"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        line_count = 5,
        height = 10,
        marks = { { line = 2, type = "Misc" } },
    })

    expect.equality(setup.hitmap[3][1].line, 2)
    click(child, setup, 2, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 3)

    click(child, setup, 6, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 5)
end

T["uses direct screen rows when short rendered content fits"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        line_count = 5,
        height = 10,
        config = mouse_config({ render = { geometry = "screen" } }),
    })

    expect.equality(setup.geometry.mode, "screen")
    click(child, setup, 6, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 5)
end

T["does not turn movement into a drag when the press starts outside the handle column"] = function()
    local child = new_child()
    local setup = setup_single(child)
    drag(child, setup, 5, setup.height - 1, 1)

    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 112)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
end

T["jumps to the exact visible mark selected by display column"] = function()
    local child = new_child()
    local config = mouse_config({
        float = { width = 3 },
        handle = { column = 3, width = 1 },
        marks = {
            Misc = { text = "A", column = 1 },
            Search = { text = "B", column = 2 },
        },
    })
    local setup = setup_single(child, {
        config = config,
        marks = {
            { line = 100, type = "Misc" },
            { line = 110, type = "Search" },
        },
    })

    local mark_row
    for row, cells in ipairs(setup.hitmap) do
        if cells[2].line == 110 then
            mark_row = row - 1
        end
    end
    expect.no_equality(mark_row, nil)

    local mark_screen_row = setup.position[1] + mark_row
    local mark_screen_col = setup.position[2] + 1
    input_mouse(child, "press", mark_screen_row, mark_screen_col)
    expect.no_equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)
    input_mouse(child, "release", mark_screen_row, mark_screen_col)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 111)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)

    setup = reset_view(child, setup, 1)
    click(child, setup, mark_row, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 101)
end

T["compact search marks keep the ordinary exact click target"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        config = mouse_config({
            marks = { Search = { text = { "-", "=" }, column = 1 } },
        }),
        compact_search = { 20, 20, 21 },
    })

    local mark_row
    for row, cells in ipairs(setup.hitmap) do
        if cells[1].line == 20 then
            mark_row = row - 1
        end
    end
    expect.no_equality(mark_row, nil)
    expect.equality(setup.hitmap[mark_row + 1][1].lines, { 20, 20, 21 })
    click(child, setup, mark_row, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 21)
end

T["keeps a mark-over-handle press as an exact mark click without movement"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        config = mouse_config({
            float = { width = 1 },
            handle = { column = 1, width = 1 },
            marks = { Misc = { text = "M", column = 1 } },
        }),
        marks = { { line = 20, type = "Misc" } },
    })

    local mark_row
    for row, cells in ipairs(setup.hitmap) do
        if cells[1].line == 20 then
            mark_row = row - 1
        end
    end
    expect.equality(mark_row, 0)
    expect.equality(setup.hitmap[mark_row + 1][1].handle, true)

    click(child, setup, mark_row, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 21)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
end

T["turns a mark-over-handle press into a handle drag after movement"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        config = mouse_config({
            float = { width = 1 },
            handle = { column = 1, width = 1 },
            marks = { Misc = { text = "M", column = 1 } },
        }),
        marks = { { line = 20, type = "Misc" } },
    })
    local screen_col = setup.position[2]
    input_mouse(child, "press", setup.position[1], screen_col)
    input_mouse(child, "drag", setup.position[1] + 5, screen_col)
    local active = child.lua_get([[require("scrollbar.mouse").get_interaction()]])
    expect.equality(active.dragging, true)
    input_mouse(child, "release", setup.position[1] + 5, screen_col)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 112)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
end

T["drags to top middle and bottom while preserving the handle grab offset"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        line_count = 30,
        height = 10,
        config = mouse_config(),
    })
    expect.equality(setup.handle.first_row, 0)
    expect.equality(setup.handle.last_row, 2)

    local cases = {
        { release_row = 0, expected_line = 1 },
        { release_row = 5, expected_line = 17 },
        { release_row = 9, expected_line = 30 },
    }
    for _, case in ipairs(cases) do
        setup = reset_view(child, setup, 1)
        drag(child, setup, 1, case.release_row, 2)
        expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], case.expected_line)
        expect.equality(child.api.nvim_get_current_win(), setup.source_win)
    end
end

T["opens only the fold containing an exact mark target"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        line_count = 100,
        folds = { { 40, 60 }, { 70, 80 } },
        marks = { { line = 49, type = "Misc" } },
    })
    local mark_row
    for row, cells in ipairs(setup.hitmap) do
        if cells[1].line == 49 then
            mark_row = row - 1
        end
    end

    local before = child.lua_func(function(source_win)
        return vim.api.nvim_win_call(source_win, function()
            return { vim.fn.foldclosed(50), vim.fn.foldclosed(75) }
        end)
    end, setup.source_win)
    expect.equality(before, { 40, 70 })

    click(child, setup, mark_row, 1)
    local after = child.lua_func(function(source_win)
        return vim.api.nvim_win_call(source_win, function()
            return {
                cursor = vim.api.nvim_win_get_cursor(source_win)[1],
                target_fold = vim.fn.foldclosed(50),
                other_fold = vim.fn.foldclosed(75),
            }
        end)
    end, setup.source_win)
    expect.equality(after.cursor, 50)
    expect.equality(after.target_fold, -1)
    expect.equality(after.other_fold, 70)
end

T["uses screen geometry when reverse-mapping an empty track click"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        line_count = 100,
        folds = { { 1, 80 } },
        config = mouse_config({ render = { geometry = "screen" } }),
    })
    expect.equality(setup.geometry.mode, "screen")

    click(child, setup, 5, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1] > 80, true)
end

T["keeps independent ownership for multiple source windows"] = function()
    local child = new_child()
    local setup = child.lua_func(function(config)
        vim.o.mouse = "a"
        local lines = {}
        for index = 1, 200 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        vim.api.nvim_win_call(first, function()
            vim.api.nvim_win_set_cursor(first, { 1, 0 })
            vim.cmd("normal! zt")
        end)
        vim.api.nvim_win_call(second, function()
            vim.api.nvim_win_set_cursor(second, { 150, 0 })
            vim.cmd("normal! zt")
        end)

        local active_config = require("scrollbar.config").set(config)
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        local mouse = require("scrollbar.mouse")
        renderer.setup()
        if active_config.set_highlights then
            require("scrollbar.utils").set_highlights()
        end
        scheduler.setup({ config = active_config, renderer = renderer })
        mouse.setup({ config = active_config, renderer = renderer, scheduler = scheduler })
        local first_state = assert(renderer.render(first))
        local second_state = assert(renderer.render(second))
        vim.cmd("redraw")
        local first_position = vim.fn.win_screenpos(first_state.float_win)
        local second_position = vim.fn.win_screenpos(second_state.float_win)
        return {
            first = {
                source_win = first,
                position = { first_position[1] - 1, first_position[2] - 1 },
                height = first_state.height,
            },
            second = {
                source_win = second,
                position = { second_position[1] - 1, second_position[2] - 1 },
                height = second_state.height,
            },
        }
    end, mouse_config())
    vim.uv.sleep(30)
    child.cmd("redraw")

    click(child, setup.first, setup.first.height - 1, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.first.source_win)[1], 200)
    expect.equality(child.api.nvim_win_get_cursor(setup.second.source_win)[1], 150)
    expect.equality(child.api.nvim_get_current_win(), setup.first.source_win)

    click(child, setup.second, 0, 1)
    expect.equality(child.api.nvim_win_get_cursor(setup.first.source_win)[1], 200)
    expect.equality(child.api.nvim_win_get_cursor(setup.second.source_win)[1], 1)
    expect.equality(child.api.nvim_get_current_win(), setup.second.source_win)
end

T["does not attach mappings or mutate mouse behavior when disabled"] = function()
    local child = new_child()
    local setup = setup_single(child, {
        config = mouse_config({ mouse = { enabled = false } }),
    })
    local before = child.lua_func(function(float_win, float_buf)
        return {
            mouse_option = vim.o.mouse,
            float_config = vim.api.nvim_win_get_config(float_win),
            mappings = vim.api.nvim_buf_get_keymap(float_buf, "n"),
        }
    end, setup.float_win, setup.float_buf)

    click(child, setup, setup.height - 1, 1)
    expect.equality(before.mouse_option, "a")
    expect.equality(before.float_config.focusable, false)
    expect.equality(before.float_config.mouse, false)
    expect.equality(before.mappings, {})
    expect.equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
end

T["restores focus when release handling errors"] = function()
    local child = new_child()
    local setup = setup_single(child)
    local row = setup.position[1] + setup.handle.first_row
    local col = setup.position[2] + setup.handle.column - 1
    input_mouse(child, "press", row, col)
    expect.no_equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)
    expect.equality(highlight_groups(child, setup.float_buf).ScrollbarHandlePressed, true)
    child.lua([[require("scrollbar.layout").track_row_to_line = function() error("mouse test failure") end]])
    input_mouse(child, "release", row, col)

    expect.equality(highlight_groups(child, setup.float_buf).ScrollbarHandlePressed, nil)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
    expect.equality(child.api.nvim_win_get_cursor(setup.source_win)[1], 1)
    expect.equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)
end

T["cancels safely when the float or source closes mid-interaction"] = function()
    local child = new_child()
    local setup = setup_single(child)
    local row = setup.position[1] + setup.height - 1
    local col = setup.position[2]
    input_mouse(child, "press", row, col)
    child.api.nvim_win_close(setup.float_win, true)
    vim.uv.sleep(20)
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
    expect.equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)

    setup = reset_view(child, setup, 1)
    row = setup.position[1] + setup.height - 1
    col = setup.position[2]
    input_mouse(child, "press", row, col)
    child.api.nvim_win_close(setup.source_win, true)
    vim.uv.sleep(20)
    expect.equality(child.lua_get([[require("scrollbar.mouse").get_interaction()]]), vim.NIL)
    expect.equality(child.api.nvim_win_is_valid(setup.source_win), false)
    expect.equality(child.api.nvim_win_is_valid(child.api.nvim_get_current_win()), true)
end

return T
