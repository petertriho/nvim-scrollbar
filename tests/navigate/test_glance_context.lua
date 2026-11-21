local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local LINE_NR = "ScrollbarGlanceLineNr"

local setup = navigate.setup_glance

--- Build a context of the current window in the child as `_G.ctx`.
---@param mode? string
---@param types? table<string, true>
local function new_context(child, mode, types)
    child.lua(
        [[_G.ctx = require("scrollbar.navigate.glance.context").new(vim.api.nvim_get_current_win(), ...)]],
        { mode or "line", types }
    )
end

local function items(child)
    return child.lua_get("_G.ctx.items")
end

local function lnums(child)
    local result = {}
    for index, item in ipairs(items(child)) do
        result[index] = item.lnum
    end
    return result
end

T["items"] = MiniTest.new_set()

T["items"]["line mode has one item for each marked line"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    new_context(child)
    local ctx = child.lua_get("{ source_win = _G.ctx.source_win, source_buf = _G.ctx.source_buf, mode = _G.ctx.mode }")
    expect.equality(ctx, { source_win = setup_result.source_win, source_buf = setup_result.source_buf, mode = "line" })
    local first = items(child)[1]
    expect.equality({
        lnum = first.lnum,
        text = first.text,
        glyph = first.glyph,
        hl = first.hl,
        type = first.type,
        types = first.types,
        group = first.group,
    }, {
        lnum = 21,
        text = "text 21",
        glyph = "-",
        hl = "ScrollbarError",
        type = "Error",
        types = { "Error", "GitChange" },
        group = nil,
    })
    expect.equality(#first.marks, 2)
    expect.equality(
        { first.marks[2].type, first.marks[2].provider, first.marks[2].glyph, first.marks[2].hl },
        { "GitChange", "test", "┃", "ScrollbarGitChange" }
    )
    expect.equality(type(first.marks[1].priority), "number")
    expect.equality(lnums(child), { 21, 61, 101, 151 })
end

T["items"]["mark mode has one item for each mark"] = function()
    local child = navigate.new_child()
    setup(child)
    new_context(child, "mark")
    expect.equality(lnums(child), { 21, 21, 61, 101, 151 })
    expect.equality(items(child)[2].types, { "GitChange" })
end

T["items"]["type mode has no headers and keeps the group order"] = function()
    local child = navigate.new_child()
    setup(child)
    new_context(child, "type")
    local result = {}
    for index, item in ipairs(items(child)) do
        result[index] = { item.group, item.lnum }
    end
    expect.equality(result, {
        { "Error", 21 },
        { "Error", 151 },
        { "Warn", 61 },
        { "Hint", 101 },
        { "GitChange", 21 },
    })
end

T["items"]["the text has no indent, and a tab is a space"] = function()
    local child = navigate.new_child()
    setup(child)
    child.api.nvim_buf_set_lines(0, 20, 21, false, { "\t\tlocal\tx" })
    new_context(child)
    expect.equality(items(child)[1].text, "local x")
end

T["items"]["the types argument filters the items"] = function()
    local child = navigate.new_child()
    setup(child, { marks = { { line = 30, type = "Cursor" }, { line = 60, type = "Warn" } } })
    new_context(child)
    expect.equality(lnums(child), { 61 })
    new_context(child, "line", { Cursor = true })
    expect.equality(lnums(child), { 31 })
end

T["selected"] = function()
    local child = navigate.new_child()
    setup(child)
    for _, case in ipairs({ { 1, 1 }, { 21, 1 }, { 50, 2 }, { 101, 3 }, { 180, 4 } }) do
        child.api.nvim_win_set_cursor(0, { case[1], 0 })
        new_context(child)
        expect.equality(child.lua_get("_G.ctx.selected"), case[2])
    end
    -- In type mode, the first item at or after the cursor line in list order.
    child.api.nvim_win_set_cursor(0, { 100, 0 })
    new_context(child, "type")
    expect.equality(child.lua_get("_G.ctx.selected"), 2)
end

T["format"] = MiniTest.new_set()

T["format"]["gives the glyph, the line number, and the text"] = function()
    local child = navigate.new_child()
    setup(child)
    new_context(child)
    expect.equality(child.lua_get("_G.ctx.format(_G.ctx.items[1])"), {
        { "-", "ScrollbarError" },
        { " " },
        { " 21", LINE_NR },
        { "  text 21" },
    })
    expect.equality(child.lua_get("_G.ctx.format(_G.ctx.items[3])")[3], { "101", LINE_NR })
end

T["format"]["pads the glyphs to the widest glyph"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ marks = { Error = { text = { "EE" } } } }) })
    new_context(child)
    local rows = child.lua([[
        local result = {}
        for index, item in ipairs(_G.ctx.items) do
            local text = {}
            for _, chunk in ipairs(_G.ctx.format(item)) do
                text[#text + 1] = chunk[1]
            end
            result[index] = table.concat(text)
        end
        return result
    ]])
    expect.equality(rows, {
        "EE  21  text 21",
        "-   61  text 61",
        "-  101  text 101",
        "EE 151  text 151",
    })
end

T["format"]["type mode adds the group column"] = function()
    local child = navigate.new_child()
    setup(child)
    new_context(child, "type")
    expect.equality(child.lua_get("_G.ctx.format(_G.ctx.items[1])"), {
        { "Error", "ScrollbarError" },
        { "      " },
        { "-", "ScrollbarError" },
        { " " },
        { " 21", LINE_NR },
        { "  text 21" },
    })
    expect.equality(child.lua_get("_G.ctx.format(_G.ctx.items[5])")[1], { "GitChange", "ScrollbarGitChange" })
    expect.equality(child.lua_get("_G.ctx.format(_G.ctx.items[1], { group = false })"), {
        { "-", "ScrollbarError" },
        { " " },
        { " 21", LINE_NR },
        { "  text 21" },
    })
end

T["jump"] = MiniTest.new_set()

T["jump"]["moves the source window and adds a jumplist entry"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    child.api.nvim_win_set_cursor(0, { 5, 0 })
    new_context(child)
    child.cmd("vsplit")
    expect.equality(child.lua_get("_G.ctx.jump(_G.ctx.items[3])"), true)
    expect.equality(child.api.nvim_get_current_win(), setup_result.source_win)
    expect.equality(child.api.nvim_win_get_cursor(0), { 101, 0 })
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0), { 5, 0 })
end

