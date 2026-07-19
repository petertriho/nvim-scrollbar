-- Benchmark: per-call cost of the work the marks provider does inside its
-- SafeState reconcile callback (reconcile_source_buffers + collect in
-- lua/scrollbar/providers/marks.lua). The cost scales with the number of
-- unique buffers visible across source windows; this benchmark measures
-- per-call latency across a configurable set of buffer counts and projects
-- total overhead at typical SafeState fire rates.
--
-- Run with: make benchmark-marks
-- Or:       nvim --headless --noplugin -u NONE -l benchmarks/marks_reconcile.lua [counts...]

local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.lines = 48
vim.o.columns = 120
vim.o.swapfile = false

local line_count = 50000
local warmup_count = 200
local iteration_count = 2000

local default_buffer_counts = { 1, 3, 8, 16 }
local buffer_counts = {}
for _, value in ipairs(arg or {}) do
    local n = tonumber(value)
    if n ~= nil and n >= 1 then
        table.insert(buffer_counts, math.floor(n))
    end
end
if #buffer_counts == 0 then
    buffer_counts = default_buffer_counts
end

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

-- Build a fixture with `buffer_count` unique buffers visible, each with the
-- same line layout and a representative set of letter marks. Mirrors what
-- collect() walks in providers/marks.lua.
local function plant_marks(buf)
    local positions = { 100, 500, 5000, 10000, 25000, 40000 }
    local names = { "a", "b", "c", "d", "e", "f" }
    for index = 1, #names do
        vim.api.nvim_buf_set_mark(buf, names[index], positions[index], 0, {})
    end
end

local function make_session(buffer_count)
    local wins = { vim.api.nvim_get_current_win() }
    local lines = {}
    for i = 1, line_count do
        lines[i] = string.format("benchmark line %d", i)
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    plant_marks(0)
    for _ = 2, buffer_count do
        vim.cmd("vsplit")
        local win = vim.api.nvim_get_current_win()
        table.insert(wins, win)
        vim.cmd("enew")
        local buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        plant_marks(buf)
    end
    return wins
end

-- Mirror marks.lua reconcile_source_buffers + collect: walk windows, dedup
-- by buffer, query line count and every letter mark per unique buffer.
local function reconcile_like_marks()
    local seen = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            if not seen[buf] then
                seen[buf] = true
                vim.api.nvim_buf_line_count(buf)
                for byte = string.byte("a"), string.byte("z") do
                    vim.api.nvim_buf_get_mark(buf, string.char(byte))
                end
                for byte = string.byte("A"), string.byte("Z") do
                    pcall(vim.api.nvim_get_mark, string.char(byte), {})
                end
            end
        end
    end
end

local function reset_session()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if win ~= vim.api.nvim_get_current_win() and vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if buf ~= 0 and buf ~= vim.api.nvim_get_current_buf() and vim.api.nvim_buf_is_loaded(buf) then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
    end
end

local function measure(buffer_count)
    reset_session()
    make_session(buffer_count)

    for _ = 1, warmup_count do
        reconcile_like_marks()
    end
    collectgarbage("collect")

    local samples = {}
    for index = 1, iteration_count do
        local started = vim.uv.hrtime()
        reconcile_like_marks()
        samples[index] = (vim.uv.hrtime() - started) / 1e6
    end
    return {
        unique_buffers = buffer_count,
        statistics = statistics(samples),
    }
end

local results = {}
for _, count in ipairs(buffer_counts) do
    table.insert(results, measure(count))
end

io.write("## Per-call cost of marks-provider reconcile (mirrors SafeState callback)\n\n")
io.write("| Unique source buffers | Median (p50) | p95 | Maximum |\n")
io.write("| ---: | ---: | ---: | ---: |\n")
for _, result in ipairs(results) do
    local stats = result.statistics
    io.write(
        string.format("| %d | %.4f | %.4f | %.4f |\n", result.unique_buffers, stats.median, stats.p95, stats.maximum)
    )
end

io.write("\n## Projected overhead at typical SafeState fire rates\n\n")
io.write("Projected overhead = fires/sec * median ms/call. At 60 Hz (16.67 ms\n")
io.write("frame budget), 1 ms/sec of overhead is roughly 0.06 ms/frame.\n\n")
io.write("| Unique source buffers | 5 fires/s | 15 fires/s | 30 fires/s |\n")
io.write("| ---: | ---: | ---: | ---: |\n")
for _, result in ipairs(results) do
    local median = result.statistics.median
    io.write(
        string.format(
            "| %d | %.3f ms/s | %.3f ms/s | %.3f ms/s |\n",
            result.unique_buffers,
            5 * median,
            15 * median,
            30 * median
        )
    )
end

vim.cmd("qa!")
