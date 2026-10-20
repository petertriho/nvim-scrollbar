# Marks Provider

The marks provider is enabled by default. It emits the `Mark` type for
supported Vim named marks in each eligible loaded buffer.

![Scrollbar marks that show the letters of the named marks a to e](https://github.com/user-attachments/assets/3bb187a9-72fa-4d3e-8355-da319f4b7078)

## Collection Options

```lua
require("scrollbar").setup({
    providers = {
        marks = { letters = true, numbers = false },
    },
})
```

| Option | Default | Meaning |
| --- | --- | --- |
| `letters` | `true` | Include `a-z` and `A-Z` |
| `numbers` | `false` | Include `0-9` |

`true` uses these defaults. `false` disables the provider. The table also
accepts the `scrollbar` and `minimap` target flags. Setup rejects all other
keys under `providers.marks`, for example `width` and `max_width`. The width of
named marks is part of the layout: set `max_width` on the `Mark` lane, as the
next section shows.

The defaults for the `Mark` type in the top-level `marks` table are
`text = {}`, `priority = 1`, and `highlight = "Special"`. The empty text list
shows each literal name that the provider supplies. A non-empty list replaces
the names with the configured density glyphs:

```lua
require("scrollbar").setup({
    marks = {
        Mark = { text = { "·", "•", "#" }, priority = 1, highlight = "Special" },
    },
})
```

## Scope And Ordering

- Lowercase marks are buffer-local.
- Uppercase and numbered marks are global file marks. They show only on their
  eligible loaded target buffer.
- Numbered marks are opt-in and may come from ShaDa.
- Special marks such as `.`, `^`, `[`, `]`, `<`, and `>` are excluded.

The provider sorts names by source line, then by literal name. On the same
line, this order puts `0-9` first, then `A-Z`, then `a-z`.

## Collapsed And Expanded Rendering

If the `Mark` lane has no `max_width`, names use ordinary collapsed
composition. One deterministic representative owns each rendered cell.

To expand colliding built-in names, set a width on the lane:

```lua
require("scrollbar").setup({
    scrollbar = {
        layout = {
            columns = {
                { "track", "thumb", { types = { "Mark" }, max_width = 8 } },
                { "marks" },
            },
        },
    },
})
```

`max_width` is the total width of the selected lane, including declared cells.
The effective float can grow and shrink for each source window. It never grows
beyond the lane cap or the active placement container. Dynamic cells hold only
marks. They grow inward, while declared track, thumb, and ordinary mark cells
stay pinned.

The lane shows the first of the sorted names, from left to right. It omits the
remaining names that do not fit. Each visible name owns its exact source line.
Expansion applies only to `Mark` values that the built-in provider named
`marks` emits. Custom `Mark` sources stay collapsed.

## Mouse

A click on a visible name jumps to its exact line and opens the fold that
contains it. The click also centers that line in the source window and
restores focus.

A name in a layer above the thumb has two behaviors. A release without movement
clicks the name. Movement starts a thumb drag.

## Updates

The provider refreshes during setup, on buffer entry, on buffer display, on
text changes, and when marks change. `:ScrollbarRefresh` always does an
explicit refresh.

## Troubleshooting

- To inspect the source data, use `:marks`.
- If a category is missing, examine the `letters` or `numbers` option for that
  category.
- To restore literal names, set `marks.Mark.text = {}`.
- If expansion does not occur, make sure that these conditions are true:
  - The `Mark` lane cap is larger than its base span.
  - The container has room.
  - Multiple names map to one rendered row.

## Related

- [Provider index](README.md)
- [Layout and geometry](../layout-and-geometry.md)
- [Mouse](../mouse.md)
