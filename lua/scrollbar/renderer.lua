local config = require("scrollbar.config")
local layout = require("scrollbar.layout")
local store = require("scrollbar.store")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarRenderer")
local AUGROUP_NAME = "ScrollbarRendererLifecycle"

---@type table<integer, ScrollbarWindowState>
local states = {}

---@type table<integer, ScrollbarWindowState>
local states_by_float = {}

---@type integer?
local lifecycle_group
local visible = false

---@type fun(state: ScrollbarWindowState)?
local state_callback

---@param value any
---@param values string[]
---@return boolean
local function contains(values, value)
    for _, item in ipairs(values) do
        if item == value then
            return true
        end
    end
    return false
end

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---@param winid integer
---@return boolean
local function owned_window(winid)
    if states_by_float[winid] ~= nil then
        return true
    end
    if not valid_window(winid) then
        return false
    end

    local ok, owned = pcall(vim.api.nvim_win_get_var, winid, "scrollbar_owned")
    return ok and owned == true
end

---@param winid integer
---@return boolean
local function normal_window(winid)
    if not valid_window(winid) or owned_window(winid) then
        return false
    end

    local ok, window_config = pcall(vim.api.nvim_win_get_config, winid)
    return ok and window_config.relative == ""
end

---@param source_win integer
---@return boolean
local function basic_eligible(source_win)
    if not normal_window(source_win) then
        return false
    end

    local source_buf = vim.api.nvim_win_get_buf(source_win)
    if not vim.api.nvim_buf_is_valid(source_buf) or not vim.api.nvim_buf_is_loaded(source_buf) then
        return false
    end

    local active_config = config.get()
    if contains(active_config.excluded_buftypes, vim.bo[source_buf].buftype) then
        return false
    end
    if contains(active_config.excluded_filetypes, vim.bo[source_buf].filetype) then
        return false
    end

    local line_count = vim.api.nvim_buf_line_count(source_buf)
    return active_config.max_lines == false or line_count <= active_config.max_lines
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

---@return boolean
local function active_only()
    local active_config = config.get()
    return active_config.visibility == "active" or active_config.float.placement.relative == "editor"
end

---@param state ScrollbarWindowState
local function forget_state(state)
    states[state.source_win] = nil
    states_by_float[state.float_win] = nil
end

---@param state ScrollbarWindowState
local function close_state(state)
    forget_state(state)
    if valid_window(state.float_win) then
        pcall(vim.api.nvim_win_close, state.float_win, true)
    end
    if vim.api.nvim_buf_is_valid(state.float_buf) then
        pcall(vim.api.nvim_buf_delete, state.float_buf, { force = true })
    end
end

---@param source_win integer
local function close_source(source_win)
    local state = states[source_win]
    if state ~= nil then
        close_state(state)
    end
end

local function close_all_states()
    local pending = {}
    for _, state in pairs(states) do
        table.insert(pending, state)
    end
    for _, state in ipairs(pending) do
        close_state(state)
    end
end

---@param source_win integer
local function close_other_states(source_win)
    local pending = {}
    for winid, state in pairs(states) do
        if winid ~= source_win then
            table.insert(pending, state)
        end
    end
    for _, state in ipairs(pending) do
        close_state(state)
    end
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
    end
end

---@param source_win integer
---@param height integer
---@return table<string, any>
local function float_config(source_win, height)
    local active_config = config.get()
    local placement = active_config.float.placement
    local source_width = vim.api.nvim_win_get_width(source_win)
    local source_height = vim.api.nvim_win_get_height(source_win)
    local container_width = placement.relative == "window" and source_width or vim.o.columns
    local container_height = placement.relative == "window" and source_height or vim.o.lines
    local north = placement.anchor == "NW" or placement.anchor == "NE"
    local west = placement.anchor == "NW" or placement.anchor == "SW"

    local result = {
        relative = placement.relative == "window" and "win" or "editor",
        anchor = placement.anchor,
        row = (north and 0 or container_height) + placement.row,
        col = (west and 0 or container_width) + placement.col,
        width = active_config.float.width,
        height = height,
        style = "minimal",
        focusable = active_config.mouse.enabled,
        mouse = active_config.mouse.enabled,
        zindex = active_config.float.zindex,
    }
    if placement.relative == "window" then
        result.win = source_win
    end
    return result
