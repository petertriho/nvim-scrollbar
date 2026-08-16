local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

local function base_config(overrides)
    return vim.tbl_deep_extend("force", {
        show = false,
        set_highlights = true,
        mouse = { enabled = false },
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
        },
    }, overrides or {})
end

T["generates canonical Thumb groups transparent base and equivalent Handle aliases"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        vim.api.nvim_set_hl(0, "Special", { fg = "#abcdef" })
        vim.api.nvim_set_hl(0, "PmenuSbar", { bg = "#112233" })
        vim.api.nvim_set_hl(0, "PmenuThumb", { bg = "#445566" })
        vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#778899" })
        require("scrollbar").setup({ scrollbar = config })
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        return {
            base = get("ScrollbarBase"),
            track = get("ScrollbarTrack"),
            thumb = get("ScrollbarThumb"),
            thumb_pressed = get("ScrollbarThumbPressed"),
            mark = get("ScrollbarMark"),
            overlap = get("ScrollbarMarkThumb"),
            overlap_pressed = get("ScrollbarMarkThumbPressed"),
            legacy_thumb = get("ScrollbarHandle"),
            legacy_thumb_pressed = get("ScrollbarHandlePressed"),
            legacy_overlap = get("ScrollbarMarkHandle"),
            legacy_overlap_pressed = get("ScrollbarMarkHandlePressed"),
        }
    end, base_config())

    expect.equality(result.base, {})
    expect.equality(result.track, { bg = 0x112233 })
    expect.equality(result.thumb, { bg = 0x445566, blend = 30 })
    expect.equality(result.thumb_pressed, { bg = 0x778899, blend = 30 })
    expect.equality(result.mark, { fg = 0xABCDEF })
    expect.equality(result.overlap, { fg = 0xABCDEF, bg = 0x445566, blend = 30 })
    expect.equality(result.overlap_pressed, { fg = 0xABCDEF, bg = 0x778899, blend = 30 })
    expect.equality(result.legacy_thumb, result.thumb)
    expect.equality(result.legacy_thumb_pressed, result.thumb_pressed)
    expect.equality(result.legacy_overlap, result.overlap)
    expect.equality(result.legacy_overlap_pressed, result.overlap_pressed)
end

T["applies full highlight tables and projects string sources by channel"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            vim.api.nvim_set_hl(0, "DirectTrackSource", { fg = "#030303", bg = "#234567", italic = true })
            vim.api.nvim_set_hl(0, "DirectThumbSource", { fg = "#010101", bg = "#123456", bold = true })
            vim.api.nvim_set_hl(0, "DirectMarkSource", { fg = "#654321", bg = "#020202", italic = true })
            vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#345678" })
            require("scrollbar").setup({ scrollbar = config })
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            return {
                track = get("ScrollbarTrack"),
                thumb = get("ScrollbarThumb"),
                pressed = get("ScrollbarThumbPressed"),
                string_mark = get("ScrollbarSearch"),
                string_overlap = get("ScrollbarSearchThumb"),
                table_mark = get("ScrollbarError"),
                table_overlap = get("ScrollbarErrorThumb"),
            }
        end,
        base_config({
            track = { highlight = "DirectTrackSource" },
            thumb = { blend = 27, highlight = "DirectThumbSource" },
            marks = {
                Search = { highlight = "DirectMarkSource" },
                Error = {
                    highlight = {
                        fg = "#fedcba",
                        bg = "#445566",
                        underline = true,
                        cterm = { underline = true },
                    },
                },
            },
        })
    )

    expect.equality(result.track, { bg = 0x234567 })
    expect.equality(result.thumb, { bg = 0x123456, blend = 27 })
    expect.equality(result.pressed, { bg = 0x345678, blend = 27 })
    expect.equality(result.string_mark, { fg = 0x654321 })
    expect.equality(result.string_overlap, { fg = 0x654321, bg = 0x123456, blend = 27 })
    expect.equality(result.table_mark, {
        fg = 0xFEDCBA,
        bg = 0x445566,
        underline = true,
        cterm = { underline = true },
    })
    expect.equality(result.table_overlap, {
        fg = 0xFEDCBA,
        bg = 0x445566,
        blend = 27,
        underline = true,
        cterm = { underline = true },
    })
