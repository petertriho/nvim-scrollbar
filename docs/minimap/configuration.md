# Minimap Configuration

You configure the minimap in the `minimap` block of
`require("scrollbar").setup()`. The minimap uses the shared `set_highlights`,
`exclude`, `providers`, and `marks` sections, which
[Configuration](../configuration.md) documents. For an overview of the
minimap, see [Minimap](README.md).

The minimap defaults to `enabled = false`. If you omit the block, the scrollbar
behavior does not change.

## Defaults

```lua
require("scrollbar").setup({
    minimap = {
        -- Global options
        enabled = false,
        show = true,
        visibility = "all", -- "all" or "active"
        autohide = false, -- true, or { delay_ms = 1000 }
        max_lines = false,
        throttle_ms = 50,
        events = { -- see Events
            "BufEnter", "BufWinEnter", "WinEnter",
            "CursorMoved", "CursorMovedI",
            "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT",
            "WinScrolled", "WinResized", "VimResized",
            "ColorScheme",
            "WinClosed", "BufDelete", "BufWipeout",
        },
        backend = "worker", -- "worker" or "sync"
        background_blend = false,

        -- Appearance options
        preset = nil, -- a built-in minimap preset name
        width = 16,
        height = false,
        scale = "fixed", -- "fixed", "fit", or lines per dot row
        encoding = "braille", -- "braille" or "block"
        columns_per_dot = 4,
        placement = {
            relative = "window", -- "window" or "editor"
            anchor = "NE", -- "NW", "NE", "SW", or "SE"
            row = 0,
            col = 0,
            zindex = 50,
            stack = "inner", -- "inner", "outer", "above", or "below"
        },
        blend = 0,
        hide_on_cursor = true,
        mouse = true,
        viewport = true,
        marks = {}, -- overrides of the shared mark types

        profiles = nil,
    },
})
```

## Global Options

