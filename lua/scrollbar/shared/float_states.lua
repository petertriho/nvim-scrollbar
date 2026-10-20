--- Float states of one renderer: the registries of its floats, the source
--- windows that autohide revealed, and the visibility. A lifecycle closes a
--- float when its source window or tab page closes, or when its buffer is
--- deleted. The scrollbar renderer and the minimap renderer each build one
--- instance over their own registries, and the instance builds the source
--- policy of the renderer. Hooks release the window resources and drop the
--- caches that only one renderer has.
---
--- `new` creates the functions of an instance once as closures, so the
--- per-event paths read upvalues and allocate nothing.

local float = require("scrollbar.shared.float")
local source_policy = require("scrollbar.shared.source_policy")
local stack = require("scrollbar.shared.stack")

local M = {}

---@class ScrollbarFloatStatesOptions
---@field renderer ScrollbarStackRenderer Name of the renderer in `scrollbar.shared.stack`
---@field config ScrollbarSourcePolicyConfigModule Read at call time, so a replaced function applies at once
---@field owned_var string Window and buffer variable that marks a float of this renderer, also from an earlier setup
---@field augroup string Name of the lifecycle augroup
---@field tuning ScrollbarSourcePolicyTuning Table whose interval fields override the memo lifetimes
---@field states table<integer, ScrollbarFloatState> Live floats, keyed by source window
---@field states_by_float table<integer, ScrollbarFloatState> Live floats, keyed by float window
---@field owned_float_buffers table<integer, boolean> Live float buffers
---@field retained? table<integer, any> Window resources other than the float, keyed by source window
---@field release? fun(source_win: integer) Free the `retained` resources of a source window
---@field forget? fun(source_win: integer, state?: ScrollbarFloatState) Drop the render caches of a source window. `state` is its closed float, or nil when the window has no float
---@field forget_buffer? fun(bufnr: integer) Drop the render caches of a deleted buffer

---@param windows table<integer, any> Table keyed by source window
---@param selected table<integer, true>
---@param stale table<integer, true>
local function mark_stale(windows, selected, stale)
    for source_win in pairs(windows) do
        if not selected[source_win] then
            stale[source_win] = true
        end
    end
end

