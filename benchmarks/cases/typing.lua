---The synchronous work of one keystroke: the TextChangedI and CursorMoved autocmds of a full setup. The deferred render
---that the throttle timer starts is not part of an operation. The render cases measure it.
local fixtures = require("benchmarks.fixtures")

---@param minimap boolean
local function setup_plugin(minimap)
    require("scrollbar").setup({
        set_highlights = false,
        exclude = { buftypes = {}, filetypes = {} },
        -- The sync backends start no worker child, so the cases measure only the parent
        providers = {
            search = { backend = "sync" },
            treesitter = false,
        },
        minimap = minimap and { enabled = true, backend = "sync" } or { enabled = false },
    })
    -- An older setup() that ignores these options would measure other work
    assert(require("scrollbar.scheduler").status().setup, "the scheduler did not start")
end

---Key presses arrive farther apart than the lifetime of the eligibility memos, so each operation starts with empty
---memos. Calls inside one event can still reuse them.
local function clear_eligibility_memos()
    for _, name in ipairs({ "scrollbar.renderer", "scrollbar.minimap.renderer" }) do
        local module = package.loaded[name]
        if module ~= nil and type(module.invalidate_source_selection) == "function" then
            module.invalidate_source_selection()
        end
    end
end

---@param name string
---@param minimap boolean
---@return bench.SyncCase
local function text_changed_i(name, minimap)
    return {
        name = "typing/text_changed_i/" .. name,
        setup = function()
            local bufnr = fixtures.buffer(fixtures.lines(fixtures.LINE_COUNT))
            fixtures.source_window(bufnr)
            setup_plugin(minimap)
            return { bufnr = bufnr }
        end,
        run = function(state)
            vim.api.nvim_exec_autocmds("TextChangedI", { buffer = state.bufnr })
        end,
        teardown = fixtures.reset,
    }
end

---@param name string
---@param minimap boolean
---@return bench.SyncCase
local function cursor_moved(name, minimap)
    return {
        name = "typing/cursor_moved/" .. name,
        setup = function()
            local bufnr = fixtures.buffer(fixtures.lines(fixtures.LINE_COUNT))
            local winid = fixtures.source_window(bufnr)
            setup_plugin(minimap)
            return { bufnr = bufnr, winid = winid, row = 0 }
        end,
        run = function(state)
            state.row = state.row % 20 + 1
            vim.api.nvim_win_set_cursor(state.winid, { state.row, 0 })
            clear_eligibility_memos()
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = state.bufnr })
        end,
        teardown = fixtures.reset,
    }
end

---@type bench.Case[]
return {
    text_changed_i("scrollbar", false),
    text_changed_i("minimap", true),
    cursor_moved("scrollbar", false),
    cursor_moved("minimap", true),
}
