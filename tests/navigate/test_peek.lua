local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function open(child, line, options)
    return child.lua_func(function(target, opts)
        local win = vim.api.nvim_get_current_win()
        local peek_win = require("scrollbar.navigate.peek").open(win, target, opts)
        vim.cmd("redraw")
        return peek_win
    end, line, options or {})
end

--- The frame position of a float relative to the editor, and its content size.
local function frame(child, win)
    return child.lua_func(function(winid)
        local position = vim.api.nvim_win_get_position(winid)
        return {
            row = position[1],
            col = position[2],
            width = vim.api.nvim_win_get_width(winid),
            height = vim.api.nvim_win_get_height(winid),
        }
    end, win)
end

local function scrollbar_frame(child)
    local float_win = child.lua_get("require('scrollbar.renderer').get_state(vim.api.nvim_get_current_win()).float_win")
    return frame(child, float_win)
end

T["position"] = MiniTest.new_set()

T["position"]["scrollbar: beside the scrollbar, centered on the anchor row"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {})
    local scrollbar = scrollbar_frame(child)
    local peek = frame(child, open(child, 100, { anchor_row = 10 }))
    -- 2 * context + 1 rows, and 60% of the window width.
    expect.equality(peek.height, 11)
    expect.equality(peek.width, 48)
    expect.equality(peek.col + peek.width, scrollbar.col)
    expect.equality(peek.row, 10 - 5)
end

T["position"]["scrollbar: clamped to the source window"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {})
    local top = frame(child, open(child, 1, { anchor_row = 1 }))
    expect.equality(top.row, 0)
    local bottom = frame(child, open(child, 199, { anchor_row = 21 }))
    expect.equality(bottom.row + bottom.height, 22)
end

T["position"]["scrollbar: on the text side of a west scrollbar"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { config = navigate.config({ scrollbar = { placement = { anchor = "NW" } } }) })
    local scrollbar = scrollbar_frame(child)
    local peek = frame(child, open(child, 100, { anchor_row = 10 }))
    expect.equality(peek.col, scrollbar.col + scrollbar.width)
end

T["position"]["scrollbar: beside the minimap on the same side"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        full = true,
        config = navigate.config({ minimap = { enabled = true, backend = "sync", width = 10 } }),
    })
    child.lua("require('scrollbar.minimap.scheduler').flush()")
    child.lua("require('scrollbar.scheduler').flush()")
    local minimap_win =
        child.lua_get("require('scrollbar.minimap.renderer').get_state(vim.api.nvim_get_current_win()).float_win")
    local minimap = frame(child, minimap_win)
    local peek = frame(child, open(child, 100, { anchor_row = 10 }))
    expect.equality(peek.col + peek.width, minimap.col)
end

T["position"]["cursor: below the cursor line, or above without room"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {})
    child.api.nvim_win_set_cursor(0, { 3, 0 })
    local below = frame(child, open(child, 100, { position = "cursor" }))
    expect.equality(below.row, 3)
    expect.equality(below.col, 0)

    child.api.nvim_win_set_cursor(0, { 18, 0 })
    local above = frame(child, open(child, 100, { position = "cursor" }))
    expect.equality(above.row + above.height, 17)
end

T["position"]["center: in the middle of the source window"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {})
    local peek = frame(child, open(child, 100, { position = "center" }))
    expect.equality(peek.row, math.floor((22 - 11) / 2))
    expect.equality(peek.col, math.floor((80 - 48) / 2))
end

T["size"] = MiniTest.new_set()

T["size"]["height and width are clamped to the text area"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { config = navigate.config({ peek = { context = 50, width = 1 } }) })
    child.wo.number = true
    child.lua("require('scrollbar.renderer').render(vim.api.nvim_get_current_win())")
    local scrollbar = scrollbar_frame(child)
    local textoff = child.fn.getwininfo(child.api.nvim_get_current_win())[1].textoff
    local peek = frame(child, open(child, 100, { anchor_row = 10 }))
    expect.equality(peek.height, 22)
    expect.equality(peek.col, textoff)
    expect.equality(peek.col + peek.width, scrollbar.col)

    local center = frame(child, open(child, 100, { position = "center" }))
    expect.equality(center.col, textoff)
    expect.equality(center.width, 80 - textoff)
end

T["size"]["a window without room opens no float"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { config = navigate.config({ peek = { window = { border = "single" } } }) })
    child.cmd("resize 2")
    expect.equality(open(child, 10, { anchor_row = 0 }), vim.NIL)
end

T["window"] = MiniTest.new_set()

