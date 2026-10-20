--- Render scheduler shared by the scrollbar and the minimap. `new` builds one
--- instance for each renderer. Each instance has its own queue, throttle
--- timer, hide timers, and augroup, so a slow flush in one renderer does not
--- delay the other.
---
--- An instance coalesces the invalidations of source windows within
--- `throttle_ms` and renders the queued windows in one flush. The autocmd rows
--- come from the `events` option of the renderer. Provider updates arrive
--- through the store. With `autohide`, activity reveals a source window and
--- restarts its hide timer.
---
--- The functions of an instance are closures that `new` creates once, so the
--- per-event paths read upvalues and allocate nothing.

local providers = require("scrollbar.providers")
local shared_config = require("scrollbar.shared_config")
local store = require("scrollbar.store")

local M = {}

local TEXT_EVENTS = { "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }
local CURSOR_EVENTS = { "CursorMoved", "CursorMovedI" }
local NO_PEERS = {}

---@alias ScrollbarSchedulerCoreConfig ScrollbarConfig|ScrollbarMinimapConfig
---@alias ScrollbarSchedulerCoreRenderer ScrollbarSchedulerRenderer|ScrollbarMinimapSchedulerRenderer

--- Another renderer whose floats the scheduler ignores. Only the registry
--- lookups run, so the check stays cheap on the per-event paths.
---@class ScrollbarSchedulerPeer
---@field is_owned_float_buffer? fun(bufnr: integer): boolean
---@field is_owned_float_window? fun(winid: integer): boolean

---@class ScrollbarSchedulerCoreSpec
---@field augroup string Augroup name of the instance
---@field label string Text after the plugin prefix in warnings, for example "minimap "
---@field consumer "scrollbar"|"minimap" Consumer name for the provider demand
---@field on_option_set? fun() Runs on a foreign `OptionSet` before the windows are queued
---@field hub? boolean Whether the instance dispatches its text and cursor rows to subscribers
---@field api? table Module table that exports the instance. Internal calls look up their function in it, so a replaced field takes effect

---@class ScrollbarSchedulerCoreOptions
---@field config ScrollbarSchedulerCoreConfig
---@field renderer ScrollbarSchedulerCoreRenderer
---@field on_colorscheme fun()
---@field channels table<string, true> Store channels that queue windows
---@field option_pattern? string[] Pattern of the `OptionSet` row when the event has no configured pattern
---@field peers? ScrollbarSchedulerPeer[]
---@field on_text_change? fun(fn: fun(args: table), events?: string[]): boolean Text dispatch of another instance. Returns false when it is inactive, and the instance keeps its own rows

---@class ScrollbarSchedulerCoreRuntime
---@field config ScrollbarSchedulerCoreConfig
---@field renderer ScrollbarSchedulerCoreRenderer
---@field peers ScrollbarSchedulerPeer[]
---@field on_colorscheme fun()
---@field timer any
---@field timer_armed boolean
---@field dirty table<integer, true>
---@field flushing boolean
---@field augroup integer
---@field uv any
---@field text_events? table<string, boolean> Text events that have a row without a pattern for the subscribers
---@field cursor_events? table<string, boolean> Cursor events that have a row without a pattern for the subscribers
---@field hide_timers table<integer, any>
---@field hide_generations table<integer, integer>
---@field held table<integer, true>
---@field unsubscribe_store fun()

---@param spec ScrollbarSchedulerCoreSpec
---@return ScrollbarSchedulerCore
M.new = function(spec)
    local prefix = "[nvim-scrollbar] " .. spec.label
    local consumer = spec.consumer
    local on_option_set = spec.on_option_set
    local hub = spec.hub == true

    ---@class ScrollbarSchedulerCore
    local instance = {}
    local api = spec.api or instance

    ---@type ScrollbarSchedulerCoreRuntime?
    local runtime
    local timer_closed = false

    -- Text-change subscriptions: providers (e.g. marks) and the minimap
    -- scheduler can ride the TextChanged dispatch instead of registering their
    -- own augroup, so one autocmd invocation per keystroke covers scheduling
    -- and the subscribers. Only an instance with `hub` dispatches.
    ---@type fun(args: table)[]
    local text_change_subscribers = {}
    ---@type fun(args: table)[]
    local cursor_activity_subscribers = {}

    local function notify_text_change_subscribers(args)
        for _, subscriber in ipairs(text_change_subscribers) do
            local ok, err = pcall(subscriber, args)
            if not ok then
                vim.notify(prefix .. "text-change subscriber failed: " .. tostring(err), vim.log.levels.WARN)
            end
        end
    end

    local function notify_cursor_activity_subscribers(args)
        for _, subscriber in ipairs(cursor_activity_subscribers) do
            local ok, err = pcall(subscriber, args)
            if not ok then
                vim.notify(prefix .. "cursor-activity subscriber failed: " .. tostring(err), vim.log.levels.WARN)
            end
        end
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param bufnr integer
    ---@return boolean
    local function peer_buffer(current, bufnr)
        local peers = current.peers
        for index = 1, #peers do
            local owned = peers[index].is_owned_float_buffer
            if owned ~= nil and owned(bufnr) == true then
                return true
            end
        end
        return false
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    ---@return boolean
    local function peer_window(current, winid)
        local peers = current.peers
        for index = 1, #peers do
            local owned = peers[index].is_owned_float_window
            if owned ~= nil and owned(winid) == true then
                return true
            end
        end
        return false
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param bufnr integer
    ---@return boolean
    local function owned_buffer(current, bufnr)
        -- `0` is nvim's current-buffer alias (e.g. OptionSet args). Resolve it
        -- to the real buffer: during renderer float configuration the current
        -- buffer is the float buffer, which the registry covers.
        if bufnr == 0 then
            bufnr = vim.api.nvim_get_current_buf()
        end
        -- Registry-only fast path: a pure table lookup, safe because queueing
        -- an ineligible window is harmless (flush re-checks eligibility) while
        -- the registry can never claim a source resource.
        local renderer = current.renderer
        local fast = renderer.is_owned_float_buffer
        if type(fast) == "function" then
            if fast(bufnr) == true then
                return true
            end
        elseif type(renderer.is_owned_buffer) == "function" then
            local ok, owned = pcall(renderer.is_owned_buffer, bufnr)
            if ok and owned == true then
                return true
            end
        end
        return peer_buffer(current, bufnr)
    end

    --- Whether `winid` is a float of this instance's renderer.
    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    ---@return boolean
    local function own_window(current, winid)
        local renderer = current.renderer
        local fast = renderer.is_owned_float_window
        if type(fast) == "function" then
            return fast(winid) == true
        end
        if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) then
            return false
        end
        if renderer.is_owned_window == nil then
            return false
        end
        local ok, owned = pcall(renderer.is_owned_window, winid)
        return ok and owned == true
    end

    --- Whether `winid` is a float of this renderer or of a peer.
    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    ---@return boolean
    local function owned_window(current, winid)
        return own_window(current, winid) or peer_window(current, winid)
    end

    ---@param current ScrollbarSchedulerCoreRuntime
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

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    ---@return boolean
    local function is_source_window(current, winid)
        if type(current.renderer.is_source_window) ~= "function" then
            return false
        end
        local ok, selected = pcall(current.renderer.is_source_window, winid)
        return ok and selected == true
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@return boolean
    local function renderer_visible(current)
        if type(current.renderer.is_visible) ~= "function" then
            return false
        end
        local ok, visible = pcall(current.renderer.is_visible)
        return ok and visible == true
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    ---@return boolean
    local function reveal_source(current, winid)
        if type(current.renderer.reveal) ~= "function" then
            return false
        end
        local ok, revealed = pcall(current.renderer.reveal, winid)
        return ok and revealed == true
    end

    --- Clear the source selection memo of the renderer. The topology and
    --- option rows call it because buffer and window options decide which
    --- windows are sources. The cursor and text rows do not, so that the memo
    --- keeps them cheap.
    local function invalidate_source_selection()
        local current = runtime
        if current == nil then
            return
        end
        local invalidate = current.renderer.invalidate_source_selection
        if type(invalidate) == "function" then
            pcall(invalidate)
        end
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    local function stop_hide_timer(current, winid)
        local timer = current.hide_timers[winid]
        if timer ~= nil then
            pcall(timer.stop, timer)
        end
    end

    ---@param current ScrollbarSchedulerCoreRuntime
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

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    local function restart_hide_deadline(current, winid)
        if runtime ~= current or not current.config.autohide or current.held[winid] then
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
                    vim.notify(prefix .. "autohide failed: " .. tostring(err), vim.log.levels.WARN)
                end
            end)
        )
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    local function arm_timer(current)
        if runtime ~= current or current.timer_armed or current.flushing or next(current.dirty) == nil then
            return
        end

        current.timer_armed = true
        current.timer:start(
            current.config.throttle_ms,
            0,
            vim.schedule_wrap(function()
                if runtime ~= current then
                    return
                end
                current.timer_armed = false
                api.flush()
            end)
        )
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    local function queue_window(current, winid)
        current.dirty[winid] = true
        arm_timer(current)
    end

    ---@param current ScrollbarSchedulerCoreRuntime
    ---@param winid integer
    ---@return boolean
    local function activity_window(current, winid)
        if runtime ~= current or not is_source_window(current, winid) then
            return false
        end
        if current.config.autohide then
            if not renderer_visible(current) or not reveal_source(current, winid) then
                return false
            end
        end
        queue_window(current, winid)
        restart_hide_deadline(current, winid)
        return true
    end

    --- Whether an event belongs to a float of this renderer or of a peer, so
    --- the rows skip it. While the current window is a float of this renderer,
    --- every event is owned. A peer float as the current window does not own
    --- the event: a peer drag scrolls a source window, and the scroll must
    --- reach this renderer.
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
        return own_window(current, current_win)
    end

    ---@param winid integer?
    local function invalidate_event_window(winid)
        local current = runtime
        if current == nil or winid == nil or owned_window(current, winid) then
            return
        end
        api.invalidate_window(winid)
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

    ---Register `callback` for the enabled events among `events`. The events
    ---with the default pattern share one autocmd. An event with a configured
    ---pattern gets its own autocmd with that pattern.
    ---@param group integer Augroup id.
    ---@param events string[] Events this registration covers.
    ---@param enabled table<string, true|string[]> Enabled events and their configured patterns; `true` selects the default pattern.
    ---@param callback fun(args: table) Autocmd callback.
    ---@param default_pattern? string[] Pattern of the events without a configured pattern.
    local function register_group(group, events, enabled, callback, default_pattern)
        local shared = {}
        for _, event in ipairs(events) do
            local pattern = enabled[event]
            if pattern == true then
                shared[#shared + 1] = event
            elseif pattern ~= nil then
                vim.api.nvim_create_autocmd(event, { group = group, pattern = pattern, callback = callback })
            end
        end
        if #shared > 0 then
            vim.api.nvim_create_autocmd(shared, { group = group, pattern = default_pattern, callback = callback })
        end
    end

    ---@param group integer
    ---@param enabled table<string, true|string[]>
    ---@param option_pattern? string[]
    local function create_autocmds(group, enabled, option_pattern)
        local notify_text = hub and notify_text_change_subscribers or nil
        local notify_cursor = hub and notify_cursor_activity_subscribers or nil

        register_group(group, { "BufEnter", "BufWinEnter" }, enabled, function(args)
            if not event_is_owned(args) then
                invalidate_source_selection()
                api.invalidate_buffer(args.buf)
            end
        end)
        register_group(group, { "WinEnter", "TabEnter", "TermEnter", "CmdwinLeave" }, enabled, function(args)
            if not event_is_owned(args) then
                invalidate_source_selection()
                api.invalidate_all()
            end
        end)
        -- A row with a configured pattern does not notify the subscribers. A
        -- pattern must not filter what they receive, so they get an unfiltered
        -- row of their own (see `subscribe_text_change`).
        register_group(group, CURSOR_EVENTS, enabled, function(args)
            if not event_is_owned(args) then
                activity_event_window(vim.api.nvim_get_current_win())
                if notify_cursor ~= nil and enabled[args.event] == true then
                    notify_cursor(args)
                end
            end
        end)
        register_group(group, TEXT_EVENTS, enabled, function(args)
            if not event_is_owned(args) then
                if notify_text ~= nil and enabled[args.event] == true then
                    notify_text(args)
                end
                api.invalidate_buffer(args.buf)
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
            api.invalidate_all()
        end)
        register_group(group, { "OptionSet" }, enabled, function(args)
            if not event_is_owned(args) then
                if on_option_set ~= nil then
                    on_option_set()
                end
                invalidate_source_selection()
                api.invalidate_all()
            end
        end, option_pattern)
        register_group(group, { "ColorScheme" }, enabled, function()
            local current = runtime
            if current == nil then
                return
            end
            local ok, err = pcall(current.on_colorscheme)
            if not ok then
                vim.notify(prefix .. "colorscheme refresh failed: " .. tostring(err), vim.log.levels.WARN)
            end
            api.invalidate_all()
        end)
        register_group(group, { "WinClosed", "BufDelete", "BufWipeout", "TabClosed" }, enabled, function(args)
            if not event_is_owned(args) then
                api.invalidate_all()
            end
        end)
        -- A closed window releases its queue entry and hide timer even when
        -- `WinClosed` is not a configured event or its pattern does not match.
        vim.api.nvim_create_autocmd("WinClosed", {
            group = group,
            callback = function(args)
                local current = runtime
                local closed_win = tonumber(args.match)
                if current ~= nil and closed_win ~= nil then
                    current.dirty[closed_win] = nil
                    close_hide_timer(current, closed_win)
                end
            end,
        })
        -- A configured event without a dedicated handler renders every window.
        local other_events = {}
        for event in pairs(enabled) do
            if not shared_config.HANDLED_EVENTS[event] then
                other_events[#other_events + 1] = event
            end
        end
        table.sort(other_events)
        register_group(group, other_events, enabled, function(args)
            if not event_is_owned(args) then
                api.invalidate_all()
            end
        end)
    end

    --- Route the text rows through the dispatch of another instance. Its rows
    --- have no pattern, so a text event with a configured pattern keeps its
    --- own row here.
    ---@param subscribe fun(fn: fun(args: table), events?: string[]): boolean
    ---@param enabled table<string, true|string[]>
    local function ride_text_change(subscribe, enabled)
        local text_events = {}
        for _, event in ipairs(TEXT_EVENTS) do
            if enabled[event] == true then
                text_events[#text_events + 1] = event
            end
        end
        if #text_events == 0 then
            return
        end
        local text_enabled = {}
        for _, event in ipairs(text_events) do
            text_enabled[event] = true
        end
        if
            subscribe(function(args)
                -- The dispatch sends every text event of its subscribers, so
                -- skip the ones that this subscription does not cover.
                if text_enabled[args.event] and not event_is_owned(args) then
                    api.invalidate_buffer(args.buf)
                end
            end, text_events)
        then
            for _, event in ipairs(text_events) do
                enabled[event] = nil
            end
        end
    end

    ---@param options ScrollbarSchedulerCoreOptions
    instance.setup = function(options)
        api.dispose()

        local active_config = options.config
        local uv = vim.uv or vim.loop
        local timer = assert(uv.new_timer())
        local augroup = vim.api.nvim_create_augroup(spec.augroup, { clear = true })
        local channels = options.channels
        ---@type ScrollbarSchedulerCoreRuntime
        local current = {
            config = active_config,
            renderer = options.renderer,
            peers = options.peers or NO_PEERS,
            on_colorscheme = options.on_colorscheme,
            timer = timer,
            timer_armed = false,
            dirty = {},
            flushing = false,
            augroup = augroup,
            uv = uv,
            hide_timers = {},
            hide_generations = {},
            held = {},
            unsubscribe_store = function() end,
        }
        runtime = current
        current.unsubscribe_store = store.subscribe(function(event)
            if
                runtime ~= current
                or not channels[event.channel]
                or not providers._consumer_enabled(event.provider, consumer)
            then
                return
            end
            if event.scope == "buffer" then
                api.invalidate_buffer(event.target)
            else
                api.invalidate_window(event.target)
            end
        end)
        timer_closed = false
        local events_enabled = {}
        for _, event_config in ipairs(active_config.events) do
            events_enabled[event_config.event] = event_config.pattern or true
        end
        text_change_subscribers = {}
        cursor_activity_subscribers = {}
        if type(options.on_text_change) == "function" then
            ride_text_change(options.on_text_change, events_enabled)
        end
        create_autocmds(augroup, events_enabled, options.option_pattern)
        -- A pending update timer firing during nvim teardown re-enters
        -- rendering on half-torn-down state (nvim 0.13 runs scheduled Lua
        -- callbacks in proc_teardown; a redraw there crashes in
        -- grid_clear_line). Disposing on VimLeavePre stops the timer and
        -- removes this augroup first.
        vim.api.nvim_create_autocmd("VimLeavePre", {
            group = augroup,
            callback = function()
                api.dispose()
            end,
        })
        if not hub then
            return
        end
        -- Only the rows without a configured pattern notify the subscribers.
        local text_events = {}
        for _, event in ipairs(TEXT_EVENTS) do
            if events_enabled[event] == true then
                text_events[event] = true
            end
        end
        current.text_events = text_events
        local cursor_events = {}
        for _, event in ipairs(CURSOR_EVENTS) do
            if events_enabled[event] == true then
                cursor_events[event] = true
            end
        end
        current.cursor_events = cursor_events
    end

    ---@param subscribers fun(args: table)[]
    ---@param registered_key "text_events"|"cursor_events"
    ---@param notify fun(args: table)
    ---@param description string
    ---@param fn fun(args: table)
    ---@param events? string[]
    ---@return boolean
    local function subscribe(subscribers, registered_key, notify, description, fn, events)
        if type(fn) ~= "function" then
            return false
        end
        subscribers[#subscribers + 1] = fn
        local current = runtime
        if current == nil or current.augroup == nil then
            return false
        end
        local registered = current[registered_key]
        if registered == nil then
            return false
        end
        for _, event in ipairs(events or {}) do
            if not registered[event] then
                registered[event] = true
                vim.api.nvim_create_autocmd(event, {
                    group = current.augroup,
                    callback = function(args)
                        if not event_is_owned(args) then
                            notify(args)
                        end
                    end,
                    desc = description,
                })
            end
        end
        return true
    end

    ---Subscribe to the TextChanged dispatch. The callback runs on text-change
    ---events fired for non-owned buffers, before invalidation. `events` lists
    ---the event names that the subscriber needs. Each event without a row, or
    ---with a row that has a configured pattern, gets a subscriber-only row
    ---without a pattern. Returns false when the dispatch is inactive so the
    ---caller keeps its own registration.
    ---@param fn fun(args: table)
    ---@param events? string[]
    ---@return boolean
    instance.subscribe_text_change = function(fn, events)
        return subscribe(
            text_change_subscribers,
            "text_events",
            notify_text_change_subscribers,
            "Scrollbar text-change subscribers",
            fn,
            events
        )
    end

    ---Subscribe to the cursor-activity dispatch (CursorMoved(I)). The callback
    ---runs after the scheduler's own activity handling, for non-owned events.
    ---`events` lists the event names that the subscriber needs. Each event
    ---without a row, or with a row that has a configured pattern, gets a
    ---subscriber-only row without a pattern. Returns false when the dispatch
    ---is inactive so the caller keeps its own registration.
    ---@param fn fun(args: table)
    ---@param events? string[]
    ---@return boolean
    instance.subscribe_cursor_activity = function(fn, events)
        return subscribe(
            cursor_activity_subscribers,
            "cursor_events",
            notify_cursor_activity_subscribers,
            "Scrollbar cursor-activity subscribers",
            fn,
            events
        )
    end

    ---@param winid integer
    ---@return boolean
    instance.invalidate_window = function(winid)
        local current = runtime
        if current == nil or not is_source_window(current, winid) then
            return false
        end
        queue_window(current, winid)
        return true
    end

    ---@param bufnr integer
    ---@return integer
    instance.invalidate_buffer = function(bufnr)
        local current = runtime
        if current == nil or type(bufnr) ~= "number" then
            return 0
        end

        -- Enumerating raw windows showing the buffer avoids the per-window
        -- eligibility/config checks on every text change. Queueing an
        -- ineligible window is harmless: flush re-checks eligibility before
        -- rendering.
        local windows
        local enumerate = current.renderer.windows_showing_buffer
        if type(enumerate) == "function" then
            local ok, enumerated = pcall(enumerate, bufnr)
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
    instance.invalidate_all = function()
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
    instance.reveal_all = function()
        local current = runtime
        if current == nil or not current.config.autohide then
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

    instance.clear_deadlines = function()
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
    instance.hold_window = function(winid)
        local current = runtime
        if
            current == nil
            or not current.config.autohide
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
    instance.resume_window = function(winid)
        local current = runtime
        if current == nil or not current.config.autohide then
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
    instance.flush = function()
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
                    vim.notify(prefix .. "render failed: " .. tostring(err), vim.log.levels.WARN)
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
    instance.status = function()
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
            interval_ms = current and current.config.throttle_ms or nil,
        }
    end

    instance.dispose = function()
        local current = runtime
        if current == nil then
            return
        end
        current.unsubscribe_store()
        runtime = nil
        text_change_subscribers = {}
        cursor_activity_subscribers = {}
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

    return instance
end

return M
