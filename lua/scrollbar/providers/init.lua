local config = require("scrollbar.config")
local store = require("scrollbar.store")

local M = {}

---@class ScrollbarManagedProvider
---@field provider ScrollbarProvider
---@field context? ScrollbarProviderContext
---@field setup_ok boolean
---@field augroups table<integer, true>
---@field cleanups function[]

---@class ScrollbarProviderManagerOptions
---@field config? ScrollbarConfig
---@field invalidate_buffer? fun(bufnr: integer)
---@field invalidate_window? fun(winid: integer)
---@field source_windows? fun(bufnr?: integer): integer[]
---@field is_buffer_eligible? fun(bufnr: integer): boolean
---@field is_source_window? fun(winid: integer): boolean

---@class ScrollbarProviderManagerState
---@field config ScrollbarConfig
---@field invalidate_buffer fun(bufnr: integer)
---@field invalidate_window fun(winid: integer)
---@field source_windows fun(bufnr?: integer): integer[]
---@field is_buffer_eligible fun(bufnr: integer): boolean
---@field is_source_window fun(winid: integer): boolean

---@type table<string, ScrollbarManagedProvider>
local registry = {}

---@type string[]
local order = {}

---@type ScrollbarProviderManagerState?
local manager

---@type integer?
local manager_group

---@type table<string, table<string, table<string, true>>>
local warned = {}

local function noop() end

---@param provider string
---@param operation string
---@param signature string
local function warn_once(provider, operation, signature)
    warned[provider] = warned[provider] or {}
    warned[provider][operation] = warned[provider][operation] or {}
    if warned[provider][operation][signature] then
        return
    end

    warned[provider][operation][signature] = true
    vim.notify(
        string.format("[scrollbar.nvim] provider '%s' %s failed: %s", provider, operation, signature),
        vim.log.levels.WARN
    )
end

---@param provider string
---@param operation string
local function reset_warnings(provider, operation)
    local provider_warnings = warned[provider]
    if provider_warnings == nil then
        return
    end

    provider_warnings[operation] = nil
    if next(provider_warnings) == nil then
        warned[provider] = nil
    end
end

---@param callback function
---@param ... any
local function guarded_callback(callback, ...)
    local ok, err = pcall(callback, ...)
    if not ok then
        vim.notify("[scrollbar.nvim] provider manager callback failed: " .. tostring(err), vim.log.levels.WARN)
    end
end

---@param changed ScrollbarChangedBuffers
local function invalidate_changed(changed)
    if manager == nil then
        return
    end
    for bufnr in pairs(changed) do
        guarded_callback(manager.invalidate_buffer, bufnr)
    end
end

---@param changed ScrollbarChangedWindows
local function invalidate_changed_windows(changed)
    if manager == nil then
        return
    end
    for winid in pairs(changed) do
        guarded_callback(manager.invalidate_window, winid)
    end
end

---@param bufnr integer
---@return boolean
local function is_buffer_eligible(bufnr)
    assert(manager ~= nil, "provider manager is not set up")
    local ok, eligible = pcall(manager.is_buffer_eligible, bufnr)
    if not ok then
        vim.notify(
            "[scrollbar.nvim] provider manager buffer eligibility lookup failed: " .. tostring(eligible),
            vim.log.levels.WARN
        )
    end
    return ok and eligible == true
end

---@param winid integer
---@return boolean
local function is_source_window(winid)
    assert(manager ~= nil, "provider manager is not set up")
    local ok, selected = pcall(manager.is_source_window, winid)
    if not ok then
        vim.notify(
            "[scrollbar.nvim] provider manager source window lookup failed: " .. tostring(selected),
            vim.log.levels.WARN
        )
    end
    return ok and selected == true
end

---@param bufnr? integer
---@return integer[]
local function source_windows(bufnr)
    assert(manager ~= nil, "provider manager is not set up")
    local ok, windows = pcall(manager.source_windows, bufnr)
    if not ok or type(windows) ~= "table" then
        vim.notify(
            "[scrollbar.nvim] provider manager source window lookup failed: " .. tostring(windows),
            vim.log.levels.WARN
        )
        return {}
    end
    return vim.deepcopy(windows)
end

---@param provider string
---@param bufnr integer
---@param marks any
---@return boolean
local function publish_buffer(provider, bufnr, marks)
    if type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) and not is_buffer_eligible(bufnr) then
        invalidate_changed(store.clear(provider, bufnr))
        return false
    end

    local success, changed = store.set(provider, bufnr, marks)
    invalidate_changed(changed)
    return success
end

