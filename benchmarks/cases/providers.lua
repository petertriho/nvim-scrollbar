---One refresh of a custom provider through the manager API that `docs/providers/custom.md` describes. A `noop`
---refresh returns the marks that the store already has. A `changed` refresh moves one mark, so the store validates and
---copies the marks and notifies the scheduler.
local fixtures = require("benchmarks.fixtures")

local PROVIDER = "benchmark_provider"

---@param state { marks: table[], spans: table[], changed: boolean, line: integer }
local function move_first(state)
    state.line = (state.line + 7) % fixtures.LINE_COUNT
    if state.marks[1] ~= nil then
        state.marks[1] = { line = state.line, type = state.marks[1].type }
    end
    if state.spans[1] ~= nil then
        local span = state.spans[1]
        state.spans[1] = {
            line = state.line,
            start_col = span.start_col,
            end_col = span.end_col,
            highlight = span.highlight,
            priority = span.priority,
        }
    end
end

---@param count integer
---@return table[]
local function spans(count)
    local result = {}
    for index = 1, count do
        result[index] = {
            line = math.floor((index - 1) * (fixtures.LINE_COUNT - 1) / math.max(1, count - 1)),
            start_col = 0,
            end_col = 12,
            highlight = "@variable",
            priority = 200,
        }
    end
    return result
end

---@param name string
---@param opts { marks?: integer, spans?: integer, changed: boolean }
---@return bench.SyncCase
local function refresh_case(name, opts)
    return {
        name = "providers/refresh/" .. name,
        setup = function()
            local bufnr = fixtures.buffer(fixtures.lines(fixtures.LINE_COUNT))
            fixtures.source_window(bufnr)
            local state = {
                bufnr = bufnr,
                marks = opts.marks and fixtures.spread(opts.marks, fixtures.LINE_COUNT, "Error") or {},
                spans = opts.spans and spans(opts.spans) or {},
                changed = opts.changed,
                line = 0,
            }

            local providers = require("scrollbar.providers")
            if opts.spans then
                providers.register({
                    name = PROVIDER,
                    targets = { minimap = true },
                    refresh_owner = { minimap_buffer = "manager" },
                    refresh_minimap = function()
                        return state.spans
                    end,
                })
            else
                providers.register({
                    name = PROVIDER,
                    refresh_owner = { buffer = "manager" },
                    refresh = function()
                        return state.marks
                    end,
                })
            end
            require("scrollbar").setup({
                set_highlights = false,
                exclude = { buftypes = {}, filetypes = {} },
                providers = {
                    cursor = false,
                    diagnostic = false,
                    search = false,
                    marks = false,
                    treesitter = false,
                },
                minimap = opts.spans and { enabled = true, backend = "sync" } or { enabled = false },
            })
            providers.refresh(bufnr)
            return state
        end,
        run = function(state)
            if state.changed then
                move_first(state)
            end
            require("scrollbar.providers").refresh(state.bufnr)
        end,
        teardown = function()
            require("scrollbar.providers").unregister(PROVIDER)
            fixtures.reset()
        end,
    }
end

---@type bench.Case[]
return {
    refresh_case("marks_200_noop", { marks = 200, changed = false }),
    refresh_case("marks_200_changed", { marks = 200, changed = true }),
    refresh_case("marks_2000_noop", { marks = 2000, changed = false }),
    refresh_case("marks_2000_changed", { marks = 2000, changed = true }),
    refresh_case("spans_5000_noop", { spans = 5000, changed = false }),
    refresh_case("spans_5000_changed", { spans = 5000, changed = true }),
}
