local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

-- Line 0 holds the cursor, so the labels go in this order: a, s, d, f, g.
local MARKS = {
    { line = 20, type = "Error" },
    { line = 60, type = "Warn" },
    { line = 100, type = "Hint" },
    { line = 150, type = "Info" },
    { line = 190, type = "Misc" },
}

local function setup(child, options)
    options = options or {}
    options.marks = options.marks or MARKS
    local result = navigate.setup(child, options)
    child.lua([[
        _G.notes = {}
        vim.notify = function(message)
            table.insert(_G.notes, message)
        end
    ]])
    return result
end

--- Run label mode with keys in the typeahead. The call returns when label mode
--- ends.
local function run_with(child, keys, types, mode)
    child.lua_func(function(typed, names, label_mode)
        vim.api.nvim_feedkeys(vim.keycode(typed), "t", false)
        -- A nil argument before another argument arrives as vim.NIL.
        require("scrollbar.navigate.jump").run({ types = names ~= vim.NIL and names or nil, mode = label_mode })
    end, keys, types, mode)
end

--- Start label mode and return while it waits for a key.
local function start(child, types, mode)
    child.lua(
        [[
        local names, label_mode = ...
        -- A nil argument before another argument arrives as vim.NIL.
        if names == vim.NIL then
            names = nil
        end
        _G.jump_done = false
        vim.schedule(function()
            require("scrollbar.navigate.jump").run({ types = names, mode = label_mode })
            _G.jump_done = true
        end)
    ]],
        { types, mode }
    )
    vim.uv.sleep(50)
end

local function input(child, keys)
    child.api.nvim_input(keys)
    vim.uv.sleep(50)
end

--- The labels as `{ row, col, text }`, sorted by row.
local function labels(child)
    return child.lua([[
        local state = require("scrollbar.renderer").get_state(vim.api.nvim_get_current_win())
        if state == nil then
            return {}
        end
        local namespace = require("scrollbar.navigate.jump").NAMESPACE
        local result = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true })) do
            result[#result + 1] = { mark[2], mark[4].virt_text_win_col, mark[4].virt_text[1][1] }
        end
        table.sort(result, function(left, right)
            return left[1] < right[1]
        end)
        return result
    ]])
end

local function label_texts(child)
    local result = {}
    for _, label in ipairs(labels(child)) do
        result[#result + 1] = label[3]
    end
    return result
end

local function peek_line(child)
    local state = child.lua_get("require('scrollbar.navigate.peek').get()")
    return state ~= vim.NIL and state.line or nil
end

local function cursor_line(child)
    return child.api.nvim_win_get_cursor(0)[1] - 1
end

T["labels go to the mark cells nearest to the cursor first"] = function()
    local child = navigate.new_child()
    setup(child)
    start(child)
    expect.equality(label_texts(child), { "a", "s", "d", "f", "g" })
    local hitmap = child.lua_get("require('scrollbar.renderer').get_hitmap(vim.api.nvim_get_current_win())")
    for _, label in ipairs(labels(child)) do
        -- Each label is on the first column of a mark cell.
        expect.no_equality(hitmap[label[1] + 1][label[2] + 1].line, nil)
    end
    input(child, "<Esc>")

    child.api.nvim_win_set_cursor(0, { 150, 0 })
    start(child)
    -- From line 149, the order is 150, 190, 100, 60, 20. The list is in row
    -- order.
    expect.equality(label_texts(child), { "g", "f", "d", "a", "s" })
    input(child, "<Esc>")
end

T["a lowercase label jumps, and <C-o> returns"] = function()
    local child = navigate.new_child()
    setup(child)
    child.api.nvim_win_set_cursor(0, { 5, 0 })
    run_with(child, "d")
    expect.equality(child.api.nvim_win_get_cursor(0), { 101, 0 })
    expect.equality(labels(child), {})
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0), { 5, 0 })
end

T["an uppercase label opens the peek, and label mode stays"] = function()
    local child = navigate.new_child()
    setup(child)
    start(child)
    input(child, "S")
    expect.equality(peek_line(child), 60)
    expect.equality(label_texts(child), { "a", "S", "d", "f", "g" })
    expect.equality(child.lua_get("_G.jump_done"), false)

    -- A second uppercase label moves the peek.
    input(child, "F")
    expect.equality(peek_line(child), 150)
    expect.equality(label_texts(child), { "a", "s", "d", "F", "g" })

    -- <CR> jumps to the peeked mark.
    input(child, "<CR>")
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(cursor_line(child), 150)
    expect.equality(peek_line(child), nil)
    expect.equality(labels(child), {})
