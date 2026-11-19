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

local function base_config(scrollbar, top)
    return vim.tbl_deep_extend("force", {
        set_highlights = true,
        providers = {
            cursor = false,
            diagnostic = false,
            search = false,
            marks = false,
        },
        scrollbar = vim.tbl_deep_extend("force", {
            mouse = false,
            hide_on_cursor = false,
            throttle_ms = 0,
            thumb = { hide_if_all_visible = false },
        }, scrollbar or {}),
    }, top or {})
end

-- Installs `require("scrollbar.test.inactive")` in the child: two vertical
-- splits of one 300-line buffer, and a reader of the groups in each float.
local function install()
    local lines = {}
    for index = 1, 300 do
        lines[index] = "line " .. index
    end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    local left = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local right = vim.api.nvim_get_current_win()

    local M = { left = left, right = right }
    package.loaded["scrollbar.test.inactive"] = M

    ---The sorted groups in the scrollbar float of `winid`, or false without a
    ---float.
    ---@param winid integer
    ---@return string[]|false
    M.groups = function(winid)
        require("scrollbar.scheduler").flush()
        local state = require("scrollbar.renderer").get_state(winid)
        if state == nil then
            return false
        end
        local namespace = vim.api.nvim_get_namespaces().ScrollbarRenderer
        local seen = {}
        local marks = require("scrollbar.test.float").extmarks(state.float_buf, namespace, 0, -1, { details = true })
        for _, mark in ipairs(marks) do
            seen[mark[4].hl_group] = true
        end
        local result = vim.tbl_keys(seen)
        table.sort(result)
        return result
    end

    ---@return { left: string[]|false, right: string[]|false }
    M.both = function()
        return { left = M.groups(left), right = M.groups(right) }
    end

    ---@param name string
    M.hl = function(name)
        return vim.api.nvim_get_hl(0, { name = name, link = false })
    end

    ---@param name string
    M.exists = function(name)
        return vim.fn.hlexists(name) == 1
    end

    ---Publish one mark of `mark_type` on the first line in both windows.
    ---@param mark_type string
    M.mark = function(mark_type)
        local providers = require("scrollbar.providers")
        providers.register({
            name = "inactive_test",
            refresh_owner = { buffer = "manager" },
            refresh = function()
                return { { line = 0, type = mark_type } }
            end,
        })
        providers.refresh(vim.api.nvim_win_get_buf(left))
    end
end

local function setup(child, config)
    child.lua_func(install)
    child.lua_func(function(value)
        require("scrollbar").setup(value)
    end, config)
end

