local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function cells(child, types)
    return child.lua_func(function(names)
        local result = {}
        for _, cell in ipairs(require("scrollbar.navigate.targets").cells(vim.api.nvim_get_current_win(), names)) do
            result[#result + 1] = { cell.row, cell.col, cell.type, cell.line }
        end
        return result
    end, types)
end

--- Each entry as `{ kind, line, types }`, and the glyph and group of its first
--- mark.
local function entries(child, mode, types)
    return child.lua_func(function(list, names)
        local result = {}
        local win = vim.api.nvim_get_current_win()
        for _, entry in ipairs(require("scrollbar.navigate.targets").entries(win, list, names)) do
            local entry_types = {}
            for _, mark in ipairs(entry.marks) do
                entry_types[#entry_types + 1] = mark.type
            end
            result[#result + 1] = {
                entry.kind,
                entry.line,
                table.concat(entry_types, ","),
                entry.marks[1].glyph,
                entry.marks[1].group,
            }
        end
        return result
    end, mode, types)
end

local MARKS = {
    { line = 10, type = "Error" },
    { line = 10, type = "GitChange" },
    { line = 10, type = "Error" },
    { line = 60, type = "Warn" },
    { line = 100, type = "Cursor" },
    { line = 150, type = "Mark", text = "a" },
}

T["cells"] = MiniTest.new_set()

T["cells"]["gives one target for each mark cell that a click reaches"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = MARKS })
    local result = cells(child)
    local hitmap = child.lua_get("require('scrollbar.renderer').get_hitmap(vim.api.nvim_get_current_win())")
    -- Each target is the line that a click on its cell uses.
    for _, cell in ipairs(result) do
        local hit = hitmap[cell[1] + 1][cell[2]]
        expect.equality(hit.line, cell[4])
        expect.equality(hit.type, cell[3])
    end
    local types = {}
    for _, cell in ipairs(result) do
        types[#types + 1] = cell[3]
    end
    -- The Error wins its cell over GitChange, and Cursor is not a target.
    expect.equality(types, { "Error", "Warn", "Mark" })
end

T["cells"]["Cursor is a target only when types names it"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = MARKS })
    local result = cells(child, { Cursor = true })
    expect.equality(#result, 1)
    expect.equality(result[1][3], "Cursor")
    expect.equality(result[1][4], 100)

    local filtered = cells(child, { Warn = true, Mark = true })
    expect.equality(#filtered, 2)
    expect.equality({ filtered[1][3], filtered[2][3] }, { "Warn", "Mark" })
end

T["cells"]["a mark that the thumb covers is not a target"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        marks = { { line = 0, type = "Error" }, { line = 150, type = "Warn" } },
        config = navigate.config({
            scrollbar = { layout = { columns = { { "track", "marks", "thumb" } } } },
        }),
    })
    local result = cells(child)
    expect.equality(#result, 1)
    expect.equality(result[1][3], "Warn")
end

T["cells"]["a scrollbar without a float has no targets"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = MARKS, config = navigate.config({ scrollbar = { show = false } }) })
    expect.equality(cells(child), {})
end

T["entries"] = MiniTest.new_set()

T["entries"]["line mode gives one entry for each marked line"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = MARKS, config = navigate.config({ marks = { Error = { text = { "E", "EE" } } } }) })
    expect.equality(entries(child, "line"), {
        -- Duplicates show once, in priority order.
        { "entry", 10, "Error,GitChange", "E", "ScrollbarError" },
        { "entry", 60, "Warn", "-", "ScrollbarWarn" },
        -- A Mark shows the letter of the provider.
        { "entry", 150, "Mark", "a", "ScrollbarMark" },
    })
end

T["entries"]["mark mode gives one entry for each mark"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = MARKS })
    expect.equality(entries(child, "mark"), {
        { "entry", 10, "Error", "-", "ScrollbarError" },
        { "entry", 10, "GitChange", "┃", "ScrollbarGitChange" },
        { "entry", 60, "Warn", "-", "ScrollbarWarn" },
        { "entry", 150, "Mark", "a", "ScrollbarMark" },
    })
end

