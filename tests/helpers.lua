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

M.setup_search = function(child, live)
    child.lua_func(function(value)
        vim.o.hlsearch = true
        vim.o.wrapscan = false
        if value == nil then
            require("scrollbar.handlers.search").setup()
        else
            require("scrollbar.handlers.search").setup({ live = value })
        end
    end, live)
end

M.setup_root_search = function(child, search_config)
    child.lua_func(function(value)
        vim.o.hlsearch = true
        vim.o.wrapscan = false
        require("scrollbar").setup({
            set_highlights = false,
            throttle_ms = 0,
            autocmd = { render = {} },
            handlers = {
                cursor = false,
                diagnostic = false,
                gitsigns = false,
                search = value,
                ale = false,
            },
        })
    end, search_config)
end

M.activate_search = function(child, pattern)
    child.lua_func(function(value)
        vim.fn.setreg("/", value)
        vim.fn.search(value, "cw")
    end, pattern)
end

M.search_marks = function(child, bufnr)
    local marks = child.lua_func(function(buffer)
        return require("scrollbar.utils").get_scrollbar_marks(buffer or 0).search
    end, bufnr)
    if marks == vim.NIL then
        return nil
    end
    return marks
end

M.mark_lines = function(child, bufnr)
    local lines = child.lua_func(function(buffer)
        local marks = require("scrollbar.utils").get_scrollbar_marks(buffer or 0).search
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
            local marks = require("scrollbar.utils").get_scrollbar_marks(0).search
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

M.accept_search = function(child, direction, pattern)
    child.type_keys(10, direction, pattern, "<CR>")
end

M.inspect_during_cmdline = function(child, direction, pattern)
    child.lua([[
        _G.scrollbar_test_cmdline = { called = false }
        vim.api.nvim_create_autocmd("CmdlineChanged", {
            pattern = { "/", "?" },
            callback = function()
                local marks = require("scrollbar.utils").get_scrollbar_marks(0).search
                _G.scrollbar_test_cmdline.lines = marks and vim.tbl_map(function(mark)
                    return mark.line
                end, marks) or nil
            end,
        })
        vim.keymap.set("c", "<F5>", function()
            _G.scrollbar_test_cmdline.called = true
            _G.scrollbar_test_cmdline.mode = vim.api.nvim_get_mode().mode
            return vim.keycode("<C-c>")
        end, { expr = true })
    ]])
    local keys = { direction }
    for character in pattern:gmatch(".") do
        table.insert(keys, character)
    end
    table.insert(keys, "<F5>")
    child.type_keys(10, keys)
    local capture = child.lua_get("_G.scrollbar_test_cmdline")
    child.lua([[vim.keymap.del("c", "<F5>")]])
    if not capture.called then
        error("command-line inspection mapping did not run")
    end
    if capture.lines == vim.NIL then
        capture.lines = nil
    end
    return capture
end

return M
