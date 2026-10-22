---Measurement functions for the cases in `benchmarks/cases/`.
local M = {}

local hrtime = vim.uv.hrtime

---A case whose operation finishes before `run` returns.
---@class bench.SyncCase
---@field name string
---@field setup? fun(): any Runs once. Its result goes to `run` and `teardown`.
---@field run fun(state: any) One operation.
---@field teardown? fun(state: any)

---A case whose operation finishes when it calls `done`, for example a search that a worker answers.
---@class bench.AsyncCase
---@field name string
---@field async true
---@field setup? fun(): any Runs once. Its result goes to the other functions.
---@field before_each? fun(state: any) Runs before each operation, outside the measurement.
---@field run fun(state: any, done: fun(err?: string)) One operation. An error message fails the case.
---@field hooks? string[] Global functions that a worker child calls. Their time counts as main-thread time, and each
---operation must call each of them, so that a renamed global fails the case instead of hiding the work.
---@field teardown? fun(state: any)

---@alias bench.Case bench.SyncCase | bench.AsyncCase

---@class bench.Options
---@field samples integer Samples for each sync case.
---@field async_samples integer Samples for each async case.
---@field min_sample_ns number A sync sample repeats the operation until it takes at least this long.
---@field alloc_ops integer Operations in the allocation pass of a sync case.
---@field timeout_ms integer Time limit for one async operation.

---@class bench.Result
---@field kind "sync" | "async"
---@field unit "us" | "ms"
---@field samples number[]
---@field median number
---@field min number
---@field alloc_kb? number Lua heap allocated for each operation of a sync case.
---@field main_ms? number Median main-thread time of an async operation.
---@field block_ms? number Median of the longest uninterrupted main-thread slice of an async operation.
---@field spawns number Processes started for each operation.
---@field blocking number Synchronous process calls (`vim.fn.system`) for each operation.

