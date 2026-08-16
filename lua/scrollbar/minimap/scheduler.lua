--- Minimap-specific scheduler. Independent of `lua/scrollbar/scheduler.lua`
--- so a stutter in one subsystem cannot delay the other. Mirrors the
--- `dirty` / `flushing` / timer coalescing model and the events-list-driven
--- autocmd registration introduced in T2.
---
--- Honors `minimap.update.events` (closed allow-list, validated by
--- `lua/scrollbar/minimap/config.lua`) and `minimap.update.interval_ms`
--- (default 50). Coalesces invalidations from mirror changes (worker
--- callbacks), viewport changes (`WinScrolled` on source windows), shared
--- store mark/span/point notifications, and eligibility changes.
---
--- Autohide hide-timer logic is engaged only when
--- `minimap.autohide.enabled = true`; otherwise the timers are not created
--- and the hold/resume API is a no-op.

local config = require("scrollbar.minimap.config")
local providers = require("scrollbar.providers")
local store = require("scrollbar.store")

local M = {}

local AUGROUP_NAME = "ScrollbarMinimapScheduler"

---@type ScrollbarMinimapSchedulerRuntime?
local runtime
local timer_closed = false

---@param current ScrollbarMinimapSchedulerRuntime
---@param bufnr integer
---@return boolean
local function owned_buffer(current, bufnr)
    -- `0` is nvim's current-buffer alias (e.g. OptionSet args); resolve to
    -- the real buffer before the registry lookup (see scrollbar/scheduler.lua).
    if bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
    end
    -- Registry-only fast path (see scrollbar/scheduler.lua notes).
    local fast = current.renderer.is_owned_float_buffer
    if type(fast) == "function" then
        return fast(bufnr) == true
    end
    if type(current.renderer.is_owned_buffer) ~= "function" then
        return false
    end
    local ok, owned = pcall(current.renderer.is_owned_buffer, bufnr)
    return ok and owned == true
end

---@param current ScrollbarMinimapSchedulerRuntime
---@param winid integer
---@return boolean
local function owned_window(current, winid)
    local fast = current.renderer.is_owned_float_window
    if type(fast) == "function" then
        return fast(winid) == true
    end
    if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) then
        return false
    end
    if current.renderer.is_owned_window == nil then
        return false
    end
    local ok, owned = pcall(current.renderer.is_owned_window, winid)
    return ok and owned == true
end

---@param current ScrollbarMinimapSchedulerRuntime
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

---@param current ScrollbarMinimapSchedulerRuntime
---@param winid integer
---@return boolean
local function is_source_window(current, winid)
    if type(current.renderer.is_source_window) ~= "function" then
        return false
    end
    local ok, selected = pcall(current.renderer.is_source_window, winid)
    return ok and selected == true
end

---@param current ScrollbarMinimapSchedulerRuntime
---@return boolean
local function renderer_visible(current)
    if type(current.renderer.is_visible) ~= "function" then
        return false
    end
    local ok, visible = pcall(current.renderer.is_visible)
    return ok and visible == true
end

---@param current ScrollbarMinimapSchedulerRuntime
---@param winid integer
---@return boolean
local function reveal_source(current, winid)
    if type(current.renderer.reveal) ~= "function" then
        return false
    end
    local ok, revealed = pcall(current.renderer.reveal, winid)
    return ok and revealed == true
end

---@param current ScrollbarMinimapSchedulerRuntime
---@param winid integer
local function stop_hide_timer(current, winid)
    local timer = current.hide_timers[winid]
    if timer ~= nil then
        pcall(timer.stop, timer)
    end
end

---@param current ScrollbarMinimapSchedulerRuntime
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

---@param current ScrollbarMinimapSchedulerRuntime
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
                vim.notify("[scrollbar.nvim] minimap autohide failed: " .. tostring(err), vim.log.levels.WARN)
            end
        end)
    )
end