end

T["preserves public canonical and legacy groups defined before setup"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local manual = {
            ScrollbarBase = { bg = "#010101" },
            ScrollbarTrack = { bg = "#123456" },
            ScrollbarThumb = { bg = "#223344", bold = true },
            ScrollbarThumbPressed = { bg = "#334455" },
            ScrollbarSearch = { fg = "#556677", italic = true },
            ScrollbarSearchThumb = { fg = "#667788", bg = "#778899" },
            ScrollbarSearchThumbPressed = { fg = "#778899", bg = "#8899aa" },
            ScrollbarHandle = { bg = "#8899aa" },
            ScrollbarHandlePressed = { bg = "#99aabb" },
            ScrollbarSearchHandle = { fg = "#99aabb" },
            ScrollbarSearchHandlePressed = { fg = "#aabbcc" },
        }
        for name, definition in pairs(manual) do
            vim.api.nvim_set_hl(0, name, definition)
        end
        local before = {}
        for name in pairs(manual) do
            before[name] = vim.api.nvim_get_hl(0, { name = name, link = true })
        end

        require("scrollbar").setup({ scrollbar = config })
        vim.cmd("doautocmd ColorScheme")
        local after = {}
        for name in pairs(manual) do
            after[name] = vim.api.nvim_get_hl(0, { name = name, link = true })
        end
        return { before = before, after = after }
    end, base_config())

    expect.equality(result.after, result.before)
end

T["refreshes private definitions while preserving public links and later user overrides"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local scrollbar = require("scrollbar")
        vim.api.nvim_set_hl(0, "ConfiguredTrackSource", { bg = "#102030" })
        vim.api.nvim_set_hl(0, "PmenuSel", { bg = "#405060" })
        scrollbar.setup({ scrollbar = config.first })

        local link = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = true }).link
        end
        local get = function(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end
        local first_links = {
            base = link("ScrollbarBase"),
            track = link("ScrollbarTrack"),
            thumb = link("ScrollbarThumb"),
            mark = link("ScrollbarSearch"),
            legacy_thumb = link("ScrollbarHandle"),
            legacy_mark = link("ScrollbarSearchHandle"),
        }
        local first = {
            track = get("ScrollbarTrack"),
            thumb = get("ScrollbarThumb"),
            mark = get("ScrollbarSearch"),
        }

        vim.api.nvim_set_hl(0, "ConfiguredTrackSource", { bg = "#203040" })
        scrollbar.setup({ scrollbar = config.second })
        local second_links = {
            base = link("ScrollbarBase"),
            track = link("ScrollbarTrack"),
            thumb = link("ScrollbarThumb"),
            mark = link("ScrollbarSearch"),
            legacy_thumb = link("ScrollbarHandle"),
            legacy_mark = link("ScrollbarSearchHandle"),
        }
        local second = {
            track = get("ScrollbarTrack"),
            thumb = get("ScrollbarThumb"),
            mark = get("ScrollbarSearch"),
        }

        vim.api.nvim_set_hl(0, second_links.mark, { fg = "#000000" })
        vim.api.nvim_set_hl(0, "ScrollbarSearch", { fg = "#556677", italic = true })
        vim.cmd("doautocmd ColorScheme")
        return {
            first_links = first_links,
            second_links = second_links,
            first = first,
            second = second,
            refreshed_private_mark = get(second_links.mark),
            preserved_public_mark = vim.api.nvim_get_hl(0, { name = "ScrollbarSearch", link = true }),
        }
    end, {
        first = base_config({
            track = { highlight = "ConfiguredTrackSource" },
            thumb = { highlight = { bg = "#112233" } },
            marks = { Search = { highlight = { fg = "#abcdef" } } },
        }),
        second = base_config({
            track = { highlight = "ConfiguredTrackSource" },
            thumb = { highlight = { bg = "#223344" } },
            marks = { Search = { highlight = { fg = "#fedcba" } } },
        }),
    })

    expect.equality(result.first_links, result.second_links)
    expect.equality(result.first_links.legacy_thumb, "ScrollbarThumb")
    expect.equality(result.first_links.legacy_mark, "ScrollbarSearchThumb")
    expect.no_equality(result.first_links.base:match("^ScrollbarGenerated%."), nil)
    expect.no_equality(result.first_links.track:match("^ScrollbarGenerated%."), nil)
    expect.no_equality(result.first_links.thumb:match("^ScrollbarGenerated%."), nil)
    expect.no_equality(result.first_links.mark:match("^ScrollbarGenerated%."), nil)
    expect.equality(result.first.track, { bg = 0x102030 })
    expect.equality(result.first.thumb, { bg = 0x112233, blend = 30 })
    expect.equality(result.first.mark, { fg = 0xABCDEF })
    expect.equality(result.second.track, { bg = 0x203040 })
    expect.equality(result.second.thumb, { bg = 0x223344, blend = 30 })
    expect.equality(result.second.mark, { fg = 0xFEDCBA })
    expect.equality(result.refreshed_private_mark, { fg = 0xFEDCBA })
    expect.equality(result.preserved_public_mark, {
        fg = 0x556677,
        italic = true,
        cterm = { italic = true },
    })
