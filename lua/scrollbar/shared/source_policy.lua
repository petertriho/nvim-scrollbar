--- Source-window policy of one renderer. The policy tells which windows and
--- buffers the renderer owns and which windows are eligible sources. It also
--- gives the selected configuration variant of a source window and the set of
--- source windows. The scrollbar renderer and the minimap renderer each build one policy over
--- their own configuration module and float registries.
---
--- Each source window has a kind. A normal window has the kind `"normal"`. A
--- floating window is a source only when the `floats` option of the block
--- admits it: a built-in picker kind with its toggle on, or another float that
--- the `when` matcher accepts (kind `"custom"`). The floats of both renderers
--- and external windows are never sources.
---
--- The exported predicates serve hot event paths (provider collect and
--- publish re-checks, scheduler activity) that run several times per
--- keystroke, so they keep a short memo. Render paths call `source_selection`
--- directly, so profile `match` rules stay dynamic per render and a stale
--- window reconciles on the next flush.

local float_kinds = require("scrollbar.shared.float_kinds")
local snacks_list = require("scrollbar.floats.snacks")

local M = {}

-- Window variables that mark the floats of both renderers, also from an
-- earlier setup. A float of the other renderer is never a source.
local RENDERER_VARS = { "scrollbar_owned", "scrollbar_minimap_owned" }

-- The picker group when floats are off. It is shared, so callers never change
-- it.
local NO_GROUP = {}

-- The eligibility of a normal window (window normality and buffer
-- eligibility) costs about 2 µs. Its inputs are the window, the buffer and its
-- line count (`max_lines`), and the static root excludes, never the profile
-- matchers. A float also reads the picker state or calls `floats.when`. The
-- memo keeps the kind of the window. The schedulers clear the memo on topology
-- and option events. For standalone use, the TTL bounds the staleness of a
-- filetype or buftype change, and of a change of the picker state.
local ELIGIBILITY_TTL_MS = 50

-- A full selection also resolves `config.select` and the active source
-- (about 5 µs). Editor-relative placement makes the result depend on focus, so
-- the active source is part of the key. The picker group rule of
-- `visibility = "active"` depends on the current window, so it is part of the
-- key too.
local SOURCE_SELECTION_TTL_MS = 50

---@class ScrollbarSourcePolicyConfigModule
---@field get fun(): table Root configuration with `enabled`, `exclude`, `max_lines`, `visibility`, and `floats`
---@field select fun(source_win: integer, kind?: ScrollbarSourceKind): table Selection with `config` and `variant_id`

---@class ScrollbarSourcePolicyTuning
---@field eligibility_interval_ms? integer Memo lifetime of the eligibility and the kind of a window
---@field source_selection_interval_ms? integer Memo lifetime of `is_source_window` and of the picker group

---@class ScrollbarSourcePolicyOptions
---@field label string Name of the block in notifications, such as `"scrollbar"`
---@field config ScrollbarSourcePolicyConfigModule Read at call time, so a replaced function applies at once
---@field owned_var string Window and buffer variable that marks a float of this renderer, also from an earlier setup
---@field states_by_float table<integer, { source_win: integer }> Live floats of this renderer, keyed by float window
---@field owned_float_buffers table<integer, boolean> Live float buffers of this renderer
---@field tuning ScrollbarSourcePolicyTuning Table whose interval fields override the memo lifetimes
---@field collect_stale fun(selected: table<integer, true>, stale: table<integer, true>) Mark each retained source window that is not in `selected`
---@field close_source fun(source_win: integer) Release the resources of a stale source window

---@class ScrollbarSourcePolicy
---@field valid_window fun(winid: integer): boolean
---@field owned_window fun(winid: integer): boolean
---@field owned_buffer fun(bufnr: integer): boolean
---@field normal_window fun(winid: integer): boolean
---@field buffer_eligible fun(bufnr: integer, root_config: table, line_count?: integer): boolean
---@field basic_eligible fun(source_win: integer, root_config: table): boolean
---@field source_kind fun(winid: integer): ScrollbarSourceKind? Kind of an eligible source window, memoized like `is_source_window`
---@field active_source_window fun(): integer?
---@field active_windows fun(active_source?: integer): table<integer, true> Windows that `visibility = "active"` shows
---@field source_selection fun(source_win: integer, root_config: table, active_source?: integer, kind?: ScrollbarSourceKind|false): table?
---@field is_source_window fun(winid: integer): boolean
---@field invalidate fun(source_win?: integer)
---@field source_windows fun(bufnr?: integer): integer[]
---@field windows_showing_buffer fun(bufnr: integer): integer[]

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

