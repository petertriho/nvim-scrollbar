local config = require("scrollbar.config")
local layout = require("scrollbar.layout")
local providers = require("scrollbar.providers")
local store = require("scrollbar.store")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarRenderer")
local AUGROUP_NAME = "ScrollbarRendererLifecycle"
local FLOAT_WINHIGHLIGHT = "Normal:ScrollbarBase,NormalNC:ScrollbarBase,EndOfBuffer:ScrollbarBase"
local STATUSCOLUMN_WRAPPER_PATTERN = '^%%!v:lua%.require%("scrollbar%.renderer"%)%._statuscolumn%((%d+)%)$'

---@class ScrollbarStatuscolumnReservation
---@field original_statuscolumn string
---@field original_numberwidth integer
---@field applied_statuscolumn string
---@field applied_numberwidth integer
---@field span integer
---@field base_textoff integer
---@field position ScrollbarGutterPosition
---@field limited boolean
---@field failed boolean

---@type table<integer, ScrollbarWindowState>
local states = {}

---@type table<integer, ScrollbarWindowState>
local states_by_float = {}

---@type table<integer, ScrollbarStatuscolumnReservation>
local statuscolumn_reservations = {}

---@type table<integer, ScrollbarFlattenedMarksCache>
local flattened_cache = {}

---@type table<integer, ScrollbarLineMarkLayerCache>
local line_layer_cache = {}

---@type table<integer, integer>
local revealed = {}

---@type integer?
local lifecycle_group
local visible = false

---@type fun(state: ScrollbarWindowState)?
local state_callback

---@param source_win integer
local function clear_source_cache(source_win)
    flattened_cache[source_win] = nil
    line_layer_cache[source_win] = nil
    layout.clear_screen_cache(source_win)
end

local function clear_all_caches()
    flattened_cache = {}
    line_layer_cache = {}
    layout.clear_cache()
    layout.clear_all_screen_caches()
end

---@param source_buf integer
local function clear_buffer_caches(source_buf)
    local pending = {}
    for source_win, cached in pairs(flattened_cache) do
        if cached.source_buf == source_buf then
            table.insert(pending, source_win)
        end
    end
    for _, source_win in ipairs(pending) do
        clear_source_cache(source_win)
    end
end

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

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
---@param name string
---@param value string|integer
---@return boolean
local function set_local_option(winid, name, value)
    local ok = pcall(vim.api.nvim_win_call, winid, function()
        vim.cmd(string.format("noautocmd let &l:%s = %s", name, vim.fn.string(value)))
    end)
    return ok
end

---@param winid integer
---@return string
local function default_statuscolumn(winid)
    local number = vim.api.nvim_get_option_value("number", { win = winid })
    local relativenumber = vim.api.nvim_get_option_value("relativenumber", { win = winid })
    local value = "%C%s"
    if number or relativenumber then
        return value .. "%=%l "
    end
    return value
end

---@param value string
---@return integer?
local function statuscolumn_owner(value)
    return tonumber(value:match(STATUSCOLUMN_WRAPPER_PATTERN))
end

---@param source_win integer
---@return string
local function statuscolumn_wrapper(source_win)
    return string.format('%%!v:lua.require("scrollbar.renderer")._statuscolumn(%d)', source_win)
end

---@param winid integer
---@param parent_win? integer
local function restore_inherited_statuscolumn(winid, parent_win)
    if not valid_window(winid) then
        return
    end
    local current = vim.api.nvim_get_option_value("statuscolumn", { win = winid })
    local owner = statuscolumn_owner(current)
    if owner == winid then
        return
    end
    if owner ~= nil then
        local inherited = statuscolumn_reservations[owner]
        if inherited == nil then
            set_local_option(winid, "statuscolumn", "")
            return
        end
        local numberwidth = vim.api.nvim_get_option_value("numberwidth", { win = winid })
        set_local_option(winid, "statuscolumn", inherited.original_statuscolumn)
        if numberwidth == inherited.applied_numberwidth then
            set_local_option(winid, "numberwidth", inherited.original_numberwidth)
        end
        return
    end

    local parent = parent_win and statuscolumn_reservations[parent_win] or nil
    if parent_win ~= nil and parent ~= nil and valid_window(parent_win) then
        local parent_statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { win = parent_win })
        local numberwidth = vim.api.nvim_get_option_value("numberwidth", { win = winid })
        if current == parent_statuscolumn and numberwidth == parent.applied_numberwidth then
            set_local_option(winid, "numberwidth", parent.original_numberwidth)
        end
    end