end

T["internal namespaces do not capture valid custom mark groups"] = function()
    local child = new_child()
    local result = child.lua_func(
        function(config)
            config.profiles = {
                {
                    match = { filetypes = { "lua" } },
                    config = { marks = { Search = { highlight = { fg = "#666666" } } } },
                },
            }
            require("scrollbar").setup({ scrollbar = config })
            local variants = require("scrollbar.config").get_variants()
            local profile_search = variants[2].config.highlights.marks.Search.mark
            local get = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = false })
            end
            local link = function(name)
                return vim.api.nvim_get_hl(0, { name = name, link = true }).link
            end
            return {
                generated = get("ScrollbarGeneratedSearch"),
                profile_like = get("ScrollbarProfile1Search"),
                generated_target = link("ScrollbarSearch"),
                profile_search = profile_search,
                profile_definition = get(profile_search),
            }
        end,
        base_config({
            marks = {
                Search = { text = "s", priority = 1, highlight = { fg = "#111111" } },
                GeneratedSearch = { text = "g", priority = 2, highlight = { fg = "#222222" } },
                Profile1Search = { text = "p", priority = 3, highlight = { fg = "#333333" } },
            },
        })
    )

    expect.equality(result.generated, { fg = 0x222222 })
    expect.equality(result.profile_like, { fg = 0x333333 })
    expect.equality(result.generated_target, "ScrollbarGenerated.Search")
    expect.equality(result.profile_search, "ScrollbarProfile1.Search")
    expect.equality(result.profile_definition, { fg = 0x666666 })
end

