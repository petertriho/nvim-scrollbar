--- Minimap lifecycle: wires config + worker + renderer + scheduler +
--- overlays + mouse into a single setup/dispose lifecycle, and registers
--- the user commands `MinimapShow`, `MinimapHide`, `MinimapToggle`,
--- `MinimapRefresh`. Mirrors `lua/scrollbar/init.lua` at a smaller scale.
---
--- The top-level dispatcher (`lua/scrollbar/init.lua`) calls
--- `require("scrollbar.minimap").setup(opts.minimap or {})` after the
--- scrollbar setup, and disposes both on reconfigure.
---
--- Default `minimap.enabled = false` means the dispatcher must early-return
--- without spawning the worker or creating floats when disabled.

local config = require("scrollbar.minimap.config")
local highlights = require("scrollbar.minimap.highlights")
local mouse = require("scrollbar.minimap.mouse")
local overlays = require("scrollbar.minimap.overlays")
local providers = require("scrollbar.providers")
local renderer = require("scrollbar.minimap.renderer")
local scheduler = require("scrollbar.minimap.scheduler")
local worker = require("scrollbar.minimap.worker")

local M = {}

local active_config
local COMMANDS = { "MinimapShow", "MinimapHide", "MinimapToggle", "MinimapRefresh" }

local function dispose_runtime()
    mouse.dispose()
    scheduler.dispose()
    overlays.dispose()
    renderer.dispose()
    worker.dispose()
    for _, name in ipairs(COMMANDS) do
        pcall(vim.api.nvim_del_user_command, name)
    end
end

local function create_commands()
    vim.api.nvim_create_user_command("MinimapShow", M.show, { force = true })
    vim.api.nvim_create_user_command("MinimapHide", M.hide, { force = true })
    vim.api.nvim_create_user_command("MinimapToggle", M.toggle, { force = true })
    vim.api.nvim_create_user_command("MinimapRefresh", M.refresh, { force = true })
end

---@param overrides? ScrollbarMinimapUserConfig
M.setup = function(overrides, wiring)
    local root_config
    if overrides == nil then
        -- Config was already validated by the top-level dispatcher.
        root_config = config.get()
    else
        root_config = config.set(overrides)
    end
    dispose_runtime()
    active_config = nil

    if not root_config.enabled then
        -- Disabled by default: do not spawn worker, scheduler, or floats.
        -- Commands still register so the user can toggle at runtime via
        -- a reconfigured setup; here we no-op.
        return root_config
    end

    active_config = root_config
    highlights.set()

    worker.setup({
        backend = root_config.backend,
        treesitter = root_config.providers.treesitter and providers._execution_mode("treesitter") == "worker",
        on_result = function(payload)
            renderer.handle_worker_result(payload)
            scheduler.invalidate_buffer(payload.bufnr)
        end,
        on_failure = function()
            renderer.handle_worker_failure()
        end,
    })
    overlays.setup({
        config = root_config,
    })
    renderer.setup({
        worker = worker,
        overlays = overlays,
        on_dirty = function(source_win)
            scheduler.invalidate_window(source_win)
        end,
    })
    scheduler.setup({
        config = root_config,
        renderer = renderer,
        on_colorscheme = function()
            highlights.set()
        end,
        on_text_change = wiring ~= nil and wiring.on_text_change or nil,
    })
    mouse.setup({
        renderer = renderer,
        scheduler = scheduler,
    })
    create_commands()
    return root_config
end

M.show = function()
    renderer.show()
    if active_config and active_config.autohide.enabled then
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
        providers.refresh(bufnr, { consumer = "minimap" })
    end
    for _, winid in ipairs(windows) do
        providers.refresh_window(winid, { consumer = "minimap" })
    end
    scheduler.invalidate_all()
end

M.dispose = function()
    dispose_runtime()
    active_config = nil
end

return M
