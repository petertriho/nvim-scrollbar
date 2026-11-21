---Requests to the worker children, and their startup. The round-trip cases start the child once in setup. The time of
---an operation runs from the request to the result in the parent. `main` counts the work that the parent does for the
---request, including the callback that the child calls over RPC.
local fixtures = require("benchmarks.fixtures")
local minimap = require("benchmarks.cases.minimap")
local search = require("benchmarks.cases.search")

local SEARCH_CALLBACK = "__scrollbar_search_worker_callback"
local MINIMAP_CALLBACK = "__scrollbar_minimap_worker_callback"

local function noop() end

---Runs one search outside the measurement, and waits for its publication.
---@param state bench.SearchState
local function search_and_wait(state)
    local searched = false
    search.run(state, function()
        searched = true
    end)
    if not vim.wait(fixtures.READY_TIMEOUT_MS, function()
        return searched
    end, 1) then
        error("the search in setup did not publish", 0)
    end
end

---Sets up the worker search, and runs one search, because the worker starts at the first search.
---@param kind bench.SearchFixture
---@return bench.SearchState
local function search_setup(kind)
    local state = search.setup(kind, "worker")
    search.next_pattern(state)
    search_and_wait(state)
    fixtures.wait_until_ready(require("scrollbar.providers.search.worker"))
    return state
end

---@param kind bench.SearchFixture
---@return bench.AsyncCase
local function search_round_trip(kind)
    return {
        name = "worker/search/round_trip_" .. kind,
        async = true,
        hooks = { SEARCH_CALLBACK },
        setup = function()
            return search_setup(kind)
        end,
        before_each = search.next_pattern,
        run = search.run,
        teardown = search.teardown,
    }
end

-- The lines that `search_edit` puts in the middle of the buffer in turn: one with a match of the first pattern, and one
-- without.
local EDIT_ROW = fixtures.LINE_COUNT / 2
local EDIT_LINES = {
    sparse = { "sparse_a plain", "plain plain" },
    dense = { "dense_a dense_b dense_b", "plain plain plain" },
}

---A search of the same pattern after an edit of one line. The edit runs before each operation, outside the
---measurement, and changes the matches, so that the store publishes each result.
---@param kind bench.SearchFixture
---@return bench.AsyncCase
local function search_edit(kind)
    return {
        name = "worker/search/edit_" .. kind,
        async = true,
        hooks = { SEARCH_CALLBACK },
        setup = function()
            local state = search_setup(kind)
            -- The store publishes only a change, so the first edit puts the line that differs from the current one.
            local current = vim.api.nvim_buf_get_lines(state.bufnr, EDIT_ROW, EDIT_ROW + 1, true)[1]
            state.index = current == EDIT_LINES[kind][1] and 1 or 2
            return state
        end,
        before_each = function(state)
            state.index = state.index % 2 + 1
            vim.api.nvim_buf_set_lines(state.bufnr, EDIT_ROW, EDIT_ROW + 1, false, { EDIT_LINES[kind][state.index] })
        end,
        run = search.run,
        teardown = search.teardown,
    }
end

---@param name string
---@param module string
---@param callback string
---@param options table The options of `setup`, without `on_failure` and `test`.
---@return bench.AsyncCase
local function startup(name, module, callback, options)
    return {
        name = string.format("worker/%s/startup", name),
        async = true,
        hooks = { callback },
        setup = function()
            return { worker = require(module) }
        end,
        before_each = function(state)
            fixtures.dispose_worker(state.worker)
        end,
        run = function(state, done)
            local started = state.worker.setup(vim.tbl_extend("force", options, {
                on_failure = function(reason)
                    done("the worker failed: " .. tostring(reason))
                end,
                test = {
                    on_timing = function(event)
                        if event == "worker_ready" then
                            done()
                        end
                    end,
                },
            }))
            if not started then
                done("the worker did not start")
            end
        end,
        teardown = function(state)
            fixtures.dispose_worker(state.worker)
            fixtures.reset()
        end,
    }
end

---@type bench.Case[]
return {
    search_round_trip("sparse"),
    search_round_trip("dense"),
    search_edit("sparse"),
    search_edit("dense"),
    {
        name = "worker/minimap/round_trip_10k",
        async = true,
        hooks = { MINIMAP_CALLBACK },
        setup = function()
            local worker = require("scrollbar.minimap.worker")
            local state = {
                worker = worker,
                bufnr = fixtures.buffer(fixtures.lines(fixtures.LINE_COUNT)),
                generation = 0,
                done = nil, ---@type fun(err?: string)?
            }
            worker.setup({
                backend = "worker",
                treesitter = false,
                on_result = function(payload)
                    local done = state.done
                    if done ~= nil and payload.generation == state.generation then
                        state.done = nil
                        done()
                    end
                end,
            })
            fixtures.wait_until_ready(worker)
            return state
        end,
        run = function(state, done)
            state.done = done
            if not state.worker.request(minimap.request(state)) then
                done("the worker rejected the request")
            end
        end,
        teardown = function(state)
            fixtures.dispose_worker(state.worker)
            fixtures.reset()
        end,
    },
    startup("search", "scrollbar.providers.search.worker", SEARCH_CALLBACK, { on_result = noop }),
    startup(
        "minimap",
        "scrollbar.minimap.worker",
        MINIMAP_CALLBACK,
        { backend = "worker", treesitter = false, on_result = noop }
    ),
}
