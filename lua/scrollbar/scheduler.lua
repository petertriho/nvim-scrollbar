local config = require("scrollbar.config")

local M = {}

local AUGROUP_NAME = "ScrollbarScheduler"
local OPTION_PATTERNS = {
    "ambiwidth",
    "breakindent",
    "cmdheight",
    "concealcursor",
    "conceallevel",
    "diff",
    "display",
    "foldcolumn",
    "foldenable",
    "foldlevel",
    "foldmethod",
    "laststatus",
    "linebreak",
    "list",
    "listchars",
    "number",
    "relativenumber",
    "showbreak",
    "showtabline",
    "signcolumn",
    "smoothscroll",
    "statusline",
    "tabstop",
    "winbar",
    "wrap",
}

---@type ScrollbarSchedulerRuntime?
local runtime
local timer_closed = false

---@param current ScrollbarSchedulerRuntime
---@param bufnr integer
---@return boolean
local function owned_buffer(current, bufnr)
    if type(current.renderer.is_owned_buffer) ~= "function" then
        return false
    end
    local ok, owned = pcall(current.renderer.is_owned_buffer, bufnr)
    return ok and owned == true
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
---@return boolean
local function owned_window(current, winid)
    if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) then
        return false
    end
    if current.renderer.is_owned_window == nil then
        return false
    end
    local ok, owned = pcall(current.renderer.is_owned_window, winid)
    return ok and owned == true
end

---@param current ScrollbarSchedulerRuntime
---@param bufnr? integer
---@return integer[]
local function source_windows(current, bufnr)
    local ok, windows = pcall(current.renderer.source_windows, bufnr)
    if not ok or type(windows) ~= "table" then
        return {}
    end

    local result = {}
    local seen = {}
    for _, winid in ipairs(windows) do
        if type(winid) == "number" and not seen[winid] then
            seen[winid] = true
            table.insert(result, winid)
        end
    end
    table.sort(result)
    return result
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
---@return boolean
local function is_source_window(current, winid)
    if type(current.renderer.is_source_window) ~= "function" then
        return false
    end
    local ok, selected = pcall(current.renderer.is_source_window, winid)
    return ok and selected == true
end

---@param current ScrollbarSchedulerRuntime
---@return boolean
local function renderer_visible(current)
    if type(current.renderer.is_visible) ~= "function" then
        return false
    end
    local ok, visible = pcall(current.renderer.is_visible)
    return ok and visible == true
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
---@return boolean
local function reveal_source(current, winid)
    if type(current.renderer.reveal) ~= "function" then
        return false
    end
    local ok, revealed = pcall(current.renderer.reveal, winid)
    return ok and revealed == true
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
local function stop_hide_timer(current, winid)
    local timer = current.hide_timers[winid]
    if timer ~= nil then
        pcall(timer.stop, timer)
    end
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
local function close_hide_timer(current, winid)
    current.hide_generations[winid] = (current.hide_generations[winid] or 0) + 1
    current.held[winid] = nil
    local timer = current.hide_timers[winid]
    current.hide_timers[winid] = nil
    if timer == nil then
        return
    end
    pcall(timer.stop, timer)
    local ok, closing = pcall(timer.is_closing, timer)
    if not ok or not closing then
        pcall(timer.close, timer)
    end
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
local function restart_hide_deadline(current, winid)
    if runtime ~= current or not current.config.autohide.enabled or current.held[winid] then
        return
    end

    local timer = current.hide_timers[winid]
    if timer == nil then
        timer = assert(current.uv.new_timer())
        current.hide_timers[winid] = timer
    end
    local generation = (current.hide_generations[winid] or 0) + 1
    current.hide_generations[winid] = generation
    pcall(timer.stop, timer)
    timer:start(
        current.config.autohide.delay_ms,
        0,
        vim.schedule_wrap(function()
            if
                runtime ~= current
                or current.hide_generations[winid] ~= generation
                or current.held[winid]
                or not renderer_visible(current)
                or not is_source_window(current, winid)
            then
                return
            end
            if type(current.renderer.conceal) ~= "function" then
                return
            end
            local ok, err = pcall(current.renderer.conceal, winid)
            if not ok then
                vim.notify("[scrollbar.nvim] autohide failed: " .. tostring(err), vim.log.levels.WARN)
            end
        end)
    )
end

---@param current ScrollbarSchedulerRuntime
local function arm_timer(current)
    if runtime ~= current or current.timer_armed or current.flushing or next(current.dirty) == nil then
        return
    end

    current.timer_armed = true
    current.timer:start(
        current.config.render.interval_ms,
        0,
        vim.schedule_wrap(function()
            if runtime ~= current then
                return
            end
            current.timer_armed = false
            M.flush()
        end)
    )
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
local function queue_window(current, winid)
    current.dirty[winid] = true
    arm_timer(current)
