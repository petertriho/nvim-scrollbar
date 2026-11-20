local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local MARKS = {
    { line = 20, type = "Error" },
    { line = 60, type = "Warn" },
    { line = 150, type = "Info" },
}

local DELAY_MS = 100

local function hover_config(scrollbar, top)
    return navigate.config(vim.tbl_deep_extend("force", {
        scrollbar = vim.tbl_deep_extend("force", { hover = { delay_ms = DELAY_MS } }, scrollbar or {}),
    }, top or {}))
end

local function setup(child, options)
    options = options or {}
    options.marks = options.marks or MARKS
    options.config = options.config or hover_config()
    options.full = true
    return navigate.setup(child, options)
end

--- Zero-based screen position of the first column of the cell of `line` on the
--- scrollbar of `win`.
local function cell_position(child, line, win)
    return child.lua_func(function(target, source)
        source = source or vim.api.nvim_get_current_win()
        local state = assert(require("scrollbar.renderer").get_state(source))
        for _, cell in ipairs(require("scrollbar.navigate.targets").cells(source)) do
            if cell.line == target then
                local position = vim.fn.win_screenpos(state.float_win)
                return {
                    position[1] - 1 + state.sides.top + cell.row,
                    position[2] - 1 + state.sides.left + cell.col - 1,
                }
            end
        end
        error("no cell for line " .. target)
    end, line, win)
end

local function move(child, position)
    child.api.nvim_input_mouse("move", "", "", 0, position[1], position[2])
    vim.uv.sleep(20)
end

local function peek_line(child)
    local state = child.lua_get("require('scrollbar.navigate.peek').get()")
    return state ~= vim.NIL and state.line or nil
end

local function wait()
    vim.uv.sleep(DELAY_MS + 100)
end

T["a pointer at rest on a mark opens the peek after the delay"] = function()
    local child = navigate.new_child()
    setup(child)
    expect.equality(child.o.mousemoveevent, true)
    local position = cell_position(child, 60)
    move(child, position)
    expect.equality(peek_line(child), nil)
    wait()
    expect.equality(peek_line(child), 60)
    -- The peek is centered on the row of the cell, beside the scrollbar.
    local peek = child.lua_get("require('scrollbar.navigate.peek').get()")
    local peek_position = child.api.nvim_win_get_position(peek.win)
    local peek_height = child.api.nvim_win_get_height(peek.win)
    expect.equality(peek_position[1] + math.floor(peek_height / 2), position[1])
    -- The marks are in the first column of the scrollbar.
    expect.equality(peek_position[2] + child.api.nvim_win_get_width(peek.win), position[2])
    -- No labels.
    expect.equality(child.lua_get("require('scrollbar.navigate.jump').active()"), false)
end

T["a move inside the same cell keeps the peek"] = function()
    local child = navigate.new_child()
    setup(child)
    local position = cell_position(child, 60)
    move(child, position)
    wait()
    local win = child.lua_get("require('scrollbar.navigate.peek').get().win")
    move(child, position)
    wait()
    expect.equality(child.lua_get("require('scrollbar.navigate.peek').get().win"), win)
end

T["the peek closes when the pointer leaves the cell, and moves to another cell"] = function()
    local child = navigate.new_child()
    setup(child)
    move(child, cell_position(child, 60))
    wait()
    expect.equality(peek_line(child), 60)
    move(child, { 5, 5 })
    expect.equality(peek_line(child), nil)

    move(child, cell_position(child, 60))
    wait()
    move(child, cell_position(child, 150))
    expect.equality(peek_line(child), nil)
    wait()
    expect.equality(peek_line(child), 150)
end

T["a pointer that leaves before the delay opens no peek"] = function()
    local child = navigate.new_child()
    setup(child)
    move(child, cell_position(child, 60))
    move(child, { 5, 5 })
    wait()
    expect.equality(peek_line(child), nil)
end

