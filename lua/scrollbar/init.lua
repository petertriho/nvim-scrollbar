local config = require("scrollbar.config")
local deferred_start = require("scrollbar.shared.deferred_start")
local highlights = require("scrollbar.highlights")
local mouse = require("scrollbar.mouse")
local navigate_config = require("scrollbar.config.navigate")
local providers = require("scrollbar.providers")
local renderer = require("scrollbar.renderer")
local scheduler = require("scrollbar.scheduler")
local stack = require("scrollbar.shared.stack")
local text_tick = require("scrollbar.shared.text_tick")

local M = {}

local BUILTINS = {
    { name = "cursor", module = "scrollbar.providers.cursor" },
    { name = "diagnostic", module = "scrollbar.providers.diagnostic" },
    { name = "search", module = "scrollbar.providers.search" },
    { name = "marks", module = "scrollbar.providers.marks" },
    { name = "gitsigns", module = "scrollbar.providers.gitsigns" },
    { name = "mini_diff", module = "scrollbar.providers.mini_diff" },
    { name = "signify", module = "scrollbar.providers.signify" },
    { name = "vgit", module = "scrollbar.providers.vgit" },
    { name = "ale", module = "scrollbar.providers.ale" },
    { name = "coc", module = "scrollbar.providers.coc" },
    { name = "qflist", module = "scrollbar.providers.qflist" },
    { name = "loclist", module = "scrollbar.providers.loclist" },
    { name = "treesitter", module = "scrollbar.providers.treesitter" },
    { name = "lsp_semantic_tokens", module = "scrollbar.providers.lsp_semantic_tokens" },
}

---@type table<string, ScrollbarProvider>
local owned_builtins = {}

-- The minimap modules load only when the minimap is enabled, or when a
-- provider asks for the minimap source windows. A minimap that is not loaded
-- has no floats.
local MINIMAP_RENDERER = "scrollbar.minimap.renderer"

---@type ScrollbarSchedulerPeer
local minimap_peer = {
    is_owned_float_buffer = function(bufnr)
        local minimap_renderer = package.loaded[MINIMAP_RENDERER]
        return minimap_renderer ~= nil and minimap_renderer.is_owned_float_buffer(bufnr)
    end,
    is_owned_float_window = function(winid)
        local minimap_renderer = package.loaded[MINIMAP_RENDERER]
        return minimap_renderer ~= nil and minimap_renderer.is_owned_float_window(winid)
    end,
}

---@param name string
---@return function
local function minimap_policy(name)
    return function(...)
        return require(MINIMAP_RENDERER)[name](...)
    end
end

local function remove_orphaned_renderer_resources()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if renderer.is_owned_window(winid) then
            pcall(vim.api.nvim_win_close, winid, true)
        end
    end
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if renderer.is_owned_buffer(bufnr) then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
    end
end

--- Close the label mode, the glance window, and the peek float, and forget
--- the notifications of the frame functions.
local function dispose_navigate()
    local jump = package.loaded["scrollbar.navigate.jump"]
    if jump ~= nil then
        jump.cancel()
    end
    local glance = package.loaded["scrollbar.navigate.glance"]
    if glance ~= nil then
        glance.close(true)
    end
    local peek = package.loaded["scrollbar.navigate.peek"]
    if peek ~= nil then
        peek.close()
    end
    local frame = package.loaded["scrollbar.navigate.frame"]
    if frame ~= nil then
        frame.reset()
    end
end

local function dispose_runtime()
    dispose_navigate()
    -- Both renderers close every float, so nothing needs to move first.
    stack.reset()
    local minimap = package.loaded["scrollbar.minimap"]
    if minimap ~= nil then
        minimap.dispose()
    end
    local hover = package.loaded["scrollbar.navigate.hover"]
    if hover ~= nil then
        hover.dispose()
    end
    mouse.dispose()
    scheduler.dispose()
    providers.dispose()
    renderer.dispose()
    text_tick.dispose()
    remove_orphaned_renderer_resources()
end

