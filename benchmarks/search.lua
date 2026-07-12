local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.swapfile = false
vim.o.hlsearch = true
vim.o.wrapscan = false
vim.o.ignorecase = false
vim.o.smartcase = false
vim.o.magic = true

local line_count = 50000
local warmup_count = 5
local iteration_count = 30
local worker_warmup_count = 2
local worker_iteration_count = 10
local timer_period_ms = 2
local timeout_ms = 60000

local function percentile(sorted, fraction)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function statistics(samples)
    table.sort(samples)
    return {
        median = percentile(samples, 0.5),
        p95 = percentile(samples, 0.95),
        maximum = samples[#samples],
    }
end

local function fixture(kind)
    local lines = {}
    if kind == "sparse" then
        for index = 1, line_count do
            local first = index % 500 == 0 and "sparse_a" or "plain"
            local second = index % 500 == 250 and "sparse_b" or "plain"
            lines[index] = first .. " " .. second
        end
        return lines, { "sparse_a", "sparse_b" }, 100
    end

    for index = 1, line_count do
        lines[index] = index % 2 == 1 and "dense_a dense_b dense_b" or "dense_a plain plain"
    end
    return lines, { "dense_a", "dense_b" }, line_count
end

local config = require("scrollbar.config")
local providers = require("scrollbar.providers")
local search = require("scrollbar.providers.search")
local store = require("scrollbar.store")
providers.register(search)

local active_sample
local last_publication_count
local original_store_set = store.set
local original_compact_set = store._set_search_compact

local function record_publication(started, finished, count, changed)
    last_publication_count = count
    if active_sample ~= nil and not active_sample.published then
        active_sample.published = true
        active_sample.match_count = count
        active_sample.publication_duration = (finished - started) / 1000000
        active_sample.publication_finished = finished
        active_sample.publication_changed = next(changed) ~= nil
    end
end

rawset(store, "set", function(provider, bufnr, marks)
    if provider ~= "search" then
        return original_store_set(provider, bufnr, marks)
    end

    local started = vim.uv.hrtime()
    local success, changed = original_store_set(provider, bufnr, marks)
    local finished = vim.uv.hrtime()
    record_publication(started, finished, #marks, changed)
    return success, changed
end)
rawset(store, "_set_search_compact", function(bufnr, compact)
    local started = vim.uv.hrtime()
    local success, changed = original_compact_set(bufnr, compact)
    local finished = vim.uv.hrtime()
    record_publication(started, finished, compact.count, changed)
    return success, changed
end)

local tick_count = 0
local last_tick = vim.uv.hrtime()
local timer = vim.uv.new_timer()
timer:start(timer_period_ms, timer_period_ms, function()
    local now = vim.uv.hrtime()
    tick_count = tick_count + 1
    if active_sample ~= nil then
        local gap = (now - last_tick) / 1000000
        active_sample.maximum_gap = math.max(active_sample.maximum_gap or 0, gap)
        if active_sample.phase ~= nil then
            active_sample.phase_gaps = active_sample.phase_gaps or {}
            active_sample.phase_gaps[active_sample.phase] =
                math.max(active_sample.phase_gaps[active_sample.phase] or 0, gap)
        end
    end
    last_tick = now
end)
assert(
    vim.wait(1000, function()
        return tick_count >= 2
    end, 1),
    "event-loop timer did not start"
)

local function callback(event)
    local autocmds = vim.api.nvim_get_autocmds({
        group = "ScrollbarProvider_search_events",
        event = event,
    })
    for _, autocmd in ipairs(autocmds) do
        if type(autocmd.callback) == "function" then
            return autocmd.callback
        end
    end
    error("search callback is unavailable")
end

local function setup_fixture(kind)
    providers.dispose()
    package.loaded["scrollbar.test.search_worker"] = { backend = "sync" }
    store.clear_provider("search")
    vim.fn.setreg("/", "")
    vim.cmd("nohlsearch")

    local lines, patterns, expected = fixture(kind)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local active_config = config.set({
        set_highlights = false,
        max_lines = false,
        providers = {
            cursor = false,
            diagnostic = false,
            gitsigns = false,
            search = { live = true },
            ale = false,
            coc = false,
        },
    })
    providers.setup({
        config = active_config,
        invalidate_buffer = function() end,
        source_windows = function(bufnr)
            if bufnr == nil or bufnr == vim.api.nvim_get_current_buf() then
                return { vim.api.nvim_get_current_win() }
            end
            return {}
        end,
    })
    return patterns, expected
end

local function activate(pattern)
    vim.fn.setreg("/", pattern)
    vim.v.hlsearch = 1
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    assert(vim.fn.search(pattern, "cw") > 0, "fixture pattern was not found")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function run_sample(trigger, expected_count)
    local previous_eventignore = vim.o.eventignore
    vim.o.eventignore = "all"
    active_sample = { maximum_gap = 0 }
    last_tick = vim.uv.hrtime()

    local started = vim.uv.hrtime()
    trigger()
    active_sample.callback_duration = (vim.uv.hrtime() - started) / 1000000
    assert(
        vim.wait(timeout_ms, function()
            return active_sample.published == true
        end, 1),
        "search result was not published"
    )

    active_sample.result_latency = (active_sample.publication_finished - started) / 1000000
    active_sample.publication_tick = tick_count
    assert(
        vim.wait(timeout_ms, function()
            return tick_count > active_sample.publication_tick
        end, 1),
        "event loop did not tick after publication"
    )
    active_sample.event_loop_delay = math.max(0, active_sample.maximum_gap - timer_period_ms)

    local result = active_sample
    active_sample = nil
    vim.o.eventignore = previous_eventignore
    assert(result.match_count == expected_count, "search fixture produced an unexpected match count")
    assert(result.publication_changed, "search benchmark must publish a changed result")
    return result
end

local function run_series(trigger_factory)
    local sequence = 0
    for _ = 1, warmup_count do
        sequence = sequence + 1
        local trigger, expected = trigger_factory(sequence)
        run_sample(trigger, expected)
    end

    collectgarbage("collect")
    local samples = {
        callback = {},
        latency = {},
        event_loop = {},
        publication = {},
    }
    local match_count
    for _ = 1, iteration_count do
        sequence = sequence + 1
        local trigger, expected = trigger_factory(sequence)
        local sample = run_sample(trigger, expected)
        match_count = sample.match_count
        table.insert(samples.callback, sample.callback_duration)
        table.insert(samples.latency, sample.result_latency)
        table.insert(samples.event_loop, sample.event_loop_delay)
        table.insert(samples.publication, sample.publication_duration)
    end
    return {
        matches = match_count,
        callback = statistics(samples.callback),
        latency = statistics(samples.latency),
        event_loop = statistics(samples.event_loop),
        publication = statistics(samples.publication),
    }
end

local results = {}
for _, kind in ipairs({ "sparse", "dense" }) do
    local patterns, expected = setup_fixture(kind)
    local leave = callback("CmdlineLeave")
    local accepted = run_series(function(index)
        local pattern = patterns[index % 2 + 1]
        activate(pattern)
        return function()
            leave({ match = "/" })
        end, expected
    end)
    table.insert(results, { trigger = "accepted", fixture = kind, result = accepted })

    patterns, expected = setup_fixture(kind)
    local changed = callback("CmdlineChanged")
    local live = run_series(function(index)
        local pattern = patterns[index % 2 + 1]
        return function()
            local original_getcmdline = vim.fn.getcmdline
            rawset(vim.fn, "getcmdline", function()
                return pattern
            end)
            changed()
            rawset(vim.fn, "getcmdline", original_getcmdline)
        end,
            expected
    end)
    table.insert(results, { trigger = "live", fixture = kind, result = live })

    patterns, expected = setup_fixture(kind)
    local pattern = patterns[1]
    activate(pattern)
    leave = callback("CmdlineLeave")
    leave({ match = "/" })
    assert(
        vim.wait(timeout_ms, function()
            return last_publication_count == expected
        end, 1),
        "initial edit benchmark search did not publish"
    )

    local text_changed = callback("TextChanged")
    local edit = run_series(function(index)
        local present = index % 2 == 0
        local replacement
        local expected_after_edit
        if kind == "sparse" then
            replacement = present and pattern .. " plain" or "plain plain"
            expected_after_edit = present and expected or expected - 1
        else
            replacement = present and pattern .. " plain plain" or "plain plain plain"
            expected_after_edit = present and expected or expected - 1
        end
        vim.api.nvim_buf_set_lines(0, line_count - 1, line_count, false, { replacement })
        return function()
            text_changed({ buf = vim.api.nvim_get_current_buf() })
        end,
            expected_after_edit
    end)
    table.insert(results, { trigger = "edit", fixture = kind, result = edit })
end

local function triplet(stats)
    return string.format("%.3f / %.3f / %.3f", stats.median, stats.p95, stats.maximum)
end

io.write("| Trigger | Fixture | Matches | Callback p50 / p95 / max | Result p50 / p95 / max | ")
io.write("Loop delay p50 / p95 / max | Publication p50 / p95 / max |\n")
io.write("| --- | --- | ---: | ---: | ---: | ---: | ---: |\n")
for _, row in ipairs(results) do
    local result = row.result
    io.write(
        string.format(
            "| %s | %s | %d | %s | %s | %s | %s |\n",
            row.trigger,
            row.fixture,
            result.matches,
            triplet(result.callback),
            triplet(result.latency),
            triplet(result.event_loop),
            triplet(result.publication)
        )
    )
end

local scheduler = require("scrollbar.scheduler")
local renderer = require("scrollbar.renderer")
local worker = require("scrollbar.providers.search_worker")

local worker_timing = {}

local function timing_event(event, payload)
    local sample = active_sample
    if sample == nil then
        return
    end
    payload = payload or {}
    local now = vim.uv.hrtime()
    if event == "startup_started" then
        sample.startup_started = now
    elseif event == "worker_ready" then
        sample.worker_ready = now
    elseif event == "snapshot_started" then
        sample.mirror_started = now
        sample.phase = "initial mirroring"
    elseif event == "snapshot_chunk" then
        sample.maximum_mirror_chunk = math.max(sample.maximum_mirror_chunk or 0, payload.duration_ms or 0)
    elseif event == "mirror_complete" then
        sample.mirror_finished = now
        if sample.mirror_started ~= nil then
            sample.initial_mirroring = (now - sample.mirror_started) / 1000000
        end
    elseif event == "delta_started" then
        sample.incremental_sync_started = now
        sample.phase = "incremental synchronization"
    elseif event == "delta_sent" then
        sample.incremental_parent = payload.duration_ms
    elseif event == "delta_complete" then
        sample.incremental_sync_finished = now
        if sample.incremental_sync_started ~= nil then
            sample.incremental_sync = (now - sample.incremental_sync_started) / 1000000
        end
    elseif event == "result_callback_started" then
        sample.result_callback_started = now
        sample.child_scan = payload.scan_duration_ms
        sample.payload_bytes = payload.compact and #payload.compact.data or 0
        sample.phase = "parent callback"
    elseif event == "result_callback_complete" then
        sample.result_callback_finished = now
        if sample.result_callback_started ~= nil then
            sample.parent_callback = (now - sample.result_callback_started) / 1000000
        end
        sample.phase = "awaiting render"
    elseif event == "mark_construction" then
        sample.mark_construction = payload.duration_ms
    elseif event == "set_marks" then
        sample.set_marks = payload.duration_ms
    elseif event == "scan_dispatched" then
        sample.phase = "child scan"
    elseif event == "sync_scan_started" then
        sample.phase = "synchronous fallback scan"
    elseif event == "sync_scan" then
        sample.sync_scan = payload.duration_ms
        sample.phase = "parent publication"
    end
end

local function finish_event_loop_sample(sample)
    local finished_tick = tick_count
    assert(
        vim.wait(timeout_ms, function()
            return tick_count > finished_tick
        end, 1),
        "event loop did not tick after benchmark sample"
    )
    sample.event_loop_delay = math.max(0, (sample.maximum_gap or 0) - timer_period_ms)
    local phase_gaps = sample.phase_gaps or {}
    if sample.mirror_started ~= nil then
        sample.mirror_loop_delay = math.max(0, (phase_gaps["initial mirroring"] or 0) - timer_period_ms)
    end
    if sample.child_scan ~= nil then
        sample.child_scan_loop_delay = math.max(0, (phase_gaps["child scan"] or 0) - timer_period_ms)
    end
end

local function read_rss_kib(pid)
    if type(pid) ~= "number" or pid <= 0 then
        return nil
    end
    local ok, lines = pcall(vim.fn.readfile, string.format("/proc/%d/status", pid))
    if not ok then
        return nil
    end
    for _, line in ipairs(lines) do
        local value = line:match("^VmRSS:%s+(%d+)%s+kB$")
        if value ~= nil then
            return tonumber(value)
        end
    end
end

local function configure_worker_fixture(kind, worker_test)
    providers.dispose()
    scheduler.dispose()
    renderer.dispose()
    store.clear_provider("search")
    vim.fn.setreg("/", "")
    vim.cmd("nohlsearch")

    local lines, patterns, expected = fixture(kind)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local active_config = config.set({
        set_highlights = false,
        max_lines = false,
        render = { interval_ms = 0, geometry = "line" },
        handle = { text = "H", hide_if_all_visible = false },
        providers = {
            cursor = false,
            diagnostic = false,
            gitsigns = false,
            search = { live = true },
            ale = false,
            coc = false,
        },
    })
    renderer.setup()
    local renderer_proxy = {
        is_owned_window = renderer.is_owned_window,
        source_windows = renderer.source_windows,
        render = function(winid)
            local started = vim.uv.hrtime()
            if active_sample ~= nil and active_sample.published and active_sample.render_finished == nil then
                active_sample.phase = "first render"
            end
            local state = renderer.render(winid)
            local finished = vim.uv.hrtime()
            if active_sample ~= nil and active_sample.published and active_sample.render_finished == nil then
                active_sample.first_render = (finished - started) / 1000000
                active_sample.render_finished = finished
                active_sample.phase = "idle"
            end
            return state
        end,
    }
    scheduler.setup({ config = active_config, renderer = renderer_proxy })
    renderer.render(vim.api.nvim_get_current_win())

    worker_test = worker_test or {}
    worker_test.backend = "worker"
    worker_test.timing = true
    worker_test.on_timing = timing_event
    package.loaded["scrollbar.test.search_worker"] = worker_test

    local setup_sample = { maximum_gap = 0, phase = "startup" }
    active_sample = setup_sample
    last_tick = vim.uv.hrtime()
    local setup_started = vim.uv.hrtime()
    providers.setup({
        config = active_config,
        invalidate_buffer = function(bufnr)
            local started = vim.uv.hrtime()
            scheduler.invalidate_buffer(bufnr)
            if active_sample ~= nil then
                active_sample.cache_invalidation = (vim.uv.hrtime() - started) / 1000000
            end
        end,
        source_windows = renderer.source_windows,
    })
    setup_sample.setup_call = (vim.uv.hrtime() - setup_started) / 1000000
    local expected_state = worker_test.fail_start and "failed" or "ready"
    assert(
        vim.wait(timeout_ms, function()
            return worker.status().state == expected_state
        end, 1),
        "worker did not reach expected startup state"
    )
    setup_sample.ready_latency = (vim.uv.hrtime() - setup_started) / 1000000
    finish_event_loop_sample(setup_sample)
    active_sample = nil
    return patterns, expected, setup_sample
end

local function dispose_worker_fixture()
    active_sample = nil
    providers.dispose()
    scheduler.dispose()
    renderer.dispose()
    package.loaded["scrollbar.test.search_worker"] = nil
end

local function run_publication_sample(trigger, expected_count, start_before_trigger)
    local previous_eventignore = vim.o.eventignore
    vim.o.eventignore = "all"
    local sample = { maximum_gap = 0 }
    active_sample = sample
    last_tick = vim.uv.hrtime()
    if start_before_trigger ~= nil then
        start_before_trigger()
    end
    local started = vim.uv.hrtime()
    trigger()
    sample.callback_duration = (vim.uv.hrtime() - started) / 1000000
    assert(
        vim.wait(timeout_ms, function()
            return sample.published == true and sample.render_finished ~= nil
        end, 1),
        "worker result was not rendered"
    )
    sample.result_latency = (sample.render_finished - started) / 1000000
    finish_event_loop_sample(sample)
    active_sample = nil
    vim.o.eventignore = previous_eventignore
    assert(sample.match_count == expected_count, "worker fixture produced an unexpected match count")
    assert(sample.publication_changed, "worker benchmark must publish a changed result")
    return sample
end

local worker_fields = {
    "callback_duration",
    "result_latency",
    "event_loop_delay",
    "initial_mirroring",
    "maximum_mirror_chunk",
    "mirror_loop_delay",
    "incremental_sync",
    "incremental_parent",
    "child_scan",
    "child_scan_loop_delay",
    "sync_scan",
    "parent_callback",
    "payload_bytes",
    "mark_construction",
    "publication_duration",
    "cache_invalidation",
    "first_render",
}

local function new_worker_samples()
    local samples = {}
    for _, field in ipairs(worker_fields) do
        samples[field] = {}
    end
    return samples
end

local function add_worker_sample(samples, sample)
    for _, field in ipairs(worker_fields) do
        if sample[field] ~= nil then
            table.insert(samples[field], sample[field])
        end
    end
end

local function summarize_worker_samples(samples)
    local summary = {}
    for _, field in ipairs(worker_fields) do
        if #samples[field] > 0 then
            summary[field] = statistics(samples[field])
        end
    end
    return summary
end

local function run_cold_worker_series(kind)
    local samples = new_worker_samples()
    local startup = { setup_call = {}, ready_latency = {}, event_loop_delay = {} }
    local memory = { parent = {}, worker = {} }
    local match_count
    for index = 1, worker_warmup_count + worker_iteration_count do
        local patterns, expected, setup_sample = configure_worker_fixture(kind)
        local pattern = patterns[index % 2 + 1]
        activate(pattern)
        local leave = callback("CmdlineLeave")
        local sample = run_publication_sample(function()
            leave({ match = "/" })
        end, expected)
        if index > worker_warmup_count then
            add_worker_sample(samples, sample)
            table.insert(startup.setup_call, setup_sample.setup_call)
            table.insert(startup.ready_latency, setup_sample.ready_latency)
            table.insert(startup.event_loop_delay, setup_sample.event_loop_delay)
            local status = worker.status()
            local child_pid = status.job_id and vim.fn.jobpid(status.job_id) or nil
            local parent_rss = read_rss_kib(vim.fn.getpid())
            local worker_rss = read_rss_kib(child_pid)
            if parent_rss ~= nil then
                table.insert(memory.parent, parent_rss)
            end
            if worker_rss ~= nil then
                table.insert(memory.worker, worker_rss)
            end
            match_count = sample.match_count
        end
        dispose_worker_fixture()
    end
    return {
        scenario = "cold accepted",
        fixture = kind,
        matches = match_count,
        phases = summarize_worker_samples(samples),
        startup = {
            setup_call = statistics(startup.setup_call),
            ready_latency = statistics(startup.ready_latency),
            event_loop_delay = statistics(startup.event_loop_delay),
        },
        memory = {
            parent = #memory.parent > 0 and statistics(memory.parent) or nil,
            worker = #memory.worker > 0 and statistics(memory.worker) or nil,
        },
    }
end

local function prime_worker(pattern, expected)
    activate(pattern)
    local leave = callback("CmdlineLeave")
    local sample = run_publication_sample(function()
        leave({ match = "/" })
    end, expected)
    assert(sample.child_scan ~= nil, "worker prime request did not use the worker")
end

local function run_incremental_worker_series(kind)
    local patterns, expected = configure_worker_fixture(kind)
    local pattern = patterns[1]
    prime_worker(pattern, expected)
    local text_changed = callback("TextChanged")
    local samples = new_worker_samples()
    local match_count
    for index = 1, worker_warmup_count + worker_iteration_count do
        local present = index % 2 == 0
        local replacement = present and pattern .. " plain plain" or "plain plain plain"
        local expected_after_edit = present and expected or expected - 1
        local sample = run_publication_sample(
            function()
                text_changed({ buf = vim.api.nvim_get_current_buf() })
            end,
            expected_after_edit,
            function()
                vim.api.nvim_buf_set_lines(0, line_count - 1, line_count, false, { replacement })
            end
        )
        if index > worker_warmup_count then
            add_worker_sample(samples, sample)
            match_count = sample.match_count
        end
    end
    dispose_worker_fixture()
    return {
        scenario = "incremental edit",
        fixture = kind,
        matches = match_count,
        phases = summarize_worker_samples(samples),
    }
end

local function run_fallback_series(kind)
    local patterns, expected = configure_worker_fixture(kind, { fail_start = true })
    local leave = callback("CmdlineLeave")
    local samples = new_worker_samples()
    local match_count
    for index = 1, worker_warmup_count + worker_iteration_count do
        local pattern = patterns[index % 2 + 1]
        activate(pattern)
        local sample = run_publication_sample(function()
            leave({ match = "/" })
        end, expected)
        if index > worker_warmup_count then
            add_worker_sample(samples, sample)
            match_count = sample.match_count
        end
    end
    dispose_worker_fixture()
    return {
        scenario = "startup-failure fallback",
        fixture = kind,
        matches = match_count,
        phases = summarize_worker_samples(samples),
    }
end

for _, kind in ipairs({ "sparse", "dense" }) do
    table.insert(worker_timing, run_cold_worker_series(kind))
    table.insert(worker_timing, run_incremental_worker_series(kind))
    table.insert(worker_timing, run_fallback_series(kind))
end

local function optional_triplet(stats)
    return stats and triplet(stats) or "-"
end

io.write("\n## Worker startup\n\n")
io.write("| Fixture | Setup call p50 / p95 / max | Ready p50 / p95 / max | Loop delay p50 / p95 / max |\n")
io.write("| --- | ---: | ---: | ---: |\n")
for _, row in ipairs(worker_timing) do
    if row.startup ~= nil then
        io.write(
            string.format(
                "| %s | %s | %s | %s |\n",
                row.fixture,
                triplet(row.startup.setup_call),
                triplet(row.startup.ready_latency),
                triplet(row.startup.event_loop_delay)
            )
        )
    end
end

io.write("\n## Worker end-to-end\n\n")
io.write("| Scenario | Fixture | Matches | Payload bytes | Callback p50 / p95 / max | Result p50 / p95 / max | ")
io.write("Loop delay p50 / p95 / max |\n")
io.write("| --- | --- | ---: | ---: | ---: | ---: | ---: |\n")
for _, row in ipairs(worker_timing) do
    io.write(
        string.format(
            "| %s | %s | %d | %s | %s | %s | %s |\n",
            row.scenario,
            row.fixture,
            row.matches,
            row.phases.payload_bytes and string.format("%.0f", row.phases.payload_bytes.median) or "-",
            optional_triplet(row.phases.callback_duration),
            optional_triplet(row.phases.result_latency),
            optional_triplet(row.phases.event_loop_delay)
        )
    )
end

local phase_labels = {
    { "initial_mirroring", "initial mirroring" },
    { "maximum_mirror_chunk", "maximum parent mirror chunk" },
    { "mirror_loop_delay", "parent loop delay during mirroring" },
    { "incremental_sync", "incremental synchronization" },
    { "incremental_parent", "incremental parent callback" },
    { "child_scan", "child scan" },
    { "child_scan_loop_delay", "parent loop delay during child scan" },
    { "sync_scan", "synchronous fallback scan" },
    { "parent_callback", "parent RPC receipt/callback" },
    { "mark_construction", "mark construction" },
    { "publication_duration", "store publication" },
    { "cache_invalidation", "cache invalidation/queue" },
    { "first_render", "first render" },
}
io.write("\n## Worker phases\n\n")
io.write("| Scenario | Fixture | Phase | p50 / p95 / max |\n")
io.write("| --- | --- | --- | ---: |\n")
for _, row in ipairs(worker_timing) do
    for _, phase in ipairs(phase_labels) do
        if row.phases[phase[1]] ~= nil then
            io.write(
                string.format(
                    "| %s | %s | %s | %s |\n",
                    row.scenario,
                    row.fixture,
                    phase[2],
                    triplet(row.phases[phase[1]])
                )
            )
        end
    end
end

io.write("\n## Idle process memory\n\n")
io.write("| Fixture | Parent RSS KiB p50 / p95 / max | Worker RSS KiB p50 / p95 / max |\n")
io.write("| --- | ---: | ---: |\n")
for _, row in ipairs(worker_timing) do
    if row.memory ~= nil then
        io.write(
            string.format(
                "| %s | %s | %s |\n",
                row.fixture,
                optional_triplet(row.memory.parent),
                optional_triplet(row.memory.worker)
            )
        )
    end
end

timer:stop()
timer:close()
providers.dispose()
scheduler.dispose()
renderer.dispose()
rawset(store, "set", original_store_set)
rawset(store, "_set_search_compact", original_compact_set)
vim.cmd("qa!")
