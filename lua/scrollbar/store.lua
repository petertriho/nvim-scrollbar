local config = require("scrollbar.config")
local minimap_config = require("scrollbar.minimap.config")
local search_compact = require("scrollbar.providers.search_compact")

local M = {}

---@type table<integer, ScrollbarStoreTrustedSnapshot>
local marks_by_buffer = {}

---@type table<integer, ScrollbarWindowStoreTrustedSnapshot>
local marks_by_window = {}

---@type ScrollbarStoreTrustedSnapshot
local empty_buffer_snapshot = {
    marks = {},
    revision = 0,
    minimap_spans = {},
    minimap_span_revision = 0,
}

---@type ScrollbarWindowStoreTrustedSnapshot
local empty_window_snapshot = {
    marks = {},
    revision = 0,
    minimap_points = {},
    minimap_point_revision = 0,
}

---@type table<string, table<string, table<integer, table<string, true>>>>
local warned = {}

---@type table<table, fun(event: ScrollbarStoreEvent)>
local subscribers = {}

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number" and value ~= math.huge and value ~= -math.huge and value == math.floor(value)
end

-- Union of configured mark types across scrollbar and minimap variants,
-- rebuilt only when either compiled variants table is replaced. `config.set`
-- and the minimap equivalent recompile into fresh tables, so identity is the
-- invalidation signal; publications otherwise re-derived this set on every
-- call, which showed up as measurable per-publication overhead.
local cached_mark_types
local cached_scrollbar_variants
local cached_minimap_variants

---@return table<string, true>
local function configured_mark_types()
    local scrollbar_variants = config.get_variants()
    local minimap_variants = minimap_config.get_variants()
    if
        cached_mark_types ~= nil
        and cached_scrollbar_variants == scrollbar_variants
        and cached_minimap_variants == minimap_variants
    then
        return cached_mark_types
    end

    local mark_types = {}
    for _, variant in ipairs(scrollbar_variants) do
        for mark_type in pairs(variant.config.marks) do
            mark_types[mark_type] = true
        end
    end
    for _, variant in ipairs(minimap_variants) do
        for mark_type in pairs(variant.config.overlays.types) do
            mark_types[mark_type] = true
        end
    end
    cached_mark_types = mark_types
    cached_scrollbar_variants = scrollbar_variants
    cached_minimap_variants = minimap_variants
    return mark_types
end

---@param changed table<integer, true>
---@param target integer
local function mark_changed(changed, target)
    changed[target] = true
end

---@param scope ScrollbarStoreScope
---@param channel ScrollbarStoreChannel
---@param target integer
---@param provider string
local function notify(scope, channel, target, provider)
    local callbacks = {}
    for _, callback in pairs(subscribers) do
        table.insert(callbacks, callback)
    end
    for _, callback in ipairs(callbacks) do
        pcall(callback, {
            scope = scope,
            channel = channel,
            target = target,
            provider = provider,
        })
    end
end

---@param callback fun(event: ScrollbarStoreEvent)
---@return fun()
M.subscribe = function(callback)
    if type(callback) ~= "function" then
        error("[scrollbar.nvim] store subscriber must be a function", 2)
    end

    local token = {}
    subscribers[token] = callback
    return function()
        subscribers[token] = nil
    end
end

---@generic T
---@param snapshot table<string, T>
---@return table<string, T>
local function copy_snapshot(snapshot)
    local copy = {}
    for provider, marks in pairs(snapshot) do
        copy[provider] = marks
    end
    return copy
end

-- Specialized equality for stored normalized payloads. `vim.deep_equal`
-- costs ~250 ns per mark (type dispatch + generic table walking); provider
-- refreshes re-publish identical payloads on every event, so the no-op path
-- is the hot one. Field-wise comparison keeps semantics identical because
-- validation guarantees the exact field sets.

local function marks_equal(left, right)
    local count = #left
    if count ~= #right then
        return false
    end
    for index = 1, count do
        local a = left[index]
        local b = right[index]
        if a.line ~= b.line or a.type ~= b.type or a.text ~= b.text then
            return false
        end
    end
    return true
