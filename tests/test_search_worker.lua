local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_worker_child(incsearch, worker_test)
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    helpers.setup_search_worker(child, incsearch, worker_test)
    return child
end

T["worker preserves exact Vim search semantics"] = function()
    local cases = {
        { lines = { "foo foo", "middle", "foo" }, pattern = "foo", expected = { 0, 0, 2 } },
        { lines = { "one", "two", "three" }, pattern = "^", expected = { 0, 1, 2 } },
        { lines = { "foo bar", "none" }, pattern = [[foo\|bar]], expected = { 0, 0 } },
        {
            lines = { "foo", "middle", "bar", "foo bar" },
            pattern = [[foo\_.\{-}bar]],
            expected = { 0, 3 },
        },
    }

    for _, case in ipairs(cases) do
        local child = new_worker_child(false)
        helpers.set_lines(child, case.lines)
        helpers.accept_search(child, "/", case.pattern)
        expect.equality(helpers.wait_for_mark_lines(child, case.expected), true)
    end
end

T["worker applies case, magic, and iskeyword options explicitly"] = function()
    local child = new_worker_child(false)
    local result = child.lua_get([=[(function()
        vim.o.ignorecase = true
        vim.o.smartcase = true
        vim.o.magic = false
        vim.bo.iskeyword = "@,48-57,_,192-255,-"
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo", "Foo", "foo-bar", "foo bar" })
        vim.fn.setreg("/", [[\<foo\>]])
        vim.fn.search([[\<foo\>]], "cw")
        require("scrollbar.providers").refresh(vim.api.nvim_get_current_buf())
        local completed = vim.wait(3000, function()
            local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
            return marks ~= nil
        end)
        local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
        return {
            completed = completed,
            lines = marks and vim.tbl_map(function(mark)
                return mark.line
            end, marks) or nil,
        }
    end)()]=])

    expect.equality(result.completed, true)
    expect.equality(result.lines, { 0, 1, 3 })
end

T["initial snapshots restart after edits and only complete versions scan"] = function()
    local child = new_worker_child(false, { chunk_size = 1 })
    local result = child.lua_get([[(function()
        local lines = {}
        for index = 1, 200 do
            lines[index] = index == 200 and "target" or "none"
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        vim.fn.setreg("/", "target")
        vim.fn.search("target", "cw")
        require("scrollbar.providers").refresh(vim.api.nvim_get_current_buf())
        vim.schedule(function()
            vim.api.nvim_buf_set_lines(0, 0, 1, false, { "target" })
            vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
        end)
        local completed = vim.wait(5000, function()
            local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
            return marks ~= nil and #marks == 2
        end)
        local marks = require("scrollbar.store").get(vim.api.nvim_get_current_buf()).search
        return {
            completed = completed,
            lines = marks and vim.tbl_map(function(mark)
                return mark.line
            end, marks) or nil,
            status = require("scrollbar.providers.search_worker").status(),
        }
    end)()]])

    expect.equality(result.completed, true)
    expect.equality(result.lines, { 0, 199 })
    expect.equality(result.status.mirrors[1].complete, true)
end

T["incremental deltas update worker mirrors"] = function()
    local child = new_worker_child(false)
    helpers.set_lines(child, { "start", "target", "none" })
    helpers.accept_search(child, "/", "target")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)

    child.lua([[
        vim.api.nvim_buf_set_lines(0, 1, 2, false, { "target", "target" })
        vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
    ]])
    expect.equality(helpers.wait_for_mark_lines(child, { 1, 2 }), true)
end

