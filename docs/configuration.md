# Configuration

`require("scrollbar").setup()` strictly validates the plugin's option schema,
including unknown keys, scalar types, enums, and dimensions. Direct highlight
definitions are accepted structurally as tables; Neovim validates their fields
when generated highlights are applied. With `set_highlights = false`, those
tables are not applied.

## Defaults

```lua
require("scrollbar").setup({
    show = true,
    visibility = "all", -- "all" or "active"
    set_highlights = true,
    max_lines = false, -- false or a positive line limit
    hide_if_all_visible = false,
    autohide = {
        enabled = false,
        delay_ms = 1000,
    },
    render = {
        interval_ms = 16,
        geometry = "line", -- "line" or "screen"
    },
    float = {
        width = 1,
        zindex = 50,
        hide_on_cursor = true,
        placement = {
            relative = "window", -- "window" or "editor"
            anchor = "NE", -- "NW", "NE", "SW", or "SE"
            row = 0,
            col = 0,
        },
    },
    track = {
        highlight = "PmenuSbar",
    },
    mouse = {
        enabled = true,
    },
    handle = {
        text = " ",
        column = 1,
        width = 1,
        blend = 30,
        highlight = "PmenuThumb",
        hide_if_all_visible = true,
    },
    marks = {
        Cursor = {
            text = { "•" },
            column = 1,
            priority = 0,
            highlight = "Normal",
        },
        Mark = {
            text = {},
            column = 1,
            priority = 1,
            highlight = "Special",
        },
        Search = {
            text = { "-", "=" },
            column = 1,
            priority = 1,
            highlight = "Search",
        },
        Error = {
            text = { "-", "=" },
            column = 1,
            priority = 2,
            highlight = "DiagnosticVirtualTextError",
        },
        Warn = {
            text = { "-", "=" },
            column = 1,
            priority = 3,
            highlight = "DiagnosticVirtualTextWarn",
        },
        Info = {
            text = { "-", "=" },
            column = 1,
            priority = 4,
            highlight = "DiagnosticVirtualTextInfo",
        },
        Hint = {
            text = { "-", "=" },
            column = 1,
            priority = 5,
            highlight = "DiagnosticVirtualTextHint",
        },
        Misc = {
            text = { "-", "=" },
            column = 1,
            priority = 6,
            highlight = "Normal",
        },
        GitAdd = {
            text = { "┃" },
            column = 1,
            priority = 7,
            highlight = "GitSignsAdd",
        },
        GitChange = {
            text = { "┃" },
            column = 1,
            priority = 7,
            highlight = "GitSignsChange",
        },
        GitDelete = {
            text = { "▁" },
            column = 1,
            priority = 7,
            highlight = "GitSignsDelete",
        },
        MiniDiffAdd = {
            text = { "▒" },
            column = 1,
            priority = 7,
            highlight = "MiniDiffSignAdd",
        },
        MiniDiffChange = {
            text = { "▒" },
            column = 1,
            priority = 7,
            highlight = "MiniDiffSignChange",
        },
        MiniDiffDelete = {
            text = { "▒" },
            column = 1,
            priority = 7,
            highlight = "MiniDiffSignDelete",
        },
        SignifyAdd = {
            text = { "┃" },
            column = 1,
            priority = 7,
            highlight = "SignifySignAdd",
        },
        SignifyChange = {
            text = { "┃" },
            column = 1,
            priority = 7,
            highlight = "SignifySignChange",
        },
        SignifyDelete = {
            text = { "▁" },
            column = 1,
            priority = 7,
            highlight = "SignifySignDelete",
        },
    },
    providers = {
        cursor = true,
        diagnostic = true,
        search = true, -- true or { incsearch = nil | boolean, backend = "worker" | "sync" }
        marks = true, -- false, true, or { letters = boolean, numbers = boolean, max_width = integer }
        gitsigns = false,
        mini_diff = false,
        signify = false,
        ale = false,
        coc = false,
    },
    excluded_buftypes = {
        "terminal",
    },
    excluded_filetypes = {
        "blink-cmp-menu",
        "dropbar_menu",
        "dropbar_menu_fzf",
        "DressingInput",
        "cmp_docs",
        "cmp_menu",
        "noice",
        "prompt",
        "TelescopePrompt",
    },
})
```

