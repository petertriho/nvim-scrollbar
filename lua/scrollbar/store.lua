local config = require("scrollbar.config")
local search_compact = require("scrollbar.providers.search_compact")

local M = {}

---@type table<integer, ScrollbarStoreTrustedSnapshot>
local marks_by_buffer = {}

---@type table<integer, ScrollbarWindowStoreTrustedSnapshot>
local marks_by_window = {}

---@type ScrollbarStoreTrustedSnapshot
local empty_buffer_snapshot = { marks = {}, revision = 0 }

---@type ScrollbarWindowStoreTrustedSnapshot
local empty_window_snapshot = { marks = {}, revision = 0 }

---@type table<string, table<string, table<integer, table<string, true>>>>
local warned = {}

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

---@param changed table<integer, true>
---@param target integer
local function mark_changed(changed, target)
    changed[target] = true
end

---@param snapshot table<string, ScrollbarMark[]>
---@return table<string, ScrollbarMark[]>
local function copy_snapshot(snapshot)
    local copy = {}
    for provider, marks in pairs(snapshot) do
        copy[provider] = marks
    end
    return copy
end

---@param current { revision: integer }?
---@return integer
local function next_revision(current)
    return (current and current.revision or 0) + 1
end

---@param provider string
---@param scope string
---@param target integer
local function reset_warnings(provider, scope, target)
    local provider_warnings = warned[provider]
    if provider_warnings == nil then
        return
    end

    local scope_warnings = provider_warnings[scope]
    if scope_warnings == nil then
        return
    end

    scope_warnings[target] = nil
    if next(scope_warnings) == nil then
        provider_warnings[scope] = nil
    end
    if next(provider_warnings) == nil then
        warned[provider] = nil
    end
end

---@param provider string
---@param scope string
---@param target integer
---@param signature string
local function warn_once(provider, scope, target, signature)
    warned[provider] = warned[provider] or {}
    warned[provider][scope] = warned[provider][scope] or {}
    warned[provider][scope][target] = warned[provider][scope][target] or {}
    if warned[provider][scope][target][signature] then
        return
    end

    warned[provider][scope][target][signature] = true
    vim.notify(
        string.format(
            "[scrollbar.nvim] provider '%s' returned invalid marks for %s %d: %s",
            provider,
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
local function validate_text(text)
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
end

---@param bufnr integer
---@param marks any
---@return ScrollbarMark[]? normalized
---@return string? error_signature
local function validate_marks(bufnr, marks)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        return nil, "buffer is invalid"
    end
    if not is_dense_list(marks) then
        return nil, "marks must be a dense list"
    end

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local mark_types = config.get().marks
    local normalized = {}
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
        if mark.line < 0 or mark.line >= line_count then
            return nil, string.format("marks[%d].line must be between 0 and %d", index, line_count - 1)
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

        normalized[index] = {
            line = mark.line,
            type = mark.type,
            text = mark.text,
        }
    end
    return normalized, nil
end

---@param provider string
---@param bufnr integer
---@param marks any
---@return boolean success
---@return ScrollbarChangedBuffers changed_buffers
M.set = function(provider, bufnr, marks)
    local normalized, validation_error = validate_marks(bufnr, marks)
    if normalized == nil then
        assert(validation_error ~= nil, "validation error missing")
        local changed = M.clear(provider, bufnr)
        warn_once(provider, "buffer", bufnr, validation_error)
        return false, changed
    end

    reset_warnings(provider, "buffer", bufnr)
    local current = marks_by_buffer[bufnr]
    local buffer_marks = current and current.marks or empty_buffer_snapshot.marks
    local previous = buffer_marks[provider]
    local replacing_compact = provider == "search" and current ~= nil and current.compact_search ~= nil
    if not replacing_compact and previous ~= nil and vim.deep_equal(previous, normalized) then
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
    }
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
    }
    return true, { [bufnr] = true }
end

---Returns a stored normalized snapshot without copying.
---Internal callers must treat the snapshot and all nested marks as immutable.
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
    if not vim.api.nvim_win_is_valid(winid) then
        validation_error = "window is invalid"
    else
        normalized, validation_error = validate_marks(vim.api.nvim_win_get_buf(winid), marks)
    end
    if normalized == nil then
        assert(validation_error ~= nil, "validation error missing")
        local changed = M.clear_window(provider, winid)
        warn_once(provider, "window", winid, validation_error)
        return false, changed
    end

    reset_warnings(provider, "window", winid)
    local current = marks_by_window[winid]
    local window_marks = current and current.marks or empty_window_snapshot.marks
    local previous = window_marks[provider]
    if previous ~= nil and vim.deep_equal(previous, normalized) then
        return true, {}
    end

    local updated = copy_snapshot(window_marks)
    updated[provider] = normalized
    marks_by_window[winid] = { marks = updated, revision = next_revision(current) }
    return true, { [winid] = true }
end

---@param winid integer
---@return ScrollbarWindowStoreSnapshot
M.get_window = function(winid)
    return vim.deepcopy(M._get_window_snapshot(winid).marks)
end

---Returns a stored normalized snapshot without copying.
---Internal callers must treat the snapshot and all nested marks as immutable.
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
    }
    mark_changed(changed, bufnr)
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
    marks_by_window[winid] = { marks = updated, revision = next_revision(current) }
    mark_changed(changed, winid)
    return changed
end

---@param provider string
---@return ScrollbarChangedBuffers changed_buffers
M.clear_provider = function(provider)
    local changed = {}
    for bufnr, current in pairs(marks_by_buffer) do
        local clears_compact = provider == "search" and current.compact_search ~= nil
        if current.marks[provider] ~= nil or clears_compact then
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
            }
            mark_changed(changed, bufnr)
        end
    end
    local provider_warnings = warned[provider]
    if provider_warnings ~= nil then
        provider_warnings.buffer = nil
        if next(provider_warnings) == nil then
            warned[provider] = nil
        end
    end
    return changed
end

---@param provider string
---@return ScrollbarChangedWindows changed_windows
M.clear_window_provider = function(provider)
    local changed = {}
    for winid, current in pairs(marks_by_window) do
        if current.marks[provider] ~= nil then
            local updated = copy_snapshot(current.marks)
            updated[provider] = nil
            marks_by_window[winid] = { marks = updated, revision = next_revision(current) }
            mark_changed(changed, winid)
        end
    end
    local provider_warnings = warned[provider]
    if provider_warnings ~= nil then
        provider_warnings.window = nil
        if next(provider_warnings) == nil then
            warned[provider] = nil
        end
    end
    return changed
end

---@param bufnr integer
---@return ScrollbarChangedBuffers changed_buffers
M.clear_buffer = function(bufnr)
    local changed = {}
    local current = marks_by_buffer[bufnr]
    if current ~= nil and (next(current.marks) ~= nil or current.compact_search ~= nil) then
        marks_by_buffer[bufnr] = { marks = {}, revision = next_revision(current) }
        mark_changed(changed, bufnr)
    end
    for provider in pairs(warned) do
        reset_warnings(provider, "buffer", bufnr)
    end
    return changed
end

---@param winid integer
local function clear_window_state(winid)
    local current = marks_by_window[winid]
    if current ~= nil and next(current.marks) ~= nil then
        marks_by_window[winid] = { marks = {}, revision = next_revision(current) }
    end
    for provider in pairs(warned) do
        reset_warnings(provider, "window", winid)
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