---@param bufnr integer
---@param compact ScrollbarCompactSearch
---@return boolean
local function publish_search_compact(bufnr, compact)
    if type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) and not is_buffer_eligible(bufnr) then
        invalidate_changed(store.clear("search", bufnr))
        return false
    end

    local success, changed = store._set_search_compact(bufnr, compact)
    invalidate_changed(changed)
    return success
end

---@param provider string
---@param winid integer
---@param marks any
---@return boolean
local function publish_window(provider, winid, marks)
    if type(winid) == "number" and vim.api.nvim_win_is_valid(winid) and not is_source_window(winid) then
        invalidate_changed_windows(store.clear_window(provider, winid))
        return false
    end

    local success, changed = store.set_window(provider, winid, marks)
    invalidate_changed_windows(changed)
    return success
end

---@param name string
---@return string
local function augroup_component(name)
    return (name:gsub("[^%w_]", "_"))
end

---@param entry ScrollbarManagedProvider
---@return ScrollbarProviderContext
local function make_context(entry)
    assert(manager ~= nil, "provider manager is not set up")
    local provider_name = entry.provider.name

    return {
        config = vim.deepcopy(manager.config),
        set_marks = function(bufnr, marks)
            return publish_buffer(provider_name, bufnr, marks)
        end,
        _set_search_compact = publish_search_compact,
        clear_marks = function(bufnr)
            local changed
            if bufnr == nil then
                changed = store.clear_provider(provider_name)
            else
                changed = store.clear(provider_name, bufnr)
            end
            invalidate_changed(changed)
            return next(changed) ~= nil
        end,
        set_window_marks = function(winid, marks)
            return publish_window(provider_name, winid, marks)
        end,
        clear_window_marks = function(winid)
            local changed
            if winid == nil then
                changed = store.clear_window_provider(provider_name)
            else
                changed = store.clear_window(provider_name, winid)
            end
            invalidate_changed_windows(changed)
            return next(changed) ~= nil
        end,
        create_augroup = function(name)
            if type(name) ~= "string" or name == "" then
                error("provider augroup name must be a non-empty string", 2)
            end
            local group = vim.api.nvim_create_augroup(
                "ScrollbarProvider_" .. augroup_component(provider_name) .. "_" .. augroup_component(name),
                { clear = true }
            )
            entry.augroups[group] = true
            return group
        end,
        add_cleanup = function(cleanup)
            if type(cleanup) ~= "function" then
                error("provider cleanup must be a function", 2)
            end
            table.insert(entry.cleanups, cleanup)
        end,
        source_windows = function(bufnr)
            return source_windows(bufnr)
        end,
        is_buffer_eligible = function(bufnr)
            return is_buffer_eligible(bufnr)
        end,
        is_source_window = function(winid)
            return is_source_window(winid)
        end,
        invalidate_buffer = function(bufnr)
            assert(manager ~= nil, "provider manager is not set up")
            guarded_callback(manager.invalidate_buffer, bufnr)
        end,
        invalidate_window = function(winid)
            assert(manager ~= nil, "provider manager is not set up")
            guarded_callback(manager.invalidate_window, winid)
        end,
    }
end

---@return integer[]
local function eligible_buffers()
    assert(manager ~= nil, "provider manager is not set up")
    local buffers = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if is_buffer_eligible(bufnr) then
            table.insert(buffers, bufnr)
        end
    end
    table.sort(buffers)
    return buffers
end

---@param winid integer
---@return boolean
local function is_eligible_window(winid)
    return is_source_window(winid)
end

---@return integer[]
local function eligible_windows()
    assert(manager ~= nil, "provider manager is not set up")
    local windows = {}
    for _, winid in ipairs(source_windows()) do
        if is_eligible_window(winid) then
            table.insert(windows, winid)
        end
    end
    table.sort(windows)
    return windows
end

---@param entry ScrollbarManagedProvider
---@param bufnr integer
---@return boolean
local function refresh_entry(entry, bufnr)
    if manager == nil or not entry.setup_ok or entry.provider.refresh == nil then
        return false
    end
    if not is_buffer_eligible(bufnr) then
        invalidate_changed(store.clear(entry.provider.name, bufnr))
        return false
    end

    local operation = "refresh for buffer " .. bufnr
    local ok, marks = pcall(entry.provider.refresh, bufnr, entry.context)
    if not ok then
        invalidate_changed(store.clear(entry.provider.name, bufnr))
        warn_once(entry.provider.name, operation, tostring(marks))
        return false
    end

    reset_warnings(entry.provider.name, operation)
    if not is_buffer_eligible(bufnr) then
        invalidate_changed(store.clear(entry.provider.name, bufnr))
        return false
    end
    if marks == nil then
        return true
    end

    return publish_buffer(entry.provider.name, bufnr, marks)
