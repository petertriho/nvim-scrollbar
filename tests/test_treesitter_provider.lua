local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.providers.treesitter"] = nil
        end,
    },
})

T["collect emits normalized single-line source byte spans"] = function()
    local provider = require("scrollbar.providers.treesitter")
    local calls = { add = 0, parser = 0, parse = 0, query = 0 }
    local node = {
        range = function()
            return 1, 2, 1, 6
        end,
    }
    local parser = {
        parse = function()
            calls.parse = calls.parse + 1
        end,
        trees = function()
            return {
                {
                    root = function()
                        return {}
                    end,
                },
            }
        end,
    }
    local query = {
        captures = { "keyword" },
        iter_captures = function()
            local emitted = false
            return function()
                if emitted then
                    return nil
                end
                emitted = true
                return 1, node
            end
        end,
    }

    local original_add = vim.treesitter.language.add
    local original_get_parser = vim.treesitter.get_parser
    local original_query_get = vim.treesitter.query.get
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.treesitter.language.add = function(lang)
        expect.equality(lang, "lua")
        calls.add = calls.add + 1
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.treesitter.get_parser = function(_, lang)
        expect.equality(lang, "lua")
        calls.parser = calls.parser + 1
        return parser
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.treesitter.query.get = function(lang, kind)
        expect.equality({ lang, kind }, { "lua", "highlights" })
        calls.query = calls.query + 1
        return query
    end
    MiniTest.finally(function()
        vim.treesitter.language.add = original_add
        vim.treesitter.get_parser = original_get_parser
        vim.treesitter.query.get = original_query_get
    end)

    local spans = provider.collect(vim.api.nvim_get_current_buf(), "lua")
    expect.equality(calls, { add = 1, parser = 1, parse = 1, query = 1 })
    expect.equality(spans, {
        {
            line = 1,
            start_col = 2,
            end_col = 6,
            highlight = "@keyword",
            priority = provider.priority,
        },
    })
end

T["language and collection failures degrade to no spans"] = function()
    local provider = require("scrollbar.providers.treesitter")
    expect.equality(provider.targets, { scrollbar = false, minimap = true })
    expect.equality(provider.execution, "worker")
    expect.equality(type(provider.priority), "number")
    expect.equality(provider.language_for(""), nil)

    local original_get_lang = vim.treesitter.language.get_lang
    local original_add = vim.treesitter.language.add
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.treesitter.language.get_lang = function()
        return "missing"
    end
    ---@diagnostic disable-next-line: duplicate-set-field
    vim.treesitter.language.add = function()
        error("missing parser")
    end
    MiniTest.finally(function()
        vim.treesitter.language.get_lang = original_get_lang
        vim.treesitter.language.add = original_add
    end)

    expect.equality(provider.language_for("test"), nil)
    expect.equality(provider.collect(vim.api.nvim_get_current_buf(), "missing"), {})
end

return T
