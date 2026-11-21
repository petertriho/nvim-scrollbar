local MiniTest = MiniTest
local navigate = require("tests.navigate.helpers")
local expect = MiniTest.expect

-- The pinned plugins of `make test-deps`. Only the children of this file and
-- of `test_pickers.lua` add them to their runtimepath.
local DEPS = { "deps/snacks.nvim", "deps/telescope.nvim", "deps/plenary.nvim" }

local MARKS = {
    { line = 20, type = "Error" },
    { line = 20, type = "GitChange" },
    { line = 60, type = "Warn" },
    { line = 100, type = "Hint" },
    { line = 150, type = "Error" },
}

local T = MiniTest.new_set()

--- A child with the pinned pickers, the marks of MARKS, and a file buffer
--- with the line text "  text <n>". Line 61 has an unsaved edit.
---@param top? table Top-level overrides of the configuration
---@return table child
---@return { source_win: integer, source_buf: integer }
local function new_child(top)
    for _, path in ipairs(DEPS) do
        if vim.fn.isdirectory(path) == 0 then
            MiniTest.skip(path .. " is missing. Run `make test-deps`.")
        end
    end
    local child = navigate.new_child()
    child.o.lines = 40
    child.o.columns = 120
    child.lua(
        [[
        for _, path in ipairs(...) do
            vim.opt.runtimepath:prepend(vim.fn.fnamemodify(path, ":p"))
        end
        -- A write of the buffer clears the marks, so the file exists first.
        _G.lines = {}
        for index = 1, 200 do
            _G.lines[index] = "  text " .. index
        end
        local file = vim.fn.tempname() .. ".txt"
        vim.fn.writefile(_G.lines, file)
        vim.cmd("edit " .. vim.fn.fnameescape(file))
    ]],
        { DEPS }
    )
    local result = navigate.setup(child, { marks = MARKS, full = true, config = navigate.config(top) })
    child.lua([[
        _G.notes = {}
        vim.notify = function(message, level)
            table.insert(_G.notes, { message, level })
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, _G.lines)
        vim.api.nvim_buf_set_lines(0, 60, 61, false, { "  unsaved 61" })
        require("snacks").setup({ picker = { enabled = true } })
        require("telescope").setup({})
    ]])
    return child, result
end

---@param child table
---@param expression string Lua expression that the child evaluates
local function wait_for(child, expression)
    local deadline = vim.uv.hrtime() + 5e9
    repeat
        if child.lua_get(expression) == true then
            return
        end
        vim.uv.sleep(20)
    until vim.uv.hrtime() > deadline
    error("timeout: " .. expression)
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

local SNACKS = "Snacks.picker.get()[1]"

--- Open the snacks glance picker and wait until the list selects `cursor`.
local function open_snacks(child, count, cursor)
    child.lua([[require("scrollbar").glance({ picker = "snacks" })]])
    wait_for(
        child,
        string.format(
            "(function() local p = %s; return p ~= nil and p.list:count() == %d and p.list.cursor == %d end)()",
            SNACKS,
            count,
            cursor
        )
    )
end

local function snacks_rows(child)
    return child.lua(string.format(
        [[
        local picker = %s
        local rows = {}
        for index, line in ipairs(vim.api.nvim_buf_get_lines(picker.list.win.buf, 0, -1, false)) do
            if line ~= "" then
                rows[index] = line
            end
        end
        return rows
    ]],
        SNACKS
    ))
end

local SNACKS_CLOSED = "#Snacks.picker.get() == 0"

T["snacks"] = MiniTest.new_set()

T["snacks"]["shows the rows in list order, selects ctx.selected, and previews the source buffer"] = function()
    local child, result = new_child()
    child.api.nvim_win_set_cursor(0, { 50, 0 })
    open_snacks(child, 4, 2)
    expect.equality(snacks_rows(child), {
        " -  21  text 21",
        " -  61  unsaved 61",
        " - 101  text 101",
        " - 151  text 151",
    })
    local preview = child.lua(string.format(
        [[
        local win = %s.preview.win.win
        return { buf = vim.api.nvim_win_get_buf(win), cursor = vim.api.nvim_win_get_cursor(win) }
    ]],
        SNACKS
    ))
    expect.equality(preview, { buf = result.source_buf, cursor = { 61, 0 } })
    child.lua(SNACKS .. ":close()")
    wait_for(child, SNACKS_CLOSED)
end

T["snacks"]["type mode shows the type column"] = function()
    local child = new_child({ glance = { entries = "type" } })
    open_snacks(child, 5, 1)
    expect.equality(snacks_rows(child), {
        " Error      -  21  text 21",
        " Error      - 151  text 151",
        " Warn       -  61  unsaved 61",
        " Hint       - 101  text 101",
        " GitChange  ┃  21  text 21",
    })
