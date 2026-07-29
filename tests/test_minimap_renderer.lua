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

local function reset_modules(child)
    child.lua([[
        for _, module in pairs({
            "scrollbar.config",
            "scrollbar.providers",
            "scrollbar.store",
            "scrollbar.minimap.config",
            "scrollbar.minimap.highlights",
            "scrollbar.minimap.semantic",
            "scrollbar.minimap.worker",
            "scrollbar.minimap.overlays",
            "scrollbar.minimap.renderer",
        }) do
            package.loaded[module] = nil
        end
        require("scrollbar.config").set({ scrollbar = {} })
    ]])
end

local function configure(child, minimap_overrides)
    child.lua_func(function(overrides)
        require("scrollbar.config").set({ scrollbar = {}, minimap = overrides or {} })
        local minimap_config = require("scrollbar.minimap.config")
        local worker = require("scrollbar.minimap.worker")
        worker.setup({
            backend = "sync",
            on_result = function(payload)
                require("scrollbar.minimap.renderer").handle_worker_result(payload)
            end,
        })
        require("scrollbar.minimap.overlays").setup({
            config = minimap_config.get(),
        })
        require("scrollbar.minimap.renderer").setup({
            worker = worker,
            overlays = require("scrollbar.minimap.overlays"),
        })
    end, minimap_overrides)
end

local function render_mark_ranges(child, content_glyph)
    return child.lua_func(function(glyph)
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 3,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                content_glyph = glyph,
            },
        })
        local renderer = require("scrollbar.minimap.renderer")
        local worker = {
            request = function(request)
                renderer.handle_worker_result({
                    bufnr = request.bufnr,
                    signature = request.signature,
                    max_line_width = 3,
                    cells = {
                        {
                            { char = "█", hl_group = "ErrorMsg" },
                            { char = "█", hl_group = "WarningMsg" },
                            { char = "█", hl_group = "Comment" },
                        },
                    },
                })
                return true
            end,
        }
        renderer.setup({
            worker = worker,
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
        local state = assert(renderer.render(0))
        local ranges = {}
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, {
                details = true,
            }))
        do
            ranges[mark[4].hl_group] = { mark[3], mark[4].end_col }
        end
        return { row = state.rows[1], ranges = ranges }
    end, content_glyph)
end

local function render_overlay_marks(child, options)
    return child.lua_func(function(opts)
        local overrides = {
            enabled = true,
            width = 6,
            height = 2,
            set_highlights = false,
            show_viewport = false,
            overlays = { enabled = true, types = { Error = {}, Search = {} } },
        }
        if opts.glyph ~= nil then
            overrides.content_glyph = opts.glyph
        end
        require("scrollbar.config").set({ scrollbar = {}, minimap = overrides })
        local renderer = require("scrollbar.minimap.renderer")
        local worker = {
            request = function(request)
                renderer.handle_worker_result({
                    bufnr = request.bufnr,
                    signature = request.signature,
                    max_line_width = 6,
                    cells = {
                        {
                            { char = "█" },
                            { char = "█" },
                            { char = " " },
                            { char = " " },
                            { char = "█" },
                            { char = "█" },
                        },
                        {
                            { char = " " },
                            { char = " " },
                            { char = " " },
                            { char = " " },
                            { char = " " },
                            { char = " " },
                        },
                    },
                })
                return true
            end,
        }
        renderer.setup({
            worker = worker,
            overlays = {
                project_with = function(source_win)
                    opts.projected_source_win = source_win
                    return {
                        {
                            source_line = 0,
                            minimap_row = 1,
                            mark_type = "Error",
                            priority = 2,
                            highlight = "ScrollbarMinimapError",
                            provider = "diagnostic",
                        },
                        {
                            source_line = 1,
                            minimap_row = 2,
                            mark_type = "Search",
                            priority = 1,
                            highlight = "ScrollbarMinimapSearch",
                            provider = "search",
                        },
                    }
                end,
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "aaaaaa", "" })
        local state = assert(renderer.render(0))
        local marks = {}
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, {
                details = true,
            }))
        do
            local details = mark[4]
            marks[#marks + 1] = {
                row = mark[2] + 1,
                start_col = mark[3],
                end_col = details.end_col,
                highlight = details.hl_group,
                priority = details.priority,
            }
        end
        return {
            rows = state.rows,
            marks = marks,
            cursor_col = state.cursor_col,
            projected_source_win = opts.projected_source_win,
            source_win = vim.api.nvim_get_current_win(),
        }
    end, options)
end

T["renders a sync squash grid into the minimap buffer"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 3,
        height = 2,
        set_highlights = false,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "defghi" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        return {
            rows = state.rows,
            height = state.height,
            width = state.width,
        }
    end)

    expect.no_equality(result.rows, nil)
    expect.equality(result.height, 2)
    expect.equality(result.width, 3)
    expect.equality(result.rows[1], "██ ")
    expect.equality(result.rows[2], "███")
end

T["content_glyph remaps every occupied cell"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 3,
        height = 2,
        set_highlights = false,
        show_viewport = false,
        content_glyph = "▌",
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "defghi" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        return { rows = state.rows }
    end)

    expect.equality(result.rows[1], "▌▌ ")
    expect.equality(result.rows[2], "▌▌▌")
end

T["highlight ranges align with complete UTF-8 content glyphs"] = function()
    local child = new_child()
    reset_modules(child)

    local result = render_mark_ranges(child, "█")

    expect.equality(result.row, "███")
    expect.equality(result.ranges.ErrorMsg, { 0, 3 })
    expect.equality(result.ranges.WarningMsg, { 3, 6 })
    expect.equality(result.ranges.Comment, { 6, 9 })
end

T["highlight ranges align with custom multibyte and ASCII cells"] = function()
    local child = new_child()
    reset_modules(child)

    local multibyte = render_mark_ranges(child, "▌")
    expect.equality(multibyte.row, "▌▌▌")
    expect.equality(multibyte.ranges.ErrorMsg, { 0, 3 })
    expect.equality(multibyte.ranges.WarningMsg, { 3, 6 })
    expect.equality(multibyte.ranges.Comment, { 6, 9 })

    reset_modules(child)
    local ascii = render_mark_ranges(child, "#")
    expect.equality(ascii.row, "###")
    expect.equality(ascii.ranges.ErrorMsg, { 0, 1 })
    expect.equality(ascii.ranges.WarningMsg, { 1, 2 })
    expect.equality(ascii.ranges.Comment, { 2, 3 })
