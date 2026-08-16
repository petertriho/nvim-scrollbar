# Cursor Provider

The cursor provider is enabled by default and publishes one mark for the cursor
position of each eligible source window.

## Setup And Defaults

`providers.cursor` is a boolean; provider-specific table options are not
accepted.

```lua
require("scrollbar").setup({
    scrollbar = {
        providers = {
            cursor = true,
        },
    },
})
```

It emits the `Cursor` mark type, whose defaults are:

| Option | Default |
| --- | --- |
| `marks.Cursor.text` | `{ "•" }` |
| `marks.Cursor.priority` | `0` |
| `marks.Cursor.highlight` | `"Normal"` |

Lower numeric priorities win overlaps, so the default cursor mark takes
precedence over every other built-in mark type in the same display cells.

## Data And Scope

The source is `nvim_win_get_cursor()` for each normal source window. Lines are
converted to the provider API's zero-based line coordinates before rendering.

The provider is window-scoped. If two splits show the same buffer, each split
keeps a separate cursor mark at its own cursor position. Invalid windows and
buffers excluded by `max_lines`, `excluded_buftypes`, or `excluded_filetypes`
produce no cursor mark.

## Updates

The mark is initialized during setup and when a source window is entered. It is
updated for the current event window on:

- `CursorMoved`
- `CursorMovedI`
- `BufWinEnter`
- `WinEnter`

In wired top-level setups the cursor-move events ride the scheduler's shared
cursor-activity dispatch (one autocmd callback per move); the provider keeps
its own registration in standalone setups.

`:ScrollbarRefresh` refreshes every eligible source window explicitly. Disabling
the provider or re-running setup clears cursor marks owned by the previous
provider instance.

## Customization

Customize the shared `Cursor` mark type under `marks`:

```lua
require("scrollbar").setup({
    scrollbar = {
        marks = {
            Cursor = {
                text = "●",
                priority = 0,
                highlight = "CursorLineNr",
            },
        },
    },
})
```

For a separate cursor lane, explicitly select `Cursor` in `layout.columns`; see
[Layout and geometry](../layout-and-geometry.md).

## Limitations And Troubleshooting

- This provider represents the ordinary Neovim cursor only. It does not expose
  selections, remote cursors, or plugin-specific multi-cursor positions.
- `float.hide_on_cursor = true` can hide the entire scrollbar when the active
  editing cursor intersects its actual screen rectangle. This is overlay
  visibility behavior, not a missing cursor mark; set it to `false` if an
  uninterrupted overlay is preferred.
- If no mark appears, confirm `providers.cursor = true`, check buffer exclusion
  and `max_lines` settings, and run `:ScrollbarRefresh` after entering the
  affected window.
- If the mark is covered after customization, compare lane stack order and
  priority. Lower priority numbers win within one mark lane.

## Related

- [Provider index](README.md)
- [Marks and mark rendering](marks.md)
- [Configuration](../configuration.md)