end

---@param source_win integer
local function release_statuscolumn(source_win)
    local reservation = statuscolumn_reservations[source_win]
    statuscolumn_reservations[source_win] = nil
    if reservation == nil or not valid_window(source_win) then
        return
    end

    local current_statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { win = source_win })
    local current_numberwidth = vim.api.nvim_get_option_value("numberwidth", { win = source_win })
    if current_statuscolumn == reservation.applied_statuscolumn then
        set_local_option(source_win, "statuscolumn", reservation.failed and "" or reservation.original_statuscolumn)
    end
    if current_numberwidth == reservation.applied_numberwidth then
        set_local_option(source_win, "numberwidth", reservation.original_numberwidth)
    end
end

---@param source_win integer
---@param span integer
---@param position ScrollbarGutterPosition
---@return ScrollbarStatuscolumnReservation?
local function ensure_statuscolumn(source_win, span, position)
    restore_inherited_statuscolumn(source_win)
    if span <= 0 then
        release_statuscolumn(source_win)
        return nil
    end

    ---@type ScrollbarStatuscolumnReservation?
    local reservation = statuscolumn_reservations[source_win]
    if reservation ~= nil then
        local current_statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { win = source_win })
        local current_numberwidth = vim.api.nvim_get_option_value("numberwidth", { win = source_win })
        if
            current_statuscolumn ~= reservation.applied_statuscolumn
            or current_numberwidth ~= reservation.applied_numberwidth
            or reservation.position ~= position
        then
            release_statuscolumn(source_win)
            reservation = nil
        elseif reservation.span == span then
            if reservation.failed then
                set_local_option(source_win, "statuscolumn", "")
                release_statuscolumn(source_win)
                return nil
            end
            reservation.base_textoff = math.max(0, vim.fn.getwininfo(source_win)[1].textoff - span)
            return reservation
        end
    end

    if reservation == nil then
        local original_statuscolumn = vim.api.nvim_get_option_value("statuscolumn", { win = source_win })
        local inherited_owner = statuscolumn_owner(original_statuscolumn)
        if inherited_owner ~= nil then
            local inherited = statuscolumn_reservations[inherited_owner]
            original_statuscolumn = inherited and inherited.original_statuscolumn or ""
            set_local_option(source_win, "statuscolumn", original_statuscolumn)
        end
        local original_numberwidth = vim.api.nvim_get_option_value("numberwidth", { win = source_win })
        reservation = {
            original_statuscolumn = original_statuscolumn,
            original_numberwidth = original_numberwidth,
            applied_statuscolumn = statuscolumn_wrapper(source_win),
            applied_numberwidth = original_numberwidth + span,
            span = span,
            base_textoff = vim.fn.getwininfo(source_win)[1].textoff,
            position = position,
            limited = false,
            failed = false,
        }
        statuscolumn_reservations[source_win] = reservation
    else
        reservation.base_textoff = math.max(0, vim.fn.getwininfo(source_win)[1].textoff - reservation.span)
        reservation.span = span
        reservation.limited = false
    end

    reservation.applied_numberwidth = math.min(20, reservation.original_numberwidth + span)
    set_local_option(source_win, "numberwidth", reservation.applied_numberwidth)
    set_local_option(source_win, "statuscolumn", reservation.applied_statuscolumn)
    vim.api.nvim__redraw({ flush = true })
    if reservation.failed then
        set_local_option(source_win, "statuscolumn", "")
        release_statuscolumn(source_win)
        return nil
    end
    if vim.api.nvim_get_option_value("statuscolumn", { win = source_win }) ~= reservation.applied_statuscolumn then
        release_statuscolumn(source_win)
        return nil
    end
    local textoff = vim.fn.getwininfo(source_win)[1].textoff
    local actual_span = math.max(0, textoff - reservation.base_textoff)
    if actual_span < span then
        reservation.span = actual_span
        reservation.limited = true
        set_local_option(source_win, "statuscolumn", reservation.applied_statuscolumn)
        vim.api.nvim__redraw({ flush = true })
        if reservation.failed then
            set_local_option(source_win, "statuscolumn", "")
            release_statuscolumn(source_win)
            return nil
        end
        if vim.api.nvim_get_option_value("statuscolumn", { win = source_win }) ~= reservation.applied_statuscolumn then
            release_statuscolumn(source_win)
            return nil
        end
        textoff = vim.fn.getwininfo(source_win)[1].textoff
    end
    reservation.base_textoff = math.max(0, textoff - reservation.span)
    return reservation
