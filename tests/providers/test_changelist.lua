local MiniTest = MiniTest
local expect = MiniTest.expect
local provider_helpers = require("tests.providers.helpers")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            provider_helpers.unload_modules({
                "scrollbar.providers.changelist",
                "scrollbar.providers.position_targets",
            })
        end,
        post_case = function()
            provider_helpers.dispose_providers()
        end,
    },
})

local press = provider_helpers.press

local function setup_provider()
    return provider_helpers.setup_list_provider("changelist")
end

--- A buffer of 100 lines in a new current window. `nvim_buf_set_lines`
--- gives the buffer a first change list entry on line 1. A scratch buffer
--- has no undo history, so each edit would only move that entry.
---@param filetype? string
---@return integer winid
---@return integer bufnr
local function show_new_buffer(filetype)
    local lines = {}
    for line = 1, 100 do
        lines[line] = "line " .. line
    end
    local bufnr = provider_helpers.new_buffer({}, filetype)
    vim.bo[bufnr].undolevels = 1000
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return provider_helpers.show_buffer(bufnr), bufnr
end

--- Delete one character on `line` of the current window. Each edit closes
--- its undo block, so each edit starts a change list entry, as a typed `x`
--- does.
---@param line integer
local function edit(line)
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    press("x")
    vim.cmd("let &g:undolevels = &g:undolevels")
end

local function marks(winid)
    return require("scrollbar.shared.store").get_window(winid).changelist
end

local function target(winid, mark_type)
    return provider_helpers.mark_line("changelist", winid, mark_type)
end

local function expect_goes_to(key, mark_type)
    provider_helpers.expect_key_goes_to_mark("changelist", key, mark_type)
end

T["after an edit, only the latest change is a target"] = function()
    setup_provider()
    local winid = show_new_buffer()
    edit(20)
    edit(60)
    vim.api.nvim_win_set_cursor(winid, { 90, 0 })
    press("j")
    expect.equality(marks(winid), { { line = 59, type = "ChangeOlder" } })

    expect_goes_to("g;", "ChangeOlder")
end

T["marks the targets of g; and g,"] = function()
    setup_provider()
    local winid = show_new_buffer()
    edit(20)
    edit(50)
    edit(80)

    expect_goes_to("g;", "ChangeOlder")
    expect_goes_to("g;", "ChangeOlder")
    expect.equality(marks(winid), {
        { line = 19, type = "ChangeOlder" },
        { line = 79, type = "ChangeNewer" },
    })
    expect_goes_to("g,", "ChangeNewer")
    expect_goes_to("g;", "ChangeOlder")
    expect_goes_to("g;", "ChangeOlder")
    expect.equality(marks(winid), {
        { line = 0, type = "ChangeOlder" },
        { line = 49, type = "ChangeNewer" },
    })
    expect_goes_to("g;", "ChangeOlder")
    -- The first entry has no older target.
    expect.equality(marks(winid), { { line = 19, type = "ChangeNewer" } })
end

T["shows no newer target at the last entry"] = function()
    setup_provider()
    local winid = show_new_buffer()
    edit(30)
    edit(70)
    expect_goes_to("g;", "ChangeOlder")
    expect.equality(vim.api.nvim_win_get_cursor(winid)[1], 70)
    expect.equality(target(winid, "ChangeNewer"), nil)

    local ok, err = pcall(function()
        vim.cmd("normal! g,")
    end)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match("E663"), nil)
end

T["an edit in one window updates the other windows of the buffer"] = function()
    setup_provider()
    local first, bufnr = show_new_buffer()
    local second = provider_helpers.show_buffer(bufnr)
    -- An edit moves the index of its window to the end of the list. An index
    -- at the end stays there when another window edits the buffer.
    edit(10)
    vim.api.nvim_set_current_win(first)
    edit(40)
    expect.equality(target(second, "ChangeOlder"), 40)
    edit(70)
    expect.equality(target(second, "ChangeOlder"), 70)
    expect.equality(vim.api.nvim_get_current_win(), first)

    vim.api.nvim_set_current_win(second)
    expect_goes_to("g;", "ChangeOlder")
end

T["each window keeps its own index"] = function()
    local providers = setup_provider()
    local first, bufnr = show_new_buffer()
    edit(30)
    edit(60)
    local second = provider_helpers.show_buffer(bufnr)
    edit(80)
    vim.api.nvim_set_current_win(first)
    expect_goes_to("g;", "ChangeOlder")
    expect_goes_to("g;", "ChangeOlder")
    expect.equality(marks(first), {
        { line = 29, type = "ChangeOlder" },
        { line = 79, type = "ChangeNewer" },
    })

    providers.refresh_window(second)
    expect.equality(marks(second), { { line = 79, type = "ChangeOlder" } })
    expect.equality(vim.api.nvim_get_current_win(), first)
    vim.api.nvim_set_current_win(second)
    expect_goes_to("g;", "ChangeOlder")
end

T["a window that starts to show the buffer follows its own index"] = function()
    setup_provider()
    local _, bufnr = show_new_buffer()
    edit(30)
    edit(60)
    -- The index of the new window starts at the first entry, so `g,` goes to
    -- the second entry.
    local second = provider_helpers.show_buffer(bufnr)
    expect.equality(marks(second), { { line = 29, type = "ChangeNewer" } })
    expect_goes_to("g,", "ChangeNewer")
end

T["Insert mode does not read the list, and InsertLeave does"] = function()
    local _, dispatch = provider_helpers.setup_with_dispatch("changelist")
    local winid, bufnr = show_new_buffer()
    local reads = provider_helpers.count_calls("getchangelist")

    assert(dispatch.cursor ~= nil and dispatch.text ~= nil, "the provider did not subscribe")
    vim.api.nvim_buf_set_lines(bufnr, 49, 50, false, { "typed" })
    dispatch.cursor({ event = "CursorMovedI", buf = bufnr })
    dispatch.text({ event = "TextChangedI", buf = bufnr })
    expect.equality(reads(), 0)

    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = bufnr })
    expect.equality(reads(), 1)
    expect.equality(target(winid, "ChangeOlder"), 50)

    -- Each edit can add an entry, so a Normal-mode edit reads the list also
    -- when the line count stays the same.
    dispatch.text({ event = "TextChanged", buf = bufnr })
    expect.equality(reads(), 2)
    dispatch.cursor({ event = "CursorMoved", buf = bufnr })
    expect.equality(reads(), 3)
end

T["an excluded buffer gets no marks"] = function()
    setup_provider()
    local winid = show_new_buffer("scrollbar-excluded")
    edit(30)
    expect.equality(marks(winid), nil)
end

T["dispose clears the marks"] = function()
    local providers = setup_provider()
    local winid = show_new_buffer()
    edit(30)
    expect.equality(target(winid, "ChangeOlder"), 30)

    providers.dispose()
    expect.equality(marks(winid), nil)
end

return T
