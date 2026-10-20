--- Minimap lifecycle: wires config + worker + renderer + scheduler +
--- overlays + mouse into a single setup/dispose lifecycle, and registers
--- the user commands `MinimapShow`, `MinimapHide`, `MinimapToggle`,
--- `MinimapRefresh`.
---
--- The top-level dispatcher (`lua/scrollbar/init.lua`) commits the minimap
--- configuration, calls `require("scrollbar.minimap").setup()`, and disposes
--- both subsystems on reconfigure.
---
--- Default `minimap.enabled = false` means the dispatcher must early-return
--- without spawning the worker or creating floats when disabled.

local config = require("scrollbar.minimap.config")
local controls_module = require("scrollbar.controls")
local highlights = require("scrollbar.minimap.highlights")
local mouse = require("scrollbar.minimap.mouse")
local overlays = require("scrollbar.minimap.overlays")
local providers = require("scrollbar.providers")
local renderer = require("scrollbar.minimap.renderer")
local scheduler = require("scrollbar.minimap.scheduler")
local stack = require("scrollbar.stack")
local worker = require("scrollbar.minimap.worker")

local M = {}

local active_config
local COMMANDS = { "MinimapShow", "MinimapHide", "MinimapToggle", "MinimapRefresh" }

local function dispose_runtime()
    stack.register("minimap", nil)
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

---@class ScrollbarMinimapWiring
---@field on_text_change? fun(fn: fun(args: table), events?: string[]): boolean Text dispatch of the scrollbar scheduler
---@field peers? ScrollbarSchedulerPeer[] Renderers whose floats the minimap scheduler ignores

---@param overrides? ScrollbarMinimapUserConfig
---@param wiring? ScrollbarMinimapWiring
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
        -- Disabled by default: no worker, scheduler, floats, or commands. A
        -- later setup with `enabled = true` creates them.
        return root_config
    end

    active_config = root_config
    highlights.set()

    worker.setup({
        backend = root_config.backend,
        treesitter = providers._consumer_enabled("treesitter", "minimap")
            and providers._execution_mode("treesitter") == "worker",
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
        visible = root_config.show,
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
        peers = wiring ~= nil and wiring.peers or nil,
    })
    stack.register("minimap", renderer.reposition)
    mouse.setup({
        renderer = renderer,
        scheduler = scheduler,
    })
    create_commands()
    return root_config
end

local controls = controls_module.new({
    renderer = renderer,
    scheduler = scheduler,
    consumer = "minimap",
    autohide = function()
        return active_config ~= nil and active_config.autohide ~= false
    end,
})

M.show = controls.show
M.hide = controls.hide
M.toggle = controls.toggle
M.refresh = controls.refresh

M.dispose = function()
    dispose_runtime()
    active_config = nil
end

return M
