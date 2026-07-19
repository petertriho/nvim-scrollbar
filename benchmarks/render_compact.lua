local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.lines = 48
vim.o.columns = 120
vim.o.swapfile = false

local line_count = 50000
local warmup_count = 5
local iteration_count = 30
local unpack_values = unpack
local jit_module = require("jit")
local setupvalue = assert(rawget(debug, "setupvalue"))

local lines = {}
for index = 1, line_count do
    lines[index] = "compact-render-benchmark line " .. index
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local source_buf = vim.api.nvim_get_current_buf()

-- Dense matches: 2 per line on even-indexed lines, 1 per line on odd-indexed.
-- This mirrors the "dense" fixture in benchmarks/search.lua and exercises the
-- dedup path inside M.screen (compact path) / expand_compact (old path).
local match_lines = {}
for index = 0, line_count - 1 do
    match_lines[#match_lines + 1] = index
    if index % 2 == 0 then
        match_lines[#match_lines + 1] = index
    end
end
local match_count = #match_lines

local ordinary_marks = {}
for index, line in ipairs(match_lines) do
    ordinary_marks[index] = { line = line, type = "Search" }
end

local compact_blob = require("scrollbar.providers.search_compact").encode(match_lines)

local function pack(...)
    return select("#", ...), { ... }
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

local function configure_screen()
    require("scrollbar.config").set({
        set_highlights = false,
        render = { interval_ms = 0, geometry = "screen" },
        excluded_buftypes = {},
        excluded_filetypes = {},
        thumb = { text = "H", hide_if_all_visible = false },
        marks = { Search = { text = { "-", "=", "#" } } },
        providers = {
            cursor = false,
            diagnostic = false,
            gitsigns = false,
            search = false,
            ale = false,
            coc = false,
        },
    })
    require("scrollbar.renderer").setup()
end

local function upvalue_index(callback, target)
    local index = 1
    while true do
        local name = debug.getupvalue(callback, index)
        if name == nil then
            break
        end
        if name == target then
            return index
        end
        index = index + 1
    end
    error(string.format("benchmark instrumentation could not find upvalue '%s'", target))
end

local function instrument_renderer()
    local renderer = require("scrollbar.renderer")
    local layout = require("scrollbar.layout")
    local current_sample
    local restores = {}

    local function record(phase, elapsed)
        if current_sample ~= nil then
            current_sample[phase] = (current_sample[phase] or 0) + elapsed
        end
    end

    local function timed(phase, callback, ...)
        local started = vim.uv.hrtime()
        local count, result = pack(callback(...))
        record(phase, (vim.uv.hrtime() - started) / 1000000)
        return unpack_values(result, 1, count)
    end

    local function wrap_upvalue(callback, name, phase)
        local index = upvalue_index(callback, name)
        local _, original = debug.getupvalue(callback, index)
        setupvalue(callback, index, function(...)
            return timed(phase, original, ...)
        end)
        table.insert(restores, function()
            setupvalue(callback, index, original)
        end)
    end

    local render_source_index = upvalue_index(renderer.render, "render_source")
    local _, render_source = debug.getupvalue(renderer.render, render_source_index)
    wrap_upvalue(render_source, "flattened_marks", "store snapshot/flattening")
    wrap_upvalue(render_source, "geometry_for", "geometry")

    local original_compose = layout.compose
    local resolve_index = upvalue_index(original_compose, "resolve_mark_layer")
    local _, resolve_mark_layer = debug.getupvalue(original_compose, resolve_index)
    wrap_upvalue(resolve_mark_layer, "group_candidates", "mark grouping/placement")
    wrap_upvalue(resolve_mark_layer, "place_marks", "mark grouping/placement")
    rawset(layout, "compose", function(...)
        local grouping_before = current_sample and current_sample["mark grouping/placement"] or 0
        local started = vim.uv.hrtime()
        local count, result = pack(original_compose(...))
        local elapsed = (vim.uv.hrtime() - started) / 1000000
        local grouping_after = current_sample and current_sample["mark grouping/placement"] or grouping_before
        record("row composition", math.max(0, elapsed - (grouping_after - grouping_before)))
        return unpack_values(result, 1, count)
    end)
    table.insert(restores, function()
        rawset(layout, "compose", original_compose)
    end)

    local original_screen = layout.screen
    rawset(layout, "screen", function(...)
        return timed("screen geometry", original_screen, ...)
    end)
    table.insert(restores, function()
        rawset(layout, "screen", original_screen)
    end)

    if jit_module ~= nil then
        jit_module.flush()
    end

    return {
        start_sample = function()
            current_sample = {}
            return current_sample
        end,
        stop_sample = function()
            current_sample = nil
        end,
        record = record,
        restore = function()
            for index = #restores, 1, -1 do
                restores[index]()
            end
            if jit_module ~= nil then
                jit_module.flush()
            end
        end,
    }
end

local phases = {
    "store snapshot/flattening",
    "geometry",
    "screen geometry",
    "mark grouping/placement",
    "row composition",
}

local function measure_phases(name, publish)
    local renderer = require("scrollbar.renderer")
    local store = require("scrollbar.store")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(winid, { 1, 0 })
    vim.cmd("normal! zt")
    configure_screen()
    local instrumentation = instrument_renderer()

    -- Publish once; renderer caches after the first render. We measure the
    -- warm-cache steady state, matching what benchmarks/render.lua does.
    publish(store)

    local samples = {}
    local function profiled_pass()
        local sample = instrumentation.start_sample()
        renderer.render(winid)
        instrumentation.stop_sample()
        return sample
    end

    for _ = 1, warmup_count do
        profiled_pass()
    end

    collectgarbage("collect")
    for _ = 1, iteration_count do
        local sample = profiled_pass()
        for _, phase in ipairs(phases) do
            samples[phase] = samples[phase] or {}
            table.insert(samples[phase], sample[phase] or 0)
        end
    end
    instrumentation.restore()

    local result = {}
    for _, phase in ipairs(phases) do
        result[phase] = statistics(samples[phase])
    end
    return { name = name, match_count = match_count, phases = result }
end

local results = {}

table.insert(
    results,
    measure_phases("screen + compact blob", function(store)
        store._set_search_compact(source_buf, compact_blob)
    end)
)

table.insert(
    results,
    measure_phases("screen + ordinary search marks", function(store)
        store.set("search", source_buf, ordinary_marks)
    end)
)

io.write(string.format("match_count = %d\n\n", match_count))
io.write("## Renderer phases (screen mode, p50 / p95 / max ms)\n\n")
io.write("| Case | Phase | p50 | p95 | max |\n")
io.write("| --- | --- | ---: | ---: | ---: |\n")
for _, result in ipairs(results) do
    for _, phase in ipairs(phases) do
        local stats = result.phases[phase]
        io.write(
            string.format(
                "| %s | %s | %s | %s | %s |\n",
                result.name,
                phase,
                string.format("%.3f", stats.median),
                string.format("%.3f", stats.p95),
                string.format("%.3f", stats.maximum)
            )
        )
    end
end

require("scrollbar.renderer").dispose()
vim.cmd("qa!")
