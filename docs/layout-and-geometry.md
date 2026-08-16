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
offsets are applied literally. `gutter` selects `"avoid"` (the default) or
`"overlap"`. `gutter_position` selects `"inner"` (the default, beside buffer
text) or `"outer"` (at the source-window edge) within an avoided west gutter.

Gutter placement applies as follows:

| Relative mode | Anchor | `gutter = "avoid"` behavior | `gutter = "overlap"` origin |
| --- | --- | --- | --- |
| `"window"` | `NW` or `SW` | Reserve blank gutter cells and place the float inside them | Source window edge |
| `"window"` | `NE` or `SE` | Existing east edge | Existing east edge |
| `"editor"` | Any | Existing editor coordinate | Existing editor coordinate |

For a window-relative west anchor, let `G` be the source's gutter width before
the scrollbar reservation, `W` the rendered float width, and `C` the configured
`col`. In `avoid` mode the renderer reserves `max(0, W + C)` blank cells. With
`gutter_position = "inner"`, the reservation follows the existing gutter and
the float starts at `G + C`, beside the shifted buffer-text edge. With
`gutter_position = "outer"`, the reservation precedes the existing gutter and
the float starts at `C`, beside the source-window edge. A positive offset leaves
a gap before the float within its reservation. A negative offset remains
literal and may deliberately extend outside or overlap adjacent gutter cells.

The reservation temporarily wraps the window-local `statuscolumn` and expands
its available width. Existing fold, sign, number, custom-format, and `%!`
content remains intact before an `"inner"` reservation or after an `"outer"`
reservation. The original `statuscolumn` and `numberwidth` are restored when the
scrollbar is hidden, disposed, becomes ineligible, or switches to an unaffected
placement. An external edit made while the reservation is active is preserved
instead of overwritten. Each split owns and restores its reservation
independently, including splits created from an already reserved window.

Neovim limits the maximum statuscolumn width. If a declared west layout is too
wide to reserve completely, the renderer omits that scrollbar instead of
partially reserving it and covering buffer text. Dynamic named-mark growth is
constrained to the reservation capacity when the declared base layout fits.

The renderer measures the live gutter on every normal render. Covered option
changes, including `number`, `relativenumber`, `numberwidth`, `foldcolumn`,
`signcolumn`, and `statuscolumn`, queue that path. Unrelated automatic sign
changes are reconciled on the next normal render rather than through polling or
immediate sign-API interception.

Contextual profiles resolve placement per source window. With root
`visibility = "all"`, compatible window-relative variants can coexist while an
editor-relative variant is shown only when its source is active. Root
`visibility = "active"` always limits the entire renderer to the active source.
Changing a match result updates the existing float's relative mode, anchor,
offsets, width, z-index, cursor-hiding policy, and mouse flags without retaining
stale rows or hit cells.

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

Each compiled profile carries normalized cache inputs. A runtime profile switch
rebuilds only that source window's static layer when layout, geometry mode, mark
text, priority, routing, direction, anchor-derived order, or named-mark expansion
limits change. Structurally equivalent and highlight-only variants reuse the
layer through explicit input equality; predicate evaluation does not clear mark
snapshots or another window's cache.

`render.geometry = "screen"` uses `nvim_win_text_height()` so wrapping, folds,
diff filler, virtual lines, `topfill`, and wrapped offsets affect both marks and
thumb geometry.

Screen geometry keeps a per-window extent cache so this accuracy stays cheap
in steady state:

- Windows whose every line renders to one display row (no wraps, no closed
  folds — verified) use arithmetic extents: scrolling and option changes render
  without measuring, and text edits verify only the edited lines.
- Other windows maintain a chunk table of display heights. Recorded text edits
  re-measure just the chunks they overlap, and each render re-validates a few
  chunks round-robin instead of rescanning the whole buffer. Fold commands fire
  no autocmd, so silent fold changes are picked up by that bounded sweep.
- Prefix anchors (display rows before a line) survive scrolls and text edits,
  so scrolling and typing reuse prior measurements instead of rewalking the
  buffer.

Users can tighten the uniform re-verification window through
`require("scrollbar.layout").screen_extent_verify_interval_ms` (default 250;
`0` re-verifies every render).

`update.interval_ms` coalesces repeated invalidations into the latest frame.

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
