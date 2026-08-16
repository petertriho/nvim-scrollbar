local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.store"] = nil
            require("scrollbar.config").set({
                scrollbar = {
                    marks = {
                        Custom = { text = "!", priority = 1, highlight = "WarningMsg" },
                    },
                },
            })
        end,
    },
})

local function new_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)
    return bufnr
end

local function show_buffer(bufnr)
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

local function capture_notifications()
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

T["isolates providers and buffers and returns copied snapshots"] = function()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one", "two", "three" })
    local second = new_buffer({ "one", "two" })
    local marks = { { line = 1, type = "Custom", text = "x" } }

    local ok, changed = store.set("alpha", first, marks)
    expect.equality(ok, true)
    expect.equality(changed, { [first] = true })
    expect.equality(select(2, store.set("beta", first, { { line = 2, type = "Search" } })), { [first] = true })
    expect.equality(select(2, store.set("alpha", second, { { line = 0, type = "Custom" } })), { [second] = true })

    marks[1].line = 0
    local snapshot = store.get(first)
    snapshot.alpha[1].line = 0
    snapshot.beta = nil

    expect.equality(store.get(first), {
        alpha = { { line = 1, type = "Custom", text = "x" } },
        beta = { { line = 2, type = "Search" } },
    })
    expect.equality(store.get(second), {
        alpha = { { line = 0, type = "Custom" } },
    })
end

T["reuses unchanged normalized elements while replacing changed marks"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three", "four" })

    assert(store.set("alpha", bufnr, {
        { line = 0, type = "Custom", text = "x" },
        { line = 1, type = "Custom", text = "y" },
        { line = 2, type = "Custom", text = "z" },
    }))

    local changed = {
        { line = 99, type = "Custom", text = "stale" },
        { line = 1, type = "Custom", text = "y" },
        { line = 0, type = "Custom", text = "changed" },
    }
    assert(store.set("alpha", bufnr, changed))
    changed[2].text = "mutated"

    expect.equality(store.get(bufnr), {
        alpha = {
            { line = 1, type = "Custom", text = "y" },
            { line = 0, type = "Custom", text = "changed" },
        },
    })
end

T["replaces lists atomically and reports only changed buffers"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })

    expect.equality(select(2, store.set("alpha", bufnr, { { line = 0, type = "Custom" } })), { [bufnr] = true })
    expect.equality(select(2, store.set("alpha", bufnr, { { line = 0, type = "Custom" } })), {})
    expect.equality(select(2, store.set("alpha", bufnr, { { line = 2, type = "Search" } })), { [bufnr] = true })
    expect.equality(store.get(bufnr), {
        alpha = { { line = 2, type = "Search" } },
    })
end

T["stores provider-scoped minimap spans as complete copied replacements"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })
    local spans = {
        { line = 0, start_col = 0, end_col = 2, highlight = "@keyword", priority = 10 },
        { line = 2, start_col = 1, end_col = 3, highlight = "Search", priority = -1 },
    }

    local initial = store._get_snapshot(bufnr)
    local ok, changed = store.set_minimap_spans("alpha", bufnr, spans)
    expect.equality(ok, true)
    expect.equality(changed, { [bufnr] = true })

    spans[1].line = 1
    local public = store.get_minimap_spans(bufnr)
    public.alpha[1].end_col = 99
    expect.equality(store.get_minimap_spans(bufnr), {
        alpha = {
            { line = 0, start_col = 0, end_col = 2, highlight = "@keyword", priority = 10 },
            { line = 2, start_col = 1, end_col = 3, highlight = "Search", priority = -1 },
        },
    })

    local first = store._get_snapshot(bufnr)
    expect.equality(first.minimap_span_revision, initial.minimap_span_revision + 1)
    expect.equality(
        select(
            2,
            store.set_minimap_spans("alpha", bufnr, {
                { line = 1, start_col = 0, end_col = 1, highlight = "Normal", priority = 0 },
            })
        ),
        { [bufnr] = true }
    )
    expect.equality(store.get_minimap_spans(bufnr), {
        alpha = {
            { line = 1, start_col = 0, end_col = 1, highlight = "Normal", priority = 0 },
        },
    })
    expect.equality(first.minimap_spans.alpha, {
        { line = 0, start_col = 0, end_col = 2, highlight = "@keyword", priority = 10 },
        { line = 2, start_col = 1, end_col = 3, highlight = "Search", priority = -1 },
    })
end

