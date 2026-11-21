local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local setup = navigate.setup_glance

local function open(child, types)
    child.lua_func(function(names)
        require("scrollbar.navigate.glance").open({ types = names })
    end, types)
end

---@return any
local function state(child)
    local result = child.lua_get("require('scrollbar.navigate.glance').get()")
    return result ~= vim.NIL and result or nil
end

local function list_lines(child)
    local current = state(child)
    return child.api.nvim_buf_get_lines(current.list_buf, 0, -1, false)
end

local function frame(child, win)
    local position = child.api.nvim_win_get_position(win)
    return {
        row = position[1],
        col = position[2],
        width = child.api.nvim_win_get_width(win),
        height = child.api.nvim_win_get_height(win),
    }
end

--- Set the configuration from Lua source that returns the top-level
--- overrides, so that they can hold functions. `recipes` is in scope.
local function set_config(child, source)
    child.lua(string.format(
        [[
        local recipes = require("scrollbar.recipes")
        local top = (function() %s end)()
        require("scrollbar.config").set(require("tests.navigate.helpers").config(top))
    ]],
        source
    ))
end

---@param predicate fun(): boolean
local function wait_until(predicate)
    expect.equality(vim.wait(2000, predicate, 20), true)
end

local function panes(child)
    local current = state(child)
    return { preview = frame(child, current.preview_win), list = frame(child, current.list_win) }
end

local function preview_line(child)
    return child.api.nvim_win_get_cursor(state(child).preview_win)[1] - 1
end

local function list_row(child)
    return child.api.nvim_win_get_cursor(state(child).list_win)[1]
end

T["frame"] = MiniTest.new_set()

T["frame"]["opens under the cursor line across the text area"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    open(child)
    local current = state(child)
    expect.equality(child.api.nvim_get_current_win(), current.list_win)
    local preview = frame(child, current.preview_win)
    local list = frame(child, current.list_win)
    expect.equality(preview, { row = 1, col = 0, width = 48, height = 18 })
    expect.equality(list, { row = 1, col = 48, width = 32, height = 18 })
    expect.equality(child.api.nvim_win_get_buf(current.preview_win), setup_result.source_buf)
    for _, win in ipairs({ current.list_win, current.preview_win }) do
        expect.equality(child.lua_get("vim.w[...].scrollbar_navigate_owned", { win }), true)
        expect.equality(child.api.nvim_win_get_config(win).focusable, true)
    end
end

T["frame"]["opens above the cursor line without room below"] = function()
    local child = navigate.new_child()
    setup(child)
    child.api.nvim_win_set_cursor(0, { 21, 0 })
    child.cmd("normal! zt")
    child.api.nvim_win_set_cursor(0, { 41, 0 })
    open(child)
    local list = frame(child, state(child).list_win)
    expect.equality(list.row + list.height, 20)
    expect.equality(list.height, 18)
end

T["frame"]["takes the larger side and clamps the height"] = function()
    local child = navigate.new_child()
    setup(child)
    set_config(child, "return { glance = { builtin = { frame = recipes.frame.cursor({ height = 40 }) } } }")
    child.api.nvim_win_set_cursor(0, { 11, 0 })
    open(child)
    local list = frame(child, state(child).list_win)
    -- Row 10 has 11 rows below and 10 rows above.
    expect.equality(list, { row = 11, col = 48, width = 32, height = 11 })
end

T["frame"]["the border comes from the window option"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ glance = { builtin = { window = { border = "single" } } } }) })
    open(child)
    local current = state(child)
    local preview = frame(child, current.preview_win)
    local list = frame(child, current.list_win)
    expect.equality(preview.width + 2 + list.width + 2, 80)
    expect.equality(list.col, preview.col + preview.width + 2)
end

T["frame"]["follows a 'winborder' change after setup"] = function()
    local child = navigate.new_child()
    if child.fn.exists("+winborder") == 0 then
        MiniTest.skip("'winborder' is not available")
    end
    setup(child)
    child.o.winborder = "single"
    open(child)
    local current = state(child)
    for _, win in ipairs({ current.list_win, current.preview_win }) do
        expect.equality(child.api.nvim_win_get_config(win).border[1], "┌")
    end
    local preview = frame(child, current.preview_win)
    local list = frame(child, current.list_win)
    expect.equality(preview.width + 2 + list.width + 2, 80)
    -- The 18 rows of the default frame include the border.
    expect.equality(list.height, 16)
