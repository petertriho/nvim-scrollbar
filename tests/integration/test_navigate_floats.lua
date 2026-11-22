local MiniTest = MiniTest
local integration = require("tests.integration.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local new_child = integration.new_child
local wait_for = integration.wait_for

local DELAY_MS = 100

-- The snacks windows are float sources, and hover opens the peek after a
-- short delay.
local TOP = { scrollbar = { floats = true, hover = { delay_ms = DELAY_MS } } }

-- Snacks sets `require("snacks.zen").win` after it opens the window.
local ZEN_READY = [[(function()
    local win = require("snacks.zen").win
    return win ~= nil
        and vim.api.nvim_win_is_valid(win.win)
        and require("scrollbar.renderer").source_kind(win.win) == "snacks_zen"
        and require("scrollbar.renderer").get_state(win.win) ~= nil
end)()]]

--- Open the snacks zen window and wait until it has a scrollbar.
---@return integer zen
local function open_zen(child)
    child.lua("Snacks.zen()")
    wait_for(child, ZEN_READY)
    return child.lua_get("require('snacks.zen').win.win")
end

--- Run label mode with keys in the typeahead. The call returns when label mode
--- ends.
local function run_label_mode(child, keys, mode)
    child.lua_func(function(typed, label_mode)
        vim.api.nvim_feedkeys(vim.keycode(typed), "t", false)
        require("scrollbar.navigate.jump").run({ mode = label_mode })
    end, keys, mode)
end

--- Open the snacks glance picker, and wait until its preview shows the source
--- buffer at the selected line 21 with a scrollbar.
---@return { input: integer, preview: integer } windows
local function open_snacks_glance(child, source_buf)
    child.lua([[require("scrollbar").glance({ picker = "snacks" })]])
    wait_for(
        child,
        string.format(
            [[(function()
                local picker = Snacks.picker.get()[1]
                local win = picker and picker.preview.win.win
                return win ~= nil
                    and vim.api.nvim_win_is_valid(win)
                    and vim.api.nvim_win_get_buf(win) == %d
                    and vim.api.nvim_win_get_cursor(win)[1] == 21
                    and require("scrollbar.renderer").source_kind(win) == "snacks_preview"
                    and #require("scrollbar.navigate.targets").cells(win) > 0
            end)()]],
            source_buf
        )
    )
    return child.lua_get([[(function()
        local picker = Snacks.picker.get()[1]
        return { input = picker.input.win.win, preview = picker.preview.win.win }
    end)()]])
end

local PICKER_OPEN = "(function() local p = Snacks.picker.get()[1]; return p ~= nil and not p.closed end)()"

---@return any
local function glance_state(child)
    local state = child.lua_get("require('scrollbar.navigate.glance').get()")
    return state ~= vim.NIL and state or nil
end

T["jump() and peek() work in the snacks zen window, and zen stays open"] = function()
    local child = new_child(TOP)
    local zen = open_zen(child)
    expect.equality(child.api.nvim_get_current_win(), zen)

    -- From line 0, the labels go to lines 20, 60, 100, and 150 in this order.
    run_label_mode(child, "d")
    expect.equality(child.api.nvim_win_get_cursor(zen), { 101, 0 })

    -- From line 100, the label "s" goes to line 60. In the peek mode, it opens
    -- the peek, and <CR> jumps to the peeked line.
    run_label_mode(child, "s<CR>", "peek")
    expect.equality(child.api.nvim_win_get_cursor(zen), { 61, 0 })
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(zen), { 101, 0 })

    -- Zen closes on a scheduled callback after focus enters a normal window.
    vim.uv.sleep(50)
    expect.equality(child.api.nvim_win_is_valid(zen), true)
    expect.equality(child.api.nvim_get_current_win(), zen)
    expect.equality(child.lua_get("require('scrollbar.navigate.peek').get()"), vim.NIL)
    expect.equality(child.lua_get("_G.notes"), {})
end

