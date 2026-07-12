local config = require("scrollbar.config")

local M = {}

---@type table<integer, ScrollbarStoreSnapshot>
local marks_by_buffer = {}

---@type table<string, table<integer, table<string, true>>>
local warned = {}

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

---@param changed ScrollbarChangedBuffers
---@param bufnr integer
local function mark_changed(changed, bufnr)
    changed[bufnr] = true
end

---@param provider string
---@param bufnr integer
local function reset_warnings(provider, bufnr)
    local provider_warnings = warned[provider]
    if provider_warnings == nil then
        return
    end

    provider_warnings[bufnr] = nil
    if next(provider_warnings) == nil then
        warned[provider] = nil
    end
end

---@param provider string
---@param bufnr integer
---@param signature string
local function warn_once(provider, bufnr, signature)
    warned[provider] = warned[provider] or {}
    warned[provider][bufnr] = warned[provider][bufnr] or {}
    if warned[provider][bufnr][signature] then
        return
    end

    warned[provider][bufnr][signature] = true
    vim.notify(
        string.format(
            "[scrollbar.nvim] provider '%s' returned invalid marks for buffer %d: %s",
            provider,
            bufnr,
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
        warn_once(provider, bufnr, validation_error)
        return false, changed
    end

    reset_warnings(provider, bufnr)
    local buffer_marks = marks_by_buffer[bufnr]
    local previous = buffer_marks and buffer_marks[provider] or nil
    if previous ~= nil and vim.deep_equal(previous, normalized) then
        return true, {}
    end

    buffer_marks = buffer_marks or {}
    marks_by_buffer[bufnr] = buffer_marks
    buffer_marks[provider] = normalized
    return true, { [bufnr] = true }
end

---@param bufnr integer
---@return ScrollbarStoreSnapshot
M.get = function(bufnr)
    return vim.deepcopy(marks_by_buffer[bufnr] or {})
end

---@param provider string
---@param bufnr integer
---@return ScrollbarChangedBuffers changed_buffers
M.clear = function(provider, bufnr)
    local changed = {}
    local buffer_marks = marks_by_buffer[bufnr]
    if buffer_marks == nil or buffer_marks[provider] == nil then
        return changed
    end

    buffer_marks[provider] = nil
    mark_changed(changed, bufnr)
    if next(buffer_marks) == nil then
        marks_by_buffer[bufnr] = nil
    end
    return changed
end

---@param provider string
---@return ScrollbarChangedBuffers changed_buffers
M.clear_provider = function(provider)
    local changed = {}
    for bufnr, buffer_marks in pairs(marks_by_buffer) do
        if buffer_marks[provider] ~= nil then
            buffer_marks[provider] = nil
            mark_changed(changed, bufnr)
            if next(buffer_marks) == nil then
                marks_by_buffer[bufnr] = nil
            end
        end
    end
    warned[provider] = nil
    return changed
end

---@param bufnr integer
---@return ScrollbarChangedBuffers changed_buffers
M.clear_buffer = function(bufnr)
    local changed = {}
    if marks_by_buffer[bufnr] ~= nil then
        marks_by_buffer[bufnr] = nil
        mark_changed(changed, bufnr)
    end
    for provider in pairs(warned) do
        reset_warnings(provider, bufnr)
    end
    return changed
end

local group = vim.api.nvim_create_augroup("ScrollbarStore", { clear = true })
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = group,
    callback = function(args)
        M.clear_buffer(args.buf)
    end,
})

return M
