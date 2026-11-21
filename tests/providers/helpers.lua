--- Helpers for the tests that run in the test Neovim itself, without a child
--- Neovim: the provider tests and the store tests.

local MiniTest = MiniTest

local M = {}

--- A scratch buffer with `lines`. The buffer gets `filetype` only when it is
--- given, because each set of 'filetype' triggers FileType. The buffer is
--- deleted at the end of the case.
---@param lines string[]
---@param filetype? string
---@return integer bufnr
M.new_buffer = function(lines, filetype)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    if filetype ~= nil then
        vim.bo[bufnr].filetype = filetype
    end
    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)
    return bufnr
end

--- Show `bufnr` in a new window at the bottom, and make it the current
--- window. At the end of the case, the window closes and the previous window
--- is current again.
---@param bufnr integer
---@return integer winid
M.show_buffer = function(bufnr)
    local previous = vim.api.nvim_get_current_win()
    vim.cmd("botright new")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    MiniTest.finally(function()
        if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_close(winid, true)
        end
        if vim.api.nvim_win_is_valid(previous) then
            vim.api.nvim_set_current_win(previous)
        end
    end)
    return winid
end

--- Replace `vim.notify` until the end of the case.
---@return { message: string, level: integer? }[] notifications Each notification, in order
M.capture_notifications = function()
    local notifications = {}
    local original = vim.notify
    rawset(vim, "notify", function(message, level)
        table.insert(notifications, { message = message, level = level })
    end)
    MiniTest.finally(function()
        rawset(vim, "notify", original)
    end)
    return notifications
end

--- Unload the configuration, the renderer, the store, the provider manager,
--- and the modules in `extra`. The next `require` loads them again.
---@param extra? string[]
M.unload_modules = function(extra)
    package.loaded["scrollbar.config"] = nil
    package.loaded["scrollbar.renderer"] = nil
    package.loaded["scrollbar.shared.store"] = nil
    package.loaded["scrollbar.providers"] = nil
    for _, module in ipairs(extra or {}) do
        package.loaded[module] = nil
    end
end

--- Dispose the provider manager, if a case loaded it.
M.dispose_providers = function()
    local providers = package.loaded["scrollbar.providers"]
    if providers then
        providers.dispose()
    end
end

--- Set up the built-in list provider `name` ("qflist" or "loclist") alone.
---@param name "qflist"|"loclist"
---@param options? any The value of `providers.<name>`. Nil enables the provider.
---@return table providers The provider manager
M.setup_list_provider = function(name, options)
    require("scrollbar.config").set({
        exclude = {
            buftypes = {},
            filetypes = { "scrollbar-excluded" },
        },
        providers = { [name] = options == nil or options },
        scrollbar = { max_lines = false },
    })
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers." .. name))
    providers.setup()
    return providers
end

return M