---@param values number[]
---@return number
local function median(values)
    local sorted = vim.list_extend({}, values)
    table.sort(sorted)
    local middle = math.floor(#sorted / 2) + 1
    if #sorted % 2 == 1 then
        return sorted[middle]
    end
    return (sorted[middle - 1] + sorted[middle]) / 2
end

---@param values number[]
---@return number
local function minimum(values)
    return math.min(unpack(values))
end

M.median = median

---Counts the processes that the code under test starts, and times its main-thread work. The code reads
---`vim.system`, `vim.fn.jobstart`, `vim.fn.system`, and `vim.schedule` when it calls them, so replacing them here is
---enough. `vim.schedule_wrap` and `vim.defer_fn` call `vim.schedule`, so the throttle timers count too. A worker child
---calls a global function over RPC, so an async case lists these globals in `hooks`.
local probe = {
    spawns = 0,
    blocking = 0,
    pending = 0,
    slices = {}, ---@type number[]
    hook_calls = {}, ---@type table<string, integer>
    -- A slice inside another slice is already part of the outer slice
    depth = 0,
}

---@type { system: function, jobstart: function, fn_system: function, fn_systemlist: function, schedule: function }?
local originals = nil
local hooked = {} ---@type table<string, function>

function probe.reset()
    probe.spawns = 0
    probe.blocking = 0
    probe.slices = {}
    for name in pairs(probe.hook_calls) do
        probe.hook_calls[name] = 0
    end
end

---@param fn function
---@return function
local function timed(fn)
    return function(...)
        if probe.depth > 0 then
            return fn(...)
        end
        probe.depth = 1
        local start = hrtime()
        local result = vim.F.pack_len(pcall(fn, ...))
        table.insert(probe.slices, hrtime() - start)
        probe.depth = 0
        if not result[1] then
            error(result[2], 0)
        end
        return unpack(result, 2, result.n)
    end
end

function probe.install()
    originals = {
        system = vim.system,
        jobstart = vim.fn.jobstart,
        fn_system = vim.fn.system,
        fn_systemlist = vim.fn.systemlist,
        schedule = vim.schedule,
    }
    local o = originals

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.system = function(cmd, opts, on_exit)
        probe.spawns = probe.spawns + 1
        if not on_exit then
            return o.system(cmd, opts)
        end

        probe.pending = probe.pending + 1
        return o.system(cmd, opts, function(...)
            probe.pending = probe.pending - 1
            return on_exit(...)
        end)
    end

    -- A worker child runs until the code stops it, so `settle` does not wait for it
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.fn.jobstart = function(...)
        probe.spawns = probe.spawns + 1
        return o.jobstart(...)
    end

    local function blocking(original)
        return function(...)
            probe.spawns = probe.spawns + 1
            probe.blocking = probe.blocking + 1
            return original(...)
        end
    end
    vim.fn.system = blocking(o.fn_system)
    vim.fn.systemlist = blocking(o.fn_systemlist)

    ---@diagnostic disable-next-line: duplicate-set-field
    vim.schedule = function(fn)
        return o.schedule(timed(fn))
    end
end

---@param names string[]
-- selene: allow(global_usage)
function probe.install_hooks(names)
    for _, name in ipairs(names) do
        local original = rawget(_G, name)
        if type(original) ~= "function" then
            error(string.format("the hook %s is not a global function", name), 0)
        end
        hooked[name] = original
        probe.hook_calls[name] = 0
        local wrapped = timed(original)
        rawset(_G, name, function(...)
            probe.hook_calls[name] = probe.hook_calls[name] + 1
            return wrapped(...)
        end)
    end
end

-- selene: allow(global_usage)
function probe.uninstall()
    for name, original in pairs(hooked) do
        rawset(_G, name, original)
    end
    hooked = {}
    probe.hook_calls = {}
    if not originals then
        return
    end

    vim.system = originals.system
    vim.fn.jobstart = originals.jobstart
    vim.fn.system = originals.fn_system
    vim.fn.systemlist = originals.fn_systemlist
    vim.schedule = originals.schedule
    originals = nil
end

---Wait until the processes that the code started exit and their scheduled callbacks run, so that the work of one
---operation does not run during the next one.
---@param timeout_ms integer
local function settle(timeout_ms)
    vim.wait(timeout_ms, function()
        return probe.pending == 0
    end, 1)
    for _ = 1, 3 do
        vim.wait(0)
    end
end

---@param run fun(state: any)
---@param state any
---@param iterations integer
---@return number ns Time for each operation.
local function time_batch(run, state, iterations)
    local start = hrtime()
    for _ = 1, iterations do
        run(state)
    end
    return (hrtime() - start) / iterations
end

---@param case bench.SyncCase
---@param opts bench.Options
---@return bench.Result
function M.measure_sync(case, opts)
    local state = case.setup and case.setup()

    probe.install()
    local ok, result = pcall(function()
        -- The first runs warm up the JIT compiler and the caches that the case fills
        probe.reset()
        local per_op = time_batch(case.run, state, 1)
        local spawns, blocking = probe.spawns, probe.blocking
        settle(opts.timeout_ms)

        local iterations = 1
        while per_op * iterations < opts.min_sample_ns and iterations < 2 ^ 20 do
            iterations = iterations * 2
            per_op = time_batch(case.run, state, iterations)
        end

        local samples = {}
        for i = 1, opts.samples do
            samples[i] = time_batch(case.run, state, iterations) / 1e3
        end

        -- With the collector stopped, the heap grows by exactly the bytes that the operations allocate
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, opts.alloc_ops do
            case.run(state)
        end
        local alloc_kb = (collectgarbage("count") - before) / opts.alloc_ops
        collectgarbage("restart")

        ---@type bench.Result
        return {
            kind = "sync",
            unit = "us",
            samples = samples,
            median = median(samples),
            min = minimum(samples),
            alloc_kb = alloc_kb,
            spawns = spawns,
            blocking = blocking,
        }
    end)
    collectgarbage("restart")
    probe.uninstall()

    if case.teardown then
        case.teardown(state)
    end
    if not ok then
        error(result, 0)
    end
    return result
end

---@param case bench.AsyncCase
---@param opts bench.Options
---@return bench.Result
function M.measure_async(case, opts)
    local state = case.setup and case.setup()

    probe.install()
    local ok, result = pcall(function()
        probe.install_hooks(case.hooks or {})
        local wall, main, block = {}, {}, {}
        local spawns, blocking = 0, 0
        local warmup = 1

        for i = 1, warmup + opts.async_samples do
            if case.before_each then
                case.before_each(state)
            end
            settle(opts.timeout_ms)
            probe.reset()

            local finished_at = nil ---@type number?
            local failure = nil ---@type string?
            local start = hrtime()
            case.run(state, function(err)
                finished_at = finished_at or hrtime()
                failure = failure or err
            end)
            local sync_ns = hrtime() - start

            if
                not vim.wait(opts.timeout_ms, function()
                    return finished_at ~= nil
                end, 1)
            then
                error(string.format("the operation did not finish within %d ms", opts.timeout_ms), 0)
            end
            if failure then
                error(failure, 0)
            end
            settle(opts.timeout_ms)
            for name, calls in pairs(probe.hook_calls) do
                if calls == 0 then
                    error(string.format("the operation did not call the hook %s", name), 0)
                end
            end

            if i > warmup then
                local main_ns, block_ns = sync_ns, sync_ns
                for _, slice in ipairs(probe.slices) do
                    main_ns = main_ns + slice
                    block_ns = math.max(block_ns, slice)
                end
                ---@cast finished_at number
                table.insert(wall, (finished_at - start) / 1e6)
                table.insert(main, main_ns / 1e6)
                table.insert(block, block_ns / 1e6)
                spawns = spawns + probe.spawns
                blocking = blocking + probe.blocking
            end
        end

        ---@type bench.Result
        return {
            kind = "async",
            unit = "ms",
            samples = wall,
            median = median(wall),
            min = minimum(wall),
            main_ms = median(main),
            block_ms = median(block),
            spawns = spawns / opts.async_samples,
            blocking = blocking / opts.async_samples,
        }
    end)
    probe.uninstall()

    if case.teardown then
        case.teardown(state)
    end
    if not ok then
        error(result, 0)
    end
    return result
end

---@param case bench.Case
---@param opts bench.Options
---@return bench.Result
function M.measure(case, opts)
    if case.async then
        ---@cast case bench.AsyncCase
        return M.measure_async(case, opts)
    end
    ---@cast case bench.SyncCase
    return M.measure_sync(case, opts)
end

---@param value number
---@param unit "us" | "ms"
---@return string
function M.format_time(value, unit)
    if unit == "ms" then
        return string.format("%.2f ms", value)
    end
    if value >= 1000 then
        return string.format("%.2f ms", value / 1000)
    end
    return string.format("%.2f us", value)
end

---@param name string
---@param result bench.Result
---@return string
function M.format_result(name, result)
    local parts = {
        string.format("%-52s", name),
        string.format("median %10s", M.format_time(result.median, result.unit)),
        string.format("min %10s", M.format_time(result.min, result.unit)),
    }
    if result.kind == "sync" then
        table.insert(parts, string.format("alloc %8.2f KB", result.alloc_kb))
    else
        table.insert(parts, string.format("main %8.2f ms", result.main_ms))
        table.insert(parts, string.format("block %7.2f ms", result.block_ms))
    end
    table.insert(parts, string.format("spawns %4.1f", result.spawns))
    if result.blocking > 0 then
        table.insert(parts, string.format("blocking %3.1f", result.blocking))
    end
    return table.concat(parts, "  ")
end

return M