M.valid_window = valid_window

---@param bufnr integer
---@return integer[]
local function windows_showing_buffer(bufnr)
    if type(bufnr) ~= "number" then
        return {}
    end
    local windows = {}
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local ok, shown = pcall(vim.api.nvim_win_get_buf, winid)
        if ok and shown == bufnr then
            windows[#windows + 1] = winid
        end
    end
    return windows
end

---@param options ScrollbarSourcePolicyOptions
---@return ScrollbarSourcePolicy
M.new = function(options)
    local label = options.label
    local config = options.config
    local owned_var = options.owned_var
    local states_by_float = options.states_by_float
    local owned_float_buffers = options.owned_float_buffers
    local tuning = options.tuning
    local collect_stale = options.collect_stale
    local close_source = options.close_source

    local eligibility_cache = {}
    local selection_cache = {}
    -- Picker windows of the current window, for `visibility = "active"`.
    ---@type { current: integer, at: integer, members: table<integer, true> }?
    local group_cache = nil
    -- Messages of failed `floats.when` calls that were notified, for the root
    -- configuration in `notified_root`.
    local notified = {}
    local notified_root = nil

    ---@param winid integer
    ---@return boolean
    local function owned_window(winid)
        if states_by_float[winid] ~= nil then
            return true
        end
        if not valid_window(winid) then
            return false
        end
        -- `vim.w` returns nil for a missing variable instead of raising an
        -- error, so the lookup stays off the error path.
        return vim.w[winid][owned_var] == true
    end

    ---@param bufnr integer
    ---@return boolean
    local function owned_buffer(bufnr)
        if owned_float_buffers[bufnr] then
            return true
        end
        if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
            return false
        end
        return vim.b[bufnr][owned_var] == true
    end

    ---@param winid integer
    ---@return boolean
    local function normal_window(winid)
        if not valid_window(winid) then
            return false
        end
        -- Every float of both renderers is a floating window, so a window that
        -- is not floating needs no ownership lookup.
        local ok, window_config = pcall(vim.api.nvim_win_get_config, winid)
        return ok and window_config.relative == ""
    end

    ---@param when fun(context: ScrollbarFloatContext): boolean
    ---@param winid integer
    ---@param window_config vim.api.keyset.win_config
    ---@param root_config table
    ---@return boolean
    local function when_matches(when, winid, window_config, root_config)
        local bufnr = vim.api.nvim_win_get_buf(winid)
        local ok, matched = pcall(when, {
            winid = winid,
            bufnr = bufnr,
            filetype = vim.bo[bufnr].filetype,
            buftype = vim.bo[bufnr].buftype,
            bufname = vim.api.nvim_buf_get_name(bufnr),
            config = window_config,
        })
        if ok then
            return matched and true or false
        end
        if notified_root ~= root_config then
            notified = {}
            notified_root = root_config
        end
        local message = tostring(matched)
        if not notified[message] then
            notified[message] = true
            vim.notify(
                string.format("[nvim-scrollbar] %s floats.when matcher failed: %s", label, message),
                vim.log.levels.ERROR
            )
        end
        return false
    end

    ---The kind of a floating window, or nil when it is not a source.
    ---@param winid integer
    ---@param window_config vim.api.keyset.win_config
    ---@param root_config table
    ---@return ScrollbarFloatKind?
    local function float_kind(winid, window_config, root_config)
        local floats = root_config.floats
        if floats == nil or not floats.enabled or window_config.external or owned_window(winid) then
            return nil
        end
        local variables = vim.w[winid]
        for _, name in ipairs(RENDERER_VARS) do
            if variables[name] == true then
                return nil
            end
        end
        -- Only the toggles decide a picker window, so `when` sees only the
        -- other floats.
        local kind = float_kinds.kind(winid)
        if kind ~= nil then
            return floats.kinds[kind] and kind or nil
        end
        if floats.when == false or not when_matches(floats.when, winid, window_config, root_config) then
            return nil
        end
        return "custom"
    end

    ---@param winid integer
    ---@param root_config table
    ---@return ScrollbarSourceKind?
    local function window_kind(winid, root_config)
        if not valid_window(winid) then
            return nil
        end
        local ok, window_config = pcall(vim.api.nvim_win_get_config, winid)
        if not ok then
            return nil
        end
        if window_config.relative == "" then
            return "normal"
        end
        return float_kind(winid, window_config, root_config)
    end

    ---@param bufnr integer
    ---@param root_config table
    ---@param line_count? integer Lines to compare with `max_lines`. Defaults to the line count of the buffer
    ---@return boolean
    local function buffer_eligible(bufnr, root_config, line_count)
        if
            not root_config.enabled
            or type(bufnr) ~= "number"
            or not vim.api.nvim_buf_is_valid(bufnr)
            or not vim.api.nvim_buf_is_loaded(bufnr)
            or owned_buffer(bufnr)
        then
            return false
        end

        if root_config.exclude.buftypes[vim.bo[bufnr].buftype] then
            return false
        end
        if root_config.exclude.filetypes[vim.bo[bufnr].filetype] then
            return false
        end

        if root_config.max_lines == false then
            return true
        end
        return (line_count or vim.api.nvim_buf_line_count(bufnr)) <= root_config.max_lines
    end

    ---The kind of an eligible source window, or nil.
    ---@param source_win integer
    ---@param root_config table
    ---@return ScrollbarSourceKind?
    local function eligible_kind(source_win, root_config)
        local kind = window_kind(source_win, root_config)
        if kind == nil then
            return nil
        end
        local line_count = nil
        if kind == "snacks_list" then
            -- The list buffer holds only the visible rows, so `max_lines`
            -- counts the items. A list that the adapter cannot read is not a
            -- source: a wrong bar is worse than no bar.
            local view = snacks_list.view(source_win)
            if view == nil then
                return nil
            end
            line_count = view.count
        end
        if not buffer_eligible(vim.api.nvim_win_get_buf(source_win), root_config, line_count) then
            return nil
        end
        return kind
    end

    ---@param source_win integer
    ---@param root_config table
    ---@return boolean
    local function basic_eligible(source_win, root_config)
        return eligible_kind(source_win, root_config) ~= nil
    end

    ---@param source_win integer
    ---@param root_config table
    ---@return ScrollbarSourceKind?
    local function eligible_kind_cached(source_win, root_config)
        local now = vim.uv.now()
        local cached = eligibility_cache[source_win]
        local ok_win, source_buf = pcall(vim.api.nvim_win_get_buf, source_win)
        if not ok_win then
            return nil
        end
        local line_count = nil
        if type(root_config.max_lines) == "number" then
            local ok_count, count = pcall(vim.api.nvim_buf_line_count, source_buf)
            if not ok_count then
                return nil
            end
            line_count = count
        end
        if
            cached ~= nil
            and cached.at >= now - (tuning.eligibility_interval_ms or ELIGIBILITY_TTL_MS)
            and cached.root == root_config
            and cached.bufnr == source_buf
            and cached.line_count == line_count
        then
            return cached.kind
        end
        local kind = eligible_kind(source_win, root_config)
        eligibility_cache[source_win] = {
            at = now,
            root = root_config,
            bufnr = source_buf,
            line_count = line_count,
            kind = kind,
        }
        return kind
    end

    ---@return integer?
    local function active_source_window()
        local current = vim.api.nvim_get_current_win()
        local owned_state = states_by_float[current]
        if owned_state ~= nil and valid_window(owned_state.source_win) then
            return owned_state.source_win
        end
        local ok, window_config = pcall(vim.api.nvim_win_get_config, current)
        if not ok then
            return nil
        end
        if window_config.relative == "" then
            return current
        end
        -- A float is the active source only when it is a source of this
        -- renderer.
        local root_config = config.get()
        local floats = root_config.floats
        if floats ~= nil and floats.enabled and eligible_kind_cached(current, root_config) ~= nil then
            return current
        end
    end

    ---The windows of the picker that has focus, keyed by window.
    ---@param root_config table
    ---@return table<integer, true>
    local function active_group(root_config)
        local floats = root_config.floats
        if floats == nil or not floats.enabled then
            return NO_GROUP
        end
        local current = vim.api.nvim_get_current_win()
        local now = vim.uv.now()
        local cached = group_cache
        if
            cached ~= nil
            and cached.current == current
            and cached.at >= now - (tuning.source_selection_interval_ms or SOURCE_SELECTION_TTL_MS)
        then
            return cached.members
        end
        local members = {}
        for _, winid in ipairs(float_kinds.group(current)) do
            members[winid] = true
        end
        group_cache = { current = current, at = now, members = members }
        return members
    end

    ---With `visibility = "active"`, the active source shows, and so do the
    ---source windows of the picker that has focus, such as the list and the
    ---preview while the picker input has focus.
    ---@param active_source? integer
    ---@return table<integer, true>
    local function active_windows(active_source)
        local result = {}
        local root_config = config.get()
        for winid in pairs(active_group(root_config)) do
            result[winid] = true
        end
        if active_source ~= nil then
            result[active_source] = true
        end
        return result
    end

    ---@param source_win integer
    ---@param root_config table
    ---@param active_source? integer
    ---@param kind? ScrollbarSourceKind|false Precomputed `eligible_kind` result. False is not eligible
    ---@return table?
    local function source_selection(source_win, root_config, active_source, kind)
        if kind == nil then
            kind = eligible_kind(source_win, root_config)
        end
        if not kind then
            return nil
        end
        if
            root_config.visibility == "active"
            and source_win ~= active_source
            and not active_group(root_config)[source_win]
        then
            return nil
        end

        local selection = config.select(source_win, kind)
        -- Editor-relative placement keeps the rule of one bar: only the active
        -- source shows, also in a picker.
        if selection.config.placement.relative == "editor" and source_win ~= active_source then
            return nil
        end
        selection.kind = kind
        return selection
    end

    ---@param winid integer
    ---@return boolean
    local function is_source_window(winid)
        local root_config = config.get()
        local now = vim.uv.now()
        local ok_win, source_buf = pcall(vim.api.nvim_win_get_buf, winid)
        if not ok_win then
            return false
        end
        local current = vim.api.nvim_get_current_win()
        local active_source = active_source_window()
        local cached = selection_cache[winid]
        if
            cached ~= nil
            and cached.at >= now - (tuning.source_selection_interval_ms or SOURCE_SELECTION_TTL_MS)
            and cached.root == root_config
            and cached.bufnr == source_buf
            and cached.active_source == active_source
            and cached.current == current
        then
            return cached.selected
        end
        local kind = eligible_kind_cached(winid, root_config)
        local selected = kind ~= nil and source_selection(winid, root_config, active_source, kind) ~= nil or false
        selection_cache[winid] = {
            at = now,
            root = root_config,
            bufnr = source_buf,
            active_source = active_source,
            current = current,
            selected = selected,
        }
        return selected
    end

    ---@param winid integer
    ---@return ScrollbarSourceKind?
    local function source_kind(winid)
        local root_config = config.get()
        return eligible_kind_cached(winid, root_config)
    end

    ---Clear the memo of one source window, or of every window.
    ---@param source_win? integer
    local function invalidate(source_win)
        group_cache = nil
        if source_win == nil then
            eligibility_cache = {}
            selection_cache = {}
        else
            eligibility_cache[source_win] = nil
            selection_cache[source_win] = nil
        end
    end

    ---List the selected source windows and release every retained source
    ---window that is no longer selected.
    ---@param bufnr? integer Only the windows that show this buffer
    ---@return integer[]
    local function source_windows(bufnr)
        local root_config = config.get()
        local active_source = active_source_window()
        local selected = {}
        local all_sources = {}
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if source_selection(winid, root_config, active_source) ~= nil then
                selected[winid] = true
                table.insert(all_sources, winid)
            end
        end
        table.sort(all_sources)

        local stale = {}
        collect_stale(selected, stale)
        for source_win in pairs(stale) do
            close_source(source_win)
        end

        if bufnr == nil then
            return all_sources
        end

        local filtered = {}
        for _, winid in ipairs(all_sources) do
            if vim.api.nvim_win_get_buf(winid) == bufnr then
                table.insert(filtered, winid)
            end
        end
        return filtered
    end

    return {
        valid_window = valid_window,
        owned_window = owned_window,
        owned_buffer = owned_buffer,
        normal_window = normal_window,
        buffer_eligible = buffer_eligible,
        basic_eligible = basic_eligible,
        source_kind = source_kind,
        active_source_window = active_source_window,
        active_windows = active_windows,
        source_selection = source_selection,
        is_source_window = is_source_window,
        invalidate = invalidate,
        source_windows = source_windows,
        windows_showing_buffer = windows_showing_buffer,
    }
end

return M