end

T["the screen shows the uppercase label while label mode waits"] = function()
    local child = navigate.new_child()
    setup(child)
    start(child)
    input(child, "S")
    -- The screen grid changes only on a redraw, and this call does not redraw.
    local label = child.lua([[
        local namespace = require("scrollbar.navigate.jump").NAMESPACE
        local state = require("scrollbar.renderer").get_state(vim.api.nvim_get_current_win())
        local float = vim.api.nvim_win_get_position(state.float_win)
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true })) do
            if mark[4].virt_text[1][1] == "S" then
                return vim.fn.screenstring(float[1] + 1 + mark[2], float[2] + 1 + mark[4].virt_text_win_col)
            end
        end
    ]])
    expect.equality(label, "S")
    input(child, "<Esc>")
end

T["a lowercase label jumps also while the peek is open"] = function()
    local child = navigate.new_child()
    setup(child)
    run_with(child, "Sa")
    expect.equality(cursor_line(child), 20)
    expect.equality(peek_line(child), nil)
end

T["<Esc> closes the peek and ends label mode"] = function()
    local child = navigate.new_child()
    setup(child)
    run_with(child, "D<Esc>")
    expect.equality(cursor_line(child), 0)
    expect.equality(peek_line(child), nil)
    expect.equality(labels(child), {})
end

T["another key ends label mode and is dropped"] = function()
    local child = navigate.new_child()
    setup(child)
    local before = child.api.nvim_buf_get_lines(0, 0, -1, false)
    -- `x` is not a label, so it does not delete a character.
    run_with(child, "x")
    expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), before)
    expect.equality(cursor_line(child), 0)
    -- <CR> without a peek also ends label mode.
    run_with(child, "<CR>")
    expect.equality(cursor_line(child), 0)
    expect.equality(labels(child), {})
end

T["cells past the last label have no label"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ scrollbar = { jump = { labels = "qw" } } }) })
    child.api.nvim_win_set_cursor(0, { 101, 0 })
    start(child)
    -- Line 100 has label q, and the nearer of 60 and 150 has label w.
    expect.equality(label_texts(child), { "w", "q" })
    input(child, "w")
    expect.equality(cursor_line(child), 60)
end

T["Cursor marks get labels only when types names them"] = function()
    local child = navigate.new_child()
    setup(child, { marks = { { line = 120, type = "Cursor" }, { line = 20, type = "Error" } } })
    start(child)
    expect.equality(label_texts(child), { "a" })
    input(child, "<Esc>")
    run_with(child, "a", { Cursor = true })
    expect.equality(cursor_line(child), 120)
end

T["notifies and does nothing without marks or without a scrollbar"] = function()
    local child = navigate.new_child()
    setup(child, { marks = {} })
    run_with(child, "")
    expect.equality(child.lua_get("_G.notes"), { "[nvim-scrollbar] jump: the scrollbar has no marks to jump to" })

    local hidden = navigate.new_child()
    setup(hidden, { config = navigate.config({ scrollbar = { show = false } }) })
    run_with(hidden, "")
    expect.equality(hidden.lua_get("_G.notes"), { "[nvim-scrollbar] jump: the current window has no scrollbar" })
    expect.equality(hidden.lua_get("require('scrollbar.navigate.jump').active()"), false)
end

T["works in a float source"] = function()
    local child = navigate.new_child()
    local result = setup(child, { float = {} })
    expect.equality(
        child.lua_get("require('scrollbar.renderer').get_state(vim.api.nvim_get_current_win()).source_kind"),
        "custom"
    )
    child.api.nvim_win_set_cursor(0, { 5, 0 })
    run_with(child, "d")
    expect.equality(child.api.nvim_get_current_win(), result.source_win)
    expect.equality(child.api.nvim_win_get_cursor(0), { 101, 0 })
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0), { 5, 0 })

    -- An uppercase label peeks, and <CR> jumps to the peeked line.
    start(child)
    input(child, "S")
    expect.equality(peek_line(child), 60)
    input(child, "<CR>")
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(cursor_line(child), 60)
    expect.equality(child.lua_get("_G.notes"), {})
end

T["notifies and does nothing on a float that is not a source"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        local buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 30, height = 10 })
    ]])
    run_with(child, "a")
    expect.equality(child.lua_get("_G.notes"), { "[nvim-scrollbar] jump: the current window has no scrollbar" })
    expect.equality(cursor_line(child), 0)
