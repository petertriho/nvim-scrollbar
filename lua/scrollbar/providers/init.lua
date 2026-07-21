local config = require("scrollbar.config")
local store = require("scrollbar.store")

local M = {}

---@class ScrollbarManagedProvider
---@field provider ScrollbarProvider
---@field context? ScrollbarProviderContext
---@field setup_ok boolean
---@field augroups table<integer, true>
---@field cleanups function[]
---@field targets ScrollbarProviderTargets
---@field builtin boolean

---@class ScrollbarProviderManagerOptions
---@field config? ScrollbarConfig
---@field provider_plan? ScrollbarEffectiveProviderPlan
---@field consumer_policies? table<"scrollbar"|"minimap", ScrollbarProviderConsumerPolicy>
---@field invalidate_buffer? fun(bufnr: integer)
---@field invalidate_window? fun(winid: integer)
---@field source_windows? fun(bufnr?: integer): integer[]
---@field is_buffer_eligible? fun(bufnr: integer): boolean
---@field is_source_window? fun(winid: integer): boolean

---@class ScrollbarProviderConsumerPolicy
---@field source_windows fun(bufnr?: integer): integer[]
---@field is_buffer_eligible fun(bufnr: integer): boolean
---@field is_source_window fun(winid: integer): boolean

---@class ScrollbarProviderManagerState
---@field config ScrollbarConfig
---@field provider_plan ScrollbarEffectiveProviderPlan
---@field consumer_policies table<"scrollbar"|"minimap", ScrollbarProviderConsumerPolicy>
---@field invalidate_buffer fun(bufnr: integer)
---@field invalidate_window fun(winid: integer)

---@type table<string, ScrollbarManagedProvider>
local registry = {}

---@type string[]
local order = {}

---@type ScrollbarProviderManagerState?
local manager

---@type integer?
local manager_group

---@type function?
local legacy_unsubscribe

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

---@param entry ScrollbarManagedProvider
---@return ScrollbarProviderConsumers
local function requested_consumers(entry)
    if not entry.builtin then
        return { scrollbar = entry.targets.scrollbar, minimap = entry.targets.minimap }
    end

    assert(manager ~= nil, "provider manager is not set up")
    local planned = manager.provider_plan[entry.provider.name]
    if planned == nil or planned.options == false then
        return { scrollbar = false, minimap = false }
    end
    return {
        scrollbar = entry.targets.scrollbar and planned.consumers.scrollbar,
        minimap = entry.targets.minimap and planned.consumers.minimap,
    }
end

---@param entry ScrollbarManagedProvider
---@return boolean
local function is_active(entry)
    local consumers = requested_consumers(entry)
    return consumers.scrollbar or consumers.minimap
end

---@param entry ScrollbarManagedProvider
---@param consumer "scrollbar"|"minimap"
---@param operation string
---@param callback function
---@param ... any
---@return boolean, any
local function query_policy(entry, consumer, operation, callback, ...)
    local ok, result = pcall(callback, ...)
    if not ok then
        vim.notify(
            string.format(
                "[scrollbar.nvim] provider '%s' %s %s lookup failed: %s",
                entry.provider.name,
                consumer,
                operation,
                tostring(result)
            ),
            vim.log.levels.WARN
        )
    end
    return ok, result
end

---@param entry ScrollbarManagedProvider
---@param bufnr integer
---@param consumer? "scrollbar"|"minimap"
---@return boolean
local function is_buffer_eligible(entry, bufnr, consumer)
    assert(manager ~= nil, "provider manager is not set up")
    local consumers = requested_consumers(entry)
    for _, name in ipairs({ "scrollbar", "minimap" }) do
        if (consumer == nil or consumer == name) and consumers[name] then
            local policy = manager.consumer_policies[name]
            local ok, eligible = query_policy(entry, name, "buffer eligibility", policy.is_buffer_eligible, bufnr)
            if ok and eligible == true then
                return true
            end
        end
    end
    return false
end