end

local function spans_equal(left, right)
    local count = #left
    if count ~= #right then
        return false
    end
    for index = 1, count do
        local a = left[index]
        local b = right[index]
        if
            a.line ~= b.line
            or a.start_col ~= b.start_col
            or a.end_col ~= b.end_col
            or a.highlight ~= b.highlight
            or a.priority ~= b.priority
        then
            return false
        end
    end
    return true
end

local function points_equal(left, right)
    local count = #left
    if count ~= #right then
        return false
    end
    for index = 1, count do
        local a = left[index]
        local b = right[index]
        if a.line ~= b.line or a.col ~= b.col or a.highlight ~= b.highlight or a.priority ~= b.priority then
            return false
        end
    end
    return true
end

---@param snapshot table<string, any>
---@param extra? string
---@return string[]
local function sorted_providers(snapshot, extra)
    local seen = {}
    local providers = {}
    for provider in pairs(snapshot) do
        seen[provider] = true
        table.insert(providers, provider)
    end
    if extra ~= nil and not seen[extra] then
        table.insert(providers, extra)
    end
    table.sort(providers)
    return providers
end

---@param current { revision: integer }?
---@return integer
local function next_revision(current)
    return (current and current.revision or 0) + 1
end

---@param current ScrollbarStoreTrustedSnapshot?
---@return integer
local function next_minimap_span_revision(current)
    return (current and current.minimap_span_revision or 0) + 1
end

---@param current ScrollbarWindowStoreTrustedSnapshot?
---@return integer
local function next_minimap_point_revision(current)
    return (current and current.minimap_point_revision or 0) + 1
end

---@param provider string
---@param channel ScrollbarStoreChannel
---@param target integer
local function reset_warnings(provider, channel, target)
    local provider_warnings = warned[provider]
    if provider_warnings == nil then
        return
    end

    local channel_warnings = provider_warnings[channel]
    if channel_warnings == nil then
        return
    end

    channel_warnings[target] = nil
    if next(channel_warnings) == nil then
        provider_warnings[channel] = nil
    end
    if next(provider_warnings) == nil then
        warned[provider] = nil
    end
end

---@param provider string
---@param channel ScrollbarStoreChannel
---@param scope string
---@param target integer
---@param signature string
local function warn_once(provider, channel, scope, target, signature)
    warned[provider] = warned[provider] or {}
    warned[provider][channel] = warned[provider][channel] or {}
    warned[provider][channel][target] = warned[provider][channel][target] or {}
    if warned[provider][channel][target][signature] then
        return
    end

    warned[provider][channel][target][signature] = true
    local output = channel == "marks" and "marks" or channel:gsub("_", " ")
    vim.notify(
        string.format(
            "[scrollbar.nvim] provider '%s' returned invalid %s for %s %d: %s",
            provider,
            output,
            scope,
            target,
            signature
        ),
        vim.log.levels.WARN
    )
end

