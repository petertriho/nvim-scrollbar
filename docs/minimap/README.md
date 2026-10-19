# Minimap

The minimap shows a squashed view of the source buffer in a floating window. It
is **disabled** by default. The minimap has its own configuration block,
profiles, visibility, mouse handling, and commands. Enabling the minimap does
not show, hide, move, or resize the scrollbar. The minimap commands never show
or hide the scrollbar.

The scrollbar and the minimap share the top-level `providers`, `marks`, and
`exclude` tables. Each built-in provider runs once, with one option set. Each
renderer shows only the providers that target it. See
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
north-east corner. Each minimap row represents a group of source lines.
Occupied cells show the single-width `glyph`, which defaults to `█`.

Occupied cells are monochrome by default. To color them with Treesitter, set
`providers.treesitter = true`. For the full schema, see
[Minimap configuration](configuration.md).

## User Commands

| Command | Behavior |
| --- | --- |
| `:MinimapShow` | Shows the minimap. If autohide is enabled, it also re-arms the autohide deadlines. |
| `:MinimapHide` | Hides every minimap float and clears pending hide deadlines. |
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

When `viewport = true` (the default), the rows that represent the visible
lines of the source window get the `ScrollbarMinimapViewport` background. The
tint spans the full minimap width and does not change the glyphs.

When the `cursor` provider targets the minimap (the default), the cell at the
exact cursor position gets the `ScrollbarMinimapCursor` highlight. This group
links to `Cursor` by default. The cursor point does not replace the glyph. To
disable the cursor point, set `providers.cursor = { minimap = false }`.

## Overlays

Ordinary provider marks, such as diagnostics, search matches, and Git hunks,
tint the occupied cells of their minimap row. A row with no occupied cells
shows no overlay. The built-in mark types are:

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
also rejects collisions between the two renderers, for example a scrollbar type
`MinimapSearch` and the minimap type `Search`, which both claim
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

- A click moves the cursor of the source window to the first column of the line
  that the clicked row represents. Then it opens folds (`zv`) and centers the
  line (`zz`).
- Each drag event moves the cursor to the line under the mouse in the same way.
- A release does the last move and returns focus to the source window. If the
  source window is closed, focus goes to the first available non-floating
  window. A canceled drag does not undo the moves.

The mapping uses logical lines. It does not account for wrapped rows, or for
folds beyond their first line. A press on the minimap does not pause the
autohide deadline.

With `minimap.mouse = false`, the float is not focusable and has no mappings.
A profile that sets `mouse = false` removes the mappings when the minimap
renders with that profile.

## Related

- [Minimap configuration](configuration.md)
- [Scrollbar configuration](../configuration.md)
- [Visibility](../visibility.md)
- [Treesitter provider](../providers/treesitter.md)
- [LSP semantic tokens](../providers/lsp_semantic_tokens.md)
- [Custom providers](../providers/custom.md)
- [Migration](../migration.md)