---@param entry ScrollbarManagedProvider
---@param winid integer
---@param consumer? "scrollbar"|"minimap"
---@return boolean
local function is_source_window(entry, winid, consumer)
    assert(manager ~= nil, "provider manager is not set up")
    local consumers = requested_consumers(entry)
    for _, name in ipairs({ "scrollbar", "minimap" }) do
        if (consumer == nil or consumer == name) and consumers[name] then
            local policy = manager.consumer_policies[name]
            local ok, selected = query_policy(entry, name, "source window", policy.is_source_window, winid)
            if ok and selected == true then
                return true
            end
        end
    end
    return false
end

---@param entry ScrollbarManagedProvider
---@param bufnr? integer
---@return integer[]
local function source_windows(entry, bufnr)
    assert(manager ~= nil, "provider manager is not set up")
    local consumers = requested_consumers(entry)
    local result = {}
    local seen = {}
    for _, name in ipairs({ "scrollbar", "minimap" }) do
        if consumers[name] then
            local policy = manager.consumer_policies[name]
            local ok, windows = query_policy(entry, name, "source window", policy.source_windows, bufnr)
            if ok and type(windows) == "table" then
                for _, winid in ipairs(windows) do
                    if not seen[winid] then
                        seen[winid] = true
                        table.insert(result, winid)
                    end
                end
            elseif ok then
                vim.notify(
                    string.format(
                        "[scrollbar.nvim] provider '%s' %s source window lookup failed: expected table",
                        entry.provider.name,
                        name
                    ),
                    vim.log.levels.WARN
                )
            end
        end
    end
    return vim.deepcopy(result)
end

---@param entry ScrollbarManagedProvider
---@param bufnr integer
---@param marks any
---@param consumer? "scrollbar"|"minimap"
---@return boolean
local function publish_buffer(entry, bufnr, marks, consumer)
    local provider = entry.provider.name
    if
        type(bufnr) == "number"
        and vim.api.nvim_buf_is_valid(bufnr)
        and not is_buffer_eligible(entry, bufnr, consumer)
    then
        store.clear(provider, bufnr)
        return false
    end

    local success = store.set(provider, bufnr, marks)
    return success
end

---@param entry ScrollbarManagedProvider
---@param bufnr integer
---@param compact ScrollbarCompactSearch
---@return boolean
local function publish_search_compact(entry, bufnr, compact)
    if type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) and not is_buffer_eligible(entry, bufnr) then
        store.clear("search", bufnr)
        return false
    end

    local success = store._set_search_compact(bufnr, compact)
    return success
end

---@param entry ScrollbarManagedProvider
---@param winid integer
---@param marks any
---@param consumer? "scrollbar"|"minimap"
---@return boolean
local function publish_window(entry, winid, marks, consumer)
    local provider = entry.provider.name
    if
        type(winid) == "number"
        and vim.api.nvim_win_is_valid(winid)
        and not is_source_window(entry, winid, consumer)
    then
        store.clear_window(provider, winid)
        return false
    end

    local success = store.set_window(provider, winid, marks)
    return success
end

---@param entry ScrollbarManagedProvider
---@param bufnr integer
---@param spans any
---@return boolean
local function publish_minimap_spans(entry, bufnr, spans)
    local provider = entry.provider.name
    if
        type(bufnr) == "number"
        and vim.api.nvim_buf_is_valid(bufnr)
        and not is_buffer_eligible(entry, bufnr, "minimap")
    then
        store.clear_minimap_spans(provider, bufnr)
        return false
    end

    local success = store.set_minimap_spans(provider, bufnr, spans)
    return success
end

