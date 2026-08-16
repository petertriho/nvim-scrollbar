local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function scan(lines, pattern, options, backend)
    options = options or {}
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    if backend == "worker" then
        helpers.setup_search_worker(child, false)
    else
        helpers.setup_search(child, false)
    end

    local fixture_spec = type(lines) == "table" and lines.kind ~= nil and lines or nil
    local inline_lines = fixture_spec == nil and lines or nil

    return child.lua_func(function(input)
        if input.budget ~= nil then
            require("scrollbar.providers.search")._set_sync_budget_for_test(input.budget)
        end
        vim.o.ignorecase = input.ignorecase or false
        vim.o.smartcase = input.smartcase or false

        local buffer_lines = input.lines
        if input.fixture ~= nil then
            buffer_lines = {}
            local fixture = input.fixture
            for index = 1, fixture.count do
                if fixture.kind == "dense" then
                    buffer_lines[index] = index % 2 == 1 and "dense_a dense_b dense_b" or "dense_a plain plain"
                else
                    error("unknown fixture kind: " .. tostring(fixture.kind))
                end
            end
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)
        vim.api.nvim_win_set_cursor(0, { input.cursor_row or 1, 0 })
        vim.fn.setreg("/", input.pattern)
        vim.fn.search(input.pattern, "cw")
        local view = vim.fn.winsaveview()
        require("scrollbar.providers").refresh(vim.api.nvim_get_current_buf())
        assert(
            vim.wait(3000, function()
                return require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search ~= nil
            end),
            "scan did not publish marks"
        )
        local store = require("scrollbar.store")
        local marks = store.get(vim.api.nvim_get_current_buf()).search
        local compact = store._get_snapshot(vim.api.nvim_get_current_buf()).compact_search
        return {
            lines = vim.tbl_map(function(mark)
                return mark.line
            end, marks),
            view_preserved = vim.deep_equal(view, vim.fn.winsaveview()),
            partial = compact and compact.partial,
        }
    end, {
        lines = inline_lines,
        fixture = fixture_spec,
        pattern = pattern,
        ignorecase = options.ignorecase,
        smartcase = options.smartcase,
        budget = options.budget,
        cursor_row = options.cursor_row,
    })
end

for _, active_backend in ipairs({ "sync", "worker" }) do
    local backend = active_backend

    T[backend .. " preserves the complete window view while scanning"] = function()
        local result = scan({ "foo", "middle", "foo" }, "foo", nil, backend)
        expect.equality(result.view_preserved, true)
    end

    T[backend .. " returns zero-based marks for every match"] = function()
        expect.equality(scan({ "foo foo", "middle", "foo" }, "foo", nil, backend).lines, { 0, 0, 2 })
    end

    T[backend .. " terminates for zero-width patterns"] = function()
        expect.equality(scan({ "one", "two", "three" }, "^", nil, backend).lines, { 0, 1, 2 })
    end

    T[backend .. " supports escaped Vim alternation"] = function()
        expect.equality(scan({ "foo bar", "none" }, [[foo\|bar]], nil, backend).lines, { 0, 0 })
    end

    T[backend .. " uses starting lines for multiline matches"] = function()
        expect.equality(scan({ "foo", "middle", "bar", "foo bar" }, [[foo\_.\{-}bar]], nil, backend).lines, { 0, 3 })
    end

    T[backend .. " pattern case atoms override case options"] = function()
        expect.equality(scan({ "foo", "Foo" }, [[\CFoo]], { ignorecase = true }, backend).lines, { 1 })
    end

    T[backend .. " honors ignorecase"] = function()
        expect.equality(scan({ "foo", "Foo" }, "foo", { ignorecase = true }, backend).lines, { 0, 1 })
    end

    T[backend .. " honors smartcase"] = function()
        expect.equality(scan({ "foo", "Foo" }, "Foo", { ignorecase = true, smartcase = true }, backend).lines, { 1 })
    end
end

T["sync completes small fixtures without partial flag"] = function()
    local result = scan({ "foo", "middle", "foo" }, "foo", nil, "sync")
    expect.equality(result.partial, false)
    expect.equality(result.lines, { 0, 2 })
end

T["sync sets partial flag on stopline cap"] = function()
    local result = scan({ kind = "dense", count = 500000 }, "dense_a", { cursor_row = 1 }, "sync")
    expect.equality(result.partial, true)
    expect.equality(#result.lines > 0, true)
end

T["sync sets partial flag on per-call timeout"] = function()
    local result = scan(
        { kind = "dense", count = 500000 },
        "dense_a",
        { cursor_row = 1, budget = { stopline = 10000000, per_call_ms = 1, total_ms = 1000 } },
        "sync"
    )
    expect.equality(result.partial, true)
end

T["sync sets partial flag when between-call budget skips backward"] = function()
    local lines = {}
    for index = 1, 10 do
        lines[index] = (index == 2 or index == 8) and "foo line" or "plain line"
    end
    local result = scan(
        lines,
        "foo",
        { cursor_row = 5, budget = { total_ms = 50, per_call_ms = 100, stopline = 10000000 } },
        "sync"
    )
    expect.equality(result.partial, true)
    expect.equality(result.lines, { 7 })
end

T["sync partial result does not clear prior marks on accepted-search pattern change"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search(child, false)

    local result = child.lua_func(function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo line", "middle line", "bar line" })
        vim.api.nvim_win_set_cursor(0, { 1, 0 })

        local store = require("scrollbar.store")
        local providers = require("scrollbar.providers")

        vim.fn.setreg("/", "foo")
        vim.fn.search("foo", "cw")
        providers.refresh(vim.api.nvim_get_current_buf())
        assert(
            vim.wait(3000, function()
                return store.get(vim.api.nvim_get_current_buf()).search ~= nil
            end),
            "first scan did not publish"
        )
        local first_compact = store._get_snapshot(vim.api.nvim_get_current_buf()).compact_search
        local first_marks = store.get(vim.api.nvim_get_current_buf()).search
        local first_lines = vim.tbl_map(function(mark)
            return mark.line
        end, first_marks)

        require("scrollbar.providers.search")._set_sync_budget_for_test({
            total_ms = 1,
            per_call_ms = 100,
            stopline = 10000000,
        })

        vim.fn.setreg("/", "bar")
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        vim.fn.search("bar", "cw")
        vim.api.nvim_win_set_cursor(0, { 1, 0 })
        providers.refresh(vim.api.nvim_get_current_buf())
        assert(
            vim.wait(3000, function()
                local compact = store._get_snapshot(vim.api.nvim_get_current_buf()).compact_search
                return compact ~= nil and compact.partial == true
            end),
            "second scan did not publish partial result"
        )
        local second_compact = store._get_snapshot(vim.api.nvim_get_current_buf()).compact_search
        local second_marks = store.get(vim.api.nvim_get_current_buf()).search
        local second_lines = vim.tbl_map(function(mark)
            return mark.line
        end, second_marks)

        return {
            first_partial = first_compact and first_compact.partial,
            first_lines = first_lines,
            second_partial = second_compact and second_compact.partial,
            second_lines = second_lines,
        }
    end)

    expect.equality(result.first_partial, false)
    expect.equality(result.first_lines, { 0 })
    expect.equality(result.second_partial, true)
    expect.equality(result.second_lines, { 2 })
end

return T