end

---@param current ScrollbarSchedulerRuntime
---@param winid integer
---@return boolean
local function activity_window(current, winid)
    if runtime ~= current or not is_source_window(current, winid) then
        return false
    end
    if current.config.autohide.enabled then
        if not renderer_visible(current) or not reveal_source(current, winid) then
            return false
        end
    end
    queue_window(current, winid)
    restart_hide_deadline(current, winid)
    return true
end

---@param args table
---@return boolean
local function event_is_owned(args)
    local current = runtime
    if current == nil then
        return true
    end
    local current_win = vim.api.nvim_get_current_win()
    if owned_buffer(current, args.buf) then
        local ok, current_buf = pcall(vim.api.nvim_win_get_buf, current_win)
        if ok and current_buf == args.buf and not owned_window(current, current_win) then
            local config_ok, window_config = pcall(vim.api.nvim_win_get_config, current_win)
            if config_ok and window_config.relative == "" then
                return false
            end
        end
        return true
    end
    return owned_window(current, current_win)
end

---@param winid integer?
local function invalidate_event_window(winid)
    local current = runtime
    if current == nil or winid == nil or owned_window(current, winid) then
        return
    end
    M.invalidate_window(winid)
end

---@param winid integer?
local function activity_event_window(winid)
    local current = runtime
    if current == nil or winid == nil or owned_window(current, winid) then
        return
    end
    activity_window(current, winid)
end

local function activity_scrolled_windows()
    local current = runtime
    if current == nil then
        return
    end
    local event = vim.v.event or {}
    if event.all == true or event.all == 1 then
        for _, winid in ipairs(source_windows(current)) do
            activity_window(current, winid)
        end
        return
    end

    local found = false
    for key in pairs(event) do
        local winid = tonumber(key)
        if winid ~= nil then
            found = true
            activity_event_window(winid)
        end
    end
    if not found then
        activity_event_window(vim.api.nvim_get_current_win())
    end
end

local function invalidate_resized_windows()
    local event = vim.v.event or {}
    local windows = event.windows
    if type(windows) ~= "table" or #windows == 0 then
        invalidate_event_window(vim.api.nvim_get_current_win())
        return
    end
    for _, winid in ipairs(windows) do
        invalidate_event_window(tonumber(winid))
    end
end

---@param group integer
local function create_autocmds(group)
    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group = group,
        callback = function(args)
            if not event_is_owned(args) then
                M.invalidate_buffer(args.buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "WinEnter", "TabEnter", "TermEnter", "CmdwinLeave" }, {
        group = group,
        callback = function(args)
            if not event_is_owned(args) then
                M.invalidate_all()
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        group = group,
        callback = function(args)
            if not event_is_owned(args) then
                activity_event_window(vim.api.nvim_get_current_win())
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }, {
        group = group,
        callback = function(args)
            if not event_is_owned(args) then
                M.invalidate_buffer(args.buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinScrolled", {
        group = group,
        callback = function(args)
            if not event_is_owned(args) then
                activity_scrolled_windows()
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinResized", {
        group = group,
        callback = function(args)
            if not event_is_owned(args) then
                invalidate_resized_windows()
            end
        end,
    })
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = M.invalidate_all,
    })
    vim.api.nvim_create_autocmd("OptionSet", {
        group = group,
        pattern = OPTION_PATTERNS,
        callback = function(args)
            if not event_is_owned(args) then
                M.invalidate_all()
            end
        end,
    })
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = function()
            local current = runtime
            if current == nil then
                return
            end
            local ok, err = pcall(current.on_colorscheme)
            if not ok then
                vim.notify("[scrollbar.nvim] colorscheme refresh failed: " .. tostring(err), vim.log.levels.WARN)
            end
            M.invalidate_all()
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            local current = runtime
            if current == nil then
                return
            end
            local closed_win = tonumber(args.match)
            if closed_win ~= nil then
                current.dirty[closed_win] = nil
                close_hide_timer(current, closed_win)
            end
            if not event_is_owned(args) then
                M.invalidate_all()
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout", "TabClosed" }, {
        group = group,
        callback = function(args)
            if not event_is_owned(args) then
                M.invalidate_all()
            end
        end,
    })
end

---@param options? ScrollbarSchedulerOptions
M.setup = function(options)
    M.dispose()
    options = options or {}

    local active_config = options.config or config.get()
    local active_renderer = options.renderer or require("scrollbar.renderer")
    local uv = vim.uv or vim.loop
    local timer = assert(uv.new_timer())
    local augroup = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
    runtime = {
        config = active_config,
        renderer = active_renderer,
        on_colorscheme = options.on_colorscheme or function()
            if active_config.set_highlights then
                require("scrollbar.utils").set_highlights()
            end
        end,
        timer = timer,
        timer_armed = false,
        dirty = {},
        flushing = false,
        augroup = augroup,
        uv = uv,
        hide_timers = {},
        hide_generations = {},
        held = {},
    }
    timer_closed = false
    create_autocmds(augroup)
