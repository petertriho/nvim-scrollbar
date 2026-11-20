local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local MARKS = {
    { line = 20, type = "Error" },
    { line = 60, type = "Warn" },
    { line = 150, type = "Info" },
}

local function capture_notes(child)
    child.lua([[
        _G.notes = {}
        vim.notify = function(message, level)
            table.insert(_G.notes, { message, level })
        end
    ]])
end

local function setup(child, options)
    options = options or {}
    options.marks = options.marks or MARKS
    options.full = true
    local result = navigate.setup(child, options)
    capture_notes(child)
    return result
end

local function notes(child)
    return child.lua_get("_G.notes")
end

local function glance_lines(child)
    local state = child.lua_get("require('scrollbar.navigate.glance').get()")
    if state == vim.NIL then
        return nil
    end
    return child.api.nvim_buf_get_lines(state.list_buf, 0, -1, false)
end

local function close_glance(child)
    child.lua("require('scrollbar.navigate.glance').close(true)")
end

local WARN = vim.log.levels.WARN
local ERROR = vim.log.levels.ERROR

T["jump() and glance() before setup() notify and do nothing"] = function()
    local child = navigate.new_child()
    capture_notes(child)
    child.lua([[
        require("scrollbar").jump()
        require("scrollbar").glance()
    ]])
    expect.equality(notes(child), {
        { "[nvim-scrollbar] jump() needs setup() first", WARN },
        { "[nvim-scrollbar] glance() needs setup() first", WARN },
    })
    expect.equality(#child.api.nvim_list_wins(), 1)
    expect.equality(child.fn.exists(":ScrollbarJump"), 0)
    expect.equality(child.fn.exists(":ScrollbarGlance"), 0)
end

T["jump() runs label mode with the types filter"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        vim.api.nvim_feedkeys("a", "t", false)
        require("scrollbar").jump({ types = { "Info" } })
    ]])
    expect.equality(child.api.nvim_win_get_cursor(0), { 151, 0 })
end

T["glance() opens the list with the types filter"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[require("scrollbar").glance({ types = { "Warn", "Info" } })]])
    expect.equality(#glance_lines(child), 2)
    close_glance(child)
    child.lua([[require("scrollbar").glance()]])
    expect.equality(#glance_lines(child), 3)
end

T["an unknown mark type or option gives an error and opens nothing"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        local scrollbar = require("scrollbar")
        scrollbar.glance({ types = { "Warn", "Nope" } })
        scrollbar.jump({ types = { "Nope" } })
        scrollbar.glance({ types = "Warn" })
        scrollbar.jump({ type = { "Warn" } })
        scrollbar.glance("Warn")
    ]])
    expect.equality(notes(child), {
        { "[nvim-scrollbar] glance(): unknown mark type 'Nope'", ERROR },
        { "[nvim-scrollbar] jump(): unknown mark type 'Nope'", ERROR },
        { "[nvim-scrollbar] glance(): opts.types must be a list of mark type names", ERROR },
        { "[nvim-scrollbar] jump(): unknown option 'type'", ERROR },
        { "[nvim-scrollbar] glance(): opts must be a table", ERROR },
    })
    expect.equality(glance_lines(child), nil)
    expect.equality(#child.api.nvim_list_wins(), 2)
end

T["commands"] = MiniTest.new_set()

T["commands"]["take mark types as arguments"] = function()
    local child = navigate.new_child()
    setup(child)
    child.cmd("ScrollbarGlance Warn")
    expect.equality(#glance_lines(child), 1)
    close_glance(child)
    child.cmd("ScrollbarGlance")
    expect.equality(#glance_lines(child), 3)
    close_glance(child)
    child.cmd("ScrollbarGlance Nope")
    expect.equality(glance_lines(child), nil)
    expect.equality(notes(child), { { "[nvim-scrollbar] glance(): unknown mark type 'Nope'", ERROR } })

    child.lua([[
        vim.api.nvim_feedkeys("a", "t", false)
        vim.cmd("ScrollbarJump Warn Info")
    ]])
    expect.equality(child.api.nvim_win_get_cursor(0), { 61, 0 })
end

T["commands"]["complete the registered mark types"] = function()
    local child = navigate.new_child()
    setup(child)
    for _, command in ipairs({ "ScrollbarJump", "ScrollbarGlance" }) do
        local names = child.fn.getcompletion(command .. " Wa", "cmdline")
        expect.equality(names, { "Warn" })
        local all = child.fn.getcompletion(command .. " Error ", "cmdline")
        expect.equality(vim.tbl_contains(all, "Cursor"), true)
        expect.equality(vim.tbl_contains(all, "Search"), true)
    end
end

T["commands"][":ScrollbarJump exists only with the scrollbar, and :ScrollbarGlance always"] = function()
    local child = navigate.new_child()
    setup(child)
    expect.equality(child.fn.exists(":ScrollbarJump"), 2)
    expect.equality(child.fn.exists(":ScrollbarGlance"), 2)
    child.lua_func(function(config)
        require("scrollbar").setup(config)
    end, navigate.config({ scrollbar = { enabled = false } }))
    expect.equality(child.fn.exists(":ScrollbarJump"), 0)
    expect.equality(child.fn.exists(":ScrollbarGlance"), 2)
    child.lua([[require("scrollbar").jump()]])
    expect.equality(notes(child), {
        { "[nvim-scrollbar] jump() needs the scrollbar, and scrollbar.enabled is false", WARN },
    })
end

T["setup()"] = MiniTest.new_set()

T["setup()"]["closes the glance window and returns focus to the source window"] = function()
    local child = navigate.new_child()
    local result = setup(child)
    child.lua([[require("scrollbar").glance()]])
    local state = child.lua_get("require('scrollbar.navigate.glance').get()")
    child.lua_func(function(config)
        require("scrollbar").setup(config)
    end, navigate.config())
    expect.equality(glance_lines(child), nil)
    expect.equality(child.api.nvim_win_is_valid(state.list_win), false)
    expect.equality(child.api.nvim_win_is_valid(state.preview_win), false)
    expect.equality(child.api.nvim_get_current_win(), result.source_win)
end

T["setup()"]["ends label mode and closes its peek"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        _G.jump_done = false
        vim.schedule(function()
            require("scrollbar").jump()
            _G.jump_done = true
        end)
    ]])
    vim.uv.sleep(50)
    child.api.nvim_input("S")
    vim.uv.sleep(50)
    expect.no_equality(child.lua_get("require('scrollbar.navigate.peek').get()"), vim.NIL)
    -- An RPC request runs while label mode waits for a key.
    child.lua_func(function(config)
        require("scrollbar").setup(config)
    end, navigate.config())
    vim.uv.sleep(50)
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(child.lua_get("require('scrollbar.navigate.jump').active()"), false)
    expect.equality(child.lua_get("require('scrollbar.navigate.peek').get()"), vim.NIL)
    expect.equality(child.api.nvim_win_get_cursor(0), { 1, 0 })
end

return T