---@param current ScrollbarMinimapSchedulerRuntime
local function arm_timer(current)
    if runtime ~= current or current.timer_armed or current.flushing or next(current.dirty) == nil then
        return
    end

    current.timer_armed = true
    current.timer:start(
        current.config.update.interval_ms,
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

---@param current ScrollbarMinimapSchedulerRuntime
---@param winid integer
local function queue_window(current, winid)
    current.dirty[winid] = true
    arm_timer(current)
end

---@param current ScrollbarMinimapSchedulerRuntime
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

---Filter an event list down to the events enabled in the configured update set.
---@param events string[]
---@param enabled table<string, boolean>
---@return string[]
local function filter_events(events, enabled)
    local filtered = {}
    for _, event in ipairs(events) do
        if enabled[event] then
            filtered[#filtered + 1] = event
        end
    end
    return filtered
end

---@param group integer
---@param events string[]
---@param enabled table<string, boolean>
---@param callback fun(args: table)
---@param opts? table
local function register_group(group, events, enabled, callback, opts)
    local filtered = filter_events(events, enabled)
    if #filtered == 0 then
        return
    end
    local autocmd_opts = { group = group, callback = callback }
    if opts then
        for key, value in pairs(opts) do
            autocmd_opts[key] = value
        end
    end
    vim.api.nvim_create_autocmd(filtered, autocmd_opts)
end

---@param group integer
---@param enabled table<string, boolean>
local function create_autocmds(group, enabled)
    register_group(group, { "BufEnter", "BufWinEnter" }, enabled, function(args)
        if not event_is_owned(args) then
            M.invalidate_buffer(args.buf)
        end
    end)
    register_group(group, { "WinEnter", "TabEnter", "TermEnter", "CmdwinLeave" }, enabled, function(args)
        if not event_is_owned(args) then
            M.invalidate_all()
        end
    end)
    register_group(group, { "CursorMoved", "CursorMovedI" }, enabled, function(args)
        if not event_is_owned(args) then
            activity_event_window(vim.api.nvim_get_current_win())
        end
    end)
    register_group(group, { "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }, enabled, function(args)
        if not event_is_owned(args) then
            M.invalidate_buffer(args.buf)
        end
    end)
    register_group(group, { "WinScrolled" }, enabled, function(args)
        if not event_is_owned(args) then
            activity_scrolled_windows()
        end
    end)
    register_group(group, { "WinResized" }, enabled, function(args)
        if not event_is_owned(args) then
            invalidate_resized_windows()
        end
    end)
    register_group(group, { "VimResized" }, enabled, function()
        M.invalidate_all()
    end)
    register_group(group, { "OptionSet" }, enabled, function(args)
        if not event_is_owned(args) then
            M.invalidate_all()
        end
    end)
    register_group(group, { "ColorScheme" }, enabled, function()
        local current = runtime
        if current == nil then
            return
        end
        local ok, err = pcall(current.on_colorscheme)
        if not ok then
            vim.notify("[scrollbar.nvim] minimap colorscheme refresh failed: " .. tostring(err), vim.log.levels.WARN)
        end
        M.invalidate_all()
    end)
    register_group(group, { "WinClosed" }, enabled, function(args)
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
    end)
    register_group(group, { "BufDelete", "BufWipeout", "TabClosed" }, enabled, function(args)
        if not event_is_owned(args) then
            M.invalidate_all()
        end
    end)
end

---@param options? ScrollbarMinimapSchedulerOptions
M.setup = function(options)
    M.dispose()
    options = options or {}

    local active_config = options.config or config.get()
    local active_renderer = options.renderer or require("scrollbar.minimap.renderer")
    local uv = vim.uv or vim.loop
    local timer = assert(uv.new_timer())
    local augroup = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
    local current = {
        config = active_config,
        renderer = active_renderer,
        on_colorscheme = options.on_colorscheme or function() end,
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
    runtime = current
    current.unsubscribe_store = store.subscribe(function(event)
        if
            runtime ~= current
            or (event.channel ~= "marks" and event.channel ~= "minimap_spans" and event.channel ~= "minimap_points")
            or not providers._consumer_enabled(event.provider, "minimap")
            or (event.channel == "marks" and not current.config.overlays.enabled)
        then
            return
        end
        if event.scope == "buffer" then
            M.invalidate_buffer(event.target)
        else
            M.invalidate_window(event.target)
        end
    end)
    timer_closed = false
    local events_enabled = {}
    for _, event in ipairs(active_config.update.events) do
        events_enabled[event] = true
    end
    -- Ride the scrollbar scheduler's shared TextChanged dispatch when wired:
    -- one autocmd invocation per keystroke covers both schedulers. Falls back
    -- to own registration when the hub is unavailable (standalone setups).
    if type(options.on_text_change) == "function" then
        local text_events =
            filter_events({ "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }, events_enabled)
        if
            options.on_text_change(function(args)
                if not event_is_owned(args) then
                    M.invalidate_buffer(args.buf)
                end
            end, text_events)
        then
            for _, event in ipairs(text_events) do
                events_enabled[event] = nil
            end
        end
    end
    create_autocmds(augroup, events_enabled)
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

    -- Raw window enumeration keeps the per-keystroke cost off the eligibility
    -- path; flush re-checks eligibility before rendering.
    local windows
    if type(current.renderer.windows_showing_buffer) == "function" then
        local ok, enumerated = pcall(current.renderer.windows_showing_buffer, bufnr)
        windows = ok and type(enumerated) == "table" and enumerated or source_windows(current, bufnr)
    else
        windows = source_windows(current, bufnr)
    end

    local count = 0
    for _, winid in ipairs(windows) do
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
                vim.notify("[scrollbar.nvim] minimap render failed: " .. tostring(err), vim.log.levels.WARN)
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
        interval_ms = current and current.config.update.interval_ms or nil,
    }
end

M.dispose = function()
    local current = runtime
    if current == nil then
        return
    end
    current.unsubscribe_store()
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