T["stores provider-scoped minimap points as complete copied replacements"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })
    local winid = show_buffer(bufnr)
    local points = {
        { line = 0, col = 0, highlight = "Cursor", priority = 20 },
        { line = 2, col = 4, highlight = "Search", priority = -2 },
    }

    local initial = store._get_window_snapshot(winid)
    local ok, changed = store.set_minimap_points("alpha", winid, points)
    expect.equality(ok, true)
    expect.equality(changed, { [winid] = true })

    points[1].line = 1
    local public = store.get_minimap_points(winid)
    public.alpha[1].col = 99
    expect.equality(store.get_minimap_points(winid), {
        alpha = {
            { line = 0, col = 0, highlight = "Cursor", priority = 20 },
            { line = 2, col = 4, highlight = "Search", priority = -2 },
        },
    })

    local first = store._get_window_snapshot(winid)
    expect.equality(first.minimap_point_revision, initial.minimap_point_revision + 1)
    expect.equality(
        select(
            2,
            store.set_minimap_points("alpha", winid, {
                { line = 1, col = 3, highlight = "Normal", priority = 0 },
            })
        ),
        { [winid] = true }
    )
    expect.equality(store.get_minimap_points(winid), {
        alpha = {
            { line = 1, col = 3, highlight = "Normal", priority = 0 },
        },
    })
    expect.equality(first.minimap_points.alpha, {
        { line = 0, col = 0, highlight = "Cursor", priority = 20 },
        { line = 2, col = 4, highlight = "Search", priority = -2 },
    })
end

