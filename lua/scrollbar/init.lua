local config = require("scrollbar.config")
local minimap = require("scrollbar.minimap")
local minimap_renderer = require("scrollbar.minimap.renderer")
local minimap_scheduler = require("scrollbar.minimap.scheduler")
local mouse = require("scrollbar.mouse")
local providers = require("scrollbar.providers")
local renderer = require("scrollbar.renderer")
local scheduler = require("scrollbar.scheduler")
local stack = require("scrollbar.stack")
local text_tick = require("scrollbar.text_tick")
local utils = require("scrollbar.utils")

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
    { name = "treesitter", module = "scrollbar.providers.treesitter" },
    { name = "lsp_semantic_tokens", module = "scrollbar.providers.lsp_semantic_tokens" },
}

---@type table<string, ScrollbarProvider>
local owned_builtins = {}

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

local function dispose_runtime()
    -- Both renderers close every float, so nothing needs to move first.
    stack.reset()
    minimap.dispose()
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

---@param enabled boolean
local function update_commands(enabled)
    for name, method in pairs(COMMANDS) do
        if enabled then
            vim.api.nvim_create_user_command(name, M[method], { force = true })
        else
            pcall(vim.api.nvim_del_user_command, name)
        end
    end
end

---@param overrides? ScrollbarUserConfig
M.setup = function(overrides)
    local active_config = config.set(overrides)
    local active_minimap_config = config.get_minimap()
    local provider_plan = config.get_provider_plan()
    dispose_runtime()
    text_tick.setup()
    reconcile_builtins(provider_plan)

    if active_config.set_highlights then
        utils.set_highlights()
    end
    update_commands(active_config.enabled)

    renderer.setup()
    -- Each scheduler ignores the floats of the other renderer: their own
    -- updates, such as the option toggles of a buffer rewrite, are not source
    -- activity.
    scheduler.setup({ config = active_config, renderer = renderer, peers = { minimap_renderer } })
    stack.register("scrollbar", function(source_win)
        if renderer.reposition(source_win) then
            scheduler.invalidate_window(source_win)
        end
    end)
    mouse.setup({ config = active_config, renderer = renderer, scheduler = scheduler })

    -- Both store consumers must be subscribed before provider setup publishes.
    minimap.setup(nil, { on_text_change = scheduler.subscribe_text_change, peers = { renderer } })
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
            },
            minimap = {
                source_windows = minimap_renderer.source_windows,
                is_buffer_eligible = minimap_renderer.is_buffer_eligible,
                is_source_window = minimap_renderer.is_source_window,
            },
        },
    })
    scheduler.invalidate_all()
    if active_minimap_config.enabled then
        minimap_scheduler.invalidate_all()
    end
end

local controls = require("scrollbar.controls").new({
    renderer = renderer,
    scheduler = scheduler,
    consumer = "scrollbar",
    autohide = function()
        return config.get().autohide ~= false
    end,
})

M.show = controls.show
M.hide = controls.hide
M.toggle = controls.toggle
M.refresh = controls.refresh

return M
