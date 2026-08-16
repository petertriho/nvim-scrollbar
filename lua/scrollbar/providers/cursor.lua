local CURSOR_HIGHLIGHT = "ScrollbarMinimapCursor"
local CURSOR_PRIORITY = 14

---@param winid integer
---@param context ScrollbarProviderContext
---@return ScrollbarMark[]? marks
---@return ScrollbarMinimapSourcePoint[]? points
local function collect(winid, context)
    if not context.is_source_window(winid) then
        return nil, nil
    end

    local cursor = vim.api.nvim_win_get_cursor(winid)
    local line = cursor[1] - 1
    return { { line = line, type = "Cursor" } }, {
        {
            line = line,
            col = cursor[2],
            highlight = CURSOR_HIGHLIGHT,
            priority = CURSOR_PRIORITY,
        },
    }
end

---@param winid integer
---@param context ScrollbarProviderContext
local function update(winid, context)
    local marks, points = collect(winid, context)
    if marks == nil then
        context.clear_window_marks(winid)
        context.clear_minimap_points(winid)
    else
        assert(points ~= nil, "cursor points are missing")
        context.set_window_marks(winid, marks)
        context.set_minimap_points(winid, points)
    end
end

---@type ScrollbarProvider
return {
    name = "cursor",
    targets = { scrollbar = true, minimap = true },
    refresh_owner = { window = "provider" },
    setup = function(context)
        local group = context.create_augroup("events")
        local function refresh(args)
            local winid = vim.api.nvim_get_current_win()
            if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == args.buf then
                update(winid, context)
            end
        end
        -- Ride the scheduler's cursor-activity dispatch when wired: one
        -- autocmd invocation per cursor move covers scheduling and the cursor
        -- update. Falls back to own registration in standalone setups.
        if type(context.on_cursor_activity) == "function" then
            if context.on_cursor_activity(refresh, { "CursorMoved", "CursorMovedI" }) then
                vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
                    group = group,
                    callback = refresh,
                    desc = "Update scrollbar cursor data",
                })
                return
            end
        end
        vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "BufWinEnter", "WinEnter" }, {
            group = group,
            callback = refresh,
            desc = "Update scrollbar cursor data",
        })
    end,
    refresh_window = function(winid, context)
        update(winid, context)
    end,
    dispose = function(context)
        context.clear_window_marks()
        context.clear_minimap_points()
    end,
}
