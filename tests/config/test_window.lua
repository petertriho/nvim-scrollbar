local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.config.window"] = nil
            package.loaded["scrollbar.minimap.config"] = nil
        end,
    },
})

local NO_SIDES = { top = 0, right = 0, bottom = 0, left = 0 }
local ALL_SIDES = { top = 1, right = 1, bottom = 1, left = 1 }

local function set_top(overrides)
    return require("scrollbar.config").set(overrides)
end

local function scrollbar_window(window)
    return set_top({ scrollbar = { window = window } }).window
end

local function minimap_window(window)
    set_top({ minimap = { enabled = true, window = window } })
    return require("scrollbar.config").get_minimap().window
end

local function expect_invalid(overrides, pattern)
    local ok, err = pcall(set_top, overrides)
    expect.equality(ok, false)
    if tostring(err):match(pattern) == nil then
        error(string.format("error %q does not match %q", tostring(err), pattern))
    end
end

T["defaults to no border and no window options in both blocks"] = function()
    local scrollbar = scrollbar_window(nil)
    local minimap = minimap_window(nil)

    for _, window in ipairs({ scrollbar, minimap }) do
        expect.equality(window.open, { border = "none" })
        expect.equality(window.wo, {})
        expect.equality(window.winhighlight, false)
        expect.equality(window.sides, NO_SIDES)
    end
    expect.equality(scrollbar.signature, minimap.signature)
end

T["the default window opens no probe float"] = function()
    local open_win = vim.api.nvim_open_win
    local opened = 0
    rawset(vim.api, "nvim_open_win", function(...)
        opened = opened + 1
        return open_win(...)
    end)
    local ok, err = pcall(set_top, {
        scrollbar = { profiles = { { match = { filetypes = { "lua" } }, thumb = { text = "#" } } } },
        minimap = { enabled = true },
    })
    rawset(vim.api, "nvim_open_win", open_win)

    expect.equality(ok, true, err)
    expect.equality(opened, 0)
end

T["computes the sides from the border that Neovim reports"] = function()
    expect.equality(scrollbar_window({ border = "rounded" }).sides, ALL_SIDES)
    expect.equality(scrollbar_window({ border = "shadow" }).sides, { top = 0, right = 1, bottom = 1, left = 0 })
    expect.equality(
        scrollbar_window({ border = { "", "", "", "│", "", "", "", "│" } }).sides,
        { top = 0, right = 1, bottom = 0, left = 1 }
    )
    expect.equality(scrollbar_window({ border = { "x" } }).sides, ALL_SIDES)
    expect.equality(
        minimap_window({ border = { { "+", "Error" }, { "-", "Error" }, { "+", "Error" }, { "|", "Error" } } }).sides,
        ALL_SIDES
    )
    expect.equality(scrollbar_window({ border = "none", wo = { cursorline = true } }).sides, NO_SIDES)
end

T["keeps the keys for nvim_open_win and splits the window options"] = function()
    local window = scrollbar_window({
        border = "single",
        title = "map",
        title_pos = "center",
        wo = { cursorline = true, winhl = "FloatBorder:Error,FloatTitle:Title" },
    })

    expect.equality(window.open, { border = "single", title = "map", title_pos = "center" })
    expect.equality(window.wo, { cursorline = true })
    expect.equality(window.winhighlight, {
        value = "FloatBorder:Error,FloatTitle:Title",
        groups = { FloatBorder = true, FloatTitle = true },
    })
end

T["merges the user winhighlight entries over the renderer entries"] = function()
    local window_config = require("scrollbar.config.window")
    local base = "Normal:Base,FloatBorder:Border,FloatTitle:Title"

    expect.equality(window_config.winhighlight(base, scrollbar_window(nil)), base)
    expect.equality(
        window_config.winhighlight(
            base,
            scrollbar_window({ wo = { winhighlight = "FloatBorder:Error,Search:Normal" } })
        ),
        "Normal:Base,FloatTitle:Title,FloatBorder:Error,Search:Normal"
    )
    expect.equality(window_config.winhighlight(base, scrollbar_window({ wo = { winhighlight = "" } })), base)

    -- A user entry for a search group replaces the search entry of the base.
    local searched = "Normal:Base," .. require("scrollbar.shared.float").SEARCH_WINHIGHLIGHT
    expect.equality(
        window_config.winhighlight(searched, scrollbar_window({ wo = { winhighlight = "Search:Foo" } })),
        "Normal:Base,CurSearch:Scrollbar.NoSearch,IncSearch:Scrollbar.NoSearch,Search:Foo"
    )
    expect.equality(window_config.winhighlight(searched, scrollbar_window(nil)), searched)