T["jump"]["split and vsplit move in a new window"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    new_context(child)
    for _, case in ipairs({ { split = "split", layout = "col" }, { split = "vsplit", layout = "row" } }) do
        child.lua("_G.ctx.jump(_G.ctx.items[2], { split = ... })", { case.split })
        local win = child.api.nvim_get_current_win()
        expect.no_equality(win, setup_result.source_win)
        expect.equality(child.api.nvim_win_get_cursor(win), { 61, 0 })
        expect.equality(child.fn.winlayout()[1], case.layout)
        expect.equality(child.api.nvim_win_get_cursor(setup_result.source_win), { 1, 0 })
        child.cmd("close")
    end
    expect.error(function()
        child.lua("_G.ctx.jump(_G.ctx.items[2], { split = 'tab' })")
    end, 'opts.split must be "split" or "vsplit"')
end

T["jump"]["does nothing when the source window is closed or shows another buffer"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    new_context(child)
    child.cmd("enew")
    expect.equality(child.lua_get("_G.ctx.jump(_G.ctx.items[1])"), false)
    child.cmd("buffer " .. setup_result.source_buf)
    child.cmd("split")
    child.api.nvim_win_close(setup_result.source_win, true)
    expect.equality(child.lua_get("_G.ctx.jump(_G.ctx.items[1])"), false)
    expect.equality(child.lua_get("_G.notes"), {
        "[nvim-scrollbar] glance: the source window is closed or shows another buffer",
        "[nvim-scrollbar] glance: the source window is closed or shows another buffer",
    })
end

---@return table
local function quickfix_list(child)
    return child.lua([[
        local list = vim.fn.getqflist({ title = 1, items = 1 })
        local items = {}
        for index, item in ipairs(list.items) do
            items[index] = { item.bufnr, item.lnum, item.text }
        end
        return { title = list.title, items = items }
    ]])
end

T["quickfix"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    -- In type mode, a line in two groups is one quickfix item.
    new_context(child, "type")
    child.lua("_G.ctx.quickfix()")
    expect.equality(child.bo.buftype, "quickfix")
    local buf = setup_result.source_buf
    expect.equality(quickfix_list(child), {
        title = "Scrollbar glance",
        items = {
            { buf, 21, "Error, GitChange: text 21" },
            { buf, 61, "Warn: text 61" },
            { buf, 101, "Hint: text 101" },
            { buf, 151, "Error: text 151" },
        },
    })
    child.lua("_G.ctx.quickfix({ _G.ctx.items[4], _G.ctx.items[3] })")
    expect.equality(quickfix_list(child).items, { { buf, 61, "Warn: text 61" }, { buf, 101, "Hint: text 101" } })
end

T["refresh reads the marks again"] = function()
    local child = navigate.new_child()
    setup(child)
    child.api.nvim_win_set_cursor(0, { 70, 0 })
    new_context(child)
    expect.equality(child.lua_get("_G.ctx.selected"), 3)
    child.lua([[
        local buf = vim.api.nvim_get_current_buf()
        local marks = vim.deepcopy(require("scrollbar.shared.store").get(buf).test)
        table.insert(marks, { line = 65, type = "Info" })
        require("scrollbar.shared.store").set("test", buf, marks)
    ]])
    expect.equality(#items(child), 4)
    local returned = child.lua("return #_G.ctx.refresh()")
    expect.equality(returned, 5)
    expect.equality(lnums(child), { 21, 61, 66, 101, 151 })
    expect.equality(child.lua_get("_G.ctx.selected"), 4)
end

return T
