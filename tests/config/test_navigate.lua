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
    expect.equality(scrollbar.jump, { labels = "asdfghjklqwertyuiopzxcvbnm" })
    expect.equality(scrollbar.hover, false)

    local peek = config.get_peek()
    expect.equality(peek.position, "scrollbar")
    expect.equality(peek.context, 5)
    expect.equality(peek.width, 0.6)
    -- Without a border key, the float applies 'winborder' when it opens.
    expect.equality(peek.window.open, {})
    expect.equality(peek.window.wo, {})
    expect.equality(peek.window.winhighlight, false)
    expect.equality(peek.window.sides, NO_SIDES)

    local glance = config.get_glance()
    expect.equality(glance.list, "line")
    expect.equality(glance.height, 18)
    expect.equality(glance.keys, { jump = { "<CR>" }, close = { "q", "<Esc>" }, preview = { "<Tab>" } })
    expect.equality(glance.window.open, {})
end

T["jump"] = MiniTest.new_set()

T["jump"]["takes unique lowercase ASCII letters"] = function()
    expect.equality(set_top({ scrollbar = { jump = { labels = "fjdk" } } }).jump, { labels = "fjdk" })
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
    set_top({ peek = { position = "cursor", context = 0, width = 1 } })
    local peek = config.get_peek()
    expect.equality({ peek.position, peek.context, peek.width }, { "cursor", 0, 1 })

    expect_invalid({ peek = { position = "left" } }, "peek.position must be one of: center, cursor, scrollbar")
    expect_invalid({ peek = { context = -1 } }, "peek.context must be a non%-negative integer")
    expect_invalid({ peek = { context = 1.5 } }, "peek.context must be")
    expect_invalid({ peek = { width = 0 } }, "peek.width must be a number greater than 0 and at most 1")
    expect_invalid({ peek = { width = 1.5 } }, "peek.width must be a number greater than 0 and at most 1")
    expect_invalid({ peek = { width = "half" } }, "peek.width must be a number greater than 0 and at most 1")
    expect_invalid({ peek = { height = 4 } }, "unknown option 'peek.height'")
    expect_invalid({ peek = "no" }, "peek must be a table")
end

T["peek"]["window keeps 'winborder' and accepts the text-area options"] = function()
    local config = require("scrollbar.config")
    set_top({ peek = { window = { title = "Peek", border = "single", wo = { number = false, signcolumn = "no" } } } })
    local window = config.get_peek().window
    expect.equality(window.open, { border = "single", title = "Peek" })
    expect.equality(window.wo, { number = false, signcolumn = "no" })

    expect_invalid({ peek = { window = { row = 1 } } }, "peek.window.row: the peek float sets this key$")
    expect_invalid(
        { peek = { window = { width = 10 } } },
        "peek.window.width: the peek float sets this key %(use 'peek.width'%)"
    )
    expect_invalid({ peek = { window = { height = 10 } } }, "use 'peek.context'")
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
    set_top({ glance = { list = "type", height = 6 } })
    expect.equality({ config.get_glance().list, config.get_glance().height }, { "type", 6 })

    expect_invalid({ glance = { list = "file" } }, "glance.list must be one of: line, mark, type")
    expect_invalid({ glance = { height = 0 } }, "glance.height must be a positive integer")
    expect_invalid({ glance = { width = 10 } }, "unknown option 'glance.width'")
    expect_invalid({ glance = { window = { col = 1 } } }, "glance.window.col: the glance window sets this key$")
    expect_invalid({ glance = { window = { height = 2 } } }, "use 'glance.height'")
end

T["glance"]["keys take a string, a list, or false"] = function()
    local config = require("scrollbar.config")
    set_top({ glance = { keys = { jump = { "<CR>", "o" }, close = "q", preview = false } } })
    expect.equality(config.get_glance().keys, { jump = { "<CR>", "o" }, close = { "q" }, preview = {} })

    set_top({ glance = { keys = { close = false } } })
    expect.equality(config.get_glance().keys, { jump = { "<CR>" }, close = {}, preview = { "<Tab>" } })

    expect_invalid(
        { glance = { keys = { jump = 1 } } },
        "glance.keys.jump must be false, a string, or a dense list of strings"
    )
    expect_invalid({ glance = { keys = { jump = { "" } } } }, "glance.keys.jump%[1%] must be a non%-empty string")
    expect_invalid({ glance = { keys = { open = "o" } } }, "unknown option 'glance.keys.open'")
    expect_invalid({ glance = { keys = "q" } }, "glance.keys must be a table")
    -- Two actions cannot share one key, also in another spelling.
    expect_invalid(
        { glance = { keys = { close = { "q", "<cr>" } } } },
        "glance.keys.close: '<cr>' is also a key of glance.keys.jump"
    )
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
    set_top({ peek = { context = 2 }, glance = { list = "mark" } })
    expect_invalid({ peek = { context = 3 }, glance = { list = "bad" } }, "glance.list")
    expect.equality(config.get_peek().context, 2)
    expect.equality(config.get_glance().list, "mark")
end

return T
