local config = require("scrollbar.config")
local layout = require("scrollbar.layout")

local M = {}

local AUGROUP_NAME = "ScrollbarMouse"
local MAPPINGS = { "<LeftMouse>", "<LeftDrag>", "<LeftRelease>" }

---@class ScrollbarMouseRuntime
---@field config ScrollbarConfig
---@field renderer ScrollbarMouseRenderer
---@field scheduler ScrollbarMouseScheduler
---@field augroup integer
---@field attached table<integer, true>

---@type ScrollbarMouseRuntime?
local runtime

---@type ScrollbarInteractionState?
local interaction

---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---@param state ScrollbarWindowState
---@return boolean
local function valid_state(state)
    return valid_window(state.source_win)
        and valid_window(state.float_win)
        and vim.api.nvim_buf_is_valid(state.source_buf)
        and vim.api.nvim_buf_is_valid(state.float_buf)
        and vim.api.nvim_win_get_buf(state.source_win) == state.source_buf
        and vim.api.nvim_win_get_buf(state.float_win) == state.float_buf
end

---@param source_win integer
local function restore_source(source_win)
    if valid_window(source_win) then
        pcall(vim.api.nvim_set_current_win, source_win)
        return
    end

    local active = runtime
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local owned = false
        if active ~= nil then
            local ok, result = pcall(active.renderer.is_owned_window, winid)
            owned = ok and result == true
        end
        if not owned and vim.api.nvim_win_get_config(winid).relative == "" then
            pcall(vim.api.nvim_set_current_win, winid)
            return
        end
    end
end

---@param current ScrollbarInteractionState
local function restore_focus(current)
    restore_source(current.source_win)
end

---@param current ScrollbarInteractionState
---@param pressed boolean
local function set_handle_pressed(current, pressed)
    local active = runtime
    if active == nil or current.handle_grab_offset == nil or type(active.renderer.set_handle_pressed) ~= "function" then
        return
    end
    pcall(active.renderer.set_handle_pressed, current.float_win, pressed)
end

---@param float_win integer
---@return integer, integer, integer
local function mouse_position(float_win)
    local mouse = vim.fn.getmousepos()
    if mouse.winid == float_win then
        return mouse.winid, mouse.winrow - 1, mouse.wincol
    end
    local position = vim.fn.win_screenpos(float_win)
    return mouse.winid, mouse.screenrow - position[1], mouse.screencol - position[2] + 1
end

---@param current ScrollbarInteractionState
---@return ScrollbarWindowState?
local function interaction_state(current)
    local active = runtime
    if active == nil then
        return nil
    end
    local state = active.renderer.get_state_by_float(current.float_win)
    if
        state == nil
        or state.source_win ~= current.source_win
        or state.source_buf ~= current.source_buf
        or state.float_buf ~= current.float_buf
        or not valid_state(state)
    then
        return nil
    end
    return state
end

---@param current ScrollbarInteractionState
---@param state ScrollbarWindowState
---@param line integer
---@return boolean
local function navigate(current, state, line)
    if not valid_state(state) then
        return false
    end
    local line_count = vim.api.nvim_buf_line_count(current.source_buf)
    line = clamp(line, 0, math.max(0, line_count - 1))
    local ok = pcall(vim.api.nvim_win_call, current.source_win, function()
        vim.api.nvim_win_set_cursor(current.source_win, { line + 1, 0 })
        vim.cmd("normal! zv")
        vim.cmd("normal! zz")
    end)
    if ok and runtime ~= nil then
        pcall(runtime.scheduler.invalidate_window, current.source_win)
    end
    return ok
end

---@param current ScrollbarInteractionState
---@param state ScrollbarWindowState
---@param row integer
---@return integer
local function track_line(current, state, row)
    return layout.track_row_to_line(
        current.source_win,
        row,
        state.height,
        state.geometry.mode,
        state.geometry.total_extent
    )
end

---@param current ScrollbarInteractionState
---@param state ScrollbarWindowState
---@param pointer_row integer
---@return integer
local function drag_line(current, state, pointer_row)
    local handle_height = current.handle.last_row - current.handle.first_row + 1
    local travel = math.max(0, state.height - handle_height)
    local handle_row = clamp(pointer_row - (current.handle_grab_offset or 0), 0, travel)
    local track_row = travel == 0 and 0 or math.floor(handle_row * (state.height - 1) / travel + 0.5)
    return track_line(current, state, track_row)
end

---@param callback fun()
---@param fallback_source? integer
---@return fun()
local function guarded(callback, fallback_source)
    return function()
        local ok = xpcall(callback, debug.traceback)
        if not ok then
            if interaction ~= nil then
                M.cancel()
            elseif fallback_source ~= nil then
                restore_source(fallback_source)
            end
        end
    end
end

---@param current ScrollbarInteractionState
---@param resume_deadline boolean
local function finish_interaction(current, resume_deadline)
    set_handle_pressed(current, false)
    interaction = nil
    restore_focus(current)
    if resume_deadline and runtime ~= nil then
        pcall(runtime.scheduler.resume_window, current.source_win)
    end
end

