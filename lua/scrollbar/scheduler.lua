--- Render scheduler of the scrollbar, built on `scrollbar.shared.scheduler`. It
--- also hosts the text-change and cursor-activity dispatch that providers and
--- the minimap scheduler subscribe to.

local config = require("scrollbar.config")
local layout = require("scrollbar.layout")
local scheduler_core = require("scrollbar.shared.scheduler")

local M = {}

-- Window and buffer options whose changes can affect the layout of a rendered
-- scrollbar. `lua/scrollbar/layout.lua` keeps the subset that affects the
-- extent (EXTENT_OPTION_PATTERNS) for the digests of its screen-geometry
-- cache. This list is the superset for the OptionSet autocmd patterns. If
-- either list changes, keep this list a superset of the layout subset.
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
    "foldexpr",
    "foldignore",
    "foldlevel",
    "foldmarker",
    "foldmethod",
    "foldminlines",
    "foldnestmax",
    "laststatus",
    "linebreak",
    "list",
    "listchars",
    "number",
    "numberwidth",
    "relativenumber",
    "showbreak",
    "showtabline",
    "signcolumn",
    "smoothscroll",
    "statuscolumn",
    "statusline",
    "tabstop",
    "winbar",
    "wrap",
}

local STORE_CHANNELS = { marks = true }

local core = scheduler_core.new({
    augroup = "ScrollbarScheduler",
    label = "",
    consumer = "scrollbar",
    -- Options that affect the extent gate the digest cache of the layout. This
    -- callback clears the cache, so that the next render reads the options
    -- again immediately.
    on_option_set = function()
        layout.invalidate_screen_options()
    end,
    hub = true,
    api = M,
})

---@param options? ScrollbarSchedulerOptions
M.setup = function(options)
    options = options or {}
    local active_config = options.config or config.get()
    core.setup({
        config = active_config,
        renderer = options.renderer or require("scrollbar.renderer"),
        on_colorscheme = options.on_colorscheme or function()
            if active_config.set_highlights then
                require("scrollbar.highlights").set_highlights()
            end
        end,
        channels = STORE_CHANNELS,
        option_pattern = OPTION_PATTERNS,
        peers = options.peers,
    })
end

M.subscribe_text_change = core.subscribe_text_change
M.subscribe_cursor_activity = core.subscribe_cursor_activity
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
