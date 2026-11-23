--- The targets of the history keys of a window: `<C-o>` and `<C-i>` in the
--- jumplist, and `g;` and `g,` in the change list. The `jumplist` and
--- `changelist` providers share these rules and their update events.
---
--- Both lists keep their index in the window, so the marks belong to the
--- window. A read of the jumplist costs about 55 µs for 100 entries, and no
--- cheaper signal shows that a list changed. Thus a provider reads the list of
--- the current window on each Normal-mode cursor move, but not on each key in
--- Insert mode. Insert-mode changes show at InsertLeave.

local M = {}

--- The entries that the older key and the newer key go to. `pos` is the
--- zero-based index that getjumplist() and getchangelist() return, so in Lua
--- indexes the older entry is at `pos` and the newer entry is at `pos + 2`.
--- After a jump or an edit, `pos` is the length of the list, so the newer key
--- has no target. (In this state `g,` goes to the latest change, which is also
--- the target of `g;`, so the change list shows no newer mark.)
---@param list table[]
---@param pos integer
---@return table? older
---@return table? newer
M.targets = function(list, pos)
    return list[pos], list[pos + 2]
end

---@class ScrollbarPositionTargetsSpec
---@field name string The provider name
---@field older string The mark type of the target of the older key
---@field newer string The mark type of the target of the newer key
---@field read fun(bufnr: integer): older: integer?, newer: integer? The one-based lines of the targets in `bufnr`. It runs with the window as the current window
---@field every_edit boolean Read each window of a buffer after each edit. When false, read only the windows whose line count changed

---@class ScrollbarPositionTargetsWindow
---@field bufnr integer The buffer of the window at the last read
---@field line_count integer The line count of that buffer

--- A window-scoped provider that publishes the targets of `spec`.
---@param spec ScrollbarPositionTargetsSpec
---@return ScrollbarProvider
M.provider = function(spec)
    ---@type ScrollbarProviderContext?
    local active = nil
    ---@type table<integer, ScrollbarPositionTargetsWindow>
    local windows = {}

    ---@param winid integer
    ---@param bufnr integer
    ---@return ScrollbarMark[]
    local function collect(winid, bufnr)
        local older, newer
        if winid == vim.api.nvim_get_current_win() then
            older, newer = spec.read(bufnr)
        else
            -- getjumplist() and getchangelist() read the index of the current
            -- window. getjumplist() also uses the buffer of the current window
            -- when it cleans the list.
            vim.api.nvim_win_call(winid, function()
                older, newer = spec.read(bufnr)
            end)
        end
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        local marks = {}
        if older ~= nil and older >= 1 and older <= line_count then
            marks[#marks + 1] = { line = older - 1, type = spec.older }
        end
        if newer ~= nil and newer >= 1 and newer <= line_count then
            marks[#marks + 1] = { line = newer - 1, type = spec.newer }
        end
        return marks
    end

    ---@param winid integer
    local function update(winid)
        local context = active
        if context == nil then
            return
        end
        if not vim.api.nvim_win_is_valid(winid) then
            windows[winid] = nil
            return
        end
        -- The check comes before the read, because a read of a long jumplist
        -- costs more than the check.
        if not context.is_source_window(winid) then
            windows[winid] = nil
            context.clear_window_marks(winid)
            return
        end
        local bufnr = vim.api.nvim_win_get_buf(winid)
        windows[winid] = { bufnr = bufnr, line_count = vim.api.nvim_buf_line_count(bufnr) }
        local marks = collect(winid, bufnr)
        if #marks == 0 or not context.set_window_marks(winid, marks) then
            context.clear_window_marks(winid)
        end
    end

    ---@param args table Autocmd arguments
    local function update_current(args)
        local winid = vim.api.nvim_get_current_win()
        if vim.api.nvim_win_get_buf(winid) == args.buf then
            update(winid)
        end
    end

    --- Read the windows of `bufnr` after an edit. An edit moves the entries of
    --- both lists in every window of the buffer. The change list also gets a
    --- new entry.
    ---@param bufnr integer
    ---@param current? integer A window to read also when its line count is the same
    local function update_edited(bufnr, current)
        local context = active
        if context == nil or not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        for _, winid in ipairs(context.source_windows(bufnr)) do
            local previous = windows[winid]
            if
                spec.every_edit
                or winid == current
                or previous == nil
                or previous.bufnr ~= bufnr
                or previous.line_count ~= line_count
            then
                update(winid)
            end
        end
    end

    ---@type ScrollbarProvider
    return {
        name = spec.name,
        targets = { scrollbar = true, minimap = true },
        refresh_owner = { window = "provider" },
        setup = function(context)
            active = context
            windows = {}
            local group = context.create_augroup("events")
            local desc = "Update scrollbar " .. spec.name .. " targets"

            -- The dispatch of the scheduler also passes CursorMovedI and
            -- TextChangedI when the scheduler handles them. The callbacks
            -- drop them, because a read for each key in Insert mode costs
            -- too much.
            local cursor_dispatched = type(context.on_cursor_activity) == "function"
                and context.on_cursor_activity(function(args)
                    if args.event == "CursorMoved" then
                        update_current(args)
                    end
                end, { "CursorMoved" })
            if not cursor_dispatched then
                vim.api.nvim_create_autocmd("CursorMoved", { group = group, callback = update_current, desc = desc })
            end
            local text_dispatched = type(context.on_text_change) == "function"
                and context.on_text_change(function(args)
                    if args.event == "TextChanged" then
                        update_edited(args.buf)
                    end
                end, { "TextChanged" })
            if not text_dispatched then
                vim.api.nvim_create_autocmd("TextChanged", {
                    group = group,
                    callback = function(args)
                        update_edited(args.buf)
                    end,
                    desc = desc,
                })
            end

            vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
                group = group,
                callback = update_current,
                desc = desc,
            })
            -- InsertLeave also reads the current window, because a jump
            -- with <C-o> in Insert mode changes its jumplist.
            vim.api.nvim_create_autocmd("InsertLeave", {
                group = group,
                callback = function(args)
                    update_edited(args.buf, vim.api.nvim_get_current_win())
                end,
                desc = desc,
            })
            vim.api.nvim_create_autocmd("WinClosed", {
                group = group,
                callback = function(args)
                    local winid = tonumber(args.match)
                    if winid ~= nil then
                        windows[winid] = nil
                    end
                end,
                desc = "Forget the scrollbar " .. spec.name .. " state of a window",
            })
        end,
        refresh_window = function(winid)
            update(winid)
            return nil
        end,
        dispose = function(context)
            context.clear_window_marks()
            active = nil
            windows = {}
        end,
    }
end

return M