T["window"]["shows the source buffer with the mark line under the cursor"] = function()
    local child = navigate.new_child()
    local setup = navigate.setup(child, {})
    local win = open(child, 120, { anchor_row = 10 })
    expect.equality(child.api.nvim_win_get_buf(win), setup.source_buf)
    expect.equality(child.api.nvim_win_get_cursor(win), { 121, 0 })
    expect.equality(child.api.nvim_get_current_win(), setup.source_win)
    local options = child.lua_func(function(peek_win)
        local result = {}
        for _, name in ipairs({ "number", "cursorline", "signcolumn", "foldenable", "wrap" }) do
            result[name] = vim.api.nvim_get_option_value(name, { win = peek_win })
        end
        result.config = vim.api.nvim_win_get_config(peek_win)
        result.owned = vim.w[peek_win].scrollbar_navigate_owned
        return result
    end, win)
    expect.equality(options.number, true)
    expect.equality(options.cursorline, true)
    expect.equality(options.signcolumn, "auto")
    expect.equality(options.foldenable, false)
    expect.equality(options.wrap, false)
    expect.equality(options.config.focusable, false)
    expect.equality(options.owned, true)
end

T["window"]["wo overrides the defaults"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        config = navigate.config({
            peek = { window = { wo = { number = false, wrap = true, winhighlight = "Normal:Search" } } },
        }),
    })
    local win = open(child, 120, { anchor_row = 10 })
    expect.equality(child.api.nvim_get_option_value("number", { win = win }), false)
    expect.equality(child.api.nvim_get_option_value("wrap", { win = win }), true)
    expect.equality(child.api.nvim_get_option_value("winhighlight", { win = win }), "Normal:Search")
end

T["window"]["moves the open float to another line"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {})
    local first = open(child, 50, { anchor_row = 5 })
    local second = open(child, 150, { anchor_row = 15 })
    expect.equality(second, first)
    expect.equality(child.api.nvim_win_get_cursor(second), { 151, 0 })
    expect.equality(frame(child, second).row, 15 - 5)
    child.lua("require('scrollbar.navigate.peek').close()")
    expect.equality(child.api.nvim_win_is_valid(first), false)
    expect.equality(child.lua_get("require('scrollbar.navigate.peek').get()"), vim.NIL)
end

T["window"]["the title names the mark types and the line number"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        marks = { { line = 119, type = "GitChange" }, { line = 119, type = "Error" }, { line = 119, type = "Cursor" } },
        config = navigate.config({ peek = { window = { border = "single" } } }),
    })
    local win = open(child, 119, { anchor_row = 10 })
    local title = child.api.nvim_win_get_config(win).title
    expect.equality(title, { { " Error, GitChange · 120 " } })
    open(child, 10, { anchor_row = 1 })
    expect.equality(child.api.nvim_win_get_config(win).title, { { " 11 " } })
end

T["window"]["a float without a border has no title"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = { { line = 119, type = "Error" } } })
    local win = open(child, 119, { anchor_row = 10 })
    expect.equality(child.api.nvim_win_get_config(win).title, nil)
end

T["window"]["follows a 'winborder' change after setup"] = function()
    local child = navigate.new_child()
    if child.fn.exists("+winborder") == 0 then
        MiniTest.skip("'winborder' is not available")
    end
    navigate.setup(child, { marks = { { line = 119, type = "Error" } } })
    local plain = open(child, 119, { anchor_row = 10 })
    expect.equality(frame(child, plain).height, 11)
    child.lua("require('scrollbar.navigate.peek').close()")

    child.o.winborder = "single"
    local scrollbar = scrollbar_frame(child)
    local bordered = open(child, 119, { anchor_row = 10 })
    local config = child.api.nvim_win_get_config(bordered)
    expect.equality(config.title, { { " Error · 120 " } })
    -- The frame is two columns wider than the content and stays beside the
    -- scrollbar.
    local position = frame(child, bordered)
    expect.equality(position.col + position.width + 2, scrollbar.col)
    -- A `border` key wins over 'winborder'.
    child.lua("require('scrollbar.navigate.peek').close()")
    child.lua(
        [[require("scrollbar.config").set(vim.tbl_extend("force", require("tests.navigate.helpers").config(), { peek = { window = { border = "none" } } }))]]
    )
    local none = open(child, 119, { anchor_row = 10 })
    expect.equality(child.api.nvim_win_get_config(none).title, nil)
end

T["window"]["never gets a scrollbar or a minimap"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {})
    -- `floats.when` admits every float, so only the source policy keeps the
    -- peek float out.
    child.lua([[
        local config = require("tests.navigate.helpers").config({ minimap = { enabled = true, backend = "sync" } })
        local function always()
            return true
        end
        config.scrollbar.floats = { when = always }
        config.minimap.floats = { when = always }
        require("scrollbar").setup(config)
    ]])
    local win = open(child, 120, { anchor_row = 10 })
    local function rendered(winid)
        return child.lua_func(function(target)
            for _, name in ipairs({ "scrollbar", "scrollbar.minimap" }) do
                local scheduler = require(name .. ".scheduler")
                scheduler.invalidate_all()
                scheduler.flush()
            end
            return {
                require("scrollbar.renderer").get_state(target) ~= nil,
                require("scrollbar.minimap.renderer").get_state(target) ~= nil,
            }
        end, winid)
    end
    expect.equality(rendered(win), { false, false })
    -- A float of another plugin on the same buffer gets both.
    local other = child.api.nvim_open_win(0, false, { relative = "editor", row = 1, col = 1, width = 30, height = 8 })
    expect.equality(rendered(other), { true, true })
end

return T