end

T["snacks"]["<CR> jumps in the source window and adds a jumplist entry"] = function()
    local child, result = new_child()
    child.api.nvim_win_set_cursor(0, { 5, 0 })
    open_snacks(child, 4, 1)
    child.lua(SNACKS .. ".list:view(3)")
    child.type_keys("<CR>")
    wait_for(child, SNACKS_CLOSED .. " and vim.api.nvim_win_get_cursor(0)[1] == 101")
    expect.equality(child.api.nvim_get_current_win(), result.source_win)
    expect.equality(child.api.nvim_get_mode().mode, "n")
    expect.equality(child.api.nvim_win_get_cursor(0), { 101, 0 })
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0), { 5, 0 })
end

T["snacks"]["<C-s> and <C-v> move in a new window"] = function()
    local child, result = new_child()
    for _, case in ipairs({ { key = "<C-s>", layout = "col" }, { key = "<C-v>", layout = "row" } }) do
        open_snacks(child, 4, 1)
        child.lua(SNACKS .. ".list:view(2)")
        child.type_keys(case.key)
        wait_for(child, string.format("%s and vim.fn.winlayout()[1] == %q", SNACKS_CLOSED, case.layout))
        local win = child.api.nvim_get_current_win()
        expect.no_equality(win, result.source_win)
        expect.equality(child.api.nvim_win_get_cursor(win), { 61, 0 })
        expect.equality(child.fn.winlayout()[1], case.layout)
        expect.equality(child.api.nvim_win_get_cursor(result.source_win), { 1, 0 })
        child.cmd("close")
    end
end

T["snacks"]["<C-q> writes the glance quickfix list"] = function()
    local child, result = new_child()
    open_snacks(child, 4, 1)
    child.type_keys("<C-q>")
    wait_for(child, SNACKS_CLOSED .. " and vim.bo.buftype == 'quickfix'")
    local buf = result.source_buf
    expect.equality(quickfix_list(child), {
        title = "Scrollbar glance",
        items = {
            { buf, 21, "Error, GitChange: text 21" },
            { buf, 61, "Warn: unsaved 61" },
            { buf, 101, "Hint: text 101" },
            { buf, 151, "Error: text 151" },
        },
    })
end

T["snacks"]["a wrapped adapter takes options"] = function()
    local child = new_child()
    child.lua([[
        require("scrollbar").glance({
            picker = function(ctx)
                require("scrollbar.glance").snacks(ctx, { title = "Marks", layout = { preset = "ivy" } })
            end,
        })
    ]])
    wait_for(child, string.format("%s ~= nil and %s.list:count() == 4", SNACKS, SNACKS))
    expect.equality(child.lua_get(SNACKS .. ".opts.title"), "Marks")
    expect.equality(child.lua_get(SNACKS .. ".resolved_layout.preset ~= nil"), true)
end

local TELESCOPE_PICKER = [[(function()
    local state = require("telescope.state")
    local prompt = state.get_existing_prompt_bufnrs()[1]
    return prompt and state.get_status(prompt).picker or nil
end)()]]

local TELESCOPE_PROMPT = [[require("telescope.state").get_existing_prompt_bufnrs()[1] ]]

local TELESCOPE_CLOSED = TELESCOPE_PROMPT .. " == nil"

--- Open the Telescope glance picker and wait until it selects the item of
--- line `lnum` and the preview shows it.
local function open_telescope(child, count, lnum)
    child.lua([[require("scrollbar").glance({ picker = "telescope" })]])
    wait_for(
        child,
        string.format(
            [[(function()
                local picker = %s
                if picker == nil or picker.manager == nil or picker.manager:num_results() ~= %d then
                    return false
                end
                local entry = require("telescope.actions.state").get_selected_entry()
                if entry == nil or entry.value.lnum ~= %d or picker.preview_win == nil then
                    return false
                end
                return vim.api.nvim_win_get_cursor(picker.preview_win)[1] == %d
            end)()]],
            TELESCOPE_PICKER,
            count,
            lnum,
            lnum
        )
    )
end

---@param action string
local function telescope_action(child, action)
    child.lua_func(function(name, prompt_expression)
        local prompt = loadstring("return " .. prompt_expression)()
        require("telescope.actions")[name](prompt)
    end, action, TELESCOPE_PROMPT)
end

