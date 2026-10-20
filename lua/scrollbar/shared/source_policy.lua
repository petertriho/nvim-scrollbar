--- Source-window policy of one renderer. The policy tells which windows and
--- buffers the renderer owns and which windows are eligible sources. It also
--- gives the selected configuration variant of a source window and the set of
--- source windows. The scrollbar renderer and the minimap renderer each build one policy over
--- their own configuration module and float registries.
---
--- The exported predicates serve hot event paths (provider collect and
--- publish re-checks, scheduler activity) that run several times per
--- keystroke, so they keep a short memo. Render paths call `source_selection`
--- directly, so profile `match` rules stay dynamic per render and a stale
--- window reconciles on the next flush.

local M = {}

-- `basic_eligible` (window normality and buffer eligibility) costs about
-- 2 µs. Its inputs are the window, the buffer and its line count
-- (`max_lines`), and the static root excludes, never the profile matchers.
-- The schedulers clear the memo on topology and option events. For standalone
-- use, the TTL bounds the staleness of a filetype or buftype change.
local ELIGIBILITY_TTL_MS = 50

-- A full selection also resolves `config.select` and the active source
-- (about 5 µs). Editor-relative placement makes the result depend on focus, so
-- the active source is part of the key.
local SOURCE_SELECTION_TTL_MS = 50

---@class ScrollbarSourcePolicyConfigModule
---@field get fun(): table Root configuration with `enabled`, `exclude`, `max_lines`, and `visibility`
---@field select fun(source_win: integer): table Selection with `config` and `variant_id`

---@class ScrollbarSourcePolicyTuning
---@field eligibility_interval_ms? integer Memo lifetime of `basic_eligible`
---@field source_selection_interval_ms? integer Memo lifetime of `is_source_window`

---@class ScrollbarSourcePolicyOptions
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
---@field buffer_eligible fun(bufnr: integer, root_config: table): boolean
---@field basic_eligible fun(source_win: integer, root_config: table): boolean
---@field active_source_window fun(): integer?
---@field source_selection fun(source_win: integer, root_config: table, active_source?: integer, basic_ok?: boolean): table?
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
    local config = options.config
    local owned_var = options.owned_var
    local states_by_float = options.states_by_float
    local owned_float_buffers = options.owned_float_buffers
    local tuning = options.tuning
    local collect_stale = options.collect_stale
    local close_source = options.close_source

    local eligibility_cache = {}
    local selection_cache = {}

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

    ---@param bufnr integer
    ---@param root_config table
    ---@return boolean
    local function buffer_eligible(bufnr, root_config)
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

        local line_count = vim.api.nvim_buf_line_count(bufnr)
        return root_config.max_lines == false or line_count <= root_config.max_lines
    end

    ---@param source_win integer
    ---@param root_config table
    ---@return boolean
    local function basic_eligible(source_win, root_config)
        return normal_window(source_win) and buffer_eligible(vim.api.nvim_win_get_buf(source_win), root_config)
    end

    ---@param source_win integer
    ---@param root_config table
    ---@return boolean
    local function basic_eligible_cached(source_win, root_config)
        local now = vim.uv.now()
        local cached = eligibility_cache[source_win]
        local ok_win, source_buf = pcall(vim.api.nvim_win_get_buf, source_win)
        if not ok_win then
            return false
        end
        local line_count = nil
        if type(root_config.max_lines) == "number" then
            local ok_count, count = pcall(vim.api.nvim_buf_line_count, source_buf)
            if not ok_count then
                return false
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
            return cached.eligible
        end
        local eligible = normal_window(source_win) and buffer_eligible(source_buf, root_config) or false
        eligibility_cache[source_win] = {
            at = now,
            root = root_config,
            bufnr = source_buf,
            line_count = line_count,
            eligible = eligible,
        }
        return eligible
    end

    ---@return integer?
    local function active_source_window()
        local current = vim.api.nvim_get_current_win()
        local owned_state = states_by_float[current]
        if owned_state ~= nil and valid_window(owned_state.source_win) then
            return owned_state.source_win
        end
        if normal_window(current) then
            return current
        end
    end

    ---@param source_win integer
    ---@param root_config table
    ---@param active_source? integer
    ---@param basic_ok? boolean Precomputed `basic_eligible` result
    ---@return table?
    local function source_selection(source_win, root_config, active_source, basic_ok)
        if basic_ok == nil then
            basic_ok = basic_eligible(source_win, root_config)
        end
        if not basic_ok then
            return nil
        end
        if root_config.visibility == "active" and source_win ~= active_source then
            return nil
        end

        local selection = config.select(source_win)
        if selection.config.placement.relative == "editor" and source_win ~= active_source then
            return nil
        end
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
        local active_source = active_source_window()
        local cached = selection_cache[winid]
        if
            cached ~= nil
            and cached.at >= now - (tuning.source_selection_interval_ms or SOURCE_SELECTION_TTL_MS)
            and cached.root == root_config
            and cached.bufnr == source_buf
            and cached.active_source == active_source
        then
            return cached.selected
        end
        local selected = basic_eligible_cached(winid, root_config)
                and source_selection(winid, root_config, active_source, true) ~= nil
            or false
        selection_cache[winid] = {
            at = now,
            root = root_config,
            bufnr = source_buf,
            active_source = active_source,
            selected = selected,
        }
        return selected
    end

    ---Clear the memo of one source window, or of every window.
    ---@param source_win? integer
    local function invalidate(source_win)
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
        active_source_window = active_source_window,
        source_selection = source_selection,
        is_source_window = is_source_window,
        invalidate = invalidate,
        source_windows = source_windows,
        windows_showing_buffer = windows_showing_buffer,
    }
end

return M