T["validates minimap spans atomically and clears only that channel"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local valid = { { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = 0 } }
    local invalid_lists = {
        false,
        { [1] = valid[1], [3] = valid[1] },
        { "span" },
        { { line = "0", start_col = 0, end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = 0.5, start_col = 0, end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = -1, start_col = 0, end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = 0, start_col = "0", end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = 0, start_col = 0.5, end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = 0, start_col = -1, end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = 0, start_col = 0, end_col = "1", highlight = "Normal", priority = 0 } },
        { { line = 0, start_col = 1, end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = 0, start_col = 2, end_col = 1, highlight = "Normal", priority = 0 } },
        { { line = 0, start_col = 0, end_col = 1, highlight = 1, priority = 0 } },
        { { line = 0, start_col = 0, end_col = 1, highlight = "", priority = 0 } },
        { { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = "0" } },
        { { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = 0.5 } },
        { { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = math.huge } },
        { { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = 0, extra = true } },
    }

    store.set("alpha", bufnr, { { line = 1, type = "Custom" } })
    for index, spans in ipairs(invalid_lists) do
        store.set_minimap_spans("alpha", bufnr, valid)
        local before = store._get_snapshot(bufnr)
        local ok, changed = store.set_minimap_spans("alpha", bufnr, spans)
        expect.equality(ok, false)
        expect.equality(changed, { [bufnr] = true })
        expect.equality(store.get_minimap_spans(bufnr), {})
        expect.equality(store.get(bufnr), { alpha = { { line = 1, type = "Custom" } } })
        expect.equality(store._get_snapshot(bufnr).revision, before.revision)
        expect.equality(store._get_snapshot(bufnr).minimap_span_revision, before.minimap_span_revision + 1)

        store.set_minimap_spans("alpha", bufnr, spans)
        expect.equality(#notifications, index)
    end

    store.set_minimap_spans("alpha", bufnr, {
        { line = 1, start_col = 0, end_col = 2, highlight = "Normal", priority = 1 },
        { line = 20, start_col = 0, end_col = 1, highlight = "Search", priority = 2 },
    })
    expect.equality(store.get_minimap_spans(bufnr), {
        alpha = {
            { line = 1, start_col = 0, end_col = 2, highlight = "Normal", priority = 1 },
        },
    })
    expect.no_equality(notifications[1].message:match("invalid minimap spans.*buffer " .. bufnr), nil)
end

T["validates minimap points atomically and clears only that channel"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local winid = show_buffer(bufnr)
    local valid = { { line = 0, col = 0, highlight = "Normal", priority = 0 } }
    local invalid_lists = {
        false,
        { [1] = valid[1], [3] = valid[1] },
        { "point" },
        { { line = "0", col = 0, highlight = "Normal", priority = 0 } },
        { { line = 0.5, col = 0, highlight = "Normal", priority = 0 } },
        { { line = -1, col = 0, highlight = "Normal", priority = 0 } },
        { { line = 0, col = "0", highlight = "Normal", priority = 0 } },
        { { line = 0, col = 0.5, highlight = "Normal", priority = 0 } },
        { { line = 0, col = -1, highlight = "Normal", priority = 0 } },
        { { line = 0, col = 0, highlight = 1, priority = 0 } },
        { { line = 0, col = 0, highlight = "", priority = 0 } },
        { { line = 0, col = 0, highlight = "Normal", priority = "0" } },
        { { line = 0, col = 0, highlight = "Normal", priority = 0.5 } },
        { { line = 0, col = 0, highlight = "Normal", priority = 0, extra = true } },
    }

    store.set_window("alpha", winid, { { line = 1, type = "Custom" } })
    for index, points in ipairs(invalid_lists) do
        store.set_minimap_points("alpha", winid, valid)
        local before = store._get_window_snapshot(winid)
        local ok, changed = store.set_minimap_points("alpha", winid, points)
        expect.equality(ok, false)
        expect.equality(changed, { [winid] = true })
        expect.equality(store.get_minimap_points(winid), {})
        expect.equality(store.get_window(winid), { alpha = { { line = 1, type = "Custom" } } })
        expect.equality(store._get_window_snapshot(winid).revision, before.revision)
        expect.equality(store._get_window_snapshot(winid).minimap_point_revision, before.minimap_point_revision + 1)

        store.set_minimap_points("alpha", winid, points)
        expect.equality(#notifications, index)
    end

    store.set_minimap_points("alpha", winid, {
        { line = 1, col = 3, highlight = "Normal", priority = 1 },
        { line = 20, col = 0, highlight = "Search", priority = 2 },
    })
    expect.equality(store.get_minimap_points(winid), {
        alpha = {
            { line = 1, col = 3, highlight = "Normal", priority = 1 },
        },
    })

    store.set_window("shared-warning", winid, { { line = -1, type = "Custom" } })
    store.set_minimap_points("shared-warning", winid, { { line = -1, col = 0, highlight = "Normal", priority = 0 } })
    expect.equality(#notifications, #invalid_lists + 2)
    expect.no_equality(notifications[1].message:match("invalid minimap points.*window " .. winid), nil)
end

T["advances mark span and point revisions independently and skips equal output"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local winid = show_buffer(bufnr)
    local spans = { { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = 1 } }
    local points = { { line = 1, col = 2, highlight = "Cursor", priority = 2 } }

    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })
    local marked_buffer = store._get_snapshot(bufnr)
    store.set_minimap_spans("alpha", bufnr, spans)
    local spanned_buffer = store._get_snapshot(bufnr)
    expect.equality(spanned_buffer.revision, marked_buffer.revision)
    expect.equality(spanned_buffer.minimap_span_revision, marked_buffer.minimap_span_revision + 1)
    expect.equality(select(2, store.set_minimap_spans("alpha", bufnr, spans)), {})
    expect.equality(rawequal(store._get_snapshot(bufnr), spanned_buffer), true)

    store.set_window("alpha", winid, { { line = 0, type = "Custom" } })
    local marked_window = store._get_window_snapshot(winid)
    store.set_minimap_points("alpha", winid, points)
    local pointed_window = store._get_window_snapshot(winid)
    expect.equality(pointed_window.revision, marked_window.revision)
    expect.equality(pointed_window.minimap_point_revision, marked_window.minimap_point_revision + 1)
    expect.equality(select(2, store.set_minimap_points("alpha", winid, points)), {})
    expect.equality(rawequal(store._get_window_snapshot(winid), pointed_window), true)

    store.set("alpha", bufnr, { { line = 1, type = "Custom" } })
    expect.equality(store._get_snapshot(bufnr).minimap_span_revision, spanned_buffer.minimap_span_revision)
    store.set_window("alpha", winid, { { line = 1, type = "Custom" } })
    expect.equality(store._get_window_snapshot(winid).minimap_point_revision, pointed_window.minimap_point_revision)
end

T["notifies channel-aware subscribers and unsubscribe is idempotent"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local winid = show_buffer(bufnr)
    local events = {}
    local unsubscribe = store.subscribe(function(event)
        table.insert(events, event)
    end)

    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })
    store.set_minimap_spans("alpha", bufnr, {
        { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = 1 },
    })
    store.set_window("beta", winid, { { line = 1, type = "Custom" } })
    store.set_minimap_points("beta", winid, {
        { line = 1, col = 2, highlight = "Cursor", priority = 2 },
    })
    store.set_minimap_points("beta", winid, {
        { line = 1, col = 2, highlight = "Cursor", priority = 2 },
    })

    expect.equality(events, {
        { scope = "buffer", channel = "marks", target = bufnr, provider = "alpha" },
        { scope = "buffer", channel = "minimap_spans", target = bufnr, provider = "alpha" },
        { scope = "window", channel = "marks", target = winid, provider = "beta" },
        { scope = "window", channel = "minimap_points", target = winid, provider = "beta" },
    })

    unsubscribe()
    unsubscribe()
    store.clear("alpha", bufnr)
    store.clear_minimap_points("beta", winid)
    expect.equality(#events, 4)
end

T["provider cleanup clears every owned channel with provider-aware events"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local winid = show_buffer(bufnr)
    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })
    store.set_minimap_spans("alpha", bufnr, {
        { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = 1 },
    })
    store.set_window("alpha", winid, { { line = 1, type = "Custom" } })
    store.set_minimap_points("alpha", winid, {
        { line = 1, col = 2, highlight = "Cursor", priority = 2 },
    })
    local buffer_before = store._get_snapshot(bufnr)
    local window_before = store._get_window_snapshot(winid)
    local events = {}
    store.subscribe(function(event)
        table.insert(events, event)
    end)

    expect.equality(store.clear_provider("alpha"), { [bufnr] = true })
    expect.equality(store.clear_window_provider("alpha"), { [winid] = true })
    expect.equality(store.get(bufnr), {})
    expect.equality(store.get_minimap_spans(bufnr), {})
    expect.equality(store.get_window(winid), {})
    expect.equality(store.get_minimap_points(winid), {})

    local buffer_after = store._get_snapshot(bufnr)
    local window_after = store._get_window_snapshot(winid)
    expect.equality(buffer_after.revision, buffer_before.revision + 1)
    expect.equality(buffer_after.minimap_span_revision, buffer_before.minimap_span_revision + 1)
    expect.equality(window_after.revision, window_before.revision + 1)
    expect.equality(window_after.minimap_point_revision, window_before.minimap_point_revision + 1)
    expect.equality(events, {
        { scope = "buffer", channel = "marks", target = bufnr, provider = "alpha" },
        { scope = "buffer", channel = "minimap_spans", target = bufnr, provider = "alpha" },
        { scope = "window", channel = "marks", target = winid, provider = "alpha" },
        { scope = "window", channel = "minimap_points", target = winid, provider = "alpha" },
    })
    expect.equality(store.clear_provider("alpha"), {})
    expect.equality(store.clear_window_provider("alpha"), {})
    expect.equality(#events, 4)
end

T["buffer and window lifecycle cleanup emits every provider channel once"] = function()
    local store = require("scrollbar.store")
    local buffer_target = new_buffer({ "one", "two" })
    local window_buffer = new_buffer({ "one", "two" })
    local window_target = show_buffer(window_buffer)
    for _, provider in ipairs({ "alpha", "beta" }) do
        store.set(provider, buffer_target, { { line = 0, type = "Custom" } })
        store.set_minimap_spans(provider, buffer_target, {
            { line = 0, start_col = 0, end_col = 1, highlight = "Normal", priority = 1 },
        })
        store.set_window(provider, window_target, { { line = 1, type = "Custom" } })
        store.set_minimap_points(provider, window_target, {
            { line = 1, col = 2, highlight = "Cursor", priority = 2 },
        })
    end
    local buffer_before = store._get_snapshot(buffer_target)
    local window_before = store._get_window_snapshot(window_target)
    local events = {}
    store.subscribe(function(event)
        table.insert(events, event)
    end)

    vim.api.nvim_buf_delete(buffer_target, { force = true })
    vim.api.nvim_win_close(window_target, true)

    local buffer_after = store._get_snapshot(buffer_target)
    local window_after = store._get_window_snapshot(window_target)
    expect.equality(buffer_after.marks, {})
    expect.equality(buffer_after.minimap_spans, {})
    expect.equality(buffer_after.revision, buffer_before.revision + 1)
    expect.equality(buffer_after.minimap_span_revision, buffer_before.minimap_span_revision + 1)
    expect.equality(window_after.marks, {})
    expect.equality(window_after.minimap_points, {})
    expect.equality(window_after.revision, window_before.revision + 1)
    expect.equality(window_after.minimap_point_revision, window_before.minimap_point_revision + 1)
    expect.equality(events, {
        { scope = "buffer", channel = "marks", target = buffer_target, provider = "alpha" },
        { scope = "buffer", channel = "marks", target = buffer_target, provider = "beta" },
        { scope = "buffer", channel = "minimap_spans", target = buffer_target, provider = "alpha" },
        { scope = "buffer", channel = "minimap_spans", target = buffer_target, provider = "beta" },
        { scope = "window", channel = "marks", target = window_target, provider = "alpha" },
        { scope = "window", channel = "marks", target = window_target, provider = "beta" },
        { scope = "window", channel = "minimap_points", target = window_target, provider = "alpha" },
        { scope = "window", channel = "minimap_points", target = window_target, provider = "beta" },
    })
end

T["tracks independent revisions and preserves trusted snapshots across no-op updates"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })
    local winid = show_buffer(bufnr)

    local initial_buffer = store._get_snapshot(bufnr)
    local initial_window = store._get_window_snapshot(winid)
    expect.equality(initial_buffer, {
        marks = {},
        revision = 0,
        minimap_spans = {},
        minimap_span_revision = 0,
    })
    expect.equality(initial_window, {
        marks = {},
        revision = 0,
        minimap_points = {},
        minimap_point_revision = 0,
    })

    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })
    local first_buffer = store._get_snapshot(bufnr)
    expect.equality(first_buffer.marks, {
        alpha = { { line = 0, type = "Custom" } },
    })
    expect.equality(first_buffer.revision, initial_buffer.revision + 1)

    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })
    expect.equality(rawequal(store._get_snapshot(bufnr), first_buffer), true)

    store.set_window("alpha", winid, { { line = 1, type = "Custom" } })
    local first_window = store._get_window_snapshot(winid)
    expect.equality(first_window.revision, initial_window.revision + 1)
    expect.equality(store._get_snapshot(bufnr).revision, first_buffer.revision)

    store.set("alpha", bufnr, { { line = 2, type = "Custom" } })
    expect.equality(store._get_snapshot(bufnr).revision, first_buffer.revision + 1)
    expect.equality(store._get_window_snapshot(winid).revision, first_window.revision)
    expect.equality(first_buffer.marks, {
        alpha = { { line = 0, type = "Custom" } },
    })