You set global options only at the root of the `minimap` block.

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `false` | Main toggle. When `false`, the minimap requests no providers, shows no floats, and creates no `:Minimap*` commands. |
| `show` | `true` | Initial visibility. `false` starts hidden. `:MinimapShow` shows it. |
| `visibility` | `"all"` | Uses the same rules as the scrollbar. See [Visibility](../visibility.md). |
| `autohide` | `false` | `true` hides each minimap after 1000 ms without cursor or scroll activity in its window. `{ delay_ms = n }` sets the delay. |
| `max_lines` | `false` | A buffer with more lines than this number gets no minimap. |
| `throttle_ms` | `50` | Renders that are queued within this interval combine into one frame. `0` renders as fast as possible. |
| `events` | see Defaults | Autocommand events that update the minimap. See [Events](#events). |
| `backend` | `"worker"` | Where Treesitter collection and the squash of the source lines run. See [Backends](#backends). |
| `background_blend` | `false` | Blend of the base surface. See [Blend](#blend). |

## Appearance Options

You set appearance options at the root of the `minimap` block or in a
[profile](#profiles).

| Option | Default | Meaning |
| --- | --- | --- |
| `preset` | `nil` | A built-in minimap preset. The options next to it win. See [Minimap presets](../presets.md#minimap-presets). |
| `width` | `16` | Width of the minimap grid in cells. A positive integer. |
| `height` | `false` | Height of the minimap grid. `false` uses the height of the source window. |
| `scale` | `"fixed"` | `"fixed"` gives each dot row one source line and scrolls the map with the source window. A positive integer gives each dot row that number of lines and also scrolls. `"fit"` shrinks the whole buffer into the float. See [The Map](README.md#the-map). |
| `encoding` | `"braille"` | `"braille"` draws the 2 x 4 dots of each cell as a Braille character. `"block"` draws `█` for each cell that has a dot. |
| `columns_per_dot` | `4` | Source display columns in each dot column. A cell covers twice this number. Columns past the minimap are clipped. A positive integer. |
| `placement.relative` | `"window"` | Reference for the float position. `"editor"` renders only the minimap of the active source window. |
| `placement.anchor` | `"NE"` | Corner used as the origin of `row` and `col`. |
| `placement.row` | `0` | Row offset from the anchor. |
| `placement.col` | `0` | Column offset from the anchor. |
| `placement.zindex` | `50` | `nvim_open_win()` z-index. |
| `placement.stack` | `"inner"` | Arrangement with a scrollbar on the same side. See [Placement Beside the Scrollbar](#placement-beside-the-scrollbar). |
| `blend` | `0` | Pseudo-transparency of the full float, `0` to `100`. |
| `hide_on_cursor` | `true` | Hides the minimap of the active source window while the cursor is inside it. See [Cursor Yielding](#cursor-yielding). |
| `mouse` | `true` | Adds the `<LeftMouse>`, `<LeftDrag>`, and `<LeftRelease>` mappings. |
| `viewport` | `true` | Tints the background of the rows that show the visible lines of the source window. |
| `marks` | `{}` | Overrides of the shared mark types for the minimap. See [Marks](#marks). |

## Events

`minimap.events` uses the same format and the same rules as
[`scrollbar.events`](../configuration.md#events). The minimap defaults do not
contain `TabEnter`, `TermEnter`, `CmdwinLeave`, `OptionSet`, and `TabClosed`.
To add an event, set it to `true`:

```lua
minimap = {
    events = { TabEnter = true },
}
```

In the minimap, `OptionSet` without a `pattern` renders all windows when any
option changes.

With `autohide`, only `CursorMoved`, `CursorMovedI`, and `WinScrolled` show a
hidden minimap again.

## Placement Beside the Scrollbar

`placement.stack` sets how the minimap and the scrollbar share one side of a
source window:

| Value | Arrangement |
| --- | --- |
| `"inner"` | Side by side. The scrollbar is at the window edge. The minimap is beside it, nearer the text. |
| `"outer"` | Side by side. The minimap is at the window edge. The scrollbar is beside it, nearer the text. |
| `"above"` | The floats overlap. The minimap is on top. |
| `"below"` | The floats overlap. The scrollbar is on top. |

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        placement = { stack = "outer" },
    },
})
```

The floats share a side when both use the same `placement.relative` and both
anchors are east (`NE`, `SE`) or both are west (`NW`, `SW`). The vertical half
of the anchor does not matter. In all other cases, each float uses only its own
placement. For example, a window-relative minimap and an editor-relative
scrollbar can overlap in the rightmost window.

### Side by Side

- The float at the window edge uses its own `placement.col`, as usual.
- The other float starts at the inward edge of the float at the window edge.
  Its own `placement.col` applies from that edge. On the east side, a negative
  `col` leaves a gap between the floats. On the west side, a positive `col`
  leaves a gap.
- When the scrollbar is at the window edge and its width changes, for example
  when named marks collide, the minimap moves at once.
- When the scrollbar is nearer the text, its named marks can grow only up to
  the far edge of the window.

A float that hides for a short time keeps its place, so the other float does
not move:

- `hide_on_cursor` hides a float while the cursor is inside it.
- `autohide` hides a float after a period without activity.

When the float at the window edge hides for a lasting reason, the other float
moves to the window edge. The lasting reasons are:

- `:ScrollbarHide` or `:MinimapHide`.
- A disabled renderer.
- An excluded buffer, or a buffer with more lines than `max_lines`.
- `hide_if_all_visible` on the scrollbar.
- An inactive window under `visibility = "active"` or with an editor-relative
  placement.

On the west side, the scrollbar can reserve gutter cells with
`scrollbar.placement.gutter`. The reservation does not change. With `"inner"`,
the minimap starts after the reserved scrollbar cells, so the line numbers stay
visible. With `"outer"`, the scrollbar moves beside the minimap, and its
reserved cells stay blank. For that combination, set
`scrollbar.placement.gutter = "overlap"`.

A window that is narrower than both floats gets no special handling. Neovim
keeps each float inside the editor, so the floats can overlap in a very narrow
window.

### Overlap

`"above"` and `"below"` set the order only when both `placement.zindex` values
are equal. In that case, the bottom float uses `zindex - 1`. If both values are
`1`, the top float uses `2` instead. Different `zindex` values always win.

## Providers

The shared `providers` table controls the minimap data sources. A provider
that targets the minimap runs once, also when the scrollbar uses it. A disabled
minimap requests no providers.

```lua
require("scrollbar").setup({
    providers = {
        lsp_semantic_tokens = true,     -- colors from the language server
        coc = { scrollbar = false },    -- minimap only
        diagnostic = { minimap = false }, -- scrollbar only
    },
    minimap = { enabled = true },
})
```

| Provider | Minimap output |
| --- | --- |
| `cursor` | The cursor-cell accent. |
| `diagnostic`, `ale`, `coc` | Diagnostic marks. |
| `search` | Search marks. |
| `marks` | Native mark positions. |
| `gitsigns`, `mini_diff`, `signify`, `vgit` | Git marks. |
| `treesitter` | Syntax colors from Treesitter. On by default. Minimap only. |
| `lsp_semantic_tokens` | Syntax colors from LSP semantic tokens. Minimap only. |

To turn off the cursor accent, set `providers.cursor = { minimap = false }`.
To turn off the syntax colors, set `providers.treesitter = false`.
See [Configuration](../configuration.md#providers) for the rules, and the
[Treesitter](../providers/treesitter.md) and
[LSP semantic-token](../providers/lsp_semantic_tokens.md) guides.

## Marks

The minimap shows the shared mark types from the top-level `marks` table as
overlays. It uses their `priority` and `highlight`. It does not use `text`.

`minimap.marks` overrides the shared types for the minimap only:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        marks = {
            Search = { priority = 0, highlight = "IncSearch" },
            Hint = false,
        },
    },
})
```

- A table merges with the shared definition. It accepts only `priority` and
  `highlight`.
- `false` hides one type. `marks = false` hides all overlays.
- An override can name only a registered type. To add a type, add it to the
  top-level `marks` table. To show a new type only in the minimap, also set
  `scrollbar.marks.<Type> = false`.
- `Cursor` is not an overlay type. The minimap draws the cursor with the
  `ScrollbarMinimapCursor` group. `marks.Cursor` is a setup error.

When several marks project onto one row, the lowest `priority` wins.

## Blend

`blend` and `background_blend` control different layers:

- `blend` is the pseudo-transparency of the full float. Profiles can change
  it.
- `background_blend = false` uses `blend` for the base surface. A number from
  `0` to `100` changes only the base surface that comes from
  `ScrollbarMinimapBase`. It works even when `blend = 0`. As a result, the base
  can blend while the viewport, cursor, overlay, and syntax backgrounds stay
  solid. It is a global option.
- An explicit `blend` in a source highlight is kept. Groups that have only a
  foreground keep their dots above the base surface.

The plugin never rewrites the public `ScrollbarMinimap*` groups.

Neovim implements `winblend` and highlight `blend` as UI pseudo-transparency,
not as per-pixel alpha. The result depends on the active colorscheme and UI.

## Cursor Yielding

With `hide_on_cursor = true`, the minimap of the active source window hides
while the editing cursor is inside its screen rectangle. The minimap shows
again when the cursor leaves. Stored cursor positions in inactive splits do not
hide their minimaps. This option is independent of the `cursor` provider. For
more information, see [Visibility](../visibility.md).

## Backends

- `"worker"` (default) runs Treesitter collection and the squash in one
  embedded headless child Neovim process.
- `"sync"` runs them in the main Neovim process. It starts no child process.

The backend squashes only a slice of the map: the rows in the float and one
float height of rows above and below. Treesitter captures only the lines of
the slice. Scrolling inside the slice uses the cached rows. When less than half
a float height of rows is left on a side that is not an end of the buffer, the
minimap requests a new slice. Until the new slice arrives, the rows outside the
cached slice are blank. With `scale = "fit"`, the slice is the whole buffer.

Treesitter collection runs only when the `treesitter` provider targets the
minimap. If the worker fails, the minimap switches to the sync backend. A later
`setup()` may try to start a new worker. LSP semantic-token requests always run
in the main process, for both backends. `backend` does not change the
`search` provider backend, which is `providers.search.backend`.

## Profiles

Minimap profiles work like [scrollbar profiles](../configuration.md#profiles).
They match on `filetypes`, `buftypes`, and `when`, and the first match wins.
Each profile has a required `match` and any appearance options:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        profiles = {
            {
                match = { filetypes = { "lua" } },
                width = 60,
                marks = { Hint = false },
            },
        },
    },
})
```

A global option in a profile is a setup error. A profile can select a minimap
preset with `preset`. Scrollbar and minimap profiles are independent. They are
not paired by declaration index.

Later layers win:

1. The plugin defaults.
2. The root `preset`.
3. The root options.
4. The profile `preset`.
5. The profile options.

Mark overrides apply on top of the shared `marks` definitions.
If a `when` predicate raises an error, that render uses the root options. A
notification appears once for each distinct pair of profile and error message.

## Highlights

When `set_highlights = true`, the minimap defines these static public groups
with theme-owned default links:

| Group | Default link | Role |
| --- | --- | --- |
| `ScrollbarMinimapBase` | `Normal` | Base float surface. It matches the editor background. |
| `ScrollbarMinimapContent` | `Comment` | Monochrome highlight for occupied cells without a syntax capture. |
| `ScrollbarMinimapViewport` | `Visual` | Background of the viewport band. |
| `ScrollbarMinimapCursor` | `Cursor` | Exact projected cursor-cell accent. |

Each shown mark type also gets a public `ScrollbarMinimap<Type>` group, such as
`ScrollbarMinimapError`, `ScrollbarMinimapSearch`, or
`ScrollbarMinimapGitAdd`. A string source contributes its resolved foreground.
A direct table is copied. A public definition that already exists is not
overwritten. In automatic mode, each profile gets its own internal groups, so
that profiles that show at the same time can use different definitions.

With `set_highlights = false`, setup and `ColorScheme` write no minimap groups.
Every profile renders through the canonical `ScrollbarMinimap<Type>` names. In
this manual mode, define those names yourself. A colorscheme may clear user
groups. If it does, reapply them from your own `ColorScheme` callback:

```lua
local function set_minimap_highlights()
    vim.api.nvim_set_hl(0, "ScrollbarMinimapBase", { bg = "#161821" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapContent", { fg = "#657080" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapViewport", { bg = "#252a38" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapCursor", { fg = "#ffffff", bg = "#7aa2f7" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapSearch", { fg = "#ff9e64" })
end

set_minimap_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_minimap_highlights })
```

## Validation

The minimap uses the same strict validation as the scrollbar. Unknown keys,
invalid values, and global options in profiles fail setup with an error that
starts with `[nvim-scrollbar]` and gives the full option path.

- `width`, `placement.zindex`, `autohide.delay_ms`, a numeric `height`, and a
  numeric `max_lines`: positive integers.
- `blend` and a numeric `background_blend`: integers from `0` to `100`.
- `throttle_ms`: a non-negative integer.
- `events`: a list or a table keyed by autocommand event name. See
  [Events](../configuration.md#events).
- `placement.row` and `placement.col`: signed integers.
- `columns_per_dot`: a positive integer.
- `scale`: `"fixed"`, `"fit"`, or a positive integer. `encoding`: `"braille"`
  or `"block"`.
- `preset`: the name of a built-in minimap preset. An unknown name lists the
  built-in names.
- `glyph` is removed. Use `encoding`. The block encoding always draws `█`.
- `Base`, `Content`, `Viewport`, and `Cursor` are not valid minimap mark
  types, because their `ScrollbarMinimap<Name>` groups belong to the static
  layers. The minimap does not show a shared type with one of these names.

When the minimap is enabled, setup also rejects a scrollbar and minimap type
pair that claims the same public highlight group, such as a scrollbar type
`MinimapSearch` and the minimap type `Search`. The same ownership check rejects
scrollbar names such as `Track`, `Handle`, or `SearchThumb` when they collide
with fixed, overlap, pressed, or legacy groups.

## Related

- [Minimap](README.md)
- [Presets](../presets.md)
- [Configuration](../configuration.md)
- [Treesitter provider](../providers/treesitter.md)
- [LSP semantic tokens](../providers/lsp_semantic_tokens.md)
- [Migration](../migration.md)
