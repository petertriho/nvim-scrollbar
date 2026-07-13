local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
        end,
    },
})

local function set(overrides)
    return require("scrollbar.config").set(overrides)
end

local function expect_invalid(overrides, pattern)
    local ok, err = pcall(set, overrides)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

T["defaults are normalized from a fresh immutable baseline"] = function()
    local first = set({
        visibility = "active",
        float = { width = 3 },
        marks = { Search = { text = "x", column = 2 } },
        providers = { search = { live = true, backend = "sync" } },
    })

    expect.equality(first.visibility, "active")
    expect.equality(first.float.width, 3)
    expect.equality(first.marks.Search.text, { "x" })
    expect.equality(first.marks.Search.column, 2)
    expect.equality(first.providers.search, { live = true, backend = "sync" })

    local second = set()
    expect.equality(second.visibility, "all")
    expect.equality(second.float.width, 1)
    expect.equality(second.marks.Search.text, { "-", "=" })
    expect.equality(second.marks.Search.column, 1)
    expect.equality(second.providers.search, { live = false, backend = "worker" })
    expect.equality(second.providers.coc, false)
    expect.equality(second.track.highlight, "PmenuSbar")
    expect.equality(second.handle.highlight, "PmenuThumb")
end

T["advances the layout generation only for static mark-layer inputs"] = function()
    local config = require("scrollbar.config")
    local initial = config.get_layout_generation()

    set({ visibility = "active", track = { highlight = "Pmenu" }, handle = { text = "H" }, float = { zindex = 80 } })
    local unrelated = config.get_layout_generation()
    set({ float = { width = 2 }, handle = { column = 2 } })
    local width = config.get_layout_generation()
    set({ float = { width = 2 }, handle = { column = 2 }, marks = { Search = { text = "S" } } })
    local mark_text = config.get_layout_generation()
    set({
        float = { width = 2 },
        handle = { column = 2 },
        marks = { Search = { text = "S", highlight = "IncSearch" } },
    })
    local highlight = config.get_layout_generation()

    expect.equality(unrelated, initial)
    expect.equality(width, initial + 1)
    expect.equality(mark_text, initial + 2)
    expect.equality(highlight, mark_text)
end

T["accepts the complete typed schema"] = function()
    local track_highlight = { bg = "#010203", bold = true }
    local handle_highlight = { bg = "#112233", blend = 10 }
    local mark_highlight = { fg = "#abcdef", bold = true, cterm = { italic = true } }
    local result = set({
        show = false,
        visibility = "active",
        set_highlights = false,
        max_lines = 1000,
        hide_if_all_visible = true,
        render = { interval_ms = 0, geometry = "screen" },
        float = {
            width = 4,
            zindex = 60,
            placement = { relative = "editor", anchor = "SW", row = -2, col = 3 },
        },
        track = { highlight = track_highlight },
        mouse = { enabled = false },
        handle = {
            text = "#",
            column = 2,
            width = 3,
            blend = 0,
            highlight = handle_highlight,
            hide_if_all_visible = false,
        },
        marks = {
            Search = { text = { "-", "=" }, column = 4, priority = 9, highlight = "Search" },
            Custom = { text = "!", column = 1, priority = 0, highlight = mark_highlight },
        },
        providers = {
            cursor = false,
            diagnostic = false,
            search = { live = true, backend = "sync" },
            gitsigns = true,
            ale = true,
            coc = false,
        },
        excluded_buftypes = { "terminal", "nofile" },
        excluded_filetypes = { "prompt" },
    })

    expect.equality(result.max_lines, 1000)
    expect.equality(result.float.placement.row, -2)
    expect.equality(result.track.highlight, track_highlight)
    expect.equality(result.handle.width, 3)
    expect.equality(result.handle.highlight, handle_highlight)
    expect.equality(result.marks.Custom.text, { "!" })
    expect.equality(result.marks.Custom.highlight, mark_highlight)
    expect.equality(result.providers.search.live, true)
    expect.equality(result.providers.search.backend, "sync")

    local normalized_track = result.track.highlight
    local normalized_handle = result.handle.highlight
    local normalized_mark = result.marks.Custom.highlight
    assert(type(normalized_track) == "table", "normalized track highlight must be a table")
    assert(type(normalized_handle) == "table", "normalized handle highlight must be a table")
    assert(type(normalized_mark) == "table", "normalized mark highlight must be a table")
    normalized_track.bg = "#000000"
    normalized_handle.bg = "#000000"
    normalized_mark.cterm.italic = false
    expect.equality(track_highlight.bg, "#010203")
    expect.equality(handle_highlight.bg, "#112233")
    expect.equality(mark_highlight.cterm.italic, true)
end

T["rejects unknown keys at every schema level"] = function()
    expect_invalid({ throttle_ms = 10 }, "unknown option 'throttle_ms'")
    expect_invalid({ render = { delay = 10 } }, "unknown option 'render.delay'")
    expect_invalid({ float = { border = "none" } }, "unknown option 'float.border'")
    expect_invalid({ float = { placement = { win = 1 } } }, "unknown option 'float.placement.win'")
    expect_invalid({ track = { color = "red" } }, "unknown option 'track.color'")
    expect_invalid({ mouse = { button = "left" } }, "unknown option 'mouse.button'")
    expect_invalid({ handle = { color = "red" } }, "unknown option 'handle.color'")
    expect_invalid({ marks = { Search = { gui = "bold" } } }, "unknown option 'marks.Search.gui'")
    expect_invalid({ providers = { custom = true } }, "unknown option 'providers.custom'")