end

T["filters stale buffer marks before replacement and revision checks"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three", "four" })
    store.set("alpha", bufnr, {
        { line = 0, type = "Custom" },
        { line = 3, type = "Search" },
    })
    local before = store._get_snapshot(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 2, -1, false, {})

    local ok, changed = store.set("alpha", bufnr, {
        { line = 1, type = "Custom", text = "x" },
        { line = 3, type = "Search" },
    })
    expect.equality(ok, true)
    expect.equality(changed, { [bufnr] = true })
    local mixed = store._get_snapshot(bufnr)
    expect.equality(mixed.marks, {
        alpha = { { line = 1, type = "Custom", text = "x" } },
    })
    expect.equality(mixed.revision, before.revision + 1)

    ok, changed = store.set("alpha", bufnr, {
        { line = 1, type = "Custom", text = "x" },
        { line = 20, type = "Custom" },
    })
    expect.equality(ok, true)
    expect.equality(changed, {})
    expect.equality(rawequal(store._get_snapshot(bufnr), mixed), true)

    ok, changed = store.set("alpha", bufnr, {
        { line = 2, type = "Custom" },
        { line = 30, type = "Search" },
    })
    expect.equality(ok, true)
    expect.equality(changed, { [bufnr] = true })
    local empty = store._get_snapshot(bufnr)
    expect.equality(empty.marks, { alpha = {} })
    expect.equality(empty.revision, mixed.revision + 1)

    ok, changed = store.set("alpha", bufnr, { { line = 100, type = "Custom" } })
    expect.equality(ok, true)
    expect.equality(changed, {})
    expect.equality(rawequal(store._get_snapshot(bufnr), empty), true)
    expect.equality(notifications, {})
end

T["filters stale window marks before replacement and revision checks"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three", "four" })
    local winid = show_buffer(bufnr)
    store.set_window("alpha", winid, {
        { line = 0, type = "Custom" },
        { line = 3, type = "Search" },
    })
    local before = store._get_window_snapshot(winid)
    vim.api.nvim_buf_set_lines(bufnr, 2, -1, false, {})

    local ok, changed = store.set_window("alpha", winid, {
        { line = 1, type = "Custom", text = "x" },
        { line = 3, type = "Search" },
    })
    expect.equality(ok, true)
    expect.equality(changed, { [winid] = true })
    local mixed = store._get_window_snapshot(winid)
    expect.equality(mixed.marks, {
        alpha = { { line = 1, type = "Custom", text = "x" } },
    })
    expect.equality(mixed.revision, before.revision + 1)

    ok, changed = store.set_window("alpha", winid, {
        { line = 1, type = "Custom", text = "x" },
        { line = 20, type = "Custom" },
    })
    expect.equality(ok, true)
    expect.equality(changed, {})
    expect.equality(rawequal(store._get_window_snapshot(winid), mixed), true)

    ok, changed = store.set_window("alpha", winid, {
        { line = 2, type = "Custom" },
        { line = 30, type = "Search" },
    })
    expect.equality(ok, true)
    expect.equality(changed, { [winid] = true })
    local empty = store._get_window_snapshot(winid)
    expect.equality(empty.marks, { alpha = {} })
    expect.equality(empty.revision, mixed.revision + 1)

    ok, changed = store.set_window("alpha", winid, { { line = 100, type = "Custom" } })
    expect.equality(ok, true)
    expect.equality(changed, {})
    expect.equality(rawequal(store._get_window_snapshot(winid), empty), true)
    expect.equality(notifications, {})
end

T["stores built-in search compactly while preserving ordinary public snapshots"] = function()
    local compact = require("scrollbar.providers.search_compact")
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three", "four" })
    local encoded = compact.encode({ 0, 1, 1, 3 })

    expect.equality(select(2, store._set_search_compact(bufnr, encoded)), { [bufnr] = true })
    local snapshot = store._get_snapshot(bufnr)
    expect.equality(snapshot.marks, {})
    expect.equality(snapshot.compact_search, encoded)
    expect.equality(store.get(bufnr), {
        search = {
            { line = 0, type = "Search" },
            { line = 1, type = "Search" },
            { line = 1, type = "Search" },
            { line = 3, type = "Search" },
        },
    })

    local public = store.get(bufnr)
    public.search[1].line = 2
    expect.equality(store.get(bufnr).search[1].line, 0)
    expect.equality(select(2, store._set_search_compact(bufnr, encoded)), {})
    expect.equality(rawequal(store._get_snapshot(bufnr), snapshot), true)

    expect.equality(store.clear("search", bufnr), { [bufnr] = true })
    expect.equality(store.get(bufnr), {})
end

T["ordinary providers keep the public mark contract when compact search exists"] = function()
    local compact = require("scrollbar.providers.search_compact")
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })

    store._set_search_compact(bufnr, compact.encode({ 0, 2 }))
    expect.equality(select(2, store.set("custom", bufnr, { { line = 1, type = "Custom", text = "x" } })), {
        [bufnr] = true,
    })
    expect.equality(store.get(bufnr), {
        custom = { { line = 1, type = "Custom", text = "x" } },
        search = {
            { line = 0, type = "Search" },
            { line = 2, type = "Search" },
        },
    })

    expect.equality(select(2, store.set("search", bufnr, { { line = 1, type = "Search" } })), { [bufnr] = true })
    expect.equality(store._get_snapshot(bufnr).compact_search, nil)
    expect.equality(store.get(bufnr).search, { { line = 1, type = "Search" } })
