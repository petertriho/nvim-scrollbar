---One accepted search with the sync backend, from the BufEnter event to the publication of the matches. The search runs
---in a scheduled callback, so these are async cases. Each operation alternates between two patterns, so that the
---result changes and the store publishes it. `benchmarks/cases/worker.lua` has the same search with the worker backend.
local fixtures = require("benchmarks.fixtures")

local M = {}

---@alias bench.SearchFixture "sparse" | "dense"

---@param kind bench.SearchFixture
---@return string[] lines
---@return string[] patterns
function M.fixture(kind)
    if kind == "sparse" then
        return fixtures.lines(fixtures.LINE_COUNT, function(index)
            local first = index % 500 == 0 and "sparse_a" or "plain"
            local second = index % 500 == 250 and "sparse_b" or "plain"
            return first .. " " .. second
        end),
            { "sparse_a", "sparse_b" }
    end
    return fixtures.lines(fixtures.LINE_COUNT, function(index)
        return index % 2 == 1 and "dense_a dense_b dense_b" or "dense_a plain plain"
    end),
        { "dense_a", "dense_b" }
end

---@class bench.SearchState
---@field bufnr integer
---@field winid integer
---@field patterns string[]
---@field index integer
---@field wait fun(done: fun(err?: string))
---@field unsubscribe fun()
---@field registered boolean The case registered the provider, so its teardown unregisters it.

---Sets up the search provider alone, without the renderers, as the provider manager does.
---@param kind bench.SearchFixture
---@param backend "sync" | "worker"
---@return bench.SearchState
function M.setup(kind, backend)
    local lines, patterns = M.fixture(kind)
    local bufnr = fixtures.buffer(lines)
    local winid = fixtures.source_window(bufnr)
    vim.o.hlsearch = true

    local config = require("scrollbar.config")
    local providers = require("scrollbar.providers")
    local active_config = config.set({
        set_highlights = false,
        providers = {
            cursor = false,
            diagnostic = false,
            marks = false,
            treesitter = false,
            search = { backend = backend, incsearch = false },
        },
        scrollbar = { max_lines = false },
    })
    -- A full setup in an earlier case can leave the built-in provider registered
    local registered = providers.get("search") == nil
    if registered then
        providers.register(require("scrollbar.providers.search"))
    end
    providers.setup({
        config = active_config,
        invalidate_buffer = function() end,
        source_windows = function(target)
            return (target == nil or target == bufnr) and { winid } or {}
        end,
        is_source_window = function(target)
            return target == winid
        end,
    })

    local wait, unsubscribe = fixtures.on_publication("search", bufnr)
    return {
        bufnr = bufnr,
        winid = winid,
        patterns = patterns,
        index = 0,
        wait = wait,
        unsubscribe = unsubscribe,
        registered = registered,
    }
end

---Selects the other pattern. It runs outside the measurement.
---@param state bench.SearchState
function M.next_pattern(state)
    state.index = state.index % #state.patterns + 1
    vim.fn.setreg("/", state.patterns[state.index])
    vim.v.hlsearch = 1
end

---Starts an accepted search, as when the cursor enters the buffer.
---@param state bench.SearchState
---@param done fun(err?: string)
function M.run(state, done)
    state.wait(done)
    vim.api.nvim_exec_autocmds("BufEnter", { buffer = state.bufnr })
end

---@param state bench.SearchState
function M.teardown(state)
    state.unsubscribe()
    fixtures.reset()
    if state.registered then
        require("scrollbar.providers").unregister("search")
    end
end

---@param kind bench.SearchFixture
---@return bench.AsyncCase
local function sync_case(kind)
    return {
        name = "search/sync/" .. kind,
        async = true,
        setup = function()
            return M.setup(kind, "sync")
        end,
        before_each = M.next_pattern,
        run = M.run,
        teardown = M.teardown,
    }
end

-- benchmarks/run.lua reads the cases from the list part. benchmarks/cases/worker.lua uses the functions.
table.insert(M, sync_case("sparse"))
table.insert(M, sync_case("dense"))

return M