end

T["setup registers ownership markers on minimap floats and excludes external windows"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        return {
            float_win = state.float_win,
            float_buf = state.float_buf,
            source_win = vim.api.nvim_get_current_win(),
            source_buf = vim.api.nvim_get_current_buf(),
        }
    end)

    local owned = child.lua_func(function(args)
        local renderer = require("scrollbar.minimap.renderer")
        return {
            own_float_win = renderer.is_owned_window(args.float_win),
            own_float_buf = renderer.is_owned_buffer(args.float_buf),
            external_win = renderer.is_owned_window(args.source_win),
            external_buf = renderer.is_owned_buffer(args.source_buf),
        }
    end, result)

    expect.equality(owned.own_float_win, true)
    expect.equality(owned.own_float_buf, true)
    expect.equality(owned.external_win, false)
    expect.equality(owned.external_buf, false)
end

T["placement NW window relative puts the float at top-left of source window"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
        float = { placement = { relative = "window", anchor = "NW", row = 0, col = 0 } },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        return vim.api.nvim_win_get_config(state.float_win)
    end)

    expect.equality(result.relative, "win")
    expect.equality(result.anchor, "NW")
    expect.equality(result.row, 0)
    expect.equality(result.col, 0)
    expect.equality(result.width, 4)
    expect.equality(result.height, 4)
end

T["placement NE window relative follows each source window right edge"] = function()
    local child = new_child()
    reset_modules(child)
    child.o.columns = 100
    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
        float = { placement = { relative = "window", anchor = "NE", row = 0, col = 0 } },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local first = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        local second = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.minimap.renderer")

        local first_state = assert(renderer.render(first))
        local second_state = assert(renderer.render(second))
        local before = {
            first_width = vim.api.nvim_win_get_width(first),
            first_col = vim.api.nvim_win_get_config(first_state.float_win).col,
            second_width = vim.api.nvim_win_get_width(second),
            second_col = vim.api.nvim_win_get_config(second_state.float_win).col,
        }

        vim.api.nvim_win_set_width(first, 30)
        first_state = assert(renderer.render(first))
        second_state = assert(renderer.render(second))
        local after = {
            first_width = vim.api.nvim_win_get_width(first),
            first_col = vim.api.nvim_win_get_config(first_state.float_win).col,
            second_width = vim.api.nvim_win_get_width(second),
            second_col = vim.api.nvim_win_get_config(second_state.float_win).col,
        }

        return { before = before, after = after }
    end)

    expect.equality(result.before.first_col, result.before.first_width)
    expect.equality(result.before.second_col, result.before.second_width)
    expect.no_equality(result.after.first_width, result.before.first_width)
    expect.equality(result.after.first_col, result.after.first_width)
    expect.equality(result.after.second_col, result.after.second_width)
end

T["placement SE editor relative anchors to bottom-right of the editor"] = function()
    local child = new_child()
    reset_modules(child)
    child.o.lines = 30
    child.o.columns = 100
    configure(child, {
        enabled = true,
        width = 5,
        height = 5,
        float = { placement = { relative = "editor", anchor = "SE", row = 0, col = 0 } },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local cfg = vim.api.nvim_win_get_config(state.float_win)
        return {
            relative = cfg.relative,
            anchor = cfg.anchor,
            row = cfg.row,
            col = cfg.col,
            width = cfg.width,
            height = cfg.height,
            expected_row = vim.api.nvim_win_get_height(0),
            expected_col = vim.o.columns,
        }
    end)

    expect.equality(result.relative, "editor")
    expect.equality(result.anchor, "SE")
    expect.equality(result.row, result.expected_row)
    expect.equality(result.col, result.expected_col)
    expect.equality(result.width, 5)
    expect.equality(result.height, 5)
end

T["viewport tint highlights the projected source viewport rows without changing text"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
    })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 20 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local namespace = renderer.namespace()
        local viewport_spans = {}
        for row = 0, state.height - 1 do
            local marks = vim.api.nvim_buf_get_extmarks(
                state.float_buf,
                namespace,
                { row, 0 },
                { row, -1 },
                { details = true }
            )
            for _, mark in ipairs(marks) do
                local details = mark[4]
                if details and details.hl_group == "ScrollbarMinimapViewport" then
                    viewport_spans[#viewport_spans + 1] = {
                        row = row + 1,
                        start_col = mark[3],
                        end_col = details.end_col,
                        row_bytes = #state.rows[row + 1],
                    }
                    break
                end
            end
        end
        return {
            rows = state.rows,
            viewport_spans = viewport_spans,
        }
    end)

    expect.no_equality(#result.viewport_spans, 0)
    expect.equality(result.viewport_spans[1].row, 1)
    for _, span in ipairs(result.viewport_spans) do
        expect.equality(span.start_col, 0)
        expect.equality(span.end_col, span.row_bytes)
    end
    for _, row in ipairs(result.rows) do
        expect.equality(row:find("┌", 1, true), nil)
        expect.equality(row:find("─", 1, true), nil)
        expect.equality(row:find("│", 1, true), nil)
    end
end

T["content viewport marks and points share one terminal-row projection"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 1,
        height = 4,
        set_highlights = false,
        show_viewport = true,
        overlays = { enabled = true, types = { Error = {} } },
    })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 20 do
            lines[index] = ""
        end
        lines[11] = "x"
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_height(source_win, 4)
        vim.api.nvim_win_set_cursor(source_win, { 11, 0 })
        vim.cmd("normal! zt")

        local store = require("scrollbar.store")
        store.set("diagnostic", vim.api.nvim_get_current_buf(), { { line = 10, type = "Error" } })
        store.set_minimap_points("cursor", source_win, {
            { line = 10, col = 0, highlight = "ScrollbarMinimapCursor", priority = 14 },
        })

        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(source_win))
        local rows_by_highlight = {}
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, { details = true }))
        do
            local highlight = mark[4] and mark[4].hl_group
            if highlight ~= nil then
                rows_by_highlight[highlight] = mark[2] + 1
            end
        end
        local content_row
        for row, text in ipairs(state.rows) do
            if text == "█" then
                content_row = row
            end
        end
        return {
            content = content_row,
            viewport = rows_by_highlight.ScrollbarMinimapViewport,
            mark = rows_by_highlight.ScrollbarMinimapError,
            point = rows_by_highlight.ScrollbarMinimapCursor,
            cursor = state.cursor_row,
        }
    end)

    expect.equality(result, {
        content = 3,
        viewport = 3,
        mark = 3,
        point = 3,
        cursor = 3,
    })
