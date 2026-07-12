local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, false)
    return child
end

local function instrument_scans(child)
    child.lua([[
        local state = { calls = {} }
        local searchpos = vim.fn.searchpos
        vim.fn.searchpos = function(pattern, flags, ...)
            table.insert(state.calls, { pattern = pattern, flags = flags })
            return searchpos(pattern, flags, ...)
        end
        package.loaded["scrollbar.test.search_scans"] = state
    ]])
end

local function scan_calls(child)
    return child.lua_get([[package.loaded["scrollbar.test.search_scans"].calls]])
end

T["accepted requests coalesce and retain previous marks while pending"] = function()
    local child = new_child()
    helpers.set_lines(child, { "start", "accepted", "first", "second", "latest" })
    helpers.accept_search(child, "/", "accepted")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    instrument_scans(child)

    local immediate = child.lua_get([[(function()
        for _, pattern in ipairs({ "first", "second", "latest" }) do
            vim.fn.setreg("/", pattern)
            vim.api.nvim_exec_autocmds("SafeState", { buffer = 0 })
        end
        local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
        return vim.tbl_map(function(mark)
            return mark.line
        end, marks)
    end)()]])

    expect.equality(immediate, { 1 })
    expect.equality(helpers.wait_for_mark_lines(child, { 4 }), true)
    expect.equality(scan_calls(child), {
        { pattern = "latest", flags = "Wnc" },
        { pattern = "latest", flags = "bWnc" },
    })
end

T["a newer generation queued during a scan rejects the stale result"] = function()
    local child = new_child()
    helpers.set_lines(child, { "start", "accepted", "stale", "latest" })
    helpers.accept_search(child, "/", "accepted")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)

    child.lua([[
        local state = { calls = {}, replaced = false }
        local searchpos = vim.fn.searchpos
        vim.fn.searchpos = function(pattern, flags, ...)
            table.insert(state.calls, { pattern = pattern, flags = flags })
            if pattern == "stale" and not state.replaced then
                state.replaced = true
                vim.fn.setreg("/", "latest")
                vim.api.nvim_exec_autocmds("SafeState", { buffer = 0 })
            end
            return searchpos(pattern, flags, ...)
        end
        package.loaded["scrollbar.test.search_scans"] = state
        vim.fn.setreg("/", "stale")
        vim.api.nvim_exec_autocmds("SafeState", { buffer = 0 })
    ]])

    expect.equality(helpers.wait_for_mark_lines(child, { 3 }), true)
    expect.equality(scan_calls(child), {
        { pattern = "stale", flags = "Wnc" },
        { pattern = "stale", flags = "bWnc" },
        { pattern = "latest", flags = "Wnc" },
        { pattern = "latest", flags = "bWnc" },
    })
end

T["repeated edits debounce to one scan and retain previous marks"] = function()
    local child = new_child()
    helpers.set_lines(child, { "start", "match", "none" })
    helpers.accept_search(child, "/", "match")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    instrument_scans(child)

    local immediate = child.lua_get([[(function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { "match" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
        vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { "match match" })
        vim.api.nvim_exec_autocmds("TextChangedI", { buffer = bufnr })
        vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "none" })
        vim.api.nvim_exec_autocmds("TextChangedP", { buffer = bufnr })

        local marks = require("scrollbar.store").get(bufnr).search
        return vim.tbl_map(function(mark)
            return mark.line
        end, marks)
    end)()]])

    expect.equality(immediate, { 1 })
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 2 }), true)
    expect.equality(scan_calls(child), {
        { pattern = "match", flags = "Wnc" },
        { pattern = "match", flags = "bWnc" },
    })
end

