local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.config.window"] = nil
            package.loaded["scrollbar.config.navigate"] = nil
        end,
    },
})

local NO_SIDES = { top = 0, right = 0, bottom = 0, left = 0 }

local function set_top(overrides)
    return require("scrollbar.config").set(overrides)
end

local function expect_invalid(overrides, pattern)
    local ok, err = pcall(set_top, overrides)
    expect.equality(ok, false)
    if tostring(err):match(pattern) == nil then
        error(string.format("error %q does not match %q", tostring(err), pattern))
    end
end

T["defaults"] = function()
    local config = require("scrollbar.config")
    local scrollbar = set_top({})
    expect.equality(scrollbar.jump, { labels = "asdfghjklqwertyuiopzxcvbnm", offset = 0 })
    expect.equality(scrollbar.hover, false)

    local peek = config.get_peek()
    expect.equality(peek.frame, "scrollbar")
    -- Without a border key, the float applies 'winborder' when it opens.
    expect.equality(peek.window.open, {})
    expect.equality(peek.window.wo, {})
    expect.equality(peek.window.winhighlight, false)
    expect.equality(peek.window.sides, NO_SIDES)

    local glance = config.get_glance()
    expect.equality({ glance.picker, glance.entries }, { "builtin", "line" })
    local builtin = glance.builtin
    expect.equality(builtin.frame, "cursor")
    expect.equality(builtin.list, { width = 0.4, side = "right" })
    expect.equality(builtin.keys, {
        list = {
            jump = { "<CR>" },
            jump_split = {},
            jump_vsplit = {},
            next = {},
            previous = {},
            focus_preview = { "<Tab>" },
            quickfix = {},
            close = { "q", "<Esc>" },
        },
        preview = { jump_split = {}, jump_vsplit = {}, next = {}, previous = {}, focus_list = {}, close = {} },
    })
    expect.equality(builtin.window.open, {})
end

T["jump"] = MiniTest.new_set()

T["jump"]["takes unique lowercase ASCII letters"] = function()
    expect.equality(set_top({ scrollbar = { jump = { labels = "fjdk" } } }).jump, { labels = "fjdk", offset = 0 })
    expect_invalid({ scrollbar = { jump = { labels = "" } } }, "scrollbar.jump.labels must be a non%-empty string")
    expect_invalid({ scrollbar = { jump = { labels = 12 } } }, "scrollbar.jump.labels must be a non%-empty string")
    expect_invalid(
        { scrollbar = { jump = { labels = "abC" } } },
        "scrollbar.jump.labels must contain only lowercase ASCII letters"
    )
    expect_invalid(
        { scrollbar = { jump = { labels = "ab1" } } },
        "scrollbar.jump.labels must contain only lowercase ASCII letters"
    )
    expect_invalid(
        { scrollbar = { jump = { labels = "aé" } } },
        "scrollbar.jump.labels must contain only lowercase ASCII letters"
    )
    expect_invalid({ scrollbar = { jump = { labels = "aba" } } }, "scrollbar.jump.labels contains duplicate label 'a'")
    expect_invalid({ scrollbar = { jump = { keys = "ab" } } }, "unknown option 'scrollbar.jump.keys'")
    expect_invalid({ scrollbar = { jump = false } }, "scrollbar.jump must be a table")
end

T["jump"]["takes an integer offset of either sign"] = function()
    expect.equality(set_top({ scrollbar = { jump = { offset = 1 } } }).jump.offset, 1)
    expect.equality(set_top({ scrollbar = { jump = { offset = -2 } } }).jump.offset, -2)
    expect_invalid({ scrollbar = { jump = { offset = 1.5 } } }, "scrollbar.jump.offset must be an integer")
    expect_invalid({ scrollbar = { jump = { offset = "right" } } }, "scrollbar.jump.offset must be an integer")
end

T["hover"] = MiniTest.new_set()