end

T["rejects the keys that the renderer sets with a hint"] = function()
    local cases = {
        { key = "anchor", value = "NW", hint = "use 'placement%.anchor'" },
        { key = "relative", value = "editor", hint = "use 'placement%.relative'" },
        { key = "row", value = 1, hint = "use 'placement%.row'" },
        { key = "zindex", value = 1, hint = "use 'placement%.zindex'" },
        { key = "mouse", value = false, hint = "use 'mouse'" },
        { key = "hide", value = true, hint = "use 'hide_on_cursor', 'autohide', or 'show'" },
        { key = "style", value = "minimal", hint = "the renderer owns this key" },
        { key = "noautocmd", value = true, hint = "the renderer owns this key" },
    }
    for _, case in ipairs(cases) do
        expect_invalid(
            { scrollbar = { window = { [case.key] = case.value } } },
            "scrollbar%.window%." .. case.key .. ": the renderer sets this key %(" .. case.hint .. "%)$"
        )
    end
    expect_invalid(
        { scrollbar = { window = { width = 2 } } },
        "scrollbar%.window%.width: the renderer sets this key %(the layout sets the width%)$"
    )
    expect_invalid(
        { minimap = { enabled = true, window = { height = 2 } } },
        "minimap%.window%.height: the renderer sets this key %(use 'height'%)$"
    )
end

T["reports the first invalid key in a fixed order"] = function()
    expect_invalid({ scrollbar = { window = { zindex = 1, anchor = "NW" } } }, "scrollbar%.window%.anchor:")
    expect_invalid({ scrollbar = { window = { [1] = "x" } } }, "scrollbar%.window must be a table keyed by name$")
    expect_invalid({ scrollbar = { window = "rounded" } }, "scrollbar%.window must be a table$")
    expect_invalid({ scrollbar = { window = { wo = "x" } } }, "scrollbar%.window%.wo must be a table$")
end

T["lets Neovim reject an unknown key or an invalid value"] = function()
    expect_invalid(
        { scrollbar = { window = { bordr = "rounded" } } },
        "^%[nvim%-scrollbar%] scrollbar%.window: .*bordr"
    )
    expect_invalid(
        { scrollbar = { window = { border = "fancy" } } },
        "^%[nvim%-scrollbar%] scrollbar%.window: .*border"
    )
    local profile = { match = { filetypes = { "lua" } }, window = { border = "nope" } }
    expect_invalid(
        { minimap = { enabled = true, profiles = { profile } } },
        "^%[nvim%-scrollbar%] minimap%.profiles%[1%]%.window: .*border"
    )
    expect_invalid(
        { scrollbar = { window = { wo = { cursorline = "yes" } } } },
        "^%[nvim%-scrollbar%] scrollbar%.window%.wo%.cursorline: "
    )
end

T["rejects the window options that the renderer sets"] = function()
    for _, name in ipairs({ "number", "relativenumber", "signcolumn", "foldcolumn", "statuscolumn", "wrap" }) do
        expect_invalid(
            { scrollbar = { window = { wo = { [name] = vim.api.nvim_get_option_info2(name, {}).default } } } },
            "scrollbar%.window%.wo%." .. name .. ": the renderer sets this option, because it changes the text area"
        )
    end
    expect_invalid(
        { scrollbar = { window = { wo = { nu = true } } } },
        "scrollbar%.window%.wo%.nu: the renderer sets this option, because it changes the text area"
    )
    expect_invalid(
        { minimap = { enabled = true, window = { wo = { winblend = 10 } } } },
        "minimap%.window%.wo%.winblend: the renderer sets this option %(use 'blend'%)$"
    )
    expect_invalid(
        { minimap = { enabled = true, window = { wo = { winbl = 10 } } } },
        "minimap%.window%.wo%.winbl: the renderer sets this option %(use 'blend'%)$"
    )
    expect.equality(scrollbar_window({ wo = { winblend = 10 } }).wo, { winblend = 10 })