T["entries"]["type mode groups by priority and then by name"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        marks = {
            { line = 70, type = "GitChange" },
            { line = 10, type = "GitAdd" },
            { line = 50, type = "Warn" },
            { line = 20, type = "Warn" },
            { line = 20, type = "Warn" },
        },
    })
    expect.equality(entries(child, "type"), {
        { "header", 20, "Warn,Warn", "-", "ScrollbarWarn" },
        { "entry", 20, "Warn", "-", "ScrollbarWarn" },
        { "entry", 50, "Warn", "-", "ScrollbarWarn" },
        { "header", 10, "GitAdd", "┃", "ScrollbarGitAdd" },
        { "entry", 10, "GitAdd", "┃", "ScrollbarGitAdd" },
        { "header", 70, "GitChange", "┃", "ScrollbarGitChange" },
        { "entry", 70, "GitChange", "┃", "ScrollbarGitChange" },
    })
end

T["entries"]["include the compact search matches as Search marks"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        marks = { { line = 10, type = "Error" } },
        compact = { 10, 40, 40 },
        config = navigate.config({ providers = { search = true } }),
    })
    expect.equality(entries(child, "mark"), {
        { "entry", 10, "Search", "-", "ScrollbarSearch" },
        { "entry", 10, "Error", "-", "ScrollbarError" },
        { "entry", 40, "Search", "-", "ScrollbarSearch" },
    })
    expect.equality(entries(child, "line", { Search = true }), {
        { "entry", 10, "Search", "-", "ScrollbarSearch" },
        { "entry", 40, "Search", "-", "ScrollbarSearch" },
    })
end

T["entries"]["Cursor and the types filter"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = MARKS })
    expect.equality(entries(child, "line", { Cursor = true }), {
        { "entry", 100, "Cursor", "•", "ScrollbarCursor" },
    })
    expect.equality(entries(child, "line", { GitChange = true, Warn = true }), {
        { "entry", 10, "GitChange", "┃", "ScrollbarGitChange" },
        { "entry", 60, "Warn", "-", "ScrollbarWarn" },
    })
end

T["entries"]["include the window marks and drop the lines past the end"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        marks = { { line = 10, type = "Error" } },
        window_marks = { { line = 30, type = "Hint" } },
    })
    child.api.nvim_buf_set_lines(0, 5, -1, false, {})
    expect.equality(entries(child, "line"), {})
    child.api.nvim_buf_set_lines(0, 5, 5, false, vim.fn["repeat"]({ "x" }, 100))
    expect.equality(entries(child, "line"), {
        { "entry", 10, "Error", "-", "ScrollbarError" },
        { "entry", 30, "Hint", "-", "ScrollbarHint" },
    })
end

T["entries"]["skip the types that the scrollbar hides and the providers that it does not consume"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        marks = MARKS,
        config = navigate.config({ scrollbar = { marks = { Warn = false } } }),
    })
    expect.equality(entries(child, "line"), {
        { "entry", 10, "Error,GitChange", "-", "ScrollbarError" },
        { "entry", 150, "Mark", "a", "ScrollbarMark" },
    })

    local minimap_only = navigate.new_child()
    navigate.setup(minimap_only, { marks = MARKS, targets = { minimap = true } })
    expect.equality(entries(minimap_only, "line"), {})
end

T["entries"]["read the providers of the minimap when the scrollbar is disabled"] = function()
    local child = navigate.new_child()
    navigate.setup(child, {
        marks = MARKS,
        targets = { scrollbar = true, minimap = true },
        config = navigate.config({ scrollbar = { enabled = false }, minimap = { enabled = true } }),
    })
    -- The minimap has no Cursor type, and the glyphs come from the scrollbar
    -- configuration.
    expect.equality(entries(child, "line"), {
        { "entry", 10, "Error,GitChange", "-", "ScrollbarError" },
        { "entry", 60, "Warn", "-", "ScrollbarWarn" },
        { "entry", 150, "Mark", "a", "ScrollbarMark" },
    })
end

T["the renderer and the list use one provider rule"] = function()
    local child = navigate.new_child()
    navigate.setup(child, { marks = MARKS, targets = { minimap = true } })
    -- The scrollbar does not consume the provider, so it has no mark cell.
    expect.equality(cells(child, { Error = true, Warn = true, Mark = true, Cursor = true }), {})
    expect.equality(entries(child, "mark"), {})
end

return T
