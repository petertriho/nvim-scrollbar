local MiniTest = MiniTest
local expect = MiniTest.expect

local original_coc_action
local original_ale_buffer_info
local original_loaded_signify

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            local providers = package.loaded["scrollbar.providers"]
            if providers then
                providers.dispose()
            end

            original_coc_action = rawget(vim.fn, "CocActionAsync")
            original_ale_buffer_info = vim.g.ale_buffer_info
            original_loaded_signify = vim.g.loaded_signify
            rawset(vim.fn, "CocActionAsync", nil)
            vim.g.ale_buffer_info = nil
            vim.g.loaded_signify = nil
            package.preload["gitsigns"] = nil
            package.loaded["gitsigns"] = nil
            rawset(package.preload, "mini.diff", nil)
            package.loaded["mini.diff"] = nil
            rawset(package.preload, "vgit.git.git_buffer_store", nil)
            package.loaded["vgit.git.git_buffer_store"] = nil
            rawset(package.preload, "vgit.settings.signs", nil)
            package.loaded["vgit.settings.signs"] = nil

            for _, module in ipairs({
                "scrollbar.config",
                "scrollbar.renderer",
                "scrollbar.store",
                "scrollbar.providers",
                "scrollbar.providers.gitsigns",
                "scrollbar.providers.mini_diff",
                "scrollbar.providers.signify",
                "scrollbar.providers.vgit",
                "scrollbar.providers.ale",
                "scrollbar.providers.coc",
            }) do
                package.loaded[module] = nil
            end
            require("scrollbar.config").set({})
        end,
        post_case = function()
            local providers = package.loaded["scrollbar.providers"]
            if providers then
                providers.dispose()
            end
            rawset(vim.fn, "CocActionAsync", original_coc_action)
            vim.g.ale_buffer_info = original_ale_buffer_info
            vim.g.loaded_signify = original_loaded_signify
            package.preload["gitsigns"] = nil
            package.loaded["gitsigns"] = nil
            rawset(package.preload, "mini.diff", nil)
            package.loaded["mini.diff"] = nil
            rawset(package.preload, "vgit.git.git_buffer_store", nil)
            package.loaded["vgit.git.git_buffer_store"] = nil
            rawset(package.preload, "vgit.settings.signs", nil)
            package.loaded["vgit.settings.signs"] = nil
        end,
    },
})

local function new_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, "/tmp/nvim-scrollbar-test-" .. bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)
    return bufnr
end

local function show_in_two_windows(first, second)
    local original_win = vim.api.nvim_get_current_win()
    local original_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_buf(original_win, first)
    vim.cmd("vsplit")
    local second_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(second_win, second)

    MiniTest.finally(function()
        if vim.api.nvim_win_is_valid(second_win) and #vim.api.nvim_list_wins() > 1 then
            vim.api.nvim_win_close(second_win, true)
        end
        if vim.api.nvim_win_is_valid(original_win) then
            vim.api.nvim_set_current_win(original_win)
            if vim.api.nvim_buf_is_valid(original_buf) then
                vim.api.nvim_win_set_buf(original_win, original_buf)
            end
        end
    end)

    return { original_win, second_win }
end

local function sorted(values)
    table.sort(values)
    return values
end

local function with_signs(names)
    for _, name in ipairs(names) do
        vim.fn.sign_define(name, { text = "x" })
    end
    MiniTest.finally(function()
        for _, name in ipairs(names) do
            pcall(vim.fn.sign_undefine, name)
        end
    end)
end

local default_vgit_main = {
    add = "GitSignsAdd",
    remove = "GitSignsDelete",
    change = "GitSignsChange",
}

local function install_vgit_store(data)
    local event_handlers = {}
    local stats = { get_calls = 0 }
    local store = {
        get = function(buffer)
            stats.get_calls = stats.get_calls + 1
            return data[tostring(buffer.bufnr)]
        end,
        on = function(event_types, handler)
            if type(event_types) == "string" then
                event_types = { event_types }
            end
            for _, event_type in ipairs(event_types) do
                event_handlers[event_type] = event_handlers[event_type] or {}
                table.insert(event_handlers[event_type], handler)
            end
        end,
    }
    rawset(package.preload, "vgit.git.git_buffer_store", function()
        return store
    end)
    return event_handlers, store, stats
end

local function dispatch_vgit_event(event_handlers, event_type, bufnr)
    for _, handler in ipairs(event_handlers[event_type] or {}) do
        handler({ bufnr = bufnr }, event_type)
    end
end

local function install_vgit_signs(main)
    rawset(package.preload, "vgit.settings.signs", function()
        return {
            get = function(_, key)
                if key == "usage" then
                    return { main = main }
                end
                return nil
            end,
        }
    end)
end

