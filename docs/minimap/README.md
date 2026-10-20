# Minimap

The minimap shows a scaled-down view of the source buffer in a float. It is
**disabled** by default. The minimap has its own configuration block,
profiles, visibility, mouse handling, and commands. When you enable the
minimap, it does not show, hide, move, or resize the scrollbar. The minimap
commands never show or hide the scrollbar.

![The minimap scrolls with the source window and tints the viewport](https://github.com/user-attachments/assets/c2844052-aa78-4896-b675-62b278d0d528)

The scrollbar and the minimap share the top-level `providers`, `marks`, and
`exclude` tables. Each built-in provider runs once, with one set of options.
Each renderer shows only the providers that target it. See
[Configuration](../configuration.md#providers).

## Quick Start

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
    },
})
```

By default, each source window gets its own 16-column minimap at its
north-east corner. The minimap draws the text of the buffer as Braille dots.
Each source line is one row of dots, and the map scrolls with the source
window. See [The Map](#the-map).

When the buffer has a Treesitter parser, the dots get the colors of the
Treesitter highlight captures. Cells without a capture use
`ScrollbarMinimapContent`. To turn off the colors, set
`providers.treesitter = false`.

To select a ready-made look, set `preset`. See [Presets](#presets). For the
full schema, see [Minimap configuration](configuration.md).

## The Map

Each cell of the minimap holds a grid of 2 x 4 dots. A dot is set when a source
line of its dot row has a non-blank character in a source column of its dot
column.

- `encoding = "braille"` (the default) draws each cell as one Braille
  character, which shows the dots.
- `encoding = "block"` draws `█` for each cell that has a dot.

An empty cell is a space.

`scale` sets the number of source lines in each dot row:

- `scale = "fixed"` (the default) gives each dot row one source line, so a
  minimap row shows 4 lines. When the map has more rows than the float, the
  map scrolls in proportion to the source window. At the top of the buffer,
  the float shows the top of the map. At the end of the buffer, it shows the
  end of the map.
- A positive integer gives each dot row that number of source lines and
  scrolls like `"fixed"`. For example, `scale = 2` shows 8 lines in each
  minimap row. `scale = 1` is the same as `"fixed"`.
- `scale = "fit"` shrinks the whole buffer into the float. A buffer that fits
  at the fixed scale looks the same in both scales.

`columns_per_dot` (default `4`) sets the number of source display columns in
each dot column. A cell covers `2 * columns_per_dot` columns. The default
16-cell minimap shows the first 128 display columns of each line. The minimap
clips the columns past its right edge, so a long line does not change the
other lines.

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        scale = 2,
        encoding = "block",
        columns_per_dot = 2,
    },
})
```

## Presets

A minimap preset sets `scale`, `encoding`, `columns_per_dot`, `width`, and
`viewport`. Two presets also hide the mark overlays. Select a preset with
`preset` in the `minimap` block or in a minimap profile:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "vscode",
    },
})
```

The built-in minimap presets are `vscode`, `sublime`, `zed`, `xcode`,
`overview`, `compact`, `minimal`, and `blocks`. The options next to `preset`
win over the preset. See [Minimap presets](../presets.md#minimap-presets).

## User Commands

| Command | Behavior |
| --- | --- |
| `:MinimapShow` | Shows the minimap. If autohide is enabled, it also starts new autohide delays. |
| `:MinimapHide` | Hides every minimap float and cancels pending autohide delays. |
| `:MinimapToggle` | Switches between `Show` and `Hide`. |
| `:MinimapRefresh` | Runs the refresh callbacks of the minimap providers and renders again. It does not show a hidden minimap or a minimap that autohide concealed. |

Setup creates the commands when it runs with `minimap.enabled = true`. With
`minimap.show = false`, the minimap starts hidden. `:MinimapShow` shows it.

## Placement and Size

The minimap supports the same four anchors (`NW`, `NE`, `SW`, `SE`) and the
same two `relative` values (`window`, `editor`) as the scrollbar. The default
placement is `window` + `NE` + `row = 0` + `col = 0`. This placement puts one
minimap at the top-right corner of each source window.

- North anchors (`NW`, `NE`) start at the top of the text area of the source
  window. South anchors (`SW`, `SE`) start at the bottom of that text area.
- West anchors (`NW`, `SW`) start at the left edge. East anchors (`NE`, `SE`)
  start at the right edge of the source window (window-relative) or of the
  editor (editor-relative).
- `placement.row` and `placement.col` are added to the anchor position. To
  move the minimap left of the east edge, use a negative `col`.

With `relative = "editor"`, the minimap shows a single editor-wide float that
tracks the active source window. The scrollbar has the same editor-relative
behavior. See [Visibility](../visibility.md) and
[Layout and geometry](../layout-and-geometry.md).

`width` sets the number of columns (default `16`). `height` defaults to
`false`, which uses the height of the text area of the source window. An
explicit `height` is clamped to that height.

By default, the minimap of the active source window hides while the editing
cursor is inside it. It shows again when the cursor leaves. See
[Visibility](../visibility.md).

### Placement Beside the Scrollbar

The minimap and the scrollbar both use east-side placement by default. When
they are on the same side, `placement.stack` arranges them. With the default
`"inner"`, the scrollbar stays at the window edge, and the minimap is beside
it, nearer the text. `"outer"` puts the minimap at the window edge. `"above"`
and `"below"` overlap the two floats and set which one is on top:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        placement = { stack = "above" },
    },
})
```