T["generates and renders isolated automatic groups for every profile"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        local lines = {}
        for index = 1, 100 do
            lines[index] = "line " .. index
        end
        vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
        local first_buf = vim.api.nvim_get_current_buf()
        vim.bo[first_buf].filetype = "lua"
        local first = vim.api.nvim_get_current_win()
        vim.cmd("split")
        local second = vim.api.nvim_get_current_win()
        local second_buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(second_buf, 0, -1, false, lines)
        vim.api.nvim_win_set_buf(second, second_buf)
        vim.bo[second_buf].filetype = "text"

        config.show = true
        config.thumb = { text = "H", hide_if_all_visible = false }
        config.profiles = {
            {
                match = { filetypes = { "lua" } },
                config = {
                    track = { highlight = { bg = "#112233" } },
                    thumb = { highlight = { bg = "#223344" }, blend = 11 },
                    marks = { Search = { highlight = { fg = "#abcdef" } } },
                },
            },
            {
                match = { filetypes = { "text" } },
                config = {
                    track = { highlight = { bg = "#445566" } },
                    thumb = { highlight = { bg = "#556677" }, blend = 22 },
                },
            },
        }
        require("scrollbar").setup({ scrollbar = config })
        local renderer = require("scrollbar.renderer")
        local first_state = assert(renderer.render(first))
        local second_state = assert(renderer.render(second))
        assert(renderer.set_handle_pressed(first_state.float_win, true))

        local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
        local function rendered_groups(state)
            local groups = {}
            for _, extmark in
                ipairs(vim.api.nvim_buf_get_extmarks(state.float_buf, namespace, 0, -1, { details = true }))
            do
                groups[extmark[4].hl_group] = true
            end
            return groups
        end
        local function get(name)
            return vim.api.nvim_get_hl(0, { name = name, link = false })
        end

        vim.api.nvim_set_hl(0, "ScrollbarProfile1.Track", { bg = "#000000" })
        vim.cmd("doautocmd ColorScheme")
        local names = vim.api.nvim_get_hl(0, {})
        return {
            first_groups = rendered_groups(first_state),
            second_groups = rendered_groups(second_state),
            first_track = get("ScrollbarProfile1.Track"),
            first_thumb = get("ScrollbarProfile1.Thumb"),
            first_pressed = get("ScrollbarProfile1.ThumbPressed"),
            first_mark = get("ScrollbarProfile1.Search"),
            second_track = get("ScrollbarProfile2.Track"),
            second_thumb = get("ScrollbarProfile2.Thumb"),
            legacy_profile_group = names["ScrollbarProfile1.Handle"] ~= nil,
            root_legacy_group = names.ScrollbarHandle ~= nil,
        }
    end, base_config())

    expect.equality(result.first_groups["ScrollbarProfile1.Track"], true)
    expect.equality(result.first_groups["ScrollbarProfile1.ThumbPressed"], true)
    expect.equality(result.second_groups["ScrollbarProfile2.Track"], true)
    expect.equality(result.second_groups["ScrollbarProfile2.Thumb"], true)
    expect.equality(result.first_track, { bg = 0x112233 })
    expect.equality(result.first_thumb, { bg = 0x223344, blend = 11 })
    expect.equality(result.first_pressed.blend, 11)
    expect.equality(result.first_mark, { fg = 0xABCDEF })
    expect.equality(result.second_track, { bg = 0x445566 })
    expect.equality(result.second_thumb, { bg = 0x556677, blend = 22 })
    expect.equality(result.legacy_profile_group, false)
    expect.equality(result.root_legacy_group, true)
end

T["manual highlight mode keeps every variant on canonical user groups"] = function()
    local child = new_child()
    local result = child.lua_func(function(config)
        config.profiles = {
            { match = { filetypes = { "lua" } }, preset = "review" },
            { match = { buftypes = { "nofile" } }, preset = "minimal" },
        }
        require("scrollbar").setup({ scrollbar = config })
        local variants = require("scrollbar.config").get_variants()
        local groups = {}
        for _, variant in ipairs(variants) do
            groups[#groups + 1] = variant.config.highlights
        end
        local profile_names = {}
        local generated_names = {}
        for name in pairs(vim.api.nvim_get_hl(0, {})) do
            if name:match("^ScrollbarProfile") then
                profile_names[#profile_names + 1] = name
            end
            if name:match("^ScrollbarGenerated%.") then
                generated_names[#generated_names + 1] = name
            end
        end
        return { groups = groups, profile_names = profile_names, generated_names = generated_names }
    end, base_config({ set_highlights = false }))

    expect.equality(result.profile_names, {})
    expect.equality(result.generated_names, {})
    expect.equality(#result.groups, 3)
    for _, groups in ipairs(result.groups) do
        expect.equality(groups.track, "ScrollbarTrack")
        expect.equality(groups.thumb, "ScrollbarThumb")
        expect.equality(groups.thumb_pressed, "ScrollbarThumbPressed")
        expect.equality(groups.marks.Search.mark, "ScrollbarSearch")
        expect.equality(groups.marks.Search.thumb, "ScrollbarSearchThumb")
        expect.equality(groups.marks.Search.thumb_pressed, "ScrollbarSearchThumbPressed")
    end
end

return T