T["gitsigns fans out fallback updates, clears marks, and disposes its augroup"] = function()
    local first = new_buffer({ "1", "2", "3", "4" })
    local second = new_buffer({ "1", "2", "3", "4" })
    local windows = show_in_two_windows(first, second)
    local hunks = { [first] = {}, [second] = {} }
    local calls = {}
    package.preload["gitsigns"] = function()
        return {
            get_hunks = function(bufnr)
                table.insert(calls, bufnr)
                return hunks[bufnr]
            end,
        }
    end

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    local invalidated = {}
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        source_windows = function()
            return windows
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    calls = {}
    invalidated = {}
    hunks[first] = { { type = "add", added = { start = 2, count = 2 } } }
    hunks[second] = { { type = "delete", added = { start = 3, count = 0 } } }
    vim.api.nvim_exec_autocmds("User", { pattern = "GitSignsUpdate" })

    expect.equality(sorted(calls), sorted({ first, second }))
    expect.equality(require("scrollbar.store").get(first).gitsigns, {
        { line = 1, type = "GitAdd" },
        { line = 2, type = "GitAdd" },
    })
    expect.equality(require("scrollbar.store").get(second).gitsigns, {
        { line = 2, type = "GitDelete" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    invalidated = {}
    hunks[first] = {}
    hunks[second] = {}
    vim.api.nvim_exec_autocmds("User", { pattern = "GitSignsUpdate" })
    expect.equality(require("scrollbar.store").get(first).gitsigns, {})
    expect.equality(require("scrollbar.store").get(second).gitsigns, {})
    expect.equality(sorted(invalidated), sorted({ first, second }))

    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "GitSignsUpdate" }), 1)
    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "GitSignsUpdate" }), 0)
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
end

T["gitsigns bounds change marks to the surviving added range"] = function()
    local target = new_buffer({ "1", "2", "3", "4", "5" })
    local hunks = {}
    package.preload["gitsigns"] = function()
        return {
            get_hunks = function()
                return hunks
            end,
        }
    end

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    hunks = {
        { type = "change", added = { start = 2, count = 1 }, removed = { count = 1 } },
    }
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).gitsigns, {
        { line = 1, type = "GitChange" },
    })

    hunks = {
        { type = "change", added = { start = 2, count = 3 }, removed = { count = 1 } },
    }
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).gitsigns, {
        { line = 1, type = "GitChange" },
        { line = 2, type = "GitAdd" },
        { line = 3, type = "GitAdd" },
    })

    hunks = {
        { type = "change", added = { start = 2, count = 1 }, removed = { count = 3 } },
    }
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).gitsigns, {
        { line = 1, type = "GitChange" },
    })
end

T["mini.diff maps hunks directly and updates only the event buffer"] = function()
    local first = new_buffer({ "1", "2", "3", "4", "5", "6" })
    local second = new_buffer({ "1", "2", "3", "4", "5", "6" })
    local data = {
        [first] = {
            hunks = {
                { type = "add", buf_start = 2, buf_count = 2 },
                { type = "change", buf_start = 4, buf_count = 2, ref_count = 1 },
                { type = "delete", buf_start = 0, buf_count = 0 },
                { type = "unknown", buf_start = 6, buf_count = 1 },
            },
        },
        [second] = { hunks = { { type = "add", buf_start = 1, buf_count = 1 } } },
    }
    local calls = {}
    rawset(package.preload, "mini.diff", function()
        return {
            get_buf_data = function(bufnr)
                table.insert(calls, bufnr)
                return data[bufnr]
            end,
        }
    end)

    local invalidated = {}
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.mini_diff"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    expect.equality(require("scrollbar.store").get(first).mini_diff, {
        { line = 1, type = "MiniDiffAdd" },
        { line = 2, type = "MiniDiffAdd" },
        { line = 3, type = "MiniDiffChange" },
        { line = 4, type = "MiniDiffChange" },
        { line = 0, type = "MiniDiffDelete" },
    })
    expect.equality(require("scrollbar.store").get(second).mini_diff, {
        { line = 0, type = "MiniDiffAdd" },
    })

    calls = {}
    invalidated = {}
    data[first] = { hunks = { { type = "change", buf_start = 3, buf_count = 1, ref_count = 4 } } }
    vim.api.nvim_set_current_buf(first)
    vim.api.nvim_exec_autocmds("User", { pattern = "MiniDiffUpdated" })
    expect.equality(calls, { first })
    expect.equality(invalidated, { first })
    expect.equality(require("scrollbar.store").get(first).mini_diff, {
        { line = 2, type = "MiniDiffChange" },
    })
    expect.equality(require("scrollbar.store").get(second).mini_diff, {
        { line = 0, type = "MiniDiffAdd" },
    })

    data[first] = nil
    providers.refresh(first)
    expect.equality(require("scrollbar.store").get(first).mini_diff, {})
end

