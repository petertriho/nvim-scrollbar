--- Shared float code of the scrollbar and minimap renderers. It builds the
--- float configuration of a placement and creates, moves, and closes a float.
--- It also hides a float under the cursor, and its row writer updates only
--- changed rows.
---
--- The row writer keeps an invariant: the extmarks of the namespace on a row
--- are exactly the spans that the last write gave that row.
--- `nvim_buf_set_lines` moves the extmarks of replaced rows to the next row and
--- does not delete them. Thus the row writer clears the extmarks of a row
--- before it replaces the text of that row.

local M = {}

---@alias ScrollbarFloatState ScrollbarWindowState|ScrollbarMinimapRendererState

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

-- Float configurations hold only scalar values, so a flat copy and a flat
-- comparison are exact and cheaper than `vim.deepcopy` and `vim.deep_equal`.

---@param float_config table<string, any>
---@return table<string, any>
local function copy_config(float_config)
    local copy = {}
    for key, value in pairs(float_config) do
        copy[key] = value
    end
    return copy
end

---@param left table<string, any>
---@param right table<string, any>
---@return boolean
local function same_config(left, right)
    for key, value in pairs(left) do
        if right[key] ~= value then
            return false
        end
    end
    for key in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

---@param active_config ScrollbarConfig|ScrollbarMinimapConfig
---@param source_win integer
---@param area_top integer Zero-based screen row of the source text area
---@param area_height integer Rows of the source text area
---@param origin integer Resolved horizontal origin that `placement.col` applies to
---@param zindex integer Resolved z-index
---@param width integer
---@param height integer
---@param hidden boolean
---@return table<string, any>
M.config = function(active_config, source_win, area_top, area_height, origin, zindex, width, height, hidden)
    local placement = active_config.placement
    local north = placement.anchor == "NW" or placement.anchor == "NE"
    local vertical_anchor
    if placement.relative == "window" then
        vertical_anchor = north and 0 or area_height
    else
        vertical_anchor = north and area_top or area_top + area_height
    end

    local result = {
        relative = placement.relative == "window" and "win" or "editor",
        anchor = placement.anchor,
        row = vertical_anchor + placement.row,
        col = origin + placement.col,
        width = width,
        height = height,
        focusable = false,
        mouse = active_config.mouse,
        zindex = zindex,
        hide = hidden,
    }
    if placement.relative == "window" then
        result.win = source_win
    end
    return result
end