---@param value any
---@return boolean
local function is_dense_list(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if not is_integer(key) or key < 1 then
            return false
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    return count == maximum
end

---@param text any
---@return string?
-- Memo of already-validated text values. Strings are immutable, so a value
-- that passed once (string type, no control characters, positive display
-- width) always will; provider refreshes publish repetitive glyph texts, and
-- the pcall'd strdisplaywidth API per mark dominated text-bearing validation.
local validated_text = {}
local validated_text_count = 0

local function validate_text(text)
    if validated_text[text] then
        return nil
    end
    if type(text) ~= "string" then
        return "text must be a string"
    end
    if text:find("%c") then
        return "text must not contain control characters"
    end

    local ok, width = pcall(vim.fn.strdisplaywidth, text)
    if not ok or width <= 0 then
        return "text must have positive display width"
    end
    validated_text[text] = true
    validated_text_count = validated_text_count + 1
    if validated_text_count > 4096 then
        validated_text = {}
        validated_text_count = 0
    end
end

---@param bufnr integer
---@param marks any
---@param previous? ScrollbarMark[] trusted normalized payload from the previous revision
---@return ScrollbarMark[]? normalized
---@return string? error_signature
---@return boolean unchanged true when every retained element matched and the count is stable
local function validate_marks(bufnr, marks, previous)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil, "buffer is invalid"
    end
    if not is_dense_list(marks) then
        return nil, "marks must be a dense list"
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local mark_types = configured_mark_types()
    local normalized = {}
    local count = 0
    local unchanged = previous ~= nil
    for index, mark in ipairs(marks) do
        if type(mark) ~= "table" then
            return nil, string.format("marks[%d] must be a table", index)
        end
        for field in pairs(mark) do
            if field ~= "line" and field ~= "type" and field ~= "text" then
                return nil, string.format("marks[%d] has an unknown field", index)
            end
        end
        if not is_integer(mark.line) then
            return nil, string.format("marks[%d].line must be an integer", index)
        end
        if mark.line < 0 then
            return nil, string.format("marks[%d].line must be non-negative", index)
        end
        if type(mark.type) ~= "string" or mark_types[mark.type] == nil then
            return nil, string.format("marks[%d].type is not configured", index)
        end
        if mark.text ~= nil then
            local text_error = validate_text(mark.text)
            if text_error ~= nil then
                return nil, string.format("marks[%d].%s", index, text_error)
            end
        end

        if mark.line < line_count then
            count = count + 1
            -- Reuse the trusted normalized element when the value is unchanged:
            -- provider refreshes typically move a few marks while the rest of the
            -- payload stays identical, and re-allocating every element shows up
            -- as GC pauses in publication p95 tails. Reused elements are already
            -- store-owned, so callers can never gain write access through them.
            local retained = previous and previous[count] or nil
            if
                retained ~= nil
                and retained.line == mark.line
                and retained.type == mark.type
                and retained.text == mark.text
            then
                normalized[count] = retained
            else
                normalized[count] = {
                    line = mark.line,
                    type = mark.type,
                    text = mark.text,
                }
                unchanged = false
            end
        end
    end
    if previous == nil or #previous ~= count then
        unchanged = false
    end
    return normalized, nil, unchanged
end

---@param bufnr integer
---@param spans any
---@param previous? ScrollbarMinimapSourceSpan[] trusted normalized payload from the previous revision
---@return ScrollbarMinimapSourceSpan[]? normalized
---@return string? error_signature
---@return boolean unchanged true when every retained element matched and the count is stable
local function validate_minimap_spans(bufnr, spans, previous)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil, "buffer is invalid"
    end
    if not is_dense_list(spans) then
        return nil, "minimap spans must be a dense list"
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local normalized = {}
    local count = 0
    local unchanged = previous ~= nil
    for index, span in ipairs(spans) do
        if type(span) ~= "table" then
            return nil, string.format("minimap spans[%d] must be a table", index)
        end
        for field in pairs(span) do
            if
                field ~= "line"
                and field ~= "start_col"
                and field ~= "end_col"
                and field ~= "highlight"
                and field ~= "priority"
            then
                return nil, string.format("minimap spans[%d] has an unknown field", index)
            end
        end
        if not is_integer(span.line) then
            return nil, string.format("minimap spans[%d].line must be an integer", index)
        end
        if span.line < 0 then
            return nil, string.format("minimap spans[%d].line must be non-negative", index)
        end
        if not is_integer(span.start_col) then
            return nil, string.format("minimap spans[%d].start_col must be an integer", index)
        end
        if span.start_col < 0 then
            return nil, string.format("minimap spans[%d].start_col must be non-negative", index)
        end
        if not is_integer(span.end_col) then
            return nil, string.format("minimap spans[%d].end_col must be an integer", index)
        end
        if span.end_col <= span.start_col then
            return nil, string.format("minimap spans[%d].end_col must be greater than start_col", index)
        end
        if type(span.highlight) ~= "string" or span.highlight == "" then
            return nil, string.format("minimap spans[%d].highlight must be a non-empty string", index)
        end
        if not is_integer(span.priority) then
            return nil, string.format("minimap spans[%d].priority must be an integer", index)
        end

        if span.line < line_count then
            count = count + 1
            local retained = previous and previous[count] or nil
            if
                retained ~= nil
                and retained.line == span.line
                and retained.start_col == span.start_col
                and retained.end_col == span.end_col
                and retained.highlight == span.highlight
                and retained.priority == span.priority
            then
                normalized[count] = retained
            else
                normalized[count] = {
                    line = span.line,
                    start_col = span.start_col,
                    end_col = span.end_col,
                    highlight = span.highlight,
                    priority = span.priority,
                }
                unchanged = false
            end
        end
    end
    if previous == nil or #previous ~= count then
        unchanged = false
    end
    return normalized, nil, unchanged
end

---@param winid integer
---@param points any
---@param previous? ScrollbarMinimapSourcePoint[] trusted normalized payload from the previous revision
---@return ScrollbarMinimapSourcePoint[]? normalized
---@return string? error_signature
---@return boolean unchanged true when every retained element matched and the count is stable
local function validate_minimap_points(winid, points, previous)
    if not vim.api.nvim_win_is_valid(winid) then
        return nil, "window is invalid"
    end
    if not is_dense_list(points) then
        return nil, "minimap points must be a dense list"
    end

    local line_count = vim.api.nvim_buf_line_count(vim.api.nvim_win_get_buf(winid))
    local normalized = {}
    local count = 0
    local unchanged = previous ~= nil
    for index, point in ipairs(points) do
        if type(point) ~= "table" then
            return nil, string.format("minimap points[%d] must be a table", index)
        end
        for field in pairs(point) do
            if field ~= "line" and field ~= "col" and field ~= "highlight" and field ~= "priority" then
                return nil, string.format("minimap points[%d] has an unknown field", index)
            end
        end
        if not is_integer(point.line) then
            return nil, string.format("minimap points[%d].line must be an integer", index)
        end
        if point.line < 0 then
            return nil, string.format("minimap points[%d].line must be non-negative", index)
        end
        if not is_integer(point.col) then
            return nil, string.format("minimap points[%d].col must be an integer", index)
        end
        if point.col < 0 then
            return nil, string.format("minimap points[%d].col must be non-negative", index)
        end
        if type(point.highlight) ~= "string" or point.highlight == "" then
            return nil, string.format("minimap points[%d].highlight must be a non-empty string", index)
        end
        if not is_integer(point.priority) then
            return nil, string.format("minimap points[%d].priority must be an integer", index)
        end

        if point.line < line_count then
            count = count + 1
            local retained = previous and previous[count] or nil
            if
                retained ~= nil
                and retained.line == point.line
                and retained.col == point.col
                and retained.highlight == point.highlight
                and retained.priority == point.priority
            then
                normalized[count] = retained
            else
                normalized[count] = {
                    line = point.line,
                    col = point.col,
                    highlight = point.highlight,
                    priority = point.priority,
                }
                unchanged = false
            end
        end
    end
    if previous == nil or #previous ~= count then
        unchanged = false
    end
    return normalized, nil, unchanged
end

---@param provider string
---@param bufnr integer
---@param marks any
---@return boolean success
---@return ScrollbarChangedBuffers changed_buffers
M.set = function(provider, bufnr, marks)
    local current = marks_by_buffer[bufnr]
    local previous = current and current.marks[provider] or nil
    local normalized, validation_error, unchanged = validate_marks(bufnr, marks, previous)
    if normalized == nil then
        assert(validation_error ~= nil, "validation error missing")
        local changed = M.clear(provider, bufnr)
        warn_once(provider, "marks", "buffer", bufnr, validation_error)
        return false, changed
    end

    reset_warnings(provider, "marks", bufnr)
    local buffer_marks = current and current.marks or empty_buffer_snapshot.marks
    local replacing_compact = provider == "search" and current ~= nil and current.compact_search ~= nil
    if not replacing_compact and (unchanged or (previous ~= nil and marks_equal(previous, normalized))) then
        return true, {}
    end

    local updated = copy_snapshot(buffer_marks)
    updated[provider] = normalized
    local compact = current and current.compact_search or nil
    if replacing_compact then
        compact = nil
    end
    marks_by_buffer[bufnr] = {
        marks = updated,
        revision = next_revision(current),
        compact_search = compact,
        minimap_spans = current and current.minimap_spans or empty_buffer_snapshot.minimap_spans,
        minimap_span_revision = current and current.minimap_span_revision or 0,
    }
    notify("buffer", "marks", bufnr, provider)
    return true, { [bufnr] = true }
end

---@param bufnr integer
---@return ScrollbarStoreSnapshot
M.get = function(bufnr)
    local snapshot = M._get_snapshot(bufnr)
    local result = vim.deepcopy(snapshot.marks)
    if snapshot.compact_search ~= nil then
        result.search = search_compact.to_marks(snapshot.compact_search)
    end
    return result
end

---@param provider string
---@param bufnr integer
---@param spans any
---@return boolean success
---@return ScrollbarChangedBuffers changed_buffers
M.set_minimap_spans = function(provider, bufnr, spans)
    local current = marks_by_buffer[bufnr]
    local previous = current and current.minimap_spans[provider] or nil
    local normalized, validation_error, unchanged = validate_minimap_spans(bufnr, spans, previous)
    if normalized == nil then
        assert(validation_error ~= nil, "validation error missing")
        local changed = M.clear_minimap_spans(provider, bufnr)
        warn_once(provider, "minimap_spans", "buffer", bufnr, validation_error)
        return false, changed
    end

    reset_warnings(provider, "minimap_spans", bufnr)
    local buffer_spans = current and current.minimap_spans or empty_buffer_snapshot.minimap_spans
    if unchanged or (previous ~= nil and spans_equal(previous, normalized)) then
        return true, {}
    end

    local updated = copy_snapshot(buffer_spans)
    updated[provider] = normalized
    marks_by_buffer[bufnr] = {
        marks = current and current.marks or empty_buffer_snapshot.marks,
        revision = current and current.revision or 0,
        compact_search = current and current.compact_search or nil,
        minimap_spans = updated,
        minimap_span_revision = next_minimap_span_revision(current),
    }
    notify("buffer", "minimap_spans", bufnr, provider)
    return true, { [bufnr] = true }
end

---@param bufnr integer
---@return ScrollbarMinimapSpanStoreSnapshot
M.get_minimap_spans = function(bufnr)
    return vim.deepcopy(M._get_snapshot(bufnr).minimap_spans)
end

---Stores trusted built-in search matches without changing the public provider mark contract.
---@param bufnr integer
---@param compact ScrollbarCompactSearch
---@return boolean success
---@return ScrollbarChangedBuffers changed_buffers
M._set_search_compact = function(bufnr, compact)
    if not vim.api.nvim_buf_is_valid(bufnr) or not search_compact.valid(compact) then
        return false, M.clear("search", bufnr)
    end

    local current = marks_by_buffer[bufnr]
    if current ~= nil and current.marks.search == nil and vim.deep_equal(current.compact_search, compact) then
        return true, {}
    end

    local buffer_marks = current and current.marks or empty_buffer_snapshot.marks
    local updated = copy_snapshot(buffer_marks)
    updated.search = nil
    marks_by_buffer[bufnr] = {
        marks = updated,
        revision = next_revision(current),
        compact_search = compact,
        minimap_spans = current and current.minimap_spans or empty_buffer_snapshot.minimap_spans,
        minimap_span_revision = current and current.minimap_span_revision or 0,
    }
    notify("buffer", "marks", bufnr, "search")
    return true, { [bufnr] = true }
end

---Returns a stored normalized snapshot without copying.
---Internal callers must treat the snapshot and all nested values as immutable.
---@param bufnr integer
---@return ScrollbarStoreTrustedSnapshot
M._get_snapshot = function(bufnr)
    return marks_by_buffer[bufnr] or empty_buffer_snapshot
end

---@param provider string
---@param winid integer
---@param marks any
---@return boolean success
---@return ScrollbarChangedWindows changed_windows
M.set_window = function(provider, winid, marks)
    local normalized
    local validation_error
    local unchanged = false
    local current = marks_by_window[winid]
    local previous = current and current.marks[provider] or nil
    if not vim.api.nvim_win_is_valid(winid) then
        validation_error = "window is invalid"
    else
        normalized, validation_error, unchanged = validate_marks(vim.api.nvim_win_get_buf(winid), marks, previous)
    end
    if normalized == nil then
        assert(validation_error ~= nil, "validation error missing")
        local changed = M.clear_window(provider, winid)
        warn_once(provider, "marks", "window", winid, validation_error)
        return false, changed
    end

    reset_warnings(provider, "marks", winid)
    local window_marks = current and current.marks or empty_window_snapshot.marks
    if unchanged or (previous ~= nil and marks_equal(previous, normalized)) then
        return true, {}
    end

    local updated = copy_snapshot(window_marks)
    updated[provider] = normalized
    marks_by_window[winid] = {
        marks = updated,
        revision = next_revision(current),
        minimap_points = current and current.minimap_points or empty_window_snapshot.minimap_points,
        minimap_point_revision = current and current.minimap_point_revision or 0,
    }
    notify("window", "marks", winid, provider)
    return true, { [winid] = true }
end

---@param winid integer
---@return ScrollbarWindowStoreSnapshot
M.get_window = function(winid)
    return vim.deepcopy(M._get_window_snapshot(winid).marks)
end

---@param provider string
---@param winid integer
---@param points any
---@return boolean success
---@return ScrollbarChangedWindows changed_windows
M.set_minimap_points = function(provider, winid, points)
    local current = marks_by_window[winid]
    local previous = current and current.minimap_points[provider] or nil
    local normalized, validation_error, unchanged = validate_minimap_points(winid, points, previous)
    if normalized == nil then
        assert(validation_error ~= nil, "validation error missing")
        local changed = M.clear_minimap_points(provider, winid)
        warn_once(provider, "minimap_points", "window", winid, validation_error)
        return false, changed
    end

    reset_warnings(provider, "minimap_points", winid)
    local window_points = current and current.minimap_points or empty_window_snapshot.minimap_points
    if unchanged or (previous ~= nil and points_equal(previous, normalized)) then
        return true, {}
    end

    local updated = copy_snapshot(window_points)
    updated[provider] = normalized
    marks_by_window[winid] = {
        marks = current and current.marks or empty_window_snapshot.marks,
        revision = current and current.revision or 0,
        minimap_points = updated,
        minimap_point_revision = next_minimap_point_revision(current),
    }
    notify("window", "minimap_points", winid, provider)
    return true, { [winid] = true }
end

---@param winid integer
---@return ScrollbarMinimapPointStoreSnapshot
M.get_minimap_points = function(winid)
    return vim.deepcopy(M._get_window_snapshot(winid).minimap_points)
end

---Returns a stored normalized snapshot without copying.
---Internal callers must treat the snapshot and all nested values as immutable.
---@param winid integer
---@return ScrollbarWindowStoreTrustedSnapshot
M._get_window_snapshot = function(winid)
    return marks_by_window[winid] or empty_window_snapshot
end

---@param provider string
---@param bufnr integer
---@return ScrollbarChangedBuffers changed_buffers
M.clear = function(provider, bufnr)
    local changed = {}
    local current = marks_by_buffer[bufnr]
    local clears_compact = provider == "search" and current ~= nil and current.compact_search ~= nil
    if current == nil or (current.marks[provider] == nil and not clears_compact) then
        return changed
    end

    local updated = copy_snapshot(current.marks)
    updated[provider] = nil
    local compact = current.compact_search
    if clears_compact then
        compact = nil
    end
    marks_by_buffer[bufnr] = {
        marks = updated,
        revision = next_revision(current),
        compact_search = compact,
        minimap_spans = current.minimap_spans,
        minimap_span_revision = current.minimap_span_revision,
    }
    mark_changed(changed, bufnr)
    notify("buffer", "marks", bufnr, provider)
    return changed
end

---@param provider string
---@param bufnr integer
---@return ScrollbarChangedBuffers changed_buffers
M.clear_minimap_spans = function(provider, bufnr)
    local changed = {}
    local current = marks_by_buffer[bufnr]
    if current == nil or current.minimap_spans[provider] == nil then
        return changed
    end

    local updated = copy_snapshot(current.minimap_spans)
    updated[provider] = nil
    marks_by_buffer[bufnr] = {
        marks = current.marks,
        revision = current.revision,
        compact_search = current.compact_search,
        minimap_spans = updated,
        minimap_span_revision = next_minimap_span_revision(current),
    }
    mark_changed(changed, bufnr)
    notify("buffer", "minimap_spans", bufnr, provider)
    return changed
end

---@param provider string
---@param winid integer
---@return ScrollbarChangedWindows changed_windows
M.clear_window = function(provider, winid)
    local changed = {}
    local current = marks_by_window[winid]
    if current == nil or current.marks[provider] == nil then
        return changed
    end

    local updated = copy_snapshot(current.marks)
    updated[provider] = nil
    marks_by_window[winid] = {
        marks = updated,
        revision = next_revision(current),
        minimap_points = current.minimap_points,
        minimap_point_revision = current.minimap_point_revision,
    }
    mark_changed(changed, winid)
    notify("window", "marks", winid, provider)
    return changed
end

---@param provider string
---@param winid integer
---@return ScrollbarChangedWindows changed_windows
M.clear_minimap_points = function(provider, winid)
    local changed = {}
    local current = marks_by_window[winid]
    if current == nil or current.minimap_points[provider] == nil then
        return changed
    end

    local updated = copy_snapshot(current.minimap_points)
    updated[provider] = nil
    marks_by_window[winid] = {
        marks = current.marks,
        revision = current.revision,
        minimap_points = updated,
        minimap_point_revision = next_minimap_point_revision(current),
    }
    mark_changed(changed, winid)
    notify("window", "minimap_points", winid, provider)
    return changed
end

---@param provider string
---@return ScrollbarChangedBuffers changed_buffers
M._clear_marks_provider = function(provider)
    local changed = {}
    for bufnr in pairs(marks_by_buffer) do
        local mark_changes = M.clear(provider, bufnr)
        if mark_changes[bufnr] then
            mark_changed(changed, bufnr)
        end
    end
    local provider_warnings = warned[provider]
    if provider_warnings ~= nil then
        provider_warnings.marks = nil
        if next(provider_warnings) == nil then
            warned[provider] = nil
        end
    end
    return changed
end

---@param provider string
---@return ScrollbarChangedBuffers changed_buffers
M._clear_minimap_spans_provider = function(provider)
    local changed = {}
    for bufnr in pairs(marks_by_buffer) do
        local span_changes = M.clear_minimap_spans(provider, bufnr)
        if span_changes[bufnr] then
            mark_changed(changed, bufnr)
        end
    end
    local provider_warnings = warned[provider]
    if provider_warnings ~= nil then
        provider_warnings.minimap_spans = nil
        if next(provider_warnings) == nil then
            warned[provider] = nil
        end
    end
    return changed
end

---@param provider string
---@return ScrollbarChangedBuffers changed_buffers
M.clear_provider = function(provider)
    local changed = M._clear_marks_provider(provider)
    local span_changes = M._clear_minimap_spans_provider(provider)
    for bufnr in pairs(span_changes) do
        mark_changed(changed, bufnr)
    end
    return changed
end

---@param provider string
---@return ScrollbarChangedWindows changed_windows
M._clear_window_marks_provider = function(provider)
    local changed = {}
    for winid in pairs(marks_by_window) do
        local mark_changes = M.clear_window(provider, winid)
        if mark_changes[winid] then
            mark_changed(changed, winid)
        end
    end
    local provider_warnings = warned[provider]
    if provider_warnings ~= nil then
        provider_warnings.marks = nil
        if next(provider_warnings) == nil then
            warned[provider] = nil
        end
    end
    return changed
end

---@param provider string
---@return ScrollbarChangedWindows changed_windows
M._clear_minimap_points_provider = function(provider)
    local changed = {}
    for winid in pairs(marks_by_window) do
        local point_changes = M.clear_minimap_points(provider, winid)
        if point_changes[winid] then
            mark_changed(changed, winid)
        end
    end
    local provider_warnings = warned[provider]
    if provider_warnings ~= nil then
        provider_warnings.minimap_points = nil
        if next(provider_warnings) == nil then
            warned[provider] = nil
        end
    end
    return changed
end

---@param provider string
---@return ScrollbarChangedWindows changed_windows
M.clear_window_provider = function(provider)
    local changed = M._clear_window_marks_provider(provider)
    local point_changes = M._clear_minimap_points_provider(provider)
    for winid in pairs(point_changes) do
        mark_changed(changed, winid)
    end
    return changed
end

---@param bufnr integer
---@return ScrollbarChangedBuffers changed_buffers
M.clear_buffer = function(bufnr)
    local changed = {}
    local current = marks_by_buffer[bufnr]
    if current ~= nil then
        local mark_providers = sorted_providers(current.marks, current.compact_search ~= nil and "search" or nil)
        local span_providers = sorted_providers(current.minimap_spans)
        local marks_changed = #mark_providers > 0
        local spans_changed = #span_providers > 0
        if marks_changed or spans_changed then
            marks_by_buffer[bufnr] = {
                marks = marks_changed and {} or current.marks,
                revision = marks_changed and next_revision(current) or current.revision,
                compact_search = marks_changed and nil or current.compact_search,
                minimap_spans = spans_changed and {} or current.minimap_spans,
                minimap_span_revision = spans_changed and next_minimap_span_revision(current)
                    or current.minimap_span_revision,
            }
            mark_changed(changed, bufnr)
        end

        for _, provider in ipairs(mark_providers) do
            notify("buffer", "marks", bufnr, provider)
        end
        for _, provider in ipairs(span_providers) do
            notify("buffer", "minimap_spans", bufnr, provider)
        end
    end
    for provider in pairs(warned) do
        reset_warnings(provider, "marks", bufnr)
        reset_warnings(provider, "minimap_spans", bufnr)
    end
    return changed
end

---@param winid integer
local function clear_window_state(winid)
    local current = marks_by_window[winid]
    if current ~= nil then
        local mark_providers = sorted_providers(current.marks)
        local point_providers = sorted_providers(current.minimap_points)
        local marks_changed = #mark_providers > 0
        local points_changed = #point_providers > 0
        if marks_changed or points_changed then
            marks_by_window[winid] = {
                marks = marks_changed and {} or current.marks,
                revision = marks_changed and next_revision(current) or current.revision,
                minimap_points = points_changed and {} or current.minimap_points,
                minimap_point_revision = points_changed and next_minimap_point_revision(current)
                    or current.minimap_point_revision,
            }
        end

        for _, provider in ipairs(mark_providers) do
            notify("window", "marks", winid, provider)
        end
        for _, provider in ipairs(point_providers) do
            notify("window", "minimap_points", winid, provider)
        end
    end
    for provider in pairs(warned) do
        reset_warnings(provider, "marks", winid)
        reset_warnings(provider, "minimap_points", winid)
    end
end

local group = vim.api.nvim_create_augroup("ScrollbarStore", { clear = true })
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
        M.clear_buffer(args.buf)
    end,
})
vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
        local winid = tonumber(args.match)
        if winid ~= nil then
            clear_window_state(winid)
        end
    end,
})

return M