T["mini.diff event failures clear only its marks"] = function()
    local target = new_buffer({ "one", "two" })
    local fail = false
    rawset(package.preload, "mini.diff", function()
        return {
            get_buf_data = function()
                if fail then
                    error("mini.diff exploded")
                end
                return { hunks = { { type = "add", buf_start = 1, buf_count = 1 } } }
            end,
        }
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.mini_diff"))
    providers.register({
        name = "other",
        refresh = function()
            return { { line = 1, type = "Error" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    fail = true
    vim.api.nvim_set_current_buf(target)
    expect.equality(pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "MiniDiffUpdated" }), true)
    expect.equality(require("scrollbar.store").get(target), {
        other = { { line = 1, type = "Error" } },
    })
end

T["missing mini.diff still owns and disposes its update autocmd"] = function()
    local target = new_buffer({ "one" })
    rawset(package.preload, "mini.diff", function()
        error("mini.diff missing")
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.mini_diff"))
    expect.equality(
        pcall(providers.setup, {
            is_buffer_eligible = function(bufnr)
                return bufnr == target
            end,
        }),
        true
    )
    expect.equality(require("scrollbar.store").get(target).mini_diff, {})
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "MiniDiffUpdated" }), 1)

    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "MiniDiffUpdated" }), 0)
    expect.equality(require("scrollbar.store").get(target), {})
end

T["late-loaded diff modules attach without rerunning setup"] = function()
    local target = new_buffer({ "one", "two" })
    rawset(package.preload, "mini.diff", function()
        error("mini.diff missing")
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.register(require("scrollbar.providers.mini_diff"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })
    expect.equality(require("scrollbar.store").get(target), {
        gitsigns = {},
        mini_diff = {},
    })

    rawset(package.loaded, "gitsigns", {
        get_hunks = function()
            return { { type = "add", added = { start = 1, count = 1 } } }
        end,
    })
    rawset(package.loaded, "mini.diff", {
        get_buf_data = function()
            return { hunks = { { type = "change", buf_start = 2, buf_count = 1 } } }
        end,
    })

    vim.api.nvim_set_current_buf(target)
    vim.api.nvim_exec_autocmds("User", { pattern = "GitSignsUpdate", data = { buffer = target } })
    vim.api.nvim_exec_autocmds("User", { pattern = "MiniDiffUpdated" })
    expect.equality(require("scrollbar.store").get(target), {
        gitsigns = { { line = 0, type = "GitAdd" } },
        mini_diff = { { line = 1, type = "MiniDiffChange" } },
    })
end

T["signify maps placed Signify signs to add/change/delete marks"] = function()
    local target = new_buffer({ "1", "2", "3", "4", "5" })
    local sign_names = {
        "SignifyAdd",
        "SignifyChange",
        "SignifyChangeDelete",
        "SignifyRemoveFirstLine",
        "SignifyDelete5",
    }
    with_signs(sign_names)

    vim.fn.sign_place(0, "", "SignifyAdd", target, { lnum = 1 })
    vim.fn.sign_place(0, "", "SignifyChange", target, { lnum = 2 })
    vim.fn.sign_place(0, "", "SignifyChangeDelete", target, { lnum = 3 })
    vim.fn.sign_place(0, "", "SignifyRemoveFirstLine", target, { lnum = 4 })
    vim.fn.sign_place(0, "", "SignifyDelete5", target, { lnum = 5 })
    vim.g.loaded_signify = 1

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.signify"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    expect.equality(require("scrollbar.store").get(target).signify, {
        { line = 0, type = "SignifyAdd" },
        { line = 1, type = "SignifyChange" },
        { line = 2, type = "SignifyChange" },
        { line = 3, type = "SignifyDelete" },
        { line = 4, type = "SignifyDelete" },
    })
end

T["signify fans out User Signify updates and clears marks"] = function()
    local first = new_buffer({ "1", "2", "3", "4" })
    local second = new_buffer({ "1", "2", "3", "4" })
    local windows = show_in_two_windows(first, second)
    with_signs({ "SignifyAdd", "SignifyChange", "SignifyDelete5" })

    vim.g.loaded_signify = 1

    local invalidated = {}
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.signify"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        source_windows = function()
            return windows
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    expect.equality(require("scrollbar.store").get(first).signify, {})
    expect.equality(require("scrollbar.store").get(second).signify, {})

    invalidated = {}
    vim.fn.sign_place(0, "", "SignifyAdd", first, { lnum = 2 })
    vim.fn.sign_place(0, "", "SignifyChange", second, { lnum = 3 })
    vim.api.nvim_exec_autocmds("User", { pattern = "Signify" })
    expect.equality(require("scrollbar.store").get(first).signify, {
        { line = 1, type = "SignifyAdd" },
    })
    expect.equality(require("scrollbar.store").get(second).signify, {
        { line = 2, type = "SignifyChange" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    invalidated = {}
    vim.fn.sign_place(0, "", "SignifyDelete5", first, { lnum = 4 })
    vim.fn.sign_place(0, "", "SignifyDelete5", second, { lnum = 1 })
    vim.api.nvim_exec_autocmds("User", { pattern = "Signify" })
    expect.equality(require("scrollbar.store").get(first).signify, {
        { line = 1, type = "SignifyAdd" },
        { line = 3, type = "SignifyDelete" },
    })
    expect.equality(require("scrollbar.store").get(second).signify, {
        { line = 0, type = "SignifyDelete" },
        { line = 2, type = "SignifyChange" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    invalidated = {}
    vim.fn.sign_unplace("*", { buffer = first })
    vim.fn.sign_unplace("*", { buffer = second })
    vim.api.nvim_exec_autocmds("User", { pattern = "Signify" })
    expect.equality(require("scrollbar.store").get(first).signify, {})
    expect.equality(require("scrollbar.store").get(second).signify, {})
    expect.equality(sorted(invalidated), sorted({ first, second }))

    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "Signify" }), 1)
    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "Signify" }), 0)
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
end

