# Cursor Provider

The cursor provider is enabled by default. It publishes one mark for the cursor
position of each eligible source window.

## Setup And Defaults

`providers.cursor` is a boolean. Setup rejects provider-specific table options.

```lua
require("scrollbar").setup({
    scrollbar = {
        providers = {
            cursor = true,
        },
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
keeps a separate cursor mark at its own cursor position. Invalid windows and
buffers excluded by `max_lines`, `excluded_buftypes`, or `excluded_filetypes`
produce no cursor mark.

## Updates

The provider initializes the mark during setup and when a source window is
entered. It updates the mark for the current event window on these events:

- `CursorMoved`
- `CursorMovedI`
- `BufWinEnter`
- `WinEnter`

`:ScrollbarRefresh` explicitly refreshes every eligible source window. If you
disable the provider or run setup again, the cursor marks that the previous
provider instance owns are cleared.

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

For a separate cursor lane, select `Cursor` explicitly in `layout.columns`. See
[Layout and geometry](../layout-and-geometry.md).

## Limitations And Troubleshooting

- This provider represents only the ordinary Neovim cursor. It does not expose
  selections, remote cursors, or plugin-specific multi-cursor positions.
- With `float.hide_on_cursor = true`, the entire scrollbar can hide when the
  active editing cursor intersects the actual screen rectangle of the
  scrollbar. This is overlay visibility behavior, not a missing cursor mark. If
  you prefer an uninterrupted overlay, set the option to `false`.
- If no mark appears, do these steps:
  1. Make sure that `providers.cursor = true`.
  2. Examine the buffer exclusion options and `max_lines`.
  3. Enter the affected window.
  4. Run `:ScrollbarRefresh`.
- If the mark is covered after customization, compare the lane stack order and
  the priorities. Lower priority numbers win within one mark lane.

## Related

- [Provider index](README.md)
- [Marks and mark rendering](marks.md)
- [Configuration](../configuration.md)