end

---@param active_config ScrollbarConfig
---@return boolean
local function reserves_statuscolumn(active_config)
    local placement = active_config.float.placement
    return placement.relative == "window"
        and (placement.anchor == "NW" or placement.anchor == "SW")
        and placement.gutter == "avoid"
end

---@param source_win integer
---@return integer
local function reservation_base_textoff(source_win)
    local reservation = statuscolumn_reservations[source_win]
    if reservation == nil then
        return vim.fn.getwininfo(source_win)[1].textoff
    end
    local textoff = vim.fn.getwininfo(source_win)[1].textoff
    reservation.base_textoff = math.max(0, textoff - reservation.span)
    return reservation.base_textoff
end

---@param owner_win integer
---@return string
M._statuscolumn = function(owner_win)
    local drawn_win = tonumber(vim.g.statusline_winid) or owner_win
    if not valid_window(drawn_win) then
        return ""
    end
    local reservation = statuscolumn_reservations[owner_win]
    if reservation == nil then
        return default_statuscolumn(drawn_win)
    end

    local value = reservation.original_statuscolumn
    if value == "" then
        value = default_statuscolumn(drawn_win)
    elseif value:sub(1, 2) == "%!" then
        if reservation.failed then
            return string.rep(" ", reservation.base_textoff + reservation.span)
        end
        local ok, evaluated = pcall(vim.api.nvim_eval, value:sub(3))
        if not ok then
            reservation.failed = true
            return string.rep(" ", reservation.base_textoff + reservation.span)
        end
        value = type(evaluated) == "string" and evaluated or vim.fn.string(evaluated)
    end
    if drawn_win == owner_win then
        local gap = string.rep(" ", reservation.span)
        value = reservation.position == "outer" and gap .. value or value .. gap
    end
    return value
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

    local ok, owned = pcall(vim.api.nvim_win_get_var, winid, "scrollbar_owned")
    return ok and owned == true
end

---@param bufnr integer
---@return boolean
local function owned_buffer(bufnr)
    if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    local ok, owned = pcall(vim.api.nvim_buf_get_var, bufnr, "scrollbar_owned")
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
---@param root_config ScrollbarConfig
---@return boolean
local function buffer_eligible(bufnr, root_config)
    if
        type(bufnr) ~= "number"
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
---@param root_config ScrollbarConfig
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
---@param root_config ScrollbarConfig
---@param active_source? integer
---@return ScrollbarConfigSelection?
local function source_selection(source_win, root_config, active_source)
    if not basic_eligible(source_win, root_config) then
        return nil
    end
    if root_config.visibility == "active" and source_win ~= active_source then
        return nil
    end

    local selection = config.select(source_win)
    if selection.config.float.placement.relative == "editor" and source_win ~= active_source then
        return nil
    end
    return selection
end

---@param state ScrollbarWindowState
---@param retain_cache? boolean
local function forget_state(state, retain_cache)
    states[state.source_win] = nil
    states_by_float[state.float_win] = nil
    if not retain_cache then
        revealed[state.source_win] = nil
        clear_source_cache(state.source_win)
    end
end

---@param state ScrollbarWindowState
---@param retain_cache? boolean
local function close_state(state, retain_cache)
    forget_state(state, retain_cache)
    if valid_window(state.float_win) then
        pcall(vim.api.nvim_win_close, state.float_win, true)
    end
    if vim.api.nvim_buf_is_valid(state.float_buf) then
        pcall(vim.api.nvim_buf_delete, state.float_buf, { force = true })
    end
    release_statuscolumn(state.source_win)
end

---@param source_win integer
local function close_source(source_win)
    local state = states[source_win]
    if state ~= nil then
        close_state(state)
    else
        revealed[source_win] = nil
        clear_source_cache(source_win)
        release_statuscolumn(source_win)
    end
end

