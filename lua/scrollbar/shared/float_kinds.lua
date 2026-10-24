--- Built-in kinds of floating windows: the windows of the snacks.nvim picker
--- and the Telescope picker. The lookups read the picker state of a plugin
--- only when the plugin already loaded its picker module, so they never load
--- a plugin. Each plugin call runs in `pcall`, and a failure means "no kind".
---
--- The picker state is not a formal API of either plugin. The integration
--- test pins both plugins and fails when a field moves.

local M = {}

---@param value any
---@return integer?
local function window_id(value)
    return type(value) == "number" and value or nil
end

--- The window of a `snacks.win`.
---@param object any
---@return integer?
local function snacks_window(object)
    local win = type(object) == "table" and object.win or nil
    return window_id(type(win) == "table" and win.win or nil)
end

---@return table[] pickers The active snacks pickers of every tab page
local function snacks_pickers()
    local module = package.loaded["snacks.picker.core.picker"]
    if type(module) ~= "table" or type(module.get) ~= "function" then
        return {}
    end
    local ok, pickers = pcall(module.get, { tab = false })
    if not ok or type(pickers) ~= "table" then
        return {}
    end
    return pickers
end

---@return table[] pickers The open Telescope pickers
local function telescope_pickers()
    local state = package.loaded["telescope.state"]
    if
        type(state) ~= "table"
        or type(state.get_existing_prompt_bufnrs) ~= "function"
        or type(state.get_status) ~= "function"
    then
        return {}
    end
    local ok, prompts = pcall(state.get_existing_prompt_bufnrs)
    if not ok or type(prompts) ~= "table" then
        return {}
    end
    local result = {}
    for _, prompt_bufnr in ipairs(prompts) do
        local status_ok, status = pcall(state.get_status, prompt_bufnr)
        local picker = status_ok and type(status) == "table" and status.picker or nil
        if type(picker) == "table" then
            result[#result + 1] = picker
        end
    end
    return result
end

--- The window of one part of a Telescope picker. A layout that creates the
--- preview later updates `picker.layout` but not always the picker field.
---@param picker table
---@param part "prompt"|"results"|"preview"
---@return integer?
local function telescope_window(picker, part)
    local layout = type(picker.layout) == "table" and picker.layout or nil
    local window = layout and layout[part]
    local from_layout = type(window) == "table" and window_id(window.winid) or nil
    return from_layout or window_id(picker[part .. "_win"])
end

---@param picker table
---@param part "prompt"|"results"|"preview"
---@return integer?
local function telescope_border(picker, part)
    local border = picker[part .. "_border"]
    if type(border) ~= "table" then
        local layout = type(picker.layout) == "table" and picker.layout or nil
        local window = layout and layout[part]
        border = type(window) == "table" and window.border or nil
    end
    return type(border) == "table" and window_id(border.winid) or nil
end

local TELESCOPE_PARTS = { "prompt", "results", "preview" }

---@param winid integer
---@return ScrollbarFloatKind?
local function kind(winid)
    for _, picker in ipairs(snacks_pickers()) do
        if type(picker) == "table" then
            if snacks_window(picker.list) == winid then
                return "snacks_list"
            end
            if snacks_window(picker.preview) == winid then
                return "snacks_preview"
            end
        end
    end
    for _, picker in ipairs(telescope_pickers()) do
        if telescope_window(picker, "results") == winid then
            return "telescope_results"
        end
        if telescope_window(picker, "preview") == winid then
            return "telescope_preview"
        end
    end
    return nil
end

---@param windows integer[]
---@param seen table<integer, true>
---@param winid? integer
local function add(windows, seen, winid)
    if winid ~= nil and not seen[winid] then
        seen[winid] = true
        windows[#windows + 1] = winid
    end
end

---@param picker table
---@return integer[]
local function snacks_group(picker)
    local windows = {}
    local seen = {}
    for _, part in ipairs({ "input", "list", "preview" }) do
        add(windows, seen, snacks_window(picker[part]))
    end
    local layout = type(picker.layout) == "table" and picker.layout or nil
    if layout ~= nil then
        for _, field in ipairs({ "wins", "box_wins" }) do
            local wins = layout[field]
            if type(wins) == "table" then
                for _, win in pairs(wins) do
                    add(windows, seen, type(win) == "table" and window_id(win.win) or nil)
                end
            end
        end
    end
    return windows
end

---@param picker table
---@return integer[]
local function telescope_group(picker)
    local windows = {}
    local seen = {}
    for _, part in ipairs(TELESCOPE_PARTS) do
        add(windows, seen, telescope_window(picker, part))
        add(windows, seen, telescope_border(picker, part))
    end
    return windows
end

---@param winid integer
---@return integer[]
local function group(winid)
    for _, picker in ipairs(snacks_pickers()) do
        if type(picker) == "table" then
            local windows = snacks_group(picker)
            if vim.list_contains(windows, winid) then
                return windows
            end
        end
    end
    for _, picker in ipairs(telescope_pickers()) do
        local windows = telescope_group(picker)
        if vim.list_contains(windows, winid) then
            return windows
        end
    end
    return {}
end

---@param winid integer
---@return table?
local function snacks_list(winid)
    for _, picker in ipairs(snacks_pickers()) do
        if type(picker) == "table" and snacks_window(picker.list) == winid then
            return picker.list
        end
    end
    return nil
end

-- A picker field can be a metatable lookup that raises an error. Any failure
-- means that the window has no kind.

--- The kind of a built-in picker window.
---@param winid integer
---@return ScrollbarFloatKind?
M.kind = function(winid)
    local ok, result = pcall(kind, winid)
    return ok and result or nil
end

--- The windows of the picker that `winid` belongs to, `winid` included. A
--- window outside a picker has an empty group.
---@param winid integer
---@return integer[]
M.group = function(winid)
    local ok, result = pcall(group, winid)
    return ok and result or {}
end

--- The snacks list object whose window is `winid`.
---@param winid integer
---@return table?
M.snacks_list = function(winid)
    local ok, result = pcall(snacks_list, winid)
    return ok and result or nil
end

return M
