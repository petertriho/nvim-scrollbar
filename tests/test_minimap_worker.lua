local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

local function setup_worker(child, options)
    child.lua_func(function(opts)
        package.loaded["scrollbar.test.minimap_worker"] = {
            results = {},
            failures = {},
            timings = {},
            timing_payloads = {},
        }
        local worker = require("scrollbar.minimap.worker")
        worker.setup({
            backend = opts.backend,
            treesitter = opts.treesitter,
            on_result = function(payload)
                table.insert(package.loaded["scrollbar.test.minimap_worker"].results, payload)
            end,
            on_failure = function(reason)
                table.insert(package.loaded["scrollbar.test.minimap_worker"].failures, reason)
            end,
            test = vim.tbl_extend("force", opts.test or {}, {
                on_timing = function(event, payload)
                    local state = package.loaded["scrollbar.test.minimap_worker"]
                    table.insert(state.timings, event)
                    state.timing_payloads[event] = state.timing_payloads[event] or {}
                    table.insert(state.timing_payloads[event], vim.deepcopy(payload))
                end,
            }),
        })
    end, {
        backend = options.backend,
        treesitter = options.treesitter,
        test = options.test,
    })
end

local function wait_for_result(child, index)
    index = index or 1
    return child.lua_func(function(idx)
        local state = package.loaded["scrollbar.test.minimap_worker"]
        local ok = vim.wait(3000, function()
            return state.results[idx] ~= nil
        end)
        return { ok = ok, payload = state.results[idx] }
    end, index)
end

local function grid_chars(cells)
    local rows = {}
    for row = 1, #cells do
        local chars = {}
        for col = 1, #cells[row] do
            chars[col] = cells[row][col].char
        end
        rows[row] = table.concat(chars)
    end
    return rows
end

local function grid_highlights(cells)
    local rows = {}
    for row = 1, #cells do
        local highlights = {}
        for col = 1, #cells[row] do
            highlights[col] = cells[row][col].hl_group
        end
        rows[row] = highlights
    end
    return rows
end

T["sync backend returns a cell grid for a buffer"] = function()
    local child = new_child()
    setup_worker(child, { backend = "sync" })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "defghi" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 3,
            height = 2,
            filetype = "",
            generation = 1,
            signature = "test",
        })
        return package.loaded["scrollbar.test.minimap_worker"].results[1]
    end)

    expect.no_equality(result, nil)
    expect.equality(result.generation, 1)
    expect.equality(result.signature, "test")
    expect.equality(result.max_line_width, 6)
    expect.equality(grid_chars(result.cells), { "██ ", "███" })
end

T["sync backend composes parent semantic spans and echoes their revision"] = function()
    local child = new_child()
    setup_worker(child, { backend = "sync" })

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "a😀 b" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 5,
            height = 1,
            filetype = "",
            generation = 1,
            signature = "semantic-sync",
            semantic_revision = 4,
            semantic_spans = {
                parent = {
                    { line = 0, start_col = 1, end_col = 5, highlight = "Emoji", priority = 10 },
                    { line = 0, start_col = 5, end_col = 6, highlight = "Whitespace", priority = 20 },
                },
            },
        })
        return package.loaded["scrollbar.test.minimap_worker"].results[1]
    end)

    expect.equality(result.semantic_revision, 4)
    expect.equality(grid_chars(result.cells), { "███ █" })
    expect.equality(grid_highlights(result.cells), { { nil, "Emoji", "Emoji", nil, nil } })
end

