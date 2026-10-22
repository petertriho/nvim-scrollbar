---Requests to the worker children, and their startup. The round-trip cases start the child once in setup. The time of
---an operation runs from the request to the result in the parent. `main` counts the work that the parent does for the
---request, including the callback that the child calls over RPC.
local fixtures = require("benchmarks.fixtures")
local minimap = require("benchmarks.cases.minimap")
local search = require("benchmarks.cases.search")

local SEARCH_CALLBACK = "__scrollbar_search_worker_callback"
local MINIMAP_CALLBACK = "__scrollbar_minimap_worker_callback"

local function noop() end

---@param kind bench.SearchFixture
---@return bench.AsyncCase
local function search_round_trip(kind)
    return {
        name = "worker/search/round_trip_" .. kind,
        async = true,
        hooks = { SEARCH_CALLBACK },
        setup = function()
            local state = search.setup(kind, "worker")
            fixtures.wait_until_ready(require("scrollbar.providers.search.worker"))
            return state
        end,
        before_each = search.next_pattern,
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
