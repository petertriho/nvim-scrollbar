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

T["jump(), peek(), and glance() before setup() notify and do nothing"] = function()
    local child = navigate.new_child()
    capture_notes(child)
    child.lua([[
        require("scrollbar").jump()
        require("scrollbar").peek()
        require("scrollbar").glance()
    ]])
    expect.equality(notes(child), {
        { "[nvim-scrollbar] jump() needs setup() first", WARN },
        { "[nvim-scrollbar] peek() needs setup() first", WARN },
        { "[nvim-scrollbar] glance() needs setup() first", WARN },
    })
    expect.equality(#child.api.nvim_list_wins(), 1)
    expect.equality(child.fn.exists(":ScrollbarJump"), 0)
    expect.equality(child.fn.exists(":ScrollbarPeek"), 0)
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

T["peek() runs label mode in the peek mode with the types filter"] = function()
    local child = navigate.new_child()
    setup(child)
    -- In the peek mode, an uppercase label jumps and ends label mode, and
    -- Neovim then runs <Esc>. In the jump mode, `A` would peek, and <Esc>
    -- would end label mode without a move.
    child.lua([[
        vim.api.nvim_feedkeys(vim.keycode("A<Esc>"), "t", false)
        require("scrollbar").peek({ types = { "Info" } })
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
        scrollbar.peek({ types = { "Nope" } })
        scrollbar.peek({ picker = "builtin" })
    ]])
    expect.equality(notes(child), {
        { "[nvim-scrollbar] glance(): unknown mark type 'Nope'", ERROR },
        { "[nvim-scrollbar] jump(): unknown mark type 'Nope'", ERROR },
        { "[nvim-scrollbar] glance(): opts.types must be a list of mark type names", ERROR },
        { "[nvim-scrollbar] jump(): unknown option 'type'", ERROR },
        { "[nvim-scrollbar] glance(): opts must be a table", ERROR },
        { "[nvim-scrollbar] peek(): unknown mark type 'Nope'", ERROR },
        { "[nvim-scrollbar] peek(): unknown option 'picker'", ERROR },
    })
    expect.equality(glance_lines(child), nil)
    expect.equality(#child.api.nvim_list_wins(), 2)
end

T["glance pickers"] = MiniTest.new_set()

--- Set a configuration with a `glance.picker` function from Lua source. The
--- function records each context in `_G.contexts`.
local function set_recording_picker(child, top_source)
    child.lua(string.format(
        [[
        _G.contexts = {}
        _G.record = function(ctx)
            table.insert(_G.contexts, {
                source_win = ctx.source_win,
                source_buf = ctx.source_buf,
                mode = ctx.mode,
                selected = ctx.selected,
                lnums = vim.tbl_map(function(item) return item.lnum end, ctx.items),
                functions = {
                    type(ctx.format), type(ctx.jump), type(ctx.quickfix), type(ctx.refresh),
                },
            })
        end
        local top = (function() %s end)()
        require("scrollbar.config").set(require("tests.navigate.helpers").config(top))
    ]],
        top_source or "return { glance = { picker = function(ctx) _G.record(ctx) end } }"
    ))
end

T["glance pickers"]["a function picker gets the context once"] = function()
    local child = navigate.new_child()
    local result = setup(child)
    set_recording_picker(child)
    child.api.nvim_win_set_cursor(0, { 30, 0 })
    child.lua([[require("scrollbar").glance()]])
    expect.equality(child.lua_get("_G.contexts"), {
        {
            source_win = result.source_win,
            source_buf = result.source_buf,
            mode = "line",
            selected = 2,
            lnums = { 21, 61, 151 },
            functions = { "function", "function", "function", "function" },
        },
    })
    expect.equality(glance_lines(child), nil)
end

T["glance pickers"]["glance({ picker }) overrides glance.picker for one call"] = function()
    local child = navigate.new_child()
    setup(child)
    set_recording_picker(child, "return { glance = { picker = 'builtin', entries = 'type' } }")
    child.lua([[require("scrollbar").glance({ picker = _G.record, types = { "Warn" } })]])
    local contexts = child.lua_get("_G.contexts")
    expect.equality(#contexts, 1)
    expect.equality({ contexts[1].mode, contexts[1].lnums }, { "type", { 61 } })
    expect.equality(glance_lines(child), nil)
    child.lua([[require("scrollbar").glance()]])
    expect.equality(#glance_lines(child), 6)
end

T["glance pickers"]["a function picker can open the builtin frame"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        require("scrollbar").glance({
            picker = function(ctx)
                ctx.items = { ctx.items[3] }
                ctx.selected = 1
                require("scrollbar.glance").builtin(ctx)
            end,
        })
    ]])
    expect.equality(glance_lines(child), { " - 151  line 151" })
end

T["glance pickers"]["a vim.ui.select picker jumps with ctx.jump"] = function()
    local child = navigate.new_child()
    local result = setup(child)
    child.lua([[
        -- A select that chooses the second item.
        vim.ui.select = function(items, opts, on_choice)
            _G.select_rows = vim.tbl_map(opts.format_item, items)
            on_choice(items[2], 2)
        end
        require("scrollbar").glance({
            picker = function(ctx)
                vim.ui.select(ctx.items, {
                    prompt = "Marks",
                    format_item = function(item)
                        return table.concat(vim.tbl_map(function(chunk) return chunk[1] end, ctx.format(item)))
                    end,
                }, function(item)
                    if item ~= nil then
                        ctx.jump(item)
                    end
                end)
            end,
        })
    ]])
    expect.equality(child.lua_get("_G.select_rows"), { "-  21  line 21", "-  61  line 61", "- 151  line 151" })
    expect.equality(child.api.nvim_get_current_win(), result.source_win)
    expect.equality(child.api.nvim_win_get_cursor(0), { 61, 0 })
end

T["glance pickers"]["an invalid picker gives an error and opens nothing"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        local scrollbar = require("scrollbar")
        scrollbar.glance({ picker = "fzf" })
        scrollbar.jump({ picker = "builtin" })
    ]])
    expect.equality(notes(child), {
        {
            '[nvim-scrollbar] glance(): opts.picker must be "builtin", "snacks", "telescope", or a function',
            ERROR,
        },
        { "[nvim-scrollbar] jump(): unknown option 'picker'", ERROR },
    })
    expect.equality(glance_lines(child), nil)