---@param provider_plan ScrollbarEffectiveProviderPlan
local function reconcile_builtins(provider_plan)
    for _, builtin in ipairs(BUILTINS) do
        local name = builtin.name
        local registered = providers.get(name)
        local owned = owned_builtins[name]
        if owned ~= nil and registered ~= owned then
            owned_builtins[name] = nil
        end

        local planned = provider_plan[name]
        local enabled = planned ~= nil and planned.options ~= false
        if enabled and registered == nil then
            local provider = require(builtin.module)
            providers._register_builtin(provider)
            owned_builtins[name] = provider
        elseif not enabled and registered ~= nil and owned_builtins[name] == registered then
            providers.unregister(name)
            owned_builtins[name] = nil
        end
    end
end

local COMMANDS = {
    ScrollbarShow = "show",
    ScrollbarHide = "hide",
    ScrollbarToggle = "toggle",
    ScrollbarRefresh = "refresh",
}

-- Whether `setup()` ran. `jump()` and `glance()` need it.
local configured = false

---@param message string
---@param level integer
local function notify(message, level)
    vim.notify("[nvim-scrollbar] " .. message, level)
end

---@class ScrollbarNavigateUserOptions
---@field types? string[] Names of registered mark types. Nil means every type except `Cursor`

---@class ScrollbarGlanceUserOptions: ScrollbarNavigateUserOptions
---@field picker? ScrollbarGlancePicker Picker of this call. Nil uses `glance.picker`

-- The options of each method.
local NAVIGATE_OPTIONS = {
    jump = { types = true },
    glance = { types = true, picker = true },
}

--- The mark type filter of `jump()` and `glance()`, or nothing when the
--- options are not valid.
---@param name "jump"|"glance"
---@param opts any
---@return boolean ok
---@return table<string, true>? types
local function navigate_types(name, opts)
    if not configured then
        notify(name .. "() needs setup() first", vim.log.levels.WARN)
        return false
    end
    if opts == nil then
        return true
    end
    if type(opts) ~= "table" then
        notify(name .. "(): opts must be a table", vim.log.levels.ERROR)
        return false
    end
    for key in pairs(opts) do
        if not NAVIGATE_OPTIONS[name][key] then
            notify(string.format("%s(): unknown option '%s'", name, tostring(key)), vim.log.levels.ERROR)
            return false
        end
    end
    if opts.picker ~= nil and not navigate_config.is_glance_picker(opts.picker) then
        notify(name .. "(): opts.picker " .. navigate_config.GLANCE_PICKER_MESSAGE, vim.log.levels.ERROR)
        return false
    end
    if opts.types == nil then
        return true
    end
    if type(opts.types) ~= "table" or not vim.islist(opts.types) then
        notify(name .. "(): opts.types must be a list of mark type names", vim.log.levels.ERROR)
        return false
    end
    local registered = config.get_mark_types()
    local types = {}
    for _, mark_type in ipairs(opts.types) do
        if type(mark_type) ~= "string" or registered[mark_type] == nil then
            notify(string.format("%s(): unknown mark type '%s'", name, tostring(mark_type)), vim.log.levels.ERROR)
            return false
        end
        types[mark_type] = true
    end
    return true, types
end

--- Label mode on the mark cells of the scrollbar of the current window.
---@param opts? ScrollbarNavigateUserOptions
M.jump = function(opts)
    deferred_start.run()
    local ok, types = navigate_types("jump", opts)
    if not ok then
        return
    end
    if not config.get().enabled then
        notify("jump() needs the scrollbar, and scrollbar.enabled is false", vim.log.levels.WARN)
        return
    end
    require("scrollbar.navigate.jump").run({ types = types })
end

--- The glance picker with the marks of the current window.
---@param opts? ScrollbarGlanceUserOptions
M.glance = function(opts)
    deferred_start.run()
    local ok, types = navigate_types("glance", opts)
    if not ok then
        return
    end
    require("scrollbar.navigate.glance").open({ types = types, picker = opts and opts.picker or nil })
end

