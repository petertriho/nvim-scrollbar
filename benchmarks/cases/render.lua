---One render of the scrollbar for each unit. The steady cases render a window that did not change. The other cases
---change the text, the view, or a window option before each render, so that the renderer computes the layout again.
local fixtures = require("benchmarks.fixtures")

local MARK_COUNT = 2000
local PROVIDER = "benchmark_render"
-- A window provider with one mark, like the cursor provider
local CURSOR_PROVIDER = "benchmark_cursor"
-- Matches on every 10th line, like a search on the 10,000-line file
local SEARCH_INTERVAL = 10

---@param unit "line" | "screenline"
---@param opts bench.RenderOptions
local function configure(unit, opts)
    local reserve = opts.reserve
    local marks = nil
    if opts.mark_text or opts.cursor_covered then
        marks = {}
        if opts.mark_text then
            marks.Misc = { text = opts.mark_text }
        end
        if opts.cursor_covered then
            marks.Cursor = { highlight_from = "covered" }
        end
    end
    require("scrollbar.config").set({
        set_highlights = false,
        exclude = { buftypes = {}, filetypes = {} },
        providers = {
            cursor = false,
            diagnostic = false,
            search = opts.search == true,
            marks = false,
        },
        marks = marks,
        scrollbar = {
            unit = unit,
            throttle_ms = 0,
            thumb = { text = opts.thumb_text or "H", hide_if_all_visible = false },
            overlap = { reserve = reserve == nil and true or reserve },
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
---@field reserve? boolean | "virtual_text" The `overlap.reserve` value (default true).
---@field change? fun(state: bench.RenderState)
---@field mark_text? ScrollbarMarkTextFunction The text of the Misc marks
---@field thumb_text? ScrollbarThumbTextFunction
---@field cursor_mark? boolean Adds one window mark of the type Cursor, which `change` can move.
---@field search? boolean Adds compact search matches on every 10th line.
---@field cursor_covered? boolean Sets `highlight_from = "covered"` on the Cursor type.

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
            local store = require("scrollbar.shared.store")
            providers.register({ name = PROVIDER, targets = { scrollbar = true } })
            assert(
                store.set(PROVIDER, bufnr, fixtures.spread(MARK_COUNT, fixtures.LINE_COUNT, "Misc", "-")),
                "the store rejected the marks"
            )
            if opts.cursor_mark then
                providers.register({ name = CURSOR_PROVIDER, targets = { scrollbar = true } })
                assert(
                    store.set_window(CURSOR_PROVIDER, windows[1], { { line = 0, type = "Cursor" } }),
                    "the store rejected the cursor mark"
                )
            end
            if opts.search then
                local lines = {}
                for line = 0, fixtures.LINE_COUNT - 1, SEARCH_INTERVAL do
                    lines[#lines + 1] = line
                end
                local compact = require("scrollbar.providers.search.compact").encode(lines)
                assert(store._set_search_compact(bufnr, compact), "the store rejected the search matches")
            end
            configure(unit, opts)
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
            if opts.cursor_mark then
                require("scrollbar.providers").unregister(CURSOR_PROVIDER)
            end
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

---Moves the cursor between two lines in the view.
---@param state bench.RenderState
local function move_cursor(state)
    state.toggle = not state.toggle
    vim.api.nvim_win_set_cursor(state.windows[1], { state.toggle and 2 or 3, 0 })
end

---Moves the window mark one line down, as a cursor move does, and starts at the top again at the end. Most moves
---keep the row of the mark, and some move it to the next row.
---@param state bench.RenderState
local function move_cursor_mark(state)
    state.topline = state.topline % fixtures.LINE_COUNT + 1
    assert(
        require("scrollbar.shared.store").set_window(
            CURSOR_PROVIDER,
            state.windows[1],
            { { line = state.topline - 1, type = "Cursor" } }
        ),
        "the store rejected the cursor mark"
    )
end

---A mark text that reads the cursor line, so each cursor line change builds the mark layer again.
---@param context ScrollbarMarkTextContext
---@return string
local function relative_line(context)
    return tostring(math.abs(context.line - context.cursor_line) % 10)
end

---@param context ScrollbarThumbTextContext
---@return string?
local function thumb_top_line(context)
    if context.index == 0 then
        return tostring(context.top_line + 1)
    end
    return nil
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
    -- The pads of `reserve = "virtual_text"`. Without a main loop, no autocmd
    -- runs, so the render updates the pads after each scroll.
    render_case("line", "virtual_text_steady", { wrapped = true, reserve = "virtual_text" }),
    render_case("line", "virtual_text_scroll", { wrapped = true, reserve = "virtual_text", change = scroll }),
    render_case("screenline", "virtual_text_scroll", { wrapped = true, reserve = "virtual_text", change = scroll }),
    -- The text functions. Each run of the mark case builds the layer again and
    -- calls the function for each group. The thumb case calls the function on
    -- each scroll.
    render_case("line", "mark_text_cursor", { mark_text = relative_line, change = move_cursor }),
    -- The cursor provider changes its window mark on each cursor move. The
    -- render must not rebuild the marks of the other providers.
    render_case("line", "cursor_mark", { cursor_mark = true, change = move_cursor_mark }),
    render_case("line", "cursor_mark_search", { cursor_mark = true, search = true, change = move_cursor_mark }),
    -- The cursor mark takes the color of the marks that it covers. On most
    -- rows, it covers a Misc mark or a search match.
    render_case(
        "line",
        "cursor_mark_covered",
        { cursor_mark = true, search = true, cursor_covered = true, change = move_cursor_mark }
    ),
    render_case("line", "thumb_text_scroll", { thumb_text = thumb_top_line, change = scroll }),
}