end

T["clears one entry, a provider, or a buffer with targeted change reporting"] = function()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one", "two" })
    local second = new_buffer({ "one", "two" })

    store.set("alpha", first, { { line = 0, type = "Custom" } })
    store.set("alpha", second, { { line = 0, type = "Custom" } })
    store.set("beta", first, { { line = 1, type = "Search" } })

    expect.equality(store.clear("beta", first), { [first] = true })
    expect.equality(store.clear("beta", first), {})
    expect.equality(store.clear_provider("alpha"), { [first] = true, [second] = true })
    expect.equality(store.get(first), {})
    expect.equality(store.get(second), {})

    store.set("alpha", first, { { line = 0, type = "Custom" } })
    store.set("beta", first, { { line = 1, type = "Search" } })
    expect.equality(store.clear_buffer(first), { [first] = true })
    expect.equality(store.clear_buffer(first), {})
end

T["advances revisions only for effective clear operations"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local winid = show_buffer(bufnr)
    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })
    store.set("beta", bufnr, { { line = 1, type = "Search" } })
    store.set_window("alpha", winid, { { line = 0, type = "Custom" } })

    local buffer_before = store._get_snapshot(bufnr)
    local window_before = store._get_window_snapshot(winid)
    expect.equality(store.clear("missing", bufnr), {})
    expect.equality(store.clear_window("missing", winid), {})
    expect.equality(rawequal(store._get_snapshot(bufnr), buffer_before), true)
    expect.equality(rawequal(store._get_window_snapshot(winid), window_before), true)

    expect.equality(store.clear("alpha", bufnr), { [bufnr] = true })
    local buffer_after = store._get_snapshot(bufnr)
    expect.equality(buffer_after.revision, buffer_before.revision + 1)
    expect.equality(buffer_after.marks, {
        beta = { { line = 1, type = "Search" } },
    })
    expect.equality(buffer_before.marks.alpha, { { line = 0, type = "Custom" } })
    expect.equality(store._get_window_snapshot(winid).revision, window_before.revision)

    expect.equality(store.clear_window("alpha", winid), { [winid] = true })
    local window_after = store._get_window_snapshot(winid)
    expect.equality(window_after.revision, window_before.revision + 1)
    expect.equality(window_after.marks, {})
    expect.equality(store.clear_window("alpha", winid), {})
    expect.equality(rawequal(store._get_window_snapshot(winid), window_after), true)