T["sync backend skips all treesitter work when the provider is disabled"] = function()
    local child = new_child()
    setup_worker(child, { backend = "sync" })

    local result = child.lua_func(function()
        local calls = { get_lang = 0, add = 0, get_parser = 0, query = 0 }
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.treesitter.language.get_lang = function()
            calls.get_lang = calls.get_lang + 1
            return "lua"
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.treesitter.language.add = function()
            calls.add = calls.add + 1
            return true
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.treesitter.get_parser = function()
            calls.get_parser = calls.get_parser + 1
            error("parser lookup should be skipped")
        end
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.treesitter.query.get = function()
            calls.query = calls.query + 1
            error("query lookup should be skipped")
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcdef" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 3,
            height = 1,
            filetype = "lua",
            generation = 1,
            signature = "test",
        })
        return {
            calls = calls,
            payload = package.loaded["scrollbar.test.minimap_worker"].results[1],
        }
    end)

    expect.equality(result.calls, { get_lang = 0, add = 0, get_parser = 0, query = 0 })
    expect.no_equality(result.payload, nil)
    for _, cell in ipairs(result.payload.cells[1]) do
        expect.equality(cell.hl_group, nil)
    end
end

local function wait_for_worker_ready(child)
    return child.lua_func(function()
        return vim.wait(5000, function()
            return require("scrollbar.minimap.worker").status().state == "ready"
        end)
    end)
end

T["worker backend reaches ready after setup and reports argv"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })

    expect.equality(wait_for_worker_ready(child), true)
    local status = child.lua_get([[require("scrollbar.minimap.worker").status()]])
    expect.equality(status.backend, "worker")
    expect.equality(status.state, "ready")
    expect.no_equality(status.job_id, nil)
    expect.equality(status.argv, {
        vim.v.progpath,
        "--embed",
        "--headless",
        "-u",
        "NONE",
        "-i",
        "NONE",
        "--noplugin",
    })
end

T["worker backend renders a buffer via child RPC"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)

    child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "defghi" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 3,
            height = 2,
            filetype = "",
            generation = 1,
            signature = "test",
        })
    end)

    local captured = wait_for_result(child, 1)
    expect.equality(captured.ok, true)
    expect.no_equality(captured.payload, nil)
    expect.equality(captured.payload.generation, 1)
    expect.equality(captured.payload.max_line_width, 6)
    expect.equality(grid_chars(captured.payload.cells), { "██ ", "███" })
end

T["worker backend retains distinct same-buffer projection requests"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 100 do
            lines[index] = string.rep("a", 20)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

        local worker = require("scrollbar.minimap.worker")
        worker.request({
            bufnr = 0,
            width = 4,
            height = 2,
            filetype = "",
            generation = 1,
            signature = "short",
        })
        worker.request({
            bufnr = 0,
            width = 4,
            height = 3,
            filetype = "",
            generation = 1,
            signature = "tall",
        })

        local state = package.loaded["scrollbar.test.minimap_worker"]
        local ok = vim.wait(5000, function()
            return #state.results == 2
        end)
        local heights = {}
        for _, payload in ipairs(state.results) do
            heights[payload.signature] = #payload.cells
        end
        return { ok = ok, heights = heights }
    end)

    expect.equality(result.ok, true)
    expect.equality(result.heights, { short = 2, tall = 3 })
end