T["a config without inactive colors creates no inactive group and swaps nothing"] = function()
    local child = new_child()
    setup(
        child,
        base_config({
            profiles = { { match = { filetypes = { "help" } }, thumb = { blend = 10 } } },
        })
    )
    local result = child.lua_func(function()
        local test = require("scrollbar.test.inactive")
        local highlights = require("scrollbar.highlights")
        local maps = {}
        for _, variant in ipairs(require("scrollbar.config").get_variants()) do
            maps[#maps + 1] = highlights.inactive_map(variant.config) ~= nil
        end
        local groups = test.both()
        local names = {}
        for _, name in ipairs(vim.fn.getcompletion("Scrollbar", "highlight")) do
            if name:find("Inactive", 1, true) then
                names[#names + 1] = name
            end
        end
        return {
            maps = maps,
            groups = groups,
            inactive_names = names,
            left_inactive = require("scrollbar.renderer").get_state(test.left).inactive,
        }
    end)
    expect.equality(result.maps, { false, false })
    expect.equality(result.groups.left, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.groups.right, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.inactive_names, {})
    expect.equality(result.left_inactive, false)
end

T["thumb.inactive_highlight swaps the groups of the window without focus"] = function()
    local child = new_child()
    setup(child, base_config({ thumb = { inactive_highlight = "InactiveThumbSource" } }))
    local result = child.lua_func(function()
        vim.api.nvim_set_hl(0, "InactiveThumbSource", { bg = "#123456" })
        require("scrollbar.highlights").set_highlights()
        local test = require("scrollbar.test.inactive")
        local before = test.both()
        vim.api.nvim_set_current_win(test.left)
        local after = test.both()
        return { before = before, after = after, thumb = test.hl("ScrollbarThumbInactive") }
    end)
    expect.equality(result.before.left, { "ScrollbarThumbInactive", "ScrollbarTrack" })
    expect.equality(result.before.right, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.after.left, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.after.right, { "ScrollbarThumbInactive", "ScrollbarTrack" })
    -- The inactive thumb takes the blend of the thumb.
    expect.equality(result.thumb, { bg = 0x123456, ctermbg = 23, blend = 30 })
end

T["a public inactive group turns on the swap without the option"] = function()
    local child = new_child()
    setup(child, base_config())
    local result = child.lua_func(function()
        local test = require("scrollbar.test.inactive")
        local before = test.both()
        vim.api.nvim_set_hl(0, "ScrollbarTrackInactive", { bg = "#010203" })
        -- A definition after setup takes effect on refresh.
        require("scrollbar").refresh()
        local refreshed = test.both()
        vim.cmd("highlight clear")
        vim.api.nvim_exec_autocmds("ColorScheme", {})
        local cleared = test.both()
        return { before = before, refreshed = refreshed, cleared = cleared }
    end)
    expect.equality(result.before.left, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.refreshed.left, { "ScrollbarThumb", "ScrollbarTrackInactive" })
    expect.equality(result.refreshed.right, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.cleared.left, { "ScrollbarThumb", "ScrollbarTrack" })
end

T["a group defined before setup turns on the swap, and a second setup without the option turns it off"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config, with_option)
        local test = require("scrollbar.test.inactive")
        vim.api.nvim_set_hl(0, "ScrollbarThumbInactive", { bg = "#0a0b0c" })
        require("scrollbar").setup(config)
        local defined = test.both()
        local definition = test.hl("ScrollbarThumbInactive")
        vim.api.nvim_set_hl(0, "ScrollbarThumbInactive", {})
        require("scrollbar").setup(with_option)
        local with_option_groups = test.both()
        require("scrollbar").setup(config)
        -- The default link of the plugin from the earlier setup stays, but it
        -- does not count as a user definition.
        return {
            defined = defined,
            definition = definition,
            with_option = with_option_groups,
            without_option = test.both(),
            link = vim.api.nvim_get_hl(0, { name = "ScrollbarThumbInactive" }).link,
        }
    end, base_config(), base_config({ thumb = { inactive_highlight = "Normal" } }))
    expect.equality(result.defined.left, { "ScrollbarThumbInactive", "ScrollbarTrack" })
    expect.equality(result.definition, { bg = 0x0A0B0C })
    expect.equality(result.with_option.left, { "ScrollbarThumbInactive", "ScrollbarTrack" })
    expect.equality(result.link, "ScrollbarGenerated.ThumbInactive")
    expect.equality(result.without_option.left, { "ScrollbarThumb", "ScrollbarTrack" })
end

T["an overlap takes the inactive color of each part that is on"] = function()
    local child = new_child()
    local function definitions(config)
        return child.lua_func(function(value)
            vim.api.nvim_set_hl(0, "ThumbSource", { bg = "#111111" })
            vim.api.nvim_set_hl(0, "InactiveThumbSource", { bg = "#222222" })
            vim.api.nvim_set_hl(0, "MarkSource", { fg = "#333333" })
            vim.api.nvim_set_hl(0, "InactiveMarkSource", { fg = "#444444" })
            require("scrollbar").setup(value)
            local test = require("scrollbar.test.inactive")
            local map = require("scrollbar.highlights").inactive_map(require("scrollbar.config").get()) or {}
            return {
                mark = test.exists("ScrollbarMarkInactive") and test.hl("ScrollbarMarkInactive") or false,
                overlap = test.hl("ScrollbarMarkThumbInactive"),
                mapped = {
                    mark = map.ScrollbarMark,
                    overlap = map.ScrollbarMarkThumb,
                    thumb = map.ScrollbarThumb,
                    pressed = map.ScrollbarMarkThumbPressed,
                },
            }
        end, config)
    end
    child.lua_func(install)

    local thumb_only = definitions(base_config({
        thumb = { highlight = "ThumbSource", inactive_highlight = "InactiveThumbSource" },
        marks = { Mark = { highlight = "MarkSource" } },
    }))
    expect.equality(thumb_only.mark, false)
    expect.equality(thumb_only.overlap, { fg = 0x333333, ctermfg = 236, bg = 0x222222, ctermbg = 235, blend = 30 })
    expect.equality(thumb_only.mapped, {
        overlap = "ScrollbarMarkThumbInactive",
        thumb = "ScrollbarThumbInactive",
    })

    local mark_only = definitions(base_config({
        thumb = { highlight = "ThumbSource" },
        marks = { Mark = { highlight = "MarkSource", inactive_highlight = "InactiveMarkSource" } },
    }))
    expect.equality(mark_only.mark, { fg = 0x444444, ctermfg = 238 })
    expect.equality(mark_only.overlap, { fg = 0x444444, ctermfg = 238, bg = 0x111111, ctermbg = 233, blend = 30 })
    expect.equality(mark_only.mapped, {
        mark = "ScrollbarMarkInactive",
        overlap = "ScrollbarMarkThumbInactive",
    })
end

T["the inactive tint follows the inactive mark"] = function()
    local child = new_child()
    setup(
        child,
        base_config({
            overlap = { marks = "tint" },
            marks = { Warn = { highlight = "MarkSource", inactive_highlight = "InactiveMarkSource" } },
        })
    )
    local result = child.lua_func(function()
        vim.api.nvim_set_hl(0, "MarkSource", { fg = "#333333" })
        vim.api.nvim_set_hl(0, "InactiveMarkSource", { fg = "#444444" })
        require("scrollbar.highlights").set_highlights()
        local test = require("scrollbar.test.inactive")
        test.mark("Warn")
        return {
            tint = test.hl("ScrollbarWarnTintInactive"),
            groups = test.both(),
        }
    end)
    expect.equality(result.tint, { bg = 0x444444, ctermbg = 238, blend = 0 })
    expect.equality(vim.tbl_contains(result.groups.left, "ScrollbarWarnTintInactive"), true)
    expect.equality(vim.tbl_contains(result.groups.right, "ScrollbarWarnTint"), true)
end

T["inactive_highlight_channel defaults to highlight_channel"] = function()
    local child = new_child()
    setup(
        child,
        base_config({
            marks = {
                Warn = {
                    highlight = "Source",
                    highlight_channel = "bg",
                    inactive_highlight = "InactiveSource",
                },
                Info = {
                    highlight = "Source",
                    highlight_channel = "bg",
                    inactive_highlight = "InactiveSource",
                    inactive_highlight_channel = "fg",
                },
            },
        })
    )
    local result = child.lua_func(function()
        vim.api.nvim_set_hl(0, "Source", { fg = "#010101", bg = "#020202" })
        vim.api.nvim_set_hl(0, "InactiveSource", { fg = "#a0a0a0", bg = "#b0b0b0" })
        require("scrollbar.highlights").set_highlights()
        local test = require("scrollbar.test.inactive")
        return { warn = test.hl("ScrollbarWarnInactive"), info = test.hl("ScrollbarInfoInactive") }
    end)
    expect.equality(result.warn.fg, 0xB0B0B0)
    expect.equality(result.info.fg, 0xA0A0A0)
end

T["a profile copies the final root group or generates its own"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        local test = require("scrollbar.test.inactive")
        config.scrollbar.profiles = {
            {
                match = {
                    when = function(context)
                        return context.winid == test.right
                    end,
                },
                thumb = { inactive_highlight = { bg = "#abcdef" } },
            },
            { match = { filetypes = { "help" } }, placement = { col = 1 } },
        }
        vim.api.nvim_set_hl(0, "InactiveThumbSource", { bg = "#123456" })
        vim.api.nvim_set_hl(0, "ScrollbarThumbInactive", { bg = "#654321" })
        require("scrollbar").setup(config)
        vim.api.nvim_set_current_win(test.left)
        local right = test.groups(test.right)
        return {
            own = test.hl("ScrollbarProfile1.ThumbInactive"),
            copy = test.hl("ScrollbarProfile2.ThumbInactive"),
            right = right,
        }
    end, base_config({ thumb = { inactive_highlight = "InactiveThumbSource" } }))
    expect.equality(result.own, { bg = 0xABCDEF, blend = 30 })
    -- The profile has the options of the root, so it copies the user
    -- definition of the public group.
    expect.equality(result.copy, { bg = 0x654321 })
    expect.equality(result.right, { "ScrollbarProfile1.ThumbInactive", "ScrollbarProfile1.Track" })
end

T["the pressed groups win over the inactive groups"] = function()
    local child = new_child()
    setup(child, base_config({ thumb = { inactive_highlight = "Normal" } }))
    local result = child.lua_func(function()
        local test = require("scrollbar.test.inactive")
        local renderer = require("scrollbar.renderer")
        test.both()
        local state = assert(renderer.get_state(test.left))
        local before = state.inactive
        assert(renderer.set_handle_pressed(state.float_win, true))
        local pressed = test.groups(test.left)
        assert(renderer.set_handle_pressed(state.float_win, false))
        return { before = before, pressed = pressed, released = test.groups(test.left) }
    end)
    expect.equality(result.before, true)
    expect.equality(result.pressed, { "ScrollbarThumbPressed", "ScrollbarTrack" })
    expect.equality(result.released, { "ScrollbarThumbInactive", "ScrollbarTrack" })
end

T["every window is inactive while a float that is not a source has focus"] = function()
    local child = new_child()
    setup(child, base_config({ thumb = { inactive_highlight = "Normal" } }))
    local result = child.lua_func(function()
        local test = require("scrollbar.test.inactive")
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_open_win(buf, true, { relative = "editor", row = 1, col = 1, width = 10, height = 2 })
        return test.both()
    end)
    expect.equality(result.left, { "ScrollbarThumbInactive", "ScrollbarTrack" })
    expect.equality(result.right, { "ScrollbarThumbInactive", "ScrollbarTrack" })
end

T["the source window of a focused minimap float stays active"] = function()
    local child = new_child()
    setup(
        child,
        base_config({ thumb = { inactive_highlight = "Normal" } }, {
            providers = { treesitter = false },
            minimap = { enabled = true, backend = "sync", throttle_ms = 0, hide_on_cursor = false, mouse = false },
        })
    )
    local result = child.lua_func(function()
        local test = require("scrollbar.test.inactive")
        require("scrollbar.minimap.scheduler").flush()
        local minimap = assert(require("scrollbar.minimap.renderer").get_state(test.right))
        -- A drag on the minimap focuses its float and scrolls the source
        -- window, and the scroll renders the scrollbar.
        vim.cmd("noautocmd call nvim_set_current_win(" .. minimap.float_win .. ")")
        require("scrollbar.renderer").render(test.left)
        require("scrollbar.renderer").render(test.right)
        return test.both()
    end)
    expect.equality(result.left, { "ScrollbarThumbInactive", "ScrollbarTrack" })
    expect.equality(result.right, { "ScrollbarThumb", "ScrollbarTrack" })
end

T["manual highlight mode swaps to the inactive groups that the user defines"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        local test = require("scrollbar.test.inactive")
        require("scrollbar").setup(config)
        local undefined = test.both()
        vim.api.nvim_set_hl(0, "ScrollbarThumbInactive", { bg = "#000001" })
        require("scrollbar").refresh()
        return {
            undefined = undefined,
            defined = test.both(),
            generated = test.exists("ScrollbarGenerated.ThumbInactive"),
        }
    end, base_config(nil, { set_highlights = false }))
    expect.equality(result.undefined.left, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.defined.left, { "ScrollbarThumbInactive", "ScrollbarTrack" })
    expect.equality(result.defined.right, { "ScrollbarThumb", "ScrollbarTrack" })
    expect.equality(result.generated, false)
end

return T
