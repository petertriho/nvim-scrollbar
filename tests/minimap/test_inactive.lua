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

local function base_config(minimap, top)
    return vim.tbl_deep_extend("force", {
        set_highlights = true,
        providers = {
            cursor = { scrollbar = false, minimap = true },
            diagnostic = false,
            search = false,
            marks = false,
            treesitter = false,
        },
        scrollbar = { enabled = false },
        minimap = vim.tbl_deep_extend("force", {
            enabled = true,
            backend = "sync",
            throttle_ms = 0,
            hide_on_cursor = false,
            mouse = false,
            width = 6,
        }, minimap or {}),
    }, top or {})
end

-- Installs `require("scrollbar.test.inactive")` in the child: two vertical
-- splits of one 300-line buffer, and a reader of the groups in each minimap.
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

    ---Publish one `Error` mark on the first line.
    M.mark = function()
        local providers = require("scrollbar.providers")
        providers.register({
            name = "inactive_test",
            targets = { minimap = true },
            refresh_owner = { buffer = "manager" },
            refresh = function()
                return { { line = 0, type = "Error" } }
            end,
        })
        providers.refresh(vim.api.nvim_win_get_buf(left))
    end

    ---The sorted groups in the minimap float of `winid`, or false without a
    ---float.
    ---@param winid integer
    ---@return string[]|false
    M.groups = function(winid)
        require("scrollbar.minimap.scheduler").flush()
        local state = require("scrollbar.minimap.renderer").get_state(winid)
        if state == nil then
            return false
        end
        local namespace = vim.api.nvim_get_namespaces().ScrollbarMinimapRenderer
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
end

