# Layout And Geometry

The renderer derives float width, physical columns, thumb geometry, mark
routing, stack order, and mouse ownership from `layout`.

## Logical Columns

Each entry in `layout.columns` is one logical display column. Layers inside a
column are ordered bottom-to-top:

```lua
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb", "marks" },
    },
}
```

Track paints background only. Thumb paints its repeated text and background
while the viewport span is active. Mark layers paint resolved glyphs. A later
track can replace the background without replacing a lower content glyph.
Marks above the thumb remain visible; marks below it are hidden by the thumb.

Plain `"marks"` receives every type not claimed by an explicit descriptor:

```lua
layout = {
    columns = {
        { "track", "thumb" },
        {
            { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } },
            "marks",
        },
    },
}
```

Repeat the same layer in adjacent columns to create a span. The thumb and each
mark lane must be contiguous. Track may be repeated anywhere. Components are
optional, so mark-only and thumb-only rulers are valid. Blank cells without a
declared track, active thumb, or visible mark use the transparent float base.

## Direction

- `auto`: declarations are inner-to-outer. East anchors render left-to-right;
  west anchors mirror them.
- `ltr`: declarations always render in physical left-to-right order.
- `rtl`: declarations always render in physical right-to-left order.

Direction moves columns, not glyph internals. Multi-cell strings retain normal
left-to-right character order.

## Named-Mark Lanes

Only a descriptor explicitly selecting `Mark` may set `max_width`:

```lua
layout = {
    columns = {
        { "track", "thumb" },
        { { kind = "marks", types = { "Mark" }, max_width = 8 } },
        { "marks" },
    },
}
```

When built-in named marks collide on a row, their lane grows only as needed.
`max_width` caps that lane's total width, including its declared base span; it
does not cap the whole float. Growth is limited by the active placement
container. Dynamic cells contain named marks only and are inserted on the
editor-facing inward side. Declared track, thumb, and ordinary mark screen cells
remain pinned as the float grows or shrinks.

Built-in names retain source-line/name order. If capacity is insufficient, the
ordered prefix remains and the tail is omitted. Custom providers emitting
`type = "Mark"` stay collapsed in the declared base lane.

## Placement

`float.placement.relative = "window"` creates one float per eligible source
window. `"editor"` uses editor coordinates and renders only the active source
window. `anchor` selects `NW`, `NE`, `SW`, or `SE`; signed `row` and `col`
offsets are applied literally.

The float covers source buffer-text rows, excluding the source winbar and bounds
already reserved for tabline, statusline, and command-line chrome. The renderer
owns derived width and height. Public float controls are `zindex`,
`hide_on_cursor`, and `placement`.

## Geometry Modes

`render.geometry = "line"` maps logical lines directly and preserves a static
mark-layer cache. Scrolling recomputes viewport/thumb geometry without
rebuilding mark placement. Mark revisions, dimensions, container width, mark
text/priority, and normalized layout inputs invalidate that cache; visual-only
highlight and unrelated runtime options do not.

`render.geometry = "screen"` uses `nvim_win_text_height()` so wrapping, folds,
diff filler, virtual lines, `topfill`, and wrapped offsets affect both marks and
thumb geometry. It is more accurate and intentionally more expensive.

`render.interval_ms` coalesces repeated invalidations into the latest frame.

## Examples

One-column default:

```lua
layout = { columns = { { "track", "thumb", "marks" } } }
```

Wide typed ruler:

```lua
layout = {
    columns = {
        { "track", { kind = "marks", types = { "GitAdd", "GitChange", "GitDelete" } } },
        { "track", "thumb" },
        { { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } }, "marks" },
    },
}
```

Expanded named marks:

```lua
layout = {
    columns = {
        { "track", "thumb", { kind = "marks", types = { "Mark" }, max_width = 8 } },
        { "marks" },
    },
}
```

Terminal cells, font width, and colorscheme highlights limit visual fidelity;
presets and examples are structural contracts rather than pixel-perfect GUI
reproductions.

## Related

- [Configuration](configuration.md)
- [Presets](presets.md)
- [Marks provider](providers/marks.md)
- [Mouse](mouse.md)