T["hover"]["is off by default and takes a boolean or a delay"] = function()
    expect.equality(set_top({ scrollbar = { hover = true } }).hover, { delay_ms = 300 })
    expect.equality(set_top({ scrollbar = { hover = { delay_ms = 0 } } }).hover, { delay_ms = 0 })
    expect.equality(set_top({ scrollbar = { hover = { delay_ms = 120 } } }).hover, { delay_ms = 120 })
    expect.equality(set_top({ scrollbar = { hover = false } }).hover, false)
    expect_invalid({ scrollbar = { hover = "yes" } }, "scrollbar.hover must be a boolean or table")
    expect_invalid(
        { scrollbar = { hover = { delay_ms = -1 } } },
        "scrollbar.hover.delay_ms must be a non%-negative integer"
    )
    expect_invalid({ scrollbar = { hover = { delay = 10 } } }, "unknown option 'scrollbar.hover.delay'")
end

T["jump and hover are global options of the scrollbar block"] = function()
    local root = set_top({
        scrollbar = {
            jump = { labels = "xyz" },
            hover = true,
            profiles = { { match = { filetypes = { "lua" } }, thumb = { text = "#" } } },
        },
    })
    local variants = require("scrollbar.config").get_variants()
    expect.equality(variants[2].config.jump, root.jump)
    expect.equality(variants[2].config.hover, root.hover)
    expect_invalid(
        { scrollbar = { profiles = { { match = { filetypes = { "lua" } }, jump = { labels = "x" } } } } },
        "scrollbar.profiles%[1%].jump is a global option and cannot be set in a profile"
    )
    expect_invalid(
        { scrollbar = { profiles = { { match = { filetypes = { "lua" } }, hover = true } } } },
        "scrollbar.profiles%[1%].hover is a global option and cannot be set in a profile"
    )
    -- The minimap block has no jump and no hover.
    expect_invalid({ minimap = { hover = true } }, "unknown option 'minimap.hover'")
end

T["peek"] = MiniTest.new_set()

T["peek"]["validates its options"] = function()
    local config = require("scrollbar.config")
    for _, preset in ipairs({ "scrollbar", "cursor", "center" }) do
        set_top({ peek = { frame = preset } })
        expect.equality(config.get_peek().frame, preset)
    end
    local function place()
        return { row = 0, col = 0, width = 10, height = 5 }
    end
    set_top({ peek = { frame = place } })
    expect.equality(config.get_peek().frame, place)

    expect_invalid({ peek = { frame = "left" } }, 'peek.frame must be "scrollbar", "cursor", "center", or a function$')
    expect_invalid({ peek = { frame = { row = 1 } } }, "peek.frame must be")
    -- The size is part of the frame.
    for _, removed in ipairs({ "position", "context", "width", "height" }) do
        expect_invalid({ peek = { [removed] = 1 } }, "unknown option 'peek." .. removed .. "'")
    end
    expect_invalid({ peek = "no" }, "peek must be a table")
end

T["peek"]["setup does not load the recipes for a preset"] = function()
    package.loaded["scrollbar.recipes"] = nil
    set_top({ peek = { frame = "center" }, glance = { builtin = { frame = "scrollbar" } } })
    expect.equality(package.loaded["scrollbar.recipes"], nil)
end

T["peek"]["window keeps 'winborder' and accepts the text-area options"] = function()
    local config = require("scrollbar.config")
    set_top({ peek = { window = { title = "Peek", border = "single", wo = { number = false, signcolumn = "no" } } } })
    local window = config.get_peek().window
    expect.equality(window.open, { border = "single", title = "Peek" })
    expect.equality(window.wo, { number = false, signcolumn = "no" })

    for _, key in ipairs({ "relative", "row", "col", "width", "height" }) do
        expect_invalid(
            { peek = { window = { [key] = 1 } } },
            "peek.window." .. key .. ": the peek float sets this key %(use 'peek.frame'%)$"
        )
    end
    expect_invalid({ peek = { window = { anchor = "NW" } } }, "peek.window.anchor: the peek float sets this key$")
    expect_invalid(
        { peek = { window = { wo = { notanoption = 1 } } } },
        "peek.window.wo.notanoption is not a window option"
    )
    -- The renderer keys that the peek does not set stay open to the user.
    set_top({ peek = { window = { zindex = 80, mouse = false } } })
    expect.equality(config.get_peek().window.open, { zindex = 80, mouse = false })
