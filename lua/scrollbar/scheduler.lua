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

---@class ScrollbarSchedulerRuntime
---@field config ScrollbarConfig
---@field renderer ScrollbarSchedulerRenderer
---@field on_colorscheme fun()
---@field timer any
---@field timer_armed boolean
---@field dirty table<integer, true>
---@field flushing boolean
---@field augroup integer

---@type ScrollbarSchedulerRuntime?
local runtime
local timer_closed = false

---@param bufnr integer
---@return boolean
local function owned_buffer(bufnr)
    if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
        return false
    end
    local ok, owned = pcall(vim.api.nvim_buf_get_var, bufnr, "scrollbar_owned")
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
        if
            type(winid) == "number"
            and not seen[winid]
            and vim.api.nvim_win_is_valid(winid)
            and not owned_window(current, winid)
        then
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
    if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) or owned_window(current, winid) then
        return false
    end
    for _, source_win in ipairs(source_windows(current)) do
        if source_win == winid then
            return true
        end
    end
    return false
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

---@param args table
---@return boolean
local function event_is_owned(args)
    local current = runtime
    if current == nil then
        return true
    end
    if owned_buffer(args.buf) then
        return true
    end
    local current_win = vim.api.nvim_get_current_win()
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

local function invalidate_scrolled_windows()
    local event = vim.v.event or {}
    if event.all == true or event.all == 1 then
        M.invalidate_all()
        return
    end

    local found = false
    for key in pairs(event) do
        local winid = tonumber(key)
        if winid ~= nil then
            found = true
            invalidate_event_window(winid)
        end
    end
    if not found then
        invalidate_event_window(vim.api.nvim_get_current_win())
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
                invalidate_scrolled_windows()
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
            local background = vim.o.background == "light" and "#ffffff" or "#000000"
            vim.api.nvim_set_hl(0, "ScrollbarFloat", { bg = background, blend = 100 })
            if active_config.set_highlights then
                require("scrollbar.utils").set_highlights()
            end
        end,
        timer = timer,
        timer_armed = false,
        dirty = {},
        flushing = false,
        augroup = augroup,
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
    for _, winid in ipairs(windows) do
        if runtime ~= current then
            break
        end
        if is_source_window(current, winid) then
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
    pcall(current.timer.stop, current.timer)
    if not current.timer:is_closing() then
        current.timer:close()
    end
    timer_closed = true
    pcall(vim.api.nvim_del_augroup_by_id, current.augroup)
end

return M
