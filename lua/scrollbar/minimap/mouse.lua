--- Minimap mouse: click + drag handlers for the minimap float. Parallel
--- to `lua/scrollbar/mouse.lua` but independent — no shared state. Line
--- mode only: row→line projection uses `floor(minimap_row * v_ratio)`.
---
--- Drag is frame-coalesced via the minimap scheduler: each `<LeftDrag>`
--- invalidates the source window through the scheduler; the scheduler's
--- interval_ms coalesces the resulting flushes. Source-window focus is
--- restored after every interaction (reusing the pattern at
--- `lua/scrollbar/mouse.lua:60-78`).

local M = {}

local AUGROUP_NAME = "ScrollbarMinimapMouse"
local MAPPINGS = { "<LeftMouse>", "<LeftDrag>", "<LeftRelease>" }

---@class ScrollbarMinimapMouseRuntime
---@field renderer ScrollbarMinimapMouseRenderer
---@field scheduler ScrollbarMinimapMouseScheduler
---@field augroup integer
---@field attached table<integer, true>

---@type ScrollbarMinimapMouseRuntime?
local runtime

---@type ScrollbarMinimapMouseInteraction?
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

---@param state ScrollbarMinimapRendererState
---@return boolean
local function valid_state(state)
    return valid_window(state.source_win)
        and valid_window(state.float_win)
        and vim.api.nvim_buf_is_valid(state.source_buf)
        and vim.api.nvim_buf_is_valid(state.float_buf)
        and vim.api.nvim_win_get_buf(state.source_win) == state.source_buf
        and vim.api.nvim_win_get_buf(state.float_win) == state.float_buf
end

---@param active ScrollbarMinimapMouseRuntime
---@param float_buf integer
local function detach(active, float_buf)
    if not active.attached[float_buf] then
        return
    end
    for _, lhs in ipairs(MAPPINGS) do
        pcall(vim.keymap.del, "n", lhs, { buffer = float_buf })
    end
    active.attached[float_buf] = nil
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

---@param current ScrollbarMinimapMouseInteraction
local function restore_focus(current)
    restore_source(current.source_win)
end

---Project a 0-based minimap row back to a 0-based source line using the
---line-mode v_ratio captured at press time.
---@param current ScrollbarMinimapMouseInteraction
---@param row integer 0-based minimap row
---@return integer source_line 0-based source line
local function row_to_line(current, row)
    local ratio = current.v_ratio
    local line = math.floor(row * ratio)
    return clamp(line, 0, math.max(0, current.source_line_count - 1))
end

---@param current ScrollbarMinimapMouseInteraction
---@param source_line integer 0-based source line
local function navigate(current, source_line)
    if not valid_window(current.source_win) or not vim.api.nvim_buf_is_valid(current.source_buf) then
        return false
    end
    local line = clamp(source_line, 0, math.max(0, current.source_line_count - 1))
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

---@param float_win integer
---@return integer mouse_winid
---@return integer row 0-based row relative to float
---@return integer col 1-based column relative to float
local function mouse_position(float_win)
    local mouse = vim.fn.getmousepos()
    if mouse.winid == float_win then
        return mouse.winid, mouse.winrow - 1, mouse.wincol
    end
    local position = vim.fn.win_screenpos(float_win)
    return mouse.winid, mouse.screenrow - position[1], mouse.screencol - position[2] + 1
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

---@param current ScrollbarMinimapMouseInteraction
local function finish_interaction(current)
    interaction = nil
    restore_focus(current)
    local active = runtime
    if active ~= nil then
        local state = active.renderer.get_state_by_float(current.float_win)
        if state ~= nil then
            M.attach(state)
        end
    end
end

---@param state ScrollbarMinimapRendererState
---@return ScrollbarMinimapMouseInteraction
local function build_interaction(state)
    local source_line_count = vim.api.nvim_buf_line_count(state.source_buf)
    local v_ratio = math.max(1, source_line_count / state.height)
    return {
        source_win = state.source_win,
        source_buf = state.source_buf,
        float_win = state.float_win,
        float_buf = state.float_buf,
        height = state.height,
        width = state.width,
        source_line_count = source_line_count,
        v_ratio = v_ratio,
        pressed_row = 0,
        dragging = false,
    }
end

---@param float_win? integer
M.press = function(float_win)
    local active = runtime
    if active == nil then
        return
    end
    if interaction ~= nil then
        M.cancel()
    end

    local state = active.renderer.get_state_by_float(float_win or vim.fn.getmousepos().winid)
    if state == nil or not valid_state(state) then
        return
    end
    if not state.config.mouse.enabled then
        return
    end
    local _, row, col = mouse_position(state.float_win)
    if row < 0 or row >= state.height or col < 1 or col > state.width then
        return
    end

    local current = build_interaction(state)
    current.pressed_row = row
    interaction = current
    if valid_window(state.float_win) then
        pcall(vim.api.nvim_set_current_win, state.float_win)
    end
    navigate(current, row_to_line(current, row))
end

M.drag = function()
    local current = interaction
    if current == nil then
        return
    end
    if not valid_window(current.float_win) then
        M.cancel()
        return
    end
    local _, row = mouse_position(current.float_win)
    row = clamp(row, 0, current.height - 1)
    current.dragging = true
    navigate(current, row_to_line(current, row))
end

M.release = function()
    local current = interaction
    if current == nil then
        return
    end
    if valid_window(current.float_win) then
        local _, row = mouse_position(current.float_win)
        row = clamp(row, 0, current.height - 1)
        navigate(current, row_to_line(current, row))
    end
    finish_interaction(current)
end

M.cancel = function()
    local current = interaction
    if current ~= nil then
        finish_interaction(current)
    end
end

---@param state ScrollbarMinimapRendererState
M.attach = function(state)
    local active = runtime
    if active == nil or not valid_state(state) then
        return
    end
    if not state.config.mouse.enabled then
        detach(active, state.float_buf)
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

---@param options? ScrollbarMinimapMouseOptions
M.setup = function(options)
    M.dispose()
    options = options or {}
    local active_renderer = options.renderer or require("scrollbar.minimap.renderer")
    local active_scheduler = options.scheduler or require("scrollbar.minimap.scheduler")
    local augroup = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
    runtime = {
        renderer = active_renderer,
        scheduler = active_scheduler,
        augroup = augroup,
        attached = {},
    }

    vim.api.nvim_create_autocmd("WinClosed", {
        group = augroup,
        callback = function(args)
            local closed = tonumber(args.match)
            local current = interaction
            if current ~= nil and (closed == current.float_win or closed == current.source_win) then
                M.cancel()
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
        finish_interaction(interaction)
    end
    runtime = nil
    active.renderer.set_state_callback(nil)
    for float_buf in pairs(active.attached) do
        detach(active, float_buf)
    end
    pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
end

---@return ScrollbarMinimapMouseInteraction?
M.get_interaction = function()
    return interaction and vim.deepcopy(interaction) or nil
end

return M
