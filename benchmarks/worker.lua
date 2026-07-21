local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.lines = 48
vim.o.columns = 120
vim.o.swapfile = false

local warmup_count = 5
local iteration_count = 20
local worker_warmup_count = 2
local worker_iteration_count = 8
local worker_ready_timeout_ms = 10000
local worker_result_timeout_ms = 30000
local semantic_enabled = vim.env.SCROLLBAR_BENCHMARK_SEMANTIC == "1"

local function percentile(sorted, fraction)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function statistics(samples)
    if #samples == 0 then
        return { median = 0, p95 = 0, maximum = 0 }
    end
    table.sort(samples)
    return {
        median = percentile(samples, 0.5),
        p95 = percentile(samples, 0.95),
        maximum = samples[#samples],
    }
end

local function make_lines(count)
    local lines = {}
    for index = 1, count do
        lines[index] = string.format("local value_%d = %d", index, index * 2)
    end
    return lines
end

local function make_semantic_spans(line_count)
    if not semantic_enabled then
        return {}
    end
    local spans = {}
    for line = 0, line_count - 1, 5 do
        spans[#spans + 1] = {
            line = line,
            start_col = 0,
            end_col = 12,
            highlight = "@variable",
            priority = 200,
        }
    end
    return spans
end

local function fresh_buffer(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
end

local function setup_worker(backend, on_timing)
    local worker = require("scrollbar.minimap.worker")
    worker.setup({
        backend = backend,
        treesitter = semantic_enabled,
        on_result = function(payload)
            require("scrollbar.minimap.renderer").handle_worker_result(payload)
        end,
        test = { on_timing = on_timing },
    })
    return worker
end

local function wait_for_worker_ready(worker)
    local ok = vim.wait(worker_ready_timeout_ms, function()
        return worker.status().state == "ready"
    end, 10)
    if not ok then
        error("minimap worker failed to reach ready state: " .. worker.status().state)
    end
end

local function dispose_worker(worker)
    local job_id = worker.status().job_id
    worker.dispose()
    if job_id ~= nil then
        vim.fn.jobwait({ job_id }, 1000)
    end
end

local function measure_sync(label, line_count)
    local lines = make_lines(line_count)
    local semantic_spans = make_semantic_spans(line_count)
    local buf = fresh_buffer(lines)
    local worker = setup_worker("sync")
    local original = require("scrollbar.minimap.renderer").handle_worker_result
    ---@diagnostic disable-next-line: duplicate-set-field
    require("scrollbar.minimap.renderer").handle_worker_result = function(_) end

    for _ = 1, warmup_count do
        worker.request({
            bufnr = buf,
            width = 80,
            height = 24,
            filetype = "lua",
            generation = 1,
            signature = label,
            semantic_revision = semantic_enabled and 1 or 0,
            semantic_spans = { benchmark_parent = semantic_spans },
        })
    end

    collectgarbage("collect")
    local dispatch_samples = {}
    local roundtrip_samples = {}
    for _ = 1, iteration_count do
        local started = vim.uv.hrtime()
        worker.request({
            bufnr = buf,
            width = 80,
            height = 24,
            filetype = "lua",
            generation = 1,
            signature = label,
            semantic_revision = semantic_enabled and 1 or 0,
            semantic_spans = { benchmark_parent = semantic_spans },
        })
        local dispatch_cost = vim.uv.hrtime() - started
        dispatch_samples[#dispatch_samples + 1] = dispatch_cost
        roundtrip_samples[#roundtrip_samples + 1] = dispatch_cost
    end

    require("scrollbar.minimap.renderer").handle_worker_result = original
    dispose_worker(worker)
    vim.api.nvim_buf_delete(buf, { force = true })
    return {
        dispatch = statistics(dispatch_samples),
        roundtrip = statistics(roundtrip_samples),
    }
end

local function measure_worker(worker, label, line_count)
    local lines = make_lines(line_count)
    local semantic_spans = make_semantic_spans(line_count)
    local buf = fresh_buffer(lines)
    local received
    local original = require("scrollbar.minimap.renderer").handle_worker_result
    ---@diagnostic disable-next-line: duplicate-set-field
    require("scrollbar.minimap.renderer").handle_worker_result = function(payload)
        received = payload
    end

    for _ = 1, worker_warmup_count do
        received = nil
        worker.request({
            bufnr = buf,
            width = 80,
            height = 24,
            filetype = "lua",
            generation = 1,
            signature = label,
            semantic_revision = semantic_enabled and 1 or 0,
            semantic_spans = { benchmark_parent = semantic_spans },
        })
        vim.wait(worker_result_timeout_ms, function()
            return received ~= nil
        end, 10)
    end

    collectgarbage("collect")
    local dispatch_samples = {}
    local roundtrip_samples = {}
    for _ = 1, worker_iteration_count do
        received = nil
        local started = vim.uv.hrtime()
        worker.request({
            bufnr = buf,
            width = 80,
            height = 24,
            filetype = "lua",
            generation = 1,
            signature = label,
            semantic_revision = semantic_enabled and 1 or 0,
            semantic_spans = { benchmark_parent = semantic_spans },
        })
        dispatch_samples[#dispatch_samples + 1] = vim.uv.hrtime() - started
        vim.wait(worker_result_timeout_ms, function()
            return received ~= nil
        end, 10)
        roundtrip_samples[#roundtrip_samples + 1] = vim.uv.hrtime() - started
    end

    require("scrollbar.minimap.renderer").handle_worker_result = original
    worker.detach_buffer(buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    return {
        dispatch = statistics(dispatch_samples),
        roundtrip = statistics(roundtrip_samples),
    }
end

local line_counts = { 1000, 10000, 50000 }
local sync_results = {}
local worker_results = {}
local semantic_snapshot_sends = 0
local worker = setup_worker("worker", function(event)
    if event == "semantic_snapshot_sent" then
        semantic_snapshot_sends = semantic_snapshot_sends + 1
    end
end)
wait_for_worker_ready(worker)
for _, count in ipairs(line_counts) do
    local previous_sends = semantic_snapshot_sends
    worker_results[count] = measure_worker(worker, "worker " .. count, count)
    worker_results[count].semantic_snapshot_sends = semantic_snapshot_sends - previous_sends
end
dispose_worker(worker)
for _, count in ipairs(line_counts) do
    sync_results[count] = measure_sync("sync " .. count, count)
end

local function write_table(headers, rows)
    io.write("| " .. table.concat(headers, " | ") .. " |\n")
    io.write("| " .. table.concat(
        vim.tbl_map(function()
            return "---"
        end, headers),
        " | "
    ) .. " |\n")
    for _, row in ipairs(rows) do
        io.write("| " .. table.concat(row, " | ") .. " |\n")
    end
end

local function us(value)
    return string.format("%.1f", value / 1000)
end

io.write("\n## Main-loop blocking per squash request (microseconds)\n\n")
io.write(string.format("Mode: %s\n\n", semantic_enabled and "semantic-enabled" or "semantic-disabled"))
io.write("Time the main thread is blocked inside `worker.request()`.\n")
io.write("Sync runs the full squash inline; worker only dispatches the RPC\n")
io.write("and returns. This is what typing latency actually feels like.\n\n")

local rows = {}
for _, count in ipairs(line_counts) do
    rows[#rows + 1] = {
        tostring(count),
        us(sync_results[count].dispatch.median),
        us(sync_results[count].dispatch.p95),
        us(worker_results[count].dispatch.median),
        us(worker_results[count].dispatch.p95),
    }
end
write_table({
    "Lines",
    "sync p50",
    "sync p95",
    "worker p50",
    "worker p95",
}, rows)

io.write("\n## End-to-end round-trip (microseconds)\n\n")
io.write("From `worker.request()` start until the result lands. For the worker\n")
io.write("this includes the RPC round-trip + child-side squash, but the main\n")
io.write("loop is free during that gap.\n\n")

local rows2 = {}
for _, count in ipairs(line_counts) do
    rows2[#rows2 + 1] = {
        tostring(count),
        us(sync_results[count].roundtrip.median),
        us(sync_results[count].roundtrip.p95),
        us(worker_results[count].roundtrip.median),
        us(worker_results[count].roundtrip.p95),
    }
end
write_table({
    "Lines",
    "sync p50",
    "sync p95",
    "worker p50",
    "worker p95",
}, rows2)

if semantic_enabled then
    io.write("\n## Parent semantic snapshot reuse\n\n")
    local semantic_rows = {}
    for _, count in ipairs(line_counts) do
        semantic_rows[#semantic_rows + 1] = {
            tostring(count),
            tostring(worker_results[count].semantic_snapshot_sends),
            tostring(worker_warmup_count + worker_iteration_count),
        }
    end
    write_table({ "Lines", "Snapshot sends", "Requests" }, semantic_rows)
end

io.write("\nAll values in microseconds (lower is better).\n")