T["a config without inactive groups swaps nothing and creates no inactive group"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        require("scrollbar").setup(config)
        local test = require("scrollbar.test.inactive")
        test.mark()
        local names = {}
        for _, name in ipairs(vim.fn.getcompletion("ScrollbarMinimap", "highlight")) do
            if name:find("Inactive", 1, true) then
                names[#names + 1] = name
            end
        end
        local config_module = require("scrollbar.minimap.config")
        return {
            map = require("scrollbar.minimap.highlights").inactive_map(config_module.get()) ~= nil,
            groups = test.both(),
            names = names,
        }
    end, base_config())
    expect.equality(result.map, false)
    expect.equality(result.groups.left, result.groups.right)
    expect.equality(vim.tbl_contains(result.groups.left, "ScrollbarMinimapViewport"), true)
    expect.equality(vim.tbl_contains(result.groups.left, "ScrollbarMinimapError"), true)
    expect.equality(result.names, {})
end

T["the static twins apply only when a user or a colorscheme defines them"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        local test = require("scrollbar.test.inactive")
        vim.api.nvim_set_hl(0, "ScrollbarMinimapViewportInactive", { bg = "#202020" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapContentInactive", { fg = "#303030" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapCursorInactive", { fg = "#404040" })
        require("scrollbar").setup(config)
        local before = test.both()
        vim.api.nvim_set_current_win(test.left)
        return { before = before, after = test.both() }
    end, base_config())
    expect.equality(result.before.left, {
        "ScrollbarMinimapContentInactive",
        "ScrollbarMinimapCursorInactive",
        "ScrollbarMinimapViewportInactive",
    })
    expect.equality(result.before.right, {
        "ScrollbarMinimapContent",
        "ScrollbarMinimapCursor",
        "ScrollbarMinimapViewport",
    })
    expect.equality(result.after.left, result.before.right)
    expect.equality(result.after.right, result.before.left)
end

T["a twin that a user defines after setup takes effect on refresh"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        local test = require("scrollbar.test.inactive")
        require("scrollbar").setup(config)
        local before = test.groups(test.left)
        vim.api.nvim_set_hl(0, "ScrollbarMinimapViewportInactive", { bg = "#202020" })
        require("scrollbar.minimap").refresh()
        return { before = before, after = test.groups(test.left) }
    end, base_config())
    expect.equality(vim.tbl_contains(result.before, "ScrollbarMinimapViewport"), true)
    expect.equality(vim.tbl_contains(result.after, "ScrollbarMinimapViewportInactive"), true)
    expect.equality(vim.tbl_contains(result.after, "ScrollbarMinimapContent"), true)
end

T["the source window of a focused scrollbar float stays active"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(
        function(config)
            local test = require("scrollbar.test.inactive")
            vim.api.nvim_set_hl(0, "ScrollbarMinimapViewportInactive", { bg = "#202020" })
            require("scrollbar").setup(config)
            require("scrollbar.scheduler").flush()
            local scrollbar = assert(require("scrollbar.renderer").get_state(test.right))
            -- A drag on the scrollbar focuses its float and scrolls the source
            -- window, and the scroll renders the minimap.
            vim.cmd("noautocmd call nvim_set_current_win(" .. scrollbar.float_win .. ")")
            require("scrollbar.minimap.renderer").render(test.left)
            require("scrollbar.minimap.renderer").render(test.right)
            return test.both()
        end,
        base_config(nil, {
            scrollbar = {
                enabled = true,
                mouse = false,
                hide_on_cursor = false,
                throttle_ms = 0,
                thumb = { hide_if_all_visible = false },
            },
        })
    )
    expect.equality(vim.tbl_contains(result.left, "ScrollbarMinimapViewportInactive"), true)
    expect.equality(vim.tbl_contains(result.right, "ScrollbarMinimapViewport"), true)
end

T["a mark inactive_highlight swaps the minimap mark of the window without focus"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(
        function(config)
            vim.api.nvim_set_hl(0, "ErrorSource", { fg = "#aa0000" })
            vim.api.nvim_set_hl(0, "InactiveErrorSource", { fg = "#550000", bg = "#110000" })
            require("scrollbar").setup(config)
            local test = require("scrollbar.test.inactive")
            test.mark()
            return {
                groups = test.both(),
                definition = test.hl("ScrollbarMinimapErrorInactive"),
                map = require("scrollbar.minimap.highlights").inactive_map(require("scrollbar.minimap.config").get()),
            }
        end,
        base_config(nil, {
            marks = {
                Error = {
                    highlight = "ErrorSource",
                    inactive_highlight = "InactiveErrorSource",
                    inactive_highlight_channel = "bg",
                },
            },
        })
    )
    expect.equality(vim.tbl_contains(result.groups.left, "ScrollbarMinimapErrorInactive"), true)
    expect.equality(vim.tbl_contains(result.groups.left, "ScrollbarMinimapViewport"), true)
    expect.equality(vim.tbl_contains(result.groups.right, "ScrollbarMinimapError"), true)
    expect.equality(result.definition, { fg = 0x110000, ctermfg = 232 })
    expect.equality(result.map, { ScrollbarMinimapError = "ScrollbarMinimapErrorInactive" })
end

T["a profile copies the final root inactive mark or generates its own"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        vim.api.nvim_set_hl(0, "InactiveErrorSource", { fg = "#550000" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapErrorInactive", { fg = "#660000" })
        config.minimap.profiles = {
            { match = { filetypes = { "help" } }, width = 4 },
            { match = { filetypes = { "text" } }, marks = { Error = { inactive_highlight = { fg = "#770000" } } } },
        }
        require("scrollbar").setup(config)
        local test = require("scrollbar.test.inactive")
        return {
            copy = test.hl("ScrollbarMinimapProfile1.ErrorInactive"),
            own = test.hl("ScrollbarMinimapProfile2.ErrorInactive"),
        }
    end, base_config(nil, { marks = { Error = { inactive_highlight = "InactiveErrorSource" } } }))
    expect.equality(result.copy, { fg = 0x660000 })
    expect.equality(result.own, { fg = 0x770000 })
end

T["background_blend blends the inactive twin"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        vim.api.nvim_set_hl(0, "ScrollbarMinimapViewport", { bg = "#101010" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapViewportInactive", { bg = "#202020" })
        require("scrollbar").setup(config)
        local test = require("scrollbar.test.inactive")
        local function viewport_backgrounds(groups)
            local backgrounds = {}
            for _, name in ipairs(groups) do
                local bg = test.hl(name).bg
                if bg == 0x101010 or bg == 0x202020 then
                    backgrounds[#backgrounds + 1] = bg
                end
            end
            return backgrounds
        end
        local groups = test.both()
        return { left = viewport_backgrounds(groups.left), right = viewport_backgrounds(groups.right) }
    end, base_config({ background_blend = 40 }))
    expect.equality(result.left, { 0x202020 })
    expect.equality(result.right, { 0x101010 })
end

T["manual highlight mode swaps the marks to the inactive groups that the user defines"] = function()
    local child = new_child()
    child.lua_func(install)
    local result = child.lua_func(function(config)
        vim.api.nvim_set_hl(0, "ScrollbarMinimapError", { fg = "#aa0000" })
        vim.api.nvim_set_hl(0, "ScrollbarMinimapErrorInactive", { fg = "#550000" })
        require("scrollbar").setup(config)
        local test = require("scrollbar.test.inactive")
        test.mark()
        return test.both()
    end, base_config(nil, { set_highlights = false }))
    expect.equality(vim.tbl_contains(result.left, "ScrollbarMinimapErrorInactive"), true)
    expect.equality(vim.tbl_contains(result.right, "ScrollbarMinimapError"), true)
end

return T