end

T["peek"]["window without a border key does not depend on 'winborder' at setup"] = function()
    if vim.fn.exists("+winborder") == 0 then
        MiniTest.skip("'winborder' is not available")
    end
    local winborder = vim.o.winborder
    MiniTest.finally(function()
        vim.o.winborder = winborder
    end)
    vim.o.winborder = "rounded"
    set_top({ peek = { window = { title = "Peek" } } })
    local window = require("scrollbar.config").get_peek().window
    expect.equality(window.open, { title = "Peek" })
    expect.equality(window.sides, NO_SIDES)
end

T["glance"] = MiniTest.new_set()

---@param builtin table
---@return table
local function builtin_top(builtin)
    return { glance = { builtin = builtin } }
end

T["glance"]["picker takes a name or a function"] = function()
    local config = require("scrollbar.config")
    for _, name in ipairs({ "builtin", "snacks", "telescope" }) do
        set_top({ glance = { picker = name } })
        expect.equality(config.get_glance().picker, name)
    end
    local picker = function() end
    set_top({ glance = { picker = picker } })
    expect.equality(config.get_glance().picker, picker)

    local message = 'glance.picker must be "builtin", "snacks", "telescope", or a function$'
    for _, value in ipairs({ "fzf", 1, false, {} }) do
        expect_invalid({ glance = { picker = value } }, message)
    end
end

T["glance"]["validates its options"] = function()
    local config = require("scrollbar.config")
    set_top({ glance = { entries = "type", builtin = { frame = "center" } } })
    expect.equality(config.get_glance().entries, "type")
    expect.equality(config.get_glance().builtin.frame, "center")
    -- The keys of the list merge with the defaults.
    set_top(builtin_top({ list = { side = "left" } }))
    expect.equality(config.get_glance().builtin.list, { width = 0.4, side = "left" })
    set_top(builtin_top({ list = { width = 40, side = "left" } }))
    expect.equality(config.get_glance().builtin.list, { width = 40, side = "left" })
    set_top(builtin_top({ list = { width = 0.25 } }))
    expect.equality(config.get_glance().builtin.list.width, 0.25)

    expect_invalid({ glance = { entries = "file" } }, "glance.entries must be one of: line, mark, type")
    expect_invalid(
        builtin_top({ frame = 1 }),
        'glance.builtin.frame must be "scrollbar", "cursor", "center", or a function$'
    )
    expect_invalid({ glance = { builtin = "cursor" } }, "glance.builtin must be a table$")
    expect_invalid(builtin_top({ list = 0.4 }), "glance.builtin.list must be a table$")
    expect_invalid(builtin_top({ list = { side = "top" } }), "glance.builtin.list.side must be one of: left, right")
    expect_invalid(builtin_top({ list = { entries = "line" } }), "unknown option 'glance.builtin.list.entries'")
    local width_message = "glance.builtin.list.width must be a number greater than 0 and less than 1,"
        .. " or a whole number greater than 1"
    -- A list as wide as the frame leaves no room for the preview.
    for _, width in ipairs({ 0, 1, 1.5, -2, "half" }) do
        expect_invalid(builtin_top({ list = { width = width } }), width_message)
    end
    expect_invalid(
        builtin_top({ window = { col = 1 } }),
        "glance.builtin.window.col: the glance window sets this key %(use 'glance.builtin.frame'%)$"
    )
    expect_invalid(builtin_top({ window = { height = 2 } }), "use 'glance.builtin.frame'")
end

T["glance"]["the options of the builtin frame are only in glance.builtin"] = function()
    for _, moved in ipairs({ "frame", "list", "keys", "window" }) do
        expect_invalid({ glance = { [moved] = {} } }, "unknown option 'glance." .. moved .. "'")
    end
    expect_invalid(builtin_top({ picker = "snacks" }), "unknown option 'glance.builtin.picker'")
end