end

T["frame"]["center: at the center for every cursor line"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ glance = { builtin = { frame = "center" } } }) })
    for _, line in ipairs({ 1, 11, 21 }) do
        child.api.nvim_win_set_cursor(0, { line, 0 })
        open(child)
        expect.equality(panes(child), {
            preview = { row = 2, col = 0, width = 48, height = 18 },
            list = { row = 2, col = 48, width = 32, height = 18 },
        })
        child.lua("require('scrollbar.navigate.glance').close(true)")
    end
end

T["frame"]["a function sets the frame from the context"] = function()
    local child = navigate.new_child()
    setup(child)
    set_config(
        child,
        [[return { glance = { builtin = { frame = function(ctx)
            _G.frame_ctx = vim.deepcopy(ctx)
            return { row = 3, col = 10, width = 60, height = 10 }
        end } } }]]
    )
    child.api.nvim_win_set_cursor(0, { 6, 0 })
    open(child)
    expect.equality(panes(child), {
        preview = { row = 3, col = 10, width = 36, height = 10 },
        list = { row = 3, col = 46, width = 24, height = 10 },
    })
    local ctx = child.lua_get("_G.frame_ctx")
    expect.equality({ ctx.kind, ctx.cursor_row, ctx.anchor_row }, { "glance", 5, 5 })
end

T["frame"]["a result is clamped into the window"] = function()
    local child = navigate.new_child()
    setup(child)
    set_config(
        child,
        "return { glance = { builtin = { frame = function() return { row = -5, col = 50, width = 200, height = 100 } end } } }"
    )
    open(child)
    expect.equality(panes(child), {
        preview = { row = 0, col = 0, width = 48, height = 22 },
        list = { row = 0, col = 48, width = 32, height = 22 },
    })
end

T["frame"]["an editor frame centers on the screen"] = function()
    local child = navigate.new_child()
    setup(child)
    child.cmd("rightbelow vsplit")
    set_config(
        child,
        [[return { glance = { builtin = { frame = recipes.frame.center({ relative = "editor", width = 60, height = 10 }) } } }]]
    )
    open(child)
    local current = state(child)
    for _, win in ipairs({ current.preview_win, current.list_win }) do
        expect.equality(child.api.nvim_win_get_config(win).relative, "editor")
    end
    -- 24 lines less the command line leave 23 rows.
    expect.equality(panes(child), {
        preview = { row = 6, col = 10, width = 36, height = 10 },
        list = { row = 6, col = 46, width = 24, height = 10 },
    })
end

T["frame"]["list.width takes a part or cells, and list.side a side"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ glance = { builtin = { list = { width = 30 } } } }) })
    open(child)
    expect.equality(panes(child).list, { row = 1, col = 50, width = 30, height = 18 })
    child.lua("require('scrollbar.navigate.glance').close(true)")

    set_config(child, "return { glance = { builtin = { list = { width = 0.25, side = 'left' } } } }")
    open(child)
    expect.equality(panes(child), {
        preview = { row = 1, col = 20, width = 60, height = 18 },
        list = { row = 1, col = 0, width = 20, height = 18 },
    })
end