end

T["cursor points project exact text whitespace and end-of-line columns"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 5,
        height = 3,
        set_highlights = false,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        local lines = { "abcd", "", "a   b", "", "abcde", "" }
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.store").set_minimap_points("cursor", source_win, {
            { line = 0, col = 2, highlight = "ScrollbarMinimapCursor", priority = 14 },
            { line = 2, col = 2, highlight = "ScrollbarMinimapCursor", priority = 14 },
            { line = 4, col = 5, highlight = "ScrollbarMinimapCursor", priority = 14 },
        })

        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(source_win))
        local positions = {}
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, {
                details = true,
            }))
        do
            if mark[4] and mark[4].hl_group == "ScrollbarMinimapCursor" then
                local row = mark[2] + 1
                local display_col = vim.fn.strdisplaywidth(state.rows[row]:sub(1, mark[3])) + 1
                positions[#positions + 1] = { row = row, col = display_col }
            end
        end
        table.sort(positions, function(left, right)
            if left.row == right.row then
                return left.col < right.col
            end
            return left.row < right.row
        end)
        return {
            positions = positions,
            cursor_row = state.cursor_row,
            cursor_col = state.cursor_col,
        }
    end)

    expect.equality(result.positions, {
        { row = 1, col = 3 },
        { row = 2, col = 3 },
        { row = 3, col = 5 },
    })
    expect.equality(result.cursor_row, 1)
    expect.equality(result.cursor_col, 3)
end

T["disabled cursor provider suppresses stored cursor points"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 1,
        set_highlights = false,
        show_viewport = false,
        providers = { cursor = false },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcd", "" })
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.store").set_minimap_points("cursor", source_win, {
            { line = 0, col = 2, highlight = "ScrollbarMinimapCursor", priority = 14 },
        })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(source_win))
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, {
                details = true,
            }))
        do
            if mark[4] and mark[4].hl_group == "ScrollbarMinimapCursor" then
                return true
            end
        end
        return false
    end)

    expect.equality(result, false)
end

T["mark and point changes rerender without requesting new cells"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 1,
        set_highlights = false,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcd", "" })
        local source_win = vim.api.nvim_get_current_win()
        local store = require("scrollbar.store")
        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end

        store.set_minimap_points("cursor", source_win, {
            { line = 0, col = 0, highlight = "ScrollbarMinimapCursor", priority = 14 },
        })
        local renderer = require("scrollbar.minimap.renderer")
        local before = assert(renderer.render(source_win))
        local first_requests = requests
        local first_col = before.cursor_col

        store.set_minimap_points("cursor", source_win, {
            { line = 0, col = 3, highlight = "ScrollbarMinimapCursor", priority = 14 },
        })
        local after = assert(renderer.render(source_win))
        store.set("diagnostic", vim.api.nvim_get_current_buf(), { { line = 0, type = "Error" } })
        renderer.render(source_win)
        worker.request = original_request
        return {
            first_requests = first_requests,
            final_requests = requests,
            first_col = first_col,
            final_col = after.cursor_col,
        }
    end)

    expect.equality(result.first_requests, 1)
    expect.equality(result.final_requests, 1)
    expect.equality(result.first_col, 1)
    expect.equality(result.final_col, 4)
end

