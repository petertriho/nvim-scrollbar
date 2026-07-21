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
            "scrollbar",
            "scrollbar.config",
            "scrollbar.minimap.config",
            "scrollbar.minimap.highlights",
            "scrollbar.minimap.worker",
            "scrollbar.minimap.overlays",
            "scrollbar.minimap.renderer",
            "scrollbar.minimap.scheduler",
            "scrollbar.minimap.mouse",
            "scrollbar.minimap",
            "scrollbar.store",
        }) do
            package.loaded[module] = nil
        end
    ]])
end

T["setup with default config (disabled) does not spawn a worker"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {},
        })
        local worker = require("scrollbar.minimap.worker")
        local renderer = require("scrollbar.minimap.renderer")
        local commands = vim.api.nvim_get_commands({})
        return {
            worker_state = worker.status().state,
            renderer_visible = renderer.is_visible(),
            has_toggle = commands.MinimapToggle ~= nil,
        }
    end)

    expect.equality(result.worker_state, "disposed")
    expect.equality(result.renderer_visible, false)
    -- Commands are not registered when disabled.
    expect.equality(result.has_toggle, false)
end

T["setup with enabled=true spawns worker, scheduler, renderer, and commands"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
            },
        })
        local worker = require("scrollbar.minimap.worker")
        local renderer = require("scrollbar.minimap.renderer")
        local scheduler = require("scrollbar.minimap.scheduler")
        local status = scheduler.status()
        local commands = vim.api.nvim_get_commands({})
        return {
            worker_state = worker.status().state,
            renderer_visible = renderer.is_visible(),
            scheduler_setup = status.setup,
            has_show = commands.MinimapShow ~= nil,
            has_hide = commands.MinimapHide ~= nil,
            has_toggle = commands.MinimapToggle ~= nil,
            has_refresh = commands.MinimapRefresh ~= nil,
        }
    end)

    expect.equality(result.worker_state, "sync")
    expect.equality(result.renderer_visible, true)
    expect.equality(result.scheduler_setup, true)
    expect.equality(result.has_show, true)
    expect.equality(result.has_hide, true)
    expect.equality(result.has_toggle, true)
    expect.equality(result.has_refresh, true)
end

T["reconfiguring from enabled to disabled removes minimap commands"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        local scrollbar = require("scrollbar")
        scrollbar.setup({
            scrollbar = { set_highlights = false },
            minimap = { enabled = true, set_highlights = false, backend = "sync" },
        })
        local before = vim.fn.exists(":MinimapRefresh")
        scrollbar.setup({
            scrollbar = { set_highlights = false },
            minimap = { enabled = false },
        })
        return {
            before = before,
            after = vim.fn.exists(":MinimapRefresh"),
            worker = require("scrollbar.minimap.worker").status().state,
        }
    end)

    expect.equality(result, { before = 2, after = 0, worker = "disposed" })
end

T["opening a buffer with enabled renders a minimap with viewport and cursor"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
            },
        })
        local lines = {}
        for index = 1, 20 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local renderer = require("scrollbar.minimap.renderer")
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.invalidate_all()
        scheduler.flush()
        local state = renderer.get_state(vim.api.nvim_get_current_win())
        return state
                and {
                    has_rows = #state.rows > 0,
                    cursor_row = state.cursor_row,
                    viewport_top = state.viewport_top,
                }
            or { has_rows = false }
    end)

    expect.equality(result.has_rows, true)
    expect.no_equality(result.cursor_row, nil)
    expect.no_equality(result.viewport_top, nil)
end

