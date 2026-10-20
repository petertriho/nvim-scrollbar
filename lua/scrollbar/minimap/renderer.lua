--- Minimap renderer: per-source-window float lifecycle, composes squashed
--- cells plus semantic, viewport, and cursor highlight layers into a visible
--- scratch buffer. It shares the source-window policy (`scrollbar.source_policy`)
--- and the float placement and row writer (`scrollbar.float`) with the
--- scrollbar renderer.
---
--- `scrollbar.stack` resolves the origin and z-index against a scrollbar on the
--- same side of the source window. Squash output is the only source of row
--- text; viewport, cursor, and semantic overlays are non-destructive extmark
--- highlights. `lua/scrollbar/minimap/projection.lua` maps source lines to
--- float rows for every layer, so all layers agree on the row of a line.
---
--- The worker squashes a slice of map rows around the visible rows. Scrolling
--- inside the slice redraws from the cache; a new slice is requested when the
--- visible rows get near the edge of the cached slice.
---
--- Every render composes all rows and their highlights. The row writer then
--- replaces only the rows whose text changed and sets extmarks only on the rows
--- whose text or highlights changed.

local config_module = require("scrollbar.minimap.config")
local float = require("scrollbar.float")
local highlight_module = require("scrollbar.minimap.highlights")
local projection_module = require("scrollbar.minimap.projection")
local providers = require("scrollbar.providers")
local semantic = require("scrollbar.minimap.semantic")
local source_policy = require("scrollbar.source_policy")
local stack = require("scrollbar.stack")
local store = require("scrollbar.store")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarMinimapRenderer")
local AUGROUP_NAME = "ScrollbarMinimapRendererLifecycle"
local FLOAT_WINHIGHLIGHT = "Normal:ScrollbarMinimapBase,NormalNC:ScrollbarMinimapBase,EndOfBuffer:ScrollbarMinimapBase"
-- Window and buffer variable that marks a minimap float, also from an earlier
-- setup.
local OWNED_VAR = "scrollbar_minimap_owned"
local VIEWPORT_PRIORITY = 1
local CONTENT_PRIORITY = 2

---@param active_config ScrollbarMinimapConfig
---@return integer blend
---@return string winhighlight
local function window_presentation(active_config)
    local background_blend = active_config.background_blend
    if background_blend == false then
        return active_config.blend, FLOAT_WINHIGHLIGHT
    end

    local base = highlight_module.resolve("ScrollbarMinimapBase", background_blend, "base")
    return math.max(active_config.blend, background_blend),
        string.format("Normal:%s,NormalNC:%s,EndOfBuffer:%s", base, base, base)
end

---@type table<integer, ScrollbarMinimapRendererState>
local states = {}

---@type table<integer, ScrollbarMinimapRendererState>
local states_by_float = {}

---@type table<integer, boolean>
local owned_float_buffers = {}

---@type table<integer, table<string, ScrollbarMinimapCellCache>>
local cell_cache = {}

---@type table<integer, table<string, ScrollbarMinimapPendingCells>>
local pending_cells = {}

---@type table<integer, ScrollbarMinimapSemanticInput>
local semantic_inputs = {}

local request_generation = 0

---@type table<integer, integer>
local revealed = {}

---@type integer?
local lifecycle_group
local visible = false

---@type fun(state: ScrollbarMinimapRendererState)?
local state_callback

---@type ScrollbarMinimapRendererOptions?
local options_ref

-- Defined with the state lifecycle below; the source policy releases stale
-- source windows through it.
local close_source

local policy = source_policy.new({
    config = config_module,
    owned_var = OWNED_VAR,
    states_by_float = states_by_float,
    owned_float_buffers = owned_float_buffers,
    tuning = M,
    collect_stale = function(selected, stale)
        for source_win in pairs(states) do
            if not selected[source_win] then
                stale[source_win] = true
            end
        end
        for source_win in pairs(revealed) do
            if not selected[source_win] then
                stale[source_win] = true
            end
        end
        for _, source_win in ipairs(stack.windows("minimap")) do
            if not selected[source_win] then
                stale[source_win] = true
            end
        end
    end,
    close_source = function(source_win)
        close_source(source_win)
    end,
})

local valid_window = policy.valid_window
local owned_window = policy.owned_window
local owned_buffer = policy.owned_buffer
local buffer_eligible = policy.buffer_eligible
local active_source_window = policy.active_source_window
---@type fun(source_win: integer, root_config: ScrollbarMinimapConfig, active_source?: integer, basic_ok?: boolean): ScrollbarMinimapConfigSelection?
local source_selection = policy.source_selection