end

T["provider disposal advances only affected buffer and window revisions"] = function()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one", "two" })
    local second = new_buffer({ "one", "two" })
    local winid = show_buffer(first)
    store.set("alpha", first, { { line = 0, type = "Custom" } })
    store.set("beta", first, { { line = 1, type = "Search" } })
    store.set("alpha", second, { { line = 0, type = "Custom" } })
    store.set_window("alpha", winid, { { line = 0, type = "Custom" } })

    local first_before = store._get_snapshot(first)
    local second_before = store._get_snapshot(second)
    local window_before = store._get_window_snapshot(winid)
    expect.equality(store.clear_provider("alpha"), { [first] = true, [second] = true })
    local first_after = store._get_snapshot(first)
    local second_after = store._get_snapshot(second)
    expect.equality(first_after.revision, first_before.revision + 1)
    expect.equality(second_after.revision, second_before.revision + 1)
    expect.equality(first_after.marks, {
        beta = { { line = 1, type = "Search" } },
    })
    expect.equality(second_after.marks, {})
    expect.equality(store._get_window_snapshot(winid).revision, window_before.revision)
    expect.equality(store.clear_provider("alpha"), {})
    expect.equality(rawequal(store._get_snapshot(first), first_after), true)
    expect.equality(rawequal(store._get_snapshot(second), second_after), true)

    expect.equality(store.clear_window_provider("alpha"), { [winid] = true })
    local window_after = store._get_window_snapshot(winid)
    expect.equality(window_after.revision, window_before.revision + 1)
    expect.equality(window_after.marks, {})
    expect.equality(store.clear_window_provider("alpha"), {})
    expect.equality(rawequal(store._get_window_snapshot(winid), window_after), true)
