local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.lines = 48
vim.o.columns = 120
vim.o.swapfile = false

local warmup_count = 10
local iteration_count = 200
local semantic_enabled = vim.env.SCROLLBAR_BENCHMARK_SEMANTIC == "1"

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

local function make_lines(count)
    local lines = {}
    for index = 1, count do
        lines[index] = string.format("local value_%d = %d", index, index * 2)
    end
    return lines
end

local function make_semantic_spans(line_count)
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

local function open_window(buf)
    return vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = 0,
        col = 0,
        width = 80,
        height = 24,
    })
end

-- `setup` replaces the previous runtime, but no public function removes it,
-- so the cleanup disposes the loaded modules in the order that setup uses.
local function dispose_plugin()
    local stack = package.loaded["scrollbar.stack"]
    if stack ~= nil then
        stack.reset()
    end
    for _, name in ipairs({
        "scrollbar.minimap",
        "scrollbar.mouse",
        "scrollbar.scheduler",
        "scrollbar.providers",
        "scrollbar.renderer",
    }) do
        local module = package.loaded[name]
        if module ~= nil and type(module.dispose) == "function" then
            pcall(module.dispose)
        end
    end
end

local function measure_scenario(label, scenario, line_counts)
    local results = {}
    for _, count in ipairs(line_counts) do
        local lines = make_lines(count)
        local buf = fresh_buffer(lines)
        local winid = open_window(buf)
        vim.api.nvim_set_current_win(winid)

        scenario.setup(buf, winid)

        collectgarbage("collect")

        for _ = 1, warmup_count do
            vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
        end

        local samples = {}
        for _ = 1, iteration_count do
            local started = vim.uv.hrtime()
            vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
            local elapsed = vim.uv.hrtime() - started
            samples[#samples + 1] = elapsed
        end

        results[#results + 1] = {
            line_count = count,
            statistics = statistics(samples),
        }

        pcall(vim.api.nvim_win_close, winid, true)
        pcall(vim.api.nvim_buf_delete, buf, { force = true })

        if scenario.cleanup then
            scenario.cleanup()
        end
    end
    return { label = label, cases = results }
end

local line_counts = { 1000, 10000, 50000 }

local baseline = measure_scenario("baseline (no plugins)", { setup = function() end }, line_counts)

local scrollbar_only = measure_scenario("scrollbar only", {
    setup = function()
        require("scrollbar").setup({
            set_highlights = false,
            exclude = { buftypes = {}, filetypes = {} },
            minimap = { enabled = false },
        })
    end,
    cleanup = function()
        dispose_plugin()
    end,
}, line_counts)

local scrollbar_and_minimap = measure_scenario("scrollbar + minimap (enabled)", {
    setup = function(buf)
        if semantic_enabled then
            vim.bo[buf].filetype = "lua"
        end
        require("scrollbar").setup({
            set_highlights = false,
            exclude = { buftypes = {}, filetypes = {} },
            providers = {
                treesitter = semantic_enabled,
                lsp_semantic_tokens = semantic_enabled,
            },
            minimap = {
                enabled = true,
                backend = "sync",
            },
        })
        if semantic_enabled then
            require("scrollbar.store").set_minimap_spans(
                "lsp_semantic_tokens",
                buf,
                make_semantic_spans(vim.api.nvim_buf_line_count(buf))
            )
        end
    end,
    cleanup = function()
        dispose_plugin()
    end,
}, line_counts)

-- Key presses arrive farther apart than the eligibility memo lifetime, so
-- each measured event starts with an empty memo. Calls inside one event can
-- still reuse it.
local function clear_eligibility_memos()
    for _, name in ipairs({ "scrollbar.renderer", "scrollbar.minimap.renderer" }) do
        local module = package.loaded[name]
        if module ~= nil and type(module.invalidate_source_selection) == "function" then
            module.invalidate_source_selection()
        end
    end
end

---@param setup fun()
local function measure_cursor_moved(setup)
    -- A floating window is never a source window, so this case uses the
    -- normal window that the editor starts with.
    local winid = vim.api.nvim_list_wins()[1]
    vim.api.nvim_set_current_win(winid)
    local buf = fresh_buffer(make_lines(10000))
    vim.api.nvim_win_set_buf(winid, buf)
    setup()
    collectgarbage("collect")

    local samples = {}
    for index = 1, warmup_count + iteration_count do
        vim.api.nvim_win_set_cursor(winid, { index % 20 + 1, 0 })
        clear_eligibility_memos()
        local started = vim.uv.hrtime()
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
        local elapsed = vim.uv.hrtime() - started
        if index > warmup_count then
            samples[#samples + 1] = elapsed
        end
    end
    return statistics(samples)
end

local cursor_cases = {
    {
        label = "baseline (no plugins)",
        setup = dispose_plugin,
    },
    {
        label = "scrollbar only",
        setup = function()
            require("scrollbar").setup({
                set_highlights = false,
                exclude = { buftypes = {}, filetypes = {} },
                minimap = { enabled = false },
            })
        end,
    },
    {
        label = "scrollbar + minimap (enabled)",
        setup = function()
            require("scrollbar").setup({
                set_highlights = false,
                exclude = { buftypes = {}, filetypes = {} },
                minimap = { enabled = true, backend = "sync" },
            })
        end,
    },
}
for _, case in ipairs(cursor_cases) do
    case.statistics = measure_cursor_moved(case.setup)
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

io.write("\n## Per-keystroke TextChangedI dispatch (microseconds)\n\n")
io.write(string.format("Mode: %s\n\n", semantic_enabled and "semantic-enabled" or "semantic-disabled"))
io.write("Fires the real `TextChangedI` autocmd against the live scheduler setup.\n")
io.write("Captures only the synchronous per-keystroke cost (autocmd callback +\n")
io.write("dirty-marking + timer re-arm). The deferred render that runs when the\n")
io.write("timer fires is measured separately below.\n\n")

local rows = {}
for _, line_count in ipairs(line_counts) do
    local row = { tostring(line_count) }
    for _, scenario in ipairs({ baseline, scrollbar_only, scrollbar_and_minimap }) do
        for _, case in ipairs(scenario.cases) do
            if case.line_count == line_count then
                row[#row + 1] = string.format("%.2f", case.statistics.median / 1000)
                row[#row + 1] = string.format("%.2f", case.statistics.p95 / 1000)
                break
            end
        end
    end
    rows[#rows + 1] = row
end
write_table({
    "Lines",
    "baseline p50",
    "baseline p95",
    "scrollbar p50",
    "scrollbar p95",
    "+minimap p50",
    "+minimap p95",
}, rows)

io.write("\n## Per-keystroke CursorMoved dispatch (microseconds)\n\n")
io.write("Fires the real `CursorMoved` autocmd in a normal window with 10000\n")
io.write("lines after each cursor move. Captures the synchronous cost: the cursor\n")
io.write("provider, the eligibility checks, and the scheduler activity. The\n")
io.write("eligibility memos are cleared before each event.\n\n")

local cursor_rows = {}
for _, case in ipairs(cursor_cases) do
    cursor_rows[#cursor_rows + 1] = {
        case.label,
        string.format("%.2f", case.statistics.median / 1000),
        string.format("%.2f", case.statistics.p95 / 1000),
    }
end
write_table({ "Case", "p50", "p95" }, cursor_rows)

io.write("\nAll values in microseconds (lower is better).\n")