---@param bufnr integer
local function prune_cell_cache(bufnr)
    local buffer_cache = cell_cache[bufnr]
    if buffer_cache == nil then
        return
    end
    local active = {}
    for _, state in pairs(states) do
        if state.source_buf == bufnr then
            active[state.cells_signature] = true
        end
    end
    for signature in pairs(buffer_cache) do
        if not active[signature] then
            buffer_cache[signature] = nil
        end
    end
    if next(buffer_cache) == nil then
        cell_cache[bufnr] = nil
    end
end

---@param float_buf integer
local function configure_buffer(float_buf)
    float.configure_buffer(float_buf, "scrollbar_minimap", OWNED_VAR)
    owned_float_buffers[float_buf] = true
end

---@param state ScrollbarMinimapRendererState
---@param blend integer
---@param winhighlight string
local function update_window_presentation(state, blend, winhighlight)
    if state.winblend == blend and state.winhighlight == winhighlight then
        return
    end
    vim.api.nvim_set_option_value("winblend", blend, { win = state.float_win })
    vim.api.nvim_set_option_value("winhighlight", winhighlight, { win = state.float_win })
    state.winblend = blend
    state.winhighlight = winhighlight
end

---@param source_win integer
---@return integer height Available rows excluding winbar
local function source_height(source_win)
    local winbar = vim.api.nvim_get_option_value("winbar", { win = source_win })
    local winbar_rows = winbar == "" and 0 or 1
    return math.max(0, vim.api.nvim_win_get_height(source_win) - winbar_rows)
end

---@param source_win integer
---@return integer top Zero-based screen row of the source window top
local function source_top(source_win)
    local winbar = vim.api.nvim_get_option_value("winbar", { win = source_win })
    local winbar_rows = winbar == "" and 0 or 1
    local screen_position = vim.fn.win_screenpos(source_win)
    return screen_position[1] - 1 + winbar_rows
end

---@param source_win integer
---@return integer top Zero-based screenrow
---@return integer height Available rows
local function source_area(source_win)
    return source_top(source_win), source_height(source_win)
end

---@param source_win integer
---@return integer top_line Zero-based, integer bottom_line Zero-based inclusive
local function source_viewport(source_win)
    return vim.api.nvim_win_call(source_win, function()
        return { vim.fn.line("w0") - 1, vim.fn.line("w$") - 1 }
    end)
end

---@param active_config ScrollbarMinimapConfig
---@param source_win integer
---@return ScrollbarStackFootprint
local function stack_footprint(active_config, source_win)
    local placement = active_config.placement
    local west = placement.anchor == "NW" or placement.anchor == "SW"
    local origin
    if west then
        origin = 0
    elseif placement.relative == "window" then
        origin = vim.api.nvim_win_get_width(source_win)
    else
        origin = vim.o.columns
    end
    return {
        relative = placement.relative,
        side = west and "W" or "E",
        origin = origin,
        col = placement.col,
        width = active_config.width,
        zindex = placement.zindex,
        stack = placement.stack,
    }
end

---@param state ScrollbarMinimapRendererState
---@param retain_cache? boolean
local function forget_state(state, retain_cache)
    states[state.source_win] = nil
    states_by_float[state.float_win] = nil
    owned_float_buffers[state.float_buf] = nil
    revealed[state.source_win] = nil
    if not retain_cache then
        prune_cell_cache(state.source_buf)
        policy.invalidate(state.source_win)
    end
end

---@param state ScrollbarMinimapRendererState
---@param retain_cache? boolean
local function close_state(state, retain_cache)
    forget_state(state, retain_cache)
    float.close(state.float_win, state.float_buf)
end

---@param source_win integer
close_source = function(source_win)
    local state = states[source_win]
    if state ~= nil then
        close_state(state)
    else
        revealed[source_win] = nil
        policy.invalidate(source_win)
    end
    stack.publish("minimap", source_win, nil)
end

--- Autohide is a short hide: the footprint stays, so a scrollbar beside the
--- minimap keeps its position.
---@param source_win integer
local function conceal_source(source_win)
    revealed[source_win] = nil
    local state = states[source_win]
    if state ~= nil then
        close_state(state, true)
    end
end

local function close_all_states()
    local pending = {}
    for _, state in pairs(states) do
        table.insert(pending, state)
    end
    for _, state in ipairs(pending) do
        close_state(state)
    end
    stack.clear("minimap")
end

local function sweep_states()
    local pending = {}
    for _, state in pairs(states) do
        if
            not valid_window(state.source_win)
            or not valid_window(state.float_win)
            or not vim.api.nvim_buf_is_valid(state.source_buf)
            or not vim.api.nvim_buf_is_valid(state.float_buf)
            or vim.api.nvim_win_get_buf(state.source_win) ~= state.source_buf
        then
            table.insert(pending, state)
        end
    end
    for _, state in ipairs(pending) do
        close_state(state)
        stack.publish("minimap", state.source_win, nil, { notify = valid_window(state.source_win) })
    end