end

---@param entry ScrollbarManagedProvider
---@param winid integer
---@return boolean
local function refresh_window_entry(entry, winid)
    if manager == nil or not entry.setup_ok or entry.provider.refresh_window == nil then
        return false
    end
    if not is_eligible_window(winid) then
        invalidate_changed_windows(store.clear_window(entry.provider.name, winid))
        return false
    end

    local operation = "window refresh for window " .. winid
    local ok, marks = pcall(entry.provider.refresh_window, winid, entry.context)
    if not ok then
        invalidate_changed_windows(store.clear_window(entry.provider.name, winid))
        warn_once(entry.provider.name, operation, tostring(marks))
        return false
    end

    reset_warnings(entry.provider.name, operation)
    if not is_eligible_window(winid) then
        invalidate_changed_windows(store.clear_window(entry.provider.name, winid))
        return false
    end
    if marks == nil then
        return true
    end

    return publish_window(entry.provider.name, winid, marks)
end

---@type fun(entry: ScrollbarManagedProvider)
local release_resources

---@param entry ScrollbarManagedProvider
local function activate_entry(entry)
    entry.context = make_context(entry)
    entry.setup_ok = false
    if entry.provider.setup ~= nil then
        local ok, err = pcall(entry.provider.setup, entry.context)
        if not ok then
            release_resources(entry)
            invalidate_changed(store.clear_provider(entry.provider.name))
            invalidate_changed_windows(store.clear_window_provider(entry.provider.name))
            warn_once(entry.provider.name, "setup", tostring(err))
            return
        end
        reset_warnings(entry.provider.name, "setup")
    end
    entry.setup_ok = true

    for _, bufnr in ipairs(eligible_buffers()) do
        refresh_entry(entry, bufnr)
    end
    for _, winid in ipairs(eligible_windows()) do
        refresh_window_entry(entry, winid)
    end
end

---@param entry ScrollbarManagedProvider
release_resources = function(entry)
    for index = #entry.cleanups, 1, -1 do
        local ok, err = pcall(entry.cleanups[index])
        if not ok then
            warn_once(entry.provider.name, "cleanup", tostring(err))
        end
    end
    entry.cleanups = {}

    for group in pairs(entry.augroups) do
        pcall(vim.api.nvim_del_augroup_by_id, group)
    end
    entry.augroups = {}
end

---@param entry ScrollbarManagedProvider
local function deactivate_entry(entry)
    if entry.context ~= nil and entry.setup_ok and entry.provider.dispose ~= nil then
        local ok, err = pcall(entry.provider.dispose, entry.context)
        if not ok then
            warn_once(entry.provider.name, "dispose", tostring(err))
        else
            reset_warnings(entry.provider.name, "dispose")
        end
    end

    release_resources(entry)
    invalidate_changed(store.clear_provider(entry.provider.name))
    invalidate_changed_windows(store.clear_window_provider(entry.provider.name))
    entry.context = nil
    entry.setup_ok = false
end

---@param provider ScrollbarProvider
M.register = function(provider)
    if type(provider) ~= "table" then
        error("[scrollbar.nvim] provider must be a table", 2)
    end
    if type(provider.name) ~= "string" or provider.name == "" then
        error("[scrollbar.nvim] provider name must be a non-empty string", 2)
    end
    for _, field in ipairs({ "setup", "refresh", "refresh_window", "dispose" }) do
        if provider[field] ~= nil and type(provider[field]) ~= "function" then
            error(string.format("[scrollbar.nvim] provider '%s' %s must be a function", provider.name, field), 2)
        end
    end
    if provider.refresh_owner ~= nil and type(provider.refresh_owner) ~= "table" then
        error(string.format("[scrollbar.nvim] provider '%s' refresh_owner must be a table", provider.name), 2)
    end
    local refresh_owner = provider.refresh_owner or {}
    local unknown_scope
    for scope in pairs(refresh_owner) do
        if scope ~= "buffer" and scope ~= "window" then
            local scope_name = type(scope) == "string" and scope or "<" .. type(scope) .. ">"
            if unknown_scope == nil or scope_name < unknown_scope then
                unknown_scope = scope_name
            end
        end
    end
    if unknown_scope ~= nil then
        error(
            string.format(
                "[scrollbar.nvim] provider '%s' refresh_owner has unknown scope '%s'",
                provider.name,
                unknown_scope
            ),
            2
        )
    end
    for _, scope in ipairs({ "buffer", "window" }) do
        local owner = refresh_owner[scope]
        if owner ~= "manager" and owner ~= "provider" then
            if owner ~= nil then
                error(
                    string.format(
                        "[scrollbar.nvim] provider '%s' refresh_owner.%s must be 'manager' or 'provider'",
                        provider.name,
                        scope
                    ),
                    2
                )
            end
        end
    end
    if provider.refresh ~= nil and refresh_owner.buffer == nil then
        error(string.format("[scrollbar.nvim] provider '%s' refresh requires refresh_owner.buffer", provider.name), 2)
    end
    if provider.refresh_window ~= nil and refresh_owner.window == nil then
        error(
            string.format("[scrollbar.nvim] provider '%s' refresh_window requires refresh_owner.window", provider.name),
            2
        )
    end
    if refresh_owner.buffer ~= nil and provider.refresh == nil then
        error(string.format("[scrollbar.nvim] provider '%s' refresh_owner.buffer requires refresh", provider.name), 2)
    end
    if refresh_owner.window ~= nil and provider.refresh_window == nil then
        error(
            string.format("[scrollbar.nvim] provider '%s' refresh_owner.window requires refresh_window", provider.name),
            2
        )
    end
    if registry[provider.name] ~= nil then
        error(string.format("[scrollbar.nvim] provider '%s' is already registered", provider.name), 2)
    end

    local entry = {
        provider = provider,
        setup_ok = false,
        augroups = {},
        cleanups = {},
    }
    registry[provider.name] = entry
    table.insert(order, provider.name)

    if manager ~= nil then
        activate_entry(entry)
    end