end

T["rejects invalid enums and scalar option types"] = function()
    expect_invalid({ visibility = "current" }, "visibility must be one of")
    expect_invalid({ render = { geometry = "fold" } }, "render.geometry must be one of")
    expect_invalid({ float = { placement = { relative = "cursor" } } }, "float.placement.relative must be one of")
    expect_invalid({ float = { placement = { anchor = "C" } } }, "float.placement.anchor must be one of")
    expect_invalid({ show = 1 }, "show must be a boolean")
    expect_invalid({ mouse = { enabled = "yes" } }, "mouse.enabled must be a boolean")
    expect_invalid({ render = false }, "render must be a table")
    expect_invalid({ float = { placement = false } }, "float.placement must be a table")
    expect_invalid({ track = false }, "track must be a table")
    expect_invalid({ marks = { Search = false } }, "marks.Search must be a table")
end

T["rejects invalid dimensions, columns, and placement offsets"] = function()
    expect_invalid({ render = { interval_ms = -1 } }, "render.interval_ms must be a non%-negative integer")
    expect_invalid({ float = { width = 0 } }, "float.width must be a positive integer")
    expect_invalid({ float = { zindex = 1.5 } }, "float.zindex must be a positive integer")
    expect_invalid({ float = { placement = { row = 0.5 } } }, "float.placement.row must be an integer")
    expect_invalid({ float = { placement = { col = "1" } } }, "float.placement.col must be an integer")
    expect_invalid({ handle = { column = 0 } }, "handle.column must be a positive integer")
    expect_invalid({ handle = { width = -1 } }, "handle.width must be a positive integer")
    expect_invalid({ handle = { blend = 101 } }, "handle.blend must be between 0 and 100")
    expect_invalid({ float = { width = 2 }, marks = { Search = { column = 3 } } }, "marks.Search.column must fit")
    expect_invalid({ max_lines = 0 }, "max_lines must be false or a positive integer")
end

T["enforces handle fit within the float"] = function()
    expect_invalid(
        { float = { width = 3 }, handle = { column = 2, width = 3 } },
        "handle.column %+ handle.width %- 1 must not exceed float.width"
    )
end

T["rejects unsafe text and malformed density variants"] = function()
    expect_invalid({ handle = { text = "" } }, "handle.text must have positive display width")
    expect_invalid({ handle = { text = "\n" } }, "handle.text must not contain control characters")
    expect_invalid({ marks = { Search = { text = {} } } }, "marks.Search.text must contain at least one variant")
    expect_invalid({ marks = { Search = { text = { "-", 2 } } } }, "marks.Search.text%[2%] must be a string")
    expect_invalid({ marks = { Search = { text = { [1] = "-", [3] = "=" } } } }, "dense list")
    expect_invalid({ marks = { Search = { text = "\t" } } }, "marks.Search.text%[1%] must not contain control")
    expect_invalid({ marks = { Search = { text = "" } } }, "marks.Search.text%[1%] must have positive display width")
end

T["rejects invalid priorities, mark names, and highlights"] = function()
    expect_invalid({ marks = { Search = { priority = -1 } } }, "marks.Search.priority must be a non%-negative integer")
    expect_invalid({ marks = { Search = { priority = 1.5 } } }, "marks.Search.priority must be a non%-negative integer")
    expect_invalid(
        { marks = { ["Bad Name"] = { text = "!", column = 1, priority = 1, highlight = "Normal" } } },
        "invalid mark type"
    )
    expect_invalid(
        { marks = { Search = { highlight = "" } } },
        "marks.Search.highlight must be a non%-empty string or table"
    )
    expect_invalid({ handle = { highlight = 1 } }, "handle.highlight must be a non%-empty string or table")
    expect_invalid({ track = { highlight = "" } }, "track.highlight must be a non%-empty string or table")
    expect_invalid(
        { marks = { Search = { highlight = false } } },
        "marks.Search.highlight must be a non%-empty string or table"
    )
end

T["rejects invalid provider options"] = function()
    expect_invalid({ providers = { cursor = {} } }, "providers.cursor must be a boolean")
    expect_invalid({ providers = { search = "yes" } }, "providers.search must be a boolean or table")
    expect_invalid({ providers = { search = { live = "yes" } } }, "providers.search.live must be a boolean")
    expect_invalid(
        { providers = { search = { backend = "thread" } } },
        "providers.search.backend must be one of: sync, worker"
    )
    expect_invalid({ providers = { search = { extra = true } } }, "unknown option 'providers.search.extra'")
end

T["rejects malformed exclusion lists without changing active config"] = function()
    local before = set({ visibility = "active" })
    expect_invalid({ excluded_filetypes = { "lua", false } }, "excluded_filetypes%[2%] must be a string")
    expect.equality(require("scrollbar.config").get(), before)
end

return T