T["glance"]["keys take a string, a list, or false"] = function()
    local config = require("scrollbar.config")
    set_top(builtin_top({ keys = { list = { jump = { "<CR>", "o" }, close = "q", focus_preview = false } } }))
    local list = config.get_glance().builtin.keys.list
    expect.equality({ list.jump, list.close, list.focus_preview }, { { "<CR>", "o" }, { "q" }, {} })

    set_top(
        builtin_top({ keys = { list = { close = false }, preview = { next = "<C-j>", close = { "Q", "<C-q>" } } } })
    )
    local keys = config.get_glance().builtin.keys
    expect.equality({ keys.list.jump, keys.list.close, keys.list.focus_preview }, { { "<CR>" }, {}, { "<Tab>" } })
    expect.equality({ keys.preview.next, keys.preview.close }, { { "<C-j>" }, { "Q", "<C-q>" } })

    expect_invalid(
        builtin_top({ keys = { list = { jump = 1 } } }),
        "glance.builtin.keys.list.jump must be false, a string, or a dense list of strings"
    )
    expect_invalid(
        builtin_top({ keys = { preview = { next = { "" } } } }),
        "glance.builtin.keys.preview.next%[1%] must be a non%-empty string"
    )
    expect_invalid(builtin_top({ keys = "q" }), "glance.builtin.keys must be a table")
    expect_invalid(builtin_top({ keys = { list = "q" } }), "glance.builtin.keys.list must be a table")
    expect_invalid(builtin_top({ keys = { preview = false } }), "glance.builtin.keys.preview must be a table")
end

T["glance"]["each pane has its own actions"] = function()
    local prefix = "unknown option 'glance.builtin.keys."
    expect_invalid(builtin_top({ keys = { list = { open = "o" } } }), prefix .. "list.open'")
    expect_invalid(builtin_top({ keys = { list = { focus_list = "x" } } }), prefix .. "list.focus_list'")
    expect_invalid(builtin_top({ keys = { preview = { jump = "x" } } }), prefix .. "preview.jump'")
    expect_invalid(builtin_top({ keys = { preview = { quickfix = "x" } } }), prefix .. "preview.quickfix'")
    expect_invalid(builtin_top({ keys = { preview = { focus_preview = "x" } } }), prefix .. "preview.focus_preview'")
    -- The keys are in the panes, not directly in `glance.builtin.keys`.
    expect_invalid(builtin_top({ keys = { jump = "<CR>" } }), prefix .. "jump'")
end

T["glance"]["two actions of one pane cannot share a key, and two panes can"] = function()
    -- Also in another spelling.
    expect_invalid(
        builtin_top({ keys = { list = { close = { "q", "<cr>" } } } }),
        "glance.builtin.keys.list.close: '<cr>' is also a key of glance.builtin.keys.list.jump"
    )
    expect_invalid(
        builtin_top({ keys = { preview = { next = "<C-j>", close = "<c-j>" } } }),
        "glance.builtin.keys.preview.close: '<c%-j>' is also a key of glance.builtin.keys.preview.next"
    )
    local config = require("scrollbar.config")
    set_top(builtin_top({ keys = { list = { next = "<C-j>" }, preview = { next = "<C-j>" } } }))
    expect.equality(config.get_glance().builtin.keys.preview.next, { "<C-j>" })
end

T["the new highlight groups are reserved"] = function()
    expect_invalid(
        { marks = { JumpLabel = { text = "x", priority = 1, highlight = "Normal" } } },
        "highlight group 'ScrollbarJumpLabel' is claimed by"
    )
    expect_invalid(
        { marks = { GlanceHeader = { text = "x", priority = 1, highlight = "Normal" } } },
        "highlight group 'ScrollbarGlanceHeader' is claimed by"
    )
end

T["failed setup preserves the peek and glance options"] = function()
    local config = require("scrollbar.config")
    set_top({ peek = { frame = "cursor" }, glance = { entries = "mark" } })
    expect_invalid({ peek = { frame = "center" }, glance = { entries = "bad" } }, "glance.entries")
    expect.equality(config.get_peek().frame, "cursor")
    expect.equality(config.get_glance().entries, "mark")
end

return T
