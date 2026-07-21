local config = require("scrollbar.config")
local minimap = require("scrollbar.minimap")
local minimap_renderer = require("scrollbar.minimap.renderer")
local minimap_scheduler = require("scrollbar.minimap.scheduler")
local mouse = require("scrollbar.mouse")
local providers = require("scrollbar.providers")
local renderer = require("scrollbar.renderer")
local scheduler = require("scrollbar.scheduler")
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
    minimap.dispose()
    mouse.dispose()
    scheduler.dispose()
    providers.dispose()
    renderer.dispose()
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

local function create_commands()
    vim.api.nvim_create_user_command("ScrollbarShow", M.show, { force = true })
    vim.api.nvim_create_user_command("ScrollbarHide", M.hide, { force = true })
    vim.api.nvim_create_user_command("ScrollbarToggle", M.toggle, { force = true })
    vim.api.nvim_create_user_command("ScrollbarRefresh", M.refresh, { force = true })
end

---@param overrides? ScrollbarTopLevelConfig
M.setup = function(overrides)
    local active_config = config.set(overrides)
    local active_minimap_config = config.get_minimap()
    local provider_plan = config.get_provider_plan()
    dispose_runtime()
    reconcile_builtins(provider_plan)

    if active_config.set_highlights then
        utils.set_highlights()
    end
    create_commands()

    renderer.setup()
    scheduler.setup({ config = active_config, renderer = renderer })
    mouse.setup({ config = active_config, renderer = renderer, scheduler = scheduler })

    -- Both store consumers must be subscribed before provider setup publishes.
    minimap.setup()
    providers.setup({
        config = active_config,
        provider_plan = provider_plan,
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

M.show = function()
    renderer.show()
    if config.get().autohide.enabled then
        scheduler.reveal_all()
    else
        scheduler.invalidate_all()
    end
end

M.hide = function()
    renderer.hide()
    scheduler.clear_deadlines()
end

M.toggle = function()
    if renderer.is_visible() then
        M.hide()
    else
        M.show()
    end
end

M.refresh = function()
    local buffers = {}
    local windows = renderer.source_windows()
    for _, winid in ipairs(windows) do
        if vim.api.nvim_win_is_valid(winid) then
            buffers[vim.api.nvim_win_get_buf(winid)] = true
        end
    end
    for bufnr in pairs(buffers) do
        providers.refresh(bufnr, { consumer = "scrollbar" })
    end
    for _, winid in ipairs(windows) do
        providers.refresh_window(winid, { consumer = "scrollbar" })
    end
    scheduler.invalidate_all()
end

return M
