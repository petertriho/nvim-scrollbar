--- Minimap renderer: per-source-window float lifecycle, composes squashed
--- cells plus semantic, viewport, and cursor highlight layers into a visible
--- scratch buffer. Parallels `lua/scrollbar/renderer.lua` but is independent.
---
--- Float placement reuses the anchor/row/col math from the scrollbar
--- renderer (copied, not imported, per the plan non-goal of no shared
--- runtime modules). Squash output is the only source of row text; viewport,
--- cursor, and semantic overlays are non-destructive extmark highlights.
---
--- State cache is keyed by
--- `(source_win, source_buf, mirror_signature, viewport, width, height, overlay_signature)`
--- so unchanged renders reuse the prior buffer contents and highlights.

local config_module = require("scrollbar.minimap.config")
local highlight_module = require("scrollbar.minimap.highlights")
local providers = require("scrollbar.providers")
local semantic = require("scrollbar.minimap.semantic")
local store = require("scrollbar.store")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarMinimapRenderer")
local AUGROUP_NAME = "ScrollbarMinimapRendererLifecycle"
local FLOAT_WINHIGHLIGHT = "Normal:ScrollbarMinimapBase,NormalNC:ScrollbarMinimapBase,EndOfBuffer:ScrollbarMinimapBase"
local OWNED_WIN_VAR = "scrollbar_minimap_owned"
local OWNED_BUF_VAR = "scrollbar_minimap_owned"
local VIEWPORT_PRIORITY = 1
local CONTENT_PRIORITY = 2

---@param active_config ScrollbarMinimapConfig
---@return integer blend
---@return string winhighlight
local function window_presentation(active_config)
    local background_blend = active_config.background.blend
    if background_blend == false then
        return active_config.float.blend, FLOAT_WINHIGHLIGHT
    end

    local base = highlight_module.resolve("ScrollbarMinimapBase", background_blend, "base")
    return math.max(active_config.float.blend, background_blend),
        string.format("Normal:%s,NormalNC:%s,EndOfBuffer:%s", base, base, base)
end

---@type table<integer, ScrollbarMinimapRendererState>
local states = {}

---@type table<integer, ScrollbarMinimapRendererState>
local states_by_float = {}

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

---@param value any
---@param values string[]
---@return boolean
local function contains(values, value)
    for _, item in ipairs(values) do
        if item == value then
            return true
        end
    end
    return false
