local M = {}

local UINT32_BYTES = 4

---@param lines integer[]
---@param partial? boolean
---@return ScrollbarCompactSearch
M.encode = function(lines, partial)
    local encoded = {}
    for index, line in ipairs(lines) do
        encoded[index] = string.char(
            math.floor(line / 0x1000000) % 0x100,
            math.floor(line / 0x10000) % 0x100,
            math.floor(line / 0x100) % 0x100,
            line % 0x100
        )
    end
    return { data = table.concat(encoded), count = #lines, partial = partial == true }
end

---@param compact ScrollbarCompactSearch
---@param callback fun(line: integer, index: integer)
M.each = function(compact, callback)
    local index = 0
    for offset = 1, #compact.data, UINT32_BYTES do
        index = index + 1
        local first, second, third, fourth = compact.data:byte(offset, offset + UINT32_BYTES - 1)
        callback(first * 0x1000000 + second * 0x10000 + third * 0x100 + fourth, index)
    end
end

---@param compact ScrollbarCompactSearch
---@return ScrollbarMark[]
M.to_marks = function(compact)
    local marks = {}
    M.each(compact, function(line, index)
        marks[index] = { line = line, type = "Search" }
    end)
    return marks
end

---@param compact any
---@return boolean
M.valid = function(compact)
    return type(compact) == "table"
        and type(compact.data) == "string"
        and type(compact.count) == "number"
        and compact.count >= 0
        and compact.count == math.floor(compact.count)
        and #compact.data == compact.count * UINT32_BYTES
        and (compact.partial == nil or type(compact.partial) == "boolean")
end

return M
