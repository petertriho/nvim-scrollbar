local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Installs `require("scrollbar.test.pickers")` in the child. It stubs the
-- picker state of snacks.nvim and Telescope in `package.loaded`, and it opens
-- the picker windows as plain floats.
local function install_pickers()
    local M = {}
    local snacks = {}
    local telescope = {}

    package.loaded["snacks.picker.core.picker"] = {
        get = function()
            return snacks
        end,
    }
    package.loaded["telescope.state"] = {
        get_existing_prompt_bufnrs = function()
            local result = {}
            for bufnr in pairs(telescope) do
                result[#result + 1] = bufnr
            end
            table.sort(result)
            return result
        end,
        get_status = function(bufnr)
            return { picker = telescope[bufnr] }
        end,
    }

    M.lines = function(count)
        local result = {}
        for index = 1, count do
            result[index] = "line " .. index
        end
        return result
    end

    M.float = function(options)
        local bufnr = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, M.lines(options.lines or 100))
        return vim.api.nvim_open_win(bufnr, false, {
            relative = "editor",
            row = options.row or 2,
            col = options.col or 2,
            width = options.width or 30,
            height = options.height or 10,
            zindex = options.zindex,
        })
    end

    -- The list buffer holds only the visible rows, like the virtual list of
    -- snacks.
    M.snacks = function(options)
        options = options or {}
        local height = options.height or 10
        local input = M.float({ row = 1, col = 2, height = 1, lines = 1 })
        local list_win = M.float({ row = 3, col = 2, height = height, lines = height })
        local preview = M.float({ row = 3, col = 34, height = height })
        local list = {
            win = { win = list_win },
            top = options.top or 1,
            state = { height = height },
            reverse = options.reverse or false,
            items = options.count or 100,
            moves = {},
        }
        function list:count()
            return self.items
        end
        function list:move(position, absolute)
            self.moves[#self.moves + 1] = { position, absolute }
        end
        local picker = {
            input = { win = { win = input } },
            list = list,
            preview = { win = { win = preview } },
            layout = { wins = {}, box_wins = {} },
        }
        snacks[#snacks + 1] = picker
        return picker
    end

    M.telescope = function()
        local prompt = M.float({ row = 15, col = 2, height = 1, lines = 1 })
        local results = M.float({ row = 17, col = 2, height = 5 })
        local preview = M.float({ row = 17, col = 34, height = 5 })
        local picker = { prompt_win = prompt, results_win = results, preview_win = preview }
        telescope[vim.api.nvim_win_get_buf(prompt)] = picker
        return picker
    end

    M.snacks_moves = function()
        return snacks[1].list.moves
    end

    M.clear = function()
        for index = #snacks, 1, -1 do
            snacks[index] = nil
        end
        for bufnr in pairs(telescope) do
            telescope[bufnr] = nil
        end
    end

    package.loaded["scrollbar.test.pickers"] = M
end

local function new_child()
    local child = helpers.new_child()
    child.lua_func(install_pickers)
    child.lua([[
        package.loaded["scrollbar.test.set_config"] = function(scrollbar, shared)
            local options = vim.tbl_extend("force", {
                set_highlights = false,
                providers = { cursor = false, diagnostic = false, search = false },
                exclude = { buftypes = {}, filetypes = {} },
            }, shared or {})
            options.scrollbar = scrollbar
            return require("scrollbar.config").set(options)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, require("scrollbar.test.pickers").lines(100))
    ]])
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

local function float_config(overrides)
    return require("scrollbar.config.schema").merge({
        show = true,
        throttle_ms = 0,
        unit = "line",
        hide_on_cursor = false,
        placement = { relative = "window", anchor = "NE", row = 0, col = 0 },
        layout = { columns = { { "track", "thumb" } } },
        mouse = false,
        thumb = { text = "H", hide_if_all_visible = false },
    }, overrides or {})
end

-- Options for `require("scrollbar").setup()`.
local function setup_options(scrollbar)
    return {
        set_highlights = false,
        providers = { cursor = false, diagnostic = false, search = false },
        exclude = { buftypes = {}, filetypes = {} },
        scrollbar = vim.tbl_deep_extend("force", { hide_on_cursor = false, throttle_ms = 0 }, scrollbar),
    }
end

T["a float is a source only when the floats option admits its kind"] = function()
    local child = new_child()
    local result = child.lua_func(function(base)
        local pickers = require("scrollbar.test.pickers")
        local snacks = pickers.snacks()
        local telescope = pickers.telescope()
        local plain = pickers.float({ row = 13, col = 40, width = 20, height = 3 })
        local owned = pickers.float({ row = 13, col = 62, width = 10, height = 3 })
        vim.w[owned].scrollbar_owned = true
        local minimap_owned = pickers.float({ row = 17, col = 66, width = 10, height = 2 })
        vim.w[minimap_owned].scrollbar_minimap_owned = true
        local external = pickers.float({ row = 20, col = 66, width = 10, height = 2 })
        -- Headless Neovim cannot open an external window.
        local get_config = vim.api.nvim_win_get_config
        rawset(vim.api, "nvim_win_get_config", function(winid)
            local value = get_config(winid)
            if winid == external then
                value.external = true
            end
            return value
        end)

        local windows = {
            normal = vim.api.nvim_get_current_win(),
            input = snacks.input.win.win,
            list = snacks.list.win.win,
            preview = snacks.preview.win.win,
            prompt = telescope.prompt_win,
            results = telescope.results_win,
            telescope_preview = telescope.preview_win,
            plain = plain,
            owned = owned,
            minimap_owned = minimap_owned,
            external = external,
        }
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local function kinds(floats)
            base.floats = floats
            require("scrollbar.test.set_config")(base)
            renderer.invalidate_source_selection()
            local kind = {}
            for name, winid in pairs(windows) do
                kind[name] = renderer.source_kind(winid) or false
            end
            return kind
        end
        local everything = function()
            return true
        end
        return {
            off = kinds(false),
            on = kinds(true),
            snacks_preview = kinds({ snacks = { preview = true } }),
            telescope = kinds({ telescope = true }),
            telescope_results = kinds({ telescope = { results = true } }),
            when = kinds({ when = everything }),
        }
    end, float_config())

    local none = {
        normal = "normal",
        input = false,
        list = false,
        preview = false,
        prompt = false,
        results = false,
        telescope_preview = false,
        plain = false,
        owned = false,
        minimap_owned = false,
        external = false,
    }
    local function with(kinds)
        return vim.tbl_extend("force", none, kinds)
    end
    expect.equality(result.off, none)
    expect.equality(
        result.on,
        with({
            list = "snacks_list",
            preview = "snacks_preview",
            results = "telescope_results",
            telescope_preview = "telescope_preview",
        })
    )
    expect.equality(result.snacks_preview, with({ preview = "snacks_preview" }))
    expect.equality(result.telescope, with({ results = "telescope_results", telescope_preview = "telescope_preview" }))
    expect.equality(result.telescope_results, with({ results = "telescope_results" }))
    -- `when` admits the floats that are not picker kinds, and never the
    -- floats of the renderers or the external windows.
    expect.equality(result.when, with({ input = "custom", prompt = "custom", plain = "custom" }))
end

T["floats.when gets the documented context, and an error notifies once"] = function()
    local child = new_child()
    local result = child.lua_func(function(base)
        local pickers = require("scrollbar.test.pickers")
        local snacks = pickers.snacks()
        local plain = pickers.float({ row = 13, col = 40, width = 20, height = 3 })
        local plain_buf = vim.api.nvim_win_get_buf(plain)
        vim.api.nvim_buf_set_name(plain_buf, "/tmp/scrollbar-floats-when.txt")
        vim.bo[plain_buf].filetype = "floatstest"

        local contexts = {}
        local fail = false
        base.floats = {
            snacks = { preview = true },
            when = function(context)
                contexts[#contexts + 1] = context
                if fail then
                    error("boom", 0)
                end
                return context.winid == plain
            end,
        }
        require("scrollbar.test.set_config")(base)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local notes = {}
        rawset(vim, "notify", function(message, level)
            notes[#notes + 1] = { message, level }
        end)
        local function kind(winid)
            renderer.invalidate_source_selection()
            return renderer.source_kind(winid) or false
        end

        local kinds = {
            normal = kind(vim.api.nvim_get_current_win()),
            list = kind(snacks.list.win.win),
            preview = kind(snacks.preview.win.win),
            input = kind(snacks.input.win.win),
            plain = kind(plain),
        }
        local seen = {}
        for _, context in ipairs(contexts) do
            seen[#seen + 1] = context.winid
        end
        local context = contexts[#contexts]

        fail = true
        local failed = { kind(plain), kind(plain), kind(plain) }
        local notes_after_failures = #notes
        require("scrollbar.test.set_config")(base)
        kind(plain)

        return {
            kinds = kinds,
            seen = seen,
            expected_seen = { snacks.input.win.win, plain },
            context = {
                winid = context.winid == plain,
                bufnr = context.bufnr == plain_buf,
                filetype = context.filetype,
                buftype = context.buftype,
                bufname = context.bufname,
                relative = context.config.relative,
                row = context.config.row,
                col = context.config.col,
            },
            failed = failed,
            notes_after_failures = notes_after_failures,
            note = notes[1],
            notes_after_reset = #notes,
        }
    end, float_config())

    expect.equality(result.kinds, {
        normal = "normal",
        list = false,
        preview = "snacks_preview",
        input = false,
        plain = "custom",
    })
    expect.equality(result.seen, result.expected_seen)
    expect.equality(result.context, {
        winid = true,
        bufnr = true,
        filetype = "floatstest",
        buftype = "nofile",
        bufname = "/tmp/scrollbar-floats-when.txt",
        relative = "editor",
        row = 13,
        col = 40,
    })
    expect.equality(result.failed, { false, false, false })
    expect.equality(result.notes_after_failures, 1)
    expect.equality(
        result.note,
        { "[nvim-scrollbar] scrollbar floats.when matcher failed: boom", vim.log.levels.ERROR }
    )
    -- A new configuration notifies again.
    expect.equality(result.notes_after_reset, 2)
end

T["exclude and max_lines apply to floats, and max_lines counts the items of the snacks list"] = function()
    local child = new_child()
    local result = child.lua_func(function(base)
        local pickers = require("scrollbar.test.pickers")
        local snacks = pickers.snacks({ count = 500 })
        local list = snacks.list
        local list_win = list.win.win
        local preview = snacks.preview.win.win
        vim.bo[vim.api.nvim_win_get_buf(preview)].filetype = "excluded"
        base.floats = true
        base.max_lines = 200
        require("scrollbar.test.set_config")(base, { exclude = { buftypes = {}, filetypes = { "excluded" } } })
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local function kind(winid)
            renderer.invalidate_source_selection()
            return renderer.source_kind(winid) or false
        end

        local kinds = { preview = kind(preview), long_list = kind(list_win) }
        list.items = 150
        kinds.short_list = kind(list_win)
        kinds.rendered = renderer.render(list_win) ~= nil
        -- A list that the adapter cannot read gets no bar.
        list.state = nil
        kinds.unreadable = kind(list_win)
        kinds.unreadable_render = renderer.render(list_win) ~= nil
        kinds.unreadable_state = renderer.get_state(list_win) ~= nil
        return kinds
    end, float_config())

    expect.equality(result, {
        preview = false,
        long_list = false,
        short_list = "snacks_list",
        rendered = true,
        unreadable = false,
        unreadable_render = false,
        unreadable_state = false,
    })
end

T["the snacks list bar follows the list position, not the buffer"] = function()
    local child = new_child()
    local result = child.lua_func(function(base)
        local pickers = require("scrollbar.test.pickers")
        local snacks = pickers.snacks({ count = 100, height = 10 })
        local list = snacks.list
        local list_win = list.win.win
        base.floats = true
        require("scrollbar.test.set_config")(base)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local function geometry()
            local state = assert(renderer.render(list_win))
            return {
                handle = { state.handle.first_row, state.handle.last_row },
                geometry = state.geometry,
            }
        end

        local top = geometry()
        list.top = 21
        local middle = geometry()
        list.reverse = true
        local reversed = geometry()
        return { top = top, middle = middle, reversed = reversed }
    end, float_config())

    expect.equality(result.top, {
        handle = { 0, 0 },
        geometry = { unit = "line", total_extent = 100, viewport_start = 0, viewport_end = 9 },
    })
    expect.equality(result.middle, {
        handle = { 1, 2 },
        geometry = { unit = "line", total_extent = 100, viewport_start = 20, viewport_end = 29 },
    })
    -- In a reversed list, item 1 is on the bottom row.
    expect.equality(result.reversed, {
        handle = { 6, 7 },
        geometry = { unit = "line", total_extent = 100, viewport_start = 70, viewport_end = 79 },
    })
end

T["the snacks list adapter maps the view and mirrors a reversed list"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local pickers = require("scrollbar.test.pickers")
        local adapter = require("scrollbar.floats.snacks")
        local snacks = pickers.snacks({ count = 100, top = 11, height = 10 })
        local list = snacks.list
        local win = list.win.win
        local count = list.count

        local views = { forward = adapter.view(win) }
        list.reverse = true
        views.reversed = adapter.view(win)
        list.reverse = false
        list.top = 95
        views.tail = adapter.view(win)
        list.items = 0
        list.top = 1
        views.empty = adapter.view(win)
        list.items = 100
        list.state = nil
        views.no_state = adapter.view(win) or false
        list.state = { height = 10 }
        list.top = nil
        views.no_top = adapter.view(win) or false
        list.top = 1
        list.count = nil
        views.no_count = adapter.view(win) or false
        list.count = count
        views.not_a_list = adapter.view(snacks.preview.win.win) or false
        return views
    end)

    expect.equality(result, {
        forward = { count = 100, top = 10, bottom = 19, reverse = false },
        reversed = { count = 100, top = 80, bottom = 89, reverse = true },
        tail = { count = 100, top = 94, bottom = 99, reverse = false },
        empty = { count = 1, top = 0, bottom = 0, reverse = false },
        no_state = false,
        no_top = false,
        no_count = false,
        not_a_list = false,
    })
end

T["the snacks list adapter moves the list to the visual position"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local pickers = require("scrollbar.test.pickers")
        local adapter = require("scrollbar.floats.snacks")
        local list = pickers.snacks({ count = 100 }).list
        local win = list.win.win

        local moved = {
            adapter.navigate(win, 0),
            adapter.navigate(win, 41),
            adapter.navigate(win, 500),
            adapter.navigate(win, -3),
        }
        -- `List:move` mirrors a reversed list itself.
        list.reverse = true
        moved[#moved + 1] = adapter.navigate(win, 5)
        list.items = 0
        moved[#moved + 1] = adapter.navigate(win, 5)
        return { moved = moved, moves = list.moves }
    end)

    expect.equality(result.moved, { true, true, true, true, true, false })
    expect.equality(result.moves, { { 1, true }, { 42, true }, { 100, true }, { 1, true }, { 6, true } })
end

T["the snacks list hook wraps List.render once and calls the callback after it"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local pickers = require("scrollbar.test.pickers")
        local adapter = require("scrollbar.floats.snacks")
        local list = pickers.snacks().list
        local win = list.win.win
        local calls = {}

        package.loaded["snacks.picker.core.list"] = nil
        local missing_module = adapter.install(function() end)
        package.loaded["snacks.picker.core.list"] = {}
        local missing_render = adapter.install(function() end)

        local List = {}
        function List.render(_, value)
            calls[#calls + 1] = "render " .. value
            return "rendered", value
        end
        package.loaded["snacks.picker.core.list"] = List
        local first = adapter.install(function(winid)
            calls[#calls + 1] = "first " .. tostring(winid == win)
        end)
        local wrapped = List.render
        local second = adapter.install(function(winid)
            calls[#calls + 1] = "second " .. tostring(winid == win)
        end)
        local results = { List.render(list, 1) }

        adapter.install(function()
            error("boom")
        end)
        local ok, value = pcall(List.render, list, 2)

        -- A reload of the module keeps the one wrapper.
        package.loaded["scrollbar.floats.snacks"] = nil
        require("scrollbar.floats.snacks").install(function(winid)
            calls[#calls + 1] = "reloaded " .. tostring(winid == win)
        end)
        List.render(list, 3)

        return {
            missing_module = missing_module,
            missing_render = missing_render,
            first = first,
            second = second,
            same_wrapper = List.render == wrapped,
            results = results,
            failed_callback = { ok, value },
            calls = calls,
        }
    end)

    expect.equality(result, {
        missing_module = false,
        missing_render = false,
        first = true,
        second = true,
        same_wrapper = true,
        results = { "rendered", 1 },
        failed_callback = { true, "rendered" },
        calls = { "render 1", "second true", "render 2", "render 3", "reloaded true" },
    })
end

T["a render of the snacks list renders its bar again"] = function()
    local child = new_child()
    local result = child.lua_func(function(scrollbar)
        local List = {}
        function List.render(_) end
        package.loaded["snacks.picker.core.list"] = List
        local pickers = require("scrollbar.test.pickers")
        local list = pickers.snacks({ count = 100 }).list
        local list_win = list.win.win
        scrollbar.floats = true
        require("scrollbar").setup({
            set_highlights = false,
            providers = { cursor = false, diagnostic = false, search = false },
            exclude = { buftypes = {}, filetypes = {} },
            scrollbar = scrollbar,
        })
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        scheduler.invalidate_all()
        scheduler.flush()
        local before = renderer.get_state(list_win).handle.first_row

        -- The list scrolls without a window event. Its render calls the hook.
        list.top = 91
        List.render(list)
        scheduler.flush()
        return { before = before, after = renderer.get_state(list_win).handle.first_row }
    end, float_config())

    expect.equality(result, { before = 0, after = 8 })
end

T["the default exclude keeps the bar off the snacks input, also when `when` accepts it"] = function()
    local child = new_child()
    local result = child.lua_func(function(options)
        local pickers = require("scrollbar.test.pickers")
        local snacks = pickers.snacks()
        local input = snacks.input.win.win
        local input_buf = vim.api.nvim_win_get_buf(input)
        vim.api.nvim_buf_set_lines(input_buf, 0, -1, false, pickers.lines(100))
        vim.bo[input_buf].filetype = "snacks_picker_input"
        local plain = pickers.float({ row = 13, col = 40, width = 20, height = 3 })
        options.scrollbar.floats = {
            when = function()
                return true
            end,
        }
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        local function bars()
            scheduler.invalidate_all()
            scheduler.flush()
            return { input = renderer.get_state(input) ~= nil, plain = renderer.get_state(plain) ~= nil }
        end

        -- The `{}` lists of `setup_options` remove the default entries.
        options.exclude = nil
        require("scrollbar").setup(options)
        local default = bars()
        options.exclude = { filetypes = { snacks_picker_input = false } }
        require("scrollbar").setup(options)
        return { default = default, without_entry = bars() }
    end, setup_options({}))

    expect.equality(result, {
        default = { input = false, plain = true },
        without_entry = { input = true, plain = true },
    })
end

T["visibility active shows the picker bars while the picker has focus"] = function()
    local child = new_child()
    local result = child.lua_func(function(options)
        local pickers = require("scrollbar.test.pickers")
        local normal = vim.api.nvim_get_current_win()
        require("scrollbar").setup(options)
        local snacks = pickers.snacks()
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        local function bars()
            scheduler.invalidate_all()
            scheduler.flush()
            return {
                normal = renderer.get_state(normal) ~= nil,
                input = renderer.get_state(snacks.input.win.win) ~= nil,
                list = renderer.get_state(snacks.list.win.win) ~= nil,
                preview = renderer.get_state(snacks.preview.win.win) ~= nil,
            }
        end

        local seen = { before = bars() }
        vim.api.nvim_set_current_win(snacks.input.win.win)
        seen.input = bars()
        vim.api.nvim_set_current_win(snacks.list.win.win)
        seen.list = bars()
        vim.api.nvim_set_current_win(normal)
        seen.after = bars()
        return seen
    end, setup_options({ visibility = "active", floats = true }))

    local outside = { normal = true, input = false, list = false, preview = false }
    local inside = { normal = false, input = false, list = true, preview = true }
    expect.equality(result, { before = outside, input = inside, list = inside, after = outside })
end

T["the bar of a float source is one zindex above its source"] = function()
    local child = new_child()
    local result = child.lua_func(function(base)
        local pickers = require("scrollbar.test.pickers")
        local low = pickers.float({ row = 13, col = 40, width = 20, height = 5, zindex = 30 })
        local snacks = pickers.snacks()
        base.floats = {
            snacks = true,
            when = function(context)
                return context.winid == low
            end,
        }
        require("scrollbar.test.set_config")(base)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local function zindex(winid)
            local state = assert(renderer.render(winid))
            return vim.api.nvim_win_get_config(state.float_win).zindex
        end
        return {
            low = zindex(low),
            list = zindex(snacks.list.win.win),
            preview = zindex(snacks.preview.win.win),
            normal = zindex(vim.api.nvim_get_current_win()),
        }
    end, float_config({ placement = { zindex = 40 } }))

    -- `placement.zindex` applies only to normal windows.
    expect.equality(result, { low = 31, list = 51, preview = 51, normal = 40 })
end

T["a stacked pair on a float source stays above the source"] = function()
    local function zindexes(stack)
        local child = new_child()
        return child.lua_func(function(stack_name)
            local pickers = require("scrollbar.test.pickers")
            local source = pickers.float({ row = 2, col = 2, width = 40, height = 15, zindex = 30 })
            local function when(context)
                return context.winid == source
            end
            require("scrollbar").setup({
                set_highlights = false,
                providers = { cursor = false, diagnostic = false, search = false },
                exclude = { buftypes = {}, filetypes = {} },
                scrollbar = {
                    hide_on_cursor = false,
                    layout = { columns = { { "track", "thumb" } } },
                    floats = { when = when },
                },
                minimap = {
                    enabled = true,
                    backend = "sync",
                    width = 4,
                    hide_on_cursor = false,
                    encoding = "block",
                    placement = { stack = stack_name },
                    floats = { when = when },
                },
            })
            local scheduler = require("scrollbar.scheduler")
            local minimap_scheduler = require("scrollbar.minimap.scheduler")
            for _ = 1, 2 do
                scheduler.invalidate_all()
                scheduler.flush()
                minimap_scheduler.invalidate_all()
                minimap_scheduler.flush()
            end
            local function zindex(renderer)
                local state = assert(require(renderer).get_state(source))
                return vim.api.nvim_win_get_config(state.float_win).zindex
            end
            return {
                scrollbar = zindex("scrollbar.renderer"),
                minimap = zindex("scrollbar.minimap.renderer"),
            }
        end, stack)
    end

    expect.equality(zindexes("above"), { scrollbar = 31, minimap = 32 })
    expect.equality(zindexes("below"), { scrollbar = 32, minimap = 31 })
end

T["a moved source float gets the bar configuration again"] = function()
    local child = new_child()
    local result = child.lua_func(function(base)
        local pickers = require("scrollbar.test.pickers")
        local source = pickers.float({ row = 2, col = 2, height = 10 })
        base.floats = {
            when = function(context)
                return context.winid == source
            end,
        }
        require("scrollbar.test.set_config")(base)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local state = assert(renderer.render(source))
        local set_config = vim.api.nvim_win_set_config
        local calls = 0
        rawset(vim.api, "nvim_win_set_config", function(winid, value)
            if winid == state.float_win then
                calls = calls + 1
            end
            return set_config(winid, value)
        end)

        renderer.render(source)
        local steady = calls
        set_config(source, { relative = "editor", row = 6, col = 12 })
        renderer.render(source)
        local moved = calls
        renderer.render(source)
        local after = calls
        rawset(vim.api, "nvim_win_set_config", set_config)
        return {
            steady = steady,
            moved = moved,
            after = after,
            parent = vim.api.nvim_win_get_config(state.float_win).win == source,
        }
    end, float_config())

    expect.equality(result, { steady = 0, moved = 1, after = 1, parent = true })
end

T["the gutter reservation comes back after a picker resets statuscolumn"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(options)
            local pickers = require("scrollbar.test.pickers")
            local snacks = pickers.snacks()
            local preview = snacks.preview.win.win
            vim.wo[preview].statuscolumn = "%l "
            require("scrollbar").setup(options)
            local renderer = require("scrollbar.renderer")
            local scheduler = require("scrollbar.scheduler")
            local function flush()
                scheduler.invalidate_all()
                scheduler.flush()
            end
            local function textoff()
                return vim.fn.getwininfo(preview)[1].textoff
            end

            flush()
            local wrapper = vim.wo[preview].statuscolumn
            local reserved = textoff()

            -- Snacks shows the next file in the preview and resets the option
            -- without `OptionSet`.
            local other = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(other, 0, -1, false, pickers.lines(100))
            vim.api.nvim_win_set_buf(preview, other)
            vim.api.nvim_win_call(preview, function()
                vim.cmd("noautocmd setlocal statuscolumn=")
            end)
            local reset = textoff()
            scheduler.flush()
            local restored = vim.wo[preview].statuscolumn
            local restored_textoff = textoff()

            -- The source stops matching. The release keeps the value of snacks.
            pickers.clear()
            renderer.invalidate_source_selection()
            flush()
            return {
                owner = wrapper:match("_statuscolumn%((%d+)%)") == tostring(preview),
                reserved = reserved > 0,
                reset = reset,
                restored = restored == wrapper,
                restored_textoff = restored_textoff,
                released = vim.wo[preview].statuscolumn,
                released_state = renderer.get_state(preview) ~= nil,
            }
        end,
        setup_options({
            floats = { snacks = { preview = true } },
            placement = { anchor = "NW", gutter = "outer" },
        })
    )

    expect.equality(result, {
        owner = true,
        reserved = true,
        reset = 0,
        restored = true,
        restored_textoff = 1,
        released = "",
        released_state = false,
    })
end

T["the cursor overlap check of a float source uses screen positions"] = function()
    local child = new_child()
    local result = child.lua_func(function(base)
        local pickers = require("scrollbar.test.pickers")
        local source = pickers.float({ row = 4, col = 10, width = 30, height = 10 })
        base.floats = {
            when = function(context)
                return context.winid == source
            end,
        }
        require("scrollbar.test.set_config")(base)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        vim.api.nvim_set_current_win(source)

        -- Inside a float, `screenrow()` and `screencol()` count from the
        -- corner of the float.
        local cursor = { row = 1, col = 1 }
        local screenrow = vim.fn.screenrow
        local screencol = vim.fn.screencol
        rawset(vim.fn, "screenrow", function()
            return cursor.row
        end)
        rawset(vim.fn, "screencol", function()
            return cursor.col
        end)
        local function hidden()
            local state = assert(renderer.render(source))
            return vim.api.nvim_win_get_config(state.float_win).hide == true
        end

        local under = hidden()
        cursor.col = 8
        local beside = hidden()
        rawset(vim.fn, "screenrow", screenrow)
        rawset(vim.fn, "screencol", screencol)
        return { under = under, beside = beside }
    end, float_config({ hide_on_cursor = true, placement = { anchor = "NW" } }))

    expect.equality(result, { under = true, beside = false })
end

T["a click on the snacks list track moves the list"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(options)
            vim.o.mouse = "a"
            local pickers = require("scrollbar.test.pickers")
            local list = pickers.snacks({ count = 100, height = 10 }).list
            local list_win = list.win.win
            require("scrollbar").setup(options)
            local renderer = require("scrollbar.renderer")
            local scheduler = require("scrollbar.scheduler")
            scheduler.invalidate_all()
            scheduler.flush()
            vim.cmd("redraw")
            local state = assert(renderer.get_state(list_win))
            local position = vim.api.nvim_win_get_position(state.float_win)
            return {
                row = position[1] + 6,
                col = position[2],
                handle = { state.handle.first_row, state.handle.last_row },
                list_win = list_win,
            }
        end,
        setup_options({
            floats = true,
            mouse = true,
            placement = { anchor = "NW" },
            layout = { columns = { { "track", "thumb" } } },
        })
    )

    expect.equality(result.handle, { 0, 0 })
    child.api.nvim_input_mouse("left", "press", "", 0, result.row, result.col)
    vim.uv.sleep(30)
    child.api.nvim_input_mouse("left", "release", "", 0, result.row, result.col)
    vim.uv.sleep(30)

    -- Track row 6 of 10 maps to item 67 of 100.
    expect.equality(
        child.lua_func(function()
            return require("scrollbar.test.pickers").snacks_moves()
        end),
        { { 67, true } }
    )
end

T["a text change of a float source renders its bars again without a TextChanged event"] = function()
    local child = new_child()
    child.lua_func(function(options)
        local pickers = require("scrollbar.test.pickers")
        local watch = {}
        package.loaded["scrollbar.test.watch"] = watch
        watch.source = pickers.float({ row = 2, col = 2, height = 10 })
        options.scrollbar.floats = {
            when = function(context)
                return context.winid == watch.source
            end,
        }
        options.minimap = {
            enabled = true,
            backend = "sync",
            throttle_ms = 0,
            floats = options.scrollbar.floats,
        }
        require("scrollbar").setup(options)
        require("scrollbar.scheduler").invalidate_all()
        require("scrollbar.scheduler").flush()
        require("scrollbar.minimap.scheduler").invalidate_all()
        require("scrollbar.minimap.scheduler").flush()
        watch.bars = function()
            return {
                total_extent = require("scrollbar.renderer").get_state(watch.source).geometry.total_extent,
                cells = vim.inspect(require("scrollbar.minimap.renderer").get_state(watch.source).rows),
            }
        end
        watch.before = watch.bars()
        -- The normal window keeps focus, as the prompt of a picker does.
        local lines = {}
        for index = 1, 300 do
            lines[index] = string.rep("x", 28)
        end
        vim.api.nvim_buf_set_lines(vim.api.nvim_win_get_buf(watch.source), 0, -1, false, lines)
    end, setup_options({}))

    -- The change queues the renders on the main loop of the child.
    vim.uv.sleep(50)
    local result = child.lua_get([[(function()
        local watch = require("scrollbar.test.watch")
        return { before = watch.before, after = watch.bars() }
    end)()]])
    expect.equality(result.before.total_extent, 100)
    expect.equality(result.after.total_extent, 300)
    expect.no_equality(result.after.cells, result.before.cells)
end

T["invalidate_all renders the windows that become sources before the flush"] = function()
    local child = new_child()
    local result = child.lua_func(function(options)
        local pickers = require("scrollbar.test.pickers")
        require("scrollbar").setup(options)
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        local telescope = pickers.telescope()
        local state = package.loaded["telescope.state"]
        local get_status = state.get_status
        -- Telescope enters the prompt before it registers the picker.
        local registered = false
        state.get_status = function(bufnr)
            return registered and get_status(bufnr) or {}
        end
        scheduler.invalidate_all()
        scheduler.flush()
        local before = renderer.get_state(telescope.results_win) ~= nil

        scheduler.invalidate_all()
        registered = true
        scheduler.flush()
        return {
            before = before,
            results = renderer.get_state(telescope.results_win) ~= nil,
            preview = renderer.get_state(telescope.preview_win) ~= nil,
        }
    end, setup_options({ floats = true }))

    expect.equality(result, { before = false, results = true, preview = true })
end

return T