T["overlay cells highlight projected rows when overlays are enabled"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
        show_viewport = false,
        overlays = { enabled = true, types = { Error = {} } },
    })

    local result = child.lua_func(function()
        local store = require("scrollbar.store")
        local lines = {}
        for index = 1, 16 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        store.set("diagnostic", vim.api.nvim_get_current_buf(), { { line = 1, type = "Error" } })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local namespace = renderer.namespace()
        local rows_with_overlay = {}
        for row = 0, state.height - 1 do
            local marks = vim.api.nvim_buf_get_extmarks(
                state.float_buf,
                namespace,
                { row, 0 },
                { row, -1 },
                { details = true }
            )
            for _, mark in ipairs(marks) do
                local details = mark[4]
                if details and details.hl_group == "ScrollbarMinimapError" then
                    rows_with_overlay[#rows_with_overlay + 1] = row + 1
                end
            end
        end
        return {
            rows_with_overlay = rows_with_overlay,
        }
    end)

    expect.no_equality(#result.rows_with_overlay, 0)
    for _, row in ipairs(result.rows_with_overlay) do
        expect.equality(row, 1)
    end
end

T["semantic overlays tint only contiguous occupied cell runs"] = function()
    local child = new_child()
    reset_modules(child)

    local result = render_overlay_marks(child, {})
    local error_ranges = {}
    local has_search = false
    for _, mark in ipairs(result.marks) do
        if mark.highlight == "ScrollbarMinimapError" then
            error_ranges[#error_ranges + 1] = { mark.start_col, mark.end_col }
        elseif mark.highlight == "ScrollbarMinimapSearch" then
            has_search = true
        end
    end

    expect.equality(result.rows, { "██  ██", "      " })
    expect.equality(error_ranges, { { 0, 6 }, { 8, 14 } })
    expect.equality(has_search, false)
    expect.equality(result.projected_source_win, result.source_win)
end

T["semantic occupancy is independent of custom glyph remapping"] = function()
    local child = new_child()
    reset_modules(child)

    local result = render_overlay_marks(child, {
        glyph = "a",
    })
    local ranges = {}
    for _, mark in ipairs(result.marks) do
        if mark.highlight == "ScrollbarMinimapError" then
            ranges[#ranges + 1] = { mark.start_col, mark.end_col }
        end
    end

    expect.equality(result.rows[1], "aa  aa")
    expect.equality(ranges, { { 0, 2 }, { 4, 6 } })
end

T["cache hit skips the worker request"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(req)
            requests = requests + 1
            return original_request(req)
        end
        local renderer = require("scrollbar.minimap.renderer")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
        assert(renderer.render(0))
        local first = requests
        renderer.render(0)
        local second = requests
        worker.request = original_request
        return { first = first, second = second }
    end)

    expect.equality(result.first, 1)
    expect.equality(result.second, 1)
end

T["content glyph changes reuse cached canonical cells"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 1,
        set_highlights = false,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcd" })
        local worker = require("scrollbar.minimap.worker")
        local original_request = worker.request
        local requests = 0
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end

        local renderer = require("scrollbar.minimap.renderer")
        local first = assert(renderer.render(0)).rows[1]
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 4,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                content_glyph = "#",
            },
        })
        local second = assert(renderer.render(0)).rows[1]
        worker.request = original_request
        return { first = first, second = second, requests = requests }
    end)

    expect.equality(result.first, "████")
    expect.equality(result.second, "####")
    expect.equality(result.requests, 1)
end

T["parent semantic spans recolor occupied cells and invalidate once per revision"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 3,
        height = 1,
        set_highlights = false,
        show_viewport = false,
        providers = { cursor = false, lsp_semantic_tokens = true },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a b", "" })
        local bufnr = vim.api.nvim_get_current_buf()
        local store = require("scrollbar.store")
        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end

        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {
            { line = 0, start_col = 0, end_col = 3, highlight = "FirstSemantic", priority = 10 },
        })
        local renderer = require("scrollbar.minimap.renderer")
        local first = assert(renderer.render(0))
        local first_requests = requests

        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {
            { line = 0, start_col = 0, end_col = 3, highlight = "SecondSemantic", priority = 10 },
        })
        local second = assert(renderer.render(0))
        local second_requests = requests
        renderer.render(0)
        local final_requests = requests
        worker.request = original_request

        local semantic_ranges = {}
        for _, span in ipairs(second.highlights[1]) do
            if span.highlight == "SecondSemantic" then
                semantic_ranges[#semantic_ranges + 1] = { span.start_col, span.end_col }
            end
        end
        return {
            first_requests = first_requests,
            second_requests = second_requests,
            final_requests = final_requests,
            first_cells_signature = first.cells_signature,
            second_cells_signature = second.cells_signature,
            semantic_ranges = semantic_ranges,
        }
    end)

    expect.equality(result.first_requests, 1)
    expect.equality(result.second_requests, 2)
    expect.equality(result.final_requests, 2)
    expect.equality(result.first_cells_signature, result.second_cells_signature)
    expect.equality(result.semantic_ranges, { { 1, 2 }, { 3, 4 } })
end

T["hide and show keep worker semantic revisions monotonic"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 1,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                providers = { cursor = false, lsp_semantic_tokens = true },
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
        local renderer = require("scrollbar.minimap.renderer")
        local requests = {}
        renderer.setup({
            worker = {
                request = function(request)
                    requests[#requests + 1] = vim.deepcopy(request)
                    renderer.handle_worker_result({
                        bufnr = request.bufnr,
                        generation = request.generation,
                        signature = request.signature,
                        changedtick = vim.api.nvim_buf_get_changedtick(request.bufnr),
                        semantic_revision = request.semantic_revision,
                        filetype = request.filetype,
                        cells = { { { char = "█", hl_group = nil } } },
                        max_line_width = 1,
                    })
                    return true
                end,
            },
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })

        local bufnr = vim.api.nvim_get_current_buf()
        local store = require("scrollbar.store")
        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {
            { line = 0, start_col = 0, end_col = 1, highlight = "Old", priority = 1 },
        })
        renderer.render(0)
        renderer.hide()
        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {
            { line = 0, start_col = 0, end_col = 1, highlight = "New", priority = 1 },
        })
        renderer.show()
        renderer.render(0)

        return {
            revisions = { requests[1].semantic_revision, requests[2].semantic_revision },
            second_highlight = requests[2].semantic_spans.lsp_semantic_tokens[1].highlight,
        }
    end)

    expect.equality(result.revisions, { 1, 2 })
    expect.equality(result.second_highlight, "New")
end

T["semantic input skips empty providers and mark-point recomputation"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 1,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                providers = { cursor = true, lsp_semantic_tokens = true },
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })

        local semantic = require("scrollbar.minimap.semantic")
        local original_signature = semantic.signature
        local signature_calls = 0
        ---@diagnostic disable-next-line: duplicate-set-field
        semantic.signature = function(spans)
            signature_calls = signature_calls + 1
            return original_signature(spans)
        end

        local renderer = require("scrollbar.minimap.renderer")
        local requests = {}
        renderer.setup({
            worker = {
                request = function(request)
                    requests[#requests + 1] = vim.deepcopy(request)
                    renderer.handle_worker_result({
                        bufnr = request.bufnr,
                        generation = request.generation,
                        signature = request.signature,
                        changedtick = vim.api.nvim_buf_get_changedtick(request.bufnr),
                        semantic_revision = request.semantic_revision,
                        filetype = request.filetype,
                        cells = { { { char = "█", hl_group = nil } } },
                        max_line_width = 1,
                    })
                    return true
                end,
            },
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })

        local bufnr = vim.api.nvim_get_current_buf()
        local winid = vim.api.nvim_get_current_win()
        local store = require("scrollbar.store")
        renderer.render(0)
        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {})
        renderer.render(0)
        store.set("cursor", bufnr, { { line = 0, type = "Cursor" } })
        store.set_minimap_points("cursor", winid, {
            { line = 0, col = 0, highlight = "ScrollbarMinimapCursor", priority = 14 },
        })
        renderer.render(0)

        semantic.signature = original_signature
        return {
            requests = #requests,
            revisions = vim.tbl_map(function(request)
                return request.semantic_revision
            end, requests),
            signature_calls = signature_calls,
        }
    end)

    expect.equality(result.requests, 1)
    expect.equality(result.revisions, { 0 })
    expect.equality(result.signature_calls, 2)
end

