--- User controls of one renderer: show, hide, toggle, and refresh. The
--- scrollbar and the minimap each build one set for their user commands.

local providers = require("scrollbar.providers")

local M = {}

---@class ScrollbarControlsRenderer
---@field show fun()
---@field hide fun()
---@field is_visible fun(): boolean
---@field source_windows fun(bufnr?: integer): integer[]

---@class ScrollbarControlsScheduler
---@field reveal_all fun(): integer
---@field invalidate_all fun(): integer
---@field clear_deadlines fun()

---@class ScrollbarControlsOptions
---@field renderer ScrollbarControlsRenderer
---@field scheduler ScrollbarControlsScheduler
---@field consumer "scrollbar"|"minimap" Consumer whose provider demand a refresh collects
---@field autohide fun(): boolean Whether the active configuration conceals the floats after a delay

---@class ScrollbarControls
---@field show fun()
---@field hide fun()
---@field toggle fun()
---@field refresh fun()

---@param options ScrollbarControlsOptions
---@return ScrollbarControls
M.new = function(options)
    local renderer = options.renderer
    local scheduler = options.scheduler
    local consumer = options.consumer
    local autohide = options.autohide
    local refresh_options = { consumer = consumer }

    local controls = {}

    controls.show = function()
        renderer.show()
        -- With autohide, this control reveals every source window and starts
        -- its hide delay.
        if autohide() then
            scheduler.reveal_all()
        else
            scheduler.invalidate_all()
        end
    end

    controls.hide = function()
        renderer.hide()
        scheduler.clear_deadlines()
    end

    controls.toggle = function()
        if renderer.is_visible() then
            controls.hide()
        else
            controls.show()
        end
    end

    controls.refresh = function()
        local buffers = {}
        local windows = renderer.source_windows()
        for _, winid in ipairs(windows) do
            if vim.api.nvim_win_is_valid(winid) then
                buffers[vim.api.nvim_win_get_buf(winid)] = true
            end
        end
        for bufnr in pairs(buffers) do
            providers.refresh(bufnr, refresh_options)
        end
        for _, winid in ipairs(windows) do
            providers.refresh_window(winid, refresh_options)
        end
        scheduler.invalidate_all()
    end

    return controls
end

return M