T["worker synchronizes each parent semantic revision once per buffer mirror"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abcd", "efgh" })
        local worker = require("scrollbar.minimap.worker")
        local spans = {
            parent = {
                { line = 0, start_col = 0, end_col = 4, highlight = "First", priority = 1 },
            },
        }
        worker.request({
            bufnr = 0,
            width = 4,
            height = 1,
            filetype = "",
            generation = 1,
            signature = "wide",
            semantic_revision = 1,
            semantic_spans = spans,
        })
        worker.request({
            bufnr = 0,
            width = 2,
            height = 1,
            filetype = "",
            generation = 1,
            signature = "narrow",
            semantic_revision = 1,
            semantic_spans = spans,
        })
        local state = package.loaded["scrollbar.test.minimap_worker"]
        local first_ok = vim.wait(5000, function()
            return #state.results == 2
        end)

        worker.request({
            bufnr = 0,
            width = 4,
            height = 1,
            filetype = "",
            generation = 2,
            signature = "wide",
            semantic_revision = 2,
            semantic_spans = {
                parent = {
                    { line = 0, start_col = 0, end_col = 4, highlight = "Second", priority = 2 },
                },
            },
        })
        local second_ok = vim.wait(5000, function()
            return #state.results == 3
        end)
        local sync_events = 0
        for _, event in ipairs(state.timings) do
            if event == "semantic_snapshot_sent" then
                sync_events = sync_events + 1
            end
        end
        local semantic_payload_resends = 0
        for _, payload in ipairs(state.timing_payloads.squash_dispatched or {}) do
            if payload.semantic_spans_sent then
                semantic_payload_resends = semantic_payload_resends + 1
            end
        end
        return {
            first_ok = first_ok,
            second_ok = second_ok,
            sync_events = sync_events,
            semantic_payload_resends = semantic_payload_resends,
            semantic_revision = state.results[3] and state.results[3].semantic_revision or nil,
            cells = state.results[3] and state.results[3].cells or nil,
        }
    end)

    expect.equality(result.first_ok, true)
    expect.equality(result.second_ok, true)
    expect.equality(result.sync_events, 2)
    expect.equality(result.semantic_payload_resends, 0)
    expect.equality(result.semantic_revision, 2)
    expect.equality(grid_highlights(result.cells)[1][1], "Second")
end

T["worker and sync backends produce identical parent semantic cells"] = function()
    local child = new_child()
    local fixture = { "a😀 b", "second" }
    local spans = {
        low = {
            { line = 0, start_col = 0, end_col = 6, highlight = "Low", priority = 1 },
        },
        high = {
            { line = 0, start_col = 1, end_col = 5, highlight = "High", priority = 2 },
        },
    }

    setup_worker(child, { backend = "sync" })
    local sync_result = child.lua_func(function(input)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, input.lines)
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 5,
            height = 1,
            filetype = "",
            generation = 1,
            signature = "semantic-equivalence",
            semantic_revision = 3,
            semantic_spans = input.spans,
        })
        return package.loaded["scrollbar.test.minimap_worker"].results[1]
    end, { lines = fixture, spans = spans })

    child.lua([[require("scrollbar.minimap.worker").dispose()]])
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)
    local worker_result = child.lua_func(function(input)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, input.lines)
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 5,
            height = 1,
            filetype = "",
            generation = 1,
            signature = "semantic-equivalence",
            semantic_revision = 3,
            semantic_spans = input.spans,
        })
        local state = package.loaded["scrollbar.test.minimap_worker"]
        return vim.wait(5000, function()
            return state.results[1] ~= nil
        end) and state.results[1] or nil
    end, { lines = fixture, spans = spans })

    expect.equality(worker_result.semantic_revision, sync_result.semantic_revision)
    expect.equality(worker_result.cells, sync_result.cells)
end

T["worker backend skips language resolution and child treesitter work when disabled"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker", test = { trace_treesitter = true } })
    expect.equality(wait_for_worker_ready(child), true)

    local result = child.lua_func(function()
        local get_lang_calls = 0
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.treesitter.language.get_lang = function()
            get_lang_calls = get_lang_calls + 1
            return "lua"
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 4,
            height = 2,
            filetype = "lua",
            generation = 1,
            signature = "mono-worker",
        })
        local state = package.loaded["scrollbar.test.minimap_worker"]
        local ok = vim.wait(5000, function()
            return state.results[1] ~= nil
        end)
        return {
            ok = ok,
            get_lang_calls = get_lang_calls,
            timings = state.timings,
            cells = state.results[1] and state.results[1].cells or nil,
        }
    end)

    expect.equality(result.ok, true)
    expect.equality(result.get_lang_calls, 0)
    expect.equality(vim.tbl_contains(result.timings, "treesitter_start"), false)
    expect.equality(vim.tbl_contains(result.timings, "capture_extract"), false)
    for _, row in ipairs(result.cells) do
        for _, cell in ipairs(row) do
            expect.equality(cell.char == " " or cell.char == "█", true)
            expect.equality(cell.hl_group, nil)
        end
    end
