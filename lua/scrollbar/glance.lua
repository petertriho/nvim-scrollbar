--- The glance pickers, for a `glance.picker` function. Each picker takes the
--- glance context that the function gets. The snacks and Telescope pickers
--- also take options that merge over their defaults.
---
--- ```lua
--- local glance = require("scrollbar.glance")
--- require("scrollbar").setup({
---     glance = {
---         picker = function(ctx)
---             if #ctx.items > 200 then
---                 glance.snacks(ctx, { layout = { preset = "ivy" } })
---             else
---                 glance.builtin(ctx)
---             end
---         end,
---     },
--- })
--- ```

local M = {}

--- The builtin frame: a list of the marks and a preview pane. It uses the
--- `glance.builtin` options.
---@param ctx ScrollbarGlanceContext
M.builtin = function(ctx)
    require("scrollbar.navigate.glance.builtin").open(ctx)
end

--- A snacks.nvim picker. `opts` merge over the defaults of the glance picker
--- and go to `Snacks.picker.pick()`.
---@param ctx ScrollbarGlanceContext
---@param opts? table
M.snacks = function(ctx, opts)
    require("scrollbar.navigate.glance.snacks").open(ctx, opts)
end

--- A Telescope picker. `opts` go to `pickers.new()`, for example a theme.
---@param ctx ScrollbarGlanceContext
---@param opts? table
M.telescope = function(ctx, opts)
    require("scrollbar.navigate.glance.telescope").open(ctx, opts)
end

return M
