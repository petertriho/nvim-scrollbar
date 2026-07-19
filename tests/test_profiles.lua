local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.presets"] = nil
        end,
    },
})

local function config()
    return require("scrollbar.config")
end

local function expect_invalid(overrides, pattern)
    local ok, err = pcall(config().set, overrides)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

T["compiles profile variants with setup-local presets and settled precedence"] = function()
    local root = config().set({
        preset = "zed",
        presets = {
            local_review = {
                extends = "review",
                thumb = { text = "R" },
            },
        },
        thumb = { blend = 35 },
        profiles = {
            {
                match = { filetypes = { "lua" } },
                preset = "local_review",
                config = {
                    float = { placement = { gutter = "overlap", gutter_position = "outer" } },
                    thumb = { blend = 10 },
                    mouse = { enabled = false },
                },
            },
            {
                match = { buftypes = { "quickfix" } },
                config = { render = { geometry = "screen" } },
            },
        },
    })
    local variants = config().get_variants()

    expect.equality(root.layout.width, 1)
    expect.equality(#variants, 3)
    expect.equality(variants[1].id, 0)
    expect.equality(variants[1].config, root)
    expect.equality(variants[2].id, 1)
    expect.equality(variants[2].config.layout.width, 3)
    expect.equality(variants[2].config.thumb.text, "R")
    expect.equality(variants[2].config.thumb.blend, 10)
    expect.equality(variants[2].config.float.placement.gutter, "overlap")
    expect.equality(variants[2].config.float.placement.gutter_position, "outer")
    expect.equality(variants[2].config.mouse.enabled, false)
    expect.equality(variants[2].config.visibility, root.visibility)
    expect.equality(variants[3].id, 2)
    expect.equality(variants[3].config.layout.width, 1)
    expect.equality(variants[3].config.thumb.blend, 35)
    expect.equality(variants[3].config.float.placement.gutter, "avoid")
    expect.equality(variants[3].config.float.placement.gutter_position, "inner")
    expect.equality(variants[3].config.render.geometry, "screen")

    for _, variant in ipairs(variants) do
        expect.equality(rawget(variant.config, "preset"), nil)
        expect.equality(rawget(variant.config, "presets"), nil)
        expect.equality(rawget(variant.config, "profiles"), nil)
    end
end

T["validates profile schema and the nested render-safe boundary"] = function()
    expect_invalid({ profiles = "lua" }, "profiles must be a dense list")
    expect_invalid({ profiles = { [2] = { match = { when = function() end } } } }, "profiles must be a dense list")
    expect_invalid({ profiles = { {} } }, "profiles%[1%].match must be a table")
    expect_invalid({ profiles = { { match = {} } } }, "profiles%[1%].match must contain at least one matcher")
    expect_invalid({ profiles = { { match = { filetypes = {} } } } }, "filetypes must contain at least one value")
    expect_invalid({ profiles = { { match = { buftypes = { "", false } } } } }, "buftypes%[2%] must be a string")
    expect_invalid({ profiles = { { match = { when = true } } } }, "when must be a function")
    expect_invalid({ profiles = { { match = { filetypes = { "lua" }, extra = true } } } }, "unknown option")
    expect_invalid({ profiles = { { match = { when = function() end }, extra = true } } }, "unknown option")
    expect_invalid({ profiles = { { match = { when = function() end }, preset = 1 } } }, "preset must be a string")
    expect_invalid({ profiles = { { match = { when = function() end }, preset = "missing" } } }, "unknown preset")
    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { float = { placement = { gutter = "inside" } } },
            },
        },
    }, "float.placement.gutter must be one of: avoid, overlap")
    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { float = { placement = { gutter_position = "middle" } } },
            },
        },
    }, "float.placement.gutter_position must be one of: inner, outer")

    local rejected = {
        { show = false },
        { visibility = "active" },
        { set_highlights = false },
        { max_lines = 100 },
        { autohide = { enabled = true } },
        { providers = { cursor = false } },
        { excluded_filetypes = { "lua" } },
        { render = { interval_ms = 50 } },
        { mouse = { extra = true } },
        { float = { extra = true } },
        { preset = "zed" },
        { presets = {} },
        { profiles = {} },
    }
    for _, unsafe in ipairs(rejected) do
        expect_invalid({ profiles = { { match = { filetypes = { "lua" } }, config = unsafe } } }, "profile")
    end
