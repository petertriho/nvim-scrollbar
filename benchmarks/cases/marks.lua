---The reconcile of the marks provider: for each unique buffer that a window shows, it reads the line count and collects
---the marks with the real collect() through refresh(). A stub context skips the eligibility check and the publication.
---The provider runs the reconcile on MarkSet, and on SafeState before Neovim 0.12.2 or with the `numbers` option.
local fixtures = require("benchmarks.fixtures")

local MARK_ROWS = { 100, 500, 2000, 4000, 6000, 9000 }
local MARK_NAMES = { "a", "b", "c", "d", "e", "f" }

---@param bufnr integer
local function set_marks(bufnr)
    for index, name in ipairs(MARK_NAMES) do
        vim.api.nvim_buf_set_mark(bufnr, name, MARK_ROWS[index], 0, {})
    end
end

---@param buffer_count integer
---@return bench.SyncCase
local function reconcile_case(buffer_count)
    return {
        name = string.format("marks/reconcile/buffers_%d", buffer_count),
        setup = function()
            require("scrollbar.config").set({})
            local plan = require("scrollbar.config").get_provider_plan()
            local context = {
                config = {
                    providers = {
                        marks = vim.deepcopy(plan.marks.options --[[@as table]]),
                    },
                },
                is_buffer_eligible = function()
                    return true
                end,
                clear_marks = function() end,
            }

            local lines = fixtures.lines(fixtures.LINE_COUNT)
            for index = 1, buffer_count do
                local bufnr = fixtures.buffer(lines)
                set_marks(bufnr)
                if index == 1 then
                    fixtures.source_window(bufnr)
                else
                    fixtures.split(bufnr)
                end
            end

            -- Without this check, a context that turns the provider off measures no work
            local marks = require("scrollbar.providers.marks")
            for _, winid in ipairs(vim.api.nvim_list_wins()) do
                local found = marks.refresh(vim.api.nvim_win_get_buf(winid), context) or {}
                assert(#found == #MARK_NAMES, string.format("collect() found %d marks", #found))
            end
            return { marks = marks, context = context }
        end,
        run = function(state)
            local seen = {}
            for _, winid in ipairs(vim.api.nvim_list_wins()) do
                local bufnr = vim.api.nvim_win_get_buf(winid)
                if not seen[bufnr] then
                    seen[bufnr] = true
                    vim.api.nvim_buf_line_count(bufnr)
                    state.marks.refresh(bufnr, state.context)
                end
            end
        end,
        teardown = fixtures.reset,
    }
end

---@type bench.Case[]
return {
    reconcile_case(1),
    reconcile_case(4),
    reconcile_case(16),
}