---@param entry ScrollbarManagedProvider
---@param winid integer
---@param points any
---@return boolean
local function publish_minimap_points(entry, winid, points)
    local provider = entry.provider.name
    if
        type(winid) == "number"
        and vim.api.nvim_win_is_valid(winid)
        and not is_source_window(entry, winid, "minimap")
    then
        store.clear_minimap_points(provider, winid)
        return false
    end

    local success = store.set_minimap_points(provider, winid, points)
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
    local provider_config = vim.deepcopy(manager.config)
    if entry.builtin then
        local planned = manager.provider_plan[provider_name]
        if planned ~= nil then
            provider_config.providers[provider_name] = vim.deepcopy(planned.options)
        end
    end

    return {
        config = provider_config,
        set_marks = function(bufnr, marks)
            return publish_buffer(entry, bufnr, marks)
        end,
        _set_search_compact = function(bufnr, compact)
            return publish_search_compact(entry, bufnr, compact)
        end,
        clear_marks = function(bufnr)
            local changed
            if bufnr == nil then
                changed = store._clear_marks_provider(provider_name)
            else
                changed = store.clear(provider_name, bufnr)
            end
            return next(changed) ~= nil
        end,
        set_minimap_spans = function(bufnr, spans)
            return publish_minimap_spans(entry, bufnr, spans)
        end,
        clear_minimap_spans = function(bufnr)
            local changed
            if bufnr == nil then
                changed = store._clear_minimap_spans_provider(provider_name)
            else
                changed = store.clear_minimap_spans(provider_name, bufnr)
            end
            return next(changed) ~= nil
        end,
        set_window_marks = function(winid, marks)
            return publish_window(entry, winid, marks)
        end,
        clear_window_marks = function(winid)
            local changed
            if winid == nil then
                changed = store._clear_window_marks_provider(provider_name)
            else
                changed = store.clear_window(provider_name, winid)
            end
            return next(changed) ~= nil
        end,
        set_minimap_points = function(winid, points)
            return publish_minimap_points(entry, winid, points)
        end,
        clear_minimap_points = function(winid)
            local changed
            if winid == nil then
                changed = store._clear_minimap_points_provider(provider_name)
            else
                changed = store.clear_minimap_points(provider_name, winid)
            end
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
            return source_windows(entry, bufnr)
        end,
        is_buffer_eligible = function(bufnr)
            return is_buffer_eligible(entry, bufnr)
        end,
        is_source_window = function(winid)
            return is_source_window(entry, winid)
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

---@param entry ScrollbarManagedProvider
---@return integer[]
local function eligible_buffers(entry)
    assert(manager ~= nil, "provider manager is not set up")
    local buffers = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if is_buffer_eligible(entry, bufnr) then
            table.insert(buffers, bufnr)
        end
    end
    table.sort(buffers)
    return buffers
end

---@param entry ScrollbarManagedProvider
---@return integer[]
local function eligible_windows(entry)
    assert(manager ~= nil, "provider manager is not set up")
    local windows = {}
    for _, winid in ipairs(source_windows(entry)) do
        if is_source_window(entry, winid) then
            table.insert(windows, winid)
        end
    end
    table.sort(windows)
    return windows
end

---@param entry ScrollbarManagedProvider
---@param bufnr integer
---@param consumer? "scrollbar"|"minimap"
---@return boolean
local function refresh_entry(entry, bufnr, consumer)
    if manager == nil or not entry.setup_ok or entry.provider.refresh == nil then
        return false
    end
    if not is_buffer_eligible(entry, bufnr, consumer) then
        if not is_buffer_eligible(entry, bufnr) then
            store.clear(entry.provider.name, bufnr)
        end
        return false
    end

    local operation = "refresh for buffer " .. bufnr
    local ok, marks = pcall(entry.provider.refresh, bufnr, entry.context)
    if not ok then
        store.clear(entry.provider.name, bufnr)
        warn_once(entry.provider.name, operation, tostring(marks))
        return false
    end

    reset_warnings(entry.provider.name, operation)
    if not is_buffer_eligible(entry, bufnr, consumer) then
        if not is_buffer_eligible(entry, bufnr) then
            store.clear(entry.provider.name, bufnr)
        end
        return false
    end
    if marks == nil then
        return true
    end

    return publish_buffer(entry, bufnr, marks, consumer)
end

---@param entry ScrollbarManagedProvider
---@param bufnr integer
---@return boolean
local function refresh_minimap_entry(entry, bufnr)
    if manager == nil or not entry.setup_ok or entry.provider.refresh_minimap == nil then
        return false
    end
    if not is_buffer_eligible(entry, bufnr, "minimap") then
        store.clear_minimap_spans(entry.provider.name, bufnr)
        return false
    end

    local operation = "minimap refresh for buffer " .. bufnr
    local ok, spans = pcall(entry.provider.refresh_minimap, bufnr, entry.context)
    if not ok then
        store.clear_minimap_spans(entry.provider.name, bufnr)
        warn_once(entry.provider.name, operation, tostring(spans))
        return false
    end

    reset_warnings(entry.provider.name, operation)
    if not is_buffer_eligible(entry, bufnr, "minimap") then
        store.clear_minimap_spans(entry.provider.name, bufnr)
        return false
    end
    if spans == nil then
        return true
    end

    return publish_minimap_spans(entry, bufnr, spans)
end

---@param entry ScrollbarManagedProvider
---@param winid integer
---@param consumer? "scrollbar"|"minimap"
---@return boolean
local function refresh_window_entry(entry, winid, consumer)
    if manager == nil or not entry.setup_ok or entry.provider.refresh_window == nil then
        return false
    end
    if not is_source_window(entry, winid, consumer) then
        if not is_source_window(entry, winid) then
            store.clear_window(entry.provider.name, winid)
        end
        return false
    end

    local operation = "window refresh for window " .. winid
    local ok, marks = pcall(entry.provider.refresh_window, winid, entry.context)
    if not ok then
        store.clear_window(entry.provider.name, winid)
        warn_once(entry.provider.name, operation, tostring(marks))
        return false
    end

    reset_warnings(entry.provider.name, operation)
    if not is_source_window(entry, winid, consumer) then
        if not is_source_window(entry, winid) then
            store.clear_window(entry.provider.name, winid)
        end
        return false
    end
    if marks == nil then
        return true
    end

    return publish_window(entry, winid, marks, consumer)
end

---@param entry ScrollbarManagedProvider
---@param winid integer
---@return boolean
local function refresh_minimap_window_entry(entry, winid)
    if manager == nil or not entry.setup_ok or entry.provider.refresh_minimap_window == nil then
        return false
    end
    if not is_source_window(entry, winid, "minimap") then
        store.clear_minimap_points(entry.provider.name, winid)
        return false
    end

    local operation = "minimap window refresh for window " .. winid
    local ok, points = pcall(entry.provider.refresh_minimap_window, winid, entry.context)
    if not ok then
        store.clear_minimap_points(entry.provider.name, winid)
        warn_once(entry.provider.name, operation, tostring(points))
        return false
    end

    reset_warnings(entry.provider.name, operation)
    if not is_source_window(entry, winid, "minimap") then
        store.clear_minimap_points(entry.provider.name, winid)
        return false
    end
    if points == nil then
        return true
    end

    return publish_minimap_points(entry, winid, points)
end

---@type fun(entry: ScrollbarManagedProvider)
local release_resources

---@param entry ScrollbarManagedProvider
local function activate_entry(entry)
    if not is_active(entry) then
        store.clear_provider(entry.provider.name)
        store.clear_window_provider(entry.provider.name)
        return
    end

    entry.context = make_context(entry)
    entry.setup_ok = false
    if entry.provider.setup ~= nil then
        local ok, err = pcall(entry.provider.setup, entry.context)
        if not ok then
            release_resources(entry)
            store.clear_provider(entry.provider.name)
            store.clear_window_provider(entry.provider.name)
            warn_once(entry.provider.name, "setup", tostring(err))
            return
        end
        reset_warnings(entry.provider.name, "setup")
    end
    entry.setup_ok = true

    for _, bufnr in ipairs(eligible_buffers(entry)) do
        refresh_entry(entry, bufnr)
        refresh_minimap_entry(entry, bufnr)
    end
    for _, winid in ipairs(eligible_windows(entry)) do
        refresh_window_entry(entry, winid)
        refresh_minimap_window_entry(entry, winid)
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
    store.clear_provider(entry.provider.name)
    store.clear_window_provider(entry.provider.name)
    entry.context = nil
    entry.setup_ok = false
end

---@param provider ScrollbarProvider
---@return ScrollbarProviderTargets
local function normalize_targets(provider)
    if provider.targets == nil then
        return { scrollbar = true, minimap = false }
    end
    if type(provider.targets) ~= "table" then
        error(string.format("[scrollbar.nvim] provider '%s' targets must be a table", provider.name), 3)
    end

    local unknown_target
    for target in pairs(provider.targets) do
        if target ~= "scrollbar" and target ~= "minimap" then
            local target_name = type(target) == "string" and target or "<" .. type(target) .. ">"
            if unknown_target == nil or target_name < unknown_target then
                unknown_target = target_name
            end
        end
    end
    if unknown_target ~= nil then
        error(
            string.format(
                "[scrollbar.nvim] provider '%s' targets has unknown target '%s'",
                provider.name,
                unknown_target
            ),
            3
        )
    end

    for _, target in ipairs({ "scrollbar", "minimap" }) do
        local enabled = provider.targets[target]
        if enabled ~= nil and type(enabled) ~= "boolean" then
            error(
                string.format("[scrollbar.nvim] provider '%s' targets.%s must be a boolean", provider.name, target),
                3
            )
        end
    end

    local targets = {
        scrollbar = provider.targets.scrollbar == true,
        minimap = provider.targets.minimap == true,
    }
    if not targets.scrollbar and not targets.minimap then
        error(string.format("[scrollbar.nvim] provider '%s' targets must enable at least one target", provider.name), 3)
    end
    return targets
end

---@param provider ScrollbarProvider
---@param builtin boolean
local function register(provider, builtin)
    if type(provider) ~= "table" then
        error("[scrollbar.nvim] provider must be a table", 3)
    end
    if type(provider.name) ~= "string" or provider.name == "" then
        error("[scrollbar.nvim] provider name must be a non-empty string", 3)
    end
    local targets = normalize_targets(provider)
    for _, field in ipairs({
        "setup",
        "refresh",
        "refresh_window",
        "refresh_minimap",
        "refresh_minimap_window",
        "dispose",
    }) do
        if provider[field] ~= nil and type(provider[field]) ~= "function" then
            error(string.format("[scrollbar.nvim] provider '%s' %s must be a function", provider.name, field), 3)
        end
    end
    if provider.refresh_owner ~= nil and type(provider.refresh_owner) ~= "table" then
        error(string.format("[scrollbar.nvim] provider '%s' refresh_owner must be a table", provider.name), 3)
    end
    local refresh_owner = provider.refresh_owner or {}
    local unknown_scope
    for scope in pairs(refresh_owner) do
        if scope ~= "buffer" and scope ~= "window" and scope ~= "minimap_buffer" and scope ~= "minimap_window" then
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
            3
        )
    end
    for _, scope in ipairs({ "buffer", "window", "minimap_buffer", "minimap_window" }) do
        local owner = refresh_owner[scope]
        if owner ~= "manager" and owner ~= "provider" then
            if owner ~= nil then
                error(
                    string.format(
                        "[scrollbar.nvim] provider '%s' refresh_owner.%s must be 'manager' or 'provider'",
                        provider.name,
                        scope
                    ),
                    3
                )
            end
        end
    end
    if provider.refresh ~= nil and refresh_owner.buffer == nil then
        error(string.format("[scrollbar.nvim] provider '%s' refresh requires refresh_owner.buffer", provider.name), 3)
    end
    if provider.refresh_window ~= nil and refresh_owner.window == nil then
        error(
            string.format("[scrollbar.nvim] provider '%s' refresh_window requires refresh_owner.window", provider.name),
            3
        )
    end
    if provider.refresh_minimap ~= nil and refresh_owner.minimap_buffer == nil then
        error(
            string.format(
                "[scrollbar.nvim] provider '%s' refresh_minimap requires refresh_owner.minimap_buffer",
                provider.name
            ),
            3
        )
    end
    if provider.refresh_minimap_window ~= nil and refresh_owner.minimap_window == nil then
        error(
            string.format(
                "[scrollbar.nvim] provider '%s' refresh_minimap_window requires refresh_owner.minimap_window",
                provider.name
            ),
            3
        )
    end
    if refresh_owner.buffer ~= nil and provider.refresh == nil then
        error(string.format("[scrollbar.nvim] provider '%s' refresh_owner.buffer requires refresh", provider.name), 3)
    end
    if refresh_owner.window ~= nil and provider.refresh_window == nil then
        error(
            string.format("[scrollbar.nvim] provider '%s' refresh_owner.window requires refresh_window", provider.name),
            3
        )
    end
    if refresh_owner.minimap_buffer ~= nil and provider.refresh_minimap == nil then
        error(
            string.format(
                "[scrollbar.nvim] provider '%s' refresh_owner.minimap_buffer requires refresh_minimap",
                provider.name
            ),
            3
        )
    end
    if refresh_owner.minimap_window ~= nil and provider.refresh_minimap_window == nil then
        error(
            string.format(
                "[scrollbar.nvim] provider '%s' refresh_owner.minimap_window requires refresh_minimap_window",
                provider.name
            ),
            3
        )
    end
    if provider.refresh_minimap ~= nil and not targets.minimap then
        error(
            string.format("[scrollbar.nvim] provider '%s' refresh_minimap requires targets.minimap", provider.name),
            3
        )
    end
    if provider.refresh_minimap_window ~= nil and not targets.minimap then
        error(
            string.format(
                "[scrollbar.nvim] provider '%s' refresh_minimap_window requires targets.minimap",
                provider.name
            ),
            3
        )
    end
    if registry[provider.name] ~= nil then
        error(string.format("[scrollbar.nvim] provider '%s' is already registered", provider.name), 3)
    end

    local entry = {
        provider = provider,
        setup_ok = false,
        augroups = {},
        cleanups = {},
        targets = targets,
        builtin = builtin,
    }
    registry[provider.name] = entry
    table.insert(order, provider.name)

    if manager ~= nil and is_active(entry) then
        activate_entry(entry)
    end