T["semantic revisions refresh every active dimension once"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = false,
        set_highlights = false,
        show_viewport = false,
        providers = { cursor = false, lsp_semantic_tokens = true },
    })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 80 do
            lines[index] = string.rep("a", 20)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        local second = vim.api.nvim_get_current_win()
        vim.api.nvim_set_option_value("winbar", "split", { win = second })

        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end
        local renderer = require("scrollbar.minimap.renderer")
        renderer.render(first)
        renderer.render(second)
        local initial_requests = requests

        require("scrollbar.store").set_minimap_spans("lsp_semantic_tokens", vim.api.nvim_get_current_buf(), {
            { line = 0, start_col = 0, end_col = 20, highlight = "Semantic", priority = 1 },
        })
        renderer.render(first)
        renderer.render(second)
        local changed_requests = requests
        renderer.render(first)
        renderer.render(second)
        worker.request = original_request
        return {
            initial_requests = initial_requests,
            changed_requests = changed_requests,
            final_requests = requests,
        }
    end)

    expect.equality(result.initial_requests, 2)
    expect.equality(result.changed_requests, 4)
    expect.equality(result.final_requests, 4)
end

T["renderer rejects stale semantic results without clearing newer pending work"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 1,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                providers = { cursor = false, lsp_semantic_tokens = true },
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
        local requests = {}
        local renderer = require("scrollbar.minimap.renderer")
        renderer.setup({
            worker = {
                request = function(request)
                    requests[#requests + 1] = vim.deepcopy(request)
                    return true
                end,
            },
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })

        local bufnr = vim.api.nvim_get_current_buf()
        local store = require("scrollbar.store")
        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {
            { line = 0, start_col = 0, end_col = 1, highlight = "Old", priority = 1 },
        })
        renderer.render(0)
        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {
            { line = 0, start_col = 0, end_col = 1, highlight = "New", priority = 2 },
        })
        renderer.render(0)

        local function deliver(request, highlight)
            renderer.handle_worker_result({
                bufnr = bufnr,
                generation = request.generation,
                signature = request.signature,
                changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
                semantic_revision = request.semantic_revision,
                cells = { { { char = "█", hl_group = highlight } } },
                max_line_width = 1,
            })
        end

        deliver(requests[1], "Stale")
        local after_stale = assert(renderer.render(0))
        local stale_highlight = after_stale.highlights[1][1] and after_stale.highlights[1][1].highlight or nil
        local requests_after_stale = #requests

        deliver(requests[2], "Current")
        local current = assert(renderer.render(0))
        return {
            request_count = #requests,
            requests_after_stale = requests_after_stale,
            stale_highlight = stale_highlight,
            current_highlight = current.highlights[1][1] and current.highlights[1][1].highlight or nil,
        }
    end)

    expect.equality(result.requests_after_stale, 2)
    expect.equality(result.request_count, 2)
    expect.equality(result.stale_highlight, nil)
    expect.equality(result.current_highlight, "Current")
end

T["worker-native span publication reuses the accepted cell result"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 1,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                providers = { cursor = false, treesitter = true },
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
        local requests = 0
        local renderer = require("scrollbar.minimap.renderer")
        renderer.setup({
            worker = {
                request = function(request)
                    requests = requests + 1
                    renderer.handle_worker_result({
                        bufnr = request.bufnr,
                        generation = request.generation,
                        signature = request.signature,
                        changedtick = vim.api.nvim_buf_get_changedtick(request.bufnr),
                        semantic_revision = request.semantic_revision,
                        cells = { { { char = "█", hl_group = "@variable" } } },
                        max_line_width = 1,
                        worker_spans = {
                            { line = 0, start_col = 0, end_col = 1, highlight = "@variable", priority = 100 },
                        },
                    })
                    return true
                end,
            },
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })

        local state = assert(renderer.render(0))
        renderer.render(0)
        return {
            requests = requests,
            highlight = state.highlights[1][1] and state.highlights[1][1].highlight or nil,
            spans = require("scrollbar.store").get_minimap_spans(vim.api.nvim_get_current_buf()).treesitter,
        }
    end)

    expect.equality(result.requests, 1)
    expect.equality(result.highlight, "@variable")
    expect.equality(result.spans, {
        { line = 0, start_col = 0, end_col = 1, highlight = "@variable", priority = 100 },
    })
end

T["LSP semantic spans override overlapping Treesitter spans"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 1,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                providers = { cursor = false, treesitter = true, lsp_semantic_tokens = true },
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
        local bufnr = vim.api.nvim_get_current_buf()
        local store = require("scrollbar.store")
        local treesitter_span = {
            line = 0,
            start_col = 0,
            end_col = 1,
            highlight = "@variable",
            priority = require("scrollbar.providers.treesitter").priority,
        }
        store.set_minimap_spans("treesitter", bufnr, { treesitter_span })
        store.set_minimap_spans("lsp_semantic_tokens", bufnr, {
            {
                line = 0,
                start_col = 0,
                end_col = 1,
                highlight = "@lsp.type.variable.lua",
                priority = require("scrollbar.providers.lsp_semantic_tokens").priorities.base,
            },
        })

        local renderer = require("scrollbar.minimap.renderer")
        renderer.setup({
            worker = {
                request = function(request)
                    local spans = vim.deepcopy(request.semantic_spans)
                    spans.treesitter = { treesitter_span }
                    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
                    local highlights = require("scrollbar.minimap.semantic").compose(lines, spans)
                    local cells, max_line_width = require("scrollbar.minimap.squash").squash(lines, 1, 1, highlights)
                    renderer.handle_worker_result({
                        bufnr = bufnr,
                        generation = request.generation,
                        signature = request.signature,
                        changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
                        semantic_revision = request.semantic_revision,
                        cells = cells,
                        max_line_width = max_line_width,
                        worker_spans = { treesitter_span },
                    })
                    return true
                end,
            },
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })
        local state = assert(renderer.render(0))
        return state.highlights[1][1] and state.highlights[1][1].highlight or nil
    end)

    expect.equality(result, "@lsp.type.variable.lua")
end