---@param options ScrollbarFloatStatesOptions
---@return ScrollbarFloatStates
M.new = function(options)
    local renderer = options.renderer
    local config = options.config
    local augroup = options.augroup
    local states = options.states
    local states_by_float = options.states_by_float
    local owned_float_buffers = options.owned_float_buffers
    local retained = options.retained
    local release = options.release
    local forget = options.forget
    local forget_buffer = options.forget_buffer

    -- Buffer of each source window at the time autohide revealed it.
    ---@type table<integer, integer>
    local revealed = {}
    local visible = false

    ---@type integer?
    local lifecycle_group

    ---@type fun(state: ScrollbarFloatState)?
    local state_callback

    -- The lifecycle code below defines this function. The source policy
    -- releases stale source windows through it.
    local close_source

    local policy = source_policy.new({
        config = config,
        owned_var = options.owned_var,
        states_by_float = states_by_float,
        owned_float_buffers = owned_float_buffers,
        tuning = options.tuning,
        collect_stale = function(selected, stale)
            mark_stale(states, selected, stale)
            mark_stale(revealed, selected, stale)
            if retained ~= nil then
                mark_stale(retained, selected, stale)
            end
            for _, source_win in ipairs(stack.windows(renderer)) do
                if not selected[source_win] then
                    stale[source_win] = true
                end
            end
        end,
        close_source = function(source_win)
            close_source(source_win)
        end,
    })

    local valid_window = policy.valid_window
    local invalidate = policy.invalidate
    local active_source_window = policy.active_source_window
    local source_selection = policy.source_selection
    local buffer_eligible = policy.buffer_eligible

    ---@param state ScrollbarFloatState
    ---@param retain_cache? boolean Keep the render caches, for a short hide
    local function close_state(state, retain_cache)
        local source_win = state.source_win
        states[source_win] = nil
        states_by_float[state.float_win] = nil
        owned_float_buffers[state.float_buf] = nil
        revealed[source_win] = nil
        if not retain_cache then
            invalidate(source_win)
            if forget ~= nil then
                forget(source_win, state)
            end
        end
        float.close(state.float_win, state.float_buf)
        if release ~= nil then
            release(source_win)
        end
    end

    ---Release a source window that has no float.
    ---@param source_win integer
    local function release_source(source_win)
        revealed[source_win] = nil
        invalidate(source_win)
        if forget ~= nil then
            forget(source_win)
        end
        if release ~= nil then
            release(source_win)
        end
    end

    ---@param source_win integer
    close_source = function(source_win)
        local state = states[source_win]
        if state ~= nil then
            close_state(state)
        else
            release_source(source_win)
        end
        stack.publish(renderer, source_win, nil)
    end

    --- Autohide is a short hide: the footprint stays, so the float of the other
    --- renderer beside it keeps its position.
    ---@param source_win integer
    local function conceal_source(source_win)
        revealed[source_win] = nil
        local state = states[source_win]
        if state ~= nil then
            close_state(state, true)
        elseif release ~= nil then
            release(source_win)
        end
    end

    local function close_all()
        local pending = {}
        for _, state in pairs(states) do
            table.insert(pending, state)
        end
        for _, state in ipairs(pending) do
            close_state(state)
        end
        if retained ~= nil and release ~= nil then
            local windows = {}
            for source_win in pairs(retained) do
                windows[#windows + 1] = source_win
            end
            for _, source_win in ipairs(windows) do
                release(source_win)
            end
        end
        stack.clear(renderer)
    end

    local function sweep_states()
        local pending = {}
        for _, state in pairs(states) do
            if
                not valid_window(state.source_win)
                or not valid_window(state.float_win)
                or not vim.api.nvim_buf_is_valid(state.source_buf)
                or not vim.api.nvim_buf_is_valid(state.float_buf)
                or vim.api.nvim_win_get_buf(state.source_win) ~= state.source_buf
            then
                table.insert(pending, state)
            end
        end
        for _, state in ipairs(pending) do
            close_state(state)
            stack.publish(renderer, state.source_win, nil, { notify = valid_window(state.source_win) })
        end
    end

    ---@param args { match: string }
    local function close_window(args)
        local closed_win = tonumber(args.match)
        if closed_win == nil then
            return
        end
        local state = states[closed_win] or states_by_float[closed_win]
        if state ~= nil then
            close_state(state)
        else
            release_source(closed_win)
        end
        -- A closing source window takes the float of the other renderer with
        -- it, so only a closed float of this renderer moves the other float.
        local source_win = state and state.source_win or closed_win
        stack.publish(renderer, source_win, nil, { notify = source_win ~= closed_win })
    end

    ---@param args { buf: integer }
    local function close_buffer(args)
        local bufnr = args.buf
        local pending = {}
        for _, state in pairs(states) do
            if state.source_buf == bufnr or state.float_buf == bufnr then
                table.insert(pending, state)
            end
        end
        for _, state in ipairs(pending) do
            close_state(state)
            stack.publish(renderer, state.source_win, nil)
        end
        if forget_buffer ~= nil then
            forget_buffer(bufnr)
        end
    end

    ---Start the render of a source window. If the window shows a different
    ---buffer than its float, close the float. If autohide is on and the window
    ---is not revealed, conceal the window.
    ---@param source_win integer
    ---@param source_buf integer Buffer that the source window shows
    ---@param autohide false|ScrollbarAutohideConfig
    ---@return ScrollbarFloatState? state Float that shows `source_buf`, if any
    ---@return boolean concealed
    local function prepare_source(source_win, source_buf, autohide)
        ---@type ScrollbarFloatState?
        local state = states[source_win]
        if state ~= nil and state.source_buf ~= source_buf then
            close_state(state)
            state = nil
        end
        if autohide and revealed[source_win] ~= source_buf then
            conceal_source(source_win)
            return nil, true
        end
        return state, false
    end

    ---Render a source window with its selected variant. If no variant is
    ---selected, close the float of the window. A failed render also closes the
    ---float of the window.
    ---The state callback gets each float that `render_source` returns.
    ---@generic State
    ---@param source_win integer
    ---@param selection? table
    ---@param root_config table
    ---@param render_source fun(source_win: integer, selection: table, root_config: table): State?
    ---@return State?
    local function render_selection(source_win, selection, root_config, render_source)
        if selection == nil then
            close_source(source_win)
            return nil
        end
        local ok, state = pcall(render_source, source_win, selection, root_config)
        if not ok then
            close_source(source_win)
            return nil
        end
        if state ~= nil and state_callback ~= nil then
            pcall(state_callback, state)
        end
        return state
    end

    ---@param callback? fun(state: ScrollbarFloatState)
    local function set_state_callback(callback)
        state_callback = callback
        if callback == nil then
            return
        end
        for _, state in pairs(states) do
            pcall(callback, state)
        end
    end

    ---@param source_win integer
    ---@return ScrollbarFloatState?
    local function get_state(source_win)
        return states[source_win]
    end

    ---@param float_win integer
    ---@return ScrollbarFloatState?
    local function get_state_by_float(float_win)
        return states_by_float[float_win]
    end

    ---@param source_win integer
    ---@return boolean
    local function reveal(source_win)
        local root_config = config.get()
        if not visible or source_selection(source_win, root_config, active_source_window()) == nil then
            return false
        end
        if root_config.autohide then
            revealed[source_win] = vim.api.nvim_win_get_buf(source_win)
        end
        return true
    end

    ---@param source_win integer
    ---@return boolean
    local function conceal(source_win)
        if not config.get().autohide then
            return false
        end
        local was_revealed = revealed[source_win] ~= nil or states[source_win] ~= nil
        conceal_source(source_win)
        return was_revealed
    end

    --- Registry-only ownership checks. They recognize only the floats of the
    --- current setup. The variable fallbacks of `owned_window` and
    --- `owned_buffer` also find the orphans of an earlier setup, which only the
    --- setup sweep needs. The scheduler treats a missed orphan as a usual
    --- source resource, and its flush checks the eligibility again. So the
    --- cheap checks are safe on the per-keystroke path.
    ---@param winid integer
    ---@return boolean
    local function is_owned_float_window(winid)
        return states_by_float[winid] ~= nil
    end

    ---@param bufnr integer
    ---@return boolean
    local function is_owned_float_buffer(bufnr)
        return owned_float_buffers[bufnr] == true
    end

    ---@param bufnr integer
    ---@return boolean
    local function is_buffer_eligible(bufnr)
        return buffer_eligible(bufnr, config.get())
    end

    ---@return boolean
    local function is_visible()
        return visible
    end

    ---@param value boolean
    local function set_visible(value)
        visible = value
    end

    ---Hide the floats until the renderer shows again. Close every float and
    ---forget the revealed windows.
    local function hide()
        visible = false
        revealed = {}
        close_all()
    end

    ---Set the visibility and create the lifecycle autocmds.
    ---@param value boolean Whether the floats show
    ---@return integer group Lifecycle augroup, for the other autocmds of the renderer
    local function setup(value)
        visible = value
        lifecycle_group = vim.api.nvim_create_augroup(augroup, { clear = true })
        vim.api.nvim_create_autocmd("WinClosed", {
            group = lifecycle_group,
            callback = close_window,
        })
        vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
            group = lifecycle_group,
            callback = close_buffer,
        })
        vim.api.nvim_create_autocmd("TabClosed", {
            group = lifecycle_group,
            callback = sweep_states,
        })
        return lifecycle_group
    end

    ---Close every float and delete the lifecycle autocmds.
    local function dispose()
        hide()
        if lifecycle_group ~= nil then
            pcall(vim.api.nvim_del_augroup_by_id, lifecycle_group)
            lifecycle_group = nil
        end
    end

    ---@class ScrollbarFloatStates
    local instance = {
        policy = policy,
        close_state = close_state,
        close_source = close_source,
        close_all = close_all,
        prepare_source = prepare_source,
        render_selection = render_selection,
        set_state_callback = set_state_callback,
        get_state = get_state,
        get_state_by_float = get_state_by_float,
        reveal = reveal,
        conceal = conceal,
        is_owned_float_window = is_owned_float_window,
        is_owned_float_buffer = is_owned_float_buffer,
        is_buffer_eligible = is_buffer_eligible,
        is_visible = is_visible,
        set_visible = set_visible,
        hide = hide,
        setup = setup,
        dispose = dispose,
    }
    return instance
end

return M