--- Wait until the results buffer of Telescope shows `expected`, without the
--- empty lines, and return the last rows. Telescope runs more than one pass
--- over the entries. A pass can leave stale rows above the entries until it
--- completes, for a moment after the selection is ready.
---@param expected string[]
---@return string[]
local function telescope_rows(child, expected)
    local source = string.format(
        [[
        local picker = %s
        return vim.tbl_filter(function(line)
            return line ~= ""
        end, vim.api.nvim_buf_get_lines(picker.results_bufnr, 0, -1, false))
    ]],
        TELESCOPE_PICKER
    )
    local deadline = vim.uv.hrtime() + 5e9
    local rows
    repeat
        rows = child.lua(source)
        if vim.deep_equal(rows, expected) then
            break
        end
        vim.uv.sleep(20)
    until vim.uv.hrtime() > deadline
    return rows
end

T["telescope"] = MiniTest.new_set()

T["telescope"]["shows the rows in list order, selects ctx.selected, and previews unsaved edits"] = function()
    local child = new_child()
    child.api.nvim_win_set_cursor(0, { 50, 0 })
    open_telescope(child, 4, 61)
    -- The default sorting strategy puts the first row at the bottom.
    local rows = { "  - 151  text 151", "  - 101  text 101", "> -  61  unsaved 61", "  -  21  text 21" }
    expect.equality(telescope_rows(child, rows), rows)
    local view = child.lua(string.format(
        [[
        local picker = %s
        local lnums = {}
        for entry in picker.manager:iter() do
            lnums[#lnums + 1] = entry.value.lnum
        end
        local preview_buf = vim.api.nvim_win_get_buf(picker.preview_win)
        return {
            lnums = lnums,
            preview = vim.api.nvim_buf_get_lines(preview_buf, 59, 62, false),
        }
    ]],
        TELESCOPE_PICKER
    ))
    expect.equality(view, {
        lnums = { 21, 61, 101, 151 },
        preview = { "  text 60", "  unsaved 61", "  text 62" },
    })
    telescope_action(child, "close")
    wait_for(child, TELESCOPE_CLOSED)
end

T["telescope"]["type mode shows the type column"] = function()
    local child = new_child({ glance = { entries = "type" } })
    open_telescope(child, 5, 21)
    local rows = {
        "  GitChange  ┃  21  text 21",
        "  Hint       - 101  text 101",
        "  Warn       -  61  unsaved 61",
        "  Error      - 151  text 151",
        "> Error      -  21  text 21",
    }
    expect.equality(telescope_rows(child, rows), rows)
end

T["telescope"]["<CR> jumps in the source window and adds a jumplist entry"] = function()
    local child, result = new_child()
    child.api.nvim_win_set_cursor(0, { 120, 0 })
    open_telescope(child, 4, 151)
    child.type_keys("<CR>")
    wait_for(child, TELESCOPE_CLOSED .. " and vim.api.nvim_win_get_cursor(0)[1] == 151")
    expect.equality(child.api.nvim_get_current_win(), result.source_win)
    expect.equality(child.api.nvim_get_mode().mode, "n")
    expect.equality(child.api.nvim_win_get_cursor(0), { 151, 0 })
    child.type_keys("<C-o>")
    expect.equality(child.api.nvim_win_get_cursor(0), { 120, 0 })
end

T["telescope"]["<C-x> and <C-v> move in a new window"] = function()
    local child, result = new_child()
    child.api.nvim_win_set_cursor(0, { 50, 0 })
    for _, case in ipairs({ { key = "<C-x>", layout = "col" }, { key = "<C-v>", layout = "row" } }) do
        open_telescope(child, 4, 61)
        child.type_keys(case.key)
        wait_for(child, string.format("%s and vim.fn.winlayout()[1] == %q", TELESCOPE_CLOSED, case.layout))
        local win = child.api.nvim_get_current_win()
        expect.no_equality(win, result.source_win)
        expect.equality(child.api.nvim_win_get_cursor(win), { 61, 0 })
        expect.equality(child.api.nvim_win_get_cursor(result.source_win), { 50, 0 })
        child.cmd("close")
    end
end

T["telescope"]["<C-q> writes the glance quickfix list"] = function()
    local child, result = new_child()
    open_telescope(child, 4, 21)
    child.type_keys("<C-q>")
    wait_for(child, TELESCOPE_CLOSED .. " and vim.bo.buftype == 'quickfix'")
    local buf = result.source_buf
    expect.equality(quickfix_list(child), {
        title = "Scrollbar glance",
        items = {
            { buf, 21, "Error, GitChange: text 21" },
            { buf, 61, "Warn: unsaved 61" },
            { buf, 101, "Hint: text 101" },
            { buf, 151, "Error: text 151" },
        },
    })
end

return T
