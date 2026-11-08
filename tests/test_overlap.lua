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
        { { reserve = 1 }, 'scrollbar.overlap.reserve must be a boolean or "virtual_text"' },
        { { reserve = "virtual" }, 'scrollbar.overlap.reserve must be a boolean or "virtual_text"' },
        { { marks = "glyphs" }, "scrollbar.overlap.marks must be one of: glyph, tint" },
        { { extra = true }, "extra" },
    }
    for _, case in ipairs(cases) do
        local message = setup_error(child, { scrollbar = { overlap = case[1] } })
        expect.no_equality(message:find(case[2], 1, true), nil)
    end
end

T["config accepts the virtual_text reserve and keeps true as the default"] = function()
    local child = new_child()
    local accepted = child.lua_func(function()
        local config = require("scrollbar.config")
        local values = { config.set({}).overlap.reserve }
        for _, value in ipairs({ true, false, "virtual_text" }) do
            values[#values + 1] = config.set({ scrollbar = { overlap = { reserve = value } } }).overlap.reserve
        end
        return values
    end)
    expect.equality(accepted, { true, true, false, "virtual_text" })
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

-- The tests of `reserve = "virtual_text"` run where Neovim has no
-- 'wrapcolumn'. With 'wrapcolumn', the reservation uses it, and no pads exist.
local function virtual_text_child()
    local child = new_child()
    if child.lua_get([[(pcall(vim.api.nvim_get_option_info2, "wrapcolumn", {}))]]) then
        MiniTest.skip("Neovim has 'wrapcolumn', which the reservation prefers")
    end
    child.lua([[
        vim.wo.wrap = true

        -- The pads of a window: { row, col, width } for each mark.
        package.loaded["scrollbar.test.pads"] = function(win, buf)
            win = win == 0 and vim.api.nvim_get_current_win() or win
            local state = require("scrollbar.wrap_padding").states[win]
            if state == nil then
                return {}
            end
            local result = {}
            local marks = vim.api.nvim_buf_get_extmarks(buf or 0, state.ns, 0, -1, { details = true })
            for _, mark in ipairs(marks) do
                local details = mark[4]
                assert(details.virt_text_pos == "inline" and details.right_gravity == false)
                result[#result + 1] = { mark[2], mark[3], #details.virt_text[1][1] }
            end
            return result
        end

        -- Characters of the visible lines that end in the covered columns,
        -- and pads that do not end their row.
        -- A `head` of false skips the check of the row starts.
        package.loaded["scrollbar.test.wrap_errors"] = function(win, covered, head)
            win = win == 0 and vim.api.nvim_get_current_win() or win
            local buf = vim.api.nvim_win_get_buf(win)
            local info = vim.fn.getwininfo(win)[1]
            local width = info.width - info.textoff
            local state = require("scrollbar.wrap_padding").states[win]
            local errors = {}
            local first, last = vim.fn.line("w0", win), vim.fn.line("w$", win)
            for lnum = first, last do
                local line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]
                local padded = {}
                for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, state.ns, { lnum - 1, 0 }, { lnum - 1, -1 }, {})) do
                    padded[mark[3] + 1] = true
                end
                local col = 1
                while col <= #line do
                    local size = vim.str_utf_end(line, col) + 1
                    local byte = line:byte(col)
                    local range = vim.fn.virtcol({ lnum, col }, true, win)
                    local cells = vim.fn.strdisplaywidth(line:sub(col, col + size - 1))
                    -- The start of a padded character is the start of its
                    -- pad. The end of a character can include a 'linebreak'
                    -- fill.
                    local last_cell = padded[col] and range[2] or range[1] + cells - 1
                    local start_cell = last_cell - cells + 1
                    if byte ~= 9 and byte ~= 32 and (last_cell - 1) % width + 1 > width - covered then
                        errors[#errors + 1] = string.format("line %d col %d in the covered columns", lnum, col)
                    end
                    if head ~= false and padded[col] and (start_cell - 1) % width ~= (head or 0) then
                        errors[#errors + 1] = string.format("line %d col %d does not start a row", lnum, col)
                    end
                    col = col + size
                end
            end
            return errors
        end
    ]])
    return child
end

local VIRTUAL_TEXT = { overlap = { reserve = "virtual_text" } }

T["virtual_text pads the wrap points of the visible lines"] = function()
    local child = virtual_text_child()
    local result = child.lua_func(function(config)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local pads = require("scrollbar.test.pads")(0)
        local rows = {}
        for _, pad in ipairs(pads) do
            assert(pad[2] == 78 and pad[3] == 2, vim.inspect(pad))
            rows[#rows + 1] = pad[1]
        end
        return {
            rows = rows,
            height = vim.api.nvim_win_get_height(source_win),
            sidescrolloff = vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = source_win }),
            errors = require("scrollbar.test.wrap_errors")(0, 2),
        }
    end, overlap_config(VIRTUAL_TEXT))
    -- Each line of 120 cells needs one pad. The lines from the top line to
    -- the window height get pads.
    local expected = {}
    for row = 0, result.height - 1 do
        expected[#expected + 1] = row
    end
    expect.equality(result.rows, expected)
    expect.equality(result.sidescrolloff, -1)
    expect.equality(result.errors, {})
end

T["virtual_text pads follow a scroll and an edit"] = function()
    local child = virtual_text_child()
    child.lua_func(function(config)
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(vim.api.nvim_get_current_win())
    end, overlap_config(VIRTUAL_TEXT))
    local function pads_of(row)
        return child.lua_func(function(target)
            local result = {}
            for _, pad in ipairs(require("scrollbar.test.pads")(0)) do
                if pad[1] == target then
                    result[#result + 1] = { pad[2], pad[3] }
                end
            end
            return result
        end, row)
    end

    child.type_keys("100Gzt")
    expect.equality(pads_of(0), {})
    expect.equality(pads_of(99), { { 78, 2 } })

    -- An insert of 40 characters makes the line need a second pad.
    child.type_keys("I", string.rep("y", 40))
    expect.equality(pads_of(99), { { 78, 2 }, { 156, 2 } })
    child.type_keys("<Esc>", "0", "dw")
    expect.equality(pads_of(99), {})
    child.type_keys("u")
    expect.equality(pads_of(99), { { 78, 2 }, { 156, 2 } })
    expect.equality(child.lua_get([[require("scrollbar.test.wrap_errors")(0, 2)]]), {})
end

T["virtual_text pads count tabs, wide characters, and the cells before a continuation row"] = function()
    local child = virtual_text_child()
    local result = child.lua_func(function(config)
        local lines = {
            "\tTAB\tline\twith\ttabs\t" .. string.rep("0123456789", 12),
            "日本語のテキスト" .. string.rep("あいうえおかきくけこ", 9),
            "ctrl\1\2\3" .. string.rep("XYZ", 50),
            string.rep("x", 77) .. "日本" .. string.rep("z", 100),
            "    indented " .. string.rep("abcdefghij", 20),
        }
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local check = require("scrollbar.test.wrap_errors")
        local errors = { plain = check(0, 2) }
        vim.cmd("set tabstop=3")
        errors.tabstop = check(0, 2)
        vim.cmd("set list listchars=eol:$")
        errors.list = check(0, 2)
        vim.cmd("set nolist vartabstop=4,6,10")
        errors.vartabstop = check(0, 2)
        -- 'showbreak' cells take a part of each continuation row.
        vim.cmd("set vartabstop= showbreak=>>")
        errors.showbreak = check(0, 2, 2)
        vim.cmd("set showbreak= breakindent breakindentopt=shift:2")
        errors.breakindent = check(0, 2, false)
        local indented = {}
        for _, pad in ipairs(require("scrollbar.test.pads")(0)) do
            if pad[1] == 4 then
                indented[#indented + 1] = { pad[2], pad[3] }
            end
        end
        return { errors = errors, indented = indented }
    end, overlap_config(VIRTUAL_TEXT))
    expect.equality(
        result.errors,
        { plain = {}, tabstop = {}, list = {}, vartabstop = {}, showbreak = {}, breakindent = {} }
    )
    -- The indent of 4 cells and the shift of 2 start each continuation row,
    -- so a continuation row holds 72 cells of text.
    expect.equality(result.indented, { { 78, 2 }, { 150, 2 } })
end

T["virtual_text pads move a word with linebreak"] = function()
    local child = virtual_text_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            -- The word fits in 80 columns, but not in the 78 usable columns.
            string.rep("w", 74) .. " abcd efg",
            -- The word does not fit in 80 columns, so Neovim moves it.
            string.rep("w", 76) .. " abcdef ghi",
        })
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local before = require("scrollbar.test.pads")(0)
        vim.cmd("set linebreak")
        return {
            before = before,
            after = require("scrollbar.test.pads")(0),
            errors = require("scrollbar.test.wrap_errors")(0, 2),
        }
    end, overlap_config(VIRTUAL_TEXT))
    expect.equality(result.before, { { 0, 78, 2 }, { 1, 78, 2 } })
    -- Neovim moves the word of the second line, so it needs no pad.
    expect.equality(result.after, { { 0, 75, 5 } })
    expect.equality(result.errors, {})