---@param source_win integer
local function conceal_source(source_win)
    revealed[source_win] = nil
    local state = states[source_win]
    if state ~= nil then
        close_state(state, true)
    else
        release_statuscolumn(source_win)
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
    local reserved = {}
    for source_win in pairs(statuscolumn_reservations) do
        reserved[#reserved + 1] = source_win
    end
    for _, source_win in ipairs(reserved) do
        release_statuscolumn(source_win)
    end
end

---@param source_win integer
local function close_other_states(source_win)
    local pending = {}
    for winid, state in pairs(states) do
        if winid ~= source_win then
            table.insert(pending, state)
        end
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

---@param source_win integer
---@return table<string, integer>
local function source_text_area(source_win)
    local winbar = vim.api.nvim_get_option_value("winbar", { win = source_win })
    local winbar_rows = winbar == "" and 0 or 1
    local screen_position = vim.fn.win_screenpos(source_win)
    local info = vim.fn.getwininfo(source_win)[1]
    return {
        width = vim.api.nvim_win_get_width(source_win),
        height = math.max(0, vim.api.nvim_win_get_height(source_win) - winbar_rows),
        top = screen_position[1] - 1 + winbar_rows,
        textoff = info.textoff,
    }
end

---@param source_win integer
---@param active_config ScrollbarConfig
---@param area table<string, integer>
---@param container_width integer
---@param width integer
---@param hidden boolean
---@return table<string, any>
local function float_config(active_config, source_win, area, container_width, width, hidden)
    local placement = active_config.float.placement
    local north = placement.anchor == "NW" or placement.anchor == "NE"
    local west = placement.anchor == "NW" or placement.anchor == "SW"
    local west_origin = 0
    if reserves_statuscolumn(active_config) and placement.gutter_position == "inner" then
        west_origin = reservation_base_textoff(source_win)
    end
    local vertical_anchor
    if placement.relative == "window" then
        vertical_anchor = north and 0 or area.height
    else
        vertical_anchor = north and area.top or area.top + area.height
    end

    local result = {
        relative = placement.relative == "window" and "win" or "editor",
        anchor = placement.anchor,
        row = vertical_anchor + placement.row,
        col = (west and west_origin or container_width) + placement.col,
        width = width,
        height = area.height,
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

---@param float_buf integer
local function configure_buffer(float_buf)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = float_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = float_buf })
    vim.api.nvim_set_option_value("undolevels", -1, { buf = float_buf })
    vim.api.nvim_set_option_value("filetype", "scrollbar", { buf = float_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    vim.api.nvim_buf_set_var(float_buf, "scrollbar_owned", true)
end

---@param float_win integer
local function configure_window(float_win)
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
    vim.api.nvim_set_option_value("winhighlight", FLOAT_WINHIGHLIGHT, { win = float_win })
    vim.api.nvim_win_set_var(float_win, "scrollbar_owned", true)
end

---@param source_win integer
---@param source_buf integer
---@param active_config ScrollbarConfig
---@param variant_id integer
---@param active_float_config table<string, any>
---@param configure_owned_buffer fun(float_buf: integer)
---@param configure_owned_window fun(float_win: integer)
---@return ScrollbarWindowState
local function create_state(
    source_win,
    source_buf,
    active_config,
    variant_id,
    active_float_config,
    configure_owned_buffer,
    configure_owned_window
)
    local float_buf = vim.api.nvim_create_buf(false, true)
    configure_owned_buffer(float_buf)
    pcall(vim.api.nvim_buf_set_name, float_buf, string.format("scrollbar://source/%d/%d", source_win, float_buf))

    -- Reapplying minimal style mutates winhighlight on Neovim 0.11.4.
    active_float_config.style = "minimal"
    local float_win = vim.api.nvim_open_win(float_buf, false, active_float_config)
    active_float_config.style = nil
    configure_owned_window(float_win)

    local state = {
        source_win = source_win,
        source_buf = source_buf,
        config = active_config,
        variant_id = variant_id,
        float_win = float_win,
        float_buf = float_buf,
        float_config = active_float_config,
        width = 0,
        height = 0,
        rows = {},
        highlights = {},
        rendered_highlights = {},
        hitmap = {},
        handle = false,
        handle_pressed = false,
        hidden_by_cursor = active_float_config.hide == true,
        geometry = { mode = "line", total_extent = 0, viewport_start = 0, viewport_end = 0 },
    }
    states[source_win] = state
    states_by_float[float_win] = state
    return state
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
---@param active_config ScrollbarConfig
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

---@param state ScrollbarWindowState
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

---@param state ScrollbarWindowState
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

---@param source_win integer
---@param source_buf integer
---@return ScrollbarLayoutMark[] marks
---@return integer buffer_revision
---@return integer window_revision
---@return ScrollbarCompactSearch? compact_search
local function flattened_marks(source_win, source_buf)
    local buffer_snapshot = store._get_snapshot(source_buf)
    local window_snapshot = store._get_window_snapshot(source_win)
    local cached = flattened_cache[source_win]
    if
        cached ~= nil
        and cached.source_buf == source_buf
        and cached.buffer_revision == buffer_snapshot.revision
        and cached.window_revision == window_snapshot.revision
    then
        return cached.marks, buffer_snapshot.revision, window_snapshot.revision, cached.compact_search
    end

    local provider_names = {}
    local seen = {}
    for provider in pairs(buffer_snapshot.marks) do
        if providers._consumer_enabled(provider, "scrollbar") then
            seen[provider] = true
        end
    end
    for provider in pairs(window_snapshot.marks) do
        if providers._consumer_enabled(provider, "scrollbar") then
            seen[provider] = true
        end
    end
    for provider in pairs(seen) do
        provider_names[#provider_names + 1] = provider
    end
    table.sort(provider_names)

    local marks = {}
    for _, provider in ipairs(provider_names) do
        for _, snapshot in ipairs({ buffer_snapshot.marks, window_snapshot.marks }) do
            for _, mark in ipairs(snapshot[provider] or {}) do
                table.insert(marks, {
                    provider = provider,
                    line = mark.line,
                    type = mark.type,
                    text = mark.text,
                })
            end
        end
    end
    local compact_search = providers._consumer_enabled("search", "scrollbar") and buffer_snapshot.compact_search or nil
    flattened_cache[source_win] = {
        source_buf = source_buf,
        buffer_revision = buffer_snapshot.revision,
        window_revision = window_snapshot.revision,
        marks = marks,
        compact_search = compact_search,
    }
    return marks, buffer_snapshot.revision, window_snapshot.revision, compact_search
end

---@param source_win integer
---@param source_buf integer
---@param active_config ScrollbarConfig
---@param height integer
---@param marks ScrollbarLayoutMark[]
---@param line_count? integer
---@param mark_rows? integer[]
---@param compact_search? ScrollbarCompactSearch
---@return ScrollbarGeometry
local function geometry_for(active_config, source_win, source_buf, height, marks, line_count, mark_rows, compact_search)
    if active_config.render.geometry == "screen" then
        return layout.screen({
            source_win = source_win,
            height = height,
            marks = marks,
            compact_search = compact_search,
        })
    end

    local viewport = vim.api.nvim_win_call(source_win, function()
        return { vim.fn.line("w0") - 1, vim.fn.line("w$") - 1 }
    end)
    return layout.normalized({
        height = height,
        line_count = line_count or vim.api.nvim_buf_line_count(source_buf),
        top_line = viewport[1],
        bottom_line = viewport[2],
        marks = marks,
        mark_rows = mark_rows,
    })
end

---@param source_win integer
---@param source_buf integer
---@param buffer_revision integer
---@param window_revision integer
---@param line_count integer
---@param container_width integer
---@param height integer
---@param active_config ScrollbarConfig
---@param marks ScrollbarLayoutMark[]
---@param compact_search? ScrollbarCompactSearch
---@return ScrollbarLineMarkLayerCache
local function line_mark_layer(
    source_win,
    source_buf,
    buffer_revision,
    window_revision,
    line_count,
    container_width,
    height,
    active_config,
    marks,
    compact_search
)
    local layout_cache = active_config.layout_cache
    local cached = line_layer_cache[source_win]
    if
        cached ~= nil
        and cached.source_buf == source_buf
        and cached.buffer_revision == buffer_revision
        and cached.window_revision == window_revision
        and cached.line_count == line_count
        and cached.container_width == container_width
        and cached.height == height
        and (cached.config == layout_cache or vim.deep_equal(cached.config, layout_cache))
    then
        cached.config = layout_cache
        return cached
    end

    local mark_rows = layout.normalized_mark_rows({
        height = height,
        line_count = line_count,
        marks = marks,
    })
    cached = {
        source_buf = source_buf,
        buffer_revision = buffer_revision,
        window_revision = window_revision,
        line_count = line_count,
        container_width = container_width,
        height = height,
        config = layout_cache,
        mark_rows = mark_rows,
        layer = layout.mark_layer({
            config = active_config,
            height = height,
            line_count = line_count,
            container_width = container_width,
            geometry = { mark_rows = mark_rows },
            marks = marks,
            compact_search = compact_search,
        }),
    }
    line_layer_cache[source_win] = cached
    return cached
end

---@param float_buf integer
---@param row integer
---@param spans ScrollbarHighlightSpan[]
local function write_highlights(float_buf, row, spans)
    for _, span in ipairs(spans) do
        vim.api.nvim_buf_set_extmark(float_buf, NAMESPACE, row, span.start_col, {
            end_row = row,
            end_col = span.end_col,
            hl_group = span.highlight,
            hl_mode = "combine",
            priority = span.priority,
            strict = false,
        })
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

---@param highlights ScrollbarHighlightSpan[][]
---@param pressed boolean
---@param active_config ScrollbarConfig
---@return ScrollbarHighlightSpan[][]
local function rendered_highlights(highlights, pressed, active_config)
    if not pressed then
        return highlights
    end

    local groups = active_config.highlights
    local replacements = {
        [groups.thumb] = groups.thumb_pressed,
    }
    for _, mark_groups in pairs(groups.marks) do
        replacements[mark_groups.thumb] = mark_groups.thumb_pressed
    end

    local result = {}
    for row, spans in ipairs(highlights) do
        local rendered = {}
        for index, span in ipairs(spans) do
            rendered[index] = {
                start_col = span.start_col,
                end_col = span.end_col,
                highlight = replacements[span.highlight] or span.highlight,
                priority = span.priority,
            }
        end
        result[row] = rendered
    end
    return result
end

---@param state ScrollbarWindowState
---@param highlights ScrollbarHighlightSpan[][]
local function update_highlight_extmarks(state, highlights)
    for row = 1, state.height do
        if not vim.deep_equal(state.rendered_highlights[row], highlights[row]) then
            vim.api.nvim_buf_clear_namespace(state.float_buf, NAMESPACE, row - 1, row)
            write_highlights(state.float_buf, row - 1, highlights[row])
        end
    end
end

---@param state ScrollbarWindowState
---@param output ScrollbarLayoutOutput
---@param width integer
---@param height integer
---@return ScrollbarHighlightSpan[][]
local function update_buffer(state, output, width, height)
    local highlights = rendered_highlights(output.highlights, state.handle_pressed, state.config)
    local dimensions_changed = state.width ~= width or state.height ~= height
    if dimensions_changed then
        with_modifiable(state.float_buf, function()
            vim.api.nvim_buf_set_lines(state.float_buf, 0, -1, false, output.rows)
        end)
        vim.api.nvim_buf_clear_namespace(state.float_buf, NAMESPACE, 0, -1)
        for row, spans in ipairs(highlights) do
            write_highlights(state.float_buf, row - 1, spans)
        end
        return highlights
    end

    for row = 1, height do
        local row_changed = state.rows[row] ~= output.rows[row]
        local highlights_changed = not vim.deep_equal(state.rendered_highlights[row], highlights[row])
        if row_changed then
            with_modifiable(state.float_buf, function()
                vim.api.nvim_buf_set_lines(state.float_buf, row - 1, row, false, { output.rows[row] })
            end)
        end
        if row_changed or highlights_changed then
            vim.api.nvim_buf_clear_namespace(state.float_buf, NAMESPACE, row - 1, row)
            write_highlights(state.float_buf, row - 1, highlights[row])
        end
    end
    return highlights
end

---@param source_win integer
---@param selection ScrollbarConfigSelection
---@param root_config ScrollbarConfig
---@return ScrollbarWindowState?
local function render_source(source_win, selection, root_config)
    local active_config = selection.config
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    ---@type ScrollbarWindowState?
    local existing_state = states[source_win]
    if existing_state ~= nil and existing_state.source_buf ~= source_buf then
        close_state(existing_state)
        existing_state = nil
    end
    if root_config.autohide.enabled and revealed[source_win] ~= source_buf then
        conceal_source(source_win)
        return nil
    end
    local reserved = reserves_statuscolumn(active_config)
    if reserved then
        local initial_width = existing_state and existing_state.width or active_config.layout.width
        local initial_span = math.max(0, initial_width + active_config.float.placement.col)
        if
            initial_span > 0
            and ensure_statuscolumn(source_win, initial_span, active_config.float.placement.gutter_position) == nil
        then
            close_source(source_win)
            return nil
        end
    else
        release_statuscolumn(source_win)
    end

    local marks, buffer_revision, window_revision, compact_search = flattened_marks(source_win, source_buf)
    local line_count = active_config.render.geometry == "line" and vim.api.nvim_buf_line_count(source_buf) or nil
    local area
    local container_width
    local geometry
    local output
    for _ = 1, 3 do
        area = source_text_area(source_win)
        if area.height < 1 then
            close_source(source_win)
            return nil
        end
        if active_config.float.placement.relative == "window" then
            local base_textoff = reserved and reservation_base_textoff(source_win) or 0
            container_width = math.max(0, area.width - base_textoff)
            local reservation = statuscolumn_reservations[source_win]
            if reserved and reservation ~= nil and reservation.limited then
                local maximum_width = math.max(0, reservation.span - active_config.float.placement.col)
                container_width = math.min(container_width, maximum_width)
            end
        else
            container_width = vim.o.columns
        end

        local mark_layer
        if line_count ~= nil then
            local cached = line_mark_layer(
                source_win,
                source_buf,
                buffer_revision,
                window_revision,
                line_count,
                container_width,
                area.height,
                active_config,
                marks,
                compact_search
            )
            geometry = geometry_for(
                active_config,
                source_win,
                source_buf,
                area.height,
                marks,
                line_count,
                cached.mark_rows,
                compact_search
            )
            mark_layer = cached.layer
        else
            geometry = geometry_for(active_config, source_win, source_buf, area.height, marks, nil, nil, compact_search)
        end
        if geometry.total_extent <= area.height and active_config.thumb.hide_if_all_visible then
            geometry.handle = { first_row = -1, last_row = -1 }
        end

        output = layout.compose({
            config = active_config,
            height = area.height,
            line_count = line_count,
            container_width = container_width,
            geometry = geometry,
            marks = marks,
            mark_layer = mark_layer,
            compact_search = compact_search,
        })
        if not reserved then
            break
        end
        local span = math.max(0, output.width + active_config.float.placement.col)
        local current = statuscolumn_reservations[source_win]
        if span == (current and current.span or 0) then
            break
        end
        if span > 0 and ensure_statuscolumn(source_win, span, active_config.float.placement.gutter_position) == nil then
            close_source(source_win)
            return nil
        end
    end

    assert(area ~= nil and geometry ~= nil and output ~= nil, "render geometry unavailable")
    if reserved then
        local reservation = statuscolumn_reservations[source_win]
        local required_span = math.max(0, output.width + active_config.float.placement.col)
        if required_span > 0 and (reservation == nil or reservation.span < required_span) then
            close_source(source_win)
            return nil
        end
    end
    local all_visible = geometry.total_extent <= area.height
    if all_visible and active_config.hide_if_all_visible then
        close_source(source_win)
        return nil
    end
    local cursor_row, cursor_col = cursor_screen_position(source_win, active_config)
    local cursor_position_available = cursor_row ~= nil and cursor_col ~= nil
    ---@type ScrollbarWindowState?
    local state = states[source_win]
    if state == nil or not valid_window(state.float_win) or not vim.api.nvim_buf_is_valid(state.float_buf) then
        if state ~= nil then
            close_state(state)
            if reserved then
                ensure_statuscolumn(
                    source_win,
                    math.max(0, output.width + active_config.float.placement.col),
                    active_config.float.placement.gutter_position
                )
            end
        end
        local active_float_config =
            float_config(active_config, source_win, area, container_width, output.width, cursor_position_available)
        state = create_state(
            source_win,
            source_buf,
            active_config,
            selection.variant_id,
            active_float_config,
            configure_buffer,
            configure_window
        )
        if cursor_position_available then
            resolve_float_position()
        end
    else
        local active_float_config = float_config(
            active_config,
            source_win,
            area,
            container_width,
            output.width,
            cursor_position_available and state.hidden_by_cursor or false
        )
        if not vim.deep_equal(state.float_config, active_float_config) then
            if cursor_position_available then
                active_float_config.hide = true
            end
            vim.api.nvim_win_set_config(state.float_win, active_float_config)
            state.float_config = active_float_config
            state.hidden_by_cursor = active_float_config.hide
            if cursor_position_available then
                resolve_float_position()
            end
        elseif not has_float_config(state.float_win, active_float_config) then
            vim.api.nvim_win_set_config(state.float_win, active_float_config)
            state.float_config = active_float_config
            state.hidden_by_cursor = active_float_config.hide
        end
    end

    update_cursor_visibility(state, cursor_row, cursor_col)

    state.config = active_config
    state.variant_id = selection.variant_id
    local active_highlights = update_buffer(state, output, output.width, area.height)
    state.width = output.width
    state.height = area.height
    state.rows = output.rows
    state.highlights = output.highlights
    state.rendered_highlights = active_highlights
    state.hitmap = output.hitmap
    state.handle = output.handle
    state.geometry = {
        mode = active_config.render.geometry,
        total_extent = geometry.total_extent,
        viewport_start = geometry.viewport_start,
        viewport_end = geometry.viewport_end,
    }
    if state_callback ~= nil then
        pcall(state_callback, state)
    end
    return state
end

---@param source_win integer
---@return ScrollbarWindowState?
M.render = function(source_win)
    source_win = source_win or vim.api.nvim_get_current_win()
    if not visible then
        close_source(source_win)
        return nil
    end

    local root_config = config.get()
    local active_source = active_source_window()
    local selection = source_selection(source_win, root_config, active_source)
    if root_config.visibility == "active" then
        if selection == nil then
            close_source(source_win)
            if active_source ~= nil then
                close_other_states(active_source)
            else
                close_all_states()
            end
            return nil
        end
        close_other_states(assert(active_source, "active source unavailable"))
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
---@return ScrollbarWindowState?
M.get_state = function(source_win)
    return states[source_win]
end

---@param float_win integer
---@return ScrollbarWindowState?
M.get_state_by_float = function(float_win)
    return states_by_float[float_win]
end

---@param source_win integer
---@return ScrollbarHitCell[][]?
M.get_hitmap = function(source_win)
    local state = states[source_win]
    return state and state.hitmap or nil
end

---@param source_win integer
---@return false|ScrollbarHandleGeometry?
M.get_handle = function(source_win)
    local state = states[source_win]
    return state and state.handle or nil
end

---@param source_win integer
---@return boolean
M.reveal = function(source_win)
    local root_config = config.get()
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
    if not config.get().autohide.enabled then
        return false
    end
    local was_revealed = revealed[source_win] ~= nil or states[source_win] ~= nil
    conceal_source(source_win)
    return was_revealed
end

---@param float_win integer
---@param pressed boolean
---@return boolean
M.set_handle_pressed = function(float_win, pressed)
    local state = states_by_float[float_win]
    if state == nil or not valid_window(state.float_win) or not vim.api.nvim_buf_is_valid(state.float_buf) then
        return false
    end

    pressed = pressed == true
    if state.handle_pressed == pressed then
        return true
    end

    local highlights = rendered_highlights(state.highlights, pressed, state.config)
    local ok = pcall(update_highlight_extmarks, state, highlights)
    if ok then
        state.handle_pressed = pressed
        state.rendered_highlights = highlights
    end
    return ok
end

---@param callback? fun(state: ScrollbarWindowState)
M.set_state_callback = function(callback)
    state_callback = callback
    if callback == nil then
        return
    end
    for _, state in pairs(states) do
        pcall(callback, state)
    end
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
    return buffer_eligible(bufnr, config.get())
end

---@param winid integer
---@return boolean
M.is_source_window = function(winid)
    return source_selection(winid, config.get(), active_source_window()) ~= nil
end

---@param bufnr? integer
---@return integer[]
M.source_windows = function(bufnr)
    local root_config = config.get()
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
    for source_win in pairs(statuscolumn_reservations) do
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
    clear_all_caches()
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

---@param source_win? integer
M.dispose = function(source_win)
    if source_win ~= nil then
        close_source(source_win)
        return
    end

    visible = false
    revealed = {}
    close_all_states()
    clear_all_caches()
    if lifecycle_group ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, lifecycle_group)
        lifecycle_group = nil
    end
end

M.setup = function()
    M.dispose()
    visible = config.get().show
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
                clear_source_cache(closed_win)
                release_statuscolumn(closed_win)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinNew", {
        group = lifecycle_group,
        callback = function()
            local current_win = vim.api.nvim_get_current_win()
            local parent_win = vim.fn.win_getid(vim.fn.winnr("#"))
            restore_inherited_statuscolumn(current_win, parent_win)
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = lifecycle_group,
        callback = function(args)
            clear_buffer_caches(args.buf)
            local pending = {}
            for _, state in pairs(states) do
                if state.source_buf == args.buf or state.float_buf == args.buf then
                    table.insert(pending, state)
                end
            end
            for _, state in ipairs(pending) do
                close_state(state)
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = lifecycle_group,
        callback = sweep_states,
    })
end

return M