end

---@param float_buf integer
local function configure_buffer(float_buf)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = float_buf })
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = float_buf })
    vim.api.nvim_set_option_value("swapfile", false, { buf = float_buf })
    vim.api.nvim_set_option_value("undolevels", -1, { buf = float_buf })
    vim.api.nvim_set_option_value("filetype", "scrollbar", { buf = float_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    vim.api.nvim_buf_set_var(float_buf, "scrollbar_owned", true)
end

---@param float_win integer
local function configure_window(float_win)
    vim.api.nvim_set_option_value("wrap", false, { win = float_win })
    vim.api.nvim_set_option_value("number", false, { win = float_win })
    vim.api.nvim_set_option_value("relativenumber", false, { win = float_win })
    vim.api.nvim_set_option_value("signcolumn", "no", { win = float_win })
    vim.api.nvim_set_option_value("foldcolumn", "0", { win = float_win })
    vim.api.nvim_set_option_value("cursorline", false, { win = float_win })
    vim.api.nvim_set_option_value("cursorcolumn", false, { win = float_win })
    vim.api.nvim_set_option_value("winfixbuf", true, { win = float_win })
    vim.api.nvim_set_option_value("list", false, { win = float_win })
    vim.api.nvim_set_option_value("spell", false, { win = float_win })
    vim.api.nvim_set_option_value(
        "winhighlight",
        "Normal:ScrollbarFloat,NormalNC:ScrollbarFloat,EndOfBuffer:ScrollbarFloat",
        { win = float_win }
    )
    vim.api.nvim_win_set_var(float_win, "scrollbar_owned", true)
end

---@param source_win integer
---@param source_buf integer
---@param height integer
---@return ScrollbarWindowState
local function create_state(source_win, source_buf, height)
    local float_buf = vim.api.nvim_create_buf(false, true)
    configure_buffer(float_buf)
    pcall(vim.api.nvim_buf_set_name, float_buf, string.format("scrollbar://source/%d/%d", source_win, float_buf))

    local float_win = vim.api.nvim_open_win(float_buf, false, float_config(source_win, height))
    configure_window(float_win)

    local state = {
        source_win = source_win,
        source_buf = source_buf,
        float_win = float_win,
        float_buf = float_buf,
        width = 0,
        height = 0,
        rows = {},
        highlights = {},
        hitmap = {},
        handle = { first_row = -1, last_row = -1, column = 1, width = 1 },
        geometry = { mode = "line", total_extent = 0, viewport_start = 0, viewport_end = 0 },
    }
    states[source_win] = state
    states_by_float[float_win] = state
    return state
end

---@param source_buf integer
---@return ScrollbarLayoutMark[]
local function flattened_marks(source_buf)
    local snapshot = store.get(source_buf)
    local providers = {}
    for provider in pairs(snapshot) do
        table.insert(providers, provider)
    end
    table.sort(providers)

    local marks = {}
    for _, provider in ipairs(providers) do
        for _, mark in ipairs(snapshot[provider]) do
            table.insert(marks, {
                provider = provider,
                line = mark.line,
                type = mark.type,
                text = mark.text,
            })
        end
    end
    return marks
end

---@param source_win integer
---@param source_buf integer
---@param height integer
---@param marks ScrollbarLayoutMark[]
---@return ScrollbarGeometry
local function geometry_for(source_win, source_buf, height, marks)
    if config.get().render.geometry == "screen" then
        return layout.screen({ source_win = source_win, marks = marks })
    end

    local viewport = vim.api.nvim_win_call(source_win, function()
        return { vim.fn.line("w0") - 1, vim.fn.line("w$") - 1 }
    end)
    return layout.normalized({
        height = height,
        line_count = vim.api.nvim_buf_line_count(source_buf),
        top_line = viewport[1],
        bottom_line = viewport[2],
        marks = marks,
    })
end

---@param float_buf integer
---@param row integer
---@param spans ScrollbarHighlightSpan[]
local function write_highlights(float_buf, row, spans)
    for _, span in ipairs(spans) do
        vim.api.nvim_buf_set_extmark(float_buf, NAMESPACE, row, span.start_col, {
            end_row = row,
            end_col = span.end_col,
            hl_group = span.highlight,
            hl_mode = "combine",
            strict = false,
        })
    end
end

---@param float_buf integer
---@param callback fun()
local function with_modifiable(float_buf, callback)
    vim.api.nvim_set_option_value("modifiable", true, { buf = float_buf })
    local ok, error_message = pcall(callback)
    if vim.api.nvim_buf_is_valid(float_buf) then
        vim.api.nvim_set_option_value("modifiable", false, { buf = float_buf })
    end
    if not ok then
        error(error_message)
    end
end

---@param state ScrollbarWindowState
---@param output ScrollbarLayoutOutput
---@param width integer
---@param height integer
local function update_buffer(state, output, width, height)
    local dimensions_changed = state.width ~= width or state.height ~= height
    if dimensions_changed then
        with_modifiable(state.float_buf, function()
            vim.api.nvim_buf_set_lines(state.float_buf, 0, -1, false, output.rows)
        end)
        vim.api.nvim_buf_clear_namespace(state.float_buf, NAMESPACE, 0, -1)
        for row, spans in ipairs(output.highlights) do
            write_highlights(state.float_buf, row - 1, spans)
        end
        return
    end

    for row = 1, height do
        if state.rows[row] ~= output.rows[row] or not vim.deep_equal(state.highlights[row], output.highlights[row]) then
            with_modifiable(state.float_buf, function()
                vim.api.nvim_buf_set_lines(state.float_buf, row - 1, row, false, { output.rows[row] })
            end)
            vim.api.nvim_buf_clear_namespace(state.float_buf, NAMESPACE, row - 1, row)
            write_highlights(state.float_buf, row - 1, output.highlights[row])
        end
    end
end

---@param source_win integer
---@return ScrollbarWindowState?
local function render_source(source_win)
    if not visible or not basic_eligible(source_win) then
        close_source(source_win)
        return nil
    end

    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local height = vim.api.nvim_win_get_height(source_win)
    if height < 1 then
        close_source(source_win)
        return nil
    end

    local marks = flattened_marks(source_buf)
    local geometry = geometry_for(source_win, source_buf, height, marks)
    local all_visible = geometry.total_extent <= height
    if all_visible and config.get().hide_if_all_visible then
        close_source(source_win)
        return nil
    end
    if all_visible and config.get().handle.hide_if_all_visible then
        geometry.handle = { first_row = -1, last_row = -1 }
    end

    local output = layout.compose({
        config = config.get(),
        height = height,
        geometry = geometry,
        marks = marks,
    })

    ---@type ScrollbarWindowState?
    local state = states[source_win]
    if state ~= nil and state.source_buf ~= source_buf then
        close_state(state)
        state = nil
    end
    if state == nil or not valid_window(state.float_win) or not vim.api.nvim_buf_is_valid(state.float_buf) then
        if state ~= nil then
            close_state(state)
        end
        state = create_state(source_win, source_buf, height)
    else
        vim.api.nvim_win_set_config(state.float_win, float_config(source_win, height))
        configure_window(state.float_win)
        configure_buffer(state.float_buf)
    end

    local width = config.get().float.width
    update_buffer(state, output, width, height)
    state.width = width
    state.height = height
    state.rows = output.rows
    state.highlights = output.highlights
    state.hitmap = output.hitmap
    state.handle = output.handle
    state.geometry = {
        mode = config.get().render.geometry,
        total_extent = geometry.total_extent,
        viewport_start = geometry.viewport_start,
        viewport_end = geometry.viewport_end,
    }
    if state_callback ~= nil then
        pcall(state_callback, state)
    end
    return state
end

---@param source_win integer
---@return ScrollbarWindowState?
M.render = function(source_win)
    source_win = source_win or vim.api.nvim_get_current_win()
    if active_only() then
        local active_source = active_source_window()
        if active_source == nil or source_win ~= active_source then
            close_source(source_win)
            if active_source ~= nil then
                close_other_states(active_source)
            else
                close_all_states()
            end
            return nil
        end
        close_other_states(active_source)
    end

    local ok, state = pcall(render_source, source_win)
    if not ok then
        close_source(source_win)
        return nil
    end
    return state
end

---@param source_win integer
---@return ScrollbarWindowState?
M.get_state = function(source_win)
    return states[source_win]
end

---@param float_win integer
---@return ScrollbarWindowState?
M.get_state_by_float = function(float_win)
    return states_by_float[float_win]
end

---@param source_win integer
---@return ScrollbarHitCell[][]?
M.get_hitmap = function(source_win)
    local state = states[source_win]
    return state and state.hitmap or nil
end

---@param source_win integer
---@return ScrollbarHandleGeometry?
M.get_handle = function(source_win)
    local state = states[source_win]
    return state and state.handle or nil
end

---@param callback? fun(state: ScrollbarWindowState)
M.set_state_callback = function(callback)
    state_callback = callback
    if callback == nil then
        return
    end
    for _, state in pairs(states) do
        pcall(callback, state)
    end
end

---@param winid integer
---@return boolean
M.is_owned_window = function(winid)
    return owned_window(winid)
end

---@param bufnr integer
---@return boolean
M.is_owned_buffer = function(bufnr)
    if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    local ok, owned = pcall(vim.api.nvim_buf_get_var, bufnr, "scrollbar_owned")
    return ok and owned == true
end

---@param bufnr? integer
---@return integer[]
M.source_windows = function(bufnr)
    local result = {}
    local only_active = active_only()
    local active_source = only_active and active_source_window() or nil
    if only_active and active_source == nil then
        return result
    end
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if
            basic_eligible(winid)
            and (not only_active or winid == active_source)
            and (bufnr == nil or vim.api.nvim_win_get_buf(winid) == bufnr)
        then
            table.insert(result, winid)
        end
    end
    table.sort(result)
    return result
end

M.hide = function()
    visible = false
    close_all_states()
end

M.show = function()
    visible = true
    for _, source_win in ipairs(M.source_windows()) do
        M.render(source_win)
    end
end

M.toggle = function()
    if visible then
        M.hide()
    else
        M.show()
    end
end

---@return boolean
M.is_visible = function()
    return visible
end

---@param source_win? integer
M.dispose = function(source_win)
    if source_win ~= nil then
        close_source(source_win)
        return
    end

    visible = false
    close_all_states()
    if lifecycle_group ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, lifecycle_group)
        lifecycle_group = nil
    end
end

M.setup = function()
    M.dispose()
    visible = config.get().show
    local background = vim.o.background == "light" and "#ffffff" or "#000000"
    vim.api.nvim_set_hl(0, "ScrollbarFloat", { bg = background, blend = 100 })
    lifecycle_group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })

    vim.api.nvim_create_autocmd("WinClosed", {
        group = lifecycle_group,
        callback = function(args)
            local closed_win = tonumber(args.match)
            if closed_win == nil then
                return
            end
            local state = states[closed_win] or states_by_float[closed_win]
            if state ~= nil then
                close_state(state)
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = lifecycle_group,
        callback = function(args)
            local pending = {}
            for _, state in pairs(states) do
                if state.source_buf == args.buf or state.float_buf == args.buf then
                    table.insert(pending, state)
                end
            end
            for _, state in ipairs(pending) do
                close_state(state)
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabClosed", {
        group = lifecycle_group,
        callback = sweep_states,
    })
end

return M