T["missing signify dependency still owns and disposes its autocmd"] = function()
    local target = new_buffer({ "one" })

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.signify"))
    expect.equality(
        pcall(providers.setup, {
            is_buffer_eligible = function(bufnr)
                return bufnr == target
            end,
        }),
        true
    )
    expect.equality(require("scrollbar.store").get(target).signify, {})
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "Signify" }), 1)

    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "Signify" }), 0)
    expect.equality(require("scrollbar.store").get(target), {})
end

T["late-loaded signify attaches marks after User Signify"] = function()
    local target = new_buffer({ "one", "two" })
    with_signs({ "SignifyAdd", "SignifyChange" })

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.signify"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })
    expect.equality(require("scrollbar.store").get(target).signify, {})

    vim.fn.sign_place(0, "", "SignifyAdd", target, { lnum = 1 })
    vim.fn.sign_place(0, "", "SignifyChange", target, { lnum = 2 })
    vim.g.loaded_signify = 1
    vim.api.nvim_set_current_buf(target)
    vim.api.nvim_exec_autocmds("User", { pattern = "Signify" })

    expect.equality(require("scrollbar.store").get(target).signify, {
        { line = 0, type = "SignifyAdd" },
        { line = 1, type = "SignifyChange" },
    })
end

T["vgit maps state.signs to VGitAdd/VGitChange/VGitDelete via usage.main"] = function()
    local first = new_buffer({ "1", "2", "3", "4", "5" })
    local second = new_buffer({ "1", "2", "3", "4", "5" })
    local data = {
        [tostring(first)] = {
            state = {
                signs = {
                    { col = 1, name = "GitSignsAdd" },
                    { col = 2, name = "GitSignsChange" },
                    { col = 0, name = "GitSignsDelete" },
                    { col = 3, name = "UnknownSign" },
                    { col = -1, name = "GitSignsAdd" },
                },
            },
        },
        [tostring(second)] = {
            state = {
                signs = {
                    { col = 4, name = "GitSignsAdd" },
                },
            },
        },
    }
    install_vgit_store(data)
    install_vgit_signs(default_vgit_main)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.vgit"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
    })

    expect.equality(require("scrollbar.store").get(first).vgit, {
        { line = 1, type = "VGitAdd" },
        { line = 2, type = "VGitChange" },
        { line = 0, type = "VGitDelete" },
    })
    expect.equality(require("scrollbar.store").get(second).vgit, {
        { line = 4, type = "VGitAdd" },
    })
end