end

T["draws the labels again after a render during label mode"] = function()
    local child = navigate.new_child()
    setup(child)
    start(child)
    local before = labels(child)
    -- A provider update writes the rows of the float again.
    child.lua([[
        local store = require("scrollbar.shared.store")
        store.set("test", vim.api.nvim_get_current_buf(), {
            { line = 20, type = "Error" },
            { line = 60, type = "Error" },
            { line = 100, type = "Hint" },
            { line = 150, type = "Info" },
            { line = 190, type = "Misc" },
            { line = 130, type = "Warn" },
        })
        require("scrollbar.scheduler").flush()
    ]])
    vim.uv.sleep(50)
    -- The targets froze when label mode started.
    expect.equality(labels(child), before)
    -- Each label shows on top of the row that the render wrote again, and the
    -- new mark shows. Label mode redraws the screen after the render.
    local shown = child.lua_func(function(placed)
        local win = vim.api.nvim_get_current_win()
        local state = assert(require("scrollbar.renderer").get_state(win))
        local position = vim.api.nvim_win_get_position(state.float_win)
        local function screen(row, col)
            return vim.fn.screenstring(position[1] + 1 + row, position[2] + col)
        end
        local result = { labels = {} }
        for index, label in ipairs(placed) do
            result.labels[index] = screen(label[1], label[2] + 1)
        end
        for _, cell in ipairs(require("scrollbar.navigate.targets").cells(win)) do
            if cell.line == 130 then
                result.new_mark = screen(cell.row, cell.col)
            end
        end
        return result
    end, before)
    expect.equality(shown, { labels = { "a", "s", "d", "f", "g" }, new_mark = "-" })
    input(child, "s")
    expect.equality(cursor_line(child), 60)
end

T["a size change of the float ends label mode"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[vim.keymap.set("n", "<F35>", function() _G.stray = true end)]])
    start(child)
    child.cmd("resize 12")
    child.lua("require('scrollbar.scheduler').invalidate_all(); require('scrollbar.scheduler').flush()")
    vim.uv.sleep(50)
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(labels(child), {})
    -- Label mode reads the wake-up key, so it does not reach Normal mode.
    expect.equality(child.lua_get("_G.stray"), vim.NIL)
    expect.equality(cursor_line(child), 0)
end

T["a closed float ends label mode"] = function()
    local child = navigate.new_child()
    setup(child)
    start(child)
    child.lua("require('scrollbar').hide()")
    vim.uv.sleep(50)
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(child.lua_get("require('scrollbar.navigate.jump').active()"), false)
end

