# Layout And Geometry

The renderer derives the float width, physical columns, thumb geometry, mark
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

The track paints only the background. The thumb paints its repeated text and
its background while the viewport span is active. Mark layers paint the
resolved glyphs. A later track can replace the background without replacing a
lower content glyph. Marks above the thumb stay visible. The thumb hides the
marks below it.

Plain `"marks"` receives every type that no explicit descriptor claims:

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

To create a span, repeat the same layer in adjacent columns. The thumb and each
mark lane must be contiguous. The track can repeat anywhere. Components are
optional, so mark-only and thumb-only rulers are valid. A blank cell without a
declared track, an active thumb, or a visible mark uses the transparent float
base.

## Direction

- `auto`: declarations are inner-to-outer. East anchors render left-to-right,
  and west anchors mirror that order.
- `ltr`: declarations always render in physical left-to-right order.
- `rtl`: declarations always render in physical right-to-left order.

Direction moves columns, not the internals of a glyph. Multi-cell strings keep
the normal left-to-right character order.

## Named-Mark Lanes

Only a descriptor that explicitly selects `Mark` can set `max_width`:

```lua
layout = {
    columns = {
        { "track", "thumb" },
        { { kind = "marks", types = { "Mark" }, max_width = 8 } },
        { "marks" },
    },
}
```

When built-in named marks collide on a row, their lane grows only as much as
necessary. `max_width` caps the total width of that lane, including its
declared base span. It does not cap the whole float. The active placement
container limits the growth. Dynamic cells contain only named marks and are
inserted on the inward side that faces the editor. The screen cells of the
declared track, thumb, and ordinary marks stay pinned as the float grows or
shrinks.

Built-in names keep the source-line/name order. If the capacity is not
sufficient, the ordered prefix stays and the tail is omitted. Marks with
`type = "Mark"` from custom providers stay collapsed in the declared base lane.

## Placement

`float.placement.relative = "window"` creates one float per eligible source
window. `"editor"` uses editor coordinates and renders only for the active
source window. `anchor` selects `NW`, `NE`, `SW`, or `SE`. The signed `row` and
`col` offsets apply literally. `gutter` selects `"avoid"` (the default) or
`"overlap"`. Within an avoided west gutter, `gutter_position` selects `"inner"`
(the default, beside the buffer text) or `"outer"` (at the source-window edge).

The gutter placement depends on the relative mode and the anchor:

| Relative mode | Anchor | `gutter = "avoid"` behavior | `gutter = "overlap"` origin |
| --- | --- | --- | --- |
| `"window"` | `NW` or `SW` | Reserves blank gutter cells and places the float inside them | Source window edge |
| `"window"` | `NE` or `SE` | Existing east edge | Existing east edge |
| `"editor"` | Any | Existing editor coordinate | Existing editor coordinate |

For a window-relative west anchor, these names apply:

- `G` is the gutter width of the source window before the scrollbar
  reservation.
- `W` is the rendered float width.
- `C` is the configured `col`.

In `avoid` mode, the renderer reserves `max(0, W + C)` blank cells. With
`gutter_position = "inner"`, the reservation follows the existing gutter. The
float starts at `G + C`, beside the shifted edge of the buffer text. With
`gutter_position = "outer"`, the reservation precedes the existing gutter. The
float starts at `C`, beside the source-window edge.

A positive offset leaves a gap before the float, within its reservation. A
negative offset stays literal. It can deliberately extend outside or overlap
adjacent gutter cells.

The reservation temporarily changes the window-local `statuscolumn` and
`numberwidth`. Existing fold, sign, number, and custom `statuscolumn` content
stays visible, before an `"inner"` reservation or after an `"outer"`
reservation. The plugin restores the original `statuscolumn` and `numberwidth`
when the scrollbar is hidden, is disposed, becomes ineligible, or switches to a
placement without a reservation. If you edit these options while the
reservation is active, your edit is kept. Each split owns and restores its own
reservation. This includes a split that you create from a window that already
has a reservation.

Neovim limits the maximum `statuscolumn` width. If a declared west layout is
too wide to reserve completely, the plugin does not show that scrollbar. It
does not reserve part of the layout and cover buffer text. When the declared
base layout fits, dynamic named-mark growth stays within the reservation.

A change to `number`, `relativenumber`, `numberwidth`, `foldcolumn`,
`signcolumn`, or `statuscolumn` queues a render. Other gutter width changes,
such as automatic sign column changes, apply at the next render.

Contextual profiles resolve the placement per source window. With the root
`visibility = "all"`, compatible window-relative variants can coexist, and an
editor-relative variant shows only when its source is active. The root
`visibility = "active"` always limits the entire renderer to the active source.
When a different profile matches, the existing float takes the relative mode,
anchor, offsets, width, z-index, cursor-hiding policy, and mouse behavior of
that profile.

The float covers the buffer-text rows of the source. It excludes the source
winbar and the rows already used by the tabline, the statusline, and the
command line. The plugin derives the float width and height. The public float
options are `zindex`, `hide_on_cursor`, and `placement`.

## Geometry Modes

`render.geometry = "line"` maps logical lines directly.

`render.geometry = "screen"` uses display rows. As a result, wrapping, folds,
diff filler, virtual lines, `topfill`, and wrapped offsets affect both the
marks and the thumb geometry.

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

Terminal cells, font width, and colorscheme highlights limit the visual
fidelity. Presets and examples are structural contracts, not pixel-perfect GUI
reproductions.

## Related

- [Configuration](configuration.md)
- [Presets](presets.md)
- [Marks provider](providers/marks.md)
- [Mouse](mouse.md)
