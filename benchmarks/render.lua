local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.lines = 48
vim.o.columns = 120
vim.o.swapfile = false

local line_count = 50000
local mark_count = 10000
local warmup_count = 5
local iteration_count = 30
local unpack_values = unpack
local jit_module = require("jit")
local setupvalue = assert(rawget(debug, "setupvalue"))

local lines = {}
for index = 1, line_count do
    lines[index] = "benchmark line " .. index
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local source_buf = vim.api.nvim_get_current_buf()

local marks = {}
for index = 1, mark_count do
    marks[index] = {
        line = math.floor((index - 1) * (line_count - 1) / (mark_count - 1)),
        text = "-",
        type = "Misc",
    }
end
assert(require("scrollbar.store").set("benchmark", source_buf, marks))

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

local function configure(geometry)
    require("scrollbar.config").set({
        set_highlights = false,
        render = { interval_ms = 0, geometry = geometry },
        excluded_buftypes = {},
        excluded_filetypes = {},
        handle = { text = "H", hide_if_all_visible = false },
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

local function render_pass(windows)
    for _, winid in ipairs(windows) do
        require("scrollbar.renderer").render(winid)
    end
end

local function measure(geometry, name, windows)
    configure(geometry)

    for _ = 1, warmup_count do
        render_pass(windows)
    end

    collectgarbage("collect")
    local samples = {}
    for index = 1, iteration_count do
        local started = vim.uv.hrtime()
        render_pass(windows)
        samples[index] = (vim.uv.hrtime() - started) / 1000000
    end
    return {
        geometry = geometry,
        name = name,
        statistics = statistics(samples),
    }
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
    wrap_upvalue(render_source, "source_text_area", "geometry")
    wrap_upvalue(render_source, "flattened_marks", "store snapshot/flattening")
    wrap_upvalue(render_source, "geometry_for", "geometry")
    wrap_upvalue(render_source, "float_config", "float configuration")
    wrap_upvalue(render_source, "configure_window", "float configuration")
    wrap_upvalue(render_source, "configure_buffer", "float configuration")
    wrap_upvalue(render_source, "update_buffer", "buffer/extmark updates")

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

    local original_win_set_config = vim.api.nvim_win_set_config
    vim.api.nvim_win_set_config = function(...)
        return timed("float configuration", original_win_set_config, ...)
    end
    table.insert(restores, function()
        vim.api.nvim_win_set_config = original_win_set_config
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
    "source-window discovery",
    "store snapshot/flattening",
    "geometry",
    "mark grouping/placement",
    "row composition",
    "float configuration",
    "buffer/extmark updates",
}

local function measure_phases(geometry, name, windows)
    local renderer = require("scrollbar.renderer")
    local instrumentation = instrument_renderer()
    local samples = {}

    local function profiled_pass()
        local sample = instrumentation.start_sample()
        local started = vim.uv.hrtime()
        local discovered = renderer.source_windows(source_buf)
        instrumentation.record("source-window discovery", (vim.uv.hrtime() - started) / 1000000)
        assert(#discovered == #windows, "source-window fixture changed during phase measurement")
        render_pass(windows)
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
    return { geometry = geometry, name = name, phases = result }
end

local end_to_end = {}
local phase_results = {}

local function measure_case(geometry, name, windows)
    table.insert(end_to_end, measure(geometry, name, windows))
    table.insert(phase_results, measure_phases(geometry, name, windows))
end

local first_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(first_win, { 1, 0 })
vim.cmd("normal! zt")
measure_case("line", "1 window", { first_win })
measure_case("screen", "1 window", { first_win })

vim.cmd("vsplit")
local second_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(second_win, { math.floor(line_count / 2), 0 })
vim.cmd("normal! zt")
vim.cmd("split")
local third_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(third_win, { line_count - 100, 0 })
vim.cmd("normal! zt")
measure_case("line", "3 windows", { first_win, second_win, third_win })
measure_case("screen", "3 windows", { first_win, second_win, third_win })

io.write("## End-to-end renderer\n\n")
io.write("| Geometry | Case | Median (p50) | p95 | Maximum |\n")
io.write("| --- | --- | ---: | ---: | ---: |\n")
for _, result in ipairs(end_to_end) do
    local stats = result.statistics
    io.write(
        string.format(
            "| %s | %s | %.3f | %.3f | %.3f |\n",
            result.geometry,
            result.name,
            stats.median,
            stats.p95,
            stats.maximum
        )
    )
end

io.write("\n## Renderer phases\n\n")
io.write("| Geometry | Case | Phase | Median (p50) | p95 | Maximum |\n")
io.write("| --- | --- | --- | ---: | ---: | ---: |\n")
for _, result in ipairs(phase_results) do
    for _, phase in ipairs(phases) do
        local stats = result.phases[phase]
        io.write(
            string.format(
                "| %s | %s | %s | %.3f | %.3f | %.3f |\n",
                result.geometry,
                result.name,
                phase,
                stats.median,
                stats.p95,
                stats.maximum
            )
        )
    end
end

require("scrollbar.renderer").dispose()
vim.cmd("qa!")