T["same-buffer split projections settle without a render loop"] = function()
    local child = new_child()
    reset_modules(child)
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
        local renders = 0
        local original_render = renderer.render
        ---@diagnostic disable-next-line: duplicate-set-field
        renderer.render = function(winid)
            renders = renders + 1
            return original_render(winid)
        end

        require("scrollbar").setup({
            scrollbar = { show = false, set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = false,
                update = { interval_ms = 1 },
            },
        })

        local scheduler = require("scrollbar.minimap.scheduler")
        local settled = vim.wait(1000, function()
            local status = scheduler.status()
            return requests == 2
                and not status.timer_active
                and #status.dirty_windows == 0
                and renderer.get_state(first) ~= nil
                and renderer.get_state(second) ~= nil
        end)
        local requests_at_settle = requests
        local renders_at_settle = renders
        vim.wait(30)

        local first_state = assert(renderer.get_state(first))
        local second_state = assert(renderer.get_state(second))
        worker.request = original_request
        renderer.render = original_render
        return {
            settled = settled,
            requests_at_settle = requests_at_settle,
            requests_after_wait = requests,
            renders_at_settle = renders_at_settle,
            renders_after_wait = renders,
            first_height = first_state.height,
            second_height = second_state.height,
            first_rows = #first_state.rows,
            second_rows = #second_state.rows,
        }
    end)

    expect.equality(result.settled, true)
    expect.equality(result.requests_at_settle, 2)
    expect.equality(result.requests_after_wait, result.requests_at_settle)
    expect.equality(result.renders_after_wait, result.renders_at_settle)
    expect.no_equality(result.first_height, result.second_height)
    expect.equality(result.first_rows, result.first_height)
    expect.equality(result.second_rows, result.second_height)
end

T["MinimapToggle hides and shows without affecting the scrollbar"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
            },
        })
        local minimap_renderer = require("scrollbar.minimap.renderer")
        local scrollbar_renderer = require("scrollbar.renderer")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })

        local minimap_visible_before = minimap_renderer.is_visible()
        vim.cmd("MinimapToggle")
        local minimap_visible_after_hide = minimap_renderer.is_visible()
        vim.cmd("MinimapToggle")
        local minimap_visible_after_show = minimap_renderer.is_visible()
        return {
            minimap_visible_before = minimap_visible_before,
            minimap_visible_after_hide = minimap_visible_after_hide,
            minimap_visible_after_show = minimap_visible_after_show,
            scrollbar_visible = scrollbar_renderer.is_visible(),
        }
    end)

    expect.equality(result.minimap_visible_before, true)
    expect.equality(result.minimap_visible_after_hide, false)
    expect.equality(result.minimap_visible_after_show, true)
    expect.equality(result.scrollbar_visible, true)
end

T["toggling scrollbar.show = false does not affect the minimap"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
            },
        })
        local minimap_renderer = require("scrollbar.minimap.renderer")
        local scrollbar_renderer = require("scrollbar.renderer")
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c" })

        scrollbar_renderer.hide()
        local scrollbar_hidden = scrollbar_renderer.is_visible()
        local minimap_still_visible = minimap_renderer.is_visible()
        return {
            scrollbar_hidden = scrollbar_hidden,
            minimap_still_visible = minimap_still_visible,
        }
    end)

    expect.equality(result.scrollbar_hidden, false)
    expect.equality(result.minimap_still_visible, true)
end

T["reconfigure via a second setup call disposes the previous worker and floats"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
            },
        })
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
        local renderer = require("scrollbar.minimap.renderer")
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.invalidate_all()
        scheduler.flush()
        local first_state = renderer.get_state(vim.api.nvim_get_current_win())
        local first_float = first_state and first_state.float_win

        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
            },
        })
        scheduler.invalidate_all()
        scheduler.flush()
        local second_state = renderer.get_state(vim.api.nvim_get_current_win())
        return {
            first_float_valid_after_reconfigure = first_float and vim.api.nvim_win_is_valid(first_float),
            second_state_present = second_state ~= nil,
        }
    end)

    expect.equality(result.first_float_valid_after_reconfigure, false)
    expect.equality(result.second_state_present, true)
end

T["setup defines the minimap highlight groups with the retuned defaults"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                backend = "sync",
                width = 4,
                height = 4,
            },
        })
        local function link_of(name)
            return vim.api.nvim_get_hl(0, { name = name, link = true }).link
        end
        local highlights = vim.api.nvim_get_hl(0, {})
        return {
            base_link = link_of("ScrollbarMinimapBase"),
            content_link = link_of("ScrollbarMinimapContent"),
            cursor_link = link_of("ScrollbarMinimapCursor"),
            viewport_link = link_of("ScrollbarMinimapViewport"),
            viewport_border_defined = highlights.ScrollbarMinimapViewportBorder ~= nil,
        }
    end)

    expect.equality(result.base_link, "NormalFloat")
    expect.equality(result.content_link, "Comment")
    expect.equality(result.cursor_link, "Cursor")
    expect.equality(result.viewport_link, "CursorLine")
    expect.equality(result.viewport_border_defined, false)
end

