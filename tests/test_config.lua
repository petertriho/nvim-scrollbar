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
        float = { width = 3, hide_on_cursor = false },
        marks = { Search = { text = "x", column = 2 }, Mark = { text = "X" } },
        providers = { search = { incsearch = true, backend = "sync" }, marks = { max_width = 3 } },
    })

    expect.equality(first.visibility, "active")
    expect.equality(first.float.width, 3)
    expect.equality(first.float.hide_on_cursor, false)
    expect.equality(first.marks.Search.text, { "x" })
    expect.equality(first.marks.Search.column, 2)
    expect.equality(first.marks.Mark.text, { "X" })
    expect.equality(first.providers.search, { incsearch = true, backend = "sync" })
    expect.equality(first.providers.marks, { max_width = 3, letters = true, numbers = false })

    first.marks.Mark.text[1] = "changed"
    first.providers.marks.max_width = 99

    local second = set()
    expect.equality(second.visibility, "all")
    expect.equality(second.float.width, 1)
    expect.equality(second.float.hide_on_cursor, true)
    expect.equality(second.marks.Search.text, { "-", "=" })
    expect.equality(second.marks.Search.column, 1)
    expect.equality(second.marks.Mark, { text = {}, column = 1, priority = 1, highlight = "Special" })
    expect.equality(second.providers.search, { backend = "worker" })
    expect.equality(second.providers.marks, { max_width = false, letters = true, numbers = false })
    expect.equality(second.providers.coc, false)
    expect.equality(second.providers.mini_diff, false)
    expect.equality(second.autohide, { enabled = false, delay_ms = 1000 })
    expect.equality(second.track.highlight, "PmenuSbar")
    expect.equality(second.handle.highlight, "PmenuThumb")
end

T["advances the layout generation only for static mark-layer inputs"] = function()
    local config = require("scrollbar.config")
    local initial = config.get_layout_generation()

    set({
        visibility = "active",
        autohide = { enabled = true, delay_ms = 250 },
        track = { highlight = "Pmenu" },
        handle = { text = "H" },
        float = { zindex = 80, hide_on_cursor = false },
    })
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
    set({
        float = { width = 2 },
        handle = { column = 2 },
        marks = { Search = { text = "S", highlight = "IncSearch" } },
        providers = { marks = true },
    })
    local collapsed_marks = config.get_layout_generation()
    set({
        float = { width = 2 },
        handle = { column = 2 },
        marks = { Search = { text = "S", highlight = "IncSearch" } },
        providers = { marks = { max_width = 4 } },
    })
    local expanded_marks = config.get_layout_generation()
    set({
        float = { width = 2 },
        handle = { column = 2 },
        marks = { Search = { text = "S", highlight = "IncSearch" } },
        providers = { marks = { max_width = 5 } },
    })
    local changed_expansion_cap = config.get_layout_generation()
    set({
        float = { width = 2, placement = { anchor = "SE" } },
        handle = { column = 2 },
        marks = { Search = { text = "S", highlight = "IncSearch" } },
        providers = { marks = { max_width = 5 } },
    })
    local same_horizontal_anchor = config.get_layout_generation()
    set({
        float = { width = 2, placement = { anchor = "SW" } },
        handle = { column = 2 },
        marks = { Search = { text = "S", highlight = "IncSearch" } },
        providers = { marks = { max_width = 5 } },
    })
    local changed_horizontal_anchor = config.get_layout_generation()

    expect.equality(unrelated, initial)
    expect.equality(width, initial + 1)
    expect.equality(mark_text, initial + 2)
    expect.equality(highlight, mark_text)
    expect.equality(collapsed_marks, highlight)
    expect.equality(expanded_marks, highlight + 1)
    expect.equality(changed_expansion_cap, expanded_marks + 1)
    expect.equality(same_horizontal_anchor, changed_expansion_cap)
    expect.equality(changed_horizontal_anchor, changed_expansion_cap + 1)
end