end

---@param provider ScrollbarProvider
M.register = function(provider)
    register(provider, false)
end

---@param provider ScrollbarProvider
M._register_builtin = function(provider)
    register(provider, true)
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

---@param name string
---@param consumer "scrollbar"|"minimap"
---@return boolean
M._consumer_enabled = function(name, consumer)
    local entry = registry[name]
    if entry ~= nil and not entry.builtin then
        return entry.targets[consumer] == true
    end
    if entry ~= nil and manager ~= nil then
        return requested_consumers(entry)[consumer] == true
    end

    local planned = config.get_provider_plan()[name]
    return planned ~= nil and planned.options ~= false and planned.consumers[consumer] == true
end

---@param name string
---@return ScrollbarProviderExecutionMode
M._execution_mode = function(name)
    local entry = registry[name]
    if entry ~= nil and not entry.builtin then
        return "parent"
    end
    if entry ~= nil and manager ~= nil then
        local planned = manager.provider_plan[name]
        return planned and planned.execution or "parent"
    end

    local planned = config.get_provider_plan()[name]
    return planned and planned.execution or "parent"
end

---@param options any
---@param channels table<string, true>
---@return ScrollbarProviderRefreshOptions
local function validate_refresh_options(options, channels)
    if options == nil then
        return {}
    end
    if type(options) ~= "table" then
        error("[scrollbar.nvim] provider refresh options must be a table", 3)
    end
    local unknown
    for key in pairs(options) do
        if key ~= "consumer" and key ~= "channel" then
            local name = type(key) == "string" and key or "<" .. type(key) .. ">"
            if unknown == nil or name < unknown then
                unknown = name
            end
        end
    end
    if unknown ~= nil then
        error(string.format("[scrollbar.nvim] provider refresh options has unknown field '%s'", unknown), 3)
    end
    if options.consumer ~= nil and options.consumer ~= "scrollbar" and options.consumer ~= "minimap" then
        error("[scrollbar.nvim] provider refresh options.consumer must be 'scrollbar' or 'minimap'", 3)
    end
    if options.channel ~= nil and not channels[options.channel] then
        local allowed = vim.tbl_keys(channels)
        table.sort(allowed)
        error(
            string.format(
                "[scrollbar.nvim] provider refresh options.channel must be one of: %s",
                table.concat(allowed, ", ")
            ),
            3
        )
    end
    return options
