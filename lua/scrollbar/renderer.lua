local config = require("scrollbar.config")
local float = require("scrollbar.shared.float")
local float_states = require("scrollbar.shared.float_states")
local layout = require("scrollbar.layout")
local providers = require("scrollbar.providers")
local source_policy = require("scrollbar.shared.source_policy")
local stack = require("scrollbar.shared.stack")
local store = require("scrollbar.shared.store")
local window_config = require("scrollbar.config.window")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarRenderer")
local AUGROUP_NAME = "ScrollbarRendererLifecycle"
local FLOAT_WINHIGHLIGHT = "Normal:ScrollbarBase,NormalNC:ScrollbarBase,EndOfBuffer:ScrollbarBase,"
    .. "FloatBorder:ScrollbarFloatBorder,FloatTitle:ScrollbarFloatTitle,FloatFooter:ScrollbarFloatFooter,"
    .. float.SEARCH_WINHIGHLIGHT
-- Window and buffer variable that marks a scrollbar float, also from an
-- earlier setup.
local OWNED_VAR = "scrollbar_owned"
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

---@type table<integer, boolean>
local owned_float_buffers = {}

---@type table<integer, ScrollbarStatuscolumnReservation>
local statuscolumn_reservations = {}

---@type table<integer, ScrollbarFlattenedMarksCache>
local flattened_cache = {}

---@type table<integer, ScrollbarLineMarkLayerCache>
local line_layer_cache = {}

---@type table<integer, table>
local screen_layer_cache = {}

local valid_window = source_policy.valid_window

---@param source_win integer
local function clear_render_caches(source_win)
    flattened_cache[source_win] = nil
    line_layer_cache[source_win] = nil
    screen_layer_cache[source_win] = nil
    layout.clear_screen_cache(source_win)
end

local function clear_all_caches()
    flattened_cache = {}
    line_layer_cache = {}
    screen_layer_cache = {}
    layout.clear_cache()
    layout.clear_all_screen_caches()
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

---Apply the statuscolumn wrapper of a reservation and draw it once. The
---function releases the reservation when the wrapper fails or when another
---value replaces it.
---@param source_win integer
---@param reservation ScrollbarStatuscolumnReservation
---@return boolean applied
local function apply_statuscolumn(source_win, reservation)
    set_local_option(source_win, "statuscolumn", reservation.applied_statuscolumn)
    vim.api.nvim__redraw({ flush = true })
    if reservation.failed then
        set_local_option(source_win, "statuscolumn", "")
        release_statuscolumn(source_win)
        return false
    end
    if vim.api.nvim_get_option_value("statuscolumn", { win = source_win }) ~= reservation.applied_statuscolumn then
        release_statuscolumn(source_win)
        return false
    end
    return true
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
    if not apply_statuscolumn(source_win, reservation) then
        return nil
    end
    local textoff = vim.fn.getwininfo(source_win)[1].textoff
    local actual_span = math.max(0, textoff - reservation.base_textoff)
    if actual_span < span then
        reservation.span = actual_span
        reservation.limited = true
        if not apply_statuscolumn(source_win, reservation) then
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
    local placement = active_config.placement
    return placement.relative == "window"
        and (placement.anchor == "NW" or placement.anchor == "SW")
        and placement.gutter ~= "overlap"
end

---@param active_config ScrollbarConfig
---@return ScrollbarGutterPosition
local function reservation_position(active_config)
    return active_config.placement.gutter == "outer" and "outer" or "inner"
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

-- `clear_buffer_caches` is defined after the float states, because it clears
-- the memo of the source selection. The float states call it to drop the
-- caches of a deleted buffer.
local clear_buffer_caches

local floats = float_states.new({
    renderer = "scrollbar",
    config = config,
    owned_var = OWNED_VAR,
    augroup = AUGROUP_NAME,
    tuning = M,
    states = states,
    states_by_float = states_by_float,
    owned_float_buffers = owned_float_buffers,
    retained = statuscolumn_reservations,
    release = release_statuscolumn,
    forget = clear_render_caches,
    forget_buffer = function(bufnr)
        clear_buffer_caches(bufnr)
    end,
})

local policy = floats.policy
local active_source_window = policy.active_source_window
---@type fun(source_win: integer, root_config: ScrollbarConfig, active_source?: integer, basic_ok?: boolean): ScrollbarConfigSelection?
local source_selection = policy.source_selection
local close_state = floats.close_state
local close_source = floats.close_source
local close_all_states = floats.close_all
local prepare_source = floats.prepare_source
local render_selection = floats.render_selection
local is_visible = floats.is_visible