end

T["commits root and variants atomically"] = function()
    local module = config()
    local before = module.set({
        visibility = "active",
        profiles = {
            { match = { filetypes = { "lua" } }, preset = "minimal" },
        },
    })
    local before_variants = module.get_variants()

    expect_invalid({
        profiles = {
            { match = { filetypes = { "lua" } }, preset = "review" },
            { match = { buftypes = { "nofile" } }, config = { render = { interval_ms = 1 } } },
        },
    }, "profile")
    expect.equality(module.get(), before)
    expect.equality(module.get_variants(), before_variants)
end

T["selects the first profile with AND semantics and stable IDs"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "lua"
    vim.bo[bufnr].buftype = "nofile"
    vim.api.nvim_buf_set_name(bufnr, "/tmp/profile.lua")
    local skipped_calls = 0

    config().set({
        profiles = {
            {
                match = {
                    filetypes = { "markdown" },
                    when = function()
                        skipped_calls = skipped_calls + 1
                        return true
                    end,
                },
                preset = "minimal",
            },
            {
                match = {
                    filetypes = { "lua" },
                    buftypes = { "nofile" },
                    when = function()
                        return true
                    end,
                },
                preset = "review",
            },
            { match = { filetypes = { "lua" } }, preset = "search" },
        },
    })

    local selected = config().select(winid)
    expect.equality(skipped_calls, 0)
    expect.equality(selected.variant_id, 2)
    expect.equality(selected.config.layout.width, 3)

    vim.bo[bufnr].buftype = ""
    selected = config().select(winid)
    expect.equality(selected.variant_id, 3)

    vim.bo[bufnr].filetype = "text"
    selected = config().select(winid)
    expect.equality(selected.variant_id, 0)
    expect.equality(selected.config, config().get())
end

T["builds exact callback context and reevaluates predicates on every call"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "lua"
    vim.bo[bufnr].buftype = "nofile"
    vim.api.nvim_buf_set_name(bufnr, "/tmp/context.lua")
    local enabled = false
    local calls = 0
    local received

    config().set({
        profiles = {
            {
                match = {
                    when = function(context)
                        calls = calls + 1
                        received = context
                        return enabled
                    end,
                },
                preset = "minimal",
            },
        },
    })

    expect.equality(config().select(winid).variant_id, 0)
    enabled = true
    expect.equality(config().select(winid).variant_id, 1)
    expect.equality(calls, 2)
    expect.equality(received, {
        winid = winid,
        bufnr = bufnr,
        filetype = "lua",
        buftype = "nofile",
        bufname = "/tmp/context.lua",
    })
end

T["falls back on callback errors rate limits notifications and recovers"] = function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    ---@type string?
    local failure = "first"
    local notifications = {}
    local original_notify = vim.notify
    vim.notify = function(message, level)
        notifications[#notifications + 1] = { message, level }
    end

    config().set({
        profiles = {
            {
                match = {
                    when = function()
                        if failure then
                            error(failure)
                        end
                        return true
                    end,
                },
                preset = "minimal",
            },
        },
    })

    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(#notifications, 1)
    failure = "second"
    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(#notifications, 2)
    failure = nil
    expect.equality(config().select(winid).variant_id, 1)

    config().set({ profiles = {} })
    config().set({
        profiles = {
            {
                match = {
                    when = function()
                        error("first")
                    end,
                },
                preset = "minimal",
            },
        },
    })
    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(#notifications, 3)
    vim.notify = original_notify
end

return T