end

---@param winid integer
---@return boolean
M.invalidate_window = function(winid)
    local current = runtime
    if current == nil or not is_source_window(current, winid) then
        return false
    end
    queue_window(current, winid)
    return true
end

---@param bufnr integer
---@return integer
M.invalidate_buffer = function(bufnr)
    local current = runtime
    if current == nil or type(bufnr) ~= "number" then
        return 0
    end

    local count = 0
    for _, winid in ipairs(source_windows(current, bufnr)) do
        if not current.dirty[winid] then
            count = count + 1
        end
        queue_window(current, winid)
    end
    return count
end

---@return integer
M.invalidate_all = function()
    local current = runtime
    if current == nil then
        return 0
    end

    local count = 0
    for _, winid in ipairs(source_windows(current)) do
        if not current.dirty[winid] then
            count = count + 1
        end
        queue_window(current, winid)
    end
    return count
end

---@return integer
M.reveal_all = function()
    local current = runtime
    if current == nil or not current.config.autohide.enabled then
        return 0
    end

    local count = 0
    for _, winid in ipairs(source_windows(current)) do
        if activity_window(current, winid) then
            count = count + 1
        end
    end
    return count
end

M.clear_deadlines = function()
    local current = runtime
    if current == nil then
        return
    end
    for winid in pairs(current.hide_timers) do
        current.hide_generations[winid] = (current.hide_generations[winid] or 0) + 1
        stop_hide_timer(current, winid)
    end
    current.held = {}
end

---@param winid integer
---@return boolean
M.hold_window = function(winid)
    local current = runtime
    if
        current == nil
        or not current.config.autohide.enabled
        or not renderer_visible(current)
        or not is_source_window(current, winid)
    then
        return false
    end
    current.held[winid] = true
    current.hide_generations[winid] = (current.hide_generations[winid] or 0) + 1
    stop_hide_timer(current, winid)
    return true
end

---@param winid integer
---@return boolean
M.resume_window = function(winid)
    local current = runtime
    if current == nil or not current.config.autohide.enabled then
        return false
    end
    current.held[winid] = nil
    if not renderer_visible(current) or not is_source_window(current, winid) then
        return false
    end
    restart_hide_deadline(current, winid)
    return true
end

---@return boolean
M.flush = function()
    local current = runtime
    if current == nil or current.flushing then
        return false
    end

    if current.timer_armed then
        current.timer:stop()
        current.timer_armed = false
    end
    if next(current.dirty) == nil then
        return false
    end

    local pending = current.dirty
    current.dirty = {}
    current.flushing = true

    local windows = {}
    for winid in pairs(pending) do
        table.insert(windows, winid)
    end
    table.sort(windows)
    local eligible = {}
    for _, winid in ipairs(source_windows(current)) do
        eligible[winid] = true
    end
    for _, winid in ipairs(windows) do
        if runtime ~= current then
            break
        end
        if eligible[winid] then
            local ok, err = pcall(current.renderer.render, winid)
            if not ok then
                vim.notify("[scrollbar.nvim] render failed: " .. tostring(err), vim.log.levels.WARN)
            end
        end
    end

    current.flushing = false
    if runtime == current then
        arm_timer(current)
    end
    return true
end

---@return ScrollbarSchedulerStatus
M.status = function()
    local current = runtime
    local dirty_windows = {}
    if current ~= nil then
        for winid in pairs(current.dirty) do
            table.insert(dirty_windows, winid)
        end
        table.sort(dirty_windows)
    end
    return {
        setup = current ~= nil,
        timer_active = current ~= nil and current.timer_armed or false,
        timer_closed = timer_closed,
        flushing = current ~= nil and current.flushing or false,
        dirty_windows = dirty_windows,
        augroup_id = current and current.augroup or nil,
        interval_ms = current and current.config.render.interval_ms or nil,
    }
end

M.dispose = function()
    local current = runtime
    if current == nil then
        return
    end
    runtime = nil
    current.dirty = {}
    current.timer_armed = false
    local hide_windows = {}
    for winid in pairs(current.hide_timers) do
        table.insert(hide_windows, winid)
    end
    for _, winid in ipairs(hide_windows) do
        close_hide_timer(current, winid)
    end
    pcall(current.timer.stop, current.timer)
    if not current.timer:is_closing() then
        current.timer:close()
    end
    timer_closed = true
    pcall(vim.api.nvim_del_augroup_by_id, current.augroup)
end

return M