T["same-buffer windows retain dimension-specific caches"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = false })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 100 do
            lines[index] = string.rep("a", 20)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local first = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        local second = vim.api.nvim_get_current_win()
        vim.api.nvim_set_option_value("winbar", "split", { win = second })

        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end

        local renderer = require("scrollbar.minimap.renderer")
        renderer.render(first)
        renderer.render(second)
        local first_state = assert(renderer.render(first))
        local second_state = assert(renderer.render(second))
        worker.request = original_request

        return {
            requests = requests,
            first_height = first_state.height,
            second_height = second_state.height,
            first_rows = #first_state.rows,
            second_rows = #second_state.rows,
            first_signature = first_state.cells_signature,
            second_signature = second_state.cells_signature,
        }
    end)

    expect.equality(result.requests, 2)
    expect.no_equality(result.first_height, result.second_height)
    expect.equality(result.first_rows, result.first_height)
    expect.equality(result.second_rows, result.second_height)
    expect.no_equality(result.first_signature, result.second_signature)
end

T["buffer edits refresh a cached projection"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 1,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end

        local renderer = require("scrollbar.minimap.renderer")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "aaaa", "aaaa" })
        local before = assert(renderer.render(0)).rows[1]
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "", "" })
        local after = assert(renderer.render(0)).rows[1]
        worker.request = original_request

        return { requests = requests, before = before, after = after }
    end)

    expect.equality(result.requests, 2)
    expect.equality(result.before, "████")
    expect.equality(result.after, "    ")
end

T["filetype changes recollect Treesitter and invalidate cached cells"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 1,
                height = 1,
                set_highlights = false,
                show_viewport = false,
                providers = { cursor = false, treesitter = true },
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
        local treesitter = require("scrollbar.providers.treesitter")
        local original_language_for = treesitter.language_for
        local original_collect = treesitter.collect
        ---@diagnostic disable-next-line: duplicate-set-field
        treesitter.language_for = function(filetype)
            return filetype ~= "" and filetype or nil
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        treesitter.collect = function(_, lang)
            return {
                { line = 0, start_col = 0, end_col = 1, highlight = "@" .. lang, priority = treesitter.priority },
            }
        end

        local renderer = require("scrollbar.minimap.renderer")
        local worker = require("scrollbar.minimap.worker")
        worker.setup({ backend = "sync", treesitter = true, on_result = renderer.handle_worker_result })
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end
        renderer.setup({
            worker = worker,
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })

        vim.bo.filetype = "lua"
        local first = assert(renderer.render(0))
        local first_highlight = first.highlights[1][1] and first.highlights[1][1].highlight or nil
        vim.bo.filetype = "python"
        local second = assert(renderer.render(0))

        worker.request = original_request
        treesitter.language_for = original_language_for
        treesitter.collect = original_collect
        return {
            requests = requests,
            first = first_highlight,
            second = second.highlights[1][1] and second.highlights[1][1].highlight or nil,
        }
    end)

    expect.equality(result.requests, 2)
    expect.equality(result.first, "@lua")
    expect.equality(result.second, "@python")
end

T["closing one same-buffer window retains the shared projection cache"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
        local first = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        local second = vim.api.nvim_get_current_win()

        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end

        local renderer = require("scrollbar.minimap.renderer")
        renderer.render(first)
        renderer.render(second)
        vim.api.nvim_win_close(first, true)
        renderer.render(second)
        worker.request = original_request
        return requests
    end)

    expect.equality(result, 1)
end

T["dispose closes all minimap floats and clears caches"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        local renderer = require("scrollbar.minimap.renderer")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
        local state = assert(renderer.render(0))
        local float_win = state.float_win
        renderer.dispose()
        return {
            float_win_valid = vim.api.nvim_win_is_valid(float_win),
            state = renderer.get_state(0),
            visible = renderer.is_visible(),
        }
    end)

    expect.equality(result.float_win_valid, false)
    expect.equality(result.state, nil)
    expect.equality(result.visible, false)
end

T["viewport layers never mutate composed rows"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
        show_viewport = false,
    })

    local content_only = child.lua_func(function()
        local lines = {}
        for index = 1, 8 do
            lines[index] = "aaaa"
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        return assert(require("scrollbar.minimap.renderer").render(0)).rows
    end)

    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
        show_viewport = true,
    })
    local with_layers = child.lua_func(function()
        return assert(require("scrollbar.minimap.renderer").render(0)).rows
    end)

    expect.equality(with_layers, content_only)
    for _, row in ipairs(with_layers) do
        for _, forbidden in ipairs({ "┌", "─", "┐", "│", "└", "┘", "▎" }) do
            expect.equality(row:find(forbidden, 1, true), nil)
        end
    end
end

T["show_viewport false suppresses the viewport tint"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 8 do
            lines[index] = "aaaa"
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local namespace = renderer.namespace()
        local marks = vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true })
        local has_viewport = false
        for _, mark in ipairs(marks) do
            local hl = mark[4] and mark[4].hl_group
            if hl == "ScrollbarMinimapViewport" then
                has_viewport = true
            end
        end
        return {
            rows = state.rows,
            has_viewport = has_viewport,
        }
    end)

    expect.equality(result.has_viewport, false)
    expect.equality(result.rows[1], "████")
end

T["occupied cells use the monochrome content highlight by default"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 1,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a  b", "a  b" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local ranges = {}
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, {
                details = true,
            }))
        do
            if mark[4] and mark[4].hl_group == "ScrollbarMinimapContent" then
                ranges[#ranges + 1] = { mark[3], mark[4].end_col }
            end
        end
        return { row = state.rows[1], ranges = ranges }
    end)

    expect.equality(result.row, "█  █")
    expect.equality(result.ranges, { { 0, 3 }, { 5, 8 } })
end

T["width false uses the 16-column renderer fallback"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = false,
        height = 1,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
        local state = assert(require("scrollbar.minimap.renderer").render(0))
        return { width = state.width, cells = vim.fn.strdisplaywidth(state.rows[1]) }
    end)

    expect.equality(result.width, 16)
    expect.equality(result.cells, 16)
end