T["frame"]["a frame without room for the panes notifies"] = function()
    local child = navigate.new_child()
    setup(child)
    set_config(
        child,
        [[return { glance = { builtin = {
            frame = function() return { row = 0, col = 0, width = 5, height = 10 } end,
            window = { border = "single" },
        } } }]]
    )
    local windows = #child.api.nvim_list_wins()
    open(child)
    expect.equality(state(child), nil)
    expect.equality(#child.api.nvim_list_wins(), windows)
    expect.equality(child.lua_get("_G.notes"), {
        "[nvim-scrollbar] glance: the current window has no room for the glance window",
    })
end

T["frame"]["an invalid result notifies once and opens nothing"] = function()
    local child = navigate.new_child()
    setup(child)
    set_config(child, "return { glance = { builtin = { frame = function() return 'x' end } } }")
    local windows = #child.api.nvim_list_wins()
    open(child)
    open(child)
    expect.equality(state(child), nil)
    expect.equality(#child.api.nvim_list_wins(), windows)
    expect.equality(
        child.lua_get("_G.notes"),
        { "[nvim-scrollbar] glance.builtin.frame returned a string, not a table" }
    )
end

T["resize"] = MiniTest.new_set()

T["resize"]["the panes follow a resize of the source window and keep the selection"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    set_config(child, "return { glance = { builtin = { frame = recipes.frame.center({ height = 10 }) } } }")
    open(child)
    child.type_keys("j", "j")
    local row = list_row(child)
    expect.equality(panes(child).list.row, 6)
    child.api.nvim_win_set_height(setup_result.source_win, 16)
    wait_until(function()
        return panes(child).list.row == 3
    end)
    expect.equality(list_row(child), row)
    expect.equality(child.api.nvim_get_current_win(), state(child).list_win)
end

T["resize"]["the panes follow a resize of the screen"] = function()
    local child = navigate.new_child()
    setup(child)
    set_config(
        child,
        [[return { glance = { builtin = { frame = recipes.frame.center({ relative = "editor", width = 60, height = 10 }) } } }]]
    )
    open(child)
    expect.equality(panes(child).preview.col, 10)
    child.o.columns = 70
    wait_until(function()
        return panes(child).preview.col == 5
    end)
end

T["resize"]["a resize of another window does not run the frame"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    set_config(
        child,
        [[return { glance = { builtin = { frame = function(ctx)
            _G.frame_calls = (_G.frame_calls or 0) + 1
            return recipes.frame.center({ width = 30, height = 10 })(ctx)
        end } } }]]
    )
    child.cmd("vsplit")
    child.cmd("split")
    local other = child.api.nvim_get_current_win()
    child.api.nvim_set_current_win(setup_result.source_win)
    open(child)
    expect.equality(child.lua_get("_G.frame_calls"), 1)
    child.api.nvim_win_set_height(other, 5)
    vim.uv.sleep(100)
    expect.equality(child.lua_get("_G.frame_calls"), 1)
    child.api.nvim_win_set_width(setup_result.source_win, 30)
    wait_until(function()
        return child.lua_get("_G.frame_calls") == 2
    end)
end

T["resize"]["a resize without room closes the frame with a notification"] = function()
    local child = navigate.new_child()
    local setup_result =
        setup(child, { config = navigate.config({ glance = { builtin = { window = { border = "single" } } } }) })
    open(child)
    child.api.nvim_win_set_height(setup_result.source_win, 2)
    wait_until(function()
        return state(child) == nil
    end)
    expect.equality(child.lua_get("_G.notes"), {
        "[nvim-scrollbar] glance: the current window has no room for the glance window",
    })
    expect.equality(child.api.nvim_get_current_win(), setup_result.source_win)
end

T["list"] = MiniTest.new_set()

T["list"]["line mode lists each marked line and selects the first at or after the cursor"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ marks = { Error = { text = { "E" } } } }) })
    child.api.nvim_win_set_cursor(0, { 50, 0 })
    open(child)
    expect.equality(list_lines(child), {
        " E  21  text 21",
        " -  61  text 61",
        " - 101  text 101",
        " E 151  text 151",
    })
    expect.equality(list_row(child), 2)
    expect.equality(preview_line(child), 60)
    local spans = state(child).spans
    expect.equality(spans[1], {
        { start_col = 1, end_col = 2, group = "ScrollbarError" },
        { start_col = 3, end_col = 6, group = "ScrollbarGlanceLineNr" },
    })
end

T["list"]["the glyphs and the line numbers show in their groups"] = function()
    local child = navigate.new_child()
    setup(child)
    open(child)
    -- Row 2 has no cursorline: " -  61  text 61" at screen row 2, column 48.
    local attrs = child.lua([[
        vim.api.nvim_set_hl(0, "ScrollbarWarn", { fg = "#ff0000" })
        vim.api.nvim_set_hl(0, "ScrollbarGlanceLineNr", { fg = "#00ff00" })
        vim.cmd("redraw")
        local row, col = 3, 49
        return {
            glyph = vim.fn.screenattr(row, col + 1),
            number = vim.fn.screenattr(row, col + 4),
            text = vim.fn.screenattr(row, col + 8),
        }
    ]])
    expect.no_equality(attrs.glyph, attrs.text)
    expect.no_equality(attrs.number, attrs.text)
    expect.no_equality(attrs.glyph, attrs.number)
end

T["list"]["mark mode lists each mark"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ glance = { entries = "mark" } }) })
    open(child)
    expect.equality(list_lines(child), {
        " -  21  text 21",
        " ┃  21  text 21",
        " -  61  text 61",
        " - 101  text 101",
        " - 151  text 151",
    })