T["vgit sync event updates marks per buffer and clears on dispose"] = function()
    local first = new_buffer({ "1", "2", "3", "4" })
    local second = new_buffer({ "1", "2", "3", "4" })
    local data = {
        [tostring(first)] = { state = { signs = {} } },
        [tostring(second)] = { state = { signs = {} } },
    }
    local handlers = install_vgit_store(data)
    install_vgit_signs(default_vgit_main)

    local vgit = require("scrollbar.providers.vgit")
    vgit.update_delay_ms = 0

    local providers = require("scrollbar.providers")
    providers.register(vgit)
    local invalidated = {}
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    invalidated = {}
    data[tostring(first)] = {
        state = { signs = { { col = 1, name = "GitSignsAdd" } } },
    }
    data[tostring(second)] = {
        state = { signs = { { col = 2, name = "GitSignsDelete" } } },
    }
    dispatch_vgit_event(handlers, "sync", first)
    dispatch_vgit_event(handlers, "sync", second)
    vim.wait(50)

    expect.equality(require("scrollbar.store").get(first).vgit, {
        { line = 1, type = "VGitAdd" },
    })
    expect.equality(require("scrollbar.store").get(second).vgit, {
        { line = 2, type = "VGitDelete" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    invalidated = {}
    data[tostring(first)] = { state = { signs = {} } }
    data[tostring(second)] = { state = { signs = {} } }
    dispatch_vgit_event(handlers, "sync", first)
    dispatch_vgit_event(handlers, "sync", second)
    vim.wait(50)
    expect.equality(require("scrollbar.store").get(first).vgit, {})
    expect.equality(require("scrollbar.store").get(second).vgit, {})
    expect.equality(sorted(invalidated), sorted({ first, second }))

    providers.dispose()
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
end

T["vgit change event refreshes only the event buffer"] = function()
    local first = new_buffer({ "1", "2", "3" })
    local second = new_buffer({ "1", "2", "3" })
    local data = {
        [tostring(first)] = {
            state = { signs = { { col = 0, name = "GitSignsAdd" } } },
        },
        [tostring(second)] = {
            state = { signs = { { col = 1, name = "GitSignsChange" } } },
        },
    }
    local handlers = install_vgit_store(data)
    install_vgit_signs(default_vgit_main)

    local vgit = require("scrollbar.providers.vgit")
    vgit.update_delay_ms = 0

    local invalidated = {}
    local providers = require("scrollbar.providers")
    providers.register(vgit)
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    expect.equality(require("scrollbar.store").get(first).vgit, {
        { line = 0, type = "VGitAdd" },
    })
    expect.equality(require("scrollbar.store").get(second).vgit, {
        { line = 1, type = "VGitChange" },
    })

    invalidated = {}
    data[tostring(first)] = {
        state = { signs = { { col = 2, name = "GitSignsDelete" } } },
    }
    dispatch_vgit_event(handlers, "change", first)
    vim.wait(50)

    expect.equality(require("scrollbar.store").get(first).vgit, {
        { line = 2, type = "VGitDelete" },
    })
    expect.equality(require("scrollbar.store").get(second).vgit, {
        { line = 1, type = "VGitChange" },
    })
    expect.equality(invalidated, { first })
end

T["late-loaded vgit subscribes on manual refresh"] = function()
    local target = new_buffer({ "one", "two", "three" })
    local invalidated = {}
    local providers = require("scrollbar.providers")
    local vgit = require("scrollbar.providers.vgit")
    vgit.update_delay_ms = 0
    providers.register(vgit)
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })
    expect.equality(require("scrollbar.store").get(target).vgit, {})

    local data = {
        [tostring(target)] = {
            state = { signs = { { col = 0, name = "GitSignsAdd" } } },
        },
    }
    local handlers, _, stats = install_vgit_store(data)
    install_vgit_signs(default_vgit_main)

    providers.refresh(target)
    expect.equality(stats.get_calls, 1)
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 0, type = "VGitAdd" },
    })
    for _, event_type in ipairs({ "attach", "reload", "change", "sync" }) do
        expect.equality(#(handlers[event_type] or {}), 1)
    end

    providers.refresh(target)
    expect.equality(stats.get_calls, 2)
    for _, event_type in ipairs({ "attach", "reload", "change", "sync" }) do
        expect.equality(#(handlers[event_type] or {}), 1)
    end

    invalidated = {}
    data[tostring(target)] = {
        state = { signs = { { col = 1, name = "GitSignsChange" } } },
    }
    dispatch_vgit_event(handlers, "change", target)
    vim.wait(50)
    expect.equality(stats.get_calls, 3)
    expect.equality(invalidated, { target })
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 1, type = "VGitChange" },
    })
end

T["vgit retained callbacks are generation-aware"] = function()
    local target = new_buffer({ "one", "two", "three" })
    local data = {
        [tostring(target)] = {
            state = { signs = { { col = 0, name = "GitSignsAdd" } } },
        },
    }
    local handlers, _, stats = install_vgit_store(data)
    install_vgit_signs(default_vgit_main)

    local vgit = require("scrollbar.providers.vgit")
    vgit.update_delay_ms = 0
    local providers = require("scrollbar.providers")
    providers.register(vgit)
    local invalidated = {}
    local options = {
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    }
    providers.setup(options)
    providers.setup(options)
    for _, event_type in ipairs({ "attach", "reload", "change", "sync" }) do
        expect.equality(#(handlers[event_type] or {}), 2)
    end

    stats.get_calls = 0
    invalidated = {}
    data[tostring(target)] = {
        state = { signs = { { col = 1, name = "GitSignsChange" } } },
    }
    handlers.sync[1]({ bufnr = target }, "sync")
    vim.wait(50)
    expect.equality(stats.get_calls, 0)
    expect.equality(invalidated, {})
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 0, type = "VGitAdd" },
    })

    dispatch_vgit_event(handlers, "sync", target)
    vim.wait(50)
    expect.equality(stats.get_calls, 1)
    expect.equality(invalidated, { target })
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 1, type = "VGitChange" },
    })

    providers.dispose()
    stats.get_calls = 0
    invalidated = {}
    dispatch_vgit_event(handlers, "sync", target)
    vim.wait(50)
    expect.equality(stats.get_calls, 0)
    expect.equality(invalidated, {})
    expect.equality(require("scrollbar.store").get(target), {})
end