T["background inheritance keeps direct groups and uses full-float winblend"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 1,
        height = 1,
        set_highlights = false,
        show_viewport = false,
        float = { blend = 35, hide_on_cursor = false },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local mark = vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, {
            details = true,
        })[1]
        return {
            winblend = vim.api.nvim_get_option_value("winblend", { win = state.float_win }),
            winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = state.float_win }),
            highlight = mark and mark[4].hl_group or nil,
        }
    end)

    expect.equality(result.winblend, 35)
    expect.equality(
        result.winhighlight,
        "Normal:ScrollbarMinimapBase,NormalNC:ScrollbarMinimapBase,EndOfBuffer:ScrollbarMinimapBase"
    )
    expect.equality(result.highlight, "ScrollbarMinimapContent")
end

T["numeric background blend isolates base and background-bearing layers"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 4,
                height = 1,
                set_highlights = false,
                background = { blend = 60 },
                float = { blend = 0, hide_on_cursor = false },
                overlays = { enabled = true, types = { Error = {} } },
                show_viewport = true,
            },
        })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapBase", { bg = "#101010" })
        vim.api.nvim_set_hl(0, "ForegroundOnly", { fg = "#abcdef", bold = true })
        vim.api.nvim_set_hl(0, "SemanticBackground", { fg = "#fedcba", bg = "#202020" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapViewport", { bg = "#303030" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapCursor", { bg = "#404040" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapError", { bg = "#505050" })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcd" })

        local renderer = require("scrollbar.minimap.renderer")
        renderer.setup({
            worker = {
                request = function(request)
                    renderer.handle_worker_result({
                        bufnr = request.bufnr,
                        signature = request.signature,
                        changedtick = vim.api.nvim_buf_get_changedtick(request.bufnr),
                        semantic_revision = request.semantic_revision,
                        filetype = request.filetype,
                        cells = {
                            {
                                { char = "█", hl_group = "ForegroundOnly" },
                                { char = "█", hl_group = "SemanticBackground" },
                                { char = "█" },
                                { char = "█" },
                            },
                        },
                        max_line_width = 4,
                    })
                    return true
                end,
            },
            overlays = {
                project_with = function()
                    return {
                        {
                            source_line = 0,
                            minimap_row = 1,
                            mark_type = "Error",
                            priority = 2,
                            highlight = "ScrollbarMinimapError",
                            provider = "diagnostic",
                        },
                    }
                end,
            },
        })
        require("scrollbar.store").set_minimap_points("cursor", vim.api.nvim_get_current_win(), {
            { line = 0, col = 3, highlight = "ScrollbarMinimapCursor", priority = 14 },
        })

        local state = assert(renderer.render(0))
        local winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = state.float_win })
        local base = winhighlight:match("Normal:([^,]+)")
        local definitions = {}
        local foreground_seen = false
        for _, mark in
            ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, renderer.namespace(), 0, -1, { details = true }))
        do
            local name = mark[4].hl_group
            if name == "ForegroundOnly" then
                foreground_seen = true
            else
                local definition = vim.api.nvim_get_hl(0, { name = name, link = false })
                if definition.bg ~= nil then
                    definitions[definition.bg] = definition.blend
                end
            end
        end
        return {
            winblend = vim.api.nvim_get_option_value("winblend", { win = state.float_win }),
            base = vim.api.nvim_get_hl(0, { name = base, link = false }),
            definitions = definitions,
            foreground_seen = foreground_seen,
        }
    end)

    expect.equality(result.winblend, 60)
    expect.equality(result.base, { bg = 0x101010, blend = 60 })
    expect.equality(result.definitions[0x202020], 0)
    expect.equality(result.definitions[0x303030], 0)
    expect.equality(result.definitions[0x404040], 0)
    expect.equality(result.definitions[0x505050], 0)
    expect.equality(result.foreground_seen, true)
end

T["profile full-float blend transitions reuse resources and refresh wrappers"] = function()
    local child = new_child()
    reset_modules(child)

    local result = child.lua_func(function()
        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 1,
                height = 1,
                set_highlights = false,
                background = { blend = 20 },
                float = { blend = 0, hide_on_cursor = false },
                show_viewport = false,
                profiles = {
                    {
                        match = { filetypes = { "lua" } },
                        config = { float = { blend = 60 } },
                    },
                },
            },
        })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapBase", { bg = "#101010" })
        vim.api.nvim_set_hl(0, "LayerBackground", { bg = "#202020" })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })

        local renderer = require("scrollbar.minimap.renderer")
        renderer.setup({
            worker = {
                request = function(request)
                    renderer.handle_worker_result({
                        bufnr = request.bufnr,
                        signature = request.signature,
                        changedtick = vim.api.nvim_buf_get_changedtick(request.bufnr),
                        semantic_revision = request.semantic_revision,
                        filetype = request.filetype,
                        cells = { { { char = "█", hl_group = "LayerBackground" } } },
                        max_line_width = 1,
                    })
                    return true
                end,
            },
            overlays = {
                project_with = function()
                    return {}
                end,
            },
        })

        vim.bo.filetype = "text"
        local first = assert(renderer.render(0))
        local first_mark = vim.api.nvim_buf_get_extmarks(first.float_buf, renderer.namespace(), 0, -1, {
            details = true,
        })[1]
        local first_group = first_mark[4].hl_group
        local snapshot = {
            float_win = first.float_win,
            float_buf = first.float_buf,
            winblend = vim.api.nvim_get_option_value("winblend", { win = first.float_win }),
            layer = vim.api.nvim_get_hl(0, { name = first_group, link = false }),
        }

        vim.bo.filetype = "lua"
        local second = assert(renderer.render(0))
        local second_mark = vim.api.nvim_buf_get_extmarks(second.float_buf, renderer.namespace(), 0, -1, {
            details = true,
        })[1]
        local second_group = second_mark[4].hl_group
        local base = vim.api.nvim_get_option_value("winhighlight", { win = second.float_win }):match("Normal:([^,]+)")
        return {
            first = snapshot,
            second = {
                float_win = second.float_win,
                float_buf = second.float_buf,
                winblend = vim.api.nvim_get_option_value("winblend", { win = second.float_win }),
                layer = vim.api.nvim_get_hl(0, { name = second_group, link = false }),
                base = vim.api.nvim_get_hl(0, { name = base, link = false }),
                background_blend = second.config.background.blend,
            },
        }
    end)

    expect.equality(result.first.float_win, result.second.float_win)
    expect.equality(result.first.float_buf, result.second.float_buf)
    expect.equality(result.first.winblend, 20)
    expect.equality(result.first.layer, { bg = 0x202020, blend = 0 })
    expect.equality(result.second.winblend, 60)
    expect.equality(result.second.layer, { bg = 0x202020, blend = 60 })
    expect.equality(result.second.base, { bg = 0x101010, blend = 20 })
    expect.equality(result.second.background_blend, 20)
