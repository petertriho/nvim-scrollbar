# Layout And Geometry

The scrollbar is a floating window attached either to each source window or to
the editor.

## Placement

`float.placement.relative` selects the placement container:

- `"window"` attaches one float to each eligible source window.
- `"editor"` uses editor coordinates and renders only the active source window.
  Horizontal anchors use the editor width; vertical anchors align with the
  active source window's text area.

`anchor` selects the float corner attached to the matching container corner.
`row` and `col` are signed offsets: positive rows move down and positive columns
move right.

```lua
require("scrollbar").setup({
    float = {
        placement = {
            relative = "window",
            anchor = "NW",
            row = 1,
            col = 2,
        },
    },
})
```

Tracks cover source buffer-text rows only. They exclude the source winbar and
remain inside window bounds that already exclude tabline, statusline, and
command-line chrome. Explicit signed offsets are still applied literally and
can intentionally move or clip the float outside those bounds.

The renderer owns float height, scratch buffers, focusability, mouse flags,
style, and source-window association. Supported float controls are `width`,
`zindex`, `hide_on_cursor`, and the typed placement fields.

## Geometry Modes

`render.geometry = "line"` is the default. It maps logical source lines to the
track and avoids fold scanning. Scroll-only frames reuse the cached static mark
layer and recompute the viewport handle.

Line mode caches mark-row composition by source buffer, buffer- and window-mark
revisions, line count, track and container dimensions, and layout-affecting
configuration. Scrolling alone reuses that layer; changes to those cached inputs
rebuild it.

`render.geometry = "screen"` uses `nvim_win_text_height()` so marks and the
handle account for wrapping, closed folds, diff filler, virtual lines,
`topfill`, and wrapped-line offsets. It is more accurate and intentionally more
expensive; screen geometry is recomputed for each dirty render.

When the logical or rendered document height fits within the track, rows align
directly and unused rows below the document stay blank. Taller documents are
proportionally compressed across the track.

`render.interval_ms` is the frame-coalescing interval. Repeated invalidations in
one frame render only the latest state. Scrolling does not recollect provider
marks, and a logical show operation joins the same latest-frame path.

## Wide Scrollbars

Handle and mark ranges can occupy separate columns:

```lua
require("scrollbar").setup({
    float = { width = 4 },
    handle = {
        text = "██",
        column = 3,
        width = 2,
    },
    marks = {
        Error = {
            text = { "E", "!" },
            column = 1,
            priority = 0,
            highlight = "DiagnosticError",
        },
        Search = {
            text = { "s", "S" },
            column = 2,
            priority = 1,
            highlight = "Search",
        },
    },
})
```

Mark text lists are density variants; see
[Marks and columns](configuration.md#marks-and-columns) for selection and
collision rules.

`float.width` is the fixed base width for ordinary rendering. Non-overlapping
ranges on the same row coexist. Overlapping ranges use mark priority, where
lower numbers win, and deterministic tie-breaking. Multi-cell glyphs are
omitted rather than partially rendered.

The built-in marks provider can expand the effective float width with
`providers.marks.max_width`. `NW` and `SW` floats grow right; `NE` and `SE`
floats grow left. The base track and handle cells remain pinned, while the
effective width can vary by source window and render. See
[Marks provider](providers/marks.md) for ordering, caps, truncation, and click
targets.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Visibility](visibility.md)
- [Mouse](mouse.md)