---@param float_buf integer
---@param filetype string
---@param owned_var string Buffer variable that marks the buffer as owned
M.configure_buffer = function(float_buf, filetype, owned_var)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = float_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = float_buf })
    vim.api.nvim_set_option_value("undolevels", -1, { buf = float_buf })
    vim.api.nvim_set_option_value("filetype", filetype, { buf = float_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    vim.api.nvim_buf_set_var(float_buf, owned_var, true)
end

---@param float_win integer
---@param owned_var string Window variable that marks the window as owned
---@param winhighlight string
---@param winblend? integer Pseudo-transparency, 0-100; nil keeps the inherited value
M.configure_window = function(float_win, owned_var, winhighlight, winblend)
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
    if winblend ~= nil then
        vim.api.nvim_set_option_value("winblend", winblend, { win = float_win })
    end
    vim.api.nvim_win_set_var(float_win, owned_var, true)
end

---Create a scratch buffer and open a float on it without entering it.
---@param name_format string Buffer name format with the source window and the float buffer
---@param source_win integer
---@param float_config table<string, any>
---@param configure_buffer fun(float_buf: integer)
---@param configure_window fun(float_win: integer)
---@return integer float_win
---@return integer float_buf
M.open = function(name_format, source_win, float_config, configure_buffer, configure_window)
    local float_buf = vim.api.nvim_create_buf(false, true)
    configure_buffer(float_buf)
    pcall(vim.api.nvim_buf_set_name, float_buf, string.format(name_format, source_win, float_buf))

    -- Applying the minimal style again changes winhighlight on Neovim 0.11.4.
    float_config.style = "minimal"
    local ok, float_win = pcall(vim.api.nvim_open_win, float_buf, false, float_config)
    float_config.style = nil
    if not ok then
        pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
        error(float_win, 0)
    end
    configure_window(float_win)
    return float_win, float_buf
end

---@param float_win integer
---@param float_buf integer
M.close = function(float_win, float_buf)
    if valid_window(float_win) then
        pcall(vim.api.nvim_win_close, float_win, true)
    end
    if vim.api.nvim_buf_is_valid(float_buf) then
        pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
    end
end

---Whether the float still has every value of `expected`. A steady render
---checks the window too, so the render corrects a float that something else
---reconfigured.
---@param float_win integer
---@param expected table<string, any>
---@return boolean
M.has_config = function(float_win, expected)
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
---@param active_config ScrollbarConfig|ScrollbarMinimapConfig
---@return integer? row Zero-based screen row of the cursor
---@return integer? col Zero-based screen column of the cursor
M.cursor_screen_position = function(source_win, active_config)
    if not active_config.hide_on_cursor or vim.api.nvim_get_current_win() ~= source_win then
        return nil, nil
    end

    local cursor_row = vim.fn.screenrow()
    local cursor_col = vim.fn.screencol()
    if type(cursor_row) ~= "number" or type(cursor_col) ~= "number" or cursor_row <= 0 or cursor_col <= 0 then
        return nil, nil
    end

    return cursor_row - 1, cursor_col - 1
end

---@param state ScrollbarFloatState
---@param cursor_row? integer
---@param cursor_col? integer
---@return boolean
local function cursor_overlaps(state, cursor_row, cursor_col)
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

---@param state ScrollbarFloatState
---@param cursor_row? integer
---@param cursor_col? integer
M.update_cursor_visibility = function(state, cursor_row, cursor_col)
    local hidden = cursor_overlaps(state, cursor_row, cursor_col)
    if state.hidden_by_cursor == hidden then
        return
    end

    local active_float_config = copy_config(state.float_config)
    active_float_config.hide = hidden
    vim.api.nvim_win_set_config(state.float_win, active_float_config)
    state.float_config = active_float_config
    state.hidden_by_cursor = hidden
end

M.resolve_position = function()
    -- Anchored positions settle during redraw. A flush while the float is hidden makes the first visible
    -- frame correct.
    vim.api.nvim__redraw({ flush = true })
end

---@param state ScrollbarFloatState
---@param desired table<string, any>
local function set_config(state, desired)
    vim.api.nvim_win_set_config(state.float_win, desired)
    state.float_config = desired
    state.hidden_by_cursor = desired.hide
end

---Apply the float configuration of a render. While the cursor can overlap the
---float, a float that moves stays hidden until its position settles. Then the
---caller updates the cursor visibility.
---@param state ScrollbarFloatState
---@param desired table<string, any>
---@param cursor_position_available boolean
M.apply_config = function(state, desired, cursor_position_available)
    if not same_config(state.float_config, desired) then
        if cursor_position_available then
            desired.hide = true
        end
        set_config(state, desired)
        if cursor_position_available then
            M.resolve_position()
        end
    elseif not M.has_config(state.float_win, desired) then
        set_config(state, desired)
    end
end

---Move a float to a new stacked origin and z-index without rendering its
---content again.
---@param state ScrollbarFloatState
---@param footprint ScrollbarStackFootprint Own footprint of the float
---@param origin? integer Stacked origin, or nil for the own origin of the footprint
---@param zindex integer
---@return boolean changed
M.reposition = function(state, footprint, origin, zindex)
    local col = (origin or footprint.origin) + footprint.col
    if state.float_config.col == col and state.float_config.zindex == zindex then
        return false
    end
    local desired = copy_config(state.float_config)
    desired.col = col
    desired.zindex = zindex

    local cursor_row, cursor_col = M.cursor_screen_position(state.source_win, state.config)
    local cursor_position_available = cursor_row ~= nil and cursor_col ~= nil
    if cursor_position_available then
        desired.hide = true
    end
    set_config(state, desired)
    if cursor_position_available then
        M.resolve_position()
    end
    M.update_cursor_visibility(state, cursor_row, cursor_col)
    return true
end

---Run `callback(...)` while the buffer is modifiable. Every toggle fires
---`OptionSet`, so a render toggles at most once.
---@param float_buf integer
---@param callback fun(...)
local function with_modifiable(float_buf, callback, ...)
    vim.api.nvim_set_option_value("modifiable", true, { buf = float_buf })
    local ok, error_message = pcall(callback, ...)
    if vim.api.nvim_buf_is_valid(float_buf) then
        vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    end
    if not ok then
        error(error_message, 0)
    end
end

---@param float_buf integer
---@param rows string[]
---@param changed integer[] Ascending one-based rows whose text changed
local function set_changed_lines(float_buf, rows, changed)
    local index = 1
    local count = #changed
    while index <= count do
        local first = changed[index]
        local last = first
        while index < count and changed[index + 1] == last + 1 do
            index = index + 1
            last = changed[index]
        end
        local replacement = {}
        for row = first, last do
            replacement[#replacement + 1] = rows[row]
        end
        vim.api.nvim_buf_set_lines(float_buf, first - 1, last, false, replacement)
        index = index + 1
    end
end

---@param left? ScrollbarHighlightSpan[]
---@param right? ScrollbarHighlightSpan[]
---@return boolean
local function same_spans(left, right)
    if left == right then
        return true
    end
    local left_count = left and #left or 0
    if left_count ~= (right and #right or 0) then
        return false
    end
    for index = 1, left_count do
        ---@cast left -nil
        ---@cast right -nil
        local left_span = left[index]
        local right_span = right[index]
        if
            left_span.start_col ~= right_span.start_col
            or left_span.end_col ~= right_span.end_col
            or left_span.highlight ~= right_span.highlight
            or left_span.priority ~= right_span.priority
        then
            return false
        end
    end
    return true
end

---@param float_buf integer
---@param namespace integer
---@param row integer Zero-based row
---@param spans? ScrollbarHighlightSpan[]
local function write_spans(float_buf, namespace, row, spans)
    if spans == nil then
        return
    end
    for index = 1, #spans do
        local span = spans[index]
        vim.api.nvim_buf_set_extmark(float_buf, namespace, row, span.start_col, {
            end_row = row,
            end_col = span.end_col,
            hl_group = span.highlight,
            hl_mode = "combine",
            priority = span.priority,
            strict = false,
        })
    end
end

---Write rows of text and their byte-column highlight spans into a float
---buffer. The writer replaces only the rows whose text changed, and only the
---rows whose text or spans changed get new extmarks.
---@param float_buf integer
---@param namespace integer
---@param previous_rows string[] Rows of the last write
---@param previous_spans ScrollbarHighlightSpan[][] Spans of the last write
---@param rows string[]
---@param spans ScrollbarHighlightSpan[][]
---@param full boolean Replace the whole buffer, for a new buffer or a new size
M.write_rows = function(float_buf, namespace, previous_rows, previous_spans, rows, spans, full)
    local count = #rows
    if full then
        vim.api.nvim_buf_clear_namespace(float_buf, namespace, 0, -1)
        with_modifiable(float_buf, vim.api.nvim_buf_set_lines, float_buf, 0, -1, false, rows)
        for row = 1, count do
            write_spans(float_buf, namespace, row - 1, spans[row])
        end
        return
    end

    local changed_text
    local rewritten
    local clear_first
    for row = 1, count do
        local text_changed = previous_rows[row] ~= rows[row]
        if text_changed then
            changed_text = changed_text or {}
            changed_text[#changed_text + 1] = row
        end
        if text_changed or not same_spans(previous_spans[row], spans[row]) then
            rewritten = rewritten or {}
            rewritten[#rewritten + 1] = row
            clear_first = clear_first or row
        elseif clear_first ~= nil then
            vim.api.nvim_buf_clear_namespace(float_buf, namespace, clear_first - 1, row - 1)
            clear_first = nil
        end
    end
    if clear_first ~= nil then
        vim.api.nvim_buf_clear_namespace(float_buf, namespace, clear_first - 1, count)
    end
    if changed_text ~= nil then
        with_modifiable(float_buf, set_changed_lines, float_buf, rows, changed_text)
    end
    if rewritten ~= nil then
        for index = 1, #rewritten do
            local row = rewritten[index]
            write_spans(float_buf, namespace, row - 1, spans[row])
        end
    end
end

return M
