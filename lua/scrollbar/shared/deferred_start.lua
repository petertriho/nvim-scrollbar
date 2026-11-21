---The runtime start of a `setup()` call during start-up. `setup()` defers the
---start to the first event loop iteration after start-up, so that the first
---screen does not wait for it. The functions of the public API run a pending
---start first, so that they act on a started runtime.
local M = {}

---@type fun()?
local pending = nil

---@param start fun()
M.defer = function(start)
    pending = start
    vim.schedule(function()
        -- A later `setup()` replaces the pending start.
        if pending == start then
            M.run()
        end
    end)
end

M.cancel = function()
    pending = nil
end

---Runs the pending start now, if there is one.
M.run = function()
    local start = pending
    if start ~= nil then
        pending = nil
        start()
    end
end

return M
