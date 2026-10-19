# Marks Provider

The marks provider is enabled by default. It emits the `Mark` type for
supported Vim named marks in each eligible loaded buffer.

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
accepts the `scrollbar` and `minimap` target flags. Width is a layout policy,
and setup rejects it under `providers.marks`.

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

Visible names keep their ordered prefix from left to right. Excess tail names
are omitted. Each visible name owns its exact source line. Expansion applies
only to `Mark` values emitted by the built-in provider named `marks`. Custom
`Mark` sources stay collapsed.

## Mouse

A click on a visible name jumps to its exact line and opens the fold that
contains it. The click also centers the source and restores focus.

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
