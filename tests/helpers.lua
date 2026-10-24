local MiniTest = MiniTest

local M = {}

-- Installs `require("scrollbar.test.float")` in the child. The float buffers
-- hold empty lines, and each row is an overlay virtual text extmark. The
-- reader gives back the rows and the highlight spans of those extmarks in the
-- shapes of `nvim_buf_get_lines` and `nvim_buf_get_extmarks`, so the tests
-- can check the rendered rows as buffer text. The chunks do not keep the
-- priorities of the spans, so a span has no `priority`. Adjacent pieces of
-- one group join into one span.
local function install_float_reader()
    local reader = {}

    ---@param bufnr integer
    ---@param namespace integer
    ---@param start any
    ---@param finish any
    ---@return table[] overlays Overlay extmarks with details
    local function overlays(bufnr, namespace, start, finish)
        local result = {}
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, start, finish, { details = true })
        for _, mark in ipairs(marks) do
            if mark[4].virt_text_pos == "overlay" then
                result[#result + 1] = mark
            end
        end
        return result
    end

    ---@param bufnr integer
    ---@param start? integer
    ---@param finish? integer
    ---@return string[]
    reader.lines = function(bufnr, start, finish)
        local count = vim.api.nvim_buf_line_count(bufnr)
        start = start or 0
        finish = finish or -1
        if finish < 0 then
            finish = count + finish + 1
        end
        local rows = {}
        for line = start, finish - 1 do
            rows[line - start + 1] = ""
        end
        for _, mark in ipairs(overlays(bufnr, -1, 0, -1)) do
            local line = mark[2]
            if line >= start and line < finish then
                local parts = {}
                for _, chunk in ipairs(mark[4].virt_text) do
                    parts[#parts + 1] = chunk[1]
                end
                rows[line - start + 1] = table.concat(parts)
            end
        end
        return rows
    end

    ---@param bufnr integer
    ---@param namespace integer
    ---@param start any
    ---@param finish any
    ---@param opts? { details?: boolean }
    ---@return table[]
    reader.extmarks = function(bufnr, namespace, start, finish, opts)
        local details = opts and opts.details
        local spans = {}
        for _, mark in ipairs(overlays(bufnr, namespace, start, finish)) do
            local row = mark[2]
            local open = {}
            local col = 0
            for _, chunk in ipairs(mark[4].virt_text) do
                local last = col + #chunk[1]
                local groups = chunk[2]
                if type(groups) ~= "table" then
                    groups = { groups }
                end
                local seen = {}
                for _, group in ipairs(groups) do
                    if not seen[group] then
                        seen[group] = true
                        local span = open[group]
                        if span ~= nil and span.end_col == col then
                            span.end_col = last
                        else
                            span = { row = row, start_col = col, end_col = last, group = group }
                            open[group] = span
                            spans[#spans + 1] = span
                        end
                    end
                end
                col = last
            end
        end
        table.sort(spans, function(left, right)
            if left.row ~= right.row then
                return left.row < right.row
            end
            if left.start_col ~= right.start_col then
                return left.start_col < right.start_col
            end
            return left.end_col < right.end_col
        end)
        local result = {}
        for index, span in ipairs(spans) do
            local mark = { index, span.row, span.start_col }
            if details then
                mark[4] = {
                    ns_id = namespace,
                    end_row = span.row,
                    end_col = span.end_col,
                    hl_group = span.group,
                }
            end
            result[index] = mark
        end
        return result
    end

    package.loaded["scrollbar.test.float"] = reader
end

M.new_child = function()
    local child = MiniTest.new_child_neovim()
    child.start({ "--noplugin", "-u", "scripts/minimal_init.lua" })
    child.o.swapfile = false
    child.o.lines = 24
    child.o.columns = 80
    child.lua_func(install_float_reader)
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
        require("scrollbar.shared.text_tick").setup()
        vim.o.hlsearch = true
        vim.o.wrapscan = false

        local active_config = require("scrollbar.config").set({
            set_highlights = false,
            providers = {
                cursor = false,
                diagnostic = false,
                search = value.search_config,
            },
            scrollbar = {
                throttle_ms = 0,
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
        return require("scrollbar.shared.store").get(buffer).search
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
        local marks = require("scrollbar.shared.store").get(buffer).search
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
            local marks = require("scrollbar.shared.store").get(vim.api.nvim_get_current_buf()).search
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
            return require("scrollbar.providers.search.worker").status().state == value
        end)
    end, expected)
end

--- The worker starts at the first search. A search command line starts it,
--- also when the user leaves the command line without a search.
M.start_search_worker = function(child)
    child.type_keys("/", "<Esc>")
    return M.wait_for_worker_status(child, "ready")
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
        local marks = require("scrollbar.shared.store").get(vim.api.nvim_get_current_buf()).search
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
