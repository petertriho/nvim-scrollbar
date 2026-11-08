local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    child.lua([[
        require("scrollbar.providers").register({ name = "test" })

        -- Set `scrollbar` as the scrollbar block over the test baseline.
        package.loaded["scrollbar.test.set_config"] = function(scrollbar, shared)
            local options = vim.tbl_extend("force", {
                set_highlights = false,
                providers = { cursor = false, diagnostic = false, search = false },
                exclude = { buftypes = {}, filetypes = {} },
            }, shared or {})
            options.scrollbar = scrollbar
            return require("scrollbar.config").set(options)
        end

        local lines = {}
        for index = 1, 200 do
            lines[index] = string.rep("x", 120)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.wo.wrap = false
    ]])
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

local function overlap_config(overrides)
    return require("scrollbar.config.schema").merge({
        show = true,
        throttle_ms = 0,
        unit = "line",
        placement = { relative = "window", anchor = "NE", row = 0, col = 0 },
        layout = {
            columns = {
                { "track", "marks" },
                { "track", "thumb" },
            },
        },
        mouse = false,
        hide_on_cursor = false,
        thumb = { text = "H", hide_if_all_visible = false },
        marks = { Misc = { text = "M" } },
    }, overrides or {})
end

-- Without a UI, Neovim does not settle the position of an east float, so the
-- cursor tests use a west float that reserves no gutter.
local WEST = { anchor = "NW", gutter = "overlap" }

local function setup_error(child, options)
    return child.lua_func(function(setup_options)
        local ok, message = pcall(require("scrollbar.config").set, setup_options)
        return ok and "" or message
    end, options)
end

T["config defaults reserve the text and hide the whole float"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local active = require("scrollbar.config").set({})
        return { overlap = active.overlap, hide_on_cursor = active.hide_on_cursor }
    end)
    expect.equality(result, {
        overlap = { reserve = true, show_through = false, marks = "glyph" },
        hide_on_cursor = true,
    })
end