---@param source_buf integer
clear_buffer_caches = function(source_buf)
    local pending = {}
    for source_win, cached in pairs(flattened_cache) do
        if cached.source_buf == source_buf then
            table.insert(pending, source_win)
        end
    end
    for _, source_win in ipairs(pending) do
        policy.invalidate(source_win)
        clear_render_caches(source_win)
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
    for _, winid in ipairs(stack.windows("scrollbar")) do
        if winid ~= source_win then
            stack.publish("scrollbar", winid, nil)
        end
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

---@param active_config ScrollbarConfig
---@return boolean
local function west_anchor(active_config)
    local anchor = active_config.placement.anchor
    return anchor == "NW" or anchor == "SW"
end

--- The column that `placement.col` applies to, without stacking.
---@param active_config ScrollbarConfig
---@param source_win integer
---@param area table<string, integer>
---@return integer
local function placement_origin(active_config, source_win, area)
    local placement = active_config.placement
    if west_anchor(active_config) then
        if reserves_statuscolumn(active_config) and placement.gutter == "inner" then
            return reservation_base_textoff(source_win)
        end
        return 0
    end
    return placement.relative == "window" and area.width or vim.o.columns
end

-- Compiled configurations do not change, so each one keeps one placement
-- table. As a result, a steady render allocates nothing for stacking.
---@type table<ScrollbarConfig, ScrollbarStackPlacement>
local stack_placements = setmetatable({}, { __mode = "k" })

---@param active_config ScrollbarConfig
---@return ScrollbarStackPlacement
local function stack_placement(active_config)
    local cached = stack_placements[active_config]
    if cached == nil then
        local placement = active_config.placement
        cached = {
            relative = placement.relative,
            side = west_anchor(active_config) and "W" or "E",
            zindex = placement.zindex,
        }
        stack_placements[active_config] = cached
    end
    return cached
end

---@param active_config ScrollbarConfig
---@param origin integer
---@param width integer
---@param previous? ScrollbarStackFootprint Returned again when nothing changed
---@return ScrollbarStackFootprint
local function stack_footprint(active_config, origin, width, previous)
    local placement = stack_placement(active_config)
    local col = active_config.placement.col
    if
        previous ~= nil
        and previous.origin == origin
        and previous.width == width
        and previous.col == col
        and previous.relative == placement.relative
        and previous.side == placement.side
        and previous.zindex == placement.zindex
    then
        return previous
    end
    return {
        relative = placement.relative,
        side = placement.side,
        zindex = placement.zindex,
        origin = origin,
        col = col,
        width = width,
    }
end

--- Width of the float with its border. The stack footprint and the
--- statuscolumn reservation use this width.
---@param active_config ScrollbarConfig
---@param width integer Content width
---@return integer
local function frame_width(active_config, width)
    local sides = active_config.window.sides
    return width + sides.left + sides.right
end

---@param source_win integer
---@param active_config ScrollbarConfig
---@param area table<string, integer>
---@param origin integer Resolved horizontal origin that `placement.col` applies to
---@param zindex integer Resolved z-index
---@param width integer Content width
---@param height integer Content height
---@param hidden boolean
---@return table<string, any>
local function float_config(active_config, source_win, area, origin, zindex, width, height, hidden)
    return float.config(active_config, source_win, area.top, area.height, origin, zindex, width, height, hidden)
end

---@param float_buf integer
local function configure_buffer(float_buf)
    float.configure_buffer(float_buf, "scrollbar", OWNED_VAR)
    owned_float_buffers[float_buf] = true
end

---@param float_win integer
---@param window ScrollbarWindowConfig
local function configure_window(float_win, window)
    float.configure_window(float_win, OWNED_VAR, window_config.winhighlight(FLOAT_WINHIGHLIGHT, window), nil, window.wo)
end

