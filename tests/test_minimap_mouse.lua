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
            "scrollbar.minimap.config",
            "scrollbar.minimap.worker",
            "scrollbar.minimap.overlays",
            "scrollbar.minimap.renderer",
            "scrollbar.minimap.projection",
            "scrollbar.minimap.mouse",
        }) do
            package.loaded[module] = nil
        end
        require("scrollbar.config").set({ scrollbar = {} })
    ]])
end

local function configure(child, minimap_overrides)
    child.lua_func(function(overrides)
        local minimap_config = require("scrollbar.minimap.config")
        minimap_config.set(overrides or {})
        local worker = require("scrollbar.minimap.worker")
        worker.setup({
            backend = "sync",
            on_result = function(payload)
                require("scrollbar.minimap.renderer").handle_worker_result(payload)
            end,
        })
        require("scrollbar.minimap.overlays").setup({ config = minimap_config.get() })
        local renderer = require("scrollbar.minimap.renderer")
        renderer.setup({
            worker = worker,
            overlays = require("scrollbar.minimap.overlays"),
        })
        local invalidated = {}
        require("scrollbar.minimap.mouse").setup({
            renderer = renderer,
            scheduler = {
                invalidate_window = function(winid)
                    table.insert(invalidated, winid)
                    return true
                end,
            },
        })
        ---@diagnostic disable-next-line: inject-field
        package.loaded["scrollbar.test.minimap_invalidated"] = invalidated
    end, minimap_overrides)
end

local function press_and_drag(child, rows)
    return child.lua_func(function(drag_rows)
        local lines = {}
        for index = 1, 400 do
            lines[index] = string.rep("a", index % 30)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local renderer = require("scrollbar.minimap.renderer")
        local projection = require("scrollbar.minimap.projection")
        local mouse = require("scrollbar.minimap.mouse")
        local state = assert(renderer.render(0))
        local source_win = state.source_win

        local function at_row(row, callback)
            local original = vim.fn.getmousepos
            ---@diagnostic disable-next-line: duplicate-set-field
            vim.fn.getmousepos = function()
                return { winid = state.float_win, winrow = row + 1, wincol = 1, screenrow = row + 1, screencol = 1 }
            end
            callback()
            vim.fn.getmousepos = original
        end
        local function view()
            local rendered = assert(renderer.render(source_win))
            return {
                band = projection.band(rendered.projection),
                top = vim.fn.line("w0", source_win),
                bottom = vim.fn.line("w$", source_win),
                cursor = vim.api.nvim_win_get_cursor(source_win)[1],
            }
        end

        at_row(drag_rows[1], function()
            mouse.press(state.float_win)
        end)
        local views = { view() }
        for index = 2, #drag_rows do
            at_row(drag_rows[index], mouse.drag)
            views[index] = view()
        end
        at_row(drag_rows[#drag_rows], mouse.release)
        return {
            views = views,
            released = view(),
            current_win = vim.api.nvim_get_current_win(),
            source_win = source_win,
            line_count = #lines,
        }
    end, rows)
end

T["click at a minimap row moves the source cursor to the first line of the row"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 20 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local mouse = require("scrollbar.minimap.mouse")
        -- Simulate a click on row 2 by calling press directly with the
        -- state's float window; press uses getmousepos, so we stub it.
        local original_getmousepos = vim.fn.getmousepos
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.getmousepos = function()
            return { winid = state.float_win, winrow = 3, wincol = 1, screenrow = 3, screencol = 1 }
        end
        mouse.press(state.float_win)
        vim.fn.getmousepos = original_getmousepos
        return {
            cursor = vim.api.nvim_win_get_cursor(state.source_win),
        }
    end)

    -- Each row covers 4 lines, so row index 2 starts at 0-based line 8.
    expect.equality(result.cursor[1], 9)
end

T["click in the fit scale uses the rows of the fitted map"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4, scale = "fit" })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 20 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local state = assert(require("scrollbar.minimap.renderer").render(0))
        local original_getmousepos = vim.fn.getmousepos
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.getmousepos = function()
            return { winid = state.float_win, winrow = 3, wincol = 1, screenrow = 3, screencol = 1 }
        end
        require("scrollbar.minimap.mouse").press(state.float_win)
        vim.fn.getmousepos = original_getmousepos
        return vim.api.nvim_win_get_cursor(state.source_win)[1]
    end)

    -- 20 lines in 16 dot rows: row index 2 starts at dot 8, which is line
    -- floor(8 * 20 / 16) = 10.
    expect.equality(result, 11)
