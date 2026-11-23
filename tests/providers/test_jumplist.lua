local MiniTest = MiniTest
local expect = MiniTest.expect
local provider_helpers = require("tests.providers.helpers")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            provider_helpers.unload_modules({
                "scrollbar.providers.jumplist",
                "scrollbar.providers.position_targets",
            })
        end,
        post_case = function()
            provider_helpers.dispose_providers()
        end,
    },
})

local press = provider_helpers.press

---@param options? any The value of `providers.jumplist`
local function setup_provider(options)
    return provider_helpers.setup_list_provider("jumplist", options)
end

local function numbered_lines(count)
    local result = {}
    for line = 1, count do
        result[line] = "line " .. line
    end
    return result
end

--- A buffer of 100 lines in a new current window with an empty jumplist. A
--- new split copies the jumplist of the previous window.
---@return integer winid
---@return integer bufnr
local function show_new_buffer()
    local bufnr = provider_helpers.new_buffer(numbered_lines(100))
    local winid = provider_helpers.show_buffer(bufnr)
    vim.cmd("clearjumps")
    return winid, bufnr
end

local function marks(winid)
    return require("scrollbar.shared.store").get_window(winid).jumplist
end

local function target(winid, mark_type)
    return provider_helpers.mark_line("jumplist", winid, mark_type)
end

local function expect_goes_to(key, mark_type)
    provider_helpers.expect_key_goes_to_mark("jumplist", key, mark_type)
end

T["marks the targets of <C-o> and <C-i>"] = function()
    setup_provider()
    local winid = show_new_buffer()
    press("20G")
    press("50G")
    press("80G")
    expect.equality(marks(winid), { { line = 49, type = "JumpOlder" } })

    expect_goes_to("<C-o>", "JumpOlder")
    expect.equality(marks(winid), {
        { line = 19, type = "JumpOlder" },
        { line = 79, type = "JumpNewer" },
    })
    expect_goes_to("<C-o>", "JumpOlder")
    expect_goes_to("<C-i>", "JumpNewer")
    expect_goes_to("<C-i>", "JumpNewer")
    expect.equality(target(winid, "JumpNewer"), nil)
end

T["shows no newer target at the end of the list"] = function()
    setup_provider()
    local winid = show_new_buffer()
    press("30G")
    press("60G")
    expect.equality(target(winid, "JumpOlder"), 30)
    expect.equality(target(winid, "JumpNewer"), nil)

    -- <C-i> at the end of the list does not move the cursor.
    press("1<C-i>")
    expect.equality(vim.api.nvim_win_get_cursor(winid)[1], 60)
end

T["shows no mark when the target is in another buffer"] = function()
    setup_provider()
    local winid, bufnr = show_new_buffer()
    local other = provider_helpers.new_buffer(numbered_lines(10))
    press("40G")
    vim.cmd("buffer " .. other)
    press("5G")
    expect.equality(marks(winid), { { line = 0, type = "JumpOlder" } })

    expect_goes_to("<C-o>", "JumpOlder")
    -- The next target is line 40 of the first buffer.
    expect.equality(marks(winid), { { line = 4, type = "JumpNewer" } })
    press("<C-o>")
    expect.equality(vim.api.nvim_win_get_buf(winid), bufnr)
    expect.equality(vim.api.nvim_win_get_cursor(winid)[1], 40)
end

T["each window shows the targets of its own jumplist"] = function()
    setup_provider()
    local first, bufnr = show_new_buffer()
    press("10G")
    press("20G")
    local second = provider_helpers.show_buffer(bufnr)
    vim.cmd("clearjumps")
    press("70G")
    press("90G")

    expect.equality(target(first, "JumpOlder"), 10)
    expect.equality(target(second, "JumpOlder"), 70)
end

T["a line delete above the targets moves the marks of every window"] = function()
    setup_provider()
    local first, bufnr = show_new_buffer()
    press("50G")
    press("60G")
    local second = provider_helpers.show_buffer(bufnr)
    vim.cmd("clearjumps")
    press("30G")
    press("40G")
    vim.api.nvim_set_current_win(first)
    expect.equality(target(first, "JumpOlder"), 50)
    expect.equality(target(second, "JumpOlder"), 30)

    vim.api.nvim_buf_set_lines(bufnr, 1, 4, false, {})
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
    expect.equality(target(first, "JumpOlder"), 47)
    expect.equality(target(second, "JumpOlder"), 27)
    expect.equality(vim.api.nvim_get_current_win(), first)