end

T["list"]["type mode groups the lines under headers"] = function()
    local child = navigate.new_child()
    setup(child, { config = navigate.config({ glance = { entries = "type" } }) })
    child.api.nvim_win_set_cursor(0, { 100, 0 })
    open(child)
    expect.equality(list_lines(child), {
        " Error (2)",
        "   -  21  text 21",
        "   - 151  text 151",
        " Warn (1)",
        "   -  61  text 61",
        " Hint (1)",
        "   - 101  text 101",
        " GitChange (1)",
        "   ┃  21  text 21",
    })
    -- The first entry at or after line 99 in list order.
    expect.equality(list_row(child), 3)
    expect.equality(state(child).spans[1], { { start_col = 1, end_col = 10, group = "ScrollbarGlanceHeader" } })

    -- On a header, the preview shows the first entry of the group, and the
    -- jump key does nothing.
    child.type_keys("k")
    expect.equality(list_row(child), 2)
    child.type_keys("k")
    expect.equality(preview_line(child), 20)
    child.type_keys("<CR>")
    expect.equality(state(child) ~= nil, true)
end

T["list"]["native motions move the preview"] = function()
    local child = navigate.new_child()
    setup(child)
    open(child)
    expect.equality(preview_line(child), 20)
    child.type_keys("j")
    expect.equality(preview_line(child), 60)
    child.type_keys("G")
    expect.equality(preview_line(child), 150)
end

T["list"]["the types argument filters the list"] = function()
    local child = navigate.new_child()
    setup(child, { marks = { { line = 30, type = "Cursor" }, { line = 60, type = "Warn" } } })
    open(child)
    expect.equality(#list_lines(child), 1)
    child.type_keys("q")
    open(child, { Cursor = true })
    expect.equality(list_lines(child), { " • 31  text 31" })
end

T["keys"] = MiniTest.new_set()

T["keys"]["<CR> jumps, closes the frame, and adds a jumplist entry"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    child.api.nvim_win_set_cursor(0, { 5, 0 })
    open(child)
    child.type_keys("jj<CR>")
    expect.equality(state(child), nil)
    expect.equality(child.api.nvim_get_current_win(), setup_result.source_win)
    expect.equality(child.api.nvim_win_get_cursor(0), { 101, 0 })
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0), { 5, 0 })
end

