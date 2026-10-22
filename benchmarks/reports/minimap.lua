local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h:h")
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

local function configure(minimap_overrides)
    minimap_overrides = vim.deepcopy(minimap_overrides or {})
    require("scrollbar.config").set({
        set_highlights = false,
        providers = {
            treesitter = semantic_enabled,
            lsp_semantic_tokens = semantic_enabled,
        },
        minimap = vim.tbl_extend("keep", minimap_overrides, {
            enabled = true,
        }),
    })
end

--- Grid of a 24-row, 80-cell float whose source window starts in the middle
--- of the buffer. `fit` squashes the whole buffer, which matches the cost of
--- the full-buffer squash. `fixed` squashes the slice around the visible rows.
local function request_grid(line_count, scale)
    local projection = require("scrollbar.minimap.projection")
    local top = math.floor(line_count / 2)
    local view = projection.new({
        scale = scale or "fit",
        line_count = line_count,
        rows = 24,
        width = 80,
        columns_per_dot = 4,
        top = top,
        bottom = math.min(line_count - 1, top + 23),
    })
    local first_row, row_count = projection.slice(view)
    return {
        width = 80,
        first_row = first_row,
        row_count = row_count,
        scale_lines = view.scale_lines,
        scale_dots = view.scale_dots,
        columns_per_dot = 4,
        encoding = "braille",
    }
end

local function fresh_buffer(lines)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    return buf
end

--- The minimap skips floating windows, so the render benchmarks use a split.
local function open_source_window(buf)
    vim.cmd("botright vsplit")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, buf)
    return winid
end

