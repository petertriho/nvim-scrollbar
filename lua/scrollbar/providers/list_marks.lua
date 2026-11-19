--- The marks of the entries of a quickfix list or a location list. The `qflist`
--- and `loclist` providers share these rules.

local M = {}

-- After an insert or a delete of lines above the entries, Neovim moves the
-- entries. To read them again, a provider must read the whole list, which
-- costs about 2 ms for each 1,000 entries. Thus the providers read the list
-- this long after the last change of the line count, and not after each key.
M.LINE_MOVE_DELAY_MS = 100

---@class ScrollbarListTimer
---@field restart fun() Run the callback after the delay, unless another restart or a stop comes first
---@field stop fun()
---@field close fun()

--- A one-shot timer that runs `callback` in the main loop.
---@param delay integer
---@param callback fun()
---@return ScrollbarListTimer
M.timer = function(delay, callback)
    local handle = assert(vim.uv.new_timer())
    local scheduled = vim.schedule_wrap(callback)
    return {
        restart = function()
            handle:stop()
            handle:start(delay, 0, scheduled)
        end,
        stop = function()
            handle:stop()
        end,
        close = function()
            handle:stop()
            if not handle:is_closing() then
                handle:close()
            end
        end,
    }
end

---@param item table An entry of getqflist() or getloclist()
---@return boolean
local function is_marked(item)
    -- `:cnext` visits only valid entries, and lnum 0 is not a buffer line.
    return (item.valid == 1 or item.valid == true)
        and type(item.bufnr) == "number"
        and item.bufnr > 0
        and type(item.lnum) == "number"
        and item.lnum >= 1
end

---@param item table An entry of getqflist() or getloclist()
---@param types table<string, string|false>
---@param own_type string
---@return string? mark_type Nil when `types` drops the entry
local function mark_type(item, types, own_type)
    -- An entry can store its type in lower case.
    local letter = type(item.type) == "string" and item.type:upper() or ""
    local mapped = types[letter]
    if mapped == false then
        return nil
    end
    return mapped or own_type
end

---@param left ScrollbarMark
---@param right ScrollbarMark
---@return boolean
local function compare(left, right)
    if left.line == right.line then
        return left.type < right.type
    end
    return left.line < right.line
end

--- The `types` map from the normalized options of a list provider.
---@param options any
---@return table<string, string|false>
M.types = function(options)
    if type(options) == "table" and type(options.types) == "table" then
        return options.types
    end
    return {}
end

--- One mark for each marked entry, grouped by buffer and sorted by line.
---@param items table[] The entries of getqflist() or getloclist()
---@param types table<string, string|false> The mark type for each entry type letter, or false to drop the entries
---@param own_type string The mark type of an untyped or unmapped entry
---@param bufnr? integer When set, only the marks of this buffer
---@return table<integer, ScrollbarMark[]>
M.by_buffer = function(items, types, own_type, bufnr)
    local result = {}
    for _, item in ipairs(items) do
        if (bufnr == nil or item.bufnr == bufnr) and is_marked(item) then
            local selected = mark_type(item, types, own_type)
            if selected ~= nil then
                local marks = result[item.bufnr]
                if marks == nil then
                    marks = {}
                    result[item.bufnr] = marks
                end
                marks[#marks + 1] = { line = item.lnum - 1, type = selected }
            end
        end
    end
    for _, marks in pairs(result) do
        table.sort(marks, compare)
    end
    return result
end

return M
