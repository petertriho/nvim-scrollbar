local MiniTest = MiniTest
local expect = MiniTest.expect
local provider_helpers = require("tests.providers.helpers")

local function free_lists()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        vim.fn.setloclist(winid, {}, "f")
    end
end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            provider_helpers.unload_modules({ "scrollbar.providers.loclist" })
            free_lists()
        end,
        post_case = function()
            provider_helpers.dispose_providers()
            free_lists()
        end,
    },
})

---@param options? any The value of `providers.loclist`
local function setup_provider(options)
    return provider_helpers.setup_list_provider("loclist", options)
end

local new_buffer = provider_helpers.new_buffer

local show_buffer = provider_helpers.show_buffer

local function marks(winid)
    return require("scrollbar.shared.store").get_window(winid).loclist
end

local function safe_state()
    vim.api.nvim_exec_autocmds("SafeState", {})
end

local function await_marks(winid, expected)
    return vim.wait(1000, function()
        return vim.deep_equal(marks(winid), expected)
    end, 10)
end

local function lines(...)
    local result = {}
    for _, line in ipairs({ ... }) do
        result[#result + 1] = { line = line, type = "Loclist" }
    end
    return result
end

T["each window shows the entries of its own list for its buffer"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    local other = new_buffer({ "x", "y" })
    local first = show_buffer(bufnr)
    local second = show_buffer(bufnr)

    vim.fn.setloclist(first, {
        { bufnr = bufnr, lnum = 4 },
        { bufnr = bufnr, lnum = 1 },
        { bufnr = bufnr, lnum = 4 },
        { bufnr = other, lnum = 2 },
        { bufnr = bufnr, lnum = 0 },
        { bufnr = bufnr, lnum = 2, valid = false },
        { text = "no buffer" },
    })
    vim.fn.setloclist(second, { { bufnr = bufnr, lnum = 2 } })
    expect.equality(marks(first), nil)
    safe_state()

    expect.equality(marks(first), lines(0, 3, 3))
    expect.equality(marks(second), lines(1))
end

T["maps the entry types with the types option"] = function()
    setup_provider({ types = { E = "Error", W = false, N = "Hint" } })
    local bufnr = new_buffer({ "1", "2", "3", "4", "5", "6" })
    local winid = show_buffer(bufnr)

    vim.fn.setloclist(winid, {
        { bufnr = bufnr, lnum = 1, type = "E" },
        { bufnr = bufnr, lnum = 2, type = "e" },
        { bufnr = bufnr, lnum = 3, type = "W" },
        { bufnr = bufnr, lnum = 4, type = "I" },
        { bufnr = bufnr, lnum = 5, type = "N" },
        { bufnr = bufnr, lnum = 6 },
    })
    safe_state()

    expect.equality(marks(winid), {
        { line = 0, type = "Error" },
        { line = 1, type = "Error" },
        { line = 3, type = "Loclist" },
        { line = 4, type = "Hint" },
        { line = 5, type = "Loclist" },
    })
end

T["a location list command publishes through QuickFixCmdPost"] = function()
    setup_provider()
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "alpha", "beta", "alpha beta" }, path)
    MiniTest.finally(function()
        vim.fn.delete(path)
    end)
    local bufnr = vim.fn.bufadd(path)
    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)
    vim.fn.bufload(bufnr)
    local winid = show_buffer(bufnr)

    vim.cmd("silent lvimgrep /alpha/j %")
    expect.equality(marks(winid), lines(0, 2))

    vim.cmd("lexpr []")
    expect.equality(marks(winid), nil)
end

T["SafeState publishes the lists of lolder and lnewer"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b", "c" })
    local winid = show_buffer(bufnr)

    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 1 } })
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 3 } })
    safe_state()
    expect.equality(marks(winid), lines(2))

    vim.cmd("silent lolder")
    safe_state()
    expect.equality(marks(winid), lines(0))

    vim.cmd("silent lnewer")
    safe_state()
    expect.equality(marks(winid), lines(2))
