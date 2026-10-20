--- Render scheduler of the minimap, built on `scrollbar.scheduler_core`.
---
--- Coalesces invalidations within `minimap.throttle_ms` (default 50) from
--- mirror changes (worker callbacks), viewport changes (`WinScrolled` on
--- source windows), shared store mark/span/point notifications, and
--- eligibility changes.
---
--- Autohide hide-timer logic is engaged only when `minimap.autohide` is
--- enabled; otherwise the timers are not created and the hold/resume API is a
--- no-op.

local config = require("scrollbar.minimap.config")
local scheduler_core = require("scrollbar.scheduler_core")

local M = {}

-- The minimap `OptionSet` row has no default pattern: without a configured
-- pattern it renders all windows when any option changes, as documented.
local core = scheduler_core.new({
    augroup = "ScrollbarMinimapScheduler",
    label = "minimap ",
    consumer = "minimap",
    api = M,
})

---@return boolean
local function any_variant_shows_marks()
    for _, variant in ipairs(config.get_variants()) do
        if next(variant.config.marks) ~= nil then
            return true
        end
    end
    return false
end

---@param options? ScrollbarMinimapSchedulerOptions
M.setup = function(options)
    options = options or {}
    local channels = { minimap_spans = true, minimap_points = true }
    -- Mark notifications matter only when a variant shows mark types.
    if any_variant_shows_marks() then
        channels.marks = true
    end
    core.setup({
        config = options.config or config.get(),
        renderer = options.renderer or require("scrollbar.minimap.renderer"),
        on_colorscheme = options.on_colorscheme or function() end,
        channels = channels,
        peers = options.peers,
        -- Ride the scrollbar scheduler's shared TextChanged dispatch when
        -- wired: one autocmd invocation per keystroke covers both schedulers.
        -- Without the dispatch (standalone setups) the minimap keeps its own
        -- text rows.
        on_text_change = options.on_text_change,
    })
end

M.invalidate_window = core.invalidate_window
M.invalidate_buffer = core.invalidate_buffer
M.invalidate_all = core.invalidate_all
M.reveal_all = core.reveal_all
M.clear_deadlines = core.clear_deadlines
M.hold_window = core.hold_window
M.resume_window = core.resume_window
M.flush = core.flush
M.status = core.status
M.dispose = core.dispose

return M