---@param float_win? integer
M.press = function(float_win)
    local active = runtime
    if active == nil or not active.config.mouse.enabled then
        return
    end
    if interaction ~= nil then
        M.cancel()
    end

    local state = active.renderer.get_state_by_float(float_win or vim.fn.getmousepos().winid)
    if state == nil or not valid_state(state) then
        return
    end
    local _, row, col = mouse_position(state.float_win)
    if row < 0 or row >= state.height or col < 1 or col > state.width then
        return
    end

    local hit = state.hitmap[row + 1] and state.hitmap[row + 1][col] or { handle = false }
    local handle_last_col = state.handle.column + state.handle.width - 1
    local pressed_handle = row >= state.handle.first_row
        and row <= state.handle.last_row
        and col >= state.handle.column
        and col <= handle_last_col
    interaction = {
        source_win = state.source_win,
        source_buf = state.source_buf,
        float_win = state.float_win,
        float_buf = state.float_buf,
        pressed_row = row,
        pressed_col = col,
        pressed_hit = vim.deepcopy(hit),
        handle = vim.deepcopy(state.handle),
        handle_grab_offset = pressed_handle and row - state.handle.first_row or nil,
        last_row = row,
        last_col = col,
        dragging = false,
    }
    pcall(active.scheduler.hold_window, state.source_win)
    if pressed_handle then
        set_handle_pressed(interaction, true)
    end
    if valid_window(state.float_win) then
        pcall(vim.api.nvim_set_current_win, state.float_win)
    end
end

M.drag = function()
    local current = interaction
    if current == nil then
        return
    end
    local state = interaction_state(current)
    if state == nil then
        M.cancel()
        return
    end

    local _, row, col = mouse_position(current.float_win)
    row = clamp(row, 0, state.height - 1)
    col = clamp(col, 1, state.width)
    local moved = row ~= current.pressed_row or col ~= current.pressed_col
    if moved and current.handle_grab_offset ~= nil then
        current.dragging = true
        navigate(current, state, drag_line(current, state, row))
    end
    current.last_row = row
    current.last_col = col
end

M.release = function()
    local current = interaction
    if current == nil then
        return
    end
    local state = interaction_state(current)
    if state == nil then
        M.cancel()
        return
    end

    local _, row = mouse_position(current.float_win)
    row = clamp(row, 0, state.height - 1)
    pcall(function()
        if current.dragging then
            navigate(current, state, drag_line(current, state, row))
        elseif current.pressed_hit.line ~= nil then
            navigate(current, state, current.pressed_hit.line)
        else
            navigate(current, state, track_line(current, state, current.pressed_row))
        end
    end)
    finish_interaction(current, true)
end

M.cancel = function()
    local current = interaction
    if current ~= nil then
        finish_interaction(current, true)
    end
end

---@param state ScrollbarWindowState
M.attach = function(state)
    local active = runtime
    if active == nil or not active.config.mouse.enabled or not valid_state(state) then
        return
    end
    if active.attached[state.float_buf] then
        return
    end

    vim.keymap.set(
        "n",
        "<LeftMouse>",
        guarded(function()
            M.press(state.float_win)
        end, state.source_win),
        {
            buffer = state.float_buf,
            nowait = true,
            silent = true,
        }
    )
    vim.keymap.set("n", "<LeftDrag>", guarded(M.drag), {
        buffer = state.float_buf,
        nowait = true,
        silent = true,
    })
    vim.keymap.set("n", "<LeftRelease>", guarded(M.release), {
        buffer = state.float_buf,
        nowait = true,
        silent = true,
    })
    active.attached[state.float_buf] = true
end

---@param options? ScrollbarMouseOptions
M.setup = function(options)
    M.dispose()
    options = options or {}
    local active_config = options.config or config.get()
    local active_renderer = options.renderer or require("scrollbar.renderer")
    local active_scheduler = options.scheduler or require("scrollbar.scheduler")
    local augroup = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
    runtime = {
        config = active_config,
        renderer = active_renderer,
        scheduler = active_scheduler,
        augroup = augroup,
        attached = {},
    }

    vim.api.nvim_create_autocmd("WinClosed", {
        group = augroup,
        callback = function(args)
            local current = interaction
            local closed = tonumber(args.match)
            if current ~= nil and (closed == current.float_win or closed == current.source_win) then
                M.cancel()
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinEnter", {
        group = augroup,
        callback = function()
            if interaction ~= nil then
                return
            end
            local float_win = vim.api.nvim_get_current_win()
            local state = active_renderer.get_state_by_float(float_win)
            if state ~= nil and vim.fn.getmousepos().winid == float_win then
                guarded(function()
                    M.press(float_win)
                end, state.source_win)()
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = augroup,
        callback = function(args)
            local active = runtime
            if active ~= nil then
                active.attached[args.buf] = nil
            end
            local current = interaction
            if current ~= nil and (args.buf == current.float_buf or args.buf == current.source_buf) then
                M.cancel()
            end
        end,
    })

    active_renderer.set_state_callback(M.attach)
end

M.dispose = function()
    local active = runtime
    if active == nil then
        return
    end
    if interaction ~= nil then
        finish_interaction(interaction, false)
    end
    runtime = nil
    active.renderer.set_state_callback(nil)
    for float_buf in pairs(active.attached) do
        if vim.api.nvim_buf_is_valid(float_buf) then
            for _, lhs in ipairs(MAPPINGS) do
                pcall(vim.keymap.del, "n", lhs, { buffer = float_buf })
            end
        end
    end
    pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
end

---@return ScrollbarInteractionState?
M.get_interaction = function()
    return interaction and vim.deepcopy(interaction) or nil
end

return M