end

---@param entry ScrollbarManagedProvider
---@param options ScrollbarProviderRefreshOptions
---@param channel ScrollbarStoreChannel
---@return boolean
local function refresh_matches(entry, options, channel)
    if options.channel ~= nil and options.channel ~= channel then
        return false
    end

    local consumers = requested_consumers(entry)
    if channel == "minimap_spans" or channel == "minimap_points" then
        return consumers.minimap and (options.consumer == nil or options.consumer == "minimap")
    end
    if options.consumer ~= nil then
        return consumers[options.consumer]
    end
    return consumers.scrollbar or consumers.minimap
end

---@param bufnr integer
---@param options? ScrollbarProviderRefreshOptions
---@return boolean
M.refresh = function(bufnr, options)
    if manager == nil then
        return false
    end
    options = validate_refresh_options(options, { marks = true, minimap_spans = true })

    local refreshed = false
    for _, name in ipairs(order) do
        local entry = registry[name]
        if refresh_matches(entry, options, "marks") then
            refreshed = refresh_entry(entry, bufnr, options.consumer) or refreshed
        end
        if refresh_matches(entry, options, "minimap_spans") then
            refreshed = refresh_minimap_entry(entry, bufnr) or refreshed
        end
    end
    return refreshed
end

---@param winid integer
---@param options? ScrollbarProviderRefreshOptions
---@return boolean
M.refresh_window = function(winid, options)
    if manager == nil then
        return false
    end
    options = validate_refresh_options(options, { marks = true, minimap_points = true })

    local refreshed = false
    for _, name in ipairs(order) do
        local entry = registry[name]
        if refresh_matches(entry, options, "marks") then
            refreshed = refresh_window_entry(entry, winid, options.consumer) or refreshed
        end
        if refresh_matches(entry, options, "minimap_points") then
            refreshed = refresh_minimap_window_entry(entry, winid) or refreshed
        end
    end
    return refreshed