end

T["rejects names that are not window options"] = function()
    expect_invalid(
        { scrollbar = { window = { wo = { tabstop = 4 } } } },
        "scrollbar%.window%.wo%.tabstop is not a window option$"
    )
    expect_invalid(
        { scrollbar = { window = { wo = { ignorecase = true } } } },
        "scrollbar%.window%.wo%.ignorecase is not a window option$"
    )
    expect_invalid(
        { scrollbar = { window = { wo = { nope = 1 } } } },
        "scrollbar%.window%.wo%.nope is not a window option$"
    )
    expect_invalid(
        { scrollbar = { window = { wo = { winhl = "A:B", winhighlight = "C:D" } } } },
        "scrollbar%.window%.wo%.winhl duplicates option 'winhighlight'$"
    )
end

T["the probe leaves no window or buffer and fires no autocmd"] = function()
    local windows = #vim.api.nvim_list_wins()
    local buffers = #vim.api.nvim_list_bufs()
    local eventignore = vim.o.eventignore
    local fired = {}
    local group = vim.api.nvim_create_augroup("ScrollbarTestWindowProbe", { clear = true })
    vim.api.nvim_create_autocmd({ "BufNew", "WinNew", "WinClosed", "BufWipeout", "OptionSet" }, {
        group = group,
        callback = function(args)
            fired[#fired + 1] = args.event
        end,
    })

    set_top({ scrollbar = { window = { border = "rounded", wo = { cursorline = true } } } })
    local ok = pcall(set_top, { scrollbar = { window = { border = "rounded", wo = { cursorline = "yes" } } } })
    vim.api.nvim_del_augroup_by_id(group)

    expect.equality(ok, false)
    expect.equality(fired, {})
    expect.equality(#vim.api.nvim_list_wins(), windows)
    expect.equality(#vim.api.nvim_list_bufs(), buffers)
    expect.equality(vim.o.eventignore, eventignore)
end

T["a failed setup keeps the active window"] = function()
    set_top({ scrollbar = { window = { border = "rounded" } } })
    expect_invalid({ scrollbar = { window = { border = "fancy" } } }, "scrollbar%.window: ")
    expect.equality(require("scrollbar.config").get().window.sides, ALL_SIDES)
end

T["profiles merge the window and can clear a root title"] = function()
    set_top({
        scrollbar = {
            window = { border = "rounded", title = "map", wo = { cursorline = true } },
            profiles = {
                { match = { filetypes = { "help" } }, window = { border = { "x" }, title = "" } },
                { match = { filetypes = { "lua" } }, thumb = { text = "#" } },
            },
        },
    })
    local variants = require("scrollbar.config").get_variants()
    local root = variants[1].config.window
    local cleared = variants[2].config.window
    local inherited = variants[3].config.window

    expect.equality(cleared.open, { border = { "x" }, title = "" })
    expect.equality(cleared.wo, { cursorline = true })
    expect.no_equality(cleared.signature, root.signature)
    expect.equality(inherited.open, root.open)
    expect.equality(inherited.signature, root.signature)
end

T["reserves the frame group names"] = function()
    expect_invalid(
        { marks = { FloatBorder = { text = "x", priority = 1, highlight = "Normal" } } },
        "highlight group 'ScrollbarFloatBorder' is claimed by the scrollbar border and scrollbar mark type 'FloatBorder'"
    )
    expect_invalid({
        marks = { FloatTitle = { text = "x", priority = 1, highlight = "Normal" } },
        scrollbar = { marks = { FloatTitle = false } },
        minimap = { enabled = true, marks = { FloatTitle = { priority = 1 } } },
    }, "minimap%.marks%.FloatTitle: conflicts with the static ScrollbarMinimapFloatTitle group")
end

return T
