--- Focus rules for the mouse floats of the scrollbar and the minimap.
---
--- The floats are not focusable, so window commands skip them, but a click
--- still enters them. The buffer-local mouse mappings of a float apply only
--- when its buffer is current, so a click from another window starts the
--- press on `WinEnter`. Any other entry returns focus to the window that it
--- left.

local M = {}

local LEFT_MOUSE = vim.keycode("<LeftMouse>")

-- Fast clicks on one cell arrive as multi-clicks, and the default multi-click
-- starts Visual mode in the float. The floats take them as single clicks.
---@type table<string, string>
local SINGLE_CLICK = {}
for count = 2, 4 do
    for _, event in ipairs({ "Mouse", "Drag", "Release" }) do
        SINGLE_CLICK[vim.keycode(string.format("<%d-Left%s>", count, event))] = vim.keycode("<Left" .. event .. ">")
    end
end

---@class ScrollbarFloatFocusOptions
---@field name string Namespace name for the key listener
---@field group integer Augroup for the `WinEnter` autocmd
---@field get_state fun(float_win: integer): { source_win: integer }?
---@field interacting fun(): boolean
---@field press fun(float_win: integer, source_win: integer)

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---Focus `source_win`, or the first non-floating window when it is closed.
---@param source_win integer
M.restore = function(source_win)
    if valid_window(source_win) then
        pcall(vim.api.nvim_set_current_win, source_win)
        return
    end
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(winid).relative == "" then
            pcall(vim.api.nvim_set_current_win, winid)
            return
        end
    end
end

---@param options ScrollbarFloatFocusOptions
---@return fun() unwatch
M.watch = function(options)
    local namespace = vim.api.nvim_create_namespace(options.name)
    ---@type integer?
    local clicked_win

    ---@param float_win integer
    ---@param previous integer
    ---@param source_win integer
    local function leave(float_win, previous, source_win)
        if vim.api.nvim_get_current_win() ~= float_win or options.interacting() then
            return
        end
        if previous ~= float_win and valid_window(previous) and options.get_state(previous) == nil then
            pcall(vim.api.nvim_set_current_win, previous)
        else
            M.restore(source_win)
        end
    end

    vim.on_key(function(key)
        clicked_win = nil
        local single = SINGLE_CLICK[key]
        if single ~= nil then
            if
                options.get_state(vim.api.nvim_get_current_win()) ~= nil
                or options.get_state(vim.fn.getmousepos().winid) ~= nil
            then
                vim.api.nvim_feedkeys(single, "im", false)
                return ""
            end
        elseif key == LEFT_MOUSE then
            clicked_win = vim.fn.getmousepos().winid
        end
    end, namespace)

    local autocmd = vim.api.nvim_create_autocmd("WinEnter", {
        group = options.group,
        nested = true,
        callback = function()
            local float_win = vim.api.nvim_get_current_win()
            local state = options.get_state(float_win)
            if state == nil or options.interacting() then
                return
            end
            local previous = vim.fn.win_getid(vim.fn.winnr("#"))
            -- The mouse mappings exist only in Normal mode.
            if clicked_win == float_win and vim.api.nvim_get_mode().mode == "n" then
                options.press(float_win, state.source_win)
                if options.interacting() then
                    return
                end
            end
            if vim.fn.getmousepos().winid ~= float_win then
                leave(float_win, previous, state.source_win)
                return
            end
            -- A mouse action places the cursor of the current window after
            -- `WinEnter`, so focus leaves after the action ends.
            vim.schedule(function()
                leave(float_win, previous, state.source_win)
            end)
        end,
    })

    return function()
        vim.on_key(nil, namespace)
        pcall(vim.api.nvim_del_autocmd, autocmd)
    end
end

return M