end

T["virtual_text pads keep a blank space in the covered columns"] = function()
    local child = virtual_text_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, {
            -- The space is in the first covered column, and the next word
            -- starts in the second.
            string.rep("w", 78) .. " rest",
            string.rep("w", 78) .. "  rest",
        })
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local pads = require("scrollbar.test.pads")(0)
        vim.cmd("set list listchars=space:.")
        return { blank = pads, shown = require("scrollbar.test.pads")(0) }
    end, overlap_config(VIRTUAL_TEXT))
    -- The pad fills the last covered column. Two spaces fill the row, so the
    -- second line needs no pad.
    expect.equality(result.blank, { { 0, 79, 1 } })
    -- 'list' shows each space, so a space gets a pad like a character.
    expect.equality(result.shown, { { 0, 78, 2 }, { 1, 78, 2 } })
end

T["virtual_text pads each window of a buffer for its own width"] = function()
    local child = virtual_text_child()
    local result = child.lua_func(function(config)
        local renderer = require("scrollbar.renderer")
        local left = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        local right = vim.fn.win_getid(vim.fn.winnr("l"))
        left = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_width(left, 30)
        require("scrollbar.test.set_config")(config)
        renderer.setup()
        renderer.render(left)
        renderer.render(right)
        local pads = require("scrollbar.test.pads")
        return {
            left = pads(left)[1],
            right = pads(right)[1],
            right_width = vim.api.nvim_win_get_width(right),
            -- The pads of one window do not move the text of the other.
            left_virtcol = vim.fn.virtcol({ 1, 30 }, true, left)[2],
            right_virtcol = vim.fn.virtcol({ 1, 30 }, true, right)[2],
            errors = {
                left = require("scrollbar.test.wrap_errors")(left, 2),
                right = require("scrollbar.test.wrap_errors")(right, 2),
            },
        }
    end, overlap_config(VIRTUAL_TEXT))
    expect.equality(result.left, { 0, 28, 2 })
    expect.equality(result.right, { 0, result.right_width - 2, 2 })
    expect.equality(result.left_virtcol, 32)
    expect.equality(result.right_virtcol, 30)
    expect.equality(result.errors, { left = {}, right = {} })
