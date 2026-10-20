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

-- The scrollbar thumb paints "S" and the minimap paints block cells, which
-- screen_row() reports as "M", so the screen shows which float is on top.
local function setup(child, options)
    options = options or {}
    child.lua_func(function(opts)
        local scrollbar = vim.tbl_deep_extend("force", {
            hide_on_cursor = false,
            layout = { columns = { { "track", "thumb" } } },
            thumb = { text = "S" },
        }, opts.scrollbar or {})
        local minimap = vim.tbl_deep_extend("force", {
            enabled = true,
            backend = "sync",
            width = 4,
            hide_on_cursor = false,
            encoding = "block",
        }, opts.minimap or {})
        require("scrollbar").setup({
            set_highlights = false,
            exclude = opts.exclude,
            providers = { cursor = false, diagnostic = false, search = false, marks = opts.marks or false },
            scrollbar = scrollbar,
            minimap = minimap,
        })
        local lines = {}
        for index = 1, 100 do
            lines[index] = string.rep("x", 40)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
    end, options)
end

-- Flush in two rounds. The minimap sets window options when it creates its
-- float. During that OptionSet, the scrollbar scheduler can close an
-- editor-relative scrollbar until its next flush.
local function flush(child)
    child.lua([[
        local scheduler = require("scrollbar.scheduler")
        local minimap_scheduler = require("scrollbar.minimap.scheduler")
        for _ = 1, 2 do
            scheduler.invalidate_all()
            scheduler.flush()
            minimap_scheduler.invalidate_all()
            minimap_scheduler.flush()
        end
    ]])
end

-- `left` is the zero-based column of the left float edge, relative to the
-- source window for a window-relative float and to the editor otherwise.
-- Headless Neovim does not apply the anchor in nvim_win_get_position(), so
-- the column comes from the float configuration.
local function floats(child, source_win)
    return child.lua_func(function(win)
        win = win or vim.api.nvim_get_current_win()
        local function info(state)
            if state == nil then
                return false
            end
            local config = vim.api.nvim_win_get_config(state.float_win)
            local east = config.anchor == "NE" or config.anchor == "SE"
            return {
                left = east and config.col - config.width or config.col,
                width = config.width,
                zindex = config.zindex,
                hide = config.hide == true,
            }
        end
        return {
            scrollbar = info(require("scrollbar.renderer").get_state(win)),
            minimap = info(require("scrollbar.minimap.renderer").get_state(win)),
        }
    end, source_win)
end

