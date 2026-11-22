--- `glance()`: build the glance context of the current window and pass it to
--- the picker.
---
--- - The picker is `options.picker`, else `glance.picker`. A name loads the
---   module of its backend. A function gets the context.
--- - The checks run before the picker, so a picker always gets a source
---   window and at least one item. The source window is a normal window or a
---   float source of the consumer: the scrollbar, or the minimap when the
---   scrollbar is disabled.
--- - A picker that raises an error shows a notification.

local config = require("scrollbar.config")
local context = require("scrollbar.navigate.glance.context")
local targets = require("scrollbar.navigate.targets")

local M = {}

local BUILTIN = "scrollbar.navigate.glance.builtin"

--- The module of each picker name. Each module has `open(ctx, opts?)`.
M.BACKENDS = {
    builtin = BUILTIN,
    snacks = "scrollbar.navigate.glance.snacks",
    telescope = "scrollbar.navigate.glance.telescope",
}

---@param message string
---@param level? integer
local function notify(message, level)
    vim.notify("[nvim-scrollbar] " .. message, level or vim.log.levels.WARN)
end

---@class ScrollbarGlanceOptions
---@field types? table<string, true> Mark types of the list. Nil lists every type except `Cursor`
---@field picker? ScrollbarGlancePicker Nil uses `glance.picker`

--- Open the glance picker for the current window.
---@param options? ScrollbarGlanceOptions
M.open = function(options)
    options = options or {}
    -- A call from a pane of the builtin frame opens the picker for the source
    -- window of the frame.
    M.close(true)
    local source_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(source_win).relative ~= "" then
        local consumer = targets.consumer()
        if targets.source_kind(source_win, consumer) == nil then
            notify(
                string.format("glance: the current float is not a source of the %s. See %s.floats", consumer, consumer)
            )
            return
        end
    end
    local glance_config = config.get_glance()
    local ctx = context.new(source_win, glance_config.entries, options.types)
    if #ctx.items == 0 then
        notify("glance: the current window has no marks")
        return
    end
    local picker = options.picker or glance_config.picker
    ---@type fun(ctx: ScrollbarGlanceContext)
    local run
    if type(picker) == "string" then
        run = require(M.BACKENDS[picker]).open
    else
        run = picker
    end
    local ok, err = pcall(run, ctx)
    if not ok then
        notify("glance: picker failed: " .. tostring(err), vim.log.levels.ERROR)
    end
end

--- Close the builtin frame. With `focus_source`, focus goes back to the source
--- window. A snacks or Telescope picker stays open.
---@param focus_source? boolean
M.close = function(focus_source)
    local builtin = package.loaded[BUILTIN]
    if builtin ~= nil then
        builtin.close(focus_source)
    end
end

--- The state of the open builtin frame, for tests.
M.get = function()
    local builtin = package.loaded[BUILTIN]
    return builtin and builtin.get() or nil
end

return M