Each call starts from these defaults and applies the supplied overrides. It does
not incrementally merge with the previous active setup.

The defaults above use accepted user-facing shorthand. Internally,
`search = true` normalizes to `{ backend = "worker" }`. The absent `incsearch`
key dynamically follows Neovim's current `vim.o.incsearch` value. `marks = true`
normalizes to
`{ letters = true, numbers = false, max_width = false }`.

## Validation

- The `providers` table accepts exactly nine built-in names. `cursor`,
  `diagnostic`, `gitsigns`, `mini_diff`, `signify`, `ale`, and `coc` are strict
  booleans.
- `visibility` accepts only `"all"` or `"active"`.
- `render.geometry` accepts only `"line"` or `"screen"`.
- `float.placement.relative` accepts only `"window"` or `"editor"`.
- `float.placement.anchor` accepts `"NW"`, `"NE"`, `"SW"`, or `"SE"`.
- `float.placement.row` and `float.placement.col` are signed integers.
- `max_lines` is `false` or a positive integer.
- `autohide.delay_ms` is a positive integer; zero is not accepted.
- Widths, columns, and `zindex` are positive integers. `render.interval_ms`,
  `handle.blend`, and mark priorities may be zero.
- `handle.blend` must be between `0` and `100`.
- `handle.column + handle.width - 1` must fit within `float.width`.
- Every mark column must fit within `float.width`.
- `handle.text` is one string with positive display width and no control
  characters. Mark text accepts a string or dense list of such strings; only
  `marks.Mark.text` may be empty.
- Mark type names must match `^[%a_][%w_]*$`.
- `providers.search` is a boolean or a table containing only `incsearch` and
  `backend`. When present, `incsearch` is a boolean; when omitted, it follows
  the current `vim.o.incsearch` value. `backend` accepts `"worker"` or `"sync"`.
- `providers.marks` is a boolean or a table containing only `letters`,
  `numbers`, and `max_width`. When present, `max_width` is a positive integer at
  least as large as `float.width`.
- Highlight values are a non-empty highlight group name or a table accepted by
  `nvim_set_hl()`.
- `excluded_buftypes` and `excluded_filetypes` must be dense lists of strings.

## Marks And Columns

`handle.column`, `handle.width`, and mark columns use one-based display-cell
coordinates. Mark text is clipped at the right edge without splitting a
multi-cell character.

Mark text lists are density variants. Marks compressed into the same rendered
row, type, and column use variant `min(mark_count, variant_count)`. For example,
`{ "·", "•", "#" }` displays `·` for one mark, `•` for two, and `#` for three
or more. A string is accepted as one variant.

Overlapping display-cell ranges are resolved by priority; lower numbers win.
Ties are deterministic. Multi-cell glyphs are atomic and are omitted rather
than split when an overlap would cut through them.

The empty default for `marks.Mark.text` is special: it allows the built-in
[marks provider](providers/marks.md) to display literal mark names.

See [Layout and geometry](layout-and-geometry.md) for wide scrollbar placement
and composition, and [Highlights](highlights.md) for generated group behavior.

## Eligibility

`max_lines` excludes buffers above the configured logical line count.
`excluded_buftypes` and `excluded_filetypes` exclude matching buffers from
rendering and manager-invoked provider refreshes. Custom provider-owned
callbacks remain responsible for their own collection decisions; marks they
publish remain non-rendered while a buffer is ineligible. Scrollbar-owned
scratch buffers are always excluded.

Visibility controls, autohide, and hide-if-all-visible behavior are documented
in [Visibility](visibility.md).

## Related

- [README](../README.md)
- [Providers](providers/README.md)
- [Layout and geometry](layout-and-geometry.md)
- [Highlights](highlights.md)