T["reveals an autohidden scrollbar and holds it until the end"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ scrollbar = { autohide = { delay_ms = 50 } } }) })
    -- Setup renders once without a reveal, so the scrollbar is hidden.
    child.lua("require('scrollbar.renderer').conceal(vim.api.nvim_get_current_win())")
    expect.equality(child.lua_get("require('scrollbar.renderer').get_state(vim.api.nvim_get_current_win())"), vim.NIL)
    start(child)
    vim.uv.sleep(150)
    expect.equality(#labels(child), 5)
    input(child, "<Esc>")
    vim.uv.sleep(150)
    expect.equality(child.lua_get("require('scrollbar.renderer').get_state(vim.api.nvim_get_current_win())"), vim.NIL)
end

T["shows a scrollbar that hide_on_cursor hid until the end"] = function()
    local child = navigate.new_child()
    setup(child)
    child.lua([[
        vim.api.nvim_buf_set_lines(0, 0, 1, false, { string.rep("x", 100) })
        vim.api.nvim_win_set_cursor(0, { 1, 79 })
        require("scrollbar.renderer").render(vim.api.nvim_get_current_win())
    ]])
    local function hidden()
        return child.lua_get("require('scrollbar.renderer').get_state(vim.api.nvim_get_current_win()).hidden_by_cursor")
    end
    expect.equality(hidden(), true)
    start(child)
    expect.equality(hidden(), false)
    expect.equality(#labels(child), 5)
    input(child, "<Esc>")
    child.lua("require('scrollbar.scheduler').flush()")
    expect.equality(hidden(), true)
end

T["offset"] = MiniTest.new_set()

local function offset_config(offset, scrollbar)
    return navigate.config({
        scrollbar = vim.tbl_deep_extend("force", { jump = { offset = offset } }, scrollbar or {}),
    })
end

--- For each mark cell of the current window, in line order: the screen text at
--- the cell and `offset` columns from it, and that column relative to the
--- source window.
local function cell_screen(child, offset)
    -- In a headless child, a new float shows at the top-left corner of the
    -- screen until its second redraw.
    child.cmd("redraw")
    return child.lua(
        [[
        local offset = ...
        local win = vim.api.nvim_get_current_win()
        local state = assert(require("scrollbar.renderer").get_state(win))
        local float = vim.fn.win_screenpos(state.float_win)
        local source_col = vim.fn.win_screenpos(win)[2]
        local result = {}
        for _, cell in ipairs(require("scrollbar.navigate.targets").cells(win)) do
            local row = float[1] + state.sides.top + cell.row
            local col = float[2] + state.sides.left + cell.col - 1
            result[#result + 1] = {
                line = cell.line,
                mark = vim.fn.screenstring(row, col),
                label = vim.fn.screenstring(row, col + offset),
                label_col = col + offset - source_col,
            }
        end
        table.sort(result, function(left, right)
            return left.line < right.line
        end)
        return result
    ]],
        { offset }
    )
end

local function shown_labels(cells)
    local result = {}
    for index, cell in ipairs(cells) do
        result[index] = cell.label
    end
    return result
end

local function peek_columns(child)
    return child.lua([[
        local config = vim.api.nvim_win_get_config(require("scrollbar.navigate.peek").get().win)
        return { first = config.col, after = config.col + config.width }
    ]])
end

T["offset"]["over a float source, the label floats and the peek float stack above the scrollbar"] = function()
    local child = navigate.new_child()
    setup(child, { config = offset_config(-1), float = {} })
    start(child)
    input(child, "S")
    local zindexes = child.lua([[
        local win = vim.api.nvim_get_current_win()
        local function zindex(winid)
            return vim.api.nvim_win_get_config(winid).zindex
        end
        local labels = {}
        for _, label_win in pairs(require("scrollbar.navigate.jump")._label_floats()) do
            labels[zindex(label_win)] = true
        end
        return {
            source = zindex(win),
            scrollbar = zindex(require("scrollbar.renderer").get_state(win).float_win),
            labels = vim.tbl_keys(labels),
            peek = zindex(require("scrollbar.navigate.peek").get().win),
        }
    ]])
    expect.equality(zindexes, { source = 50, scrollbar = 51, labels = { 52 }, peek = 53 })
    expect.equality(shown_labels(cell_screen(child, -1)), { "a", "S", "d", "f", "g" })
    input(child, "<Esc>")
end

T["offset"]["puts each label in a float beside its mark cell, so the marks stay visible"] = function()
    local child = navigate.new_child()
    setup(child, { config = offset_config(-1) })
    local before = cell_screen(child, -1)
    start(child)
    local during = cell_screen(child, -1)
    expect.equality(shown_labels(during), { "a", "s", "d", "f", "g" })
    for index, cell in ipairs(during) do
        expect.equality(cell.mark, before[index].mark)
    end
    -- No label is on the float buffer.
    expect.equality(labels(child), {})
    expect.equality(vim.tbl_count(child.lua_get("require('scrollbar.navigate.jump')._label_floats()")), 5)

    input(child, "<Esc>")
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(#child.api.nvim_list_wins(), 2)
    expect.equality(cell_screen(child, -1), before)
end

T["offset"]["an uppercase label shows in its float, beside the peek float"] = function()
    local child = navigate.new_child()
    setup(child, { config = offset_config(-1) })
    start(child)
    input(child, "S")
    expect.equality(peek_line(child), 60)
    local during = cell_screen(child, -1)
    expect.equality(shown_labels(during), { "a", "S", "d", "f", "g" })
    -- On the east side, the peek float ends at the label column.
    expect.equality(peek_columns(child).after, during[2].label_col)

    input(child, "<CR>")
    expect.equality(cursor_line(child), 60)
    expect.equality(#child.api.nvim_list_wins(), 2)
end

T["offset"]["goes to the right of a west scrollbar"] = function()
    local child = navigate.new_child()
    -- The marks are in the first of the two columns.
    setup(child, { config = offset_config(2, { placement = { anchor = "NW" } }) })
    local before = cell_screen(child, 2)
    start(child)
    local during = cell_screen(child, 2)
    expect.equality(shown_labels(during), { "a", "s", "d", "f", "g" })
    for index, cell in ipairs(during) do
        expect.equality(cell.mark, before[index].mark)
    end
    input(child, "D")
    -- On the west side, the peek float starts after the label column.
    expect.equality(peek_columns(child).first, cell_screen(child, 2)[3].label_col + 1)
    input(child, "<Esc>")
end

T["offset"]["the label floats follow the scrollbar float"] = function()
    local child = navigate.new_child()
    child.cmd("vsplit")
    setup(child, { config = offset_config(-1) })
    start(child)
    local first = cell_screen(child, -1)

    -- A layout change moves the east scrollbar float with the right edge of
    -- the window. Its size stays, so label mode continues.
    child.lua([[
        vim.api.nvim_win_set_width(0, vim.api.nvim_win_get_width(0) - 10)
        require("scrollbar.scheduler").invalidate_all()
        require("scrollbar.scheduler").flush()
    ]])
    vim.uv.sleep(50)
    expect.equality(child.lua_get("_G.jump_done"), false)
    local resized = cell_screen(child, -1)
    expect.equality(shown_labels(resized), { "a", "s", "d", "f", "g" })
    expect.equality(resized[1].label_col, first[1].label_col - 10)

    input(child, "a")
    expect.equality(cursor_line(child), 20)
end

T["offset"]["the label floats follow the scrollbar float when the minimap beside it shows or hides"] = function()
    local child = navigate.new_child()
    -- With `stack = "outer"`, the minimap is at the edge of the window and the
    -- scrollbar is beside it.
    local config = offset_config(-1)
    config.minimap = { enabled = true, placement = { stack = "outer" } }
    setup(child, { config = config, full = true })
    local function toggle_minimap(method)
        child.lua(
            [[
            require("scrollbar.minimap")[...]()
            require("scrollbar.scheduler").invalidate_all()
            require("scrollbar.scheduler").flush()
        ]],
            { method }
        )
        vim.uv.sleep(50)
        expect.no_equality(child.lua_get("_G.jump_done"), true)
    end
    toggle_minimap("hide")
    start(child)
    local first = cell_screen(child, -1)

    -- The renderer moves the scrollbar float inward with
    -- `nvim_win_set_config`, and the layout does not change. A float relative
    -- to the scrollbar float does not follow such a move.
    toggle_minimap("show")
    local inward = cell_screen(child, -1)
    expect.equality(inward[1].label_col < first[1].label_col, true)
    expect.equality(shown_labels(inward), { "a", "s", "d", "f", "g" })

    toggle_minimap("hide")
    local outward = cell_screen(child, -1)
    expect.equality(outward[1].label_col, first[1].label_col)
    expect.equality(shown_labels(outward), { "a", "s", "d", "f", "g" })
    input(child, "a")
    expect.equality(cursor_line(child), 20)
end

T["peek mode"] = MiniTest.new_set()

--- The highlight groups of the extmark labels, sorted and without duplicates.
local function label_groups(child)
    return child.lua([=[
        local state = assert(require("scrollbar.renderer").get_state(vim.api.nvim_get_current_win()))
        local namespace = require("scrollbar.navigate.jump").NAMESPACE
        local seen = {}
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true })) do
            seen[mark[4].virt_text[1][2]] = true
        end
        local result = vim.tbl_keys(seen)
        table.sort(result)
        return result
    ]=])
end

T["peek mode"]["a lowercase label opens the peek, and label mode stays"] = function()
    local child = navigate.new_child()
    setup(child)
    start(child, nil, "peek")
    input(child, "s")
    expect.equality(peek_line(child), 60)
    expect.equality(label_texts(child), { "a", "S", "d", "f", "g" })
    expect.equality(child.lua_get("_G.jump_done"), false)

    -- A second lowercase label moves the peek.
    input(child, "f")
    expect.equality(peek_line(child), 150)
    expect.equality(label_texts(child), { "a", "s", "d", "F", "g" })

    -- The same lowercase label again peeks again. It does not jump.
    input(child, "f")
    expect.equality(peek_line(child), 150)
    expect.equality(child.lua_get("_G.jump_done"), false)

    -- <CR> jumps to the peeked mark.
    input(child, "<CR>")
    expect.equality(child.lua_get("_G.jump_done"), true)
    expect.equality(cursor_line(child), 150)
    expect.equality(peek_line(child), nil)
    expect.equality(labels(child), {})
end

T["peek mode"]["an uppercase label jumps, and <C-o> returns"] = function()
    local child = navigate.new_child()
    setup(child)
    child.api.nvim_win_set_cursor(0, { 5, 0 })
    run_with(child, "D", nil, "peek")
    expect.equality(child.api.nvim_win_get_cursor(0), { 101, 0 })
    expect.equality(labels(child), {})
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0), { 5, 0 })
end