local function screen_row(child, source_win)
    child.cmd("redraw")
    return child.lua_func(function(win)
        win = win or vim.api.nvim_get_current_win()
        local info = vim.fn.getwininfo(win)[1]
        local cells = {}
        for offset = 0, info.width - 1 do
            local cell = vim.fn.screenstring(info.winrow, info.wincol + offset)
            cells[#cells + 1] = cell == "█" and "M" or cell
        end
        return table.concat(cells)
    end, source_win)
end

T["inner places the minimap beside the text and the scrollbar at the east edge"] = function()
    local child = new_child()
    setup(child)
    flush(child)

    expect.equality(floats(child), {
        scrollbar = { left = 79, width = 1, zindex = 50, hide = false },
        minimap = { left = 75, width = 4, zindex = 50, hide = false },
    })
    expect.equality(screen_row(child):sub(-5), "MMMMS")
end

T["outer places the scrollbar beside the text and the minimap at the east edge"] = function()
    local child = new_child()
    setup(child, { minimap = { placement = { stack = "outer" } } })
    flush(child)

    expect.equality(floats(child), {
        scrollbar = { left = 75, width = 1, zindex = 50, hide = false },
        minimap = { left = 76, width = 4, zindex = 50, hide = false },
    })
    expect.equality(screen_row(child):sub(-5), "SMMMM")
end

T["inner float col is relative to the inward edge of the outer float"] = function()
    local child = new_child()
    setup(child, {
        scrollbar = { placement = { col = -1 } },
        minimap = { placement = { col = -2 } },
    })
    flush(child)

    expect.equality(floats(child).scrollbar.left, 78)
    expect.equality(floats(child).minimap.left, 72)
    expect.equality(screen_row(child):sub(-8), "MMMM  S ")
end

local function cycle_hide(child, renderer)
    child.lua_func(function(module)
        local state = require(module).get_state(vim.api.nvim_get_current_win())
        vim.api.nvim_win_set_config(state.float_win, { hide = true })
        vim.cmd("redraw")
        vim.api.nvim_win_set_config(state.float_win, { hide = false })
    end, renderer)
end

T["above keeps the minimap on top after hide and show cycles"] = function()
    local child = new_child()
    setup(child, { minimap = { placement = { stack = "above" } } })
    flush(child)

    expect.equality(floats(child), {
        scrollbar = { left = 79, width = 1, zindex = 49, hide = false },
        minimap = { left = 76, width = 4, zindex = 50, hide = false },
    })
    expect.equality(screen_row(child):sub(-4), "MMMM")
    cycle_hide(child, "scrollbar.renderer")
    expect.equality(screen_row(child):sub(-4), "MMMM")
end

T["below keeps the scrollbar on top after hide and show cycles"] = function()
    local child = new_child()
    setup(child, { minimap = { placement = { stack = "below" } } })
    flush(child)

    expect.equality(floats(child), {
        scrollbar = { left = 79, width = 1, zindex = 50, hide = false },
        minimap = { left = 76, width = 4, zindex = 49, hide = false },
    })
    expect.equality(screen_row(child):sub(-4), "MMMS")
    cycle_hide(child, "scrollbar.minimap.renderer")
    expect.equality(screen_row(child):sub(-4), "MMMS")
end

T["different explicit z-indexes win over above and below"] = function()
    local child = new_child()
    setup(child, { minimap = { placement = { stack = "above", zindex = 40 } } })
    flush(child)

    expect.equality(floats(child).scrollbar.zindex, 50)
    expect.equality(floats(child).minimap.zindex, 40)
    expect.equality(screen_row(child):sub(-4), "MMMS")
end

T["west inner places the minimap after the reserved scrollbar cells"] = function()
    local child = new_child()
    setup(child, {
        scrollbar = { placement = { anchor = "NW", gutter = "inner" } },
        minimap = { placement = { anchor = "NW" } },
    })
    child.lua([[
        vim.wo.number = true
        vim.wo.relativenumber = false
        vim.wo.signcolumn = "no"
        vim.wo.foldcolumn = "0"
    ]])
    flush(child)
    flush(child)

    expect.equality(floats(child).scrollbar.left, 4)
    expect.equality(floats(child).minimap.left, 5)
    expect.equality(screen_row(child):sub(1, 10), "  1 SMMMMx")
end

T["west outer with an overlapping gutter places the scrollbar after the minimap"] = function()
    local child = new_child()
    setup(child, {
        scrollbar = { placement = { anchor = "NW", gutter = "overlap" } },
        minimap = { placement = { anchor = "NW", stack = "outer" } },
    })
    flush(child)

    expect.equality(floats(child).minimap.left, 0)
    expect.equality(floats(child).scrollbar.left, 4)
    expect.equality(screen_row(child):sub(1, 6), "MMMMSx")
end

T["a cursor-hidden outer scrollbar keeps the minimap slot"] = function()
    local child = new_child()
    setup(child, { scrollbar = { hide_on_cursor = true } })
    -- Headless Neovim does not settle anchored float positions, so place the
    -- cursor on the last screen column and resolve positions from the float
    -- configuration.
    child.lua([[
        rawset(vim.fn, "screenrow", function()
            return 1
        end)
        rawset(vim.fn, "screencol", function()
            return 80
        end)
        local get_config = vim.api.nvim_win_get_config
        rawset(vim.api, "nvim_win_get_position", function(win)
            local config = get_config(win)
            local east = config.anchor == "NE" or config.anchor == "SE"
            return { config.row, east and config.col - config.width or config.col }
        end)
    ]])
    flush(child)

    local result = floats(child)
    expect.equality(result.scrollbar.hide, true)
    expect.equality(result.minimap.left, 75)
end

T["an autohidden outer scrollbar keeps the minimap slot"] = function()
    local child = new_child()
    setup(child, { scrollbar = { autohide = true } })
    child.lua([[require("scrollbar.scheduler").reveal_all()]])
    flush(child)
    expect.equality(floats(child).scrollbar.left, 79)
    expect.equality(floats(child).minimap.left, 75)

    child.lua([[require("scrollbar.renderer").conceal(vim.api.nvim_get_current_win())]])
    expect.equality(floats(child), {
        scrollbar = false,
        minimap = { left = 75, width = 4, zindex = 50, hide = false },
    })

    -- A concealed render keeps the held footprint.
    child.lua([[require("scrollbar.renderer").render(vim.api.nvim_get_current_win())]])
    child.lua([[require("scrollbar.minimap.renderer").render(vim.api.nvim_get_current_win())]])
    expect.equality(floats(child).scrollbar, false)
    expect.equality(floats(child).minimap.left, 75)
end

T["MinimapHide moves an inner scrollbar to the edge at once"] = function()
    local child = new_child()
    setup(child, { minimap = { placement = { stack = "outer" } } })
    flush(child)
    expect.equality(floats(child).scrollbar.left, 75)

    child.cmd("MinimapHide")
    expect.equality(floats(child), {
        scrollbar = { left = 79, width = 1, zindex = 50, hide = false },
        minimap = false,
    })

    child.cmd("MinimapShow")
    flush(child)
    expect.equality(floats(child).scrollbar.left, 75)
end

T["a minimap-excluded filetype moves an inner scrollbar to the edge"] = function()
    local child = new_child()
    setup(child, {
        exclude = { filetypes = { stackft = { scrollbar = false } } },
        minimap = { placement = { stack = "outer" } },
    })
    flush(child)
    expect.equality(floats(child).scrollbar.left, 75)

    child.lua([[vim.bo.filetype = "stackft"]])
    flush(child)
    expect.equality(floats(child), {
        scrollbar = { left = 79, width = 1, zindex = 50, hide = false },
        minimap = false,
    })
end

T["hide_if_all_visible on the outer scrollbar moves the minimap to the edge"] = function()
    local child = new_child()
    setup(child, { scrollbar = { hide_if_all_visible = true } })
    flush(child)
    expect.equality(floats(child).minimap.left, 75)

    child.lua([[vim.api.nvim_buf_set_lines(0, 10, -1, false, {})]])
    flush(child)
    expect.equality(floats(child), {
        scrollbar = false,
        minimap = { left = 76, width = 4, zindex = 50, hide = false },
    })
end

T["a wider outer scrollbar moves the minimap without a minimap render"] = function()
    local child = new_child()
    setup(child, {
        scrollbar = {
            profiles = {
                {
                    match = { filetypes = { "wide" } },
                    layout = { columns = { { "track", "thumb" }, { "track", "thumb" } } },
                },
            },
        },
    })
    flush(child)
    expect.equality(floats(child).minimap.left, 75)

    local result = child.lua_func(function()
        local win = vim.api.nvim_get_current_win()
        local minimap_renderer = require("scrollbar.minimap.renderer")
        local before = minimap_renderer.get_state(win).rendered_signature
        vim.bo.filetype = "wide"
        require("scrollbar.renderer").invalidate_source_selection(win)
        require("scrollbar.scheduler").invalidate_all()
        require("scrollbar.scheduler").flush()
        local state = assert(minimap_renderer.get_state(win))
        return {
            col = vim.api.nvim_win_get_config(state.float_win).col,
            same_render = state.rendered_signature == before,
        }
    end)
    expect.equality(result, { col = 78, same_render = true })
end

T["a repositioned minimap checks the cursor overlap again"] = function()
    local child = new_child()
    setup(child, {
        minimap = { hide_on_cursor = true },
        scrollbar = {
            profiles = {
                {
                    match = { filetypes = { "wide" } },
                    layout = { columns = { { "track", "thumb" }, { "track", "thumb" } } },
                },
            },
        },
    })
    -- The cursor is on screen column 75 (zero-based 74), one cell left of the
    -- minimap. After the scrollbar grows to two cells, the minimap covers it.
    child.lua([[
        rawset(vim.fn, "screenrow", function()
            return 1
        end)
        rawset(vim.fn, "screencol", function()
            return 75
        end)
        local get_config = vim.api.nvim_win_get_config
        rawset(vim.api, "nvim_win_get_position", function(win)
            local config = get_config(win)
            local east = config.anchor == "NE" or config.anchor == "SE"
            return { config.row, east and config.col - config.width or config.col }
        end)
    ]])
    flush(child)
    expect.equality(floats(child).minimap, { left = 75, width = 4, zindex = 50, hide = false })

    child.lua([[
        local win = vim.api.nvim_get_current_win()
        vim.bo.filetype = "wide"
        require("scrollbar.renderer").invalidate_source_selection(win)
        require("scrollbar.scheduler").invalidate_all()
        require("scrollbar.scheduler").flush()
    ]])
    expect.equality(floats(child).minimap, { left = 74, width = 4, zindex = 50, hide = true })
end

T["does not stack a pair with mixed relative modes or opposite sides"] = function()
    local child = new_child()
    setup(child, { scrollbar = { placement = { relative = "editor" } } })
    flush(child)
    expect.equality(floats(child).scrollbar.left, 79)
    expect.equality(floats(child).minimap.left, 76)

    child.lua([[require("scrollbar").setup({
        set_highlights = false,
        providers = { cursor = false, diagnostic = false, search = false, marks = false },
        scrollbar = { hide_on_cursor = false },
        minimap = { enabled = true, backend = "sync", width = 4, hide_on_cursor = false, placement = { anchor = "NW" } },
    })]])
    flush(child)
    expect.equality(floats(child).scrollbar.left, 79)
    expect.equality(floats(child).minimap.left, 0)
end

T["a disabled minimap leaves the scrollbar float config unchanged"] = function()
    local child = new_child()
    setup(child, { minimap = { enabled = false } })
    flush(child)

    local result = child.lua_func(function()
        local state = assert(require("scrollbar.renderer").get_state(vim.api.nvim_get_current_win()))
        local config = vim.api.nvim_win_get_config(state.float_win)
        return {
            col = config.col,
            zindex = config.zindex,
            minimap_footprints = require("scrollbar.shared.stack").windows("minimap"),
        }
    end)
    expect.equality(result, { col = 80, zindex = 50, minimap_footprints = {} })
end

T["each split stacks on its own and a closed split drops its footprints"] = function()
    local child = new_child()
    setup(child)
    child.cmd("vsplit")
    flush(child)

    local windows = child.lua_get([[vim.tbl_filter(function(win)
        return vim.api.nvim_win_get_config(win).relative == ""
    end, vim.api.nvim_tabpage_list_wins(0))]])
    expect.equality(#windows, 2)
    for _, win in ipairs(windows) do
        local width = child.lua_get("vim.api.nvim_win_get_width(...)", { win })
        local result = floats(child, win)
        expect.equality(result.scrollbar.left, width - 1)
        expect.equality(result.minimap.left, width - 5)
    end

    local closed = child.lua_get("vim.api.nvim_get_current_win()")
    child.cmd("close")
    flush(child)
    local remaining = child.lua_get([[{
        scrollbar = require("scrollbar.shared.stack").windows("scrollbar"),
        minimap = require("scrollbar.shared.stack").windows("minimap"),
    }]])
    expect.equality(vim.tbl_contains(remaining.scrollbar, closed), false)
    expect.equality(vim.tbl_contains(remaining.minimap, closed), false)
    expect.equality(#remaining.scrollbar, 1)
    expect.equality(#remaining.minimap, 1)
end

T["an inactive window under scrollbar visibility active moves the minimap to the edge"] = function()
    local child = new_child()
    setup(child, { scrollbar = { visibility = "active" } })
    child.cmd("vsplit")
    flush(child)

    local active = child.lua_get("vim.api.nvim_get_current_win()")
    local other = child.lua_get("vim.fn.win_getid(vim.fn.winnr('#'))")
    local active_width = child.lua_get("vim.api.nvim_win_get_width(...)", { active })
    local other_width = child.lua_get("vim.api.nvim_win_get_width(...)", { other })
    expect.equality(floats(child, active).minimap.left, active_width - 5)
    expect.equality(floats(child, other), {
        scrollbar = false,
        minimap = { left = other_width - 4, width = 4, zindex = 50, hide = false },
    })
end

local SIDE_BORDER = { "", "", "", "│", "", "", "", "│" }

-- The border characters take more than one byte, so the checks cut the row by
-- the byte length of the expected text.
local function expect_row_end(child, expected)
    local row = screen_row(child)
    expect.equality(row:sub(-#expected), expected)
end

local function expect_row_start(child, expected)
    local row = screen_row(child)
    expect.equality(row:sub(1, #expected), expected)
end

T["inner places the bordered minimap at the inward frame edge of the scrollbar"] = function()
    local child = new_child()
    setup(child, {
        scrollbar = { window = { border = SIDE_BORDER } },
        minimap = { window = { border = SIDE_BORDER } },
    })
    flush(child)

    expect_row_end(child, " │MMMM││S│")
end

T["outer places the bordered scrollbar at the inward frame edge of the minimap"] = function()
    local child = new_child()
    setup(child, {
        scrollbar = { window = { border = SIDE_BORDER } },
        minimap = { placement = { stack = "outer" }, window = { border = SIDE_BORDER } },
    })
    flush(child)

    expect_row_end(child, " │S││MMMM│")
end

T["west inner places the bordered minimap after the reserved scrollbar frame"] = function()
    local child = new_child()
    setup(child, {
        scrollbar = { placement = { anchor = "NW", gutter = "inner" }, window = { border = SIDE_BORDER } },
        minimap = { placement = { anchor = "NW" }, window = { border = SIDE_BORDER } },
    })
    child.lua([[
        vim.wo.number = true
        vim.wo.relativenumber = false
        vim.wo.signcolumn = "no"
        vim.wo.foldcolumn = "0"
    ]])
    flush(child)
    flush(child)

    expect_row_start(child, "  1 │S││MMMM│x")
end

return T