T["vgit subscriptions follow the active store identity"] = function()
    local target = new_buffer({ "one", "two", "three" })
    local data_a = {
        [tostring(target)] = {
            state = { signs = { { col = 0, name = "GitSignsAdd" } } },
        },
    }
    local handlers_a = install_vgit_store(data_a)
    install_vgit_signs(default_vgit_main)

    local vgit = require("scrollbar.providers.vgit")
    vgit.update_delay_ms = 0
    local providers = require("scrollbar.providers")
    providers.register(vgit)
    local invalidated = {}
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    local data_b = {
        [tostring(target)] = {
            state = { signs = { { col = 1, name = "GitSignsChange" } } },
        },
    }
    local handlers_b, store_b, stats_b = install_vgit_store(data_b)
    package.loaded["vgit.git.git_buffer_store"] = store_b
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 1, type = "VGitChange" },
    })
    expect.equality(#handlers_a.sync, 1)
    expect.equality(#handlers_b.sync, 1)

    stats_b.get_calls = 0
    invalidated = {}
    data_b[tostring(target)] = {
        state = { signs = { { col = 2, name = "GitSignsDelete" } } },
    }
    dispatch_vgit_event(handlers_a, "sync", target)
    vim.wait(50)
    expect.equality(stats_b.get_calls, 0)
    expect.equality(invalidated, {})
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 1, type = "VGitChange" },
    })

    dispatch_vgit_event(handlers_b, "sync", target)
    vim.wait(50)
    expect.equality(stats_b.get_calls, 1)
    expect.equality(invalidated, { target })
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 2, type = "VGitDelete" },
    })
end

T["vgit collection survives unavailable subscriptions"] = function()
    local target = new_buffer({ "one", "two" })
    local data = {
        [tostring(target)] = {
            state = { signs = { { col = 0, name = "GitSignsAdd" } } },
        },
    }
    local _, store = install_vgit_store(data)
    install_vgit_signs(default_vgit_main)
    store.on = nil

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.vgit"))
    local options = {
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    }
    providers.setup(options)
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 0, type = "VGitAdd" },
    })

    store.on = function()
        error("vgit subscription failed")
    end
    providers.setup(options)
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 0, type = "VGitAdd" },
    })
end

T["missing vgit dependency leaves provider setup usable"] = function()
    local target = new_buffer({ "one" })
    rawset(package.preload, "vgit.git.git_buffer_store", function()
        error("vgit store missing")
    end)
    rawset(package.preload, "vgit.settings.signs", function()
        error("vgit signs missing")
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.vgit"))
    expect.equality(
        pcall(providers.setup, {
            is_buffer_eligible = function(bufnr)
                return bufnr == target
            end,
        }),
        true
    )
    expect.equality(require("scrollbar.store").get(target).vgit, {})

    providers.dispose()
    expect.equality(require("scrollbar.store").get(target), {})
end

T["vgit event failures clear only vgit marks"] = function()
    local target = new_buffer({ "one", "two" })
    local fail = false
    local event_handlers = {}
    rawset(package.preload, "vgit.git.git_buffer_store", function()
        return {
            get = function()
                if fail then
                    error("vgit store exploded")
                end
                return {
                    state = { signs = { { col = 0, name = "GitSignsAdd" } } },
                }
            end,
            on = function(event_types, handler)
                if type(event_types) == "string" then
                    event_types = { event_types }
                end
                for _, event_type in ipairs(event_types) do
                    event_handlers[event_type] = event_handlers[event_type] or {}
                    table.insert(event_handlers[event_type], handler)
                end
            end,
        }
    end)
    install_vgit_signs(default_vgit_main)

    local vgit = require("scrollbar.providers.vgit")
    vgit.update_delay_ms = 0

    local providers = require("scrollbar.providers")
    providers.register(vgit)
    providers.register({
        name = "other",
        refresh = function()
            return { { line = 1, type = "Error" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 0, type = "VGitAdd" },
    })

    fail = true
    dispatch_vgit_event(event_handlers, "sync", target)
    vim.wait(50)
    expect.equality(require("scrollbar.store").get(target), {
        other = { { line = 1, type = "Error" } },
    })
end

T["ALE converts one-based lines and updates only each event buffer"] = function()
    local first = new_buffer({ "1", "2", "3" })
    local second = new_buffer({ "1", "2", "3" })
    vim.g.ale_buffer_info = {
        [tostring(first)] = {
            loclist = {
                { lnum = 1, type = "E" },
                { lnum = 3, type = "W" },
            },
        },
        [tostring(second)] = {
            loclist = {
                { lnum = 2, type = "E" },
            },
        },
    }

    local invalidated = {}
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.ale"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })

    expect.equality(require("scrollbar.store").get(first).ale, {
        { line = 0, type = "Error" },
        { line = 2, type = "Warn" },
    })
    expect.equality(require("scrollbar.store").get(second).ale, {
        { line = 1, type = "Error" },
    })

    invalidated = {}
    vim.g.ale_buffer_info = {
        [tostring(first)] = { loclist = {} },
        [tostring(second)] = {
            loclist = {
                { lnum = 2, type = "E" },
            },
        },
    }
    vim.api.nvim_set_current_buf(first)
    vim.api.nvim_exec_autocmds("User", { pattern = "ALELintPost" })

    expect.equality(require("scrollbar.store").get(first).ale, {})
    expect.equality(require("scrollbar.store").get(second).ale, {
        { line = 1, type = "Error" },
    })
    expect.equality(invalidated, { first })

    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "ALELintPost" }), 1)
    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "ALELintPost" }), 0)
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
end