T["keys"]["q and <Esc> close the frame"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    for _, key in ipairs({ "q", "<Esc>" }) do
        open(child)
        local current = state(child)
        child.type_keys(key)
        expect.equality(state(child), nil)
        expect.equality(child.api.nvim_win_is_valid(current.list_win), false)
        expect.equality(child.api.nvim_win_is_valid(current.preview_win), false)
        expect.equality(child.api.nvim_get_current_win(), setup_result.source_win)
        expect.equality(child.api.nvim_win_get_cursor(0), { 1, 0 })
    end
end

T["keys"]["glance.builtin.keys.list changes and removes the keys"] = function()
    local child = navigate.new_child()
    setup(child, {
        config = navigate.config({
            glance = { builtin = { keys = { list = { close = "x", focus_preview = false, jump = "o" } } } },
        }),
    })
    open(child)
    local list_buf = state(child).list_buf
    local mapped = child.lua_func(function(buf)
        local result = {}
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
            result[#result + 1] = map.lhs
        end
        table.sort(result)
        return result
    end, list_buf)
    expect.equality(mapped, { "o", "x" })
    child.type_keys("j", "o")
    expect.equality(child.api.nvim_win_get_cursor(0), { 61, 0 })
end

local function keys_config(keys, top)
    return navigate.config(vim.tbl_deep_extend("force", { glance = { builtin = { keys = keys } } }, top or {}))
end

T["keys"]["next and previous skip the headers and wrap around"] = function()
    local child = navigate.new_child()
    setup(child, {
        config = keys_config({ list = { next = "<C-j>", previous = "<C-k>" } }, { glance = { entries = "type" } }),
    })
    child.api.nvim_win_set_cursor(0, { 100, 0 })
    open(child)
    expect.equality(list_row(child), 3)
    child.type_keys("<C-j>")
    expect.equality({ list_row(child), preview_line(child) }, { 5, 60 })
    child.type_keys("<C-j>", "<C-j>")
    expect.equality({ list_row(child), preview_line(child) }, { 9, 20 })
    -- Past the last entry, the selection goes to the first entry, after the
    -- first header.
    child.type_keys("<C-j>")
    expect.equality({ list_row(child), preview_line(child) }, { 2, 20 })
    child.type_keys("<C-k>")
    expect.equality(list_row(child), 9)
end

T["keys"]["jump_split and jump_vsplit open the line in a new window"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child, { config = keys_config({ list = { jump_split = "s", jump_vsplit = "v" } }) })
    for _, case in ipairs({ { key = "s", layout = "col" }, { key = "v", layout = "row" } }) do
        open(child)
        child.type_keys("j", case.key)
        expect.equality(state(child), nil)
        local win = child.api.nvim_get_current_win()
        expect.no_equality(win, setup_result.source_win)
        expect.equality(child.api.nvim_win_get_buf(win), setup_result.source_buf)
        expect.equality(child.api.nvim_win_get_cursor(win), { 61, 0 })
        expect.equality(child.fn.winlayout()[1], case.layout)
        -- The source window keeps its cursor.
        expect.equality(child.api.nvim_win_get_cursor(setup_result.source_win), { 1, 0 })
        child.cmd("close")
    end
end

T["keys"]["quickfix puts each listed line in a new quickfix list and closes the frame"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child, { config = keys_config({ list = { quickfix = "Q" } }) })
    open(child)
    child.type_keys("Q")
    expect.equality(state(child), nil)
    expect.equality(child.bo.buftype, "quickfix")
    local quickfix = child.lua([[
        local list = vim.fn.getqflist({ title = 1, items = 1 })
        local items = {}
        for index, item in ipairs(list.items) do
            items[index] = { item.bufnr, item.lnum, item.text }
        end
        return { title = list.title, items = items }
    ]])
    local buf = setup_result.source_buf
    expect.equality(quickfix, {
        title = "Scrollbar glance",
        items = {
            { buf, 21, "Error, GitChange: text 21" },
            { buf, 61, "Warn: text 61" },
            { buf, 101, "Hint: text 101" },
            { buf, 151, "Error: text 151" },
        },
    })
end

T["preview"] = MiniTest.new_set()

T["preview"]["<Tab> focuses the preview, an edit changes the buffer, and the list rebuilds on return"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    open(child)
    child.type_keys("j")
    local current = state(child)
    child.type_keys("<Tab>")
    expect.equality(child.api.nvim_get_current_win(), current.preview_win)
    expect.equality(child.api.nvim_win_get_cursor(0), { 61, 0 })
    -- Two new lines above the Warn mark move it down. 'autoindent' keeps the
    -- indent of line 1.
    child.type_keys("ggOnew one<CR>new two<Esc>")
    expect.equality(child.api.nvim_buf_get_lines(setup_result.source_buf, 0, 2, false), { "  new one", "  new two" })
    child.lua([[
        local buf = vim.api.nvim_get_current_buf()
        require("scrollbar.shared.store").set("test", buf, {
            { line = 22, type = "Error" },
            { line = 62, type = "Warn" },
        })
    ]])
    child.type_keys("<C-w>p")
    expect.equality(child.api.nvim_get_current_win(), current.list_win)
    expect.equality(list_lines(child), {
        " - 23  text 21",
        " - 63  text 61",
    })
    -- The list selects the entry of the line that the preview showed before.
    expect.equality(list_row(child), 2)
    expect.equality(preview_line(child), 62)
end

T["preview"]["a mark that arrives while the list has focus shows only after a return from the preview"] = function()
    local child = navigate.new_child()
    setup(child)
    open(child)
    child.lua([[
        local source = require("scrollbar.navigate.glance").get().source_win
        local buf = vim.api.nvim_win_get_buf(source)
        local marks = vim.deepcopy(require("scrollbar.shared.store").get(buf).test)
        table.insert(marks, { line = 80, type = "Info" })
        require("scrollbar.shared.store").set("test", buf, marks)
    ]])
    vim.uv.sleep(50)
    expect.equality(#list_lines(child), 4)
    child.type_keys("<Tab>", "<C-w>p")
    expect.equality(#list_lines(child), 5)
    expect.equality(list_lines(child)[3], " -  81  text 81")
end

--- The buffer-local normal map of `buf` for `lhs`: its description, or its
--- rhs for a map without one, or nil.
local function buffer_map(child, buf, lhs)
    local result = child.lua(
        [[
        local buf, lhs = ...
        return vim.api.nvim_buf_call(buf, function()
            local map = vim.fn.maparg(lhs, "n", false, true)
            if map.buffer ~= 1 then
                return nil
            end
            return map.desc or map.rhs
        end)
    ]],
        { buf, lhs }
    )
    return result ~= vim.NIL and result or nil
end

local PREVIEW_KEYS = {
    preview = { next = "<C-j>", previous = "<C-k>", focus_list = "<C-l>", close = "Q", jump_vsplit = "<C-v>" },
}

T["preview"]["the preview keys exist only while the preview pane has focus"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child, { config = keys_config(PREVIEW_KEYS) })
    local buf = setup_result.source_buf
    -- The buffer-local maps of the user: one with an rhs and one with a
    -- callback.
    child.lua([[
        vim.keymap.set("n", "Q", "<Cmd>let g:user_q = 1<CR>", { buffer = 0 })
        vim.keymap.set("n", "<C-j>", function()
            vim.g.user_cj = 1
        end, { buffer = 0, desc = "user <C-j>" })
    ]])
    open(child)
    expect.equality(buffer_map(child, buf, "Q"), "<Cmd>let g:user_q = 1<CR>")

    child.type_keys("<Tab>")
    expect.equality(child.api.nvim_get_current_win(), state(child).preview_win)
    expect.equality(buffer_map(child, buf, "Q"), "Scrollbar glance: close")
    expect.equality(buffer_map(child, buf, "<C-l>"), "Scrollbar glance: focus_list")
    -- The next entry shows in the preview, and the focus stays in it.
    child.type_keys("<C-j>")
    expect.equality({ list_row(child), preview_line(child) }, { 2, 60 })
    expect.equality(child.api.nvim_get_current_win(), state(child).preview_win)
    child.type_keys("<C-k>", "<C-k>")
    expect.equality({ list_row(child), preview_line(child) }, { 4, 150 })

    -- The user maps come back when the pane loses focus.
    child.type_keys("<C-l>")
    expect.equality(child.api.nvim_get_current_win(), state(child).list_win)
    expect.equality(buffer_map(child, buf, "Q"), "<Cmd>let g:user_q = 1<CR>")
    expect.equality(buffer_map(child, buf, "<C-j>"), "user <C-j>")
    expect.equality(buffer_map(child, buf, "<C-l>"), nil)

    -- A close key in the preview closes the frame, and the maps come back.
    child.type_keys("<Tab>", "Q")
    expect.equality(state(child), nil)
    expect.equality(child.api.nvim_get_current_win(), setup_result.source_win)
    expect.equality(child.g.user_q, vim.NIL)
    child.type_keys("Q", "<C-j>")
    expect.equality({ child.g.user_q, child.g.user_cj }, { 1, 1 })
end

T["preview"]["a split jump from the preview pane uses the selected entry"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child, { config = keys_config(PREVIEW_KEYS) })
    open(child)
    child.type_keys("jj", "<Tab>", "gg", "<C-v>")
    expect.equality(state(child), nil)
    expect.equality(child.fn.winlayout()[1], "row")
    expect.no_equality(child.api.nvim_get_current_win(), setup_result.source_win)
    expect.equality(child.api.nvim_win_get_cursor(0), { 101, 0 })
    -- No preview key stays on the source buffer.
    expect.equality(buffer_map(child, setup_result.source_buf, "<C-v>"), nil)
end

T["preview"]["without preview keys, the source buffer gets no maps"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    open(child)
    child.type_keys("<Tab>")
    expect.equality(child.api.nvim_get_current_win(), state(child).preview_win)
    expect.equality(child.api.nvim_buf_get_keymap(setup_result.source_buf, "n"), {})
end

T["preview"]["a map that another plugin sets while the pane has focus stays"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child, { config = keys_config(PREVIEW_KEYS) })
    open(child)
    child.type_keys("<Tab>")
    child.lua([[vim.keymap.set("n", "Q", "<Nop>", { buffer = 0, desc = "other plugin" })]])
    child.type_keys("<C-l>")
    expect.equality(buffer_map(child, setup_result.source_buf, "Q"), "other plugin")
    expect.equality(buffer_map(child, setup_result.source_buf, "<C-j>"), nil)
end

T["close"] = MiniTest.new_set()

T["close"][":q in either pane closes the frame"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    open(child)
    child.cmd("quit")
    vim.uv.sleep(20)
    expect.equality(state(child), nil)
    expect.equality(child.api.nvim_get_current_win(), setup_result.source_win)
    expect.equality(#child.api.nvim_list_wins(), 2)

    open(child)
    local current = state(child)
    child.type_keys("<Tab>")
    child.cmd("quit")
    vim.uv.sleep(20)
    expect.equality(state(child), nil)
    expect.equality(child.api.nvim_win_is_valid(current.list_win), false)
    expect.equality(child.api.nvim_get_current_win(), setup_result.source_win)
end

T["close"]["focus on another window closes the frame"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    child.cmd("vsplit")
    local other = child.api.nvim_get_current_win()
    child.api.nvim_set_current_win(setup_result.source_win)
    open(child)
    child.api.nvim_set_current_win(other)
    vim.uv.sleep(20)
    expect.equality(state(child), nil)
    -- Focus stays where it went.
    expect.equality(child.api.nvim_get_current_win(), other)
end

T["close"]["a closed source window closes the frame"] = function()
    local child = navigate.new_child()
    local setup_result = setup(child)
    child.cmd("split")
    child.api.nvim_set_current_win(setup_result.source_win)
    open(child)
    local current = state(child)
    child.api.nvim_win_close(setup_result.source_win, true)
    vim.uv.sleep(20)
    expect.equality(state(child), nil)
    expect.equality(child.api.nvim_win_is_valid(current.list_win), false)
end

T["notifies and does nothing on a float or without marks"] = function()
    local child = navigate.new_child()
    setup(child, { marks = {} })
    open(child)
    expect.equality(state(child), nil)
    expect.equality(child.lua_get("_G.notes"), { "[nvim-scrollbar] glance: the current window has no marks" })

    local floating = navigate.new_child()
    setup(floating)
    floating.lua([[
        vim.api.nvim_open_win(0, true, { relative = "editor", row = 1, col = 1, width = 30, height = 10 })
    ]])
    open(floating)
    expect.equality(state(floating), nil)
    expect.equality(floating.lua_get("_G.notes"), { "[nvim-scrollbar] glance works only in a normal window" })
end

T["builds a list of 10000 search matches"] = function()
    local child = navigate.new_child()
    local matches = {}
    for line = 0, 9999 do
        matches[#matches + 1] = line
    end
    setup(child, {
        marks = {},
        compact = matches,
        line_count = 10000,
        config = navigate.config({ providers = { search = true } }),
    })
    local elapsed = child.lua([[
        local start = vim.uv.hrtime()
        require("scrollbar.navigate.glance").open()
        vim.cmd("redraw")
        return (vim.uv.hrtime() - start) / 1e6
    ]])
    expect.equality(#list_lines(child), 10000)
    MiniTest.add_note(string.format("glance with 10000 search matches: %.1f ms", elapsed))
end

return T