end

---@param name string
---@return boolean
M.unregister = function(name)
    local entry = registry[name]
    if entry == nil then
        return false
    end

    if manager ~= nil then
        deactivate_entry(entry)
    else
        store.clear_provider(name)
        store.clear_window_provider(name)
    end
    registry[name] = nil
    warned[name] = nil
    for index, registered_name in ipairs(order) do
        if registered_name == name then
            table.remove(order, index)
            break
        end
    end
    return true
end

---@param name string
---@return ScrollbarProvider?
M.get = function(name)
    local entry = registry[name]
    return entry and entry.provider or nil
end

---@param bufnr integer
---@return boolean
M.refresh = function(bufnr)
    if manager == nil then
        return false
    end

    local refreshed = false
    for _, name in ipairs(order) do
        refreshed = refresh_entry(registry[name], bufnr) or refreshed
    end
    return refreshed
end

---@param winid integer
---@return boolean
M.refresh_window = function(winid)
    if manager == nil then
        return false
    end

    local refreshed = false
    for _, name in ipairs(order) do
        refreshed = refresh_window_entry(registry[name], winid) or refreshed
    end
    return refreshed
end

---@param options? ScrollbarProviderManagerOptions
M.setup = function(options)
    options = options or {}
    M.dispose()

    local active_config = vim.deepcopy(options.config or config.get())
    local renderer = require("scrollbar.renderer")
    manager = {
        config = active_config,
        invalidate_buffer = options.invalidate_buffer or noop,
        invalidate_window = options.invalidate_window or noop,
        source_windows = options.source_windows or renderer.source_windows,
        is_buffer_eligible = options.is_buffer_eligible or renderer.is_buffer_eligible,
        is_source_window = options.is_source_window or renderer.is_source_window,
    }

    manager_group = vim.api.nvim_create_augroup("ScrollbarProviderManager", { clear = true })
    vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = manager_group,
        callback = function(args)
            if manager == nil then
                return
            end
            for _, name in ipairs(order) do
                local entry = registry[name]
                local ownership = entry.provider.refresh_owner
                if ownership ~= nil and ownership.buffer == "manager" then
                    refresh_entry(entry, args.buf)
                end
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
        group = manager_group,
        callback = function(args)
            if manager == nil then
                return
            end
            local winid = vim.api.nvim_get_current_win()
            local eligible = is_eligible_window(winid)
            for _, name in ipairs(order) do
                local entry = registry[name]
                local ownership = entry.provider.refresh_owner
                if ownership ~= nil and ownership.window == "manager" then
                    if args.event == "BufWinEnter" then
                        invalidate_changed_windows(store.clear_window(entry.provider.name, winid))
                    end
                    if eligible then
                        refresh_window_entry(entry, winid)
                    else
                        invalidate_changed_windows(store.clear_window(entry.provider.name, winid))
                    end
                end
            end
        end,
    })

    for _, name in ipairs(order) do
        activate_entry(registry[name])
    end
end

M.dispose = function()
    if manager == nil then
        return
    end

    if manager_group ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, manager_group)
        manager_group = nil
    end
    for _, name in ipairs(order) do
        deactivate_entry(registry[name])
    end
    manager = nil
end

return M