end

T["worker and sync backends produce identical cell grids for the same fixture"] = function()
    local child = new_child()
    local fixture = {
        "local M = {}",
        "",
        "function M.foo(a, b)",
        "    return a + b",
        "end",
        "",
        "return M",
    }

    setup_worker(child, { backend = "sync", treesitter = true })
    local sync_data = child.lua_func(function(lines)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.bo.filetype = "lua"
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 8,
            height = 4,
            filetype = "lua",
            generation = 1,
            signature = "fixture",
        })
        local state = package.loaded["scrollbar.test.minimap_worker"]
        local cells = vim.wait(2000, function()
            return state.results[1] ~= nil
        end) and state.results[1].cells or nil
        ---@diagnostic disable-next-line: redundant-parameter
        local lang = vim.treesitter.language.get_lang("lua")
        local parser_ok = lang ~= nil and pcall(vim.treesitter.language.add, lang)
        local query_ok, query = false, nil
        if parser_ok then
            query_ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
        end
        return { cells = cells, parser_available = parser_ok and query_ok and query ~= nil }
    end, fixture)
    local sync_cells = sync_data.cells

    child.lua([[require("scrollbar.minimap.worker").dispose()]])
    setup_worker(child, { backend = "worker", treesitter = true })
    expect.equality(wait_for_worker_ready(child), true)

    local worker_cells = child.lua_func(function(lines)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.bo.filetype = "lua"
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 8,
            height = 4,
            filetype = "lua",
            generation = 1,
            signature = "fixture",
        })
        local state = package.loaded["scrollbar.test.minimap_worker"]
        return vim.wait(5000, function()
            return state.results[1] ~= nil
        end) and state.results[1].cells or nil
    end, fixture)

    expect.no_equality(sync_cells, nil)
    expect.no_equality(worker_cells, nil)
    local has_highlight = false
    expect.equality(#sync_cells, #worker_cells)
    for row = 1, #sync_cells do
        expect.equality(#sync_cells[row], #worker_cells[row])
        for col = 1, #sync_cells[row] do
            expect.equality(sync_cells[row][col].char, worker_cells[row][col].char)
            expect.equality(sync_cells[row][col].hl_group, worker_cells[row][col].hl_group)
            has_highlight = has_highlight or sync_cells[row][col].hl_group ~= nil
        end
    end
    if sync_data.parser_available then
        expect.equality(has_highlight, true)
    end
end

T["repeated setup resets the treesitter provider to disabled"] = function()
    local child = new_child()
    setup_worker(child, { backend = "sync", treesitter = true })
    setup_worker(child, { backend = "sync" })

    local calls = child.lua_func(function()
        local get_lang_calls = 0
        ---@diagnostic disable-next-line: duplicate-set-field
        vim.treesitter.language.get_lang = function()
            get_lang_calls = get_lang_calls + 1
            return "lua"
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local value = 1" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 4,
            height = 1,
            filetype = "lua",
            generation = 1,
            signature = "reset",
        })
        return get_lang_calls
    end)

    expect.equality(calls, 0)
end

