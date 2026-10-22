local MiniTest = MiniTest
local expect = MiniTest.expect

local catalog = dofile("scripts/demo/entries.lua")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.config.presets"] = nil
            package.loaded["scrollbar.minimap.config"] = nil
        end,
    },
})

-- Run the setup source of an entry with a stub `scrollbar` module, then
-- validate the captured configuration without starting the plugin.
---@param entry DemoEntry
local function validate(entry)
    local options
    local original = package.loaded["scrollbar"]
    package.loaded["scrollbar"] = {
        setup = function(value)
            options = value
        end,
    }
    local ok, err = pcall(assert(load(entry.setup, "=" .. entry.id)))
    package.loaded["scrollbar"] = original
    if not ok then
        error(err, 0)
    end
    expect.equality(type(options), "table")
    require("scrollbar.config").set(vim.tbl_extend("force", options, { set_highlights = false }))
end

local ids = {}
for _, entry in ipairs(catalog.entries) do
    table.insert(ids, { entry.id })
end

T["setup"] = MiniTest.new_set({ parametrize = ids })

T["setup"]["is a valid configuration"] = function(id)
    validate(catalog.find(id))
end

T["entries have unique ids and labels that the tapes can match"] = function()
    local seen = {}
    for _, entry in ipairs(catalog.entries) do
        expect.equality(seen[entry.id], nil)
        seen[entry.id] = true
        expect.equality(entry.label:find("/", 1, true), nil)
    end
end

T["every showcase entry is in a known section"] = function()
    local sections = {}
    for _, section in ipairs(catalog.sections) do
        sections[section.id] = true
    end
    for _, entry in ipairs(catalog.entries) do
        if entry.section ~= nil then
            expect.equality(sections[entry.section], true)
        end
    end
end

T["every GIF entry has a tape"] = function()
    for _, entry in ipairs(catalog.entries) do
        if entry.kind == "gif" then
            expect.equality(vim.fn.filereadable("scripts/demo/" .. entry.id .. ".tape"), 1)
        end
    end
end

T["every GIF tape opens the demo buffer and searches for the demo pattern"] = function()
    for _, entry in ipairs(catalog.entries) do
        if entry.kind == "gif" then
            local tape = table.concat(vim.fn.readfile("scripts/demo/" .. entry.id .. ".tape"), "\n")
            local searches = tape:find('Type "/', 1, true) ~= nil
            expect.equality({
                id = entry.id,
                opens_file = tape:find(catalog.file, 1, true) ~= nil,
                types_pattern = not searches or tape:find('"/?' .. vim.pesc(catalog.search_pattern) .. '"') ~= nil,
            }, { id = entry.id, opens_file = true, types_pattern = true })
        end
    end
end

T["positions are fractions from 0 to 1"] = function()
    local positions = { catalog.position }
    for _, entry in ipairs(catalog.entries) do
        table.insert(positions, entry.position)
    end
    for _, diagnostic in ipairs(catalog.diagnostics) do
        table.insert(positions, diagnostic[1])
    end
    for _, hunk in ipairs(catalog.hunks) do
        table.insert(positions, hunk.position)
    end
    for _, position in pairs(catalog.marks) do
        table.insert(positions, position)
    end
    local outside = {}
    for _, position in pairs(positions) do
        if position < 0 or position > 1 then
            table.insert(outside, position)
        end
    end
    expect.equality(outside, {})
end

T["line_at gives the first line for 0 and the last line for 1"] = function()
    expect.equality(catalog.line_at(0, 165), 1)
    expect.equality(catalog.line_at(0.5, 165), 83)
    expect.equality(catalog.line_at(1, 165), 165)
    expect.equality(catalog.line_at(1, 1), 1)
end

T["the marks and hunks are on separate lines of the demo buffer"] = function()
    local line_count = #vim.fn.readfile(catalog.file)
    local names, shared = {}, {}
    for name, position in pairs(catalog.marks) do
        local line = catalog.line_at(position, line_count)
        if names[line] ~= nil then
            table.insert(shared, line)
        end
        names[line] = name
    end
    expect.equality(shared, {})

    -- Hunks without an unchanged line between them are one hunk in the diff
    local previous = 0
    for index, hunk in ipairs(catalog.hunks) do
        local first = catalog.line_at(hunk.position, line_count)
        local last = hunk.kind == "delete" and first or first + hunk.count - 1
        expect.equality(
            { hunk = index, after_previous = first > previous + 1, in_buffer = last <= line_count },
            { hunk = index, after_previous = true, in_buffer = true }
        )
        previous = last
    end
end

-- The hero tape jumps to a match and then presses `n` 4 times
T["the search pattern matches at least 5 lines of the demo buffer"] = function()
    local regex = vim.regex(catalog.search_pattern)
    local count = 0
    for _, line in ipairs(vim.fn.readfile(catalog.file)) do
        if regex:match_str(line) then
            count = count + 1
        end
    end
    expect.equality(count >= 5, true)
end

return T
