local config = require("scrollbar.config")
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
    { name = "ale", module = "scrollbar.providers.ale" },
    { name = "coc", module = "scrollbar.providers.coc" },
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
    mouse.dispose()
    scheduler.dispose()
    providers.dispose()
    renderer.dispose()
    remove_orphaned_renderer_resources()
end

---@param active_config ScrollbarConfig
local function reconcile_builtins(active_config)
    for _, builtin in ipairs(BUILTINS) do
        local name = builtin.name
        local registered = providers.get(name)
        local owned = owned_builtins[name]
        if owned ~= nil and registered ~= owned then
            owned_builtins[name] = nil
        end

        local enabled = active_config.providers[name] ~= false
        if enabled and registered == nil then
            local provider = require(builtin.module)
            providers.register(provider)
            owned_builtins[name] = provider
        elseif not enabled and registered ~= nil and owned_builtins[name] == registered then
            providers.unregister(name)
            owned_builtins[name] = nil
        end
    end
end

---@param bufnr integer
---@param active_config ScrollbarConfig
---@return boolean
local function is_buffer_eligible(bufnr, active_config)
    if
        not vim.api.nvim_buf_is_valid(bufnr)
        or not vim.api.nvim_buf_is_loaded(bufnr)
        or renderer.is_owned_buffer(bufnr)
    then
        return false
    end
    if vim.tbl_contains(active_config.excluded_buftypes, vim.bo[bufnr].buftype) then
        return false
    end
    if vim.tbl_contains(active_config.excluded_filetypes, vim.bo[bufnr].filetype) then
        return false
    end
    return active_config.max_lines == false or vim.api.nvim_buf_line_count(bufnr) <= active_config.max_lines
end

local function create_commands()
    vim.api.nvim_create_user_command("ScrollbarShow", M.show, { force = true })
    vim.api.nvim_create_user_command("ScrollbarHide", M.hide, { force = true })
    vim.api.nvim_create_user_command("ScrollbarToggle", M.toggle, { force = true })
    vim.api.nvim_create_user_command("ScrollbarRefresh", M.refresh, { force = true })
end

---@param overrides? ScrollbarUserConfig
M.setup = function(overrides)
    local active_config = config.set(overrides)
    dispose_runtime()
    reconcile_builtins(active_config)

    if active_config.set_highlights then
        utils.set_highlights()
    end
    create_commands()

    renderer.setup()
    scheduler.setup({ config = active_config, renderer = renderer })
    mouse.setup({ config = active_config, renderer = renderer, scheduler = scheduler })
    providers.setup({
        config = active_config,
        invalidate_buffer = scheduler.invalidate_buffer,
        invalidate_window = scheduler.invalidate_window,
        source_windows = renderer.source_windows,
        is_buffer_eligible = function(bufnr)
            return is_buffer_eligible(bufnr, active_config)
        end,
    })
    scheduler.invalidate_all()
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
        providers.refresh(bufnr)
    end
    for _, winid in ipairs(windows) do
        providers.refresh_window(winid)
    end
    scheduler.invalidate_all()
end

return M
