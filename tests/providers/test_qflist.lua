local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect
local provider_helpers = require("tests.providers.helpers")

local function free_lists()
    vim.fn.setqflist({}, "f")
end

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            provider_helpers.unload_modules({ "scrollbar.providers.qflist" })
            free_lists()
        end,
        post_case = function()
            provider_helpers.dispose_providers()
            free_lists()
        end,
    },
})

---@param options? any The value of `providers.qflist`
local function setup_provider(options)
    return provider_helpers.setup_list_provider("qflist", options)
end

local new_buffer = provider_helpers.new_buffer

local function new_file(lines)
    local path = vim.fn.tempname() .. ".txt"
    vim.fn.writefile(lines, path)
    MiniTest.finally(function()
        local bufnr = vim.fn.bufnr(path)
        if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
        vim.fn.delete(path)
    end)
    return path
end

local show_buffer = provider_helpers.show_buffer

local function marks(bufnr)
    return require("scrollbar.shared.store").get(bufnr).qflist
end

local function safe_state()
    vim.api.nvim_exec_autocmds("SafeState", {})
end

local function await_marks(bufnr, expected)
    return vim.wait(1000, function()
        return vim.deep_equal(marks(bufnr), expected)
    end, 10)
end

local function lines(...)
    local result = {}
    for _, line in ipairs({ ... }) do
        result[#result + 1] = { line = line, type = "Qflist" }
    end
    return result
end

T["marks the valid entries of the current list in each buffer"] = function()
    setup_provider()
    local first = new_buffer({ "a", "b", "c", "d" })
    local second = new_buffer({ "x", "y" })

    vim.fn.setqflist({
        { bufnr = first, lnum = 3, text = "three" },
        { bufnr = first, lnum = 1, text = "one" },
        { bufnr = first, lnum = 3, text = "again" },
        { bufnr = second, lnum = 2, text = "two" },
        { bufnr = first, lnum = 0, text = "no line" },
        { bufnr = first, lnum = 2, text = "not valid", valid = false },
        { text = "no buffer" },
    })
    safe_state()

    -- Two entries on one line give two marks, so the row shows the density.
    expect.equality(marks(first), lines(0, 2, 2))
    expect.equality(marks(second), lines(1))
end

T["maps the entry types with the types option"] = function()
    setup_provider({ types = { E = "Error", W = false, N = "Hint" } })
    local bufnr = new_buffer({ "1", "2", "3", "4", "5", "6" })

    vim.fn.setqflist({
        { bufnr = bufnr, lnum = 1, type = "E" },
        { bufnr = bufnr, lnum = 2, type = "e" },
        { bufnr = bufnr, lnum = 3, type = "W" },
        { bufnr = bufnr, lnum = 4, type = "I" },
        { bufnr = bufnr, lnum = 5, type = "N" },
        { bufnr = bufnr, lnum = 6 },
    })
    safe_state()

    expect.equality(marks(bufnr), {
        { line = 0, type = "Error" },
        { line = 1, type = "Error" },
        { line = 3, type = "Qflist" },
        { line = 4, type = "Hint" },
        { line = 5, type = "Qflist" },
    })
end

T["SafeState publishes the lists of setqflist, colder, and cnewer"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b", "c" })

    vim.fn.setqflist({ { bufnr = bufnr, lnum = 1 } })
    expect.equality(marks(bufnr), nil)
    safe_state()
    expect.equality(marks(bufnr), lines(0))

    vim.fn.setqflist({ { bufnr = bufnr, lnum = 3 } })
    safe_state()
    expect.equality(marks(bufnr), lines(2))

    vim.cmd("silent colder")
    safe_state()
    expect.equality(marks(bufnr), lines(0))

    vim.cmd("silent cnewer")
    safe_state()
    expect.equality(marks(bufnr), lines(2))

    -- A changed entry of the current list changes its changedtick.
    vim.fn.setqflist({}, "a", { items = { { bufnr = bufnr, lnum = 2 } } })
    safe_state()
    expect.equality(marks(bufnr), lines(1, 2))
end

T["a quickfix command publishes through QuickFixCmdPost"] = function()
    setup_provider()
    local path = new_file({ "alpha", "beta", "alpha beta" })
    vim.cmd.edit(vim.fn.fnameescape(path))
    local bufnr = vim.api.nvim_get_current_buf()

    vim.cmd("silent vimgrep /alpha/j %")
    expect.equality(marks(bufnr), lines(0, 2))

    vim.cmd("cexpr []")
    expect.equality(marks(bufnr), nil)
end

T["moves the marks when lines above the entries are inserted or deleted"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    vim.fn.setqflist({ { bufnr = bufnr, lnum = 2 }, { bufnr = bufnr, lnum = 4 } })
    safe_state()
    expect.equality(marks(bufnr), lines(1, 3))

    -- The provider reads the list again after the line count stays the same
    -- for the delay.
    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new", "lines" })
    safe_state()
    expect.equality(marks(bufnr), lines(1, 3))
    expect.equality(await_marks(bufnr, lines(3, 5)), true)

    vim.api.nvim_buf_set_lines(bufnr, 0, 3, false, {})
    safe_state()
    expect.equality(await_marks(bufnr, lines(0, 2)), true)
end

T["a change of the list during the delay updates at once"] = function()
    setup_provider()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    vim.fn.setqflist({ { bufnr = bufnr, lnum = 2 } })
    safe_state()

    vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "new" })
    safe_state()
    vim.fn.setqflist({ { bufnr = bufnr, lnum = 1 } })
    safe_state()
    expect.equality(marks(bufnr), lines(0))
    -- The pending timer finds nothing to collect.
    vim.wait(200)
    expect.equality(marks(bufnr), lines(0))
end

T["a manual refresh catches an edit that keeps the line count"] = function()
    local providers = setup_provider()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    show_buffer(bufnr)
    vim.fn.setqflist({ { bufnr = bufnr, lnum = 1 } })
    safe_state()
    expect.equality(marks(bufnr), lines(0))

    vim.cmd("1move 3")
    safe_state()
    -- SafeState checks only the line count, which `:move` keeps.
    expect.equality(marks(bufnr), lines(0))

    providers.refresh(bufnr)
    expect.equality(marks(bufnr), lines(2))
end

T["publishes a listed buffer when it loads"] = function()
    setup_provider()
    local path = new_file({ "one", "two", "three" })
    local bufnr = vim.fn.bufadd(path)
    vim.fn.setqflist({ { bufnr = bufnr, lnum = 2 } })
    safe_state()
    expect.equality(vim.api.nvim_buf_is_loaded(bufnr), false)
    expect.equality(marks(bufnr), nil)

    show_buffer(bufnr)
    expect.equality(marks(bufnr), lines(1))
end

T["dispose clears the marks"] = function()
    local providers = setup_provider()
    local bufnr = new_buffer({ "a", "b" })
    vim.fn.setqflist({ { bufnr = bufnr, lnum = 2 } })
    safe_state()
    expect.equality(marks(bufnr), lines(1))

    providers.dispose()
    expect.equality(marks(bufnr), nil)
end

T["publishes for a minimap-only setup"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)

    local result = child.lua_func(function()
        require("scrollbar").setup({
            minimap = { enabled = true },
            providers = { qflist = { scrollbar = false } },
        })
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "a", "b", "c" })
        vim.fn.setqflist({ { bufnr = bufnr, lnum = 2 } })
        vim.api.nvim_exec_autocmds("SafeState", {})
        return {
            consumers = require("scrollbar.config").get_provider_plan().qflist.consumers,
            marks = require("scrollbar.shared.store").get(bufnr).qflist,
            spec = require("scrollbar.config").get_minimap().marks.Qflist,
        }
    end)

    expect.equality(result.consumers, { scrollbar = false, minimap = true })
    expect.equality(result.marks, { { line = 1, type = "Qflist" } })
    expect.equality(result.spec, { priority = 6, highlight = "QuickFixLine", group = "ScrollbarMinimapQflist" })
end

return T
