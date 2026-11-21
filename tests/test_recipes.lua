local MiniTest = MiniTest
local expect = MiniTest.expect
local helpers = dofile("tests/helpers.lua")

local T = MiniTest.new_set()

local recipes = require("scrollbar.recipes")

---A mark context that records the reads of the lazy fields, as the context of
---the mark layer does.
---@param fields table
---@return table context
---@return table<string, true> reads
local function mark_context(fields)
    local reads = {}
    local lazy = { cursor_line = fields.cursor_line, line_count = fields.line_count }
    fields.cursor_line = nil
    fields.line_count = nil
    local context = setmetatable(fields, {
        __index = function(_, key)
            reads[key] = true
            return lazy[key]
        end,
    })
    return context, reads
end

---@param fields table
---@return table
local function thumb_context(fields)
    return vim.tbl_extend("keep", fields, {
        winid = 1000,
        bufnr = 1,
        index = 0,
        row = 0,
        first_row = 0,
        last_row = 3,
        height = 20,
        top_line = 0,
        bottom_line = 9,
        line_count = 100,
        cursor_line = 0,
    })
end

T["marks"] = MiniTest.new_set()

T["marks"]["line_number shows the one-based line"] = function()
    local context = mark_context({ line = 41, count = 1 })

    expect.equality(recipes.marks.line_number()(context), "42")
    expect.equality(recipes.marks.line_number({ width = 4 })(context), "  42")
    expect.equality(recipes.marks.line_number({ width = 4, align = "left" })(context), "42  ")
    expect.equality(recipes.marks.line_number({ width = 2 })(mark_context({ line = 12344 })), "12345")
end

T["marks"]["relative_number shows the distance to the cursor line"] = function()
    local relative = recipes.marks.relative_number()

    expect.equality(relative(mark_context({ line = 41, cursor_line = 50 })), "9")
    expect.equality(relative(mark_context({ line = 60, cursor_line = 50 })), "10")
    expect.equality(relative(mark_context({ line = 50, cursor_line = 50 })), "0")
    expect.equality(recipes.marks.relative_number({ width = 3 })(mark_context({ line = 7, cursor_line = 0 })), "  7")
    -- The context has no cursor line when the source window closed.
    expect.equality(relative(mark_context({ line = 7 })), nil)
end

T["marks"]["count shows + when the count does not fit"] = function()
    local count = recipes.marks.count()
    local wide = recipes.marks.count({ width = 2 })

    expect.equality(count(mark_context({ line = 0, count = 3 })), "3")
    expect.equality(count(mark_context({ line = 0, count = 9 })), "9")
    expect.equality(count(mark_context({ line = 0, count = 10 })), "+")
    expect.equality(wide(mark_context({ line = 0, count = 3 })), " 3")
    expect.equality(wide(mark_context({ line = 0, count = 14 })), "14")
    expect.equality(wide(mark_context({ line = 0, count = 100 })), " +")
    expect.equality(recipes.marks.count({ width = 2, align = "left" })(mark_context({ line = 0, count = 3 })), "3 ")
end

T["marks"]["label joins the provider text and the line"] = function()
    local label = recipes.marks.label()

    expect.equality(label(mark_context({ line = 41, text = "a" })), "a:42")
    expect.equality(label(mark_context({ line = 41 })), "42")
    expect.equality(label(mark_context({ line = 41, text = "" })), "42")
    -- The padding counts display cells, not bytes.
    expect.equality(recipes.marks.label({ width = 6 })(mark_context({ line = 41, text = "界" })), " 界:42")
end

T["marks"]["only relative_number reads the cursor line"] = function()
    local cases = {
        line_number = recipes.marks.line_number(),
        count = recipes.marks.count(),
        label = recipes.marks.label({ width = 4 }),
        relative_number = recipes.marks.relative_number(),
    }
    local seen = {}
    for name, recipe in pairs(cases) do
        local context, reads = mark_context({ line = 4, count = 2, text = "a", cursor_line = 1, line_count = 10 })
        recipe(context)
        seen[name] = reads
    end

    expect.equality(seen.line_number, {})
    expect.equality(seen.count, {})
    expect.equality(seen.label, {})
    expect.equality(seen.relative_number, { cursor_line = true })
end

T["thumb"] = MiniTest.new_set()

