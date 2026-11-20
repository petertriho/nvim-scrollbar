local MiniTest = MiniTest
local helpers = require("tests.helpers")

local M = {}

M.new_child = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

--- A configuration with only the test provider and a scrollbar of two columns:
--- the marks in the left column and the thumb in the right column, so that the
--- thumb covers no mark.
---@param top? table Top-level overrides
---@return table
M.config = function(top)
    local schema = require("scrollbar.config.schema")
    return schema.merge({
        set_highlights = true,
        providers = {
            cursor = false,
            diagnostic = false,
            search = false,
            marks = false,
        },
        exclude = { buftypes = {}, filetypes = {} },
        scrollbar = {
            throttle_ms = 0,
            placement = { anchor = "NE" },
            layout = {
                direction = "ltr",
                columns = {
                    { "track", "marks" },
                    { "track", "thumb" },
                },
            },
            thumb = { hide_if_all_visible = false },
        },
    }, top or {})
end

--- Fill the current buffer, set the configuration, and render the scrollbar of
--- the current window. The marks come from the provider `test`. With
--- `full = true`, the call runs `require("scrollbar").setup()`. Otherwise it
--- sets up only the configuration, the renderer, and the scheduler, so that no
--- built-in provider changes the store.
---@param child table
---@param options { config?: table, marks?: table[], compact?: integer[], line_count?: integer, full?: boolean, window_marks?: table[], targets?: table }
---@return { source_win: integer, source_buf: integer, float_win?: integer, float_buf?: integer }
M.setup = function(child, options)
    return child.lua_func(function(opts)
        vim.o.mouse = "a"
        local lines = {}
        for index = 1, opts.line_count do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        local source_win = vim.api.nvim_get_current_win()
        local source_buf = vim.api.nvim_get_current_buf()

        local providers = require("scrollbar.providers")
        if providers.get("test") == nil then
            providers.register({ name = "test", targets = opts.targets })
        end
        local store = require("scrollbar.shared.store")
        local renderer = require("scrollbar.renderer")
        local scheduler = require("scrollbar.scheduler")
        if opts.full then
            require("scrollbar").setup(opts.config)
        else
            local active_config = require("scrollbar.config").set(opts.config)
            renderer.setup()
            require("scrollbar.highlights").set_highlights()
            scheduler.setup({ config = active_config, renderer = renderer })
        end
        if #opts.marks > 0 then
            assert(store.set("test", source_buf, opts.marks))
        end
        if #opts.window_marks > 0 then
            assert(store.set_window("test", source_win, opts.window_marks))
        end
        if opts.compact ~= nil then
            local compact = require("scrollbar.providers.search.compact").encode(opts.compact)
            assert(store._set_search_compact(source_buf, compact))
        end
        local state = renderer.render(source_win)
        vim.cmd("redraw")
        return {
            source_win = source_win,
            source_buf = source_buf,
            float_win = state and state.float_win or nil,
            float_buf = state and state.float_buf or nil,
        }
    end, {
        config = options.config or M.config(),
        marks = options.marks or {},
        window_marks = options.window_marks or {},
        compact = options.compact,
        line_count = options.line_count or 200,
        full = options.full == true,
        targets = options.targets,
    })
end

--- The text of screen rows `first` to `last` (1-based), columns `first_col`
--- to `last_col`.
M.screen_rows = function(child, first, last, first_col, last_col)
    local text = child.get_screenshot().text
    local rows = {}
    for row = first, last do
        rows[#rows + 1] = table.concat(text[row], "", first_col or 1, last_col or #text[row])
    end
    return rows
end

return M
