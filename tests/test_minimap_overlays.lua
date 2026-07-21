local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.providers"] = nil
            package.loaded["scrollbar.store"] = nil
            package.loaded["scrollbar.minimap.config"] = nil
            package.loaded["scrollbar.minimap.overlays"] = nil
            require("scrollbar.config").set({
                scrollbar = {},
                minimap = { enabled = true },
            })
            local providers = require("scrollbar.providers")
            for _, name in ipairs({ "alpha", "other", "zeta" }) do
                providers.register({ name = name, targets = { minimap = true } })
            end
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

local function overlays()
    return require("scrollbar.minimap.overlays")
end

local function store()
    return require("scrollbar.store")
end

local function minimap_config()
    return require("scrollbar.minimap.config")
end

local function setup_with(options)
    options = options or {}
    overlays().setup({
        config = options.config or minimap_config().get(),
    })
end

local function source_window(bufnr)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    return winid
end

local function project(bufnr, height)
    return overlays().project(source_window(bufnr), height)
end

local function project_with(bufnr, height, line_count)
    return overlays().project_with(source_window(bufnr), height, line_count)
end

T["project returns an empty list for a buffer with no marks"] = function()
    setup_with()
    local bufnr = new_buffer({ "one", "two", "three" })

    expect.equality(project(bufnr, 4), {})
end

