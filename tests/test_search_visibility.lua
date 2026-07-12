local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function search_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, true)
    helpers.set_lines(child, { "start", "accepted", "preview", "preview" })
    helpers.accept_search(child, "/", "preview")
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 3 }), true)
    return child
end

local function clear_with_nohlsearch(child)
    child.type_keys(10, ":nohlsearch", "<CR>")
    return helpers.wait_for_mark_lines(child, nil)
end

T[":nohlsearch clears marks from every loaded buffer"] = function()
    local child = search_child()
    local buffers = child.lua_get([[(function()
        local current = vim.api.nvim_get_current_buf()
        local other = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(other, 0, -1, false, { "preview" })
        vim.api.nvim_win_set_buf(0, other)
        return { current = current, other = other }
    end)()]])
    expect.equality(helpers.mark_lines(child), { 0 })
    child.api.nvim_win_set_buf(0, buffers.current)
    expect.equality(clear_with_nohlsearch(child), true)
    expect.equality(helpers.search_marks(child, buffers.other), nil)
    expect.equality(helpers.search_marks(child, buffers.current), nil)
end

T["a new accepted search restores marks after :nohlsearch"] = function()
    local child = search_child()
    expect.equality(clear_with_nohlsearch(child), true)
    helpers.accept_search(child, "/", "preview")
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 3 }), true)
end

T["set nohlsearch clears current marks"] = function()
    local child = search_child()
    child.o.hlsearch = false
    expect.equality(helpers.wait_for_mark_lines(child, nil), true)
end

T["accepted searches work after hlsearch is re-enabled"] = function()
    local child = search_child()
    child.o.hlsearch = false
    expect.equality(helpers.wait_for_mark_lines(child, nil), true)
    child.o.hlsearch = true
    helpers.accept_search(child, "/", "preview")
    expect.equality(helpers.wait_for_mark_lines(child, { 2, 3 }), true)
end

T["provider manager restart restores visible native highlighting"] = function()
    local child = search_child()
    child.lua([[
        local providers = require("scrollbar.providers")
        providers.dispose()
        providers.setup({ config = require("scrollbar.config").get() })
    ]])
    expect.equality(helpers.mark_lines(child), { 2, 3 })
end

T["CursorMoved synchronizes changed native search patterns"] = function()
    local child = search_child()
    child.fn.setreg("/", "accepted")
    child.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
    expect.equality(helpers.mark_lines(child), { 1 })
    child.fn.setreg("/", "preview")
    child.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
    expect.equality(helpers.mark_lines(child), { 2, 3 })
end

T["CursorMoved does not rescan an unchanged visible search"] = function()
    local child = search_child()
    child.lua([[
        require("scrollbar.store").set("search", vim.api.nvim_get_current_buf(), {
            { line = 0, type = "Search" },
        })
    ]])
    child.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
    expect.equality(helpers.mark_lines(child), { 0 })
end

T["WinScrolled does not rescan an unchanged visible search"] = function()
    local child = search_child()
    child.lua([[
        require("scrollbar.store").set("search", vim.api.nvim_get_current_buf(), {
            { line = 0, type = "Search" },
        })
    ]])
    child.api.nvim_exec_autocmds("WinScrolled", {})
    expect.equality(helpers.mark_lines(child), { 0 })
end

T["an empty accepted pattern clears marks"] = function()
    local child = search_child()
    child.fn.setreg("/", "")
    child.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
    expect.equality(helpers.search_marks(child), nil)
end

T["clearing search invalidates every source window displaying the buffer"] = function()
    local child = search_child()
    child.cmd("vsplit")
    local expected_windows = child.api.nvim_list_wins()
    table.sort(expected_windows)
    helpers.reset_search_invalidations(child)

    expect.equality(clear_with_nohlsearch(child), true)
    local invalidations = helpers.search_invalidations(child)
    local invalidated_buffers = {}
    local invalidated_windows = {}
    for _, bufnr in ipairs(invalidations.buffers) do
        invalidated_buffers[bufnr] = true
    end
    for _, winid in ipairs(invalidations.windows) do
        invalidated_windows[winid] = true
    end
    invalidations.buffers = vim.tbl_keys(invalidated_buffers)
    invalidations.windows = vim.tbl_keys(invalidated_windows)
    table.sort(invalidations.buffers)
    table.sort(invalidations.windows)

    expect.equality(invalidations.buffers, { child.api.nvim_get_current_buf() })
    expect.equality(invalidations.windows, expected_windows)
end

return T
