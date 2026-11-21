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
    expect.equality(glance.frame, "cursor")
    expect.equality(glance.list, { entries = "line", width = 0.4, side = "right" })
    expect.equality(glance.keys, {
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
    expect.equality(glance.window.open, {})
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
    set_top({ peek = { frame = "center" }, glance = { frame = "scrollbar" } })
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

T["glance"]["validates its options"] = function()
    local config = require("scrollbar.config")
    set_top({ glance = { frame = "center", list = { entries = "type" } } })
    expect.equality(config.get_glance().frame, "center")
    -- The keys of the list merge with the defaults.
    expect.equality(config.get_glance().list, { entries = "type", width = 0.4, side = "right" })
    set_top({ glance = { list = { width = 40, side = "left" } } })
    expect.equality(config.get_glance().list, { entries = "line", width = 40, side = "left" })
    set_top({ glance = { list = { width = 0.25 } } })
    expect.equality(config.get_glance().list.width, 0.25)

    expect_invalid({ glance = { frame = 1 } }, 'glance.frame must be "scrollbar", "cursor", "center", or a function$')
    expect_invalid(
        { glance = { list = "type" } },
        "glance.list must be a table: set the entries with glance.list.entries$"
    )
    expect_invalid({ glance = { list = { entries = "file" } } }, "glance.list.entries must be one of: line, mark, type")
    expect_invalid({ glance = { list = { side = "top" } } }, "glance.list.side must be one of: left, right")
    expect_invalid({ glance = { list = { position = "left" } } }, "unknown option 'glance.list.position'")
    local width_message = "glance.list.width must be a number greater than 0 and less than 1,"
        .. " or a whole number greater than 1"
    -- A list as wide as the frame leaves no room for the preview.
    for _, width in ipairs({ 0, 1, 1.5, -2, "half" }) do
        expect_invalid({ glance = { list = { width = width } } }, width_message)
    end
    for _, removed in ipairs({ "height", "width", "list_width" }) do
        expect_invalid({ glance = { [removed] = 10 } }, "unknown option 'glance." .. removed .. "'")
    end
    expect_invalid(
        { glance = { window = { col = 1 } } },
        "glance.window.col: the glance window sets this key %(use 'glance.frame'%)$"
    )
    expect_invalid({ glance = { window = { height = 2 } } }, "use 'glance.frame'")
end

T["glance"]["keys take a string, a list, or false"] = function()
    local config = require("scrollbar.config")
    set_top({ glance = { keys = { list = { jump = { "<CR>", "o" }, close = "q", focus_preview = false } } } })
    local list = config.get_glance().keys.list
    expect.equality({ list.jump, list.close, list.focus_preview }, { { "<CR>", "o" }, { "q" }, {} })

    set_top({ glance = { keys = { list = { close = false }, preview = { next = "<C-j>", close = { "Q", "<C-q>" } } } } })
    local keys = config.get_glance().keys
    expect.equality({ keys.list.jump, keys.list.close, keys.list.focus_preview }, { { "<CR>" }, {}, { "<Tab>" } })
    expect.equality({ keys.preview.next, keys.preview.close }, { { "<C-j>" }, { "Q", "<C-q>" } })

    expect_invalid(
        { glance = { keys = { list = { jump = 1 } } } },
        "glance.keys.list.jump must be false, a string, or a dense list of strings"
    )
    expect_invalid(
        { glance = { keys = { preview = { next = { "" } } } } },
        "glance.keys.preview.next%[1%] must be a non%-empty string"
    )
    expect_invalid({ glance = { keys = "q" } }, "glance.keys must be a table")
    expect_invalid({ glance = { keys = { list = "q" } } }, "glance.keys.list must be a table")
    expect_invalid({ glance = { keys = { preview = false } } }, "glance.keys.preview must be a table")
end

T["glance"]["each pane has its own actions"] = function()
    expect_invalid({ glance = { keys = { list = { open = "o" } } } }, "unknown option 'glance.keys.list.open'")
    expect_invalid(
        { glance = { keys = { list = { focus_list = "x" } } } },
        "unknown option 'glance.keys.list.focus_list'"
    )
    expect_invalid({ glance = { keys = { preview = { jump = "x" } } } }, "unknown option 'glance.keys.preview.jump'")
    expect_invalid(
        { glance = { keys = { preview = { quickfix = "x" } } } },
        "unknown option 'glance.keys.preview.quickfix'"
    )
    expect_invalid(
        { glance = { keys = { preview = { focus_preview = "x" } } } },
        "unknown option 'glance.keys.preview.focus_preview'"
    )
    -- The keys are in the panes, not directly in `glance.keys`.
    expect_invalid({ glance = { keys = { jump = "<CR>" } } }, "unknown option 'glance.keys.jump'")
end

T["glance"]["two actions of one pane cannot share a key, and two panes can"] = function()
    -- Also in another spelling.
    expect_invalid(
        { glance = { keys = { list = { close = { "q", "<cr>" } } } } },
        "glance.keys.list.close: '<cr>' is also a key of glance.keys.list.jump"
    )
    expect_invalid(
        { glance = { keys = { preview = { next = "<C-j>", close = "<c-j>" } } } },
        "glance.keys.preview.close: '<c%-j>' is also a key of glance.keys.preview.next"
    )
    local config = require("scrollbar.config")
    set_top({ glance = { keys = { list = { next = "<C-j>" }, preview = { next = "<C-j>" } } } })
    expect.equality(config.get_glance().keys.preview.next, { "<C-j>" })
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
    set_top({ peek = { frame = "cursor" }, glance = { list = { entries = "mark" } } })
    expect_invalid({ peek = { frame = "center" }, glance = { list = { entries = "bad" } } }, "glance.list")
    expect.equality(config.get_peek().frame, "cursor")
    expect.equality(config.get_glance().list.entries, "mark")
end

return T