end

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

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---@param float_buf integer
local function configure_buffer(float_buf)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = float_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = float_buf })
    vim.api.nvim_set_option_value("undolevels", -1, { buf = float_buf })
    vim.api.nvim_set_option_value("filetype", "scrollbar_minimap", { buf = float_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    vim.api.nvim_buf_set_var(float_buf, OWNED_BUF_VAR, true)
end

---@param float_win integer
---@param blend integer Window pseudo-transparency (winblend), 0-100
---@param winhighlight string
local function configure_window(float_win, blend, winhighlight)
    vim.api.nvim_set_option_value("wrap", false, { win = float_win })
    vim.api.nvim_set_option_value("number", false, { win = float_win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = float_win })
    vim.api.nvim_set_option_value("signcolumn", "no", { win = float_win })
    vim.api.nvim_set_option_value("foldcolumn", "0", { win = float_win })
    vim.api.nvim_set_option_value("statuscolumn", "", { win = float_win })
    vim.api.nvim_set_option_value("cursorline", false, { win = float_win })
    vim.api.nvim_set_option_value("cursorcolumn", false, { win = float_win })
    vim.api.nvim_set_option_value("winfixbuf", true, { win = float_win })
    vim.api.nvim_set_option_value("list", false, { win = float_win })
    vim.api.nvim_set_option_value("spell", false, { win = float_win })
    vim.api.nvim_set_option_value("winhighlight", winhighlight, { win = float_win })
    vim.api.nvim_set_option_value("winblend", blend or 0, { win = float_win })
    vim.api.nvim_win_set_var(float_win, OWNED_WIN_VAR, true)
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

---@param winid integer
---@return boolean
local function owned_window(winid)
    if states_by_float[winid] ~= nil then
        return true
    end
    if not valid_window(winid) then
        return false
    end
    local ok, owned = pcall(vim.api.nvim_win_get_var, winid, OWNED_WIN_VAR)
    return ok and owned == true
end

---@param bufnr integer
---@return boolean
local function owned_buffer(bufnr)
    if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    local ok, owned = pcall(vim.api.nvim_buf_get_var, bufnr, OWNED_BUF_VAR)
    return ok and owned == true
end

---@param winid integer
---@return boolean
local function normal_window(winid)
    if not valid_window(winid) or owned_window(winid) then
        return false
    end
    local ok, window_config = pcall(vim.api.nvim_win_get_config, winid)
    return ok and window_config.relative == ""
end

---@param bufnr integer
---@param root_config ScrollbarMinimapConfig
---@return boolean
local function buffer_eligible(bufnr, root_config)
    if
        not root_config.enabled
        or type(bufnr) ~= "number"
        or not vim.api.nvim_buf_is_valid(bufnr)
        or not vim.api.nvim_buf_is_loaded(bufnr)
        or owned_buffer(bufnr)
    then
        return false
    end

    if contains(root_config.excluded_buftypes, vim.bo[bufnr].buftype) then
        return false
    end
    if contains(root_config.excluded_filetypes, vim.bo[bufnr].filetype) then
        return false
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    return root_config.max_lines == false or line_count <= root_config.max_lines
end

---@param source_win integer
---@param root_config ScrollbarMinimapConfig
---@return boolean
local function basic_eligible(source_win, root_config)
    return normal_window(source_win) and buffer_eligible(vim.api.nvim_win_get_buf(source_win), root_config)
end

---@return integer?
local function active_source_window()
    local current = vim.api.nvim_get_current_win()
    local owned_state = states_by_float[current]
    if owned_state ~= nil and valid_window(owned_state.source_win) then
        return owned_state.source_win
    end
    if normal_window(current) then
        return current
    end
end

---@param source_win integer
---@param root_config ScrollbarMinimapConfig
---@param active_source? integer
---@return ScrollbarMinimapConfigSelection?
local function source_selection(source_win, root_config, active_source)
    if not basic_eligible(source_win, root_config) then
        return nil
    end
    if root_config.visibility == "active" and source_win ~= active_source then
        return nil
    end
    local selection = config_module.select(source_win)
    if selection.config.float.placement.relative == "editor" and source_win ~= active_source then
        return nil
    end
    return selection
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

---Compute the float config for the minimap window. Mirrors the scrollbar
---renderer's float_config math at `lua/scrollbar/renderer.lua:545-576` but
---uses the minimap's own width/height and placement.
---@param active_config ScrollbarMinimapConfig
---@param source_win integer
---@param area_top integer
---@param area_height integer
---@param editor_columns integer
---@param target_width integer
---@param target_height integer
---@param hidden boolean
---@return table<string, any>
local function float_config(
    active_config,
    source_win,
    area_top,
    area_height,
    editor_columns,
    target_width,
    target_height,
    hidden
)
    local placement = active_config.float.placement
    local north = placement.anchor == "NW" or placement.anchor == "NE"
    local west = placement.anchor == "NW" or placement.anchor == "SW"

    local vertical_anchor
    if placement.relative == "window" then
        vertical_anchor = north and 0 or area_height
    else
        vertical_anchor = north and area_top or (area_top + area_height)
    end
    local horizontal_origin
    if west then
        horizontal_origin = 0
    elseif placement.relative == "window" then
        horizontal_origin = vim.api.nvim_win_get_width(source_win)
    else
        horizontal_origin = editor_columns
    end

    local result = {
        relative = placement.relative == "window" and "win" or "editor",
        anchor = placement.anchor,
        row = vertical_anchor + placement.row,
        col = horizontal_origin + placement.col,
        width = target_width,
        height = target_height,
        focusable = active_config.mouse.enabled,
        mouse = active_config.mouse.enabled,
        zindex = active_config.float.zindex,
        hide = hidden,
    }
    if placement.relative == "window" then
        result.win = source_win
    end
    return result
end

---@param float_win integer
---@param expected table<string, any>
---@return boolean
local function has_float_config(float_win, expected)
    local ok, current = pcall(vim.api.nvim_win_get_config, float_win)
    if not ok then
        return false
    end
    for key, value in pairs(expected) do
        if not vim.deep_equal(current[key], value) then
            return false
        end
    end
    return true
end

---@param source_win integer
---@param active_config ScrollbarMinimapConfig
---@return integer? row
---@return integer? col
local function cursor_screen_position(source_win, active_config)
    if not active_config.float.hide_on_cursor or vim.api.nvim_get_current_win() ~= source_win then
        return nil, nil
    end

    local cursor_row = vim.fn.screenrow()
    local cursor_col = vim.fn.screencol()
    if type(cursor_row) ~= "number" or type(cursor_col) ~= "number" or cursor_row <= 0 or cursor_col <= 0 then
        return nil, nil
    end

    return cursor_row - 1, cursor_col - 1
end

---@param state ScrollbarMinimapRendererState
---@param cursor_row? integer
---@param cursor_col? integer
---@return boolean
local function cursor_overlaps_float(state, cursor_row, cursor_col)
    if cursor_row == nil or cursor_col == nil then
        return false
    end

    local ok, position = pcall(vim.api.nvim_win_get_position, state.float_win)
    if not ok or type(position) ~= "table" then
        return false
    end

    local top = position[1]
    local left = position[2]
    local height = state.float_config.height
    local width = state.float_config.width
    if
        type(top) ~= "number"
        or type(left) ~= "number"
        or type(height) ~= "number"
        or type(width) ~= "number"
        or height <= 0
        or width <= 0
    then
        return false
    end

    return cursor_row >= top and cursor_row < top + height and cursor_col >= left and cursor_col < left + width
end

---@param state ScrollbarMinimapRendererState
---@param cursor_row? integer
---@param cursor_col? integer
local function update_cursor_visibility(state, cursor_row, cursor_col)
    local hidden = cursor_overlaps_float(state, cursor_row, cursor_col)
    if state.hidden_by_cursor == hidden then
        return
    end

    local active_float_config = vim.deepcopy(state.float_config)
    active_float_config.hide = hidden
    vim.api.nvim_win_set_config(state.float_win, active_float_config)
    state.float_config = active_float_config
    state.hidden_by_cursor = hidden
end

local function resolve_float_position()
    -- Anchored positions settle during redraw; flush while hidden so the first visible frame is correct.
    vim.api.nvim__redraw({ flush = true })
end

---@param state ScrollbarMinimapRendererState
---@param retain_cache? boolean
local function forget_state(state, retain_cache)
    states[state.source_win] = nil
    states_by_float[state.float_win] = nil
    revealed[state.source_win] = nil
    if not retain_cache then
        prune_cell_cache(state.source_buf)
    end
end

---@param state ScrollbarMinimapRendererState
---@param retain_cache? boolean
local function close_state(state, retain_cache)
    forget_state(state, retain_cache)
    if valid_window(state.float_win) then
        pcall(vim.api.nvim_win_close, state.float_win, true)
    end
    if vim.api.nvim_buf_is_valid(state.float_buf) then
        pcall(vim.api.nvim_buf_delete, state.float_buf, { force = true })
    end
end

---@param source_win integer
local function close_source(source_win)
    local state = states[source_win]
    if state ~= nil then
        close_state(state)
    else
        revealed[source_win] = nil
    end
end

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
    end
end

---Translate a canonical cell grid into buffer text rows + per-row highlight spans.
---@param cells ScrollbarMinimapCell[][]
---@param content_glyph string Glyph used for every occupied cell
---@return string[] rows
---@return ScrollbarMinimapHighlightSpan[][] highlights
local function compose_rows(cells, content_glyph)
    if cells == nil then
        return {}, {}
    end
    local rows = {}
    local highlights = {}
    for row = 1, #cells do
        local line_chars = {}
        local line_spans = {}
        local cells_in_row = cells[row]
        local col = 1
        for c = 1, #cells_in_row do
            local cell = cells_in_row[c]
            local occupied = cell.char ~= " "
            local char = occupied and content_glyph or " "
            local width = vim.fn.strdisplaywidth(char)
            if width <= 0 then
                width = 1
            end
            line_chars[c] = char
            local highlight = occupied and (cell.hl_group or "ScrollbarMinimapContent") or nil
            if highlight ~= nil then
                local previous = line_spans[#line_spans]
                if previous ~= nil and previous.highlight == highlight and previous.end_col == col then
                    previous.end_col = col + width
                else
                    line_spans[#line_spans + 1] = {
                        start_col = col,
                        end_col = col + width,
                        highlight = highlight,
                        priority = CONTENT_PRIORITY,
                    }
                end
            end
            col = col + width
        end
        rows[row] = table.concat(line_chars, "")
        highlights[row] = line_spans
    end
    return rows, highlights
end

---Compose non-destructive viewport and point highlight layers.
---@param target_highlights ScrollbarMinimapHighlightSpan[][]
---@param viewport_top_row integer 1-based first row of viewport in minimap
---@param viewport_bottom_row integer 1-based last row of viewport in minimap
---@param points ScrollbarMinimapProjectedPoint[]
---@param target_width integer Minimap grid width in cells
---@param show_viewport boolean
local function overlay_layers(
    target_highlights,
    viewport_top_row,
    viewport_bottom_row,
    points,
    target_width,
    show_viewport
)
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

    if show_viewport and viewport_top_row <= viewport_bottom_row then
        for row = viewport_top_row, viewport_bottom_row do
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

---Project provider-owned source byte points onto the completed squash grid.
---@param source_win integer
---@param source_buf integer
---@param target_height integer
---@param target_width integer
---@param v_ratio number
---@param h_ratio number
---@return ScrollbarMinimapProjectedPoint[] points
---@return integer? cursor_row
---@return integer? cursor_col
local function project_points(source_win, source_buf, target_height, target_width, v_ratio, h_ratio)
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
                local row = math.max(1, math.min(target_height, math.floor(point.line / v_ratio) + 1))
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
                local col = math.max(1, math.min(target_width, math.floor(display_col / h_ratio) + 1))
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
    return points, cursor_row, cursor_col
end

---Convert a one-based minimap cell boundary to a zero-based byte offset.
---@param row_text string
---@param boundary integer
---@return integer
local function cell_boundary_to_byte(row_text, boundary)
    local byte_col = vim.fn.byteidx(row_text, math.max(0, boundary - 1))
    if byte_col < 0 then
        return #row_text
    end
    return math.min(byte_col, #row_text)
end

---@param rows string[]
---@param highlights ScrollbarMinimapHighlightSpan[][]
---@param active_config ScrollbarMinimapConfig
local function write_highlights(float_buf, rows, highlights, active_config)
    vim.api.nvim_buf_clear_namespace(float_buf, NAMESPACE, 0, -1)
    for row = 1, #rows do
        local spans = highlights[row] or {}
        for _, span in ipairs(spans) do
            local start_col = cell_boundary_to_byte(rows[row], span.start_col)
            local end_col = cell_boundary_to_byte(rows[row], span.end_col)
            if start_col < end_col then
                local highlight = span.highlight
                if active_config.background.blend ~= false then
                    highlight = highlight_module.resolve(highlight, active_config.float.blend, "layer")
                end
                vim.api.nvim_buf_set_extmark(float_buf, NAMESPACE, row - 1, start_col, {
                    end_row = row - 1,
                    end_col = end_col,
                    hl_group = highlight,
                    hl_mode = "combine",
                    priority = span.priority,
                    strict = false,
                })
            end
        end
    end
end

---@param float_buf integer
---@param callback fun()
local function with_modifiable(float_buf, callback)
    vim.api.nvim_set_option_value("modifiable", true, { buf = float_buf })
    local ok, error_message = pcall(callback)
    if vim.api.nvim_buf_is_valid(float_buf) then
        vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    end
    if not ok then
        error(error_message)
    end
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

---Compose the worker request signature for a source buffer. The signature
---describes only the dimensions that drive the squash output; viewport
---and overlay composition are layered on top during render and do not
---require fresh cells from the worker.
---@param source_buf integer
---@param target_width integer
---@param target_height integer
---@return string
local function cell_signature(source_buf, target_width, target_height)
    return string.format("%d:%d:%d", source_buf, target_width, target_height)
end

---Issue a worker request for the desired grid. The sync backend completes
---synchronously and updates the cache via `handle_worker_result` before
---returning; the worker backend returns immediately and the cache is
---updated asynchronously.
---@param source_buf integer
---@param filetype string
---@param target_width integer
---@param target_height integer
---@param generation integer
---@param semantic_state ScrollbarMinimapSemanticInput
---@return boolean
local function request_cells(source_buf, filetype, target_width, target_height, generation, semantic_state)
    local worker = options_ref and options_ref.worker
    if worker == nil or target_width <= 0 or target_height <= 0 then
        return false
    end
    local signature = cell_signature(source_buf, target_width, target_height)
    return worker.request({
        bufnr = source_buf,
        width = target_width,
        height = target_height,
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
    if root_config.autohide.enabled and revealed[source_win] ~= source_buf then
        conceal_source(source_win)
        return nil
    end

    local area_top, area_height = source_area(source_win)
    local target_height = active_config.height
    if target_height == false then
        target_height = area_height
    end
    target_height = math.max(1, math.min(target_height, area_height))
    local target_width = active_config.width
    if target_width == false then
        target_width = 16
    end
    if target_width <= 0 then
        close_source(source_win)
        return nil
    end

    local viewport = source_viewport(source_win)
    local viewport_top = viewport[1]
    local viewport_bottom = viewport[2]
    local source_line_count = line_count_of(source_buf)
    local v_ratio = math.max(1, source_line_count / target_height)
    local viewport_top_row = math.max(1, math.min(target_height, math.floor(viewport_top / v_ratio) + 1))
    local viewport_bottom_row = math.max(1, math.min(target_height, math.floor(viewport_bottom / v_ratio) + 1))

    local overlays = {}
    if active_config.overlays.enabled and options_ref and options_ref.overlays then
        overlays =
            options_ref.overlays.project_with(source_win, target_height, source_line_count, active_config.overlays)
    end
    local overlay_sig = overlay_signature(overlays)

    local desired_cells_signature = cell_signature(source_buf, target_width, target_height)
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
        then
            request_generation = request_generation + 1
            pending = {
                changedtick = changedtick,
                semantic_revision = semantic_state.revision,
                generation = request_generation,
                filetype = filetype,
            }
            buffer_pending[desired_cells_signature] = pending
            if
                not request_cells(source_buf, filetype, target_width, target_height, pending.generation, semantic_state)
                and buffer_pending[desired_cells_signature] == pending
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
            revision = 0,
            changedtick = changedtick,
            semantic_revision = semantic_state.revision,
            filetype = filetype,
            source_line_count = source_line_count,
            max_line_width = 0,
            mirror_signature = "",
        }
    end

    local cells = cache and cache.cells or {}
    local rows, highlights = compose_rows(cells, active_config.content_glyph)
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

    local max_line_width = (cache and cache.max_line_width) or 0
    local h_ratio = math.max(1, max_line_width / target_width)
    local points, cursor_row, cursor_col =
        project_points(source_win, source_buf, target_height, target_width, v_ratio, h_ratio)

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

    overlay_layers(highlights, viewport_top_row, viewport_bottom_row, points, target_width, active_config.show_viewport)

    local active_winblend, active_winhighlight = window_presentation(active_config)
    local cursor_screen_row, cursor_screen_col = cursor_screen_position(source_win, active_config)
    local cursor_position_available = cursor_screen_row ~= nil and cursor_screen_col ~= nil
    ---@type ScrollbarMinimapRendererState?
    local state = states[source_win]
    if state == nil or not valid_window(state.float_win) or not vim.api.nvim_buf_is_valid(state.float_buf) then
        if state ~= nil then
            close_state(state)
        end
        local desired = float_config(
            active_config,
            source_win,
            area_top,
            area_height,
            vim.o.columns,
            target_width,
            target_height,
            cursor_position_available
        )
        desired.style = "minimal"
        local float_buf = vim.api.nvim_create_buf(false, true)
        configure_buffer(float_buf)
        pcall(vim.api.nvim_buf_set_name, float_buf, string.format("scrollbar_minimap://%d/%d", source_win, float_buf))
        local float_win = vim.api.nvim_open_win(float_buf, false, desired)
        desired.style = nil
        configure_window(float_win, active_winblend, active_winhighlight)
        state = {
            source_win = source_win,
            source_buf = source_buf,
            config = active_config,
            variant_id = selection.variant_id,
            float_win = float_win,
            float_buf = float_buf,
            float_config = desired,
            width = target_width,
            height = target_height,
            rows = {},
            highlights = {},
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
        }
        states[source_win] = state
        states_by_float[float_win] = state
        if cursor_position_available then
            resolve_float_position()
        end
    else
        local desired = float_config(
            active_config,
            source_win,
            area_top,
            area_height,
            vim.o.columns,
            target_width,
            target_height,
            cursor_position_available and state.hidden_by_cursor or false
        )
        if not vim.deep_equal(state.float_config, desired) then
            if cursor_position_available then
                desired.hide = true
            end
            vim.api.nvim_win_set_config(state.float_win, desired)
            state.float_config = desired
            state.hidden_by_cursor = desired.hide
            if cursor_position_available then
                resolve_float_position()
            end
        elseif not has_float_config(state.float_win, desired) then
            vim.api.nvim_win_set_config(state.float_win, desired)
            state.float_config = desired
            state.hidden_by_cursor = desired.hide
        end
        state.source_buf = source_buf
        state.config = active_config
        state.variant_id = selection.variant_id
    end

    update_cursor_visibility(state, cursor_screen_row, cursor_screen_col)
    update_window_presentation(state, active_winblend, active_winhighlight)

    with_modifiable(state.float_buf, function()
        vim.api.nvim_buf_set_lines(state.float_buf, 0, -1, false, rows)
    end)
    write_highlights(state.float_buf, rows, highlights, active_config)

    state.width = target_width
    state.height = target_height
    state.rows = rows
    state.highlights = highlights
    state.viewport_top = viewport_top
    state.viewport_bottom = viewport_bottom
    state.cursor_row = cursor_row
    state.cursor_col = cursor_col
    state.overlay_signature = overlay_sig
    state.cells_signature = cache.signature
    state.rendered_signature = cache.signature
    prune_cell_cache(source_buf)

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
    if root_config.autohide.enabled then
        revealed[source_win] = vim.api.nvim_win_get_buf(source_win)
    end
    return true
end

---@param source_win integer
---@return boolean
M.conceal = function(source_win)
    if not config_module.get().autohide.enabled then
        return false
    end
    local was_revealed = revealed[source_win] ~= nil or states[source_win] ~= nil
    conceal_source(source_win)
    return was_revealed
end

---Worker result callback. Updates the dimension-specific cell cache and bumps
---the revision so the next render picks up fresh content. The lifecycle
---owner (T10 init.lua) wires the worker's `on_result` to this handler
---plus a scheduler invalidation.
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
    if existing == nil or changedtick >= existing.changedtick then
        buffer_cache[signature] = {
            signature = signature,
            cells = payload.cells or {},
            revision = (existing and existing.revision or 0) + 1,
            changedtick = changedtick,
            semantic_revision = accepted_semantic_revision,
            filetype = filetype,
            source_line_count = line_count_of(bufnr),
            max_line_width = payload.max_line_width or (existing and existing.max_line_width or 0),
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
end

---@param winid integer
---@return boolean
M.is_owned_window = function(winid)
    return owned_window(winid)
end

---@param bufnr integer
---@return boolean
M.is_owned_buffer = function(bufnr)
    return owned_buffer(bufnr)
end

---@param bufnr integer
---@return boolean
M.is_buffer_eligible = function(bufnr)
    return buffer_eligible(bufnr, config_module.get())
end

---@param winid integer
---@return boolean
M.is_source_window = function(winid)
    return source_selection(winid, config_module.get(), active_source_window()) ~= nil
end

---@param bufnr? integer
---@return integer[]
M.source_windows = function(bufnr)
    local root_config = config_module.get()
    local active_source = active_source_window()
    local selected = {}
    local all_sources = {}
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if source_selection(winid, root_config, active_source) ~= nil then
            selected[winid] = true
            table.insert(all_sources, winid)
        end
    end
    table.sort(all_sources)

    local stale = {}
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
    for source_win in pairs(stale) do
        close_source(source_win)
    end

    if bufnr == nil then
        return all_sources
    end

    local filtered = {}
    for _, winid in ipairs(all_sources) do
        if vim.api.nvim_win_get_buf(winid) == bufnr then
            table.insert(filtered, winid)
        end
    end
    return filtered
end

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
            end
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
