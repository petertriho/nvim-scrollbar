# Cursor Provider

The cursor provider is enabled by default. It publishes one mark for the cursor
position of each eligible source window.

## Setup And Defaults

`providers.cursor` is a boolean, or a table that contains only the `scrollbar`
and `minimap` target flags. The provider has no other options.

```lua
require("scrollbar").setup({
    providers = {
        cursor = true,
    },
})
```

The provider emits the `Cursor` mark type. The defaults of this type are:

| Option | Default |
| --- | --- |
| `marks.Cursor.text` | `{ "•" }` |
| `marks.Cursor.priority` | `0` |
| `marks.Cursor.highlight` | `"Normal"` |

Lower numeric priorities win overlaps. As a result, the default cursor mark has
precedence over every other built-in mark type in the same display cells.

## Scope

The provider is window-scoped. If two splits show the same buffer, each split
keeps a separate cursor mark at its own cursor position. Invalid windows
produce no cursor mark. Buffers that `max_lines` or the top-level `exclude`
table excludes also produce no cursor mark.

## Updates

The provider initializes the mark during setup and when you enter a source
window. It updates the mark for the current event window on these events:

- `CursorMoved`
- `CursorMovedI`
- `BufWinEnter`
- `WinEnter`

`:ScrollbarRefresh` explicitly refreshes every eligible source window. If you
disable the provider or run setup again, scrollbar clears the cursor marks that
the previous provider instance owns.

## Customization

Customize the `Cursor` mark type in the top-level `marks` registry:

```lua
require("scrollbar").setup({
    marks = {
        Cursor = {
            text = "●",
            priority = 0,
            highlight = "CursorLineNr",
        },
    },
})
```

For a separate cursor lane, select `Cursor` explicitly in `layout.columns`. See
[Layout and geometry](../layout-and-geometry.md).

In the minimap, the provider draws the cursor-cell accent with the
`ScrollbarMinimapCursor` group instead of a `Cursor` mark. `minimap.marks`
rejects `Cursor`. To turn off the accent, set
`providers.cursor = { minimap = false }`.

## Limitations And Troubleshooting

- This provider represents only the ordinary Neovim cursor. It does not expose
  selections, remote cursors, or plugin-specific multi-cursor positions.
- With `scrollbar.hide_on_cursor = true`, the entire scrollbar can hide when the
  active editing cursor intersects the actual screen rectangle of the
  scrollbar. This behavior is part of the overlay visibility. It does not mean
  that the cursor mark is missing. If you prefer an uninterrupted overlay, set
  the option to `false`.
- If no mark appears, do these steps:
  1. Make sure that `providers.cursor` targets the scrollbar.
  2. Examine the top-level `exclude` table and `max_lines`.
  3. Enter the affected window.
  4. Run `:ScrollbarRefresh`.
- If another mark covers the cursor mark after customization, compare the lane
  stack order and the priorities. Lower priority numbers win within one mark
  lane.

## Related

- [Provider index](README.md)
- [Marks and mark rendering](marks.md)
- [Configuration](../configuration.md)