end

T["virtual_text pads a buffer only in one window without a window scope"] = function()
    local child = virtual_text_child()
    local result = child.lua_func(function(config)
        -- A Neovim release without `nvim__ns_set`.
        vim.api.nvim__ns_set = nil
        local source_win = vim.api.nvim_get_current_win()
        require("scrollbar.test.set_config")(config)
        local renderer = require("scrollbar.renderer")
        renderer.setup()
        renderer.render(source_win)
        local pads = require("scrollbar.test.pads")
        local single = #pads(source_win)
        vim.cmd("split")
        local split = #pads(source_win)
        vim.cmd("close")
        renderer.render(source_win)
        return { single = single, split = split, closed = #pads(source_win) }
    end, overlap_config(VIRTUAL_TEXT))
    expect.no_equality(result.single, 0)
    expect.equality(result.split, 0)
    expect.equality(result.closed, result.single)
end

T["virtual_text pads go away with nowrap, another buffer, another reserve, and dispose"] = function()
    local child = virtual_text_child()
    local result = child.lua_func(function(config, off)
        local source_win = vim.api.nvim_get_current_win()
        local first_buf = vim.api.nvim_get_current_buf()
        local renderer = require("scrollbar.renderer")
        local function all_pads(buf)
            return #vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { type = "virt_text" })
        end
        require("scrollbar.test.set_config")(config)
        renderer.setup()
        renderer.render(source_win)
        local counts = { start = all_pads(first_buf) }

        -- The OptionSet autocmd removes the pads before the next render.
        vim.wo.wrap = false
        counts.nowrap = all_pads(first_buf)
        renderer.render(source_win)
        counts.sidescrolloff = vim.api.nvim_get_option_value("sidescrolloff", { scope = "local", win = source_win })
        vim.wo.wrap = true
        renderer.render(source_win)
        counts.wrap = all_pads(first_buf)

        -- Another buffer in the window takes the pads.
        vim.cmd("enew")
        local second_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(second_buf, 0, -1, false, { string.rep("z", 100) })
        vim.wo.wrap = true
        renderer.render(source_win)
        counts.first_after_enew = all_pads(first_buf)
        counts.second = all_pads(second_buf)

        require("scrollbar.test.set_config")(off)
        renderer.render(source_win)
        counts.reserve_off = all_pads(second_buf)

        require("scrollbar.test.set_config")(config)
        renderer.render(source_win)
        counts.again = all_pads(second_buf)
        renderer.dispose(source_win)
        counts.disposed = all_pads(second_buf)
        counts.states = vim.tbl_count(require("scrollbar.wrap_padding").states)
        local ok, autocmds = pcall(vim.api.nvim_get_autocmds, { group = "ScrollbarWrapPadding" })
        counts.autocmds = ok and #autocmds or 0
        return counts
    end, overlap_config(VIRTUAL_TEXT), overlap_config({ overlap = { reserve = true } }))
    expect.no_equality(result.start, 0)
    expect.equality(result.nowrap, 0)
    expect.equality(result.sidescrolloff, 2)
    expect.no_equality(result.wrap, 0)
    expect.equality(result.first_after_enew, 0)
    expect.equality(result.second, 1)
    expect.equality(result.reserve_off, 0)
    expect.equality(result.again, 1)
    expect.equality(result.disposed, 0)
    expect.equality(result.states, 0)
    expect.equality(result.autocmds, 0)
end

return T