end

---Translate a canonical cell grid into buffer text rows + per-row highlight
---spans. Each cell is one character, so the span columns count cells.
---@param cells ScrollbarMinimapCell[][]
---@return string[] rows
---@return ScrollbarMinimapHighlightSpan[][] highlights
local function compose_rows(cells)
    if cells == nil then
        return {}, {}
    end
    local rows = {}
    local highlights = {}
    for row = 1, #cells do
        local line_chars = {}
        local line_spans = {}
        local cells_in_row = cells[row]
        for col = 1, #cells_in_row do
            local cell = cells_in_row[col]
            local char = cell.char
            line_chars[col] = char
            if char ~= " " then
                local highlight = cell.hl_group or "ScrollbarMinimapContent"
                local previous = line_spans[#line_spans]
                if previous ~= nil and previous.highlight == highlight and previous.end_col == col then
                    previous.end_col = col + 1
                else
                    line_spans[#line_spans + 1] = {
                        start_col = col,
                        end_col = col + 1,
                        highlight = highlight,
                        priority = CONTENT_PRIORITY,
                    }
                end
            end
        end
        rows[row] = table.concat(line_chars, "")
        highlights[row] = line_spans
    end
    return rows, highlights
end

---Compose non-destructive viewport and point highlight layers.
---@param target_highlights ScrollbarMinimapHighlightSpan[][]
---@param band_first? integer 1-based first float row of the viewport band
---@param band_last? integer 1-based last float row of the viewport band
---@param points ScrollbarMinimapProjectedPoint[]
---@param target_width integer Minimap grid width in cells
---@param show_viewport boolean
local function overlay_layers(target_highlights, band_first, band_last, points, target_width, show_viewport)
    local function add_span(row, start_col, end_col, highlight, priority)
        if target_highlights[row] == nil then
            target_highlights[row] = {}
        end
        table.insert(target_highlights[row], {
            start_col = start_col,
            end_col = end_col,
            highlight = highlight,
            priority = priority,
        })
    end

    if show_viewport and band_first ~= nil and band_last ~= nil then
        for row = band_first, band_last do
            add_span(row, 1, target_width + 1, "ScrollbarMinimapViewport", VIEWPORT_PRIORITY)
        end
    end

    for _, point in ipairs(points) do
        add_span(point.row, point.col, point.col + 1, point.highlight, point.priority)
    end
end

---@class ScrollbarMinimapProjectedPoint
---@field row integer
---@field col integer
---@field highlight string
---@field priority integer
---@field provider string

---Project provider-owned source byte points onto the float rows. Points on
---rows outside the float are skipped.
---@param source_win integer
---@param source_buf integer
---@param projection ScrollbarMinimapProjection
---@return ScrollbarMinimapProjectedPoint[] points
---@return integer? cursor_row
---@return integer? cursor_col
local function project_points(source_win, source_buf, projection)
    local snapshot = store._get_window_snapshot(source_win)
    local provider_names = vim.tbl_keys(snapshot.minimap_points)
    table.sort(provider_names)

    local points = {}
    local cursor_row
    local cursor_col
    local source_lines = {}
    for _, provider in ipairs(provider_names) do
        if providers._consumer_enabled(provider, "minimap") then
            for _, point in ipairs(snapshot.minimap_points[provider]) do
                local row = projection_module.float_row(projection, point.line)
                if row ~= nil then
                    local source_line = source_lines[point.line]
                    if source_line == nil then
                        source_line = vim.api.nvim_buf_get_lines(source_buf, point.line, point.line + 1, true)[1] or ""
                        source_lines[point.line] = source_line
                    end
                    local byte_col = math.min(point.col, #source_line)
                    local ok, display_col = pcall(vim.fn.strdisplaywidth, source_line:sub(1, byte_col))
                    if not ok then
                        display_col = 0
                    end
                    local col = projection_module.cell(projection, display_col)
                    points[#points + 1] = {
                        row = row,
                        col = col,
                        highlight = point.highlight,
                        priority = point.priority,
                        provider = provider,
                    }
                    if provider == "cursor" and cursor_row == nil then
                        cursor_row = row
                        cursor_col = col
                    end
                end
            end
        end
    end
    return points, cursor_row, cursor_col
end

-- Byte offset of each cell of the row being converted. The table is reused
-- across rows and renders, so entries past the current row are stale.
---@type integer[]
local cell_offsets = {}

---Convert the cell spans of every row into the byte-column spans that the
---float buffer shows, with the layer highlight groups resolved. A boundary
---past the last cell maps to the end of the row, and empty spans are dropped.
---@param cells ScrollbarMinimapCell[][]
---@param highlights ScrollbarMinimapHighlightSpan[][]
---@param active_config ScrollbarMinimapConfig
---@return ScrollbarHighlightSpan[][]
local function rendered_highlights(cells, highlights, active_config)
    local resolve_blend = active_config.background_blend ~= false
    local rendered = {}
    for row = 1, #highlights do
        local cells_in_row = cells[row]
        local cell_count = cells_in_row and #cells_in_row or 0
        local row_bytes = 0
        for col = 1, cell_count do
            cell_offsets[col] = row_bytes
            row_bytes = row_bytes + #cells_in_row[col].char
        end

        local row_spans = {}
        for _, span in ipairs(highlights[row]) do
            local first = span.start_col
            local last = span.end_col
            local start_col = first <= 1 and 0 or (first > cell_count and row_bytes or cell_offsets[first])
            local end_col = last <= 1 and 0 or (last > cell_count and row_bytes or cell_offsets[last])
            if start_col < end_col then
                local highlight = span.highlight
                if resolve_blend then
                    highlight = highlight_module.resolve(highlight, active_config.blend, "layer")
                end
                row_spans[#row_spans + 1] = {
                    start_col = start_col,
                    end_col = end_col,
                    highlight = highlight,
                    priority = span.priority,
                }
            end
        end
        rendered[row] = row_spans
    end
    return rendered
end

---@param overlays ScrollbarMinimapOverlay[]
---@return string
local function overlay_signature(overlays)
    if overlays == nil then
        return ""
    end
    local parts = {}
    for index, overlay in ipairs(overlays) do
        parts[index] = overlay.minimap_row .. ":" .. overlay.mark_type
    end
    return table.concat(parts, "|")
end

---@param source_buf integer
---@return integer source_line_count
local function line_count_of(source_buf)
    if not vim.api.nvim_buf_is_valid(source_buf) then
        return 0
    end
    return vim.api.nvim_buf_line_count(source_buf)
end

---@param source_buf integer
---@return ScrollbarMinimapSemanticInput
local function semantic_input(source_buf)
    local snapshot = store._get_snapshot(source_buf)
    local current = semantic_inputs[source_buf]
    if current ~= nil and current.store_revision == snapshot.minimap_span_revision then
        return current
    end

    local spans = {}
    for provider, provider_spans in pairs(snapshot.minimap_spans) do
        if
            #provider_spans > 0
            and providers._consumer_enabled(provider, "minimap")
            and providers._execution_mode(provider) ~= "worker"
        then
            spans[provider] = provider_spans
        end
    end

    local signature = semantic.signature(spans)
    if current ~= nil and current.signature == signature then
        current.store_revision = snapshot.minimap_span_revision
        current.spans = spans
        return current
    end

    local revision = current and current.revision + 1 or (signature == "" and 0 or 1)
    local input = {
        revision = revision,
        store_revision = snapshot.minimap_span_revision,
        signature = signature,
        spans = spans,
    }
    semantic_inputs[source_buf] = input
    return input
end

---Compose the cache key of a source buffer. The key describes the grid
---shape. The slice position and the line scale are stored in the cache
---entry, so a stale entry can still draw while a new slice is pending.
---Viewport and overlay composition are layered on top during render and do
---not require fresh cells from the worker.
---@param source_buf integer
---@param active_config ScrollbarMinimapConfig
---@param target_width integer
---@param target_height integer
---@return string
local function cell_signature(source_buf, active_config, target_width, target_height)
    return string.format(
        "%d:%d:%d:%s:%s:%d",
        source_buf,
        target_width,
        target_height,
        active_config.scale,
        active_config.encoding,
        active_config.columns_per_dot
    )
end

---Whether cached or pending rows serve `projection`.
---@param slice { first_row: integer, row_count: integer, scale_lines: integer, scale_dots: integer }
---@param projection ScrollbarMinimapProjection
---@param margin boolean
---@return boolean
local function slice_serves(slice, projection, margin)
    return slice.scale_lines == projection.scale_lines
        and slice.scale_dots == projection.scale_dots
        and projection_module.covers(projection, slice.first_row, slice.row_count, margin)
end

---Issue a worker request for a grid slice. The sync backend completes
---synchronously and updates the cache via `handle_worker_result` before
---returning; the worker backend returns immediately and the cache is
---updated asynchronously.
---@param source_buf integer
---@param filetype string
---@param grid ScrollbarMinimapGrid
---@param signature string
---@param generation integer
---@param semantic_state ScrollbarMinimapSemanticInput
---@return boolean
local function request_cells(source_buf, filetype, grid, signature, generation, semantic_state)
    local worker = options_ref and options_ref.worker
    if worker == nil or grid.width <= 0 or grid.row_count <= 0 then
        return false
    end
    return worker.request({
        bufnr = source_buf,
        grid = grid,
        filetype = filetype,
        generation = generation,
        signature = signature,
        semantic_revision = semantic_state.revision,
        semantic_spans = semantic_state.spans,
    }) ~= false
end

---@param source_win integer
---@param selection ScrollbarMinimapConfigSelection
---@param root_config ScrollbarMinimapConfig
---@return ScrollbarMinimapRendererState?
local function render_source(source_win, selection, root_config)
    local active_config = selection.config
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    ---@type ScrollbarMinimapRendererState?
    local existing_state = states[source_win]
    if existing_state ~= nil and existing_state.source_buf ~= source_buf then
        close_state(existing_state)
        existing_state = nil
    end
    if root_config.autohide and revealed[source_win] ~= source_buf then
        conceal_source(source_win)
        stack.publish("minimap", source_win, stack_footprint(active_config, source_win))
        return nil
    end

    local area_top, area_height = source_area(source_win)
    local target_height = active_config.height
    if target_height == false then
        target_height = area_height
    end
    target_height = math.max(1, math.min(target_height, area_height))
    local target_width = active_config.width
    if target_width <= 0 then
        close_source(source_win)
        return nil
    end

    local viewport = source_viewport(source_win)
    local viewport_top = viewport[1]
    local viewport_bottom = viewport[2]
    local projection = projection_module.new({
        scale = active_config.scale,
        line_count = line_count_of(source_buf),
        rows = target_height,
        width = target_width,
        columns_per_dot = active_config.columns_per_dot,
        top = viewport_top,
        bottom = viewport_bottom,
    })

    local overlays = {}
    if next(active_config.marks) ~= nil and options_ref and options_ref.overlays then
        overlays = options_ref.overlays.project_with(source_win, projection, active_config.marks)
    end
    local overlay_sig = overlay_signature(overlays)

    local desired_cells_signature = cell_signature(source_buf, active_config, target_width, target_height)
    local changedtick = vim.api.nvim_buf_get_changedtick(source_buf)
    local filetype = vim.bo[source_buf].filetype
    local semantic_state = semantic_input(source_buf)
    local buffer_cache = cell_cache[source_buf]
    local cache = buffer_cache and buffer_cache[desired_cells_signature] or nil
    if
        cache == nil
        or cache.changedtick ~= changedtick
        or cache.semantic_revision ~= semantic_state.revision
        or cache.filetype ~= filetype
        or not slice_serves(cache, projection, true)
    then
        local buffer_pending = pending_cells[source_buf]
        if buffer_pending == nil then
            buffer_pending = {}
            pending_cells[source_buf] = buffer_pending
        end
        local pending = buffer_pending[desired_cells_signature]
        if
            pending == nil
            or pending.changedtick ~= changedtick
            or pending.semantic_revision ~= semantic_state.revision
            or pending.filetype ~= filetype
            or not slice_serves(pending.grid, projection, false)
        then
            local first_row, row_count = projection_module.slice(projection)
            request_generation = request_generation + 1
            pending = {
                changedtick = changedtick,
                semantic_revision = semantic_state.revision,
                generation = request_generation,
                filetype = filetype,
                grid = {
                    width = target_width,
                    first_row = first_row,
                    row_count = row_count,
                    scale_lines = projection.scale_lines,
                    scale_dots = projection.scale_dots,
                    columns_per_dot = active_config.columns_per_dot,
                    encoding = active_config.encoding,
                },
            }
            buffer_pending[desired_cells_signature] = pending
            if
                not request_cells(
                    source_buf,
                    filetype,
                    pending.grid,
                    desired_cells_signature,
                    pending.generation,
                    semantic_state
                ) and buffer_pending[desired_cells_signature] == pending
            then
                buffer_pending[desired_cells_signature] = nil
            end
        end
        buffer_cache = cell_cache[source_buf]
        cache = buffer_cache and buffer_cache[desired_cells_signature] or cache
    end
    if cache == nil then
        cache = {
            signature = desired_cells_signature,
            cells = {},
            first_row = 0,
            row_count = 0,
            scale_lines = projection.scale_lines,
            scale_dots = projection.scale_dots,
            revision = 0,
            changedtick = changedtick,
            semantic_revision = semantic_state.revision,
            filetype = filetype,
            source_line_count = projection.line_count,
            mirror_signature = "",
        }
    end

    -- Rows outside the cached slice stay blank until the pending slice
    -- arrives. Rows past the end of the map are always blank.
    local cells = {}
    local blank_row
    for row = 1, target_height do
        local cached = cache.cells[projection.offset + row - cache.first_row]
        if cached == nil then
            if blank_row == nil then
                blank_row = {}
                for col = 1, target_width do
                    blank_row[col] = { char = " " }
                end
            end
            cached = blank_row
        end
        cells[row] = cached
    end
    local rows, highlights = compose_rows(cells)
    for index = #rows, target_height + 1, -1 do
        rows[index] = nil
        highlights[index] = nil
    end
    while #rows < target_height do
        rows[#rows + 1] = ""
        highlights[#highlights + 1] = {}
    end
    for index = 1, #rows do
        if highlights[index] == nil then
            highlights[index] = {}
        end
    end

    local points, cursor_row, cursor_col = project_points(source_win, source_buf, projection)

    for _, overlay in ipairs(overlays) do
        local row = overlay.minimap_row
        if highlights[row] == nil then
            highlights[row] = {}
        end
        local cells_in_row = cells[row] or {}
        local run_start
        for col = 1, #cells_in_row + 1 do
            local occupied = col <= #cells_in_row and cells_in_row[col].char ~= " "
            if occupied and run_start == nil then
                run_start = col
            elseif not occupied and run_start ~= nil then
                table.insert(highlights[row], {
                    start_col = run_start,
                    end_col = col,
                    highlight = overlay.highlight,
                    priority = 3 + (10 - math.min(10, overlay.priority)),
                })
                run_start = nil
            end
        end
    end

    local band_first, band_last = projection_module.band(projection)
    overlay_layers(highlights, band_first, band_last, points, target_width, active_config.viewport)

    local active_winblend, active_winhighlight = window_presentation(active_config)
    local rendered = rendered_highlights(cells, highlights, active_config)
    local cursor_screen_row, cursor_screen_col = float.cursor_screen_position(source_win, active_config)
    local cursor_position_available = cursor_screen_row ~= nil and cursor_screen_col ~= nil
    local footprint = stack_footprint(active_config, source_win)
    local stack_origin, stack_zindex = stack.resolve("minimap", source_win, footprint)
    local origin = stack_origin or footprint.origin
    ---@type ScrollbarMinimapRendererState?
    local state = states[source_win]
    if state == nil or not valid_window(state.float_win) or not vim.api.nvim_buf_is_valid(state.float_buf) then
        if state ~= nil then
            close_state(state)
        end
        local desired = float.config(
            active_config,
            source_win,
            area_top,
            area_height,
            origin,
            stack_zindex,
            target_width,
            target_height,
            cursor_position_available
        )
        local float_win, float_buf = float.open(
            "scrollbar_minimap://%d/%d",
            source_win,
            desired,
            configure_buffer,
            function(opened_win)
                float.configure_window(opened_win, OWNED_VAR, active_winhighlight, active_winblend)
            end
        )
        -- The zero size makes the first write fill the whole buffer.
        state = {
            source_win = source_win,
            source_buf = source_buf,
            config = active_config,
            variant_id = selection.variant_id,
            float_win = float_win,
            float_buf = float_buf,
            float_config = desired,
            width = 0,
            height = 0,
            projection = projection,
            rows = {},
            highlights = {},
            rendered_highlights = {},
            rendered_signature = "",
            viewport_top = viewport_top,
            viewport_bottom = viewport_bottom,
            cursor_row = cursor_row,
            cursor_col = cursor_col,
            overlay_signature = overlay_sig,
            cells_signature = cache and cache.signature or "",
            hidden_by_cursor = desired.hide == true,
            winblend = active_winblend,
            winhighlight = active_winhighlight,
            footprint = footprint,
        }
        states[source_win] = state
        states_by_float[float_win] = state
        if cursor_position_available then
            float.resolve_position()
        end
    else
        local desired = float.config(
            active_config,
            source_win,
            area_top,
            area_height,
            origin,
            stack_zindex,
            target_width,
            target_height,
            cursor_position_available and state.hidden_by_cursor or false
        )
        float.apply_config(state, desired, cursor_position_available)
        state.source_buf = source_buf
        state.config = active_config
        state.variant_id = selection.variant_id
    end

    float.update_cursor_visibility(state, cursor_screen_row, cursor_screen_col)
    update_window_presentation(state, active_winblend, active_winhighlight)

    float.write_rows(
        state.float_buf,
        NAMESPACE,
        state.rows,
        state.rendered_highlights,
        rows,
        rendered,
        state.width ~= target_width or state.height ~= target_height
    )

    state.width = target_width
    state.height = target_height
    state.projection = projection
    state.rows = rows
    state.highlights = highlights
    state.rendered_highlights = rendered
    state.viewport_top = viewport_top
    state.viewport_bottom = viewport_bottom
    state.cursor_row = cursor_row
    state.cursor_col = cursor_col
    state.overlay_signature = overlay_sig
    state.cells_signature = cache.signature
    state.rendered_signature = cache.signature
    state.footprint = footprint
    prune_cell_cache(source_buf)
    stack.publish("minimap", source_win, footprint)

    if state_callback ~= nil then
        pcall(state_callback, state)
    end
    return state
end

---@param source_win integer
---@return ScrollbarMinimapRendererState?
M.render = function(source_win)
    if source_win == nil or source_win == 0 then
        source_win = vim.api.nvim_get_current_win()
    end
    if not visible then
        close_source(source_win)
        return nil
    end

    local root_config = config_module.get()
    local active_source = active_source_window()
    local selection = source_selection(source_win, root_config, active_source)
    if root_config.visibility == "active" then
        if selection == nil then
            close_source(source_win)
            return nil
        end
    elseif selection == nil then
        close_source(source_win)
        return nil
    end

    local ok, state = pcall(render_source, source_win, selection, root_config)
    if not ok then
        close_source(source_win)
        return nil
    end
    return state
end

--- Resolve the stacked origin and z-index of one minimap float again, after
--- the scrollbar footprint of its source window changes. The content does not
--- render again.
---@param source_win integer
---@return boolean changed
M.reposition = function(source_win)
    local state = states[source_win]
    if state == nil or not valid_window(source_win) or not valid_window(state.float_win) then
        return false
    end
    local footprint = state.footprint
    local origin, zindex = stack.resolve("minimap", source_win, footprint)
    return float.reposition(state, footprint, origin, zindex)
end

---@param source_win integer
---@return ScrollbarMinimapRendererState?
M.get_state = function(source_win)
    return states[source_win]
end

---@param float_win integer
---@return ScrollbarMinimapRendererState?
M.get_state_by_float = function(float_win)
    return states_by_float[float_win]
end

---@param source_win integer
---@return boolean
M.reveal = function(source_win)
    local root_config = config_module.get()
    if not visible or source_selection(source_win, root_config, active_source_window()) == nil then
        return false
    end
    if root_config.autohide then
        revealed[source_win] = vim.api.nvim_win_get_buf(source_win)
    end
    return true
end

---@param source_win integer
---@return boolean
M.conceal = function(source_win)
    if not config_module.get().autohide then
        return false
    end
    local was_revealed = revealed[source_win] ~= nil or states[source_win] ~= nil
    conceal_source(source_win)
    return was_revealed
end

---Worker result callback. Updates the dimension-specific cell cache and bumps
---the revision so the next render picks up fresh content. `scrollbar.minimap`
---wires the worker's `on_result` to this handler plus a scheduler
---invalidation.
---@param payload table
M.handle_worker_result = function(payload)
    if type(payload) ~= "table" or type(payload.bufnr) ~= "number" then
        return
    end
    local bufnr = payload.bufnr
    local signature = payload.signature
    if type(signature) ~= "string" then
        return
    end
    local buffer_pending = pending_cells[bufnr]
    local pending = buffer_pending and buffer_pending[signature] or nil
    if pending == nil then
        return
    end

    local generation = payload.generation or pending.generation
    local semantic_revision = payload.semantic_revision
    if semantic_revision == nil then
        semantic_revision = pending.semantic_revision
    end
    if generation ~= pending.generation or semantic_revision ~= pending.semantic_revision then
        return
    end
    local filetype = payload.filetype or pending.filetype
    if filetype ~= pending.filetype then
        return
    end

    local changedtick = payload.changedtick
    if type(changedtick) ~= "number" then
        changedtick = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_changedtick(bufnr) or 0
    end
    if
        not vim.api.nvim_buf_is_valid(bufnr)
        or vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick
        or vim.bo[bufnr].filetype ~= filetype
        or semantic_input(bufnr).revision ~= semantic_revision
    then
        return
    end

    if
        payload.worker_spans ~= nil
        and providers._consumer_enabled("treesitter", "minimap")
        and providers._execution_mode("treesitter") == "worker"
    then
        store.set_minimap_spans("treesitter", bufnr, payload.worker_spans)
    end
    local accepted_semantic_revision = semantic_input(bufnr).revision
    local buffer_cache = cell_cache[bufnr]
    if buffer_cache == nil then
        buffer_cache = {}
        cell_cache[bufnr] = buffer_cache
    end
    local existing = buffer_cache[signature]
    local grid = pending.grid
    if existing == nil or changedtick >= existing.changedtick then
        buffer_cache[signature] = {
            signature = signature,
            cells = payload.cells or {},
            first_row = grid.first_row,
            row_count = grid.row_count,
            scale_lines = grid.scale_lines,
            scale_dots = grid.scale_dots,
            revision = (existing and existing.revision or 0) + 1,
            changedtick = changedtick,
            semantic_revision = accepted_semantic_revision,
            filetype = filetype,
            source_line_count = line_count_of(bufnr),
            mirror_signature = signature,
        }
    end
    if buffer_pending ~= nil then
        if buffer_pending[signature] == pending then
            buffer_pending[signature] = nil
        end
        if next(buffer_pending) == nil then
            pending_cells[bufnr] = nil
        end
    end
    local source_win
    for winid, state in pairs(states) do
        if state.source_buf == bufnr then
            source_win = winid
            break
        end
    end
    if source_win == nil then
        return
    end
    if options_ref and type(options_ref.on_dirty) == "function" then
        options_ref.on_dirty(source_win)
    end
end

M.handle_worker_failure = function()
    pending_cells = {}
    local dirtied = {}
    if options_ref and type(options_ref.on_dirty) == "function" then
        for source_win in pairs(states) do
            if not dirtied[source_win] then
                dirtied[source_win] = true
                options_ref.on_dirty(source_win)
            end
        end
    end
end

---@param callback? fun(state: ScrollbarMinimapRendererState)
M.set_state_callback = function(callback)
    state_callback = callback
    if callback == nil then
        return
    end
    for _, state in pairs(states) do
        pcall(callback, state)
    end
end

---@type fun(winid: integer): boolean
M.is_owned_window = owned_window

--- Registry-only ownership checks, as in the scrollbar renderer: the variable
--- fallbacks only matter for orphans of an earlier setup, which the setup
--- sweep detects through `is_owned_*`.
---@param winid integer
---@return boolean
M.is_owned_float_window = function(winid)
    return states_by_float[winid] ~= nil
end

---@type fun(bufnr: integer): integer[]
M.windows_showing_buffer = policy.windows_showing_buffer

---@type fun(bufnr: integer): boolean
M.is_owned_buffer = owned_buffer

---@param bufnr integer
---@return boolean
M.is_owned_float_buffer = function(bufnr)
    return owned_float_buffers[bufnr] == true
end

---@param bufnr integer
---@return boolean
M.is_buffer_eligible = function(bufnr)
    return buffer_eligible(bufnr, config_module.get())
end

--- The result is memoized for 50 ms.
---@type fun(winid: integer): boolean
M.is_source_window = policy.is_source_window

---Clear cached source eligibility (one window or all). Wired to the
---scheduler's topology/option events; safe to call at any time.
---@type fun(source_win?: integer)
M.invalidate_source_selection = policy.invalidate

---@type fun(bufnr?: integer): integer[]
M.source_windows = policy.source_windows

M.hide = function()
    visible = false
    revealed = {}
    close_all_states()
    cell_cache = {}
    pending_cells = {}
end

M.show = function()
    visible = true
end

M.toggle = function()
    if visible then
        M.hide()
    else
        M.show()
    end
end

---@return boolean
M.is_visible = function()
    return visible
end

---@return integer namespace Nvim namespace id used for the minimap extmarks
M.namespace = function()
    return NAMESPACE
end

---@param source_win? integer
M.dispose = function(source_win)
    if source_win ~= nil then
        close_source(source_win)
        return
    end

    visible = false
    revealed = {}
    close_all_states()
    cell_cache = {}
    pending_cells = {}
    semantic_inputs = {}
    request_generation = 0
    if lifecycle_group ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, lifecycle_group)
        lifecycle_group = nil
    end
    options_ref = nil
end

---@param options ScrollbarMinimapRendererOptions
M.setup = function(options)
    M.dispose()
    options = options or {}
    options_ref = options
    visible = options.visible ~= false
    lifecycle_group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = lifecycle_group,
        callback = function(args)
            local closed_win = tonumber(args.match)
            if closed_win == nil then
                return
            end
            local state = states[closed_win] or states_by_float[closed_win]
            if state ~= nil then
                close_state(state)
            else
                revealed[closed_win] = nil
                policy.invalidate(closed_win)
            end
            -- A closing source window takes the scrollbar float with it, so
            -- only a closed minimap float repositions the scrollbar.
            local source_win = state and state.source_win or closed_win
            stack.publish("minimap", source_win, nil, { notify = source_win ~= closed_win })
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = lifecycle_group,
        callback = function(args)
            local pending = {}
            for _, state in pairs(states) do
                if state.source_buf == args.buf or state.float_buf == args.buf then
                    table.insert(pending, state)
                end
            end
            for _, state in ipairs(pending) do
                close_state(state)
                stack.publish("minimap", state.source_win, nil)
            end
            cell_cache[args.buf] = nil
            pending_cells[args.buf] = nil
            semantic_inputs[args.buf] = nil
        end,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = lifecycle_group,
        callback = sweep_states,
    })
end

return M