T["generates overlay highlights through user-preserving public links"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        local scrollbar = require("scrollbar")
        local base = {
            enabled = true,
            backend = "sync",
            width = 4,
            height = 4,
            overlays = {
                types = {
                    Search = { highlight = "OverlayStringSource" },
                    Direct = { priority = 8, highlight = { fg = "#abcdef", bold = true } },
                },
            },
        }
        vim.api.nvim_set_hl(0, "OverlayStringSource", { fg = "#123456", bg = "#010101" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapError", { fg = "#654321", italic = true })
        local preserved_before = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapError", link = true })
        scrollbar.setup({ scrollbar = { set_highlights = false }, minimap = base })

        local link = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = true }).link
        end
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        local search_target = link("ScrollbarMinimapSearch")
        local direct_target = link("ScrollbarMinimapDirect")
        local first = {
            search = get("ScrollbarMinimapSearch"),
            direct = get("ScrollbarMinimapDirect"),
        }

        vim.api.nvim_set_hl(0, "OverlayStringSource", { fg = "#234567", bg = "#020202" })
        scrollbar.setup({ scrollbar = { set_highlights = false }, minimap = base })
        local second = {
            search_target = link("ScrollbarMinimapSearch"),
            direct_target = link("ScrollbarMinimapDirect"),
            search = get("ScrollbarMinimapSearch"),
            direct = get("ScrollbarMinimapDirect"),
        }

        vim.api.nvim_set_hl(0, search_target, { fg = "#000000" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapSearch", { fg = "#556677", underline = true })
        vim.cmd("doautocmd ColorScheme")
        return {
            search_target = search_target,
            direct_target = direct_target,
            first = first,
            second = second,
            refreshed_private = get(search_target),
            preserved_before = preserved_before,
            preserved_after = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapError", link = true }),
            public_override = vim.api.nvim_get_hl(0, { name = "ScrollbarMinimapSearch", link = true }),
        }
    end)

    expect.no_equality(result.search_target:match("^ScrollbarMinimapGenerated%."), nil)
    expect.no_equality(result.direct_target:match("^ScrollbarMinimapGenerated%."), nil)
    expect.equality(result.first.search, { fg = 0x123456 })
    expect.equality(result.first.direct, { fg = 0xABCDEF, bold = true, cterm = { bold = true } })
    expect.equality(result.second.search_target, result.search_target)
    expect.equality(result.second.direct_target, result.direct_target)
    expect.equality(result.second.search, { fg = 0x234567 })
    expect.equality(result.second.direct, result.first.direct)
    expect.equality(result.refreshed_private, { fg = 0x234567 })
    expect.equality(result.preserved_after, result.preserved_before)
    expect.equality(result.public_override, {
        fg = 0x556677,
        underline = true,
        cterm = { underline = true },
    })
end

T["generates isolated automatic overlay groups for minimap profiles"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                backend = "sync",
                width = 4,
                height = 4,
                overlays = { types = { Search = { highlight = { fg = "#010101" } } } },
                profiles = {
                    {
                        match = { filetypes = { "lua" } },
                        config = { overlays = { types = { Search = { highlight = { fg = "#112233" } } } } },
                    },
                    {
                        match = { filetypes = { "text" } },
                        config = { overlays = { types = { Search = { highlight = { fg = "#445566" } } } } },
                    },
                },
            },
        })
        local variants = require("scrollbar.minimap.config").get_variants()
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        return {
            groups = {
                variants[1].config.overlays.types.Search.group,
                variants[2].config.overlays.types.Search.group,
                variants[3].config.overlays.types.Search.group,
            },
            root = get("ScrollbarMinimapSearch"),
            first = get("ScrollbarMinimapProfile1.Search"),
            second = get("ScrollbarMinimapProfile2.Search"),
        }
    end)

    expect.equality(result.groups, {
        "ScrollbarMinimapSearch",
        "ScrollbarMinimapProfile1.Search",
        "ScrollbarMinimapProfile2.Search",
    })
    expect.equality(result.root, { fg = 0x010101 })
    expect.equality(result.first, { fg = 0x112233 })
    expect.equality(result.second, { fg = 0x445566 })
end

