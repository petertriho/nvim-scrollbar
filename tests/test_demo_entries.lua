local MiniTest = MiniTest
local expect = MiniTest.expect

local catalog = dofile("scripts/demo/entries.lua")

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.presets"] = nil
            package.loaded["scrollbar.minimap.config"] = nil
        end,
    },
})

-- Run the setup source of an entry with a stub `scrollbar` module, then
-- validate the captured options without starting the plugin.
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

return T
