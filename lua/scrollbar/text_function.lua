--- Calls the text functions of the marks and of the thumb, and checks their
--- results. A failed or invalid call hides its text and notifies once for each
--- key and message, so a broken function does not flood the messages on every
--- render.

local M = {}

---@type table<string, true>
local notified = {}

---@param label string
---@param message string
local function notify_once(label, message)
    local key = label .. "\0" .. message
    if notified[key] then
        return
    end
    notified[key] = true
    vim.notify(string.format("[nvim-scrollbar] %s %s", label, message), vim.log.levels.ERROR)
end

---Display width of a string without control characters.
---@param text string
---@return integer
M.width = function(text)
    -- Printable ASCII has one cell for each byte, which skips an API call for
    -- the common case of numbers and letters.
    if not text:find("[\128-\255]") then
        return #text
    end
    return vim.api.nvim_strwidth(text)
end

---@param value any
---@return string? reason Nil when the value is a valid text
local function invalid_reason(value)
    if type(value) ~= "string" then
        return string.format("returned a %s, not a string", type(value))
    end
    if value:find("%c") then
        return "returned text with control characters"
    end
    if M.width(value) <= 0 then
        return "returned text without display width"
    end
    return nil
end

---Calls a text function. Nil, `""`, an error, and an invalid result all hide
---the text. The last two notify once.
---@param fn function
---@param context table
---@param label string Names the function in a notification, for example `"the thumb text function"`
---@return string? text
M.call = function(fn, context, label)
    local ok, result = pcall(fn, context)
    if not ok then
        notify_once(label, "failed: " .. tostring(result))
        return nil
    end
    if result == nil or result == "" then
        return nil
    end
    local reason = invalid_reason(result)
    if reason ~= nil then
        notify_once(label, reason)
        return nil
    end
    return result
end

---Forgets the notifications, so that the next failure notifies again.
M.reset = function()
    notified = {}
end

return M
