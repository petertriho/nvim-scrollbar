--- Shared float code of the scrollbar and minimap renderers. It builds the
--- float configuration of a placement and creates, moves, and closes a float.
--- It also hides a float under the cursor, and its row writer updates only
--- changed rows.
---
--- The row writer does not put the rows into the buffer text. 'hlsearch' is
--- global, and Neovim applies the search highlight to the buffer text of every
--- window, floats included (issue #122). Thus the float buffer holds only
--- empty lines, one for each row, and each row is an overlay virtual text
--- extmark on its line. Overlay virtual text with `hl_mode = "replace"` never
--- gets the search highlight. A zero-width match, such as `/^`, colors the
--- first cell of an empty line, so the virtual text of an empty row is one
--- space. `hl_mode = "combine"` would let that cell through.
---
--- The row writer keeps an invariant: the extmark with id `row` of the
--- namespace is on line `row - 1`, and its chunks are the text and the spans
--- that the last write gave that row. The lines change only on a full write,
--- which clears the namespace first, so the extmarks never move.

local M = {}

-- The target of the search groups in a float. The plugin does not define this
-- group, so it is empty. A mark type cannot contain a dot, so no generated
-- group has this name. `None` is a global group that a user can define. An
-- empty target gives a cell another attribute id when a search matches, also
-- when the colors do not change.
local NO_SEARCH_GROUP = "Scrollbar.NoSearch"

-- `winhighlight` entries that map the search groups of a float to an empty
-- group. The overlay rows hide the search matches, so the mapping is a
-- backstop for any cell that an overlay does not cover. `CurSearch` applies
-- at the cursor of the float also when the float is not the current window.
-- `IncSearch` applies when a search starts while the float is the current
-- window.
M.SEARCH_WINHIGHLIGHT = "Search:"
    .. NO_SEARCH_GROUP
    .. ",CurSearch:"
    .. NO_SEARCH_GROUP
    .. ",IncSearch:"
    .. NO_SEARCH_GROUP

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
---@param wo? table<string, any> Window options of the `window` configuration. They apply last, so they win
M.configure_window = function(float_win, owned_var, winhighlight, winblend, wo)
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
    -- A click puts the cursor of the float on the clicked cell. With
    -- 'virtualedit', the cursor can be past the end of the empty line, and a
    -- global 'sidescrolloff' then scrolls the float sideways. The overlays
    -- start at column 0, so they move out of view.
    vim.api.nvim_set_option_value("sidescrolloff", 0, { win = float_win })
    vim.api.nvim_set_option_value("winhighlight", winhighlight, { win = float_win })
    if winblend ~= nil then
        vim.api.nvim_set_option_value("winblend", winblend, { win = float_win })
    end
    if wo ~= nil then
        for name, value in pairs(wo) do
            vim.api.nvim_set_option_value(name, value, { win = float_win })
        end
    end
    vim.api.nvim_win_set_var(float_win, owned_var, true)
end

---Create a scratch buffer and open a float on it without entering it.
---@param name_format string Buffer name format with the source window and the float buffer
---@param source_win integer
---@param float_config table<string, any>
---@param open_keys table<string, any> `nvim_open_win` keys of the `window` configuration, such as `border`
---@param configure_buffer fun(float_buf: integer)
---@param configure_window fun(float_win: integer)
---@return integer float_win
---@return integer float_buf
M.open = function(name_format, source_win, float_config, open_keys, configure_buffer, configure_window)
    local float_buf = vim.api.nvim_create_buf(false, true)
    configure_buffer(float_buf)
    pcall(vim.api.nvim_buf_set_name, float_buf, string.format(name_format, source_win, float_buf))

    -- Only the open gets the style and the `window` keys. Applying the minimal
    -- style again changes winhighlight on Neovim 0.11.4. A float with other
    -- `window` keys opens again, because `nvim_win_set_config` keeps the keys
    -- that it does not get.
    local open_config = copy_config(float_config)
    for key, value in pairs(open_keys) do
        open_config[key] = value
    end
    open_config.style = "minimal"
    local ok, float_win = pcall(vim.api.nvim_open_win, float_buf, false, open_config)
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

    cursor_row, cursor_col = cursor_row - 1, cursor_col - 1
    -- In a floating window, `screenrow()` and `screencol()` count from the
    -- corner of the grid of the float, and the grid includes the border.
    if vim.fn.win_gettype(source_win) == "popup" then
        local position = vim.api.nvim_win_get_position(source_win)
        cursor_row = cursor_row + position[1]
        cursor_col = cursor_col + position[2]
    end
    return cursor_row, cursor_col
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
    -- The position is the corner of the frame, so the border counts too.
    local sides = state.sides
    height = height + sides.top + sides.bottom
    width = width + sides.left + sides.right

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
---@param force? boolean Apply `desired` also when it equals the last configuration
M.apply_config = function(state, desired, cursor_position_available, force)
    if force or not same_config(state.float_config, desired) then
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

---Keep the screen position of a floating source window in `state`, and tell
---whether the window moved since the last call. A float that is relative to a
---floating window does not follow that window when it moves. It moves only on
---its next `nvim_win_set_config`, and its relative configuration stays the
---same. So a render applies the configuration again after a move.
---@param state ScrollbarFloatState
---@param source_win integer
---@param floating boolean Whether the source window is a float
---@return boolean moved
M.track_source = function(state, source_win, floating)
    if not floating then
        state.source_position = nil
        return false
    end
    local position = vim.api.nvim_win_get_position(source_win)
    local previous = state.source_position
    state.source_position = position
    return previous ~= nil and (previous[1] ~= position[1] or previous[2] ~= position[2])
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

---@param text string
---@param col integer Byte column
---@return integer col The column clamped to the row, moved forward to the start of a character
local function char_start(text, col)
    if col <= 0 then
        return 0
    end
    local length = #text
    if col >= length then
        return length
    end
    local byte = string.byte(text, col + 1)
    while byte ~= nil and byte >= 0x80 and byte < 0xC0 do
        col = col + 1
        byte = string.byte(text, col + 1)
    end
    return col
end

---@param left? string|string[]
---@param right? string|string[]
---@return boolean
local function same_groups(left, right)
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then
        return false
    end
    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end
    return true
end

---@alias ScrollbarOverlayChunk { [1]: string, [2]: string|string[]|nil } Text and the groups that combine in order

-- Scratch tables of `row_chunks`. Entries past the current row are stale.
---@type integer[]
local span_starts = {}
---@type integer[]
local span_ends = {}
---@type integer[]
local cuts = {}
---@type integer[]
local covering = {}

---Convert a row and its byte-column spans into overlay virtual text chunks.
---The row is cut at every span boundary. The chunk of each piece combines
---the groups of the spans that cover it, in the order in which Neovim
---combines overlapping extmark highlights: ascending priority, then the later
---start, then the later span. Adjacent pieces with the same groups merge. An
---empty row is one space without a group.
---@param text string
---@param spans? ScrollbarHighlightSpan[]
---@return ScrollbarOverlayChunk[] chunks
local function row_chunks(text, spans)
    local length = #text
    if length == 0 then
        return { { " " } }
    end
    local span_count = spans and #spans or 0
    if span_count == 0 then
        return { { text } }
    end
    ---@cast spans -nil

    cuts[1] = 0
    cuts[2] = length
    local cut_count = 2
    for index = 1, span_count do
        local span = spans[index]
        local first = char_start(text, span.start_col)
        local last = char_start(text, span.end_col)
        span_starts[index] = first
        span_ends[index] = last
        if first < last then
            cuts[cut_count + 1] = first
            cuts[cut_count + 2] = last
            cut_count = cut_count + 2
        end
    end
    -- Insertion sort without duplicates; a row has few cuts.
    local unique = 0
    for index = 1, cut_count do
        local cut = cuts[index]
        local position = unique
        while position > 0 and cuts[position] > cut do
            position = position - 1
        end
        if position == 0 or cuts[position] ~= cut then
            for move = unique, position + 1, -1 do
                cuts[move + 1] = cuts[move]
            end
            cuts[position + 1] = cut
            unique = unique + 1
        end
    end

    local chunks = {}
    local chunk_first = 0
    local chunk_groups
    for index = 1, unique - 1 do
        local first = cuts[index]
        local count = 0
        for span_index = 1, span_count do
            if span_starts[span_index] <= first and span_ends[span_index] > first then
                local span = spans[span_index]
                local position = count + 1
                while position > 1 do
                    local other_index = covering[position - 1]
                    local other = spans[other_index]
                    if
                        other.priority < span.priority
                        or (other.priority == span.priority and span_starts[other_index] <= span_starts[span_index])
                    then
                        break
                    end
                    covering[position] = other_index
                    position = position - 1
                end
                covering[position] = span_index
                count = count + 1
            end
        end

        local groups
        if count == 1 then
            groups = spans[covering[1]].highlight
        elseif count > 1 then
            groups = {}
            for position = 1, count do
                groups[position] = spans[covering[position]].highlight
            end
        end
        if index == 1 then
            chunk_groups = groups
        elseif not same_groups(chunk_groups, groups) then
            chunks[#chunks + 1] = { text:sub(chunk_first + 1, first), chunk_groups }
            chunk_first = first
            chunk_groups = groups
        end
    end
    chunks[#chunks + 1] = { text:sub(chunk_first + 1, length), chunk_groups }
    return chunks
end

M._row_chunks = row_chunks

---@param float_buf integer
---@param namespace integer
---@param row integer One-based row, which is also the extmark id
---@param text string
---@param spans? ScrollbarHighlightSpan[]
local function write_row(float_buf, namespace, row, text, spans)
    vim.api.nvim_buf_set_extmark(float_buf, namespace, row - 1, 0, {
        id = row,
        virt_text = row_chunks(text, spans),
        virt_text_pos = "overlay",
        hl_mode = "replace",
    })
end

---@type table<integer, string[]>
local empty_lines = {}

---@param count integer
---@return string[]
local function empty_lines_of(count)
    local lines = empty_lines[count]
    if lines == nil then
        lines = {}
        for row = 1, count do
            lines[row] = ""
        end
        empty_lines[count] = lines
    end
    return lines
end

---Write rows of text and their byte-column highlight spans into a float
---buffer as overlay virtual text. Only the rows whose text or spans changed
---get a new extmark. Only a full write changes the buffer lines.
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
        -- Only this writer changes the lines, and they are always empty, so
        -- the line count tells whether the lines need a change.
        if vim.api.nvim_buf_line_count(float_buf) ~= math.max(count, 1) then
            with_modifiable(float_buf, vim.api.nvim_buf_set_lines, float_buf, 0, -1, false, empty_lines_of(count))
        end
        for row = 1, count do
            write_row(float_buf, namespace, row, rows[row], spans[row])
        end
        return
    end

    for row = 1, count do
        local text = rows[row]
        if previous_rows[row] ~= text or not same_spans(previous_spans[row], spans[row]) then
            write_row(float_buf, namespace, row, text, spans[row])
        end
    end
end

return M
