# Minimap Layout

The minimap renders one floating window per source window. The float's
position, size, and visible decoration are controlled by the
[`float.placement`](configuration.md#fields) block, the [`width` /
`height`](configuration.md#fields) pair, the `show_viewport` toggle, and
provider-published marks, spans, and points.

## Float Placement

The minimap supports the same four anchors (`NW`, `NE`, `SW`, `SE`) and
two relatives (`window`, `editor`) as the scrollbar. The default placement
is `window` + `NE` + `row = 0` + `col = 0`, putting one minimap at the
top-right corner of each source window.

With `relative = "editor"` the minimap instead renders a single editor-wide
float that tracks the active source window (multiple editor-relative floats
would all stack at the same editor corner). This mirrors the scrollbar's
`editor`-relative behavior; see
[Visibility](../visibility.md) and [Layout and geometry](../layout-and-geometry.md).

The float position is computed from:

1. **Vertical anchor.**
   - North anchors (`NW`, `NE`) use the active source window's text-area top.
     Window-relative placement expresses that as row `0`; editor-relative
     placement expresses the same screen row in editor coordinates.
   - South anchors (`SW`, `SE`) use the active source window's text-area
     bottom in the corresponding coordinate system.
2. **Horizontal anchor.**
   - West anchors (`NW`, `SW`) start at column 0 (left edge).
   - East anchors (`NE`, `SE`) start at the source window width
     (window-relative) or `vim.o.columns` (editor-relative).
3. **Offsets.** `placement.row` and `placement.col` are added to the
   computed anchor position. Use a negative `col` to shift the minimap
   left of the east edge.

### Conflict Avoidance with the Scrollbar

The minimap and scrollbar both default to east-side placement and may
overlap. The minimap does not auto-detect the scrollbar's lane width;
coordinate them explicitly:

```lua
require("scrollbar").setup({
    scrollbar = {
        float = { placement = { relative = "editor", anchor = "NE", col = 0 } },
    },
    minimap = {
        enabled = true,
        float = { placement = { relative = "editor", anchor = "NE", col = -2 } },
    },
})
```

## Grid Dimensions

The minimap renders into a `(width × height)` cell grid. `width` is the
horizontal column count (default `16`). `height` defaults to `false`,
meaning "track the source window height"; an explicit integer clamps to
the source window height.

The grid is composed by `lua/scrollbar/minimap/squash.lua` using one source-line
bucket per terminal minimap row:

1. **Vertical merge.** `v_ratio = max(1, source_lines / height)`. Target row
   `r` owns source lines
   `[floor(r * v_ratio), floor((r+1) * v_ratio))`. Every occupied source cell
   in that range is merged by binary OR. When the target is taller than the
   source, the remaining rows are blank.
2. **Binary density.** Each source display column is either filled (any
   non-blank character) or empty (whitespace). Run length no longer matters.
3. **Horizontal merge.** `h_ratio = max(1, max_source_line_len / width)`.
   Target column `c` owns source columns aggregated by binary OR. The
   longest source line's display width (`max_line_width`) is threaded back
   from the worker so the renderer can apply the same `h_ratio` when
   projecting the cursor column.
4. **Canonical cells.** Empty output cells are spaces and occupied output cells
   are `█`. The renderer maps occupied cells to `content_glyph`, so glyph
   customization does not change the squash result, cache key, or occupancy.
5. **Highlight composition.** Occupied cells use
   `ScrollbarMinimapContent` by default. Enabled semantic providers publish
   zero-based source byte spans, which are converted to display columns before
   squashing. Higher numeric span priority wins; ties use provider name and
   list order. Treesitter uses priority `100`, while LSP semantic token layers
   use `200`, `201`, and `202`, so LSP layers override overlapping Treesitter
   captures. Semantic color is applied only where source content is occupied.

Indentation is preserved as leading blank cells because whitespace columns
always produce density 0. Tabs, wide characters, and combining characters use
Neovim display-column widths before horizontal ownership is computed.

## Viewport Tint

When `show_viewport = true` (default), the renderer applies
`ScrollbarMinimapViewport` across the minimap rows corresponding to the source
window's `w0..w$` range. It uses the same terminal-row line-mode projection as
content, ordinary overlays, points, and mouse interaction:
`floor(source_line / v_ratio) + 1`, clamped to the minimap height.

The viewport is a highlight-only layer. It spans the full minimap width and
never rewrites canonical occupancy or custom content glyphs.

## Cursor Point

The default `minimap.providers.cursor = true` publishes one window-scoped point
at the exact cursor byte column. The renderer converts the source prefix to
display width, then applies the same horizontal ratio as the squash
(`floor(display_col / h_ratio) + 1`, clamped to `[1, width]`). The row uses the
same terminal-row `v_ratio` as content and overlays. This remains exact for
text, whitespace, and end-of-line positions.

The point uses `ScrollbarMinimapCursor`, links to `Cursor` by default,
has extmark priority `14`, and does not replace the content glyph. Disable it
with `minimap.providers.cursor = false`.

## Layer Priority

Viewport extmarks use priority `1`, monochrome or semantic cell content uses
priority `2`, and ordinary mark overlays use priorities `3` through `13` after
their lower-wins minimap overlay-spec collision is resolved. Minimap points use their published
extmark priority; the built-in cursor's `14` therefore appears above ordinary
overlays. Custom point providers should use a value above `13` when the point
must win that visual overlap.

Semantic span priority is a separate source-composition rule: higher values win
inside the squash before the content extmark is written. It does not use the
ordinary overlay-spec priority scale. Point extmarks also use higher numeric
priority to win. In short, ordinary mark collisions are lower-wins, while span
and point collisions are higher-wins.

## Caching

The renderer caches squashed cell grids per `(source_buf, width, height)` so
same-buffer windows with different dimensions retain independent projections.
Each projection records the buffer `changedtick`, source filetype, and a
semantic input revision.
The semantic revision advances only when the enabled parent-published span
snapshot changes. Each active dimension requests one new squash for that
revision; repeated renders with the same revision reuse the accepted cells.

Ordinary mark overlays and minimap points do not enter the squash cache. Their
store changes rebuild projected extmarks without requesting new cells. Viewport
composition is likewise rebuilt from live source-window state. Semantic spans
do enter the squash and therefore invalidate the dimension-specific cell cache.

For the `"worker"` backend the first render after a content change draws
the previously known cells; the worker's response then triggers a
re-render with fresh content. Results are accepted only when generation,
buffer `changedtick`, and semantic revision still match. For the `"sync"`
backend the cache is updated synchronously inside `renderer.render`.

## Related

- [Configuration](configuration.md)
- [Overlays](overlays.md)
- [Mouse](mouse.md)