T["one child is shared across mirrored buffers"] = function()
    local child = new_worker_child(false)
    helpers.set_lines(child, { "start", "match" })
    helpers.accept_search(child, "/", "match")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)

    local result = child.lua_get([[(function()
        vim.cmd("vsplit")
        local first = vim.api.nvim_get_current_buf()
        local second = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(second, 0, -1, false, { "none", "match" })
        vim.api.nvim_win_set_buf(0, second)
        local completed = vim.wait(3000, function()
            local marks = require("scrollbar.store").get(second).search
            return marks ~= nil and #marks == 1 and marks[1].line == 1
        end)
        local status = require("scrollbar.providers.search_worker").status()
        vim.api.nvim_buf_delete(second, { force = true })
        local detached = vim.wait(1000, function()
            return #require("scrollbar.providers.search_worker").status().mirrors == 1
        end)
        return {
            completed = completed,
            detached = detached,
            first = first,
            second = second,
            status = status,
        }
    end)()]])

    expect.equality(result.completed, true)
    expect.equality(result.detached, true)
    expect.equality(result.status.state, "ready")
    expect.equality(#result.status.mirrors, 2)
    expect.no_equality(result.status.job_id, nil)
    expect.equality(result.status.argv, {
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

T["worker incsearch override previews and restores the accepted result"] = function()
    local child = new_worker_child(true)
    child.o.incsearch = false
    helpers.set_lines(child, { "start", "accepted", "preview", "preview" })
    helpers.accept_search(child, "/", "accepted")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)

    expect.equality(helpers.inspect_during_cmdline(child, "/", "preview").lines, { 2, 3 })
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    expect.equality(child.o.incsearch, false)
end

T["rapid replacements retain one scan and publish only the newest request"] = function()
    local child = new_worker_child(false, { scan_delay_ms = 150 })
    helpers.set_lines(child, { "start", "first", "second", "latest" })
    helpers.accept_search(child, "/", "first")
    expect.equality(
        child.lua_get([[vim.wait(3000, function()
            return require("scrollbar.providers.search_worker").status().in_flight ~= nil
        end)]]),
        true
    )

    local responsive = child.lua_get([[(function()
        local fired = false
        vim.defer_fn(function()
            fired = true
        end, 10)
        for _, pattern in ipairs({ "second", "latest" }) do
            vim.fn.setreg("/", pattern)
            vim.api.nvim_exec_autocmds("SafeState", { buffer = 0 })
        end
        vim.wait(75, function()
            return fired
        end)
        return fired
    end)()]])

    expect.equality(responsive, true)
    expect.equality(helpers.wait_for_mark_lines(child, { 3 }), true)
    local result = child.lua_get([[(function()
        local snapshot = require("scrollbar.store")._get_snapshot(vim.api.nvim_get_current_buf())
        return {
            status = require("scrollbar.providers.search_worker").status(),
            compact_count = snapshot.compact_search and snapshot.compact_search.count or nil,
            ordinary_search = snapshot.marks.search,
        }
    end)()]])
    local status = result.status
    expect.equality(status.max_in_flight, 1)
    expect.equality(status.pending_count, 0)
    expect.equality(result.compact_count, 1)
    expect.equality(result.ordinary_search, nil)
end

T["obsolete worker callbacks cannot publish into a new session"] = function()
    local child = new_worker_child(false)
    expect.equality(helpers.wait_for_worker_status(child, "ready"), true)
    local old_session = child.lua_get([[require("scrollbar.providers.search_worker").status().session]])

    child.lua([[
        local providers = require("scrollbar.providers")
        providers.dispose()
        providers.setup({ config = require("scrollbar.config").get() })
    ]])
    expect.equality(helpers.wait_for_worker_status(child, "ready"), true)
    child.lua_func(function(session)
        -- selene: allow(global_usage)
        _G.__scrollbar_search_worker_callback(session, "result", {
            bufnr = vim.api.nvim_get_current_buf(),
            generation = 999,
            signature = "obsolete",
            mirror = { id = 999, version = 999, changedtick = 999 },
            lines = { 0 },
        })
    end, old_session)

    helpers.set_lines(child, { "none", "current" })
    helpers.accept_search(child, "/", "current")
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
end

T["startup failure warns once and falls back through the synchronous scheduler"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.lua([[
        package.loaded["scrollbar.test.notifications"] = {}
        vim.notify = function(message, level)
            table.insert(package.loaded["scrollbar.test.notifications"], { message = message, level = level })
        end
    ]])
    helpers.setup_search_worker(child, false, { fail_start = true })
    helpers.set_lines(child, { "fallback", "fallback" })
    helpers.accept_search(child, "/", "fallback")

    expect.equality(helpers.wait_for_mark_lines(child, { 0, 1 }), true)
    expect.equality(child.lua_get([=[#package.loaded["scrollbar.test.notifications"]]=]), 1)
    expect.equality(child.lua_get([[require("scrollbar.providers.search_worker").status().state]]), "failed")
    expect.equality(
        child.lua_get([[(function()
            local snapshot = require("scrollbar.store")._get_snapshot(vim.api.nvim_get_current_buf())
            return snapshot.compact_search ~= nil and snapshot.compact_search.count == 2 and snapshot.marks.search == nil
        end)()]]),
        true
    )
end

T["worker crashes reroute in-flight and future requests through exact fallback"] = function()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.lua([[
        package.loaded["scrollbar.test.notifications"] = {}
        vim.notify = function(message, level)
            table.insert(package.loaded["scrollbar.test.notifications"], { message = message, level = level })
        end
    ]])
    helpers.setup_search_worker(child, false, { scan_delay_ms = 500 })
    helpers.set_lines(child, { "start", "worker", "fallback" })
    helpers.accept_search(child, "/", "worker")
    expect.equality(
        child.lua_get([[vim.wait(3000, function()
            return require("scrollbar.providers.search_worker").status().in_flight ~= nil
        end)]]),
        true
    )

    child.lua([[
        vim.fn.jobstop(require("scrollbar.providers.search_worker").status().job_id)
    ]])
    expect.equality(helpers.wait_for_worker_status(child, "failed"), true)
    expect.equality(helpers.wait_for_mark_lines(child, { 1 }), true)
    helpers.accept_search(child, "/", "fallback")

    expect.equality(helpers.wait_for_mark_lines(child, { 2 }), true)
    expect.equality(child.lua_get([=[#package.loaded["scrollbar.test.notifications"]]=]), 1)
end

T["repeated setup, disposal, and parent shutdown clean worker ownership"] = function()
    local child = new_worker_child(false)
    expect.equality(helpers.wait_for_worker_status(child, "ready"), true)
    local first = child.lua_get([[require("scrollbar.providers.search_worker").status()]])

    child.lua([[
        local providers = require("scrollbar.providers")
        providers.dispose()
        providers.setup({ config = require("scrollbar.config").get() })
    ]])
    expect.equality(helpers.wait_for_worker_status(child, "ready"), true)
    local second = child.lua_get([[require("scrollbar.providers.search_worker").status()]])
    expect.no_equality(second.session, first.session)
    expect.no_equality(second.job_id, first.job_id)
    expect.equality(child.fn.jobwait({ first.job_id }, 0)[1] ~= -1, true)

    child.api.nvim_exec_autocmds("VimLeavePre", {})
    expect.equality(child.lua_get([[require("scrollbar.providers.search_worker").status().state]]), "disposed")
    expect.equality(child.fn.jobwait({ second.job_id }, 1000)[1] ~= -1, true)
end

return T