end

T["the list window gets no marks"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b" })
    local winid = show_buffer(bufnr)
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 2 } })
    safe_state()

    vim.cmd("lopen")
    local list_window = vim.api.nvim_get_current_win()
    MiniTest.finally(function()
        if vim.api.nvim_win_is_valid(list_window) then
            vim.api.nvim_win_close(list_window, true)
        end
    end)
    safe_state()

    expect.equality(vim.bo[vim.api.nvim_win_get_buf(list_window)].buftype, "quickfix")
    expect.equality(marks(list_window), nil)
    expect.equality(marks(winid), lines(1))
end

T["moves the marks when lines above the entries are inserted or deleted"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    local winid = show_buffer(bufnr)
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 2 }, { bufnr = bufnr, lnum = 4 } })
    safe_state()
    expect.equality(marks(winid), lines(1, 3))

    -- The provider reads the list again after the line count stays the same
    -- for the delay.
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new", "lines" })
    safe_state()
    expect.equality(marks(winid), lines(1, 3))
    expect.equality(await_marks(winid, lines(3, 5)), true)

    vim.api.nvim_buf_set_lines(bufnr, 0, 3, false, {})
    safe_state()
    expect.equality(await_marks(winid, lines(0, 2)), true)
end

T["entering a window does not read an unchanged list again"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b" })
    local winid = show_buffer(bufnr)
    local other = show_buffer(new_buffer({ "x" }))
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 2 } })
    safe_state()
    expect.equality(marks(winid), lines(1))

    local reads = 0
    local getloclist = vim.fn.getloclist
    rawset(vim.fn, "getloclist", function(win, what)
        if type(what) == "table" and what.items ~= nil then
            reads = reads + 1
        end
        return getloclist(win, what)
    end)
    MiniTest.finally(function()
        rawset(vim.fn, "getloclist", getloclist)
    end)

    vim.api.nvim_set_current_win(winid)
    vim.api.nvim_set_current_win(other)
    vim.api.nvim_set_current_win(winid)
    expect.equality(reads, 0)
    expect.equality(marks(winid), lines(1))
end

T["a window that changes its buffer shows the entries of the new buffer"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b", "c" })
    local other = new_buffer({ "x", "y", "z" })
    local winid = show_buffer(bufnr)
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 1 }, { bufnr = other, lnum = 3 } })
    safe_state()
    expect.equality(marks(winid), lines(0))

    vim.api.nvim_win_set_buf(winid, other)
    expect.equality(marks(winid), lines(2))

    vim.api.nvim_win_set_buf(winid, bufnr)
    expect.equality(marks(winid), lines(0))
end

T["a manual refresh catches an edit that keeps the line count"] = function()
    local providers = setup_provider()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    local winid = show_buffer(bufnr)
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 1 } })
    safe_state()
    expect.equality(marks(winid), lines(0))

    vim.cmd("1move 3")
    safe_state()
    -- SafeState checks only the line count, which `:move` keeps.
    expect.equality(marks(winid), lines(0))

    providers.refresh_window(winid)
    expect.equality(marks(winid), lines(2))
end

T["a closed window leaves no marks and no state"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b" })
    local winid = show_buffer(bufnr)
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 2 } })
    safe_state()
    expect.equality(marks(winid), lines(1))

    vim.api.nvim_win_close(winid, true)
    expect.no_error(safe_state)
    expect.equality(require("scrollbar.shared.store").get_window(winid), {})
end

T["dispose clears the marks"] = function()
    local providers = setup_provider()
    local bufnr = new_buffer({ "a", "b" })
    local winid = show_buffer(bufnr)
    vim.fn.setloclist(winid, { { bufnr = bufnr, lnum = 2 } })
    safe_state()
    expect.equality(marks(winid), lines(1))

    providers.dispose()
    expect.equality(marks(winid), nil)
end

return T