T["visible buffers debounce independently"] = function()
    local child = new_child()
    helpers.set_lines(child, { "start", "match" })
    helpers.accept_search(child, "/", "match")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)

    local buffers = child.lua_get([[(function()
        vim.cmd("vsplit")
        local first = vim.api.nvim_get_current_buf()
        local second = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(second, 0, -1, false, { "start", "match" })
        vim.api.nvim_win_set_buf(0, second)
        return { first = first, second = second }
    end)()]])
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)

    child.lua([[
        local state = { scans = {} }
        local searchpos = vim.fn.searchpos
        vim.fn.searchpos = function(pattern, flags, ...)
            if flags == "Wnc" then
                local bufnr = vim.api.nvim_get_current_buf()
                state.scans[bufnr] = (state.scans[bufnr] or 0) + 1
            end
            return searchpos(pattern, flags, ...)
        end
        package.loaded["scrollbar.test.search_scans"] = state
    ]])

    child.lua_func(function(value)
        vim.api.nvim_buf_set_lines(value.first, 1, 2, false, { "match match match" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = value.first })
        vim.api.nvim_buf_set_lines(value.first, 1, 2, false, { "match match" })
        vim.api.nvim_exec_autocmds("TextChangedI", { buffer = value.first })

        vim.api.nvim_buf_set_lines(value.second, 1, 2, false, { "none", "match match" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = value.second })
        vim.api.nvim_buf_set_lines(value.second, 2, 3, false, { "match" })
        vim.api.nvim_exec_autocmds("TextChangedP", { buffer = value.second })
    end, buffers)

    local completed = child.lua_func(function(value)
        local function mark_lines(bufnr)
            local marks = require("scrollbar.store").get(bufnr).search
            return marks and vim.tbl_map(function(mark)
                return mark.line
            end, marks) or nil
        end
        return vim.wait(1000, function()
            return vim.deep_equal(mark_lines(value.first), { 1, 1 }) and vim.deep_equal(mark_lines(value.second), { 2 })
        end)
    end, buffers)

    expect.equality(completed, true)
    expect.equality(child.lua_get([[package.loaded["scrollbar.test.search_scans"].scans]]), {
        [buffers.first] = 1,
        [buffers.second] = 1,
    })
end

T["aborting before live debounce cancels preview without rescanning the accepted signature"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, true)
    helpers.set_lines(child, { "start", "accepted", "preview" })
    helpers.accept_search(child, "/", "accepted")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    instrument_scans(child)

    child.type_keys(0, "/", "preview", "<C-c>")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    child.lua([[vim.wait(100)]])
    expect.equality(scan_calls(child), {})
end

T["live input coalesces to the latest preview and restores on abort"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, true)
    helpers.set_lines(child, { "start", "accepted", "preview", "preview" })
    helpers.accept_search(child, "/", "accepted")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    instrument_scans(child)

    expect.equality(helpers.inspect_during_cmdline(child, "/", "preview").lines, { 2, 3 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    expect.equality(scan_calls(child), {
        { pattern = "preview", flags = "Wnc" },
        { pattern = "preview", flags = "bWnc" },
        { pattern = "accepted", flags = "Wnc" },
        { pattern = "accepted", flags = "bWnc" },
    })
end

T["disposal cancels pending scans"] = function()
    local child = new_child()
    helpers.set_lines(child, { "start", "match" })
    helpers.accept_search(child, "/", "match")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    instrument_scans(child)

    expect.equality(
        child.lua_get([[(function()
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "match match" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
        return require("scrollbar.providers").unregister("search")
    end)()]]),
        true
    )
    child.lua([[vim.wait(100)]])

    expect.equality(scan_calls(child), {})
    expect.equality(helpers.search_marks(child), nil)
end

T["unchanged signatures do not enqueue scans"] = function()
    local child = new_child()
    helpers.set_lines(child, { "start", "match" })
    helpers.accept_search(child, "/", "match")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    instrument_scans(child)

    child.lua([[
        local bufnr = vim.api.nvim_get_current_buf()
        require("scrollbar.store").set("search", bufnr, { { line = 0, type = "Search" } })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr })
        vim.api.nvim_exec_autocmds("SafeState", { buffer = bufnr })
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = bufnr })
    ]])
    child.lua([[vim.wait(100)]])

    expect.equality(scan_calls(child), {})
    expect.equality(helpers.mark_lines(child), { 0 })
end

return T