T["any other key closes the peek"] = function()
    local child = navigate.new_child()
    setup(child)
    move(child, cell_position(child, 60))
    wait()
    expect.equality(peek_line(child), 60)
    child.api.nvim_input("l")
    vim.uv.sleep(20)
    expect.equality(peek_line(child), nil)
end

T["a scroll of the source window closes the peek"] = function()
    local child = navigate.new_child()
    setup(child)
    move(child, cell_position(child, 60))
    wait()
    expect.equality(peek_line(child), 60)
    -- Neovim fires `WinScrolled` after the key or the event that scrolled, so
    -- the test fires it after the scroll.
    child.lua([[
        vim.api.nvim_exec_autocmds("WinScrolled", {})
    ]])
    expect.equality(peek_line(child), 60)
    child.lua([[
        vim.fn.winrestview({ topline = 30 })
        vim.api.nvim_exec_autocmds("WinScrolled", {})
    ]])
    expect.equality(peek_line(child), nil)
end

T["does nothing with mouse = false"] = function()
    local child = navigate.new_child()
    setup(child, { config = hover_config({ mouse = false }) })
    move(child, cell_position(child, 60))
    wait()
    expect.equality(peek_line(child), nil)
end

T["does nothing during label mode, and a pointer move keeps label mode"] = function()
    local child = navigate.new_child()
    setup(child)
    local position = cell_position(child, 60)
    child.lua([[
        _G.jump_done = false
        vim.schedule(function()
            require("scrollbar.navigate.jump").run()
            _G.jump_done = true
        end)
    ]])
    vim.uv.sleep(50)
    move(child, position)
    wait()
    expect.equality(peek_line(child), nil)
    expect.equality(child.lua_get("_G.jump_done"), false)
    -- The second label is on line 60.
    child.api.nvim_input("s")
    vim.uv.sleep(50)
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(child.api.nvim_win_get_cursor(0), { 61, 0 })
end

T["does nothing on the scrollbar of a floating source window"] = function()
    local child = navigate.new_child()
    setup(child)
    local float_win = child.lua([[
        local always = function()
            return true
        end
        local user = require("tests.navigate.helpers").config({
            scrollbar = { hover = { delay_ms = 100 }, floats = { when = always } },
        })
        require("scrollbar").setup(user)
        local buf = vim.api.nvim_get_current_buf()
        -- The setup clears the store.
        assert(require("scrollbar.shared.store").set("test", buf, { { line = 60, type = "Warn" } }))
        local win = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 2, col = 2, width = 40, height = 15 })
        require("scrollbar.scheduler").invalidate_all()
        require("scrollbar.scheduler").flush()
        vim.cmd("redraw")
        return win
    ]])
    expect.equality(child.lua_get("require('scrollbar.renderer').get_state(...) ~= nil", { float_win }), true)
    move(child, cell_position(child, 60, float_win))
    wait()
    expect.equality(peek_line(child), nil)
end

T["'mousemoveevent'"] = MiniTest.new_set()

T["'mousemoveevent'"]["a setup without hover restores it, and a setup closes the peek"] = function()
    local child = navigate.new_child()
    setup(child)
    move(child, cell_position(child, 60))
    wait()
    expect.equality(peek_line(child), 60)
    child.lua_func(function(config)
        require("scrollbar").setup(config)
    end, navigate.config())
    expect.equality(child.o.mousemoveevent, false)
    expect.equality(peek_line(child), nil)
    expect.equality(child.lua_get("require('scrollbar.navigate.hover').shown()"), vim.NIL)
end

T["'mousemoveevent'"]["stays on when it was on before the setup"] = function()
    local child = navigate.new_child()
    child.o.mousemoveevent = true
    setup(child)
    child.lua_func(function(config)
        require("scrollbar").setup(config)
    end, navigate.config())
    expect.equality(child.o.mousemoveevent, true)
end

T["'mousemoveevent'"]["stays off when the scrollbar is disabled"] = function()
    local child = navigate.new_child()
    setup(child, { config = hover_config({ enabled = false }) })
    expect.equality(child.o.mousemoveevent, false)
end

return T