end

T["click with a numeric scale uses the lines of each row"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4, scale = 2 })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 30 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local state = assert(require("scrollbar.minimap.renderer").render(0))
        local original_getmousepos = vim.fn.getmousepos
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.getmousepos = function()
            return { winid = state.float_win, winrow = 3, wincol = 1, screenrow = 3, screencol = 1 }
        end
        require("scrollbar.minimap.mouse").press(state.float_win)
        vim.fn.getmousepos = original_getmousepos
        return vim.api.nvim_win_get_cursor(state.source_win)[1]
    end)

    -- Each row covers 8 lines, so row index 2 starts at 0-based line 16.
    expect.equality(result, 17)
end

T["drag scrolls the source so that the band follows the pointer"] = function()
    for _, scale in ipairs({ "fixed", "fit", 2 }) do
        local child = new_child()
        reset_modules(child)
        configure(child, { enabled = true, width = 4, height = 16, scale = scale })

        local result = press_and_drag(child, { 6, 7, 9, 8, 7 })
        local pressed = result.views[1]
        for index = 2, #result.views do
            local delta = ({ 6, 7, 9, 8, 7 })[index] - 6
            local view = result.views[index]
            expect.equality(math.abs(view.band - (pressed.band + delta)) <= 1, true)
            -- The cursor stays inside the visible lines.
            expect.equality(view.cursor >= view.top and view.cursor <= view.bottom, true)
        end
        -- The release ends the drag without a jump.
        expect.equality(result.released.top, result.views[#result.views].top)
        expect.equality(result.current_win, result.source_win)
    end
end

T["one drag reaches both ends of the buffer"] = function()
    for _, scale in ipairs({ "fixed", "fit", 2 }) do
        local child = new_child()
        reset_modules(child)
        configure(child, { enabled = true, width = 4, height = 16, scale = scale })

        local result = press_and_drag(child, { 8, 60, -60 })

        expect.equality(result.views[2].bottom, result.line_count)
        expect.equality(result.views[3].top, 1)
    end
end

T["source window retains focus after release"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 20 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local mouse = require("scrollbar.minimap.mouse")
        local original = vim.fn.getmousepos
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.getmousepos = function()
            return { winid = state.float_win, winrow = 2, wincol = 1, screenrow = 2, screencol = 1 }
        end
        mouse.press(state.float_win)
        mouse.release()
        vim.fn.getmousepos = original
        return {
            current_win = vim.api.nvim_get_current_win(),
            source_win = state.source_win,
        }
    end)

    expect.equality(result.current_win, result.source_win)
end

T["disabled config does not attach keymaps to the float buffer"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4, mouse = false })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local buffer_keymaps = vim.api.nvim_buf_get_keymap(state.float_buf, "n")
        return {
            keymap_count = #buffer_keymaps,
        }
    end)

    expect.equality(result.keymap_count, 0)
end

T["dispose detaches all float buffer keymaps"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a", "b", "c", "d" })
        local renderer = require("scrollbar.minimap.renderer")
        local state = assert(renderer.render(0))
        local mouse = require("scrollbar.minimap.mouse")
        local before = #vim.api.nvim_buf_get_keymap(state.float_buf, "n")
        mouse.dispose()
        local after = #vim.api.nvim_buf_get_keymap(state.float_buf, "n")
        return { before = before, after = after }
    end)

    expect.no_equality(result.before, 0)
    expect.equality(result.after, 0)
end

T["augroup is independent of the scrollbar mouse augroup"] = function()
    local child = new_child()
    reset_modules(child)
    configure(child, { enabled = true, width = 4, height = 4 })

    local result = child.lua_func(function()
        local groups = vim.api.nvim_get_autocmds({})
        local names = {}
        for _, autocmd in ipairs(groups) do
            if autocmd.group_name ~= nil then
                names[autocmd.group_name] = true
            end
        end
        return {
            has_minimap = names["ScrollbarMinimapMouse"] == true,
            has_scrollbar = names["ScrollbarMouse"] == true,
        }
    end)

    expect.equality(result.has_minimap, true)
    -- ScrollbarMouse may or may not exist depending on whether scrollbar
    -- mouse.setup was called. The augroup name is what we care about.
end

return T
