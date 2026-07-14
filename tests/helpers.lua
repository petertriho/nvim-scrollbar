local MiniTest = MiniTest

local M = {}

M.new_child = function()
    local child = MiniTest.new_child_neovim()
    child.start({ "--noplugin", "-u", "scripts/minimal_init.lua" })
    child.o.swapfile = false
    child.o.lines = 24
    child.o.columns = 80
    return child
end

M.stop_child = function(child)
    if child and child.is_running() then
        child.stop()
    end
end

M.set_lines = function(child, lines)
    child.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    child.api.nvim_win_set_cursor(0, { 1, 0 })
end

local function setup_search_provider(child, search_config, worker_test)
    child.lua_func(function(value)
        package.loaded["scrollbar.test.search_worker"] = value.worker_test
        vim.o.hlsearch = true
        vim.o.wrapscan = false

        local active_config = require("scrollbar.config").set({
            set_highlights = false,
            render = { interval_ms = 0 },
            providers = {
                cursor = false,
                diagnostic = false,
                gitsigns = false,
                search = value.search_config,
                ale = false,
                coc = false,
            },
        })
        local providers = require("scrollbar.providers")
        local state = package.loaded["scrollbar.test.search"]
        if type(state) ~= "table" then
            state = {}
            package.loaded["scrollbar.test.search"] = state
        end
        if not state.registered then
            providers.register(require("scrollbar.providers.search"))
            state.registered = true
        end

        state.invalidated_buffers = {}
        state.invalidated_windows = {}
        providers.setup({
            config = active_config,
            invalidate_buffer = function(bufnr)
                table.insert(state.invalidated_buffers, bufnr)
                for _, winid in ipairs(vim.api.nvim_list_wins()) do
                    if
                        vim.api.nvim_win_get_config(winid).relative == ""
                        and vim.api.nvim_win_get_buf(winid) == bufnr
                    then
                        table.insert(state.invalidated_windows, winid)
                    end
                end
            end,
        })
        state.invalidated_buffers = {}
        state.invalidated_windows = {}
    end, { search_config = search_config, worker_test = worker_test })
end

M.setup_search = function(child, incsearch)
    setup_search_provider(child, { incsearch = incsearch }, { backend = "sync" })
end

M.setup_search_worker = function(child, incsearch, worker_test)
    worker_test = worker_test or {}
    worker_test.backend = "worker"
    setup_search_provider(child, { incsearch = incsearch }, worker_test)
end

M.setup_search_default = function(child, incsearch)
    setup_search_provider(child, { incsearch = incsearch })
end

M.setup_search_default_config = function(child, search_config)
    setup_search_provider(child, search_config)
end

M.setup_search_config = function(child, search_config)
    setup_search_provider(child, search_config, { backend = "sync" })
end

M.activate_search = function(child, pattern)
    child.lua_func(function(value)
        vim.fn.setreg("/", value)
        vim.fn.search(value, "cw")
    end, pattern)
end

M.search_marks = function(child, bufnr)
    local marks = child.lua_func(function(buffer)
        if buffer == nil or buffer == 0 then
            buffer = vim.api.nvim_get_current_buf()
        end
        return require("scrollbar.store").get(buffer).search
    end, bufnr)
    if marks == vim.NIL then
        return nil
    end
    return marks
end

M.mark_lines = function(child, bufnr)
    local lines = child.lua_func(function(buffer)
        if buffer == nil or buffer == 0 then
            buffer = vim.api.nvim_get_current_buf()
        end
        local marks = require("scrollbar.store").get(buffer).search
        if marks == nil then
            return nil
        end

        return vim.tbl_map(function(mark)
            return mark.line
        end, marks)
    end, bufnr)
    if lines == vim.NIL then
        return nil
    end
    return lines
end

M.wait_for_mark_lines = function(child, expected)
    return child.lua_func(function(value)
        return vim.wait(1000, function()
            local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
            if marks == nil then
                return value == nil
            end

            local lines = vim.tbl_map(function(mark)
                return mark.line
            end, marks)
            return vim.deep_equal(lines, value)
        end)
    end, expected)
end

M.wait_for_worker_status = function(child, expected)
    return child.lua_func(function(value)
        return vim.wait(3000, function()
            return require("scrollbar.providers.search_worker").status().state == value
        end)
    end, expected)
end

M.accept_search = function(child, direction, pattern)
    child.type_keys(10, direction, pattern, "<CR>")
end

M.inspect_during_cmdline = function(child, direction, pattern)
    local keys = { direction }
    for character in pattern:gmatch(".") do
        table.insert(keys, character)
    end
    child.type_keys(10, keys)
    vim.uv.sleep(100)
    child.type_keys(10, "<Left>")
    vim.uv.sleep(100)
    local capture = child.lua_get([[(function()
        local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
        return {
            mode = vim.api.nvim_get_mode().mode,
            lines = marks and vim.tbl_map(function(mark)
                return mark.line
            end, marks) or nil,
        }
    end)()]])
    child.type_keys(10, "<C-c>")
    if capture.lines == vim.NIL then
        capture.lines = nil
    end
    return capture
end

M.reset_search_invalidations = function(child)
    child.lua([[
        local state = package.loaded["scrollbar.test.search"]
        state.invalidated_buffers = {}
        state.invalidated_windows = {}
    ]])
end

M.search_invalidations = function(child)
    return child.lua_get([[
        (function()
            local state = package.loaded["scrollbar.test.search"]
            return {
                buffers = state.invalidated_buffers,
                windows = state.invalidated_windows,
            }
        end)()
    ]])
end

return M
