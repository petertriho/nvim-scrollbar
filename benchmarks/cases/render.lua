---One render of the scrollbar for each unit. The steady cases render a window that did not change. The other cases
---change the text, the view, or a window option before each render, so that the renderer computes the layout again.
local fixtures = require("benchmarks.fixtures")

local MARK_COUNT = 2000
local PROVIDER = "benchmark_render"

---@param unit "line" | "screenline"
local function configure(unit)
    require("scrollbar.config").set({
        set_highlights = false,
        exclude = { buftypes = {}, filetypes = {} },
        providers = {
            cursor = false,
            diagnostic = false,
            search = false,
            marks = false,
        },
        scrollbar = {
            unit = unit,
            throttle_ms = 0,
            thumb = { text = "H", hide_if_all_visible = false },
        },
    })
    require("scrollbar.renderer").setup()
end

---Every 40th line is longer than the window, so the screen geometry is not uniform.
---@param index integer
---@return string
local function wrapped_line(index)
    return index % 40 == 0 and string.rep("w", 200) or "benchmark line " .. index
end

---@class bench.RenderState
---@field bufnr integer
---@field windows integer[]
---@field toggle boolean
---@field topline integer

---@param state bench.RenderState
local function render(state)
    local renderer = require("scrollbar.renderer")
    for _, winid in ipairs(state.windows) do
        renderer.render(winid)
    end
end

---@class bench.RenderOptions
---@field wrapped? boolean
---@field windows? integer The number of windows that show the buffer (default 1).
---@field change? fun(state: bench.RenderState)

---@param unit "line" | "screenline"
---@param name string
---@param opts? bench.RenderOptions
---@return bench.SyncCase
local function render_case(unit, name, opts)
    opts = opts or {}
    return {
        name = string.format("render/%s/%s", unit, name),
        setup = function()
            local bufnr = fixtures.buffer(fixtures.lines(fixtures.LINE_COUNT, opts.wrapped and wrapped_line or nil))
            local windows = { fixtures.source_window(bufnr) }
            if opts.wrapped then
                vim.api.nvim_win_set_width(windows[1], 110)
                vim.wo[windows[1]].wrap = true
            end
            for index = 2, opts.windows or 1 do
                local winid = fixtures.split(bufnr, index == 2 and "vsplit" or "split")
                vim.api.nvim_win_set_cursor(winid, { math.floor(fixtures.LINE_COUNT * (index - 1) / 3), 0 })
                vim.cmd("normal! zt")
                table.insert(windows, winid)
            end

            local providers = require("scrollbar.providers")
            providers.register({ name = PROVIDER, targets = { scrollbar = true } })
            assert(
                require("scrollbar.shared.store").set(
                    PROVIDER,
                    bufnr,
                    fixtures.spread(MARK_COUNT, fixtures.LINE_COUNT, "Misc", "-")
                ),
                "the store rejected the marks"
            )
            configure(unit)
            ---@type bench.RenderState
            local state = { bufnr = bufnr, windows = windows, toggle = false, topline = 1 }
            render(state)
            return state
        end,
        run = function(state)
            if opts.change then
                opts.change(state)
            end
            render(state)
        end,
        teardown = function()
            require("scrollbar.providers").unregister(PROVIDER)
            fixtures.reset()
        end,
    }
end

---Scrolls one line, and starts at the top again before the end, so that any number of runs scroll.
---@param state bench.RenderState
local function scroll(state)
    state.topline = state.topline % (fixtures.LINE_COUNT - 100) + 1
    vim.api.nvim_win_call(state.windows[1], function()
        vim.fn.winrestview({ topline = state.topline, lnum = state.topline })
    end)
end

---Changes the first 8 bytes of a line in the middle, and changes them back on the next run.
---@param state bench.RenderState
local function edit(state)
    local row = math.floor(fixtures.LINE_COUNT / 2)
    state.toggle = not state.toggle
    vim.api.nvim_buf_set_text(state.bufnr, row, 0, row, 8, { state.toggle and "CHANGED!" or "local va" })
end

---Inserts a line in the middle, and deletes it on the next run.
---@param state bench.RenderState
local function insert(state)
    local row = math.floor(fixtures.LINE_COUNT / 2)
    state.toggle = not state.toggle
    if state.toggle then
        vim.api.nvim_buf_set_lines(state.bufnr, row, row, false, { "INSERTED" })
    else
        vim.api.nvim_buf_set_lines(state.bufnr, row, row + 1, false, {})
    end
end

---@param state bench.RenderState
local function toggle_number(state)
    local winid = state.windows[1]
    vim.wo[winid].number = not vim.wo[winid].number
end

---@type bench.Case[]
return {
    render_case("line", "steady"),
    render_case("line", "insert", { change = insert }),
    render_case("line", "3_windows", { windows = 3 }),
    render_case("screenline", "steady"),
    render_case("screenline", "scroll", { change = scroll }),
    render_case("screenline", "edit", { change = edit }),
    render_case("screenline", "option", { change = toggle_number }),
    render_case("screenline", "3_windows", { windows = 3 }),
    render_case("screenline", "wrapped_steady", { wrapped = true }),
    render_case("screenline", "wrapped_scroll", { wrapped = true, change = scroll }),
    render_case("screenline", "wrapped_edit", { wrapped = true, change = edit }),
}
