# Marks Provider

The default-on marks provider emits the `Mark` type for supported Vim named
marks in each eligible loaded buffer.

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

`true` uses these defaults; `false` disables the provider. Width is a layout
policy and is not accepted under `providers.marks`.

The `Mark` presentation defaults to `text = {}`, `priority = 1`, and
`highlight = "Special"`. The empty text list displays each provider-supplied
literal name. A non-empty list replaces names with configured density glyphs:

```lua
marks = {
    Mark = { text = { "·", "•", "#" }, priority = 1, highlight = "Special" },
}
```

## Scope And Ordering

- Lowercase marks are buffer-local.
- Uppercase and numbered marks are global file marks shown only on their
  eligible loaded target buffer.
- Numbered marks are opt-in and may come from ShaDa.
- Special marks such as `.`, `^`, `[`, `]`, `<`, and `>` are excluded.

Names are ordered by source line and then literal name. On the same line this
places `0-9`, then `A-Z`, then `a-z`.

## Collapsed And Expanded Rendering

Without a `Mark` lane `max_width`, names use ordinary collapsed composition and
one deterministic representative owns each rendered cell.

To expand colliding built-in names, put width on the lane:

```lua
require("scrollbar").setup({
    layout = {
        columns = {
            { "track", "thumb", { kind = "marks", types = { "Mark" }, max_width = 8 } },
            { "marks" },
        },
    },
})
```

`max_width` is the total width of the selected lane, including declared cells.
The effective float can grow and shrink per source window, but never beyond the
lane cap or active placement container. Dynamic cells are marks-only and grow
inward while declared track, thumb, and ordinary mark cells stay pinned.

Visible names keep their ordered prefix from left to right; excess tail names
are omitted. Each visible name owns its exact source line. Expansion applies
only to `Mark` values emitted by the built-in provider named `marks`; custom
`Mark` sources remain collapsed.

## Mouse

Clicking a visible name jumps to its exact line, opens its containing fold,
centers the source, and restores focus. A name above the thumb clicks on release
without movement and starts a thumb drag after movement.

## Updates

The provider refreshes during setup, buffer entry, buffer display, and text
changes. Neovim 0.11 through 0.12.1 uses `SafeState` reconciliation because
mark-change events are incomplete. Neovim 0.12.2 and newer uses `MarkSet` for
the default letter-only path. Numbered marks retain `SafeState` reconciliation.
`:ScrollbarRefresh` always performs an explicit refresh.

## Troubleshooting

- Use `:marks` to inspect source data.
- Verify `letters` or `numbers` when a category is missing.
- Use `marks.Mark.text = {}` to restore literal names.
- If expansion does not occur, verify the `Mark` lane cap exceeds its base span,
  the container has room, and multiple names map to one rendered row.

## Related

- [Provider index](README.md)
- [Layout and geometry](../layout-and-geometry.md)
- [Mouse](../mouse.md)