T["the glance builtin opens from the snacks zen window, and zen stays open"] = function()
    local child = new_child(TOP)
    local zen = open_zen(child)
    child.lua([[require("scrollbar").glance({ picker = "builtin" })]])
    vim.uv.sleep(50)
    local state = glance_state(child)
    expect.equality(state.source_win, zen)
    expect.equality(child.api.nvim_get_current_win(), state.list_win)
    expect.equality(child.api.nvim_win_is_valid(zen), true)

    child.type_keys("jj<CR>")
    vim.uv.sleep(50)
    expect.equality(glance_state(child), nil)
    expect.equality(child.api.nvim_win_is_valid(zen), true)
    expect.equality(child.api.nvim_get_current_win(), zen)
    expect.equality(child.api.nvim_win_get_cursor(zen), { 101, 0 })
    expect.equality(child.lua_get("_G.notes"), {})
end

T["hover on the bar of a snacks picker preview opens the peek above the picker"] = function()
    local child, result = new_child(TOP)
    local windows = open_snacks_glance(child, result.source_buf)
    local function cell_position()
        return child.lua_func(function(win)
            -- In a headless child, the screen position of a float can be old
            -- until a redraw.
            vim.cmd("redraw")
            local state = assert(require("scrollbar.renderer").get_state(win))
            for _, cell in ipairs(require("scrollbar.navigate.targets").cells(win)) do
                if cell.line == 100 then
                    local screen = vim.fn.win_screenpos(state.float_win)
                    return {
                        screen[1] - 1 + state.sides.top + cell.row,
                        screen[2] - 1 + state.sides.left + cell.col - 1,
                    }
                end
            end
            error("no cell for line 100")
        end, windows.preview)
    end
    -- snacks can change the layout of the preview and scroll it once more
    -- after it shows. Then the bar moves, or the scroll closes the hover peek.
    -- A user then moves the pointer to the bar again, so the test does the
    -- same.
    local opened = false
    for _ = 1, 5 do
        local position = cell_position()
        child.api.nvim_input_mouse("move", "", "", 0, position[1], position[2])
        local deadline = vim.uv.hrtime() + (DELAY_MS + 400) * 1e6
        repeat
            vim.uv.sleep(20)
            opened = child.lua_get("require('scrollbar.navigate.peek').get() ~= nil")
        until opened or vim.uv.hrtime() > deadline
        if opened then
            break
        end
    end
    expect.equality(opened, true)

    local peek = child.lua_func(function(preview)
        local state = assert(require("scrollbar.navigate.peek").get())
        local function zindex(winid)
            return vim.api.nvim_win_get_config(winid).zindex
        end
        return {
            line = state.line,
            source = state.source_win == preview,
            zindex = zindex(state.win),
            preview = zindex(preview),
            scrollbar = zindex(require("scrollbar.renderer").get_state(preview).float_win),
        }
    end, windows.preview)
    expect.equality({ peek.line, peek.source }, { 100, true })
    -- The label floats would go 1 above the scrollbar.
    expect.equality(peek.scrollbar, peek.preview + 1)
    expect.equality(peek.zindex, peek.scrollbar + 2)

    vim.uv.sleep(DELAY_MS)
    expect.equality(child.lua_get(PICKER_OPEN), true)
    expect.equality(child.api.nvim_get_current_win(), windows.input)
    child.lua("Snacks.picker.get()[1]:close()")
end

T["the glance builtin opens from a focused snacks preview, and the picker stays open"] = function()
    local child, result = new_child(TOP)
    local windows = open_snacks_glance(child, result.source_buf)
    child.lua([[
        vim.cmd("stopinsert")
        Snacks.picker.get()[1]:focus("preview")
    ]])
    wait_for(child, string.format("vim.api.nvim_get_current_win() == %d", windows.preview))

    child.lua([[require("scrollbar").glance({ picker = "builtin" })]])
    vim.uv.sleep(50)
    local state = glance_state(child)
    expect.equality(state.source_win, windows.preview)
    expect.equality(child.api.nvim_get_current_win(), state.list_win)
    expect.equality(#child.api.nvim_buf_get_lines(state.list_buf, 0, -1, false), 4)
    expect.equality(child.lua_get(PICKER_OPEN), true)

    child.type_keys("q")
    vim.uv.sleep(50)
    expect.equality(glance_state(child), nil)
    expect.equality(child.api.nvim_get_current_win(), windows.preview)
    expect.equality(child.lua_get(PICKER_OPEN), true)
    expect.equality(child.lua_get("_G.notes"), {})
    child.lua("Snacks.picker.get()[1]:close()")
end

return T