T["Coc asynchronously replaces all URI diagnostics and preserves severity mapping"] = function()
    local first = new_buffer({ "1", "2", "3", "4" })
    local second = new_buffer({ "1", "2", "3", "4" })
    local callbacks = {}
    rawset(vim.fn, "CocActionAsync", function(action, callback)
        expect.equality(action, "diagnosticList")
        table.insert(callbacks, callback)
    end)

    local invalidated = {}
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.coc"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == first or bufnr == second
        end,
        invalidate_buffer = function(bufnr)
            table.insert(invalidated, bufnr)
        end,
    })
    expect.equality(#callbacks, 1)

    invalidated = {}
    callbacks[1](vim.NIL, {
        {
            severity = "Error",
            location = { uri = vim.uri_from_bufnr(first), range = { start = { line = 0 } } },
        },
        {
            severity = "Information",
            location = { uri = vim.uri_from_bufnr(first), range = { start = { line = 2 } } },
        },
        {
            severity = "Warning",
            location = { uri = vim.uri_from_bufnr(second), range = { start = { line = 1 } } },
        },
    })

    expect.equality(require("scrollbar.store").get(first).coc, {
        { line = 0, type = "Error" },
        { line = 2, type = "Info" },
    })
    expect.equality(require("scrollbar.store").get(second).coc, {
        { line = 1, type = "Warn" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    callbacks[1]("request failed", {})
    expect.equality(require("scrollbar.store").get(first).coc, {
        { line = 0, type = "Error" },
        { line = 2, type = "Info" },
    })

    vim.api.nvim_exec_autocmds("User", { pattern = "CocDiagnosticChange" })
    expect.equality(#callbacks, 2)
    invalidated = {}
    callbacks[2](vim.NIL, {
        {
            severity = "Hint",
            location = { uri = vim.uri_from_bufnr(second), range = { start = { line = 3 } } },
        },
    })

    expect.equality(require("scrollbar.store").get(first).coc, {})
    expect.equality(require("scrollbar.store").get(second).coc, {
        { line = 3, type = "Hint" },
    })
    expect.equality(sorted(invalidated), sorted({ first, second }))

    providers.dispose()
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "CocDiagnosticChange" }), 0)
    expect.equality(require("scrollbar.store").get(first), {})
    expect.equality(require("scrollbar.store").get(second), {})
    expect.equality(
        pcall(callbacks[2], vim.NIL, {
            {
                severity = "Error",
                location = { uri = vim.uri_from_bufnr(first), range = { start = { line = 0 } } },
            },
        }),
        true
    )
    expect.equality(require("scrollbar.store").get(first), {})
end

T["Coc ignores diagnostic responses older than the latest request"] = function()
    local target = new_buffer({ "1", "2", "3" })
    local callbacks = {}
    rawset(vim.fn, "CocActionAsync", function(_, callback)
        table.insert(callbacks, callback)
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.coc"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })
    vim.api.nvim_exec_autocmds("User", { pattern = "CocDiagnosticChange" })
    expect.equality(#callbacks, 2)

    callbacks[2](vim.NIL, {
        {
            severity = "Warning",
            location = { uri = vim.uri_from_bufnr(target), range = { start = { line = 1 } } },
        },
    })
    callbacks[1](vim.NIL, {
        {
            severity = "Error",
            location = { uri = vim.uri_from_bufnr(target), range = { start = { line = 0 } } },
        },
    })

    expect.equality(require("scrollbar.store").get(target).coc, {
        { line = 1, type = "Warn" },
    })
end

T["optional event routes preflight ineligible buffers before collection"] = function()
    local target = new_buffer({ "one", "two" })
    local windows = show_in_two_windows(target, target)
    local calls = { gitsigns = 0, mini_diff = 0, signify = 0 }
    package.preload["gitsigns"] = function()
        return {
            get_hunks = function()
                calls.gitsigns = calls.gitsigns + 1
                return { { type = "add", added = { start = 1, count = 1 } } }
            end,
        }
    end
    rawset(package.preload, "mini.diff", function()
        return {
            get_buf_data = function()
                calls.mini_diff = calls.mini_diff + 1
                return { hunks = { { type = "add", buf_start = 1, buf_count = 1 } } }
            end,
        }
    end)
    vim.g.loaded_signify = 1
    local sign_getplaced = vim.fn.sign_getplaced
    rawset(vim.fn, "sign_getplaced", function(...)
        calls.signify = calls.signify + 1
        return sign_getplaced(...)
    end)
    MiniTest.finally(function()
        rawset(vim.fn, "sign_getplaced", sign_getplaced)
    end)
    vim.g.ale_buffer_info = {
        [tostring(target)] = { loclist = { { lnum = 1, type = "E" } } },
    }

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.register(require("scrollbar.providers.mini_diff"))
    providers.register(require("scrollbar.providers.signify"))
    providers.register(require("scrollbar.providers.ale"))
    providers.setup({
        is_buffer_eligible = function()
            return false
        end,
        source_windows = function()
            return windows
        end,
    })

    local store = require("scrollbar.store")
    for _, name in ipairs({ "gitsigns", "mini_diff", "signify", "ale" }) do
        assert(store.set(name, target, { { line = 0, type = "Error" } }))
    end
    calls = { gitsigns = 0, mini_diff = 0, signify = 0 }
    vim.api.nvim_set_current_buf(target)
    vim.api.nvim_exec_autocmds("User", { pattern = "GitSignsUpdate", data = { buffer = target } })
    vim.api.nvim_exec_autocmds("User", { pattern = "MiniDiffUpdated" })
    vim.api.nvim_exec_autocmds("User", { pattern = "Signify" })
    vim.api.nvim_exec_autocmds("User", { pattern = "ALELintPost" })

    expect.equality(calls, { gitsigns = 0, mini_diff = 0, signify = 0 })
    expect.equality(store.get(target), {})
end

T["vgit deferred callbacks recheck policy before collection"] = function()
    local target = new_buffer({ "one", "two" })
    local allowed = true
    local calls = 0
    local handlers = install_vgit_store({
        [tostring(target)] = {
            state = { signs = { { col = 0, name = "GitSignsAdd" } } },
        },
    })
    install_vgit_signs(default_vgit_main)
    package.loaded["vgit.git.git_buffer_store"] = nil
    local preload = package.preload["vgit.git.git_buffer_store"]
    rawset(package.preload, "vgit.git.git_buffer_store", function()
        local store = preload()
        local get = store.get
        store.get = function(...)
            calls = calls + 1
            return get(...)
        end
        return store
    end)

    local vgit = require("scrollbar.providers.vgit")
    vgit.update_delay_ms = 20
    local providers = require("scrollbar.providers")
    providers.register(vgit)
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target and allowed
        end,
    })
    expect.equality(require("scrollbar.store").get(target).vgit, {
        { line = 0, type = "VGitAdd" },
    })

    calls = 0
    dispatch_vgit_event(handlers, "sync", target)
    allowed = false
    vim.wait(100)

    expect.equality(calls, 0)
    expect.equality(require("scrollbar.store").get(target), {})
end

T["Coc does not retain diagnostics collected for ineligible URI buffers"] = function()
    local target = new_buffer({ "one", "two" })
    local allowed = true
    local callbacks = {}
    rawset(vim.fn, "CocActionAsync", function(_, callback)
        table.insert(callbacks, callback)
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.coc"))
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target and allowed
        end,
    })
    local diagnostics = {
        {
            severity = "Error",
            location = { uri = vim.uri_from_bufnr(target), range = { start = { line = 0 } } },
        },
    }
    callbacks[1](vim.NIL, diagnostics)
    expect.equality(require("scrollbar.store").get(target).coc, { { line = 0, type = "Error" } })

    vim.api.nvim_exec_autocmds("User", { pattern = "CocDiagnosticChange" })
    allowed = false
    callbacks[2](vim.NIL, diagnostics)
    expect.equality(require("scrollbar.store").get(target), {})

    allowed = true
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target).coc, { { line = 0, type = "Error" } })
end