---@param arg_lead string
---@return string[]
local function complete_mark_types(arg_lead)
    local names = {}
    for mark_type in pairs(config.get_mark_types()) do
        if vim.startswith(mark_type, arg_lead) then
            names[#names + 1] = mark_type
        end
    end
    table.sort(names)
    return names
end

---@param method "jump"|"glance"
---@return fun(args: { fargs: string[] })
local function navigate_command(method)
    return function(args)
        M[method]({ types = #args.fargs > 0 and args.fargs or nil })
    end
end

---@param enabled boolean
local function update_commands(enabled)
    for name, method in pairs(COMMANDS) do
        if enabled then
            vim.api.nvim_create_user_command(name, M[method], { force = true })
        else
            pcall(vim.api.nvim_del_user_command, name)
        end
    end
    if enabled then
        vim.api.nvim_create_user_command("ScrollbarJump", navigate_command("jump"), {
            force = true,
            nargs = "*",
            complete = complete_mark_types,
            desc = "Show labels on the marks of the scrollbar",
        })
    else
        pcall(vim.api.nvim_del_user_command, "ScrollbarJump")
    end
    vim.api.nvim_create_user_command("ScrollbarGlance", navigate_command("glance"), {
        force = true,
        nargs = "*",
        complete = complete_mark_types,
        desc = "Open the glance window with the marks of the current window",
    })
end

---@param active_config ScrollbarConfig
---@param active_minimap_config ScrollbarMinimapConfig
---@param provider_plan ScrollbarEffectiveProviderPlan
local function start_runtime(active_config, active_minimap_config, provider_plan)
    dispose_runtime()
    text_tick.setup()
    reconcile_builtins(provider_plan)

    -- The call also defines the blend-only groups when `set_highlights` is
    -- false.
    highlights.set_highlights()

    renderer.setup()
    -- Each scheduler ignores the floats of the other renderer: their own
    -- updates, such as the option toggles of a buffer rewrite, are not source
    -- activity.
    scheduler.setup({ config = active_config, renderer = renderer, peers = { minimap_peer } })
    stack.register("scrollbar", function(source_win)
        if renderer.reposition(source_win) then
            scheduler.invalidate_window(source_win)
        end
    end)
    mouse.setup({ config = active_config, renderer = renderer, scheduler = scheduler })
    if active_config.enabled and active_config.hover ~= false then
        require("scrollbar.navigate.hover").setup(active_config.hover)
    end

    -- Both store consumers must be subscribed before provider setup publishes.
    if active_minimap_config.enabled then
        local minimap = require("scrollbar.minimap")
        minimap.setup(nil, { on_text_change = scheduler.subscribe_text_change, peers = { renderer } })
    end
    providers.setup({
        config = active_config,
        provider_plan = provider_plan,
        on_text_change = scheduler.subscribe_text_change,
        on_cursor_activity = scheduler.subscribe_cursor_activity,
        consumer_policies = {
            scrollbar = {
                source_windows = renderer.source_windows,
                is_buffer_eligible = renderer.is_buffer_eligible,
                is_source_window = renderer.is_source_window,
                source_kind = renderer.source_kind,
            },
            minimap = {
                source_windows = minimap_policy("source_windows"),
                is_buffer_eligible = minimap_policy("is_buffer_eligible"),
                is_source_window = minimap_policy("is_source_window"),
                source_kind = minimap_policy("source_kind"),
            },
        },
    })
    scheduler.invalidate_all()
    if active_minimap_config.enabled then
        require("scrollbar.minimap.scheduler").invalidate_all()
    end
end

---@param overrides? ScrollbarUserConfig
M.setup = function(overrides)
    local active_config = config.set(overrides)
    local active_minimap_config = config.get_minimap()
    local provider_plan = config.get_provider_plan()
    configured = true
    update_commands(active_config.enabled)
    local function start()
        start_runtime(active_config, active_minimap_config, provider_plan)
    end
    -- During start-up, the runtime starts after the first screen. The
    -- highlight groups, the floats, and the provider data come one event loop
    -- iteration later, so the first screen does not wait for them. After
    -- start-up, for example when a plugin manager loads the plugin lazily,
    -- the runtime starts at once.
    if vim.v.vim_did_enter == 0 then
        deferred_start.defer(start)
        return
    end
    deferred_start.cancel()
    start()
end

local controls = require("scrollbar.shared.controls").new({
    renderer = renderer,
    scheduler = scheduler,
    consumer = "scrollbar",
    autohide = function()
        return config.get().autohide ~= false
    end,
    refresh_highlights = highlights.refresh_inactive,
})

M.show = function()
    deferred_start.run()
    controls.show()
end

M.hide = function()
    deferred_start.run()
    controls.hide()
end

M.toggle = function()
    deferred_start.run()
    controls.toggle()
end

M.refresh = function()
    deferred_start.run()
    controls.refresh()
end

return M
