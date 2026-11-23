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

--- Set up the built-in list provider `name` alone.
---@param name "qflist"|"loclist"|"jumplist"|"changelist"
---@param options? any The value of `providers.<name>`. Nil enables the provider.
---@param manager_options? ScrollbarProviderManagerOptions Options of the provider manager setup
---@return table providers The provider manager
M.setup_list_provider = function(name, options, manager_options)
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
    providers.setup(manager_options)
    return providers
end

--- Run `keys` in the current window as Normal-mode keys. Then fire
--- TextChanged when the buffer changed, and CursorMoved. Neovim fires these
--- events only before it waits for input, so `nvim_feedkeys` with the `x`
--- flag fires neither.
---@param keys string Keys in the notation of `vim.keycode`
M.press = function(keys)
    local bufnr = vim.api.nvim_get_current_buf()
    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
    vim.api.nvim_feedkeys(vim.keycode(keys), "nx", false)
    if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_changedtick(bufnr) ~= tick then
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
    end
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
end

--- The one-based line of the `mark_type` window mark of `provider`, or nil.
---@param provider string
---@param winid integer
---@param mark_type string
---@return integer?
M.mark_line = function(provider, winid, mark_type)
    for _, mark in ipairs(require("scrollbar.shared.store").get_window(winid)[provider] or {}) do
        if mark.type == mark_type then
            return mark.line + 1
        end
    end
    return nil
end

--- Press `key` in the current window, and expect that the cursor goes to the
--- line of the `mark_type` mark that `provider` published before the key.
---@param provider string
---@param key string Keys in the notation of `vim.keycode`
---@param mark_type string
M.expect_key_goes_to_mark = function(provider, key, mark_type)
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local line = M.mark_line(provider, winid, mark_type)
    MiniTest.expect.no_equality(line, nil)
    M.press(key)
    MiniTest.expect.equality(
        { vim.api.nvim_win_get_buf(winid), vim.api.nvim_win_get_cursor(winid)[1] },
        { bufnr, line }
    )
end

--- Replace `vim.fn[name]` with a wrapper that counts its calls until the end
--- of the case.
---@param name string
---@return fun(): integer count The number of calls so far
M.count_calls = function(name)
    local original = vim.fn[name]
    local calls = 0
    rawset(vim.fn, name, function(...)
        calls = calls + 1
        return original(...)
    end)
    MiniTest.finally(function()
        rawset(vim.fn, name, original)
    end)
    return function()
        return calls
    end
end

--- Set up a provider with fake scheduler dispatch hooks. The hooks keep the
--- callbacks, so a case can pass any event to them.
---@param name "jumplist"|"changelist"
---@return table providers The provider manager
---@return { cursor: fun(args: table)?, text: fun(args: table)? } dispatch The callbacks of the provider
M.setup_with_dispatch = function(name)
    local dispatch = {}
    local providers = M.setup_list_provider(name, nil, {
        on_cursor_activity = function(fn)
            dispatch.cursor = fn
            return true
        end,
        on_text_change = function(fn)
            dispatch.text = fn
            return true
        end,
    })
    return providers, dispatch
end

return M
