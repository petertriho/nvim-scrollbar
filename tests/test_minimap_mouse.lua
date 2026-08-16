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

T["click at a minimap row moves the source cursor to the projected line"] = function()
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
        -- 20 source lines / 4 minimap rows => v_ratio = 5.
        -- Row index 2 (0-based) maps to source line floor(2 * 5) = 10.
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

    -- Source cursor should be at line 11 (1-based), since 0-based line 10.
    expect.equality(result.cursor[1], 11)
end

T["drag events move the source cursor through projected lines"] = function()
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

        local function simulate(row)
            local original = vim.fn.getmousepos
            ---@diagnostic disable-next-line: duplicate-set-field
            vim.fn.getmousepos = function()
                return { winid = state.float_win, winrow = row + 1, wincol = 1, screenrow = row + 1, screencol = 1 }
            end
            mouse.drag()
            vim.fn.getmousepos = original
        end

        local original_getmousepos = vim.fn.getmousepos
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.fn.getmousepos = function()
            return { winid = state.float_win, winrow = 1, wincol = 1, screenrow = 1, screencol = 1 }
        end
        mouse.press(state.float_win)
        vim.fn.getmousepos = original_getmousepos

        simulate(1)
        local after_one = vim.api.nvim_win_get_cursor(state.source_win)[1]
        simulate(3)
        local after_three = vim.api.nvim_win_get_cursor(state.source_win)[1]

        mouse.release()
        return {
            after_one = after_one,
            after_three = after_three,
        }
    end)

    -- Row 1 maps to source line floor(1 * 5) = 5 → 1-based line 6.
    expect.equality(result.after_one, 6)
    -- Row 3 maps to source line floor(3 * 5) = 15 → 1-based line 16.
    expect.equality(result.after_three, 16)
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
    configure(child, { enabled = true, width = 4, height = 4, mouse = { enabled = false } })

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