T["minimap internal namespaces do not capture valid custom type groups"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                backend = "sync",
                width = 4,
                height = 4,
                overlays = {
                    types = {
                        Search = { highlight = { fg = "#111111" } },
                        GeneratedSearch = { priority = 8, highlight = { fg = "#222222" } },
                        Profile1Search = { priority = 9, highlight = { fg = "#333333" } },
                    },
                },
                profiles = {
                    {
                        match = { filetypes = { "lua" } },
                        config = { overlays = { types = { Search = { highlight = { fg = "#444444" } } } } },
                    },
                },
            },
        })
        local variants = require("scrollbar.minimap.config").get_variants()
        local profile_search = variants[2].config.overlays.types.Search.group
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        local link = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = true }).link
        end
        return {
            generated = get("ScrollbarMinimapGeneratedSearch"),
            profile_like = get("ScrollbarMinimapProfile1Search"),
            generated_target = link("ScrollbarMinimapSearch"),
            profile_search = profile_search,
            profile_definition = get(profile_search),
        }
    end)

    expect.equality(result.generated, { fg = 0x222222 })
    expect.equality(result.profile_like, { fg = 0x333333 })
    expect.equality(result.generated_target, "ScrollbarMinimapGenerated.Search")
    expect.equality(result.profile_search, "ScrollbarMinimapProfile1.Search")
    expect.equality(result.profile_definition, { fg = 0x444444 })
end

T["manual minimap highlight mode writes no public private or profile groups"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 4,
                overlays = {
                    types = { ManualOnly = { priority = 1, highlight = "Special" } },
                },
                profiles = {
                    {
                        match = { filetypes = { "lua" } },
                        config = { overlays = { types = { Search = { priority = 0 } } } },
                    },
                },
            },
        })
        vim.cmd("doautocmd ColorScheme")
        local names = {}
        for name in pairs(vim.api.nvim_get_hl(0, {})) do
            if name:match("^ScrollbarMinimap") then
                names[#names + 1] = name
            end
        end
        table.sort(names)
        local groups = {}
        for _, variant in ipairs(require("scrollbar.minimap.config").get_variants()) do
            groups[#groups + 1] = {
                manual = variant.config.overlays.types.ManualOnly.group,
                search = variant.config.overlays.types.Search.group,
            }
        end
        return { names = names, groups = groups }
    end)

    expect.equality(result.names, {})
    for _, groups in ipairs(result.groups) do
        expect.equality(groups.manual, "ScrollbarMinimapManualOnly")
        expect.equality(groups.search, "ScrollbarMinimapSearch")
    end
end

T["setup forwards treesitter provider demand to the worker"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        local values = {}
        package.loaded["scrollbar.minimap.worker"] = {
            dispose = function() end,
            setup = function(options)
                values[#values + 1] = {
                    treesitter = options.treesitter,
                    syntax_highlighting = rawget(options, "syntax_highlighting"),
                }
            end,
        }
        package.loaded["scrollbar.minimap.mouse"] = { dispose = function() end, setup = function() end }
        package.loaded["scrollbar.minimap.overlays"] = { dispose = function() end, setup = function() end }
        package.loaded["scrollbar.minimap.renderer"] = {
            dispose = function() end,
            setup = function() end,
        }
        package.loaded["scrollbar.minimap.scheduler"] = {
            dispose = function() end,
            setup = function() end,
            invalidate_all = function() end,
        }

        local minimap = require("scrollbar.minimap")
        minimap.setup({ enabled = true, set_highlights = false, providers = { treesitter = true } })
        minimap.setup({ enabled = true, set_highlights = false, providers = { treesitter = false } })
        return values
    end)

    expect.equality(result, {
        { treesitter = true },
        { treesitter = false },
    })
end

T["treesitter results publish spans once without recomputing the same cells"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        require("scrollbar").setup({
            scrollbar = { set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 8,
                height = 2,
                providers = { cursor = false, treesitter = true },
            },
        })
        vim.bo.filetype = "lua"
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1", "return value" })

        local worker = require("scrollbar.minimap.worker")
        local requests = 0
        local original_request = worker.request
        ---@diagnostic disable-next-line: duplicate-set-field
        worker.request = function(request)
            requests = requests + 1
            return original_request(request)
        end

        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.invalidate_all()
        scheduler.flush()
        scheduler.flush()
        worker.request = original_request

        local spans = require("scrollbar.store").get_minimap_spans(vim.api.nvim_get_current_buf()).treesitter
        local priority_ok = true
        for _, span in ipairs(spans or {}) do
            if span.priority ~= require("scrollbar.providers.treesitter").priority then
                priority_ok = false
            end
        end
        return {
            requests = requests,
            spans_present = spans ~= nil,
            priority_ok = priority_ok,
        }
    end)

    expect.equality(result.requests, 1)
    expect.equality(result.spans_present, true)
    expect.equality(result.priority_ok, true)