end

T["validates complete lists against the current config and mark contract"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local invalid_lists = {
        false,
        { [1] = { line = 0, type = "Custom" }, [3] = { line = 1, type = "Custom" } },
        { "mark" },
        { { line = "0", type = "Custom" } },
        { { line = 0.5, type = "Custom" } },
        { { line = -1, type = "Custom" } },
        { { line = 0, type = "Missing" } },
        { { line = 0, type = "Custom", extra = true } },
        { { line = 0, type = "Custom", text = 1 } },
        { { line = 0, type = "Custom", text = "\n" } },
        { { line = 0, type = "Custom", text = "" } },
    }

    for index, marks in ipairs(invalid_lists) do
        local ok, changed = store.set("invalid-" .. index, bufnr, marks)
        expect.equality(ok, false)
        expect.equality(changed, {})
        expect.equality(store.get(bufnr), {})
    end
    expect.equality(#notifications, #invalid_lists)

    require("scrollbar.config").set({
        scrollbar = {
            marks = {
                Runtime = { text = "r", priority = 1, highlight = "Normal" },
            },
        },
    })
    local ok, changed = store.set("alpha", bufnr, { { line = 1, type = "Runtime" } })
    expect.equality(ok, true)
    expect.equality(changed, { [bufnr] = true })
end

T["accepts types configured only for minimap overlays"] = function()
    require("scrollbar.config").set({
        scrollbar = {},
        minimap = {
            overlays = {
                types = {
                    MinimapOnly = { priority = 1, highlight = "Special" },
                },
            },
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    config = {
                        overlays = {
                            types = {
                                ProfileOnly = { priority = 2, highlight = "Question" },
                            },
                        },
                    },
                },
            },
        },
    })
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })

    local ok, changed = store.set("alpha", bufnr, {
        { line = 0, type = "ProfileOnly" },
        { line = 1, type = "MinimapOnly" },
    })
    expect.equality(ok, true)
    expect.equality(changed, { [bufnr] = true })
    expect.equality(store.get(bufnr), {
        alpha = {
            { line = 0, type = "ProfileOnly" },
            { line = 1, type = "MinimapOnly" },
        },
    })
end

T["stale positions do not hide malformed fields in atomic replacements"] = function()
    capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })

    local ok, changed = store.set("alpha", bufnr, {
        { line = 1, type = "Custom" },
        { line = 2, type = "Missing" },
    })

    expect.equality(ok, false)
    expect.equality(changed, { [bufnr] = true })
    expect.equality(store.get(bufnr), {})