end

T["cursor overlap hides and restores the same minimap only on transitions"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 4,
        set_highlights = false,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three", "four" })
        local source_win = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.minimap.renderer")
        local worker = require("scrollbar.minimap.worker")
        local cursor = { row = 3, col = 7 }
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        local get_position = vim.api.nvim_win_get_position
        local set_config = vim.api.nvim_win_set_config
        local redraw = vim.api.nvim__redraw
        local request = worker.request
        local config_calls = 0
        local redraw_calls = 0
        local requests = 0
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
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(options)
            requests = requests + 1
            return request(options)
        end

        local hidden = assert(renderer.render(source_win))
        local hidden_config = vim.api.nvim_win_get_config(hidden.float_win).hide
        local hidden_by_cursor = hidden.hidden_by_cursor
        local after_hide = config_calls
        renderer.render(source_win)
        local after_hidden_steady = config_calls

        cursor.col = 5
        local restored = assert(renderer.render(source_win))
        local restored_config = vim.api.nvim_win_get_config(restored.float_win).hide
        local after_restore = config_calls
        renderer.render(source_win)
        local after_visible_steady = config_calls

        worker.request = request
        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        rawset(vim.api, "nvim_win_set_config", set_config)
        rawset(vim.api, "nvim__redraw", redraw)
        return {
            hidden_by_cursor = hidden_by_cursor,
            hidden_config = hidden_config,
            restored_by_cursor = restored.hidden_by_cursor,
            restored_config = restored_config,
            same_float = hidden.float_win == restored.float_win,
            same_buffer = hidden.float_buf == restored.float_buf,
            resources_valid = vim.api.nvim_win_is_valid(restored.float_win)
                and vim.api.nvim_buf_is_valid(restored.float_buf),
            requests = requests,
            redraw_calls = redraw_calls,
            calls = {
                after_hide = after_hide,
                after_hidden_steady = after_hidden_steady,
                after_restore = after_restore,
                after_visible_steady = after_visible_steady,
            },
        }
    end)

    expect.equality(result, {
        hidden_by_cursor = true,
        hidden_config = true,
        restored_by_cursor = false,
        restored_config = false,
        same_float = true,
        same_buffer = true,
        resources_valid = true,
        requests = 1,
        redraw_calls = 1,
        calls = {
            after_hide = 0,
            after_hidden_steady = 0,
            after_restore = 1,
            after_visible_steady = 1,
        },
    })
end

T["cursor hiding uses inclusive top-left and exclusive bottom-right bounds"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 3,
        set_highlights = false,
        show_viewport = false,
        providers = { cursor = false },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local renderer = require("scrollbar.minimap.renderer")
        local source_win = vim.api.nvim_get_current_win()
        local cursor = { row = 6, col = 8 }
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
            return { 5, 7 }
        end)

        local top_left = assert(renderer.render(source_win))
        local top_left_hidden = top_left.hidden_by_cursor
        local cursor_projection = top_left.cursor_row
        cursor.row = 9
        local bottom = assert(renderer.render(source_win)).hidden_by_cursor
        cursor.row = 6
        cursor.col = 12
        local right = assert(renderer.render(source_win)).hidden_by_cursor
        cursor.row = 8
        cursor.col = 11
        local bottom_right_inside = assert(renderer.render(source_win)).hidden_by_cursor

        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        rawset(vim.api, "nvim_win_get_position", get_position)
        return {
            top_left = top_left_hidden,
            bottom = bottom,
            right = right,
            bottom_right_inside = bottom_right_inside,
            cursor_projection = cursor_projection,
        }
    end)

    expect.equality(result, {
        top_left = true,
        bottom = false,
        right = false,
        bottom_right_inside = true,
        cursor_projection = nil,
    })
end

T["disabled cursor hiding skips coordinate work and unavailable coordinates fail open"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 3,
        set_highlights = false,
        show_viewport = false,
        float = { hide_on_cursor = false },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local source_win = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.minimap.renderer")
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

        local disabled = assert(renderer.render(source_win))
        local disabled_calls = vim.deepcopy(calls)
        local disabled_hide = vim.api.nvim_win_get_config(disabled.float_win).hide

        require("scrollbar.config").set({
            scrollbar = {},
            minimap = {
                enabled = true,
                width = 4,
                height = 3,
                set_highlights = false,
                show_viewport = false,
                float = { hide_on_cursor = true },
            },
        })
        renderer.setup({
            worker = require("scrollbar.minimap.worker"),
            overlays = require("scrollbar.minimap.overlays"),
        })
        calls = { row = 0, col = 0, position = 0 }
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
    end)

    expect.equality(result, {
        disabled_hide = false,
        disabled_calls = { row = 0, col = 0, position = 0 },
        unavailable_hide = false,
        unavailable_calls = { row = 1, col = 1, position = 0 },
    })
end

T["focus transfer restores inactive minimaps and hides the newly active source"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 3,
        set_highlights = false,
        show_viewport = false,
        update = { interval_ms = 0 },
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.minimap.renderer")
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

        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.setup({ config = require("scrollbar.minimap.config").get(), renderer = renderer })
        vim.api.nvim_set_current_win(first)
        scheduler.invalidate_all()
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
    end)

    expect.equality(result, {
        initial = { first = false, second = true },
        transferred = { first = true, second = false, same_first = true, same_second = true },
    })
end

T["cursor overlap state repairs external float hide mutations"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, {
        enabled = true,
        width = 4,
        height = 3,
        set_highlights = false,
        show_viewport = false,
    })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
        local source_win = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.minimap.renderer")
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
    end)

    expect.equality(result, {
        repaired_visible = false,
        repaired_hidden = true,
        hidden_by_cursor = true,
    })
end

return T
