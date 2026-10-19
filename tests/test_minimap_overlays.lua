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

local function numbered(count)
    local lines = {}
    for line = 1, count do
        lines[line] = "line " .. line
    end
    return lines
end

local function projection_for(bufnr, rows, options)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    return require("scrollbar.minimap.projection").new(vim.tbl_extend("force", {
        scale = "fixed",
        line_count = line_count,
        rows = rows,
        width = 16,
        columns_per_dot = 4,
        top = 0,
        bottom = line_count - 1,
    }, options or {}))
end

local function project(bufnr, rows, options)
    local source_win = source_window(bufnr)
    return overlays().project(source_win, projection_for(bufnr, rows, options))
end

T["project returns an empty list for a buffer with no marks"] = function()
    setup_with()
    local bufnr = new_buffer({ "one", "two", "three" })

    expect.equality(project(bufnr, 4), {})
end

T["project returns an overlay per published mark of an allowed type"] = function()
    setup_with()
    local bufnr = new_buffer(numbered(8))
    store().set("diagnostic", bufnr, { { line = 5, type = "Error" } })

    local result = project(bufnr, 4)
    expect.equality(#result, 1)
    expect.equality(result[1].source_line, 5)
    expect.equality(result[1].minimap_row, 2)
    expect.equality(result[1].mark_type, "Error")
    expect.equality(result[1].priority, 2)
    expect.equality(result[1].highlight, "ScrollbarMinimapError")
    expect.equality(result[1].provider, "diagnostic")
end

T["project uses the row that the squash draws the line in"] = function()
    setup_with()
    local squash = require("scrollbar.minimap.squash")
    for _, case in ipairs({
        { lines = 16, marks = { 0, 4, 9, 15 } },
        { lines = 32, marks = { 0, 8, 20, 31 }, scale = "fit" },
        { lines = 30, marks = { 0, 7, 16, 29 }, scale = "fit" },
    }) do
        local bufnr = new_buffer(numbered(case.lines))
        local types = { "Error", "Warn", "Info", "Hint" }
        local marks = {}
        for index, line in ipairs(case.marks) do
            marks[index] = { line = line, type = types[index] }
        end
        store().set("diagnostic", bufnr, marks)

        local p = projection_for(bufnr, 4, { scale = case.scale or "fixed" })
        local by_line = {}
        for _, overlay in ipairs(overlays().project(source_window(bufnr), p)) do
            by_line[overlay.source_line] = overlay.minimap_row
        end
        for _, line in ipairs(case.marks) do
            expect.equality(by_line[line], math.floor(squash.line_dot(line, p) / squash.DOT_ROWS) + 1)
        end
    end
end

T["project skips marks on rows outside the float"] = function()
    setup_with()
    local bufnr = new_buffer(numbered(40))
    store().set("diagnostic", bufnr, {
        { line = 8, type = "Warn" },
        { line = 39, type = "Error" },
    })

    local result = project(bufnr, 3, { bottom = 9 })
    expect.equality(#result, 1)
    expect.equality(result[1].source_line, 8)
    expect.equality(result[1].minimap_row, 3)
end

T["project follows the scroll offset of the projection"] = function()
    setup_with()
    local bufnr = new_buffer(numbered(400))
    store().set("diagnostic", bufnr, {
        { line = 0, type = "Warn" },
        { line = 160, type = "Error" },
        { line = 239, type = "Hint" },
    })

    local result = project(bufnr, 20, { top = 180, bottom = 219 })
    expect.equality(
        vim.tbl_map(function(overlay)
            return { overlay.source_line, overlay.minimap_row }
        end, result),
        { { 160, 1 }, { 239, 20 } }
    )
end

T["project excludes marks whose type minimap.marks hides"] = function()
    minimap_config().set({ marks = { Hint = false, Info = false } })
    setup_with()
    local bufnr = new_buffer(numbered(16))
    store().set("diagnostic", bufnr, {
        { line = 0, type = "Error" },
        { line = 4, type = "Hint" },
        { line = 8, type = "Info" },
        { line = 12, type = "Warn" },
    })

    local result = project(bufnr, 4)
    table.sort(result, function(a, b)
        return a.source_line < b.source_line
    end)
    expect.equality(#result, 2)
    expect.equality(result[1].mark_type, "Error")
    expect.equality(result[2].mark_type, "Warn")
end

T["project applies the mark type filter selected for the source window"] = function()
    require("scrollbar.config").set({
        scrollbar = {},
        minimap = {
            enabled = true,
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    marks = { Error = false },
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

T["default types include Mark and registered custom mark types"] = function()
    require("scrollbar.config").set({
        marks = {
            Runtime = { text = "R", priority = 3, highlight = "String" },
        },
        minimap = { enabled = true },
    })
    setup_with()
    local bufnr = new_buffer(numbered(16))
    store().set("marks", bufnr, { { line = 0, type = "Mark", text = "a" } })
    store().set("diagnostic", bufnr, { { line = 8, type = "Runtime" } })

    local mark_types = {}
    for _, overlay in ipairs(project(bufnr, 4)) do
        mark_types[overlay.mark_type] = true
    end
    expect.equality(mark_types, { Mark = true, Runtime = true })
end

T["marks false suppresses otherwise eligible marks"] = function()
    minimap_config().set({ marks = false })
    setup_with()
    local bufnr = new_buffer({ "a", "b" })
    store().set("diagnostic", bufnr, { { line = 0, type = "Error" } })

    expect.equality(project(bufnr, 2), {})
end

T["projects a registered custom type that the scrollbar hides"] = function()
    require("scrollbar.config").set({
        marks = {
            MinimapOnly = { text = "m", priority = 0, highlight = "Special" },
        },
        scrollbar = {
            marks = { MinimapOnly = false },
        },
        minimap = { enabled = true },
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
        marks = {
            Error = { text = "!", priority = 0, highlight = "ErrorMsg" },
            Hint = { text = "?", priority = 9, highlight = "Question" },
        },
        minimap = {
            enabled = true,
            marks = {
                Error = { priority = 8 },
                Hint = { priority = 1 },
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
    local bufnr = new_buffer(numbered(16))
    local first = source_window(bufnr)
    vim.cmd("split")
    local second = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(second, bufnr)

    store().set("diagnostic", bufnr, { { line = 4, type = "Error" } })
    store().set_window("diagnostic", first, { { line = 0, type = "Warn" } })
    store().set_window("diagnostic", second, { { line = 12, type = "Hint" } })

    local function source_lines(source_win)
        local lines = {}
        for _, overlay in ipairs(overlays().project_with(source_win, projection_for(bufnr, 4))) do
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
        first = { 0, 4 },
        second = { 4, 12 },
    })
end

T["filters providers disabled for the minimap"] = function()
    require("scrollbar.config").set({
        providers = { diagnostic = { minimap = false } },
        minimap = { enabled = true },
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
    local bufnr = new_buffer(numbered(12))
    store().set("diagnostic", bufnr, {
        { line = 9, type = "Hint" },
        { line = 1, type = "Error" },
        { line = 5, type = "Warn" },
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

T["project_with returns an empty list for an empty projection"] = function()
    setup_with()
    local bufnr = new_buffer({ "a" })
    store().set("diagnostic", bufnr, { { line = 0, type = "Error" } })

    expect.equality(project(bufnr, 4, { line_count = 0 }), {})
end

T["projects compact search by iterating it without mark expansion"] = function()
    setup_with()
    local bufnr = new_buffer(numbered(16))
    local compact = require("scrollbar.providers.search_compact")
    assert(store()._set_search_compact(bufnr, compact.encode({ 1, 9 })))

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
        { 1, 9 }
    )
end

return T