end

T["MinimapRefresh recollects only minimap provider capabilities and preserves hidden state"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
        local calls = { shared_marks = 0, shared_spans = 0, shared_window = 0, shared_points = 0, scrollbar = 0 }
        local span_priority = 0
        local providers = require("scrollbar.providers")
        providers.register({
            name = "refresh-shared",
            targets = { scrollbar = true, minimap = true },
            refresh_owner = {
                buffer = "provider",
                window = "provider",
                minimap_buffer = "provider",
                minimap_window = "provider",
            },
            refresh = function()
                calls.shared_marks = calls.shared_marks + 1
                return { { line = 0, type = "Misc" } }
            end,
            refresh_window = function()
                calls.shared_window = calls.shared_window + 1
                return { { line = 0, type = "Misc" } }
            end,
            refresh_minimap = function()
                calls.shared_spans = calls.shared_spans + 1
                span_priority = span_priority + 1
                return {
                    {
                        line = 0,
                        start_col = 0,
                        end_col = 1,
                        highlight = "Identifier",
                        priority = span_priority,
                    },
                }
            end,
            refresh_minimap_window = function()
                calls.shared_points = calls.shared_points + 1
                return { { line = 0, col = 0, highlight = "Cursor", priority = 1 } }
            end,
        })
        providers.register({
            name = "refresh-scrollbar-only",
            refresh_owner = { buffer = "provider" },
            refresh = function()
                calls.scrollbar = calls.scrollbar + 1
                return { { line = 0, type = "Misc" } }
            end,
        })

        require("scrollbar").setup({
            scrollbar = {
                set_highlights = false,
                marks = { Misc = { text = "!", priority = 1, highlight = "Identifier" } },
            },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 4,
                height = 2,
            },
        })
        calls = { shared_marks = 0, shared_spans = 0, shared_window = 0, shared_points = 0, scrollbar = 0 }
        local bufnr = vim.api.nvim_get_current_buf()
        local before = require("scrollbar.store")._get_snapshot(bufnr)
        vim.cmd("MinimapHide")
        vim.cmd("MinimapRefresh")
        local after = require("scrollbar.store")._get_snapshot(bufnr)
        return {
            calls = calls,
            mark_revision = { before.revision, after.revision },
            span_revision = { before.minimap_span_revision, after.minimap_span_revision },
            visible = require("scrollbar.minimap.renderer").is_visible(),
        }
    end)

    expect.equality(result.calls, {
        shared_marks = 1,
        shared_spans = 1,
        shared_window = 1,
        shared_points = 1,
        scrollbar = 0,
    })
    expect.equality(result.mark_revision[2], result.mark_revision[1])
    expect.equality(result.span_revision[2], result.span_revision[1] + 1)
    expect.equality(result.visible, false)
end

T["custom treesitter shadow stays parent-executed and keeps its spans"] = function()
    local child = new_child()
    reset_modules(child)
    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a" })
        require("scrollbar.providers").register({
            name = "treesitter",
            targets = { minimap = true },
            refresh_owner = { minimap_buffer = "provider" },
            refresh_minimap = function()
                return {
                    { line = 0, start_col = 0, end_col = 1, highlight = "CustomTS", priority = 500 },
                }
            end,
        })
        require("scrollbar").setup({
            scrollbar = { show = false, set_highlights = false },
            minimap = {
                enabled = true,
                set_highlights = false,
                backend = "sync",
                width = 1,
                height = 1,
                providers = { cursor = false, treesitter = true },
            },
        })
        local scheduler = require("scrollbar.minimap.scheduler")
        scheduler.flush()
        local state = require("scrollbar.minimap.renderer").get_state(vim.api.nvim_get_current_win())
        return {
            execution = require("scrollbar.providers")._execution_mode("treesitter"),
            spans = require("scrollbar.store").get_minimap_spans(vim.api.nvim_get_current_buf()).treesitter,
            highlight = state and state.highlights[1][1] and state.highlights[1][1].highlight or nil,
        }
    end)

    expect.equality(result.execution, "parent")
    expect.equality(result.spans, {
        { line = 0, start_col = 0, end_col = 1, highlight = "CustomTS", priority = 500 },
    })
    expect.equality(result.highlight, "CustomTS")
end

return T