---@param source_win integer
---@param source_buf integer
---@param active_config ScrollbarConfig
---@param variant_id integer
---@param active_float_config table<string, any>
---@param configure_owned_buffer fun(float_buf: integer)
---@param configure_owned_window fun(float_win: integer, window: ScrollbarWindowConfig)
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
    local window = active_config.window
    local float_win, float_buf = float.open(
        "scrollbar://source/%d/%d",
        source_win,
        active_float_config,
        window.open,
        configure_owned_buffer,
        function(opened_win)
            configure_owned_window(opened_win, window)
        end
    )
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
        geometry = { unit = "line", total_extent = 0, viewport_start = 0, viewport_end = 0 },
        sides = window.sides,
        window_signature = window.signature,
    }
    states[source_win] = state
    states_by_float[float_win] = state
    return state
end

---@param left ScrollbarLayoutMark
---@param right ScrollbarLayoutMark
local function flattened_mark_less(left, right)
    if left.line ~= right.line then
        return left.line < right.line
    end
    return (left.text or "") < (right.text or "")
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

    -- This loop emits the providers in name order and sorts the marks of each
    -- provider by (line, text), so the flattened array is in `source_less`
    -- order. The layout then skips the sort of each group on rebuilds. This
    -- code pays the sort cost only when a revision change rebuilds this cache
    -- anyway.
    local marks = {}
    for _, provider in ipairs(provider_names) do
        local base = #marks
        for _, snapshot in ipairs({ buffer_snapshot.marks, window_snapshot.marks }) do
            for _, mark in ipairs(snapshot[provider] or {}) do
                marks[#marks + 1] = {
                    provider = provider,
                    line = mark.line,
                    type = mark.type,
                    text = mark.text,
                }
            end
        end
        if #marks > base + 1 then
            local region = {}
            for index = base + 1, #marks do
                region[#region + 1] = marks[index]
            end
            table.sort(region, flattened_mark_less)
            for index = 1, #region do
                marks[base + index] = region[index]
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
---@param height integer Track rows
---@param viewport_height integer Text rows of the source window
---@param marks ScrollbarLayoutMark[]
---@param line_count? integer
---@param mark_rows? integer[]
---@param compact_search? ScrollbarCompactSearch
---@return ScrollbarGeometry
local function geometry_for(
    active_config,
    source_win,
    source_buf,
    height,
    viewport_height,
    marks,
    line_count,
    mark_rows,
    compact_search
)
    if active_config.unit == "screenline" then
        return layout.screen({
            source_win = source_win,
            height = height,
            viewport_height = viewport_height,
            marks = marks,
            marks_sorted = true,
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

    -- Rows and the mark layer depend only on marks, line_count, height,
    -- container_width, and the layout configuration. They do not depend on
    -- the revisions. When the flattened marks table is the same object as in
    -- the last build, the rows are computed again in place, and only the
    -- shifted entries are stored. When no row shifted, every layer input is
    -- provably identical, and the cached layer is reused.
    local rows_changed = nil
    local mark_rows
    if
        cached ~= nil
        and compact_search == nil
        and cached.source_buf == source_buf
        and cached.marks == marks
        and cached.height == height
    then
        mark_rows, rows_changed = layout.normalized_mark_rows({
            height = height,
            line_count = line_count,
            marks = marks,
            previous = {
                rows = cached.mark_rows,
                line_count = cached.line_count,
                height = cached.height,
                segments = cached.layer ~= nil and cached.layer.segments or nil,
            },
        })
    else
        mark_rows = layout.normalized_mark_rows({
            height = height,
            line_count = line_count,
            marks = marks,
        })
    end

    if
        rows_changed ~= nil
        and #rows_changed == 0
        and cached ~= nil
        and cached.container_width == container_width
        and (cached.config == layout_cache or vim.deep_equal(cached.config, layout_cache))
    then
        cached.config = layout_cache
        cached.buffer_revision = buffer_revision
        cached.window_revision = window_revision
        cached.line_count = line_count
        return cached
    end

    -- When a few rows shifted and all other inputs are identical, the layout
    -- gets the previous layer, so that it rebuilds only the affected rows.
    local previous_layer_input = nil
    if
        rows_changed ~= nil
        and #rows_changed > 0
        and cached ~= nil
        and cached.layer ~= nil
        and cached.container_width == container_width
        and (cached.config == layout_cache or vim.deep_equal(cached.config, layout_cache))
    then
        previous_layer_input = { layer = cached.layer, changed = rows_changed }
    end

    cached = {
        source_buf = source_buf,
        buffer_revision = buffer_revision,
        window_revision = window_revision,
        line_count = line_count,
        container_width = container_width,
        height = height,
        config = layout_cache,
        marks = marks,
        mark_rows = mark_rows,
        layer = layout.mark_layer({
            config = active_config,
            height = height,
            line_count = line_count,
            container_width = container_width,
            geometry = { mark_rows = mark_rows },
            marks = marks,
            marks_sorted = true,
            compact_search = compact_search,
            previous = previous_layer_input,
        }),
    }
    line_layer_cache[source_win] = cached
    return cached
end

---@param source_win integer
---@param source_buf integer
---@param buffer_revision integer
---@param window_revision integer
---@param container_width integer
---@param height integer
---@param active_config ScrollbarConfig
---@param marks ScrollbarLayoutMark[]
---@param geometry ScrollbarGeometry
---@param compact_search? ScrollbarCompactSearch
---@return ScrollbarResolvedMarkLayer
local function screen_mark_layer(
    source_win,
    source_buf,
    buffer_revision,
    window_revision,
    container_width,
    height,
    active_config,
    marks,
    geometry,
    compact_search
)
    local layout_cache = active_config.layout_cache
    local cached = screen_layer_cache[source_win]
    if
        cached ~= nil
        and cached.source_buf == source_buf
        and cached.buffer_revision == buffer_revision
        and cached.window_revision == window_revision
        and cached.container_width == container_width
        and cached.height == height
        and cached.marks == marks
        and cached.compact == compact_search
        and cached.mark_rows == geometry.mark_rows
        and cached.compact_mark_rows == geometry.compact_mark_rows
        and (cached.config == layout_cache or vim.deep_equal(cached.config, layout_cache))
    then
        cached.config = layout_cache
        return cached.layer
    end

    local layer = layout.mark_layer({
        config = active_config,
        height = height,
        line_count = vim.api.nvim_buf_line_count(source_buf),
        container_width = container_width,
        geometry = geometry,
        marks = marks,
        marks_sorted = true,
        compact_search = compact_search,
    })
    screen_layer_cache[source_win] = {
        source_buf = source_buf,
        buffer_revision = buffer_revision,
        window_revision = window_revision,
        container_width = container_width,
        height = height,
        marks = marks,
        compact = compact_search,
        mark_rows = geometry.mark_rows,
        compact_mark_rows = geometry.compact_mark_rows,
        config = layout_cache,
        layer = layer,
    }
    return layer
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
---@param output ScrollbarLayoutOutput
---@param width integer
---@param height integer
---@return ScrollbarHighlightSpan[][]
local function update_buffer(state, output, width, height)
    local highlights = rendered_highlights(output.highlights, state.handle_pressed, state.config)
    float.write_rows(
        state.float_buf,
        NAMESPACE,
        state.rows,
        state.rendered_highlights,
        output.rows,
        highlights,
        state.width ~= width or state.height ~= height
    )
    return highlights
end

---@param source_win integer
---@param selection ScrollbarConfigSelection
---@param root_config ScrollbarConfig
---@return ScrollbarWindowState?
local function render_source(source_win, selection, root_config)
    local active_config = selection.config
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local existing_state, concealed = prepare_source(source_win, source_buf, root_config.autohide)
    if concealed then
        local previous = stack.footprint("scrollbar", source_win)
        local origin = placement_origin(active_config, source_win, source_text_area(source_win))
        local width = previous and previous.width or frame_width(active_config, active_config.layout.width)
        stack.publish("scrollbar", source_win, stack_footprint(active_config, origin, width, previous))
        return nil
    end
    local reserved = reserves_statuscolumn(active_config)
    if reserved then
        local initial_width = existing_state and existing_state.width or active_config.layout.width
        local initial_span = math.max(0, frame_width(active_config, initial_width) + active_config.placement.col)
        if
            initial_span > 0
            and ensure_statuscolumn(source_win, initial_span, reservation_position(active_config)) == nil
        then
            close_source(source_win)
            return nil
        end
    else
        release_statuscolumn(source_win)
    end

    local marks, buffer_revision, window_revision, compact_search = flattened_marks(source_win, source_buf)
    local line_count = active_config.unit == "line" and vim.api.nvim_buf_line_count(source_buf) or nil
    local west = west_anchor(active_config)
    local stack_origin, stack_zindex = stack.resolve("scrollbar", source_win, stack_placement(active_config))
    local sides = active_config.window.sides
    local area
    local content_height
    local container_width
    local geometry
    local output
    for _ = 1, 3 do
        area = source_text_area(source_win)
        -- The frame stays inside the text area, so the border rows shorten the
        -- track.
        content_height = area.height - sides.top - sides.bottom
        if content_height < 1 then
            close_source(source_win)
            return nil
        end
        if active_config.placement.relative == "window" then
            local base_textoff = reserved and reservation_base_textoff(source_win) or 0
            container_width = math.max(0, area.width - base_textoff)
            if stack_origin ~= nil then
                -- Beside a minimap, named marks grow only up to the far edge.
                container_width = math.max(0, west and area.width - stack_origin or stack_origin)
            end
            local reservation = statuscolumn_reservations[source_win]
            if reserved and reservation ~= nil and reservation.limited then
                local maximum_width = math.max(0, reservation.span - active_config.placement.col)
                container_width = math.min(container_width, maximum_width)
            end
        else
            container_width = vim.o.columns
            if stack_origin ~= nil then
                container_width = math.max(0, west and vim.o.columns - stack_origin or stack_origin)
            end
        end
        container_width = math.max(0, container_width - sides.left - sides.right)

        local mark_layer
        if line_count ~= nil then
            local cached = line_mark_layer(
                source_win,
                source_buf,
                buffer_revision,
                window_revision,
                line_count,
                container_width,
                content_height,
                active_config,
                marks,
                compact_search
            )
            geometry = geometry_for(
                active_config,
                source_win,
                source_buf,
                content_height,
                area.height,
                marks,
                line_count,
                cached.mark_rows,
                compact_search
            )
            mark_layer = cached.layer
        else
            geometry = geometry_for(
                active_config,
                source_win,
                source_buf,
                content_height,
                area.height,
                marks,
                nil,
                nil,
                compact_search
            )
            mark_layer = screen_mark_layer(
                source_win,
                source_buf,
                buffer_revision,
                window_revision,
                container_width,
                content_height,
                active_config,
                marks,
                geometry,
                compact_search
            )
        end
        if geometry.total_extent <= area.height and active_config.thumb.hide_if_all_visible then
            geometry.handle = { first_row = -1, last_row = -1 }
        end

        output = layout.compose({
            config = active_config,
            height = content_height,
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
        local span = math.max(0, frame_width(active_config, output.width) + active_config.placement.col)
        local current = statuscolumn_reservations[source_win]
        if span == (current and current.span or 0) then
            break
        end
        if span > 0 and ensure_statuscolumn(source_win, span, reservation_position(active_config)) == nil then
            close_source(source_win)
            return nil
        end
    end

    assert(area ~= nil and content_height ~= nil and geometry ~= nil and output ~= nil, "render geometry unavailable")
    if reserved then
        local reservation = statuscolumn_reservations[source_win]
        local required_span = math.max(0, frame_width(active_config, output.width) + active_config.placement.col)
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
    local cursor_row, cursor_col = float.cursor_screen_position(source_win, active_config)
    local cursor_position_available = cursor_row ~= nil and cursor_col ~= nil
    local own_origin
    ---@type ScrollbarWindowState?
    local state = states[source_win]
    if
        state == nil
        or not valid_window(state.float_win)
        or not vim.api.nvim_buf_is_valid(state.float_buf)
        or state.window_signature ~= active_config.window.signature
    then
        if state ~= nil then
            close_state(state)
            if reserved then
                ensure_statuscolumn(
                    source_win,
                    math.max(0, frame_width(active_config, output.width) + active_config.placement.col),
                    reservation_position(active_config)
                )
            end
        end
        own_origin = placement_origin(active_config, source_win, area)
        local active_float_config = float_config(
            active_config,
            source_win,
            area,
            stack_origin or own_origin,
            stack_zindex,
            output.width,
            content_height,
            cursor_position_available
        )
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
            float.resolve_position()
        end
    else
        own_origin = placement_origin(active_config, source_win, area)
        local active_float_config = float_config(
            active_config,
            source_win,
            area,
            stack_origin or own_origin,
            stack_zindex,
            output.width,
            content_height,
            cursor_position_available and state.hidden_by_cursor or false
        )
        float.apply_config(state, active_float_config, cursor_position_available)
    end

    float.update_cursor_visibility(state, cursor_row, cursor_col)

    state.config = active_config
    state.variant_id = selection.variant_id
    local active_highlights = update_buffer(state, output, output.width, content_height)
    state.width = output.width
    state.height = content_height
    state.rows = output.rows
    state.highlights = output.highlights
    state.rendered_highlights = active_highlights
    state.hitmap = output.hitmap
    state.handle = output.handle
    state.geometry = {
        unit = active_config.unit,
        total_extent = geometry.total_extent,
        viewport_start = geometry.viewport_start,
        viewport_end = geometry.viewport_end,
    }
    state.footprint =
        stack_footprint(active_config, own_origin, frame_width(active_config, output.width), state.footprint)
    stack.publish("scrollbar", source_win, state.footprint)
    return state
end

---@param source_win integer
---@return ScrollbarWindowState?
M.render = function(source_win)
    source_win = source_win or vim.api.nvim_get_current_win()
    if not is_visible() then
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
    end
    return render_selection(source_win, selection, root_config, render_source)
end

--- Resolve the stacked origin and z-index of one scrollbar float again, after
--- the minimap footprint of its source window changes. The content does not
--- render again. When this function returns true, the caller schedules a
--- render, because the container for named-mark growth depends on the origin.
---@param source_win integer
---@return boolean changed
M.reposition = function(source_win)
    local state = states[source_win]
    local footprint = state and state.footprint
    if state == nil or footprint == nil or not valid_window(source_win) or not valid_window(state.float_win) then
        return false
    end
    local origin, zindex = stack.resolve("scrollbar", source_win, footprint)
    return float.reposition(state, footprint, origin, zindex)
end

---@type fun(source_win: integer): ScrollbarWindowState?
M.get_state = floats.get_state

---@type fun(float_win: integer): ScrollbarWindowState?
M.get_state_by_float = floats.get_state_by_float

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

---@type fun(source_win: integer): boolean
M.reveal = floats.reveal

---@type fun(source_win: integer): boolean
M.conceal = floats.conceal

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
    local ok = pcall(
        float.write_rows,
        state.float_buf,
        NAMESPACE,
        state.rows,
        state.rendered_highlights,
        state.rows,
        highlights,
        false
    )
    if ok then
        state.handle_pressed = pressed
        state.rendered_highlights = highlights
    end
    return ok
end

---@type fun(callback?: fun(state: ScrollbarWindowState))
M.set_state_callback = floats.set_state_callback

---@type fun(winid: integer): boolean
M.is_owned_window = policy.owned_window

--- Registry-only ownership check of the floats of the current setup.
---@type fun(winid: integer): boolean
M.is_owned_float_window = floats.is_owned_float_window

--- Registry-only ownership check of the float buffers of the current setup.
---@type fun(bufnr: integer): boolean
M.is_owned_float_buffer = floats.is_owned_float_buffer

---@type fun(bufnr: integer): boolean
M.is_owned_buffer = policy.owned_buffer

---@type fun(bufnr: integer): boolean
M.is_buffer_eligible = floats.is_buffer_eligible

--- The result is memoized for 50 ms, or for `M.source_selection_interval_ms`.
---@type fun(winid: integer): boolean
M.is_source_window = policy.is_source_window

---Clear the cached source eligibility of one window, or of all windows. The
---topology and option events of the scheduler call this function. It is safe
---to call at any time.
---@type fun(source_win?: integer)
M.invalidate_source_selection = policy.invalidate

---@type fun(bufnr?: integer): integer[]
M.source_windows = policy.source_windows

M.hide = function()
    floats.hide()
    clear_all_caches()
end

M.show = function()
    floats.set_visible(config.get().enabled)
end

M.toggle = function()
    if is_visible() then
        M.hide()
    else
        M.show()
    end
end

---@type fun(): boolean
M.is_visible = is_visible

---@type fun(bufnr: integer): integer[]
M.windows_showing_buffer = policy.windows_showing_buffer

---@param source_win? integer
M.dispose = function(source_win)
    if source_win ~= nil then
        close_source(source_win)
        return
    end

    floats.dispose()
    clear_all_caches()
end

M.setup = function()
    M.dispose()
    local root_config = config.get()
    local lifecycle_group = floats.setup(root_config.enabled and root_config.show)
    vim.api.nvim_create_autocmd("WinNew", {
        group = lifecycle_group,
        callback = function()
            local current_win = vim.api.nvim_get_current_win()
            local parent_win = vim.fn.win_getid(vim.fn.winnr("#"))
            restore_inherited_statuscolumn(current_win, parent_win)
        end,
    })
end

return M