T["missing optional dependencies leave runtime and provider setup usable"] = function()
    local target = new_buffer({ "one" })
    rawset(package.preload, "mini.diff", function()
        error("mini.diff missing")
    end)
    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.register(require("scrollbar.providers.mini_diff"))
    providers.register(require("scrollbar.providers.vgit"))
    providers.register(require("scrollbar.providers.ale"))
    providers.register(require("scrollbar.providers.coc"))

    expect.equality(
        pcall(providers.setup, {
            is_buffer_eligible = function(bufnr)
                return bufnr == target
            end,
        }),
        true
    )
    expect.equality(require("scrollbar.store").get(target), {
        ale = {},
        coc = {},
        gitsigns = {},
        mini_diff = {},
        vgit = {},
    })
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "GitSignsUpdate" }), 1)
    expect.equality(#vim.api.nvim_get_autocmds({ event = "User", pattern = "MiniDiffUpdated" }), 1)
    vim.api.nvim_set_current_buf(target)
    expect.equality(pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "ALELintPost" }), true)
    expect.equality(pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "CocDiagnosticChange" }), true)
end

T["manager clears only gitsigns marks when its refresh fails"] = function()
    local target = new_buffer({ "one", "two" })
    local fail = false
    package.preload["gitsigns"] = function()
        return {
            get_hunks = function()
                if fail then
                    error("gitsigns exploded")
                end
                return { { type = "add", added = { start = 1, count = 1 } } }
            end,
        }
    end
    local original_notify = vim.notify
    rawset(vim, "notify", function() end)
    MiniTest.finally(function()
        rawset(vim, "notify", original_notify)
    end)

    local providers = require("scrollbar.providers")
    providers.register(require("scrollbar.providers.gitsigns"))
    providers.register({
        name = "other",
        refresh = function()
            return { { line = 1, type = "Error" } }
        end,
    })
    providers.setup({
        is_buffer_eligible = function(bufnr)
            return bufnr == target
        end,
    })

    fail = true
    providers.refresh(target)
    expect.equality(require("scrollbar.store").get(target), {
        other = { { line = 1, type = "Error" } },
    })
end

return T
