--- Fakes for the tests of the scrollbar scheduler and the minimap scheduler.
--- The tests require this module in the child Neovim, where the scheduler
--- calls the fakes.

local M = {}

--- A renderer that draws the source windows `windows`. Each buffer is
--- eligible, and the renderer owns no buffer and no window. The fields of
--- `overrides` replace the fields of the renderer.
---@param windows integer[]
---@param overrides? table
---@return table
M.renderer = function(windows, overrides)
    local renderer = {
        source_windows = function()
            return vim.list_extend({}, windows)
        end,
        is_source_window = function(winid)
            return vim.tbl_contains(windows, winid)
        end,
        is_buffer_eligible = function()
            return true
        end,
        is_owned_buffer = function()
            return false
        end,
        is_owned_window = function()
            return false
        end,
        render = function() end,
    }
    for key, value in pairs(overrides or {}) do
        renderer[key] = value
    end
    return renderer
end

--- A renderer with no source windows and no eligible buffers.
---@param overrides? table
---@return table
M.idle_renderer = function(overrides)
    return M.renderer(
        {},
        vim.tbl_extend("force", {
            is_buffer_eligible = function()
                return false
            end,
        }, overrides or {})
    )
end

--- A renderer that draws the window `winid`, which shows the buffer `bufnr`.
--- Only `bufnr` is eligible.
---@param bufnr integer
---@param winid integer
---@param overrides? table
---@return table
M.buffer_renderer = function(bufnr, winid, overrides)
    return M.renderer(
        { winid },
        vim.tbl_extend("force", {
            source_windows = function(target_buf)
                if target_buf == nil or target_buf == bufnr then
                    return { winid }
                end
                return {}
            end,
            is_buffer_eligible = function(target_buf)
                return target_buf == bufnr
            end,
        }, overrides or {})
    )
end

---@class ScrollbarFakeTimer
---@field callback? fun() The callback of the last start
---@field timeout? integer The timeout of the last start
---@field starts integer
---@field stopped? true
---@field closed boolean

--- Replace `uv.new_timer` with timers that never fire. A test runs the
--- callback of a timer itself.
---@return ScrollbarFakeTimer[] timers The new timers, in the order of creation
---@return fun() restore Restores `uv.new_timer`
M.fake_timers = function()
    local uv = vim.uv or vim.loop
    local original_new_timer = uv.new_timer
    local timers = {}
    uv.new_timer = function()
        local timer = { closed = false, starts = 0 }
        function timer:start(timeout, _, callback)
            self.timeout = timeout
            self.callback = callback
            self.starts = self.starts + 1
        end
        function timer:stop()
            self.stopped = true
        end
        function timer:close()
            self.closed = true
        end
        function timer:is_closing()
            return self.closed
        end
        table.insert(timers, timer)
        return timer
    end
    return timers, function()
        uv.new_timer = original_new_timer
    end
end

--- Record the arguments of each `invalidate_buffer` and `invalidate_window`
--- call of `scheduler`. The calls still invalidate.
---@param scheduler table
---@return { buffer: integer[], window: integer[] }
M.record_invalidations = function(scheduler)
    local calls = { buffer = {}, window = {} }
    local original_invalidate_buffer = scheduler.invalidate_buffer
    local original_invalidate_window = scheduler.invalidate_window
    rawset(scheduler, "invalidate_buffer", function(target_buf)
        table.insert(calls.buffer, target_buf)
        return original_invalidate_buffer(target_buf)
    end)
    rawset(scheduler, "invalidate_window", function(source_win)
        table.insert(calls.window, source_win)
        return original_invalidate_window(source_win)
    end)
    return calls
end

return M