local function setup_worker(backend)
    local worker = require("scrollbar.minimap.worker")
    worker.setup({
        backend = backend,
        treesitter = semantic_enabled,
        on_result = function(payload)
            require("scrollbar.minimap.renderer").handle_worker_result(payload)
        end,
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

local function measure_squash(label, source_line_counts, scale)
    local squash = require("scrollbar.minimap.squash")
    local results = {}
    for _, count in ipairs(source_line_counts) do
        local grid = request_grid(count, scale)
        local first, last = squash.line_range(grid, count)
        local lines = vim.list_slice(make_lines(count), first + 1, last)
        local samples = {}
        for _ = 1, warmup_count do
            squash.squash(lines, first, grid)
        end
        collectgarbage("collect")
        for _ = 1, iteration_count do
            local started = vim.uv.hrtime()
            squash.squash(lines, first, grid)
            samples[#samples + 1] = (vim.uv.hrtime() - started) / 1000000
        end
        results[#results + 1] = { line_count = count, statistics = statistics(samples) }
    end
    return { label = label, cases = results }
end

local function measure_ratios(label, ratio_cases)
    local squash = require("scrollbar.minimap.squash")
    local results = {}
    for _, case in ipairs(ratio_cases) do
        local lines = make_lines(case.source_lines)
        local grid = request_grid(case.source_lines)
        local samples = {}
        for _ = 1, warmup_count do
            squash.squash(lines, 0, grid)
        end
        collectgarbage("collect")
        for _ = 1, iteration_count do
            local started = vim.uv.hrtime()
            squash.squash(lines, 0, grid)
            samples[#samples + 1] = (vim.uv.hrtime() - started) / 1000000
        end
        results[#results + 1] = vim.tbl_extend("keep", case, { statistics = statistics(samples) })
    end
    return { label = label, cases = results }
end

local function measure_backend_parity(line_count)
    local lines = make_lines(line_count)
    local semantic_spans = make_semantic_spans(line_count)
    local buf = fresh_buffer(lines)
    local sync_worker = setup_worker("sync")
    local sync_cells
    local original_handler = require("scrollbar.minimap.renderer").handle_worker_result
    ---@diagnostic disable-next-line: duplicate-set-field
    require("scrollbar.minimap.renderer").handle_worker_result = function(payload)
        sync_cells = payload.cells
    end
    sync_worker.request({
        bufnr = buf,
        grid = request_grid(line_count),
        filetype = "lua",
        generation = 1,
        signature = "parity",
        semantic_revision = semantic_enabled and 1 or 0,
        semantic_spans = { benchmark_parent = semantic_spans },
    })
    require("scrollbar.minimap.renderer").handle_worker_result = original_handler
    dispose_worker(sync_worker)

    local worker = setup_worker("worker")
    wait_for_worker_ready(worker)
    local worker_cells
    ---@diagnostic disable-next-line: duplicate-set-field
    require("scrollbar.minimap.renderer").handle_worker_result = function(payload)
        worker_cells = payload.cells
    end
    worker.request({
        bufnr = buf,
        grid = request_grid(line_count),
        filetype = "lua",
        generation = 1,
        signature = "parity",
        semantic_revision = semantic_enabled and 1 or 0,
        semantic_spans = { benchmark_parent = semantic_spans },
    })
    vim.wait(worker_result_timeout_ms, function()
        return worker_cells ~= nil
    end, 10)
    require("scrollbar.minimap.renderer").handle_worker_result = original_handler
    dispose_worker(worker)

    local identical = sync_cells ~= nil and worker_cells ~= nil and #sync_cells == #worker_cells
    if identical then
        for row = 1, #sync_cells do
            if #sync_cells[row] ~= #worker_cells[row] then
                identical = false
                break
            end
            for col = 1, #sync_cells[row] do
                if
                    sync_cells[row][col].char ~= worker_cells[row][col].char
                    or sync_cells[row][col].hl_group ~= worker_cells[row][col].hl_group
                then
                    identical = false
                    break
                end
            end
            if not identical then
                break
            end
        end
    end

    vim.api.nvim_buf_delete(buf, { force = true })
    return identical
end

local function measure_backend_walltime(label, backend, line_count, scale)
    local lines = make_lines(line_count)
    local semantic_spans = make_semantic_spans(line_count)
    local buf = fresh_buffer(lines)
    local worker = setup_worker(backend)
    if backend == "worker" then
        wait_for_worker_ready(worker)
    end
    local received
    local original = require("scrollbar.minimap.renderer").handle_worker_result
    ---@diagnostic disable-next-line: duplicate-set-field
    require("scrollbar.minimap.renderer").handle_worker_result = function(payload)
        received = payload
    end

    local iterations = backend == "worker" and worker_iteration_count or iteration_count
    local warmups = backend == "worker" and worker_warmup_count or warmup_count
    for _ = 1, warmups do
        received = nil
        worker.request({
            bufnr = buf,
            grid = request_grid(line_count, scale),
            filetype = "lua",
            generation = 1,
            signature = label,
            semantic_revision = semantic_enabled and 1 or 0,
            semantic_spans = { benchmark_parent = semantic_spans },
        })
        if backend == "worker" then
            vim.wait(worker_result_timeout_ms, function()
                return received ~= nil
            end, 10)
        end
    end

    collectgarbage("collect")
    local samples = {}
    for _ = 1, iterations do
        received = nil
        local started = vim.uv.hrtime()
        worker.request({
            bufnr = buf,
            grid = request_grid(line_count, scale),
            filetype = "lua",
            generation = 1,
            signature = label,
            semantic_revision = semantic_enabled and 1 or 0,
            semantic_spans = { benchmark_parent = semantic_spans },
        })
        if backend == "worker" then
            vim.wait(worker_result_timeout_ms, function()
                return received ~= nil
            end, 10)
        end
        samples[#samples + 1] = (vim.uv.hrtime() - started) / 1000000
    end
    require("scrollbar.minimap.renderer").handle_worker_result = original
    dispose_worker(worker)
    vim.api.nvim_buf_delete(buf, { force = true })
    return statistics(samples)
end

local function measure_render(_label, line_count, options)
    options = options or {}
    local lines = make_lines(line_count)
    local buf = fresh_buffer(lines)
    local source_win = open_source_window(buf)
    configure({
        backend = "sync",
        width = 80,
        height = 24,
        marks = options.overlays ~= false and {} or false,
        viewport = true,
        scale = options.scale,
    })
    local worker = setup_worker("sync")
    local overlays = require("scrollbar.minimap.overlays")
    overlays.setup({ config = require("scrollbar.minimap.config").get() })
    local renderer = require("scrollbar.minimap.renderer")
    renderer.setup({ worker = worker, overlays = overlays })

    if options.overlays ~= false then
        local store = require("scrollbar.shared.store")
        local marks = {}
        for index = 0, math.min(line_count - 1, 200) do
            marks[#marks + 1] = { line = index, type = "Error" }
        end
        store.set("diagnostic", buf, marks)
    end
    if semantic_enabled then
        require("scrollbar.shared.store").set_minimap_spans("lsp_semantic_tokens", buf, make_semantic_spans(line_count))
    end

    -- Warm up the renderer cache.
    renderer.render(source_win)
    renderer.render(source_win)

    collectgarbage("collect")
    local samples = {}
    for _ = 1, iteration_count do
        local started = vim.uv.hrtime()
        renderer.render(source_win)
        samples[#samples + 1] = (vim.uv.hrtime() - started) / 1000000
    end
    local stats = statistics(samples)

    renderer.dispose()
    overlays.dispose()
    dispose_worker(worker)
    pcall(vim.api.nvim_win_close, source_win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return stats
end

--- Render cost while the source window scrolls one page per render in the
--- fixed scale. The renderer requests a new slice when the margin runs low.
local function measure_scroll(line_count)
    local lines = make_lines(line_count)
    local buf = fresh_buffer(lines)
    local source_win = open_source_window(buf)
    configure({
        backend = "sync",
        width = 80,
        height = 24,
        viewport = true,
    })
    local worker = setup_worker("sync")
    local overlays = require("scrollbar.minimap.overlays")
    overlays.setup({ config = require("scrollbar.minimap.config").get() })
    local renderer = require("scrollbar.minimap.renderer")
    renderer.setup({ worker = worker, overlays = overlays })

    local function scroll_to(topline)
        vim.api.nvim_win_call(source_win, function()
            vim.fn.winrestview({ topline = topline, lnum = topline })
        end)
    end

    scroll_to(1)
    renderer.render(source_win)
    collectgarbage("collect")
    local samples = {}
    local topline = 1
    for _ = 1, iteration_count * 5 do
        topline = topline + 24
        if topline > line_count - 24 then
            topline = 1
        end
        scroll_to(topline)
        local started = vim.uv.hrtime()
        renderer.render(source_win)
        samples[#samples + 1] = (vim.uv.hrtime() - started) / 1000000
    end
    local stats = statistics(samples)

    renderer.dispose()
    overlays.dispose()
    dispose_worker(worker)
    pcall(vim.api.nvim_win_close, source_win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return stats
end

local function measure_cadence(_label)
    local lines = make_lines(10000)
    local buf = fresh_buffer(lines)
    local source_win = open_source_window(buf)
    configure({
        backend = "sync",
        width = 80,
        height = 24,
        throttle_ms = 5,
    })
    local worker = setup_worker("sync")
    local overlays = require("scrollbar.minimap.overlays")
    overlays.setup({ config = require("scrollbar.minimap.config").get() })
    local renderer = require("scrollbar.minimap.renderer")
    renderer.setup({ worker = worker, overlays = overlays })
    local scheduler = require("scrollbar.minimap.scheduler")
    scheduler.setup({ config = require("scrollbar.minimap.config").get(), renderer = renderer })

    renderer.render(source_win)
    collectgarbage("collect")
    local samples = {}
    for _ = 1, iteration_count do
        local started = vim.uv.hrtime()
        scheduler.invalidate_all()
        scheduler.flush()
        samples[#samples + 1] = (vim.uv.hrtime() - started) / 1000000
    end
    local stats = statistics(samples)

    scheduler.dispose()
    renderer.dispose()
    overlays.dispose()
    dispose_worker(worker)
    pcall(vim.api.nvim_win_close, source_win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
    return stats
end

local source_line_counts = { 1000, 10000, 50000 }
local ratio_cases = {
    { label = "ratio 1", source_lines = 24, width = 80, height = 24 },
    { label = "ratio 2", source_lines = 48, width = 80, height = 24 },
    { label = "ratio 5", source_lines = 120, width = 80, height = 24 },
    { label = "ratio 10", source_lines = 240, width = 80, height = 24 },
}

local parity_ok = measure_backend_parity(2000)
local backend_worker = measure_backend_walltime("worker backend", "worker", 10000)
local backend_sync = measure_backend_walltime("sync backend", "sync", 10000)
local backend_sync_fixed = measure_backend_walltime("sync backend fixed", "sync", 10000, "fixed")
local squash_size_results = measure_squash("squash by source size", source_line_counts)
local squash_slice_results = measure_squash("squash slice by source size", source_line_counts, "fixed")
local squash_ratio_results = measure_ratios("squash by ratio", ratio_cases)
local render_overlays_off = measure_render("render overlays off", 10000, { overlays = false })
local render_overlays_on = measure_render("render overlays on", 10000, { overlays = true })
local render_fit = measure_render("render fit", 10000, { overlays = true, scale = "fit" })
local scroll = measure_scroll(10000)
local render_ratios = {
    { label = "ratio 1", stats = measure_render("render ratio 1", 24, { overlays = false }) },
    { label = "ratio 2", stats = measure_render("render ratio 2", 48, { overlays = false }) },
    { label = "ratio 5", stats = measure_render("render ratio 5", 120, { overlays = false }) },
    { label = "ratio 10", stats = measure_render("render ratio 10", 240, { overlays = false }) },
}
local cadence = measure_cadence("cadence")

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

io.write(string.format("\nMode: %s\n", semantic_enabled and "semantic-enabled" or "semantic-disabled"))

io.write("\n## Squash cost by source size (fit, whole buffer)\n\n")
write_table(
    { "Source lines", "Median (p50)", "p95", "Maximum" },
    vim.tbl_map(function(case)
        return {
            tostring(case.line_count),
            string.format("%.3f", case.statistics.median),
            string.format("%.3f", case.statistics.p95),
            string.format("%.3f", case.statistics.maximum),
        }
    end, squash_size_results.cases)
)

io.write("\n## Squash cost of the fixed-scale slice by source size\n\n")
write_table(
    { "Source lines", "Median (p50)", "p95", "Maximum" },
    vim.tbl_map(function(case)
        return {
            tostring(case.line_count),
            string.format("%.3f", case.statistics.median),
            string.format("%.3f", case.statistics.p95),
            string.format("%.3f", case.statistics.maximum),
        }
    end, squash_slice_results.cases)
)

io.write("\n## Squash cost by ratio\n\n")
write_table(
    { "Case", "Source lines", "Width", "Height", "Median (p50)", "p95", "Maximum" },
    vim.tbl_map(function(case)
        return {
            case.label,
            tostring(case.source_lines),
            tostring(case.width),
            tostring(case.height),
            string.format("%.3f", case.statistics.median),
            string.format("%.3f", case.statistics.p95),
            string.format("%.3f", case.statistics.maximum),
        }
    end, squash_ratio_results.cases)
)

io.write("\n## Worker vs sync parity (10k Lua lines)\n\n")
io.write(string.format("Identical output: %s\n", parity_ok and "yes" or "no"))

io.write("\n## Worker vs sync wall time (10k Lua lines)\n\n")
write_table({ "Backend", "Median (p50)", "p95", "Maximum" }, {
    {
        "sync",
        string.format("%.3f", backend_sync.median),
        string.format("%.3f", backend_sync.p95),
        string.format("%.3f", backend_sync.maximum),
    },
    {
        "worker",
        string.format("%.3f", backend_worker.median),
        string.format("%.3f", backend_worker.p95),
        string.format("%.3f", backend_worker.maximum),
    },
    {
        "sync, fixed-scale slice",
        string.format("%.3f", backend_sync_fixed.median),
        string.format("%.3f", backend_sync_fixed.p95),
        string.format("%.3f", backend_sync_fixed.maximum),
    },
})

io.write("\n## Render cost with overlays on/off (10k lines)\n\n")
write_table({ "Overlays", "Median (p50)", "p95", "Maximum" }, {
    {
        "off",
        string.format("%.3f", render_overlays_off.median),
        string.format("%.3f", render_overlays_off.p95),
        string.format("%.3f", render_overlays_off.maximum),
    },
    {
        "on",
        string.format("%.3f", render_overlays_on.median),
        string.format("%.3f", render_overlays_on.p95),
        string.format("%.3f", render_overlays_on.maximum),
    },
    {
        "on, fit scale",
        string.format("%.3f", render_fit.median),
        string.format("%.3f", render_fit.p95),
        string.format("%.3f", render_fit.maximum),
    },
})

io.write("\n## Render cost while scrolling one page per render (10k lines, fixed scale)\n\n")
write_table({ "Case", "Median (p50)", "p95", "Maximum" }, {
    {
        "scroll",
        string.format("%.3f", scroll.median),
        string.format("%.3f", scroll.p95),
        string.format("%.3f", scroll.maximum),
    },
})

io.write("\n## Render cost across squash ratios\n\n")
write_table(
    { "Ratio", "Median (p50)", "p95", "Maximum" },
    vim.tbl_map(function(case)
        return {
            case.label,
            string.format("%.3f", case.stats.median),
            string.format("%.3f", case.stats.p95),
            string.format("%.3f", case.stats.maximum),
        }
    end, render_ratios)
)

io.write("\n## Update-cadence cost\n\n")
write_table({ "Case", "Median (p50)", "p95", "Maximum" }, {
    {
        "invalidate all and flush",
        string.format("%.3f", cadence.median),
        string.format("%.3f", cadence.p95),
        string.format("%.3f", cadence.maximum),
    },
})

vim.cmd("qa!")