T["peek mode"]["an uppercase label jumps also while the peek is open"] = function()
    local child = navigate.new_child()
    setup(child)
    run_with(child, "sA", nil, "peek")
    expect.equality(cursor_line(child), 20)
    expect.equality(peek_line(child), nil)
end

T["peek mode"]["<Esc> closes the peek, and another key ends label mode and is dropped"] = function()
    local child = navigate.new_child()
    setup(child)
    run_with(child, "d<Esc>", nil, "peek")
    expect.equality(cursor_line(child), 0)
    expect.equality(peek_line(child), nil)
    expect.equality(labels(child), {})

    local before = child.api.nvim_buf_get_lines(0, 0, -1, false)
    -- `X` is not a label, so it does not delete a character.
    run_with(child, "X", nil, "peek")
    expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false), before)
    expect.equality(cursor_line(child), 0)
    expect.equality(labels(child), {})
end

T["peek mode"]["the labels use ScrollbarPeekLabel, and the jump mode labels ScrollbarJumpLabel"] = function()
    local child = navigate.new_child()
    setup(child)
    start(child, nil, "peek")
    expect.equality(label_groups(child), { "ScrollbarPeekLabel" })
    input(child, "s")
    expect.equality(label_groups(child), { "ScrollbarPeekLabel" })
    input(child, "<Esc>")
    expect.equality(child.lua_get("_G.jump_done"), true)

    start(child)
    expect.equality(label_groups(child), { "ScrollbarJumpLabel" })
    input(child, "<Esc>")