end

T["follows the keys with jumpoptions=stack"] = function()
    local jumpoptions = vim.o.jumpoptions
    vim.o.jumpoptions = "stack"
    MiniTest.finally(function()
        vim.o.jumpoptions = jumpoptions
    end)
    setup_provider()
    local winid = show_new_buffer()
    press("10G")
    press("20G")
    press("30G")
    press("40G")

    expect_goes_to("<C-o>", "JumpOlder")
    expect_goes_to("<C-o>", "JumpOlder")
    expect.equality(target(winid, "JumpNewer"), 30)
    -- A jump from the middle of the list drops the newer entries.
    press("35G")
    expect.equality(target(winid, "JumpNewer"), nil)
    expect_goes_to("<C-o>", "JumpOlder")
end

T["Insert mode does not read the list, and InsertLeave does"] = function()
    local _, dispatch = provider_helpers.setup_with_dispatch("jumplist")
    local winid, bufnr = show_new_buffer()
    local reads = provider_helpers.count_calls("getjumplist")
    press("50G")
    local before = reads()

    assert(dispatch.cursor ~= nil and dispatch.text ~= nil, "the provider did not subscribe")
    dispatch.cursor({ event = "CursorMovedI", buf = bufnr })
    dispatch.text({ event = "TextChangedI", buf = bufnr })
    expect.equality(reads(), before)
    -- An edit that keeps the line count does not move the jumplist entries.
    dispatch.text({ event = "TextChanged", buf = bufnr })
    expect.equality(reads(), before)

    dispatch.cursor({ event = "CursorMoved", buf = bufnr })
    expect.equality(reads(), before + 1)
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = bufnr })
    expect.equality(reads(), before + 2)
    expect.equality(target(winid, "JumpOlder"), 1)
end

T["two reads in a row give the same targets"] = function()
    local providers = setup_provider()
    local winid = show_new_buffer()
    press("25G")
    press("75G")
    -- `m'` adds the cursor line to the end of the list. A read of the list
    -- removes this entry again, as <C-o> does.
    vim.cmd("normal! m'")
    providers.refresh_window(winid)
    local first = marks(winid)
    providers.refresh_window(winid)
    expect.equality(marks(winid), first)
    expect.equality(first, { { line = 24, type = "JumpOlder" } })
    expect_goes_to("<C-o>", "JumpOlder")
end

T["a manual refresh reads the list at once"] = function()
    local providers = setup_provider()
    local winid = show_new_buffer()
    press("30G")
    press("60G")
    expect.equality(target(winid, "JumpOlder"), 30)

    vim.cmd("clearjumps")
    expect.equality(target(winid, "JumpOlder"), 30)
    providers.refresh_window(winid)
    expect.equality(marks(winid), nil)
end

T["a window that is not current reads its own list"] = function()
    local providers = setup_provider()
    local first, bufnr = show_new_buffer()
    press("15G")
    press("45G")
    local second = provider_helpers.show_buffer(bufnr)
    vim.cmd("clearjumps")
    providers.refresh_window(first)
    expect.equality(target(first, "JumpOlder"), 15)
    expect.equality(vim.api.nvim_get_current_win(), second)
end

T["an excluded buffer gets no marks"] = function()
    setup_provider()
    local bufnr = provider_helpers.new_buffer(numbered_lines(100), "scrollbar-excluded")
    local winid = provider_helpers.show_buffer(bufnr)
    vim.cmd("clearjumps")
    press("30G")
    press("60G")
    expect.equality(marks(winid), nil)
end

T["dispose clears the marks"] = function()
    local providers = setup_provider()
    local winid = show_new_buffer()
    press("30G")
    press("60G")
    expect.equality(target(winid, "JumpOlder"), 30)

    providers.dispose()
    expect.equality(marks(winid), nil)
end

return T