T["config accepts the row mode and rejects other cursor values"] = function()
    local child = new_child()
    local accepted = child.lua_func(function()
        local config = require("scrollbar.config")
        local values = {}
        for _, value in ipairs({ true, false, "row" }) do
            values[#values + 1] = config.set({ scrollbar = { hide_on_cursor = value } }).hide_on_cursor
        end
        return values
    end)
    expect.equality(accepted, { true, false, "row" })

    expect.no_equality(
        setup_error(child, { scrollbar = { hide_on_cursor = "rows" } }):find(
            'scrollbar.hide_on_cursor must be a boolean or "row"',
            1,
            true
        ),
        nil
    )
    -- The minimap keeps the boolean option.
    expect.no_equality(
        setup_error(child, { minimap = { enabled = true, hide_on_cursor = "row" } }):find(
            "minimap.hide_on_cursor must be a boolean",
            1,
            true
        ),
        nil
    )
end

T["config validates the overlap block"] = function()
    local child = new_child()
    local cases = {
        { { show_through = 0 }, "scrollbar.overlap.show_through must be false or an integer between 1 and 100" },
        { { show_through = 101 }, "scrollbar.overlap.show_through must be false or an integer between 1 and 100" },
        { { show_through = true }, "scrollbar.overlap.show_through must be false or an integer between 1 and 100" },
        { { reserve = 1 }, "scrollbar.overlap.reserve must be a boolean" },
        { { marks = "glyphs" }, "scrollbar.overlap.marks must be one of: glyph, tint" },
        { { extra = true }, "extra" },
    }
    for _, case in ipairs(cases) do
        local message = setup_error(child, { scrollbar = { overlap = case[1] } })
        expect.no_equality(message:find(case[2], 1, true), nil)
    end
end

T["a profile can set the overlap block"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local config = require("scrollbar.config")
        config.set({
            scrollbar = {
                overlap = { reserve = false },
                profiles = {
                    { match = { filetypes = { "markdown" } }, overlap = { show_through = 40, marks = "tint" } },
                },
            },
        })
        local variants = config.get_variants()
        return { root = variants[1].config.overlap, profile = variants[2].config.overlap }
    end)
    expect.equality(result.root, { reserve = false, show_through = false, marks = "glyph" })
    expect.equality(result.profile, { reserve = false, show_through = 40, marks = "tint" })
end

T["the float blends only when a cell needs it"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        local config = require("scrollbar.config")
        local overlap = require("scrollbar.overlap")
        local function winblend(scrollbar)
            return overlap.float_winblend(config.set({ scrollbar = scrollbar }))
        end
        return {
            default = winblend({}),
            opaque_thumb = winblend({ thumb = { blend = 0 } }),
            row = winblend({ thumb = { blend = 0 }, hide_on_cursor = "row" }),
            show_through = winblend({ overlap = { show_through = 60 } }),
            window = winblend({ window = { wo = { winblend = 20 } }, overlap = { show_through = 60 } }),
        }
    end)
    expect.equality(result, { default = 1, opaque_thumb = 0, row = 1, show_through = 60, window = 20 })
end

T["show_through blends the track, the thumb, and the base"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        vim.api.nvim_set_hl(0, "PmenuSbar", { bg = "#112233" })
        vim.api.nvim_set_hl(0, "PmenuThumb", { bg = "#445566" })
        vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#778899" })
        require("scrollbar").setup({
            providers = { cursor = false, diagnostic = false, search = false, marks = false },
            marks = { Error = { highlight = { fg = "#ff0000" } } },
            scrollbar = {
                show = false,
                mouse = false,
                hide_on_cursor = "row",
                overlap = { show_through = 60, marks = "tint" },
                profiles = {
                    { match = { filetypes = { "markdown" } }, thumb = { blend = 80 }, overlap = { show_through = 20 } },
                },
            },
        })
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        return {
            base = get("ScrollbarBase"),
            track = get("ScrollbarTrack"),
            thumb = get("ScrollbarThumb"),
            tint = get("ScrollbarErrorTint"),
            surface = get("ScrollbarGenerated.Surface60"),
            clear = get("ScrollbarGenerated.Clear"),
            profile_base = get("ScrollbarProfile1.Base"),
            profile_track = get("ScrollbarProfile1.Track"),
            profile_thumb = get("ScrollbarProfile1.Thumb"),
            profile_tint = get("ScrollbarProfile1.ErrorTint"),
        }
    end)

    expect.equality(result.base, { blend = 100, sp = 0 })
    expect.equality(result.track, { bg = 0x112233, blend = 60 })
    -- The thumb shows the text at least as much as the track.
    expect.equality(result.thumb, { bg = 0x445566, blend = 60 })
    expect.equality(result.tint, { bg = 0xFF0000, blend = 60 })
    expect.equality(result.surface, { blend = 60, sp = 0 })
    expect.equality(result.clear, { blend = 100, sp = 0 })
    expect.equality(result.profile_base, { blend = 100, sp = 0 })
    expect.equality(result.profile_track, { bg = 0x112233, blend = 20 })
    expect.equality(result.profile_thumb, { bg = 0x445566, blend = 80 })
    expect.equality(result.profile_tint, { bg = 0xFF0000, blend = 20 })
end

T["the blend-only groups exist without automatic highlights"] = function()
    local child = new_child()
    local result = child.lua_func(function()
        require("scrollbar").setup({
            set_highlights = false,
            scrollbar = { show = false, hide_on_cursor = "row", overlap = { show_through = 40 } },
        })
        return {
            clear = vim.api.nvim_get_hl(0, { name = "ScrollbarGenerated.Clear" }),
            surface = vim.api.nvim_get_hl(0, { name = "ScrollbarGenerated.Surface40" }),
        }
    end)
    expect.equality(result, { clear = { blend = 100, sp = 0 }, surface = { blend = 40, sp = 0 } })
end

T["the float gets the winblend and the base of its configuration"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        local state = assert(renderer.render(source_win))
        local first = vim.api.nvim_get_option_value("winblend", { win = state.float_win })

        config.overlap = { show_through = 70 }
        require("scrollbar.test.set_config")(config)
        state = assert(renderer.render(source_win))
        return {
            first = first,
            second = vim.api.nvim_get_option_value("winblend", { win = state.float_win }),
            winhighlight = vim.api.nvim_get_option_value("winhighlight", { win = state.float_win }),
        }
    end, overlap_config())
    expect.equality(result.first, 1)
    expect.equality(result.second, 70)
    expect.no_equality(result.winhighlight:find("Normal:ScrollbarBase,", 1, true), nil)
end

T["row mode clears only the row under the cursor"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        local reader = require("scrollbar.test.float")
        renderer.setup()

        -- Row 10 is below the thumb.
        local cursor = { row = 10, col = 1 }
        rawset(vim.fn, "screenrow", function()
            return cursor.row
        end)
        rawset(vim.fn, "screencol", function()
            return cursor.col
        end)
        local function snapshot()
            local state = assert(renderer.render(source_win))
            local groups = {}
            for _, mark in ipairs(reader.extmarks(state.float_buf, -1, { 9, 0 }, { 9, -1 }, { details = true })) do
                groups[#groups + 1] = mark[4].hl_group
            end
            return {
                hidden = vim.api.nvim_win_get_config(state.float_win).hide == true,
                cleared_row = state.cleared_row,
                row = reader.lines(state.float_buf, 9, 10)[1],
                groups = groups,
            }
        end

        local under = snapshot()
        cursor.col = 10
        local beside = snapshot()
        return { under = under, beside = beside }
    end, overlap_config({ hide_on_cursor = "row", placement = WEST }))

    expect.equality(result.under.hidden, false)
    expect.equality(result.under.cleared_row, 10)
    expect.equality(result.under.row, "  ")
    expect.equality(result.under.groups, { "ScrollbarGenerated.Clear" })
    expect.equality(result.beside.hidden, false)
    expect.equality(result.beside.cleared_row, nil)
    expect.equality(result.beside.row, "  ")
    expect.equality(result.beside.groups, { "ScrollbarTrack" })
end

T["row mode hides the whole float when the cursor is on the border"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        -- The first row of the frame is the top border.
        rawset(vim.fn, "screenrow", function()
            return 1
        end)
        rawset(vim.fn, "screencol", function()
            return 1
        end)
        local state = assert(renderer.render(source_win))
        return { hidden = vim.api.nvim_win_get_config(state.float_win).hide == true, cleared = state.cleared_row }
    end, overlap_config({ hide_on_cursor = "row", placement = WEST, window = { border = "single" } }))
    expect.equality(result, { hidden = true })
end

T["true still hides the whole float under the cursor"] = function()
    local child = new_child()
    local hidden = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        rawset(vim.fn, "screenrow", function()
            return 3
        end)
        rawset(vim.fn, "screencol", function()
            return 1
        end)
        local state = assert(renderer.render(source_win))
        return vim.api.nvim_win_get_config(state.float_win).hide == true and state.cleared_row == nil
    end, overlap_config({ hide_on_cursor = true, placement = WEST }))
    expect.equality(hidden, true)
end

T["tint marks are spaces in the tint group"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local store = require("scrollbar.shared.store")
        assert(store.set("test", vim.api.nvim_win_get_buf(source_win), { { line = 199, type = "Misc" } }))
        local renderer = require("scrollbar.renderer")
        local reader = require("scrollbar.test.float")
        renderer.setup()
        local state = assert(renderer.render(source_win))
        local last = state.height - 1
        local groups = {}
        for _, mark in ipairs(reader.extmarks(state.float_buf, -1, { last, 0 }, { last, -1 }, { details = true })) do
            groups[mark[4].hl_group] = true
        end
        return { row = reader.lines(state.float_buf, last, last + 1)[1], groups = groups }
    end, overlap_config({ overlap = { marks = "tint" } }))
    expect.equality(result.row, "  ")
    expect.equality(result.groups, { ScrollbarTrack = true, ScrollbarMiscTint = true })
end

T["show_through puts the surface under a glyph mark without a track"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            local source_win = vim.api.nvim_get_current_win()
            require("scrollbar.test.set_config")(config)
            local store = require("scrollbar.shared.store")
            assert(store.set("test", vim.api.nvim_win_get_buf(source_win), { { line = 199, type = "Misc" } }))
            local renderer = require("scrollbar.renderer")
            local reader = require("scrollbar.test.float")
            renderer.setup()
            local state = assert(renderer.render(source_win))
            local last = state.height - 1
            local spans = {}
            for _, mark in ipairs(reader.extmarks(state.float_buf, -1, { last, 0 }, { last, -1 }, { details = true })) do
                spans[#spans + 1] = { mark[3], mark[4].end_col, mark[4].hl_group }
            end
            table.sort(spans, function(left, right)
                if left[1] ~= right[1] then
                    return left[1] < right[1]
                end
                return left[3] < right[3]
            end)
            return { row = reader.lines(state.float_buf, last, last + 1)[1], spans = spans }
        end,
        overlap_config({
            overlap = { show_through = 50 },
            layout = { columns = { { "marks" }, { "track", "thumb" } } },
        })
    )
    expect.equality(result.row, "M ")
    expect.equality(result.spans, {
        { 0, 1, "ScrollbarGenerated.Surface50" },
        { 0, 1, "ScrollbarMisc" },
        { 1, 2, "ScrollbarTrack" },
    })
end

T["the default reserve keeps the cursor out of an east scrollbar and restores the option"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        local function siso()
            return vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = source_win })
        end
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local reserved = siso()

        -- An edit of the user wins over the reservation.
        vim.api.nvim_set_option_value("sidescrolloff", 5, { scope = "local", win = source_win })
        renderer.render(source_win)
        local larger = siso()
        vim.api.nvim_set_option_value("sidescrolloff", 0, { scope = "local", win = source_win })
        renderer.render(source_win)
        local smaller = siso()

        renderer.dispose(source_win)
        local disposed = siso()
        return { reserved = reserved, larger = larger, smaller = smaller, disposed = disposed }
    end, overlap_config())
    expect.equality(result, { reserved = 2, larger = 5, smaller = 2, disposed = 0 })
