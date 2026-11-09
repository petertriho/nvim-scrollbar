-- Benchmark: the cost per call of the reconcile of the marks provider
-- (reconcile_source_buffers in lua/scrollbar/providers/marks.lua). The provider
-- runs it on MarkSet, and also on SafeState when Neovim is older than 0.12.2 or
-- the `numbers` option is on. For each unique buffer that a window shows, the
-- benchmark runs the real collect() through the refresh() export. A stub
-- context skips the eligibility check and the publication to the store.
-- The cost scales with the number of unique buffers that are visible in source
-- windows. This benchmark measures the latency per call for a configurable set
-- of buffer counts. It also projects the overhead of the SafeState fallback at
-- typing rates.
--
-- Run with: make benchmark-marks
-- Or:       nvim --headless --noplugin -u NONE -l benchmarks/reports/marks_reconcile.lua [counts...]

local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h:h")
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

-- The provider context that collect() reads. The marks options come from the
-- default provider plan, so the benchmark follows the default `letters` and
-- `numbers` options.
require("scrollbar.config").set({})
local marks_provider = require("scrollbar.providers.marks")
local context = {
    config = {
        providers = {
            marks = vim.deepcopy(
                require("scrollbar.config").get_provider_plan().marks.options --[[@as ScrollbarMarksProviderConfig]]
            ),
        },
    },
    is_buffer_eligible = function()
        return true
    end,
    clear_marks = function() end,
}

local mark_positions = { 100, 500, 5000, 10000, 25000, 40000 }
local mark_names = { "a", "b", "c", "d", "e", "f" }

-- Set a representative set of letter marks, like the data that collect() walks
-- in providers/marks.lua.
local function plant_marks(buf)
    for index = 1, #mark_names do
        vim.api.nvim_buf_set_mark(buf, mark_names[index], mark_positions[index], 0, {})
    end
end

-- Build a fixture with `buffer_count` unique visible buffers. Each buffer has
-- the same line layout and the letter marks of plant_marks().
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

-- Mirror reconcile_source_buffers and update in marks.lua. Walk the windows and
-- dedup them by buffer. For each unique buffer, query the line count and run
-- the real collect() through refresh(). The result is not published.
local function reconcile_marks()
    local seen = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local buf = vim.api.nvim_win_get_buf(win)
            if not seen[buf] then
                seen[buf] = true
                if vim.api.nvim_buf_is_valid(buf) then
                    vim.api.nvim_buf_line_count(buf)
                    marks_provider.refresh(buf, context)
                end
            end
        end
    end
end

-- Stop the benchmark if collect() does not return every planted mark of each
-- buffer. Without this check, a context that disables the provider measures no
-- work and still prints plausible numbers.
local function assert_collect_finds_marks()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local marks = marks_provider.refresh(buf, context) or {}
        assert(
            #marks == #mark_names,
            string.format("buffer %d: collect() returned %d marks, expected %d", buf, #marks, #mark_names)
        )
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
    assert_collect_finds_marks()

    for _ = 1, warmup_count do
        reconcile_marks()
    end
    collectgarbage("collect")

    local samples = {}
    for index = 1, iteration_count do
        local started = vim.uv.hrtime()
        reconcile_marks()
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

io.write("## Per-call cost of the marks reconcile (reconcile_source_buffers)\n\n")
io.write("| Unique source buffers | Median (p50) | p95 | Maximum |\n")
io.write("| ---: | ---: | ---: | ---: |\n")
for _, result in ipairs(results) do
    local stats = result.statistics
    io.write(
        string.format("| %d | %.4f | %.4f | %.4f |\n", result.unique_buffers, stats.median, stats.p95, stats.maximum)
    )
end

io.write("\n## Projected overhead of the SafeState fallback\n\n")
io.write("The provider reconciles on SafeState only on Neovim older than 0.12.2\n")
io.write("or with `numbers = true`. SafeState fires about once per keystroke, so\n")
io.write("the rates below are typing rates. On Neovim 0.12.2 or later with the\n")
io.write("default options, the reconcile runs only on MarkSet, at the rate of mark\n")
io.write("commands. A text change that changes the line count updates only its\n")
io.write("own buffer.\n\n")
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
