---The minimap in the parent: the squash of the source lines into braille cells, a sync request to the worker module,
---and one render of the float. `benchmarks/cases/worker.lua` has the requests to the worker child.
local fixtures = require("benchmarks.fixtures")

local M = {}

M.WIDTH = 80
M.ROWS = 24

---The grid of a 24-row, 80-cell float whose source window starts in the middle of the buffer. `fit` squashes the
---whole buffer. `fixed` squashes the slice around the visible rows.
---@param line_count integer
---@param scale? "fit" | "fixed"
---@return table
function M.grid(line_count, scale)
    local projection = require("scrollbar.minimap.projection")
    local top = math.floor(line_count / 2)
    local view = projection.new({
        scale = scale or "fit",
        line_count = line_count,
        rows = M.ROWS,
        width = M.WIDTH,
        columns_per_dot = 4,
        top = top,
        bottom = math.min(line_count - 1, top + M.ROWS - 1),
    })
    local first_row, row_count = projection.slice(view)
    return {
        width = M.WIDTH,
        first_row = first_row,
        row_count = row_count,
        scale_lines = view.scale_lines,
        scale_dots = view.scale_dots,
        columns_per_dot = 4,
        encoding = "braille",
    }
end

---A request for the worker module. Each request has a new generation, so that no cache can answer it.
---@param state { bufnr: integer, generation: integer }
---@return table
function M.request(state)
    state.generation = state.generation + 1
    return {
        bufnr = state.bufnr,
        grid = M.grid(fixtures.LINE_COUNT),
        filetype = "lua",
        generation = state.generation,
        signature = "benchmark",
        semantic_revision = 0,
        semantic_spans = {},
    }
end

---@param line_count integer
---@param scale "fit" | "fixed"
---@return bench.SyncCase
local function squash_case(line_count, scale)
    return {
        name = string.format("minimap/squash/%s_%dk", scale, line_count / 1000),
        setup = function()
            local squash = require("scrollbar.minimap.squash")
            local grid = M.grid(line_count, scale)
            local first, last = squash.line_range(grid, line_count)
            return {
                squash = squash,
                grid = grid,
                first = first,
                lines = vim.list_slice(fixtures.lines(line_count), first + 1, last),
            }
        end,
        run = function(state)
            state.squash.squash(state.lines, state.first, state.grid)
        end,
    }
end

---@class bench.MinimapRenderState
---@field winid integer
---@field topline integer
---@field renderer table
---@field overlays table
---@field worker table

---@param name string
---@param opts { overlays: boolean, scroll?: boolean }
---@return bench.SyncCase
local function render_case(name, opts)
    return {
        name = "minimap/render/" .. name,
        setup = function()
            local bufnr = fixtures.buffer(fixtures.lines(fixtures.LINE_COUNT))
            local winid = fixtures.source_window(bufnr)
            local config = require("scrollbar.config")
            config.set({
                set_highlights = false,
                minimap = {
                    enabled = true,
                    backend = "sync",
                    width = M.WIDTH,
                    height = M.ROWS,
                    marks = opts.overlays and {} or false,
                    viewport = true,
                },
            })
            local worker = require("scrollbar.minimap.worker")
            worker.setup({
                backend = "sync",
                on_result = function(payload)
                    require("scrollbar.minimap.renderer").handle_worker_result(payload)
                end,
            })
            local overlays = require("scrollbar.minimap.overlays")
            overlays.setup({ config = require("scrollbar.minimap.config").get() })
            local renderer = require("scrollbar.minimap.renderer")
            renderer.setup({ worker = worker, overlays = overlays })
            if opts.overlays then
                local marks = {}
                for line = 0, 200 do
                    marks[#marks + 1] = { line = line, type = "Error" }
                end
                require("scrollbar.shared.store").set("diagnostic", bufnr, marks)
            end
            renderer.render(winid)
            renderer.render(winid)
            ---@type bench.MinimapRenderState
            return { winid = winid, topline = 1, renderer = renderer, overlays = overlays, worker = worker }
        end,
        run = function(state)
            if opts.scroll then
                -- One page for each render. The renderer requests a new slice when the margin runs low.
                state.topline = state.topline + M.ROWS
                if state.topline > fixtures.LINE_COUNT - M.ROWS then
                    state.topline = 1
                end
                vim.api.nvim_win_call(state.winid, function()
                    vim.fn.winrestview({ topline = state.topline, lnum = state.topline })
                end)
            end
            state.renderer.render(state.winid)
        end,
        teardown = function(state)
            require("scrollbar.shared.store").clear_provider("diagnostic")
            state.renderer.dispose()
            state.overlays.dispose()
            fixtures.dispose_worker(state.worker)
            fixtures.reset()
        end,
    }
end

table.insert(M, squash_case(1000, "fit"))
table.insert(M, squash_case(10000, "fit"))
table.insert(M, squash_case(10000, "fixed"))
table.insert(M, {
    name = "minimap/request/sync_10k",
    setup = function()
        local bufnr = fixtures.buffer(fixtures.lines(fixtures.LINE_COUNT))
        local worker = require("scrollbar.minimap.worker")
        worker.setup({ backend = "sync", on_result = function() end })
        return { worker = worker, bufnr = bufnr, generation = 0 }
    end,
    run = function(state)
        state.worker.request(M.request(state))
    end,
    teardown = function(state)
        fixtures.dispose_worker(state.worker)
        fixtures.reset()
    end,
})
table.insert(M, render_case("overlays_off", { overlays = false }))
table.insert(M, render_case("overlays_on", { overlays = true }))
table.insert(M, render_case("scroll", { overlays = false, scroll = true }))

-- benchmarks/run.lua reads the cases from the list part. benchmarks/cases/worker.lua uses the functions.
return M