end

T["glance pickers"]["a missing picker plugin gives an error and opens nothing"] = function()
    local child = navigate.new_child()
    setup(child)
    local windows = #child.api.nvim_list_wins()
    child.lua([[
        require("scrollbar").glance({ picker = "snacks" })
        require("scrollbar").glance({ picker = "telescope" })
    ]])
    expect.equality(notes(child), {
        { '[nvim-scrollbar] glance: picker "snacks" needs snacks.nvim', ERROR },
        { '[nvim-scrollbar] glance: picker "telescope" needs telescope.nvim', ERROR },
    })
    expect.equality(#child.api.nvim_list_wins(), windows)
end

T["glance pickers"]["the threshold recipe opens the glance window up to max entries"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        local threshold = require("scrollbar.recipes").glance.threshold
        _G.small = threshold({ max = 3, picker = "snacks" })
        _G.large = threshold({ max = 2, picker = "snacks" })
    ]])
    child.lua([[require("scrollbar").glance({ picker = _G.small })]])
    expect.equality(#glance_lines(child), 3)
    -- The list has the focus, and glance() does not open from a float.
    child.lua([[require("scrollbar.navigate.glance").close(true)]])
    child.lua([[require("scrollbar").glance({ picker = _G.large })]])
    expect.equality(glance_lines(child), nil)
    child.lua([[require("scrollbar").glance({ picker = require("scrollbar.recipes").glance.threshold })]])
    expect.equality(notes(child), {
        { '[nvim-scrollbar] glance: picker "snacks" needs snacks.nvim', ERROR },
        {
            "[nvim-scrollbar] glance: picker failed: [nvim-scrollbar] recipes.glance.threshold:"
                .. " call the recipe to get its function, for example recipes.glance.threshold()",
            ERROR,
        },
    })
end

T["glance pickers"]["a picker error shows a notification"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[require("scrollbar").glance({ picker = function() error("boom", 0) end })]])
    expect.equality(notes(child), { { "[nvim-scrollbar] glance: picker failed: boom", ERROR } })
end

T["glance pickers"]["the picker is not called on a float that is not a source or without marks"] = function()
    local child = navigate.new_child()
    setup(child, { marks = {} })
    set_recording_picker(child)
    child.lua([[require("scrollbar").glance()]])
    child.lua([[
        vim.api.nvim_open_win(0, true, { relative = "editor", row = 1, col = 1, width = 30, height = 10 })
        require("scrollbar").glance()
    ]])
    expect.equality(child.lua_get("_G.contexts"), {})
    expect.equality(notes(child), {
        { "[nvim-scrollbar] glance: the current window has no marks", WARN },
        { "[nvim-scrollbar] glance: the current float is not a source of the scrollbar. See scrollbar.floats", WARN },
    })
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

    -- From line 60, the label `a` is on line 60 and `s` is on line 150.
    child.lua([[
        vim.api.nvim_feedkeys(vim.keycode("S<Esc>"), "t", false)
        vim.cmd("ScrollbarPeek Warn Info")
    ]])
    expect.equality(child.api.nvim_win_get_cursor(0), { 151, 0 })
end

T["commands"]["complete the registered mark types"] = function()
    local child = navigate.new_child()
    setup(child)
    for _, command in ipairs({ "ScrollbarJump", "ScrollbarPeek", "ScrollbarGlance" }) do
        local names = child.fn.getcompletion(command .. " Wa", "cmdline")
        expect.equality(names, { "Warn" })
        local all = child.fn.getcompletion(command .. " Error ", "cmdline")
        expect.equality(vim.tbl_contains(all, "Cursor"), true)
        expect.equality(vim.tbl_contains(all, "Search"), true)
    end
end

T["commands"][":ScrollbarJump and :ScrollbarPeek exist only with the scrollbar, and :ScrollbarGlance always"] = function()
    local child = navigate.new_child()
    setup(child)
    expect.equality(child.fn.exists(":ScrollbarJump"), 2)
    expect.equality(child.fn.exists(":ScrollbarPeek"), 2)
    expect.equality(child.fn.exists(":ScrollbarGlance"), 2)
    child.lua_func(function(config)
        require("scrollbar").setup(config)
    end, navigate.config({ scrollbar = { enabled = false } }))
    expect.equality(child.fn.exists(":ScrollbarJump"), 0)
    expect.equality(child.fn.exists(":ScrollbarPeek"), 0)
    expect.equality(child.fn.exists(":ScrollbarGlance"), 2)
    child.lua([[
        require("scrollbar").jump()
        require("scrollbar").peek()
    ]])
    expect.equality(notes(child), {
        { "[nvim-scrollbar] jump() needs the scrollbar, and scrollbar.enabled is false", WARN },
        { "[nvim-scrollbar] peek() needs the scrollbar, and scrollbar.enabled is false", WARN },
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