See [Placement Beside the Scrollbar](configuration.md#placement-beside-the-scrollbar).

## Viewport and Cursor

When `viewport = true` (the default), the rows that show the visible lines of
the source window get the `ScrollbarMinimapViewport` background. The viewport
band includes every row that shows a visible line, so a row with only some
visible lines is in the band. The tint spans the full minimap width and does
not change the dots.

When the `cursor` provider targets the minimap (the default), the cell at the
exact cursor position gets the `ScrollbarMinimapCursor` highlight. This group
links to `Cursor` by default. The cursor point does not replace the dots. To
disable the cursor point, set `providers.cursor = { minimap = false }`.

## Overlays

Ordinary provider marks, such as diagnostics, search matches, and Git hunks,
tint the occupied cells of their minimap row. A row with no occupied cells
shows no overlay. A mark on a row that is outside the float does not show. The
built-in mark types are:

| Mark type | Source |
| --- | --- |
| `Search` | Search provider |
| `Error`, `Warn`, `Info`, `Hint` | Diagnostic providers (built-in, ALE, Coc) |
| `Mark` | Native marks provider |
| `Misc` | Diagnostic fallback and custom provider use |
| `GitAdd`, `GitChange`, `GitDelete` | gitsigns.nvim |
| `MiniDiffAdd`, `MiniDiffChange`, `MiniDiffDelete` | mini.diff |
| `SignifyAdd`, `SignifyChange`, `SignifyDelete` | vim-signify |
| `VGitAdd`, `VGitChange`, `VGitDelete` | vgit.nvim |

The minimap shows every type in the top-level `marks` registry, except
`Cursor`, with the `priority` and `highlight` of the registry. The minimap
does not use `text`. Use `minimap.marks` to override fields or to hide types.
The types that you do not specify stay visible:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        marks = {
            Error = { priority = 0, highlight = "DiagnosticError" },
            Hint = false,
        },
    },
})
```

Define a custom type once in the top-level `marks` registry. Both renderers
show it. To show it only in the minimap, hide it in the scrollbar:

```lua
require("scrollbar").setup({
    marks = {
        CustomReview = {
            text = "!",
            priority = 8,
            highlight = "Special",
        },
    },
    scrollbar = {
        marks = { CustomReview = false },
    },
    minimap = {
        enabled = true,
        marks = { CustomReview = { priority = 2 } },
    },
})
```

To disable ordinary mark overlays, set `minimap.marks = false`. Semantic
colors and the cursor point stay active. Providers can still publish a hidden
type, but the minimap does not draw it. See
[Minimap configuration](configuration.md#marks).

If more than one mark falls on one minimap row, the type with the lowest
`priority` wins. A `minimap.marks.<Type>.priority` override changes only the
minimap. Ties go to the provider name that sorts first, then to the earlier
mark in the list of that provider.

`minimap.marks` rejects `Cursor`, `Base`, `Content`, and `Viewport`, because
the static minimap layers own these names. The minimap does not show a
registered type with one of these names. When the minimap is enabled, setup
also rejects collisions between the two renderers. For example, a scrollbar
type `MinimapSearch` and the minimap type `Search` both claim
`ScrollbarMinimapSearch`.

Custom providers can also publish semantic spans and exact points for the
minimap. See [Custom providers](../providers/custom.md). For spans, the higher
`priority` wins. Treesitter uses `100`, and LSP semantic tokens use `200`
through `202`. Ordinary overlays draw with priorities `3` through `13`, and the
built-in cursor point uses `14`. A custom point with a `priority` above `13`
appears above ordinary overlays.

## Mouse

The minimap installs buffer-local mappings for `<LeftMouse>`, `<LeftDrag>`, and
`<LeftRelease>` on each minimap float. These mappings are independent of the
scrollbar mouse mappings. The minimap never changes `vim.o.mouse`. You must
enable the mouse modes that you want, for example:

```lua
vim.o.mouse = "a"
```

- A click moves the cursor of the source window to the first column of the
  first line that the clicked row shows. Then it opens folds (`zv`) and centers
  the line (`zz`).
- A drag scrolls the source window so that the viewport band follows the
  pointer, like the slider of a scrollbar. The drag changes the top line of the
  source window. The cursor moves only when it leaves the visible lines. One
  drag can reach both ends of the buffer, in both scales.
- A release returns focus to the source window. A release without a drag
  moves the cursor to the released row, like a click. If the source window is
  closed, focus goes to the first available non-floating window. A canceled
  drag does not undo the scroll.

The click uses logical lines. It does not account for wrapped rows, or for
folds beyond their first line. A drag scrolls with `CTRL-E` and `CTRL-Y`,
which count a closed fold as one line. As a result, a drag over closed folds
can scroll past the band position.

With `autohide`, a press or drag on the minimap pauses the autohide delay of
its source window. Release or cancellation starts a new full delay.

The minimap float is not focusable, and it uses the same focus rules as the
scrollbar floats. See [Focus](../mouse.md#focus).

With `minimap.mouse = false`, mouse input passes through the float, and the
float has no mappings. A profile that sets `mouse = false` removes the mappings
when the minimap renders with that profile.

## Related

- [Minimap configuration](configuration.md)
- [Presets](../presets.md)
- [Scrollbar configuration](../configuration.md)
- [Visibility](../visibility.md)
- [Treesitter provider](../providers/treesitter.md)
- [LSP semantic tokens](../providers/lsp_semantic_tokens.md)
- [Custom providers](../providers/custom.md)
- [Migration](../migration.md)