T["thumb"]["top_line shows the first visible line on the first row"] = function()
    local top_line = recipes.thumb.top_line()

    expect.equality(top_line(thumb_context({ index = 0, top_line = 40 })), "41")
    expect.equality(top_line(thumb_context({ index = 1, top_line = 40 })), nil)
    expect.equality(recipes.thumb.top_line({ width = 4 })(thumb_context({ top_line = 40 })), "  41")
end

T["thumb"]["range shows the first and the last visible line"] = function()
    local range = recipes.thumb.range()
    local view = { top_line = 40, bottom_line = 77, first_row = 5, last_row = 8 }

    expect.equality(range(thumb_context(vim.tbl_extend("force", view, { index = 0 }))), "41")
    expect.equality(range(thumb_context(vim.tbl_extend("force", view, { index = 1 }))), nil)
    expect.equality(range(thumb_context(vim.tbl_extend("force", view, { index = 3 }))), "78")
    -- A thumb of one row shows the first line.
    expect.equality(range(thumb_context({ index = 0, first_row = 5, last_row = 5, top_line = 40 })), "41")
end

T["thumb"]["percent follows the rule of the ruler"] = function()
    local percent = recipes.thumb.percent()

    expect.equality(percent(thumb_context({ top_line = 0, bottom_line = 99, line_count = 100 })), "All")
    expect.equality(percent(thumb_context({ top_line = 0, bottom_line = 9, line_count = 100 })), "Top")
    expect.equality(percent(thumb_context({ top_line = 90, bottom_line = 99, line_count = 100 })), "Bot")
    -- 45 lines above and 45 lines below.
    expect.equality(percent(thumb_context({ top_line = 45, bottom_line = 54, line_count = 100 })), "50%")
    expect.equality(percent(thumb_context({ top_line = 1, bottom_line = 10, line_count = 100 })), "1%")
    -- Above one million lines, Neovim divides first.
    expect.equality(
        percent(thumb_context({ top_line = 1500001, bottom_line = 1500010, line_count = 2000011 })),
        string.format("%d%%", math.floor(1500001 / math.floor(2000001 / 100)))
    )
    expect.equality(percent(thumb_context({ index = 1, top_line = 45, bottom_line = 54 })), nil)
    expect.equality(recipes.thumb.percent({ width = 4 })(thumb_context({ top_line = 4, bottom_line = 13 })), "  4%")
end