end

T["peek mode"]["with an offset, the label floats use ScrollbarPeekLabel"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ scrollbar = { peek = { offset = -1 } } }) })
    start(child, nil, "peek")
    input(child, "s")
    expect.equality(peek_line(child), 60)
    expect.equality(shown_labels(cell_screen(child, -1)), { "a", "S", "d", "f", "g" })
    local highlights = child.lua([[
        local seen = {}
        for _, win in pairs(require("scrollbar.navigate.jump")._label_floats()) do
            seen[vim.wo[win].winhighlight] = true
        end
        return vim.tbl_keys(seen)
    ]])
    expect.equality(highlights, { "NormalFloat:ScrollbarPeekLabel" })

    input(child, "D")
    expect.equality(cursor_line(child), 100)
    expect.equality(#child.api.nvim_list_wins(), 2)
end

T["peek mode"]["reads scrollbar.peek, not scrollbar.jump"] = function()
    local child = navigate.new_child()
    setup(child, {
        config = navigate.config({ scrollbar = { jump = { labels = "qw" }, peek = { labels = "zx", offset = -1 } } }),
    })
    start(child, nil, "peek")
    -- With the offset of `scrollbar.peek`, the labels are floats, and no label
    -- is on the float buffer.
    expect.equality(labels(child), {})
    local floats = child.lua_get("vim.tbl_keys(require('scrollbar.navigate.jump')._label_floats())")
    table.sort(floats)
    expect.equality(floats, { "x", "z" })
    input(child, "x")
    expect.equality(peek_line(child), 60)
    input(child, "<Esc>")
    expect.equality(child.lua_get("_G.jump_done"), true)

    -- The jump mode keeps the labels and the offset of `scrollbar.jump`.
    start(child)
    expect.equality(label_texts(child), { "q", "w" })
    expect.equality(child.lua_get("require('scrollbar.navigate.jump')._label_floats()"), {})
    input(child, "<Esc>")
end

T["peek mode"]["notifies with the peek prefix"] = function()
    local child = navigate.new_child()
    setup(child, { marks = {} })
    run_with(child, "", nil, "peek")
    expect.equality(child.lua_get("_G.notes"), { "[nvim-scrollbar] peek: the scrollbar has no marks to peek at" })

    local hidden = navigate.new_child()
    setup(hidden, { config = navigate.config({ scrollbar = { show = false } }) })
    run_with(hidden, "", nil, "peek")
    expect.equality(hidden.lua_get("_G.notes"), { "[nvim-scrollbar] peek: the current window has no scrollbar" })

    local floating = navigate.new_child()
    setup(floating, { float = {} })
    run_with(floating, "s<CR>", nil, "peek")
    expect.equality(floating.lua_get("_G.notes"), {})
    expect.equality(cursor_line(floating), 60)
end

return T