T["chunked snapshot transfers large buffers and renders every source line"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker", test = { chunk_size = 4 } })
    expect.equality(wait_for_worker_ready(child), true)

    child.lua_func(function()
        local lines = {}
        for index = 1, 50 do
            lines[index] = string.rep("a", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 4,
            height = 4,
            filetype = "",
            generation = 1,
            signature = "big",
        })
    end)

    local captured = wait_for_result(child, 1)
    expect.equality(captured.ok, true)
    expect.equality(#captured.payload.cells, 4)
end

T["mirror invalidation triggers a re-snapshot when buffer edits during snapshot"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker", test = { chunk_size = 1 } })
    expect.equality(wait_for_worker_ready(child), true)

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 40 do
            lines[index] = string.rep("x", index)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local worker = require("scrollbar.minimap.worker")
        worker.request({
            bufnr = 0,
            width = 4,
            height = 4,
            filetype = "",
            generation = 1,
            signature = "race",
        })

        -- Edit during snapshot to trigger changedtick drift + restart
        vim.schedule(function()
            vim.api.nvim_buf_set_lines(0, 39, 40, false, { "EDITED" })
            vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
        end)

        local state = package.loaded["scrollbar.test.minimap_worker"]
        return vim.wait(5000, function()
            return state.results[1] ~= nil
        end)
    end)

    expect.equality(result, true)
    local status = child.lua_get([[require("scrollbar.minimap.worker").status()]])
    expect.equality(status.state, "ready")
    expect.equality(status.mirrors[1].complete, true)
end

T["child mirror invalidation requeues the in-flight squash after resnapshot"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker", test = { chunk_size = 128 } })
    expect.equality(wait_for_worker_ready(child), true)

    local result = child.lua_func(function()
        local lines = {}
        for index = 1, 10000 do
            lines[index] = string.rep("x", 80)
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local worker = require("scrollbar.minimap.worker")
        worker.request({
            bufnr = 0,
            width = 80,
            height = 24,
            filetype = "",
            generation = 1,
            signature = "mirror-invalid",
        })
        local dispatched = vim.wait(5000, function()
            return worker.status().in_flight ~= nil
        end)
        if dispatched then
            local status = worker.status()
            -- selene: allow(global_usage)
            _G.__scrollbar_minimap_worker_callback(status.session, "mirror_invalid", {
                bufnr = vim.api.nvim_get_current_buf(),
            })
        end
        local state = package.loaded["scrollbar.test.minimap_worker"]
        local completed = vim.wait(10000, function()
            return state.results[1] ~= nil
        end)
        local dispatches = 0
        for _, event in ipairs(state.timings) do
            if event == "squash_dispatched" then
                dispatches = dispatches + 1
            end
        end
        return {
            dispatched = dispatched,
            completed = completed,
            dispatches = dispatches,
            in_flight = worker.status().in_flight,
        }
    end)

    expect.equality(result.dispatched, true)
    expect.equality(result.completed, true)
    expect.equality(result.dispatches >= 2, true)
    expect.equality(result.in_flight, nil)
end

T["on_lines deltas update child mirror after snapshot completes"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)

    child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc", "def" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 2,
            height = 2,
            filetype = "",
            generation = 1,
            signature = "v1",
        })
    end)
    expect.equality(wait_for_result(child, 1).ok, true)

    child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, 1, false, { "ABCDEFGHIJ" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 2,
            height = 2,
            filetype = "",
            generation = 2,
            signature = "v2",
        })
    end)
    local captured = wait_for_result(child, 2)
    expect.equality(captured.ok, true)
    -- The first source line owns row 1; both horizontal buckets are occupied.
    expect.equality(grid_chars(captured.payload.cells)[1], "██")
end

