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
    local ok, err = pcall(config().set, { scrollbar = overrides })
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

T["compiles profile variants with presets and settled precedence"] = function()
    local root = config().set({
        scrollbar = {
            preset = "zed",
            thumb = { blend = 35 },
            profiles = {
                {
                    match = { filetypes = { "lua" } },
                    preset = "review",
                    thumb = { text = "R", blend = 10 },
                    placement = { gutter = "overlap" },
                    mouse = false,
                },
                {
                    match = { buftypes = { "quickfix" } },
                    geometry = "screen",
                },
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
    expect.equality(variants[2].config.placement.gutter, "overlap")
    expect.equality(variants[2].config.mouse, false)
    expect.equality(variants[2].config.visibility, root.visibility)
    expect.equality(variants[3].id, 2)
    expect.equality(variants[3].config.layout.width, 1)
    expect.equality(variants[3].config.thumb.blend, 35)
    expect.equality(variants[3].config.placement.gutter, "inner")
    expect.equality(variants[3].config.geometry, "screen")

    for _, variant in ipairs(variants) do
        expect.equality(rawget(variant.config, "preset"), nil)
        expect.equality(rawget(variant.config, "match"), nil)
        expect.equality(rawget(variant.config, "profiles"), nil)
    end
end

T["validates profile schema and the appearance boundary"] = function()
    expect_invalid({ profiles = "lua" }, "scrollbar.profiles must be a dense list")
    expect_invalid({ profiles = { [2] = { match = { when = function() end } } } }, "profiles must be a dense list")
    expect_invalid({ profiles = { "lua" } }, "scrollbar.profiles%[1%] must be a table")
    expect_invalid({ profiles = { {} } }, "scrollbar.profiles%[1%].match is required")
    expect_invalid({ profiles = { { match = "lua" } } }, "scrollbar.profiles%[1%].match must be a table")
    expect_invalid({ profiles = { { match = {} } } }, "profiles%[1%].match must contain at least one matcher")
    expect_invalid({ profiles = { { match = { filetypes = {} } } } }, "filetypes must contain at least one value")
    expect_invalid({ profiles = { { match = { buftypes = { "", false } } } } }, "buftypes%[2%] must be a string")
    expect_invalid({ profiles = { { match = { when = true } } } }, "when must be a function")
    expect_invalid(
        { profiles = { { match = { filetypes = { "lua" }, extra = true } } } },
        "unknown option 'scrollbar.profiles%[1%].match.extra'"
    )
    expect_invalid(
        { profiles = { { match = { when = function() end }, extra = true } } },
        "unknown option 'scrollbar.profiles%[1%].extra'"
    )
    expect_invalid(
        { profiles = { { match = { when = function() end }, preset = 1 } } },
        "scrollbar.profiles%[1%].preset must be a string"
    )
    expect_invalid({ profiles = { { match = { when = function() end }, preset = "missing" } } }, "unknown preset")
    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                placement = { gutter = "inside" },
            },
        },
    }, "scrollbar.profiles%[1%].placement.gutter must be one of: inner, outer, overlap")
    expect_invalid({
        profiles = {
            {
                match = { filetypes = { "lua" } },
                placement = { gutter_position = "outer" },
            },
        },
    }, "unknown option 'scrollbar.profiles%[1%].placement.gutter_position'")

    local global = {
        { enabled = false },
        { show = false },
        { visibility = "active" },
        { max_lines = 100 },
        { autohide = true },
        { throttle_ms = 50 },
        { profiles = {} },
    }
    for _, unsafe in ipairs(global) do
        unsafe.match = { filetypes = { "lua" } }
        expect_invalid({ profiles = { unsafe } }, "scrollbar.profiles%[1%]%.[%w_]+ is a global option")
    end

    local rejected = {
        { set_highlights = false },
        { providers = { cursor = false } },
        { excluded_filetypes = { "lua" } },
        { exclude = { filetypes = { "lua" } } },
        { update = { interval_ms = 50 } },
        { mouse = { enabled = false } },
        { float = { zindex = 1 } },
        { presets = {} },
        { config = {} },
    }
    for _, unsafe in ipairs(rejected) do
        unsafe.match = { filetypes = { "lua" } }
        expect_invalid({ profiles = { unsafe } }, "profiles%[1%]")
    end
end

T["commits root and variants atomically"] = function()
    local module = config()
    local before = module.set({
        scrollbar = {
            visibility = "active",
            profiles = {
                { match = { filetypes = { "lua" } }, preset = "minimal" },
            },
        },
    })
    local before_variants = module.get_variants()

    expect_invalid({
        profiles = {
            { match = { filetypes = { "lua" } }, preset = "review" },
            { match = { buftypes = { "nofile" } }, throttle_ms = 1 },
        },
    }, "scrollbar.profiles%[2%].throttle_ms is a global option")
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
        scrollbar = {
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
        scrollbar = {
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
    rawset(vim, "notify", function(message, level)
        notifications[#notifications + 1] = { message, level }
    end)
    MiniTest.finally(function()
        rawset(vim, "notify", original_notify)
    end)

    config().set({
        scrollbar = {
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

    config().set({ scrollbar = { profiles = {} } })
    config().set({
        scrollbar = {
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
        },
    })
    expect.equality(config().select(winid).variant_id, 0)
    expect.equality(#notifications, 3)
end

return T