end

T["reserve counts the columns that a negative col adds"] = function()
    local child = new_child()
    local reserved = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        return vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = source_win })
    end, overlap_config({ overlap = { reserve = true }, placement = { col = -3 } }))
    expect.equality(reserved, 5)
end

T["reserve leaves the options alone for a west anchor or when it is off"] = function()
    local child = new_child()
    local result = child.lua_func(function(west, off)
        local source_win = vim.api.nvim_get_current_win()
        local renderer = require("scrollbar.renderer")
        local values = {}
        for _, config in ipairs({ west, off }) do
            require("scrollbar.test.set_config")(config)
            renderer.setup()
            renderer.render(source_win)
            values[#values + 1] = vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = source_win })
            renderer.dispose(source_win)
        end
        return values
    end, overlap_config({ placement = { anchor = "NW" } }), overlap_config({ overlap = { reserve = false } }))
    expect.equality(result, { -1, -1 })
end

T["reserve moves from sidescrolloff to wrapcolumn when wrap turns on"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        local overlap = require("scrollbar.overlap")
        local function value(name)
            return vim.api.nvim_get_option_value(name, { scope = "local", win = source_win })
        end
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local before = value("sidescrolloff")
        vim.wo[source_win].wrap = true
        renderer.render(source_win)
        local info = vim.fn.getwininfo(source_win)[1]
        return {
            before = before,
            after = value("sidescrolloff"),
            supported = overlap.wrapcolumn_supported(),
            wrapcolumn = overlap.wrapcolumn_supported() and value("wrapcolumn") or nil,
            expected = info.width - info.textoff - 2,
        }
    end, overlap_config({ overlap = { reserve = true } }))
    expect.equality(result.before, 2)
    expect.equality(result.after, -1)
    if result.supported then
        expect.equality(result.wrapcolumn, result.expected)
    end
end

return T
