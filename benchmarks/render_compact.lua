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

-- Dense matches: 2 per line on even-indexed lines, 1 per line on odd-indexed
-- lines. This fixture mirrors the "dense" fixture in benchmarks/search.lua. The
-- two forms publish the matches as a compact blob or as ordinary search marks.
-- Two match sets alternate, because the store ignores an identical publish.
-- Each timed pass is a cold render:
-- - publish: a new match set, as on an incsearch keystroke or a refresh after
--   an edit. The pass times the store call and the render.
-- - scroll: a scroll by one line. In screenline mode, a scroll runs the line
--   dedup in M.screen and rebuilds the mark layer.
local function dense_match_lines(shift)
    local result = {}
    for index = 0, line_count - 1 do
        local line = (index + shift) % line_count
        result[#result + 1] = line
        if index % 2 == 0 then
            result[#result + 1] = line
        end
    end
    table.sort(result)
    return result
end

local match_sets = { dense_match_lines(0), dense_match_lines(1) }
local match_count = #match_sets[1]

local compact = require("scrollbar.providers.search.compact")
local compact_blobs = {}
local ordinary_marks = {}
for set_index, match_lines in ipairs(match_sets) do
    compact_blobs[set_index] = compact.encode(match_lines)
    ordinary_marks[set_index] = {}
    for index, line in ipairs(match_lines) do
        ordinary_marks[set_index][index] = { line = line, type = "Search" }
    end
end

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
        exclude = { buftypes = {}, filetypes = {} },
        -- The renderer draws search marks only when the search consumer of
        -- the scrollbar is enabled. The benchmark does not call
        -- `providers.setup()`, so this option starts no search provider, no
        -- autocmds, and no worker. The benchmark publishes the matches itself.
        providers = {
            cursor = false,
            diagnostic = false,
            gitsigns = false,
            search = true,
            ale = false,
            coc = false,
        },
        scrollbar = {
            throttle_ms = 0,
            unit = "screenline",
            thumb = { text = "H", hide_if_all_visible = false },
            marks = { Search = { text = { "-", "=", "#" } } },
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

-- Render once and stop the benchmark if the screen geometry does not get every
-- match. Without this check, a configuration that drops the search marks
-- measures an empty render and still prints plausible numbers.
local function assert_render_gets_matches(name, winid)
    local layout = require("scrollbar.layout")
    local original_screen = layout.screen
    local received
    rawset(layout, "screen", function(input)
        received = input
        return original_screen(input)
    end)
    local ok, render_error = pcall(require("scrollbar.renderer").render, winid)
    rawset(layout, "screen", original_screen)
    assert(ok, render_error)
    assert(received ~= nil, string.format("%s: the render did not call layout.screen", name))
    local compact_count = received.compact_search and received.compact_search.count or 0
    local received_count = #received.marks + compact_count
    assert(
        received_count == match_count,
        string.format("%s: layout.screen got %d matches, expected %d", name, received_count, match_count)
    )
end

local phases = {
    "publish",
    "store snapshot/flattening",
    "geometry",
    "screen geometry",
    "mark grouping/placement",
    "row composition",
}

local function measure_phases(name, mode, publish)
    local renderer = require("scrollbar.renderer")
    local store = require("scrollbar.shared.store")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_cursor(winid, { 1, 0 })
    vim.cmd("normal! zt")
    configure_screen()
    local instrumentation = instrument_renderer()

    store.clear("search", source_buf)
    local set_index = 1
    local topline = 1
    publish(store, set_index)
    assert_render_gets_matches(name, winid)

    local samples = {}
    local function profiled_pass()
        local sample = instrumentation.start_sample()
        if mode == "publish" then
            set_index = 3 - set_index
            local started = vim.uv.hrtime()
            assert(publish(store, set_index), "the store rejected the publish")
            instrumentation.record("publish", (vim.uv.hrtime() - started) / 1000000)
        else
            topline = 3 - topline
            vim.fn.winrestview({ topline = topline, lnum = topline })
        end
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

local publishers = {
    ["compact blob"] = function(store, set_index)
        return store._set_search_compact(source_buf, compact_blobs[set_index])
    end,
    ["ordinary search marks"] = function(store, set_index)
        return store.set("search", source_buf, ordinary_marks[set_index])
    end,
}

local results = {}
for _, mode in ipairs({ "publish", "scroll" }) do
    for _, form in ipairs({ "compact blob", "ordinary search marks" }) do
        table.insert(results, measure_phases(string.format("%s, %s", mode, form), mode, publishers[form]))
    end
end

io.write(string.format("match_count = %d\n\n", match_count))
io.write("## Renderer phases (screenline unit, p50 / p95 / max ms)\n\n")
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
