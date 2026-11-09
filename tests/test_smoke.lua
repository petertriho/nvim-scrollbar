local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

T["loads and sets up in a clean child process"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    expect.no_error(function()
        child.lua([[
            require("scrollbar").setup({
                set_highlights = false,
                providers = {
                    cursor = false,
                    diagnostic = false,
                    gitsigns = false,
                    search = false,
                    ale = false,
                    coc = false,
                },
                scrollbar = { throttle_ms = 0 },
            })
        ]])
    end)
    expect.equality(child.fn.exists(":ScrollbarToggle"), 2)
    expect.equality(child.fn.exists(":ScrollbarShow"), 2)
    expect.equality(child.fn.exists(":ScrollbarHide"), 2)
    expect.equality(child.fn.exists(":ScrollbarRefresh"), 2)
end

T["enables accepted search and leaves Coc disabled by default"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        require("scrollbar").setup({
            set_highlights = false,
            scrollbar = {
                throttle_ms = 0,
                mouse = false,
            },
        })

        local plan = require("scrollbar.config").get_provider_plan()
        local providers = require("scrollbar.providers")
        return {
            search = plan.search.options,
            coc = plan.coc.options,
            search_registered = providers.get("search") ~= nil,
            coc_registered = providers.get("coc") ~= nil,
        }
    end)

    expect.equality(result, {
        search = { backend = "worker" },
        coc = false,
        search_registered = true,
        coc_registered = false,
    })
end

T["opens both floats without the winborder border"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        vim.o.winborder = "rounded"
        local lines = {}
        for index = 1, 200 do
            lines[index] = string.rep("x", 40)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        require("scrollbar").setup({
            set_highlights = false,
            providers = { cursor = false, diagnostic = false, search = false, marks = false },
            scrollbar = { throttle_ms = 0, hide_on_cursor = false },
            minimap = { enabled = true, backend = "sync", width = 4, hide_on_cursor = false },
        })
        for _, name in ipairs({ "scrollbar.scheduler", "scrollbar.minimap.scheduler" }) do
            require(name).invalidate_all()
            require(name).flush()
        end
        local source_win = vim.api.nvim_get_current_win()
        local function bordered(module)
            local state = assert(require(module).get_state(source_win))
            return type(vim.api.nvim_win_get_config(state.float_win).border) == "table"
        end
        return {
            scrollbar = bordered("scrollbar.renderer"),
            minimap = bordered("scrollbar.minimap.renderer"),
        }
    end)

    expect.equality(result, { scrollbar = false, minimap = false })
end

-- Issue #122: 'hlsearch' is global, and Neovim colors the search matches in
-- the buffer text of every window, floats included. With buffer text, a match
-- can also drop the mark color of a cell. The search provider is off, so the
-- float content is the same with 'hlsearch' on and off, and every float cell
-- must keep its attribute. `screenattr()` reads the float grid, and its
-- attribute id changes with any change of the cell colors.
-- (`nvim__inspect_cell` does not report the drawn colors on Neovim 0.12.6.)
T["keeps the search highlight out of both floats"] = function()
    -- Every character, the letter mark, the mark glyphs, the whole row, and
    -- the matches at the start or the end of a line, some of them empty.
    local patterns = { ".", "a", "=", "-", ".*", "$", "\\s*", "^", "^$", "\\n" }
    -- The minimap base is `ScrollbarMinimapBase`, or a group that the
    -- numeric blend resolves.
    for _, background_blend in ipairs({ false, 20 }) do
        local child = helpers.new_child()
        MiniTest.finally(function()
            helpers.stop_child(child)
        end)

        local result = child.lua_func(function(search_patterns, minimap_blend)
            vim.o.termguicolors = true
            vim.api.nvim_set_hl(0, "Search", { fg = "#000000", bg = "#ffff00" })
            vim.api.nvim_set_hl(0, "CurSearch", { fg = "#000000", bg = "#ff00ff" })
            vim.api.nvim_set_hl(0, "IncSearch", { fg = "#000000", bg = "#00ffff" })
            local lines = {}
            for index = 1, 80 do
                -- Empty lines make blank minimap rows.
                lines[index] = (index % 4 == 0 or index > 40) and ""
                    or ("local value_" .. index .. " = " .. index .. " - 1")
            end
            vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
            require("scrollbar.providers").register({ name = "test" })
            require("scrollbar").setup({
                providers = { cursor = false, diagnostic = false, search = false, marks = false },
                marks = { Misc = { text = "a", highlight = { fg = "#ff8800" } } },
                scrollbar = { throttle_ms = 0, hide_on_cursor = false },
                minimap = {
                    enabled = true,
                    backend = "sync",
                    width = 8,
                    hide_on_cursor = false,
                    background_blend = minimap_blend,
                },
            })
            local source_win = vim.api.nvim_get_current_win()
            -- Marks outside the thumb use groups that set only a foreground.
            assert(require("scrollbar.shared.store").set("test", vim.api.nvim_get_current_buf(), {
                { line = 30, type = "Misc" },
                { line = 50, type = "Error" },
                { line = 70, type = "Warn" },
            }))
            for _, name in ipairs({ "scrollbar.scheduler", "scrollbar.minimap.scheduler" }) do
                require(name).invalidate_all()
                require(name).flush()
            end
            local states = {
                scrollbar = assert(require("scrollbar.renderer").get_state(source_win)),
                minimap = assert(require("scrollbar.minimap.renderer").get_state(source_win)),
            }
            local windows = {
                source = source_win,
                scrollbar = states.scrollbar.float_win,
                minimap = states.minimap.float_win,
            }

            local foreground_marks = { Error = 0, Misc = 0 }
            for _, spans in ipairs(states.scrollbar.rendered_highlights) do
                for _, span in ipairs(spans) do
                    local group = vim.api.nvim_get_hl(0, { name = span.highlight, link = false })
                    for mark_type, count in pairs(foreground_marks) do
                        if span.highlight:find(mark_type, 1, true) and group.fg ~= nil and group.bg == nil then
                            foreground_marks[mark_type] = count + 1
                        end
                    end
                end
            end
            local blank_rows = {}
            for name, state in pairs(states) do
                local count = 0
                for _, row in ipairs(state.rows) do
                    if row:match("^%s*$") then
                        count = count + 1
                    end
                end
                blank_rows[name] = count
            end
            local letter_rows = 0
            for _, row in ipairs(states.scrollbar.rows) do
                if row:find("a", 1, true) then
                    letter_rows = letter_rows + 1
                end
            end

            local invalid = 0
            local function attributes()
                vim.cmd("redraw!")
                local by_window = {}
                for name, win in pairs(windows) do
                    local position = vim.fn.win_screenpos(win)
                    local cells = {}
                    for row = 0, vim.api.nvim_win_get_height(win) - 1 do
                        for col = 0, vim.api.nvim_win_get_width(win) - 1 do
                            local attribute = vim.fn.screenattr(position[1] + row, position[2] + col)
                            if attribute < 0 then
                                invalid = invalid + 1
                            end
                            cells[#cells + 1] = attribute
                        end
                    end
                    by_window[name] = cells
                end
                return by_window
            end

            -- The first redraw of the child allocates the screen.
            vim.cmd("redraw!")
            local changed = {}
            for _, pattern in ipairs(search_patterns) do
                vim.fn.setreg("/", pattern)
                vim.o.hlsearch = false
                local off = attributes()
                vim.o.hlsearch = true
                vim.v.hlsearch = 1
                local on = attributes()
                local counts = {}
                for name, cells in pairs(off) do
                    local count = 0
                    for index, attribute in ipairs(cells) do
                        if on[name][index] ~= attribute then
                            count = count + 1
                        end
                    end
                    counts[name] = count
                end
                changed[pattern] = counts
            end
            return {
                invalid = invalid,
                changed = changed,
                blank_rows = blank_rows,
                letter_rows = letter_rows,
                foreground_marks = foreground_marks,
            }
        end, patterns, background_blend)

        expect.equality(result.invalid, 0)
        expect.equality(result.foreground_marks.Error > 0, true)
        expect.equality(result.foreground_marks.Misc > 0, true)
        expect.equality(result.letter_rows > 0, true)
        expect.equality(result.blank_rows.scrollbar > 0, true)
        expect.equality(result.blank_rows.minimap > 0, true)
        -- The patterns that leave the source window unchanged, and the float
        -- cells that a pattern changes. The source window shows the matches,
        -- so the check is live.
        local unchanged_source = {}
        local changed_floats = {}
        for _, pattern in ipairs(patterns) do
            local counts = result.changed[pattern]
            if counts.source == 0 then
                unchanged_source[#unchanged_source + 1] = pattern
            end
            for _, name in ipairs({ "scrollbar", "minimap" }) do
                if counts[name] ~= 0 then
                    changed_floats[name .. " " .. pattern] = counts[name]
                end
            end
        end
        local case = { background_blend = background_blend }
        expect.equality({ case = case, unchanged_source = unchanged_source }, { case = case, unchanged_source = {} })
        expect.equality({ case = case, changed_floats = changed_floats }, { case = case, changed_floats = {} })
    end
end

return T