end

T["rate limits warnings by provider, buffer, and signature until success"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local first = new_buffer({ "one" })
    local second = new_buffer({ "one" })
    local invalid_line = { { line = -1, type = "Custom" } }

    store.set("alpha", first, invalid_line)
    store.set("alpha", first, invalid_line)
    expect.equality(#notifications, 1)

    store.set("alpha", first, { { line = 0, type = "Missing" } })
    store.set("beta", first, invalid_line)
    store.set("alpha", second, invalid_line)
    expect.equality(#notifications, 4)

    local ok = store.set("alpha", first, { { line = 0, type = "Custom" } })
    expect.equality(ok, true)
    store.set("alpha", first, invalid_line)
    expect.equality(#notifications, 5)
    expect.equality(notifications[1].level, vim.log.levels.WARN)
    expect.no_equality(notifications[1].message:match("provider 'alpha'.*buffer " .. first), nil)
end

T["removes marks when a buffer is deleted"] = function()
    local store = require("scrollbar.store")
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "one" })
    store.set("alpha", bufnr, { { line = 0, type = "Custom" } })
    local before = store._get_snapshot(bufnr)

    vim.api.nvim_buf_delete(bufnr, { force = true })

    expect.equality(store.get(bufnr), {})
    local after = store._get_snapshot(bufnr)
    expect.equality(after.revision, before.revision + 1)
    expect.equality(after.marks, {})
    expect.equality(before.marks, {
        alpha = { { line = 0, type = "Custom" } },
    })
    expect.equality(store.clear_buffer(bufnr), {})
    expect.equality(rawequal(store._get_snapshot(bufnr), after), true)
end

T["isolates window marks and removes them when a window closes"] = function()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two", "three" })
    local first = show_buffer(bufnr)
    local second = show_buffer(bufnr)
    local marks = { { line = 0, type = "Custom", text = "x" } }

    expect.equality(select(2, store.set_window("alpha", first, marks)), { [first] = true })
    expect.equality(select(2, store.set_window("alpha", second, { { line = 2, type = "Custom" } })), {
        [second] = true,
    })
    expect.equality(select(2, store.set_window("alpha", first, marks)), {})

    marks[1].line = 1
    local snapshot = store.get_window(first)
    snapshot.alpha[1].line = 2
    expect.equality(store.get_window(first), {
        alpha = { { line = 0, type = "Custom", text = "x" } },
    })
    expect.equality(store.get_window(second), {
        alpha = { { line = 2, type = "Custom" } },
    })

    local before_close = store._get_window_snapshot(first)
    vim.api.nvim_win_close(first, true)
    expect.equality(store.get_window(first), {})
    local after_close = store._get_window_snapshot(first)
    expect.equality(after_close.revision, before_close.revision + 1)
    expect.equality(after_close.marks, {})
    expect.equality(before_close.marks, {
        alpha = { { line = 0, type = "Custom", text = "x" } },
    })
    expect.equality(store.get_window(second), {
        alpha = { { line = 2, type = "Custom" } },
    })
end

T["validates and clears window marks with targeted change reporting"] = function()
    local notifications = capture_notifications()
    local store = require("scrollbar.store")
    local bufnr = new_buffer({ "one", "two" })
    local first = show_buffer(bufnr)
    local second = show_buffer(bufnr)

    store.set_window("alpha", first, { { line = 0, type = "Custom" } })
    store.set_window("alpha", second, { { line = 1, type = "Custom" } })
    store.set_window("beta", first, { { line = 1, type = "Search" } })

    expect.equality(store.clear_window("beta", first), { [first] = true })
    expect.equality(store.clear_window("beta", first), {})
    expect.equality(store.clear_window_provider("alpha"), { [first] = true, [second] = true })
    expect.equality(store.get_window(first), {})
    expect.equality(store.get_window(second), {})

    local ok, changed = store.set_window("invalid", first, { { line = -1, type = "Custom" } })
    expect.equality(ok, false)
    expect.equality(changed, {})
    store.set_window("invalid", first, { { line = -1, type = "Custom" } })
    expect.equality(#notifications, 1)
    expect.no_equality(notifications[1].message:match("provider 'invalid'.*window " .. first), nil)

    ok = store.set_window("invalid", first, { { line = 1, type = "Custom" } })
    expect.equality(ok, true)
    store.set_window("invalid", first, { { line = -1, type = "Custom" } })
    expect.equality(#notifications, 2)
end

return T