T["thumb"]["percent matches the %P statusline item"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local results = child.lua([[
        local percent = require("scrollbar.recipes").thumb.percent()
        local lines = {}
        for index = 1, 1000 do
            lines[index] = tostring(index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local results = {}
        for _, top in ipairs({ 1, 2, 50, 500, 981, 983, 1000 }) do
            vim.cmd("normal! " .. top .. "Gzt")
            vim.cmd("redraw")
            local expected = vim.trim(vim.api.nvim_eval_statusline("%P", { winid = 0 }).str)
            local actual = percent({
                index = 0,
                top_line = vim.fn.line("w0") - 1,
                bottom_line = vim.fn.line("w$") - 1,
                line_count = vim.api.nvim_buf_line_count(0),
            })
            results[#results + 1] = { top = top, expected = expected, actual = actual }
        end
        return results
    ]])

    for _, result in ipairs(results) do
        expect.equality({ top = result.top, text = result.actual }, { top = result.top, text = result.expected })
    end
end

T["options"] = MiniTest.new_set()

T["options"]["reject invalid values when the factory is called"] = function()
    local cases = {
        { recipes.marks.line_number, "x", "[nvim-scrollbar] recipes.marks.line_number: options must be a table" },
        {
            recipes.marks.count,
            { size = 2 },
            "[nvim-scrollbar] recipes.marks.count: unknown option 'size'",
        },
        {
            recipes.marks.label,
            { width = 0 },
            "[nvim-scrollbar] recipes.marks.label: width must be a positive integer",
        },
        {
            recipes.thumb.top_line,
            { width = 1.5 },
            "[nvim-scrollbar] recipes.thumb.top_line: width must be a positive integer",
        },
        {
            recipes.thumb.percent,
            { align = "center" },
            '[nvim-scrollbar] recipes.thumb.percent: align must be "left" or "right"',
        },
    }
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[1], case[2])
        expect.equality(ok, false)
        expect.equality(err, case[3])
    end
end

T["options"]["name the missing call of a factory"] = function()
    local messages = {}
    local original = vim.notify
    vim.notify = function(message)
        messages[#messages + 1] = message
    end
    MiniTest.finally(function()
        vim.notify = original
    end)
    local text_function = require("scrollbar.text_function")
    text_function.reset()

    -- The plugin calls `text = recipes.marks.line_number` with the context.
    local context = mark_context({ winid = 1000, bufnr = 1, line = 0, count = 1 })
    expect.equality(text_function.call(recipes.marks.line_number, context, "the test function"), nil)

    expect.equality(messages, {
        "[nvim-scrollbar] the test function failed: [nvim-scrollbar] recipes.marks.line_number:"
            .. " call the recipe to get its function, for example recipes.marks.line_number()",
    })
end

T["options"]["are copied when the factory is called"] = function()
    local options = { width = 4 }
    local line_number = recipes.marks.line_number(options)
    options.width = 8
    options.align = "left"

    expect.equality(line_number(mark_context({ line = 6 })), "   7")
end

---A frame context of a window of 80 by 22 cells without a gutter, a
---scrollbar in the last 2 columns, and no border.
---@param fields? table
---@return ScrollbarFrameContext
local function frame_context(fields)
    return vim.tbl_deep_extend("force", {
        kind = "glance",
        winid = 1000,
        bufnr = 1,
        win = { width = 80, height = 22, textoff = 0 },
        editor = { width = 120, height = 40 },
        sides = { top = 0, right = 0, bottom = 0, left = 0 },
        cursor_row = 0,
        anchor_row = 0,
        free = { side = "E", first_col = 0, last_col = 78 },
    }, fields or {})
end

T["frame"] = MiniTest.new_set()

T["frame"]["center: at the center of the text area"] = function()
    local center = recipes.frame.center
    expect.equality(center()(frame_context()), { row = 2, col = 0, width = 80, height = 18 })
    expect.equality(
        center()(frame_context({ kind = "peek" })),
        { row = math.floor((22 - 11) / 2), col = 16, width = 48, height = 11 }
    )
    expect.equality(
        center({ width = 0.5, height = 10 })(frame_context()),
        { row = 6, col = 20, width = 40, height = 10 }
    )
    -- A part measures the text area, right of the gutter.
    expect.equality(
        center({ width = 0.5 })(frame_context({ win = { textoff = 4 } })),
        { row = 2, col = 4 + 19, width = 38, height = 18 }
    )
    -- A size larger than the text area shrinks to it.
    expect.equality(
        center({ width = 200, height = 50 })(frame_context({ win = { textoff = 4 } })),
        { row = 0, col = 4, width = 76, height = 22 }
    )
end

T["frame"]["center: relative to the editor"] = function()
    local place = recipes.frame.center({ relative = "editor", width = 0.8, height = 0.5 })
    expect.equality(place(frame_context()), { relative = "editor", row = 10, col = 12, width = 96, height = 20 })
    -- Without a size, the default size of the kind measures the editor area.
    expect.equality(
        recipes.frame.center({ relative = "editor" })(frame_context()),
        { relative = "editor", row = 11, col = 0, width = 120, height = 18 }
    )
end

T["frame"]["cursor: below, above, or the larger side"] = function()
    local cursor = recipes.frame.cursor()
    expect.equality(cursor(frame_context({ cursor_row = 3 })), { row = 4, col = 0, width = 80, height = 18 })
    expect.equality(cursor(frame_context({ cursor_row = 20 })), { row = 2, col = 0, width = 80, height = 18 })
    -- Row 10 has 11 rows below and 10 rows above.
    expect.equality(cursor(frame_context({ cursor_row = 10 })), { row = 11, col = 0, width = 80, height = 11 })
    expect.equality(cursor(frame_context({ cursor_row = 12 })), { row = 0, col = 0, width = 80, height = 12 })
    -- The peek is 11 rows by 60% of the text width, and it starts at the gutter.
    expect.equality(
        cursor(frame_context({ kind = "peek", cursor_row = 3, win = { textoff = 5 } })),
        { row = 4, col = 5, width = 45, height = 11 }
    )
    -- With a border, a side needs room for one content row and the border.
    local bordered = frame_context({ cursor_row = 0, win = { height = 2 }, sides = { top = 1, bottom = 1 } })
    expect.equality(cursor(bordered).row, 1)
end

T["frame"]["scrollbar: beside the floats, centered on the anchor row"] = function()
    local scrollbar = recipes.frame.scrollbar()
    expect.equality(
        scrollbar(frame_context({ kind = "peek", anchor_row = 10 })),
        { row = 5, col = 30, width = 48, height = 11 }
    )
    -- The content rows center on the anchor row, below a top border.
    expect.equality(
        scrollbar(frame_context({ kind = "peek", anchor_row = 10, sides = { top = 1, bottom = 1 } })).row,
        10 - 1 - 4
    )
    expect.equality(
        scrollbar(frame_context({ kind = "peek", free = { side = "W", first_col = 2, last_col = 80 } })).col,
        2
    )
    -- The width stays inside the free columns.
    expect.equality(
        recipes.frame.scrollbar({ width = 1 })(frame_context({ free = { first_col = 10, last_col = 40 } })),
        { row = -9, col = 10, width = 30, height = 18 }
    )
    expect.equality(scrollbar(frame_context({ free = { first_col = 40, last_col = 40 } })), nil)
end

T["frame"]["sizes take parts or cells"] = function()
    local context = frame_context()
    expect.equality(
        recipes.frame.center({ width = 1, height = 1 })(context),
        { row = 0, col = 0, width = 80, height = 22 }
    )
    expect.equality(recipes.frame.center({ width = 30, height = 2 })(context).width, 30)
    expect.equality(recipes.frame.center({ width = 0.25 })(context).width, 20)
end

T["frame"]["presets are the recipes without options"] = function()
    local frame = require("scrollbar.navigate.frame")
    for _, kind in ipairs({ "peek", "glance" }) do
        for _, preset in ipairs({ "scrollbar", "cursor", "center" }) do
            local context = frame_context({ kind = kind, cursor_row = 5, anchor_row = 9 })
            local from_preset = frame.run("test.frame", preset, context, 0)
            local from_recipe = frame.run("test.frame", recipes.frame[preset](), context, 0)
            expect.equality(from_preset, from_recipe)
            expect.no_equality(from_preset, nil)
        end
    end
end

T["frame"]["factories reject invalid options"] = function()
    local cases = {
        { recipes.frame.center, "x", "[nvim-scrollbar] recipes.frame.center: options must be a table" },
        { recipes.frame.center, { row = 1 }, "[nvim-scrollbar] recipes.frame.center: unknown option 'row'" },
        {
            recipes.frame.cursor,
            { relative = "editor" },
            "[nvim-scrollbar] recipes.frame.cursor: unknown option 'relative'",
        },
        {
            recipes.frame.center,
            { relative = "screen" },
            '[nvim-scrollbar] recipes.frame.center: relative must be "win" or "editor"',
        },
    }
    local size_message = " must be a number greater than 0 and at most 1, or a whole number greater than 1"
    for _, value in ipairs({ 0, -1, 1.5, "half", 0 / 0, math.huge }) do
        cases[#cases + 1] = {
            recipes.frame.scrollbar,
            { width = value },
            "[nvim-scrollbar] recipes.frame.scrollbar: width" .. size_message,
        }
        cases[#cases + 1] = {
            recipes.frame.cursor,
            { height = value },
            "[nvim-scrollbar] recipes.frame.cursor: height" .. size_message,
        }
    end
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[1], case[2])
        expect.equality(ok, false)
        expect.equality(err, case[3])
    end
end

T["frame"]["name the missing call of a factory"] = function()
    local messages = {}
    local original = vim.notify
    vim.notify = function(message)
        messages[#messages + 1] = message
    end
    MiniTest.finally(function()
        vim.notify = original
    end)
    local frame = require("scrollbar.navigate.frame")
    frame.reset()

    -- The plugin calls `frame = recipes.frame.center` with the context.
    expect.equality({ frame.run("glance.frame", recipes.frame.center, frame_context(), 0) }, { nil, "failed" })
    expect.equality(messages, {
        "[nvim-scrollbar] glance.frame failed: [nvim-scrollbar] recipes.frame.center:"
            .. " call the recipe to get its function, for example recipes.frame.center()",
    })
end

T["frame"]["options are copied when the factory is called"] = function()
    local options = { width = 0.5 }
    local place = recipes.frame.center(options)
    options.width = 10
    expect.equality(place(frame_context()).width, 40)
end

T["setup does not load the recipes"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    child.lua([[require("scrollbar").setup()]])

    expect.equality(child.lua_get([[package.loaded["scrollbar.recipes"] == nil]]), true)
end

T["when"] = MiniTest.new_set()

---@param fields? table
---@return table
local function when_context(fields)
    return vim.tbl_extend("keep", fields or {}, {
        winid = vim.api.nvim_get_current_win(),
        bufnr = vim.api.nvim_get_current_buf(),
        filetype = "lua",
        buftype = "",
        bufname = "",
        renderer = "scrollbar",
    })
end

T["when"]["searching follows the rule of the search provider"] = function()
    local provider = require("scrollbar.providers.search")
    local searching = recipes.when.searching({ cmdline = false })
    local saved = { hlsearch = vim.o.hlsearch, register = vim.fn.getreg("/") }
    MiniTest.finally(function()
        vim.o.hlsearch = saved.hlsearch
        vim.fn.setreg("/", saved.register)
    end)

    local matched = 0
    for _, hlsearch in ipairs({ false, true }) do
        for _, visible in ipairs({ 0, 1 }) do
            for _, register in ipairs({ "", "line" }) do
                vim.o.hlsearch = hlsearch
                vim.fn.setreg("/", register)
                vim.v.hlsearch = visible
                local expected = provider._search_is_visible()
                expect.equality(searching(when_context()), expected)
                matched = matched + (expected and 1 or 0)
            end
        end
    end
    -- Only 'hlsearch' on, `v:hlsearch` set, and a pattern match.
    expect.equality(matched, 1)
end

T["when"]["searching matches an open search command line"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.o.hlsearch = false

    child.type_keys(10, "/", "a")
    local during = child.lua_get([[{
        require("scrollbar.recipes").when.searching()({}),
        require("scrollbar.recipes").when.searching({ cmdline = false })({}),
    }]])
    child.type_keys(10, "<Esc>")
    local after = child.lua_get([[require("scrollbar.recipes").when.searching()({})]])

    expect.equality(during, { true, false })
    expect.equality(after, false)
end

T["when"]["diff matches a window with diff set"] = function()
    local diff = recipes.when.diff()
    local winid = vim.api.nvim_get_current_win()
    MiniTest.finally(function()
        vim.wo[winid].diff = false
    end)

    expect.equality(diff(when_context()), false)
    vim.wo[winid].diff = true
    expect.equality(diff(when_context()), true)
end

T["when"]["line_count matches the bounds"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    MiniTest.finally(function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "1", "2", "3", "4", "5" })
    local context = when_context({ bufnr = bufnr })

    expect.equality(recipes.when.line_count({ min = 5 })(context), true)
    expect.equality(recipes.when.line_count({ min = 6 })(context), false)
    expect.equality(recipes.when.line_count({ max = 5 })(context), true)
    expect.equality(recipes.when.line_count({ max = 4 })(context), false)
    expect.equality(recipes.when.line_count({ min = 2, max = 5 })(context), true)
    expect.equality(recipes.when.line_count({ min = 6, max = 9 })(context), false)
end

T["when"]["filetypes matches the filetype of the context"] = function()
    expect.equality(recipes.when.filetypes({ "lua", "markdown" })(when_context()), true)
    expect.equality(recipes.when.filetypes({ "help" })(when_context()), false)
end

T["when"]["any, all, and negate combine predicates"] = function()
    local function yes()
        return true
    end
    local function no()
        return false
    end
    local context = when_context()
    local seen
    local function record(value)
        seen = value
        return true
    end

    expect.equality(recipes.when.any(no, yes)(context), true)
    expect.equality(recipes.when.any(no, no)(context), false)
    expect.equality(recipes.when.all(yes, yes)(context), true)
    expect.equality(recipes.when.all(yes, no)(context), false)
    expect.equality(recipes.when.negate(no)(context), true)
    expect.equality(recipes.when.negate(yes)(context), false)
    expect.equality(recipes.when.negate(recipes.when.any(no, record))(context), false)
    expect.equality(seen, context)
end

T["when"]["active is false without a loaded renderer"] = function()
    local active = recipes.when.active()

    expect.equality(active(when_context({ renderer = "unknown" })), false)
    expect.equality(active(when_context({ renderer = nil })), false)
end

T["when"]["factories reject invalid arguments"] = function()
    local function predicate()
        return true
    end
    local cases = {
        { recipes.when.line_count, {}, "recipes.when.line_count: needs min or max" },
        { recipes.when.line_count, { {} }, "recipes.when.line_count: needs min or max" },
        { recipes.when.line_count, { { min = 0 } }, "recipes.when.line_count: min must be a positive integer" },
        { recipes.when.line_count, { { max = 2.5 } }, "recipes.when.line_count: max must be a positive integer" },
        { recipes.when.line_count, { { min = 5, max = 2 } }, "recipes.when.line_count: min must not be more than max" },
        { recipes.when.searching, { { cmdline = 1 } }, "recipes.when.searching: cmdline must be a boolean" },
        { recipes.when.searching, { { search = true } }, "recipes.when.searching: unknown option 'search'" },
        { recipes.when.diff, { { cmdline = true } }, "recipes.when.diff: takes no options" },
        { recipes.when.filetypes, { {} }, "recipes.when.filetypes: needs a non-empty list of filetypes" },
        { recipes.when.filetypes, { "lua" }, "recipes.when.filetypes: needs a non-empty list of filetypes" },
        { recipes.when.filetypes, { { lua = true } }, "recipes.when.filetypes: needs a non-empty list of filetypes" },
        { recipes.when.any, {}, "recipes.when.any: needs at least one predicate" },
        { recipes.when.all, { predicate, "x" }, "recipes.when.all: argument 2 must be a function" },
        { recipes.when.negate, { predicate, predicate }, "recipes.when.negate: takes one predicate" },
        -- The plugin calls a factory with the context when the user forgets the call.
        {
            recipes.when.diff,
            { when_context() },
            "recipes.when.diff: call the recipe to get its function, for example recipes.when.diff()",
        },
        {
            recipes.when.active,
            { when_context() },
            "recipes.when.active: call the recipe to get its function, for example recipes.when.active()",
        },
        {
            recipes.when.searching,
            { when_context() },
            "recipes.when.searching: call the recipe to get its function, for example recipes.when.searching()",
        },
    }
    for _, case in ipairs(cases) do
        local ok, err = pcall(case[1], unpack(case[2], 1, table.maxn(case[2])))
        expect.equality({ ok = ok, err = err }, { ok = false, err = "[nvim-scrollbar] " .. case[3] })
    end
end

T["when profiles"] = MiniTest.new_set()

---Starts the full plugin in a child with two vertical splits of one 300-line
---buffer. `config_source` is Lua code that returns the setup table, because a
---predicate cannot cross the RPC boundary.
---@param config_source string
---@return table child
local function plugin_child(config_source)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.lua(
        [[
        local lines = {}
        for index = 1, 300 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        _G.left = vim.api.nvim_get_current_win()
        vim.cmd("vsplit")
        _G.right = vim.api.nvim_get_current_win()
        vim.o.hlsearch = true

        local modules = {
            scrollbar = { renderer = "scrollbar.renderer", scheduler = "scrollbar.scheduler" },
            minimap = { renderer = "scrollbar.minimap.renderer", scheduler = "scrollbar.minimap.scheduler" },
        }
        ---The width of the float of a renderer on a window, or false.
        _G.width = function(renderer, winid)
            require(modules[renderer].scheduler).flush()
            local state = require(modules[renderer].renderer).get_state(winid)
            if state == nil or not vim.api.nvim_win_is_valid(state.float_win) then
                return false
            end
            return vim.api.nvim_win_get_width(state.float_win)
        end
        ---Waits for the widths of both splits. Returns the last widths.
        _G.widths = function(renderer, left, right)
            local result
            vim.wait(1000, function()
                result = { left = _G.width(renderer, _G.left), right = _G.width(renderer, _G.right) }
                return result.left == left and result.right == right
            end, 10)
            return result
        end

        require("scrollbar").setup(loadstring(...)())
    ]],
        { config_source }
    )
    return child
end

-- One column at the root, and two columns in the profile.
local TWO_COLUMN_PROFILE = [[
    local recipes = require("scrollbar.recipes")
    local function profile(when)
        return {
            match = { when = when },
            layout = { columns = { { "track", "thumb" }, { { types = { "Search" } } } } },
        }
    end
    return {
        providers = { cursor = false, diagnostic = false, search = { backend = "sync" }, marks = false },
        scrollbar = {
            throttle_ms = 0,
            layout = { columns = { { "track", "thumb", "marks" } } },
            profiles = { profile(%s) },
        },
    }
]]

T["when profiles"]["searching switches the layout with the search"] = function()
    local child = plugin_child(string.format(TWO_COLUMN_PROFILE, "recipes.when.searching()"))
    expect.equality(child.lua_get([[_G.widths("scrollbar", 1, 1)]]), { left = 1, right = 1 })

    helpers.accept_search(child, "/", "line 5")
    expect.equality(child.lua_get([[_G.widths("scrollbar", 2, 2)]]), { left = 2, right = 2 })

    child.type_keys(10, ":nohlsearch", "<CR>")
    expect.equality(child.lua_get([[_G.widths("scrollbar", 1, 1)]]), { left = 1, right = 1 })
end

T["when profiles"]["diff switches the layout of a window in diff mode"] = function()
    local child = plugin_child(string.format(TWO_COLUMN_PROFILE, "recipes.when.diff()"))
    expect.equality(child.lua_get([[_G.widths("scrollbar", 1, 1)]]), { left = 1, right = 1 })

    child.cmd("diffthis")
    expect.equality(child.lua_get([[_G.widths("scrollbar", 1, 2)]]), { left = 1, right = 2 })

    child.cmd("diffoff")
    expect.equality(child.lua_get([[_G.widths("scrollbar", 1, 1)]]), { left = 1, right = 1 })
end

T["when profiles"]["negate(active()) selects the windows without focus in both renderers"] = function()
    local child = plugin_child([[
        local when = require("scrollbar.recipes").when
        local inactive = when.negate(when.active())
        return {
            providers = { cursor = false, diagnostic = false, search = false, marks = false, treesitter = false },
            scrollbar = {
                throttle_ms = 0,
                layout = { columns = { { "track", "thumb", "marks" } } },
                profiles = {
                    {
                        match = { when = inactive },
                        layout = { columns = { { "track", "thumb" }, { "track", "marks" } } },
                    },
                },
            },
            minimap = {
                enabled = true,
                backend = "sync",
                throttle_ms = 0,
                hide_on_cursor = false,
                mouse = false,
                width = 6,
                profiles = { { match = { when = inactive }, width = 4 } },
            },
        }
    ]])

    -- The right split has focus.
    expect.equality(child.lua_get([[_G.widths("scrollbar", 2, 1)]]), { left = 2, right = 1 })
    expect.equality(child.lua_get([[_G.widths("minimap", 4, 6)]]), { left = 4, right = 6 })

    child.cmd("wincmd w")
    expect.equality(child.lua_get([[_G.widths("scrollbar", 1, 2)]]), { left = 1, right = 2 })
    expect.equality(child.lua_get([[_G.widths("minimap", 6, 4)]]), { left = 6, right = 4 })
end

T["when profiles"]["active in floats.when does not loop"] = function()
    local child = plugin_child([[
        local when = require("scrollbar.recipes").when
        return {
            providers = { cursor = false, diagnostic = false, search = false, marks = false },
            scrollbar = {
                throttle_ms = 0,
                floats = { when = when.active() },
                profiles = { { match = { when = when.negate(when.active()) }, thumb = { blend = 10 } } },
            },
        }
    ]])

    local result = child.lua_get([[(function()
        local float = vim.api.nvim_open_win(vim.api.nvim_get_current_buf(), true, {
            relative = "editor", row = 2, col = 2, width = 30, height = 10,
        })
        require("scrollbar.scheduler").flush()
        return { current = vim.api.nvim_get_current_win() == float, errors = vim.v.errmsg }
    end)()]])

    expect.equality(result, { current = true, errors = "" })
end

T["when profiles"]["the when contexts name the renderer"] = function()
    local child = plugin_child([[
        _G.renderers = {}
        local function record(key)
            return function(context)
                _G.renderers[key] = context.renderer
                return false
            end
        end
        return {
            providers = { cursor = false, diagnostic = false, search = false, marks = false, treesitter = false },
            scrollbar = {
                throttle_ms = 0,
                floats = { when = record("floats") },
                profiles = { { match = { when = record("scrollbar") }, thumb = { blend = 10 } } },
            },
            minimap = {
                enabled = true,
                backend = "sync",
                throttle_ms = 0,
                profiles = { { match = { when = record("minimap") }, width = 4 } },
            },
        }
    ]])

    local renderers = child.lua_get([[(function()
        vim.api.nvim_open_win(vim.api.nvim_get_current_buf(), true, {
            relative = "editor", row = 2, col = 2, width = 30, height = 10,
        })
        _G.widths("scrollbar", 1, 1)
        _G.width("minimap", _G.left)
        return _G.renderers
    end)()]])

    expect.equality(renderers, { floats = "scrollbar", scrollbar = "scrollbar", minimap = "minimap" })
end

return T