T["project returns an overlay per published mark of an allowed type"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    store().set("diagnostic", bufnr, { { line = 1, type = "Error" } })

    local result = project(bufnr, 4)
    expect.equality(#result, 1)
    expect.equality(result[1].source_line, 1)
    expect.equality(result[1].minimap_row, 2)
    expect.equality(result[1].mark_type, "Error")
    expect.equality(result[1].priority, 2)
    expect.equality(result[1].highlight, "ScrollbarMinimapError")
    expect.equality(result[1].provider, "diagnostic")
end

T["project computes v_ratio the same way squash does"] = function()
    setup_with()
    local bufnr = new_buffer({
        "l0",
        "l1",
        "l2",
        "l3",
        "l4",
        "l5",
        "l6",
        "l7",
    })
    -- Eight source lines into four minimap rows: v_ratio = 2.
    -- Line 0 -> row 1, line 1 -> row 1, line 2 -> row 2, ..., line 7 -> row 4.
    store().set("diagnostic", bufnr, {
        { line = 0, type = "Error" },
        { line = 2, type = "Warn" },
        { line = 5, type = "Info" },
        { line = 7, type = "Hint" },
    })

    local rows = {}
    local by_line = {}
    for _, overlay in ipairs(project(bufnr, 4)) do
        table.insert(rows, overlay.minimap_row)
        by_line[overlay.source_line] = overlay.minimap_row
    end
    table.sort(rows)
    expect.equality(rows, { 1, 2, 3, 4 })
    expect.equality(by_line[0], 1)
    expect.equality(by_line[2], 2)
    expect.equality(by_line[5], 3)
    expect.equality(by_line[7], 4)
end

T["project clamps marks to the minimap height when source exceeds target"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d", "e", "f", "g", "h" })
    store().set("diagnostic", bufnr, { { line = 7, type = "Error" } })

    local result = project(bufnr, 3)
    expect.equality(#result, 1)
    expect.equality(result[1].minimap_row, 3)
end

T["project excludes marks whose type is not in overlays.types"] = function()
    minimap_config().set({ overlays = { types = { Hint = false, Info = false } } })
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    store().set("diagnostic", bufnr, {
        { line = 0, type = "Error" },
        { line = 1, type = "Hint" },
        { line = 2, type = "Info" },
        { line = 3, type = "Warn" },
    })

    local result = project(bufnr, 4)
    table.sort(result, function(a, b)
        return a.source_line < b.source_line
    end)
    expect.equality(#result, 2)
    expect.equality(result[1].mark_type, "Error")
    expect.equality(result[2].mark_type, "Warn")
end

T["project applies the overlay type filter selected for the source window"] = function()
    require("scrollbar.config").set({
        scrollbar = {},
        minimap = {
            enabled = true,
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    config = { overlays = { types = { Error = false } } },
                },
            },
        },
    })
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    vim.bo[bufnr].filetype = "lua"
    store().set("diagnostic", bufnr, {
        { line = 0, type = "Error" },
        { line = 1, type = "Hint" },
    })

    local result = project(bufnr, 2)
    expect.equality(#result, 1)
    expect.equality(result[1].mark_type, "Hint")
    expect.equality(result[1].highlight, "ScrollbarMinimapProfile1.Hint")
end

T["default types include Mark and configured custom mark types"] = function()
    require("scrollbar.config").set({
        scrollbar = {
            marks = {
                Runtime = { text = "R", priority = 3, highlight = "String" },
            },
        },
        minimap = { enabled = true },
    })
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    store().set("marks", bufnr, { { line = 0, type = "Mark", text = "a" } })
    store().set("diagnostic", bufnr, { { line = 2, type = "Runtime" } })

    local mark_types = {}
    for _, overlay in ipairs(project(bufnr, 4)) do
        mark_types[overlay.mark_type] = true
    end
    expect.equality(mark_types, { Mark = true, Runtime = true })
end

T["overlays.enabled false suppresses otherwise eligible marks"] = function()
    minimap_config().set({ overlays = { enabled = false } })
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    store().set("diagnostic", bufnr, { { line = 0, type = "Error" } })

    expect.equality(project(bufnr, 2), {})
end

T["projects a fully specified minimap-only custom type"] = function()
    require("scrollbar.config").set({
        scrollbar = {},
        minimap = {
            enabled = true,
            overlays = {
                types = {
                    MinimapOnly = { priority = 0, highlight = "Special" },
                },
            },
        },
    })
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    local ok = store().set("diagnostic", bufnr, { { line = 0, type = "MinimapOnly" } })

    local result = project(bufnr, 2)
    expect.equality(ok, true)
    expect.equality(#result, 1)
    expect.equality(result[1].mark_type, "MinimapOnly")
    expect.equality(result[1].priority, 0)
    expect.equality(result[1].highlight, "ScrollbarMinimapMinimapOnly")
end

T["project resolves collisions using minimap priorities"] = function()
    require("scrollbar.config").set({
        scrollbar = {
            marks = {
                Error = { text = "!", priority = 0, highlight = "ErrorMsg" },
                Hint = { text = "?", priority = 9, highlight = "Question" },
            },
        },
        minimap = {
            enabled = true,
            overlays = {
                types = {
                    Error = { priority = 8 },
                    Hint = { priority = 1 },
                },
            },
        },
    })
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    store().set("diagnostic", bufnr, { { line = 0, type = "Hint" } })
    store().set("other", bufnr, { { line = 0, type = "Error" } })

    local result = project(bufnr, 1)
    expect.equality(#result, 1)
    expect.equality(result[1].mark_type, "Hint")
    expect.equality(result[1].priority, 1)
    expect.equality(result[1].provider, "diagnostic")
end

T["project breaks priority ties by alphabetical provider order"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    -- Two Search marks from different providers both at priority 1.
    store().set("zeta", bufnr, { { line = 0, type = "Search" } })
    store().set("alpha", bufnr, { { line = 0, type = "Search" } })

    local result = project(bufnr, 1)
    expect.equality(#result, 1)
    expect.equality(result[1].provider, "alpha")
end

T["project breaks priority ties by list order within one provider"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    -- Two Search marks (same priority) from one provider on the same row.
    store().set("diagnostic", bufnr, {
        { line = 0, type = "Search" },
        { line = 0, type = "Search" },
    })

    local result = project(bufnr, 1)
    expect.equality(#result, 1)
end

T["merges buffer marks with only the current source window marks"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    local first = source_window(bufnr)
    vim.cmd("split")
    local second = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(second, bufnr)

    store().set("diagnostic", bufnr, { { line = 1, type = "Error" } })
    store().set_window("diagnostic", first, { { line = 0, type = "Warn" } })
    store().set_window("diagnostic", second, { { line = 3, type = "Hint" } })

    local function source_lines(source_win)
        local lines = {}
        for _, overlay in ipairs(overlays().project_with(source_win, 4, 4)) do
            lines[#lines + 1] = overlay.source_line
        end
        table.sort(lines)
        return lines
    end

    local result = {
        first = source_lines(first),
        second = source_lines(second),
    }
    vim.api.nvim_win_close(second, true)
    expect.equality(result, {
        first = { 0, 1 },
        second = { 1, 3 },
    })
end

T["filters providers disabled for the minimap"] = function()
    require("scrollbar.config").set({
        scrollbar = { providers = { diagnostic = true } },
        minimap = {
            enabled = true,
            providers = {
                cursor = false,
                diagnostic = false,
                search = false,
                marks = false,
                gitsigns = false,
                mini_diff = false,
                signify = false,
                vgit = false,
                ale = false,
                coc = false,
                treesitter = false,
                lsp_semantic_tokens = false,
            },
        },
    })
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    store().set("diagnostic", bufnr, { { line = 0, type = "Error" } })

    expect.equality(project(bufnr, 2), {})
end

T["project drops overlays whose mark was cleared from the store"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    store().set("diagnostic", bufnr, {
        { line = 0, type = "Error" },
        { line = 2, type = "Warn" },
    })
    store().clear("diagnostic", bufnr)

    expect.equality(project(bufnr, 4), {})
end

T["project returns overlays sorted by minimap row ascending"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d", "e", "f" })
    store().set("diagnostic", bufnr, {
        { line = 5, type = "Hint" },
        { line = 1, type = "Error" },
        { line = 3, type = "Warn" },
    })

    local rows = {}
    for _, overlay in ipairs(project(bufnr, 3)) do
        table.insert(rows, overlay.minimap_row)
    end
    expect.equality(rows, { 1, 2, 3 })
end

T["project returns empty list before setup is called"] = function()
    local bufnr = new_buffer({ "a", "b" })
    expect.equality(project(bufnr, 2), {})
end

T["project is read-only and does not mutate the store snapshot"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    store().set("diagnostic", bufnr, { { line = 1, type = "Error" } })
    local before = store().get(bufnr)

    project(bufnr, 4)
    expect.equality(store().get(bufnr), before)
end

T["project_with returns empty list for non-positive source line count"] = function()
    setup_with()
    local bufnr = new_buffer({ "a" })
    expect.equality(project_with(bufnr, 4, 0), {})
    expect.equality(project_with(bufnr, 0, 4), {})
end

T["project_with reuses a caller-provided source line count"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d", "e", "f", "g", "h" })
    store().set("diagnostic", bufnr, { { line = 7, type = "Error" } })

    local result = project_with(bufnr, 4, 8)
    expect.equality(#result, 1)
    expect.equality(result[1].minimap_row, 4)
end

T["projects compact search by iterating it without mark expansion"] = function()
    setup_with()
    local bufnr = new_buffer({ "a", "b", "c", "d" })
    local compact = require("scrollbar.providers.search_compact")
    assert(store()._set_search_compact(bufnr, compact.encode({ 1, 3 })))

    local each = compact.each
    local to_marks = compact.to_marks
    local iterations = 0
    rawset(compact, "each", function(snapshot, callback)
        iterations = iterations + 1
        return each(snapshot, callback)
    end)
    rawset(compact, "to_marks", function()
        error("compact search must not expand to marks")
    end)
    local result = project(bufnr, 4)
    rawset(compact, "each", each)
    rawset(compact, "to_marks", to_marks)

    expect.equality(iterations, 1)
    expect.equality(
        vim.tbl_map(function(overlay)
            return overlay.source_line
        end, result),
        { 1, 3 }
    )
end

return T