T["normalizes marks provider modes"] = function()
    expect.equality(set().providers.marks, { max_width = false, letters = true, numbers = false })
    expect.equality(set({ providers = { marks = false } }).providers.marks, false)

    local collapsed = set({ providers = { marks = true } })
    expect.equality(collapsed.providers.marks, { max_width = false, letters = true, numbers = false })
    collapsed.providers.marks.max_width = 8
    expect.equality(
        set({ providers = { marks = true } }).providers.marks,
        { max_width = false, letters = true, numbers = false }
    )

    expect.equality(
        set({ providers = { marks = { max_width = 8 } } }).providers.marks,
        { max_width = 8, letters = true, numbers = false }
    )
    expect.equality(
        set({ providers = { marks = { numbers = true } } }).providers.marks,
        { max_width = false, letters = true, numbers = true }
    )
    expect.equality(
        set({ providers = { marks = { letters = false, numbers = true } } }).providers.marks,
        { max_width = false, letters = false, numbers = true }
    )
end

T["normalizes tri-state search provider modes"] = function()
    expect.equality(set().providers.search, { backend = "worker" })
    expect.equality(set({ providers = { search = true } }).providers.search, { backend = "worker" })
    expect.equality(set({ providers = { search = { backend = "sync" } } }).providers.search, { backend = "sync" })
    expect.equality(set({ providers = { search = { incsearch = true } } }).providers.search, {
        incsearch = true,
        backend = "worker",
    })
    expect.equality(set({ providers = { search = { incsearch = false } } }).providers.search, {
        incsearch = false,
        backend = "worker",
    })
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
        autohide = { enabled = true, delay_ms = 750 },
        render = { interval_ms = 0, geometry = "screen" },
        float = {
            width = 4,
            zindex = 60,
            hide_on_cursor = false,
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
            search = { incsearch = true, backend = "sync" },
            marks = { max_width = 8, letters = false, numbers = true },
            gitsigns = true,
            mini_diff = true,
            ale = true,
            coc = false,
        },
        excluded_buftypes = { "terminal", "nofile" },
        excluded_filetypes = { "prompt" },
    })

    expect.equality(result.max_lines, 1000)
    expect.equality(result.autohide, { enabled = true, delay_ms = 750 })
    expect.equality(result.float.placement.row, -2)
    expect.equality(result.float.hide_on_cursor, false)
    expect.equality(result.track.highlight, track_highlight)
    expect.equality(result.handle.width, 3)
    expect.equality(result.handle.highlight, handle_highlight)
    expect.equality(result.marks.Custom.text, { "!" })
    expect.equality(result.marks.Custom.highlight, mark_highlight)
    expect.equality(result.providers.search.incsearch, true)
    expect.equality(result.providers.search.backend, "sync")
    expect.equality(result.providers.marks, { max_width = 8, letters = false, numbers = true })
    expect.equality(result.providers.mini_diff, true)

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
    expect_invalid({ autohide = { timeout = 10 } }, "unknown option 'autohide.timeout'")
    expect_invalid({ float = { border = "none" } }, "unknown option 'float.border'")
    expect_invalid({ float = { placement = { win = 1 } } }, "unknown option 'float.placement.win'")
    expect_invalid({ track = { color = "red" } }, "unknown option 'track.color'")
    expect_invalid({ mouse = { button = "left" } }, "unknown option 'mouse.button'")
    expect_invalid({ handle = { color = "red" } }, "unknown option 'handle.color'")
    expect_invalid({ marks = { Search = { gui = "bold" } } }, "unknown option 'marks.Search.gui'")
    expect_invalid({ providers = { custom = true } }, "unknown option 'providers.custom'")
    expect_invalid(
        { providers = { marks = { expand = true, max_width = 8 } } },
        "unknown option 'providers.marks.expand'"
    )
    expect_invalid({ providers = { search = { live = true } } }, "unknown option 'providers.search.live'")
end

T["rejects invalid enums and scalar option types"] = function()
    expect_invalid({ visibility = "current" }, "visibility must be one of")
    expect_invalid({ render = { geometry = "fold" } }, "render.geometry must be one of")
    expect_invalid({ float = { placement = { relative = "cursor" } } }, "float.placement.relative must be one of")
    expect_invalid({ float = { placement = { anchor = "C" } } }, "float.placement.anchor must be one of")
    expect_invalid({ show = 1 }, "show must be a boolean")
    expect_invalid({ autohide = false }, "autohide must be a table")
    expect_invalid({ autohide = { enabled = "yes" } }, "autohide.enabled must be a boolean")
    expect_invalid({ mouse = { enabled = "yes" } }, "mouse.enabled must be a boolean")
    expect_invalid({ float = { hide_on_cursor = "yes" } }, "float.hide_on_cursor must be a boolean")
    expect_invalid({ render = false }, "render must be a table")
    expect_invalid({ float = { placement = false } }, "float.placement must be a table")
    expect_invalid({ track = false }, "track must be a table")
    expect_invalid({ marks = { Search = false } }, "marks.Search must be a table")