end

---@param options? ScrollbarProviderManagerOptions
M.setup = function(options)
    options = options or {}
    M.dispose()

    local active_config = vim.deepcopy(options.config or config.get())
    local renderer = require("scrollbar.renderer")
    local minimap_renderer = require("scrollbar.minimap.renderer")
    local supplied_policies = options.consumer_policies or {}
    local scrollbar_policy = supplied_policies.scrollbar or {}
    local minimap_policy = supplied_policies.minimap or {}
    manager = {
        config = active_config,
        provider_plan = vim.deepcopy(options.provider_plan or config.get_provider_plan()),
        consumer_policies = {
            scrollbar = {
                source_windows = scrollbar_policy.source_windows or options.source_windows or renderer.source_windows,
                is_buffer_eligible = scrollbar_policy.is_buffer_eligible
                    or options.is_buffer_eligible
                    or renderer.is_buffer_eligible,
                is_source_window = scrollbar_policy.is_source_window
                    or options.is_source_window
                    or renderer.is_source_window,
            },
            minimap = {
                source_windows = minimap_policy.source_windows or minimap_renderer.source_windows,
                is_buffer_eligible = minimap_policy.is_buffer_eligible or minimap_renderer.is_buffer_eligible,
                is_source_window = minimap_policy.is_source_window or minimap_renderer.is_source_window,
            },
        },
        invalidate_buffer = options.invalidate_buffer or noop,
        invalidate_window = options.invalidate_window or noop,
    }
    if options.invalidate_buffer ~= nil or options.invalidate_window ~= nil then
        legacy_unsubscribe = store.subscribe(function(event)
            if manager == nil or event.channel ~= "marks" then
                return
            end
            if event.scope == "buffer" then
                guarded_callback(manager.invalidate_buffer, event.target)
            else
                guarded_callback(manager.invalidate_window, event.target)
            end
        end)
    end

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
                if ownership ~= nil and ownership.minimap_buffer == "manager" then
                    refresh_minimap_entry(entry, args.buf)
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
            for _, name in ipairs(order) do
                local entry = registry[name]
                local ownership = entry.provider.refresh_owner
                if ownership ~= nil and ownership.window == "manager" then
                    if args.event == "BufWinEnter" then
                        store.clear_window(entry.provider.name, winid)
                    end
                    refresh_window_entry(entry, winid)
                end
                if ownership ~= nil and ownership.minimap_window == "manager" then
                    if args.event == "BufWinEnter" then
                        store.clear_minimap_points(entry.provider.name, winid)
                    end
                    refresh_minimap_window_entry(entry, winid)
                end
            end
        end,
    })

    for _, name in ipairs(order) do
        local entry = registry[name]
        if is_active(entry) then
            activate_entry(entry)
        else
            store.clear_provider(entry.provider.name)
            store.clear_window_provider(entry.provider.name)
        end
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
    if legacy_unsubscribe ~= nil then
        legacy_unsubscribe()
        legacy_unsubscribe = nil
    end
    manager = nil
end

return M