T["dispose cleans up child mirror buffers and tears down the worker"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)

    child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
        require("scrollbar.minimap.worker").sync_buffer(0, "")
    end)
    expect.equality(
        child.lua_func(function()
            return vim.wait(3000, function()
                local status = require("scrollbar.minimap.worker").status()
                return #status.mirrors == 1 and status.mirrors[1].complete
            end)
        end),
        true
    )

    local job_id = child.lua_get([[require("scrollbar.minimap.worker").status().job_id]])
    child.lua([[require("scrollbar.minimap.worker").dispose()]])

    local status = child.lua_get([[require("scrollbar.minimap.worker").status()]])
    expect.equality(status.state, "disposed")
    expect.equality(status.job_id, nil)
    expect.equality(#status.mirrors, 0)
    expect.equality(child.fn.jobwait({ job_id }, 1000)[1] ~= -1, true)
end

T["VimLeavePre autocmd disposes the worker process"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)
    local job_id = child.lua_get([[require("scrollbar.minimap.worker").status().job_id]])

    child.api.nvim_exec_autocmds("VimLeavePre", {})
    expect.equality(child.lua_get([[require("scrollbar.minimap.worker").status().state]]), "disposed")
    expect.equality(child.fn.jobwait({ job_id }, 1000)[1] ~= -1, true)
end

T["startup failure warns once and flips to sync for the rest of the session"] = function()
    local child = new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.lua([[
        package.loaded["scrollbar.test.notifications"] = {}
        vim.notify = function(message, level)
            table.insert(package.loaded["scrollbar.test.notifications"], { message = message, level = level })
        end
    ]])
    setup_worker(child, { backend = "worker", test = { fail_start = true } })

    local status = child.lua_get([[require("scrollbar.minimap.worker").status()]])
    expect.equality(status.backend, "worker")
    expect.equality(status.state, "failed")
    expect.equality(status.job_id, nil)

    -- Subsequent requests route through the sync fallback synchronously.
    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 1,
            height = 1,
            filetype = "",
            generation = 1,
            signature = "test",
            semantic_revision = 7,
            semantic_spans = {
                parent = {
                    { line = 0, start_col = 0, end_col = 3, highlight = "Fallback", priority = 1 },
                },
            },
        })
        return package.loaded["scrollbar.test.minimap_worker"].results[1]
    end)
    expect.no_equality(result, nil)
    expect.equality(result.semantic_revision, 7)
    expect.equality(result.cells[1][1].hl_group, "Fallback")

    expect.equality(child.lua_get([=[#package.loaded["scrollbar.test.notifications"]]=]), 1)
end

T["worker crash flips to sync and emits exactly one warning"] = function()
    local child = new_child()
    child.lua([[
        package.loaded["scrollbar.test.notifications"] = {}
        vim.notify = function(message, level)
            table.insert(package.loaded["scrollbar.test.notifications"], { message = message, level = level })
        end
    ]])
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)

    child.lua([[
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "abc" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0, width = 2, height = 1, filetype = "",
            generation = 1, signature = "before",
        })
    ]])
    expect.equality(wait_for_result(child, 1).ok, true)

    -- Kill the child to inject a crash.
    child.lua([[
        vim.fn.jobstop(require("scrollbar.minimap.worker").status().job_id)
    ]])
    expect.equality(
        child.lua_func(function()
            return vim.wait(3000, function()
                return require("scrollbar.minimap.worker").status().state == "failed"
            end)
        end),
        true
    )

    -- Subsequent requests should route through sync.
    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "def" })
        require("scrollbar.minimap.worker").request({
            bufnr = 0,
            width = 1,
            height = 1,
            filetype = "",
            generation = 2,
            signature = "after",
        })
        local state = package.loaded["scrollbar.test.minimap_worker"]
        return vim.wait(2000, function()
            return state.results[2] ~= nil
        end) and state.results[2].cells or nil
    end)
    expect.no_equality(result, nil)
    expect.equality(#result, 1)
    expect.equality(child.lua_get([=[#package.loaded["scrollbar.test.notifications"]]=]), 1)
end

T["repeated setup spawns a new session and disposes the prior worker"] = function()
    local child = new_child()
    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)
    local first = child.lua_get([[require("scrollbar.minimap.worker").status()]])

    setup_worker(child, { backend = "worker" })
    expect.equality(wait_for_worker_ready(child), true)
    local second = child.lua_get([[require("scrollbar.minimap.worker").status()]])

    expect.no_equality(second.session, first.session)
    expect.no_equality(second.job_id, first.job_id)
    expect.equality(child.fn.jobwait({ first.job_id }, 1000)[1] ~= -1, true)
end

return T