end

T["rejects invalid dimensions, columns, and placement offsets"] = function()
    expect_invalid({ render = { interval_ms = -1 } }, "render.interval_ms must be a non%-negative integer")
    expect_invalid({ autohide = { delay_ms = 0 } }, "autohide.delay_ms must be a positive integer")
    expect_invalid({ autohide = { delay_ms = -1 } }, "autohide.delay_ms must be a positive integer")
    expect_invalid({ autohide = { delay_ms = 1.5 } }, "autohide.delay_ms must be a positive integer")
    expect_invalid({ autohide = { delay_ms = "500" } }, "autohide.delay_ms must be a positive integer")
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
    expect.equality(set({ marks = { Mark = { text = {} } } }).marks.Mark.text, {})
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
    expect_invalid({ providers = { mini_diff = "yes" } }, "providers.mini_diff must be a boolean")
    expect_invalid({ providers = { search = "yes" } }, "providers.search must be a boolean or table")
    expect_invalid({ providers = { search = { incsearch = "yes" } } }, "providers.search.incsearch must be a boolean")
    expect_invalid(
        { providers = { search = { backend = "thread" } } },
        "providers.search.backend must be one of: sync, worker"
    )
    expect_invalid({ providers = { search = { extra = true } } }, "unknown option 'providers.search.extra'")
    expect_invalid({ providers = { marks = "yes" } }, "providers.marks must be a boolean or table")
    expect_invalid(
        { providers = { marks = { max_width = false } } },
        "providers.marks.max_width must be a positive integer"
    )
    expect_invalid(
        { providers = { marks = { max_width = 0 } } },
        "providers.marks.max_width must be a positive integer"
    )
    expect_invalid(
        { providers = { marks = { max_width = 1.5 } } },
        "providers.marks.max_width must be a positive integer"
    )
    expect_invalid(
        { providers = { marks = { max_width = math.huge } } },
        "providers.marks.max_width must be a positive integer"
    )
    expect_invalid(
        { providers = { marks = { max_width = "8" } } },
        "providers.marks.max_width must be a positive integer"
    )
    expect_invalid(
        { float = { width = 4 }, providers = { marks = { max_width = 3 } } },
        "providers.marks.max_width must be greater than or equal to float.width"
    )
    expect_invalid({ providers = { marks = { letters = "yes" } } }, "providers.marks.letters must be a boolean")
    expect_invalid({ providers = { marks = { numbers = 1 } } }, "providers.marks.numbers must be a boolean")
end

T["uses the exact MiniDiff mark defaults"] = function()
    local marks = set().marks

    expect.equality(marks.MiniDiffAdd, { text = { "▒" }, column = 1, priority = 7, highlight = "MiniDiffSignAdd" })
    expect.equality(
        marks.MiniDiffChange,
        { text = { "▒" }, column = 1, priority = 7, highlight = "MiniDiffSignChange" }
    )
    expect.equality(
        marks.MiniDiffDelete,
        { text = { "▒" }, column = 1, priority = 7, highlight = "MiniDiffSignDelete" }
    )
end

T["uses the exact gitsigns mark defaults"] = function()
    local marks = set().marks

    expect.equality(marks.GitAdd, { text = { "┃" }, column = 1, priority = 7, highlight = "GitSignsAdd" })
    expect.equality(marks.GitChange, { text = { "┃" }, column = 1, priority = 7, highlight = "GitSignsChange" })
    expect.equality(marks.GitDelete, { text = { "▁" }, column = 1, priority = 7, highlight = "GitSignsDelete" })
end

T["rejects malformed exclusion lists without changing active config"] = function()
    local before = set({ visibility = "active" })
    expect_invalid({ excluded_filetypes = { "lua", false } }, "excluded_filetypes%[2%] must be a string")
    expect.equality(require("scrollbar.config").get(), before)
end

return T
