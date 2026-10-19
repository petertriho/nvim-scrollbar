# Highlights

The scrollbar and the minimap generate automatic highlights independently. When
a renderer has `set_highlights = true`, setup creates the highlight groups of
that renderer. The plugin updates them after `ColorScheme` when the
`update.events` list of that renderer contains `ColorScheme`. Public groups are
created only as `default = true` links, so existing user or colorscheme
definitions are kept.

## Sources

- A string `track.highlight` or `thumb.highlight` contributes its resolved
  background.
- A string `marks.<Type>.highlight` contributes its resolved foreground.
- A string `minimap.overlays.types.<Type>.highlight` also contributes its
  resolved foreground.
- A table is used as a direct `nvim_set_hl()` definition.

```lua
require("scrollbar").setup({
    scrollbar = {
        track = { highlight = "PmenuSbar" },
        thumb = { highlight = { bg = "#3b4261", blend = 20 } },
        marks = {
            Search = { highlight = { fg = "#ff9e64", bold = true } },
        },
    },
})
```

The resting thumb uses `PmenuThumb` by default. Pressed thumb backgrounds are
derived from `PmenuSel`. When the resolved or direct definition does not
already set `blend`, the plugin adds `thumb.blend`. Mark-over-thumb groups
deep-merge the thumb background and the mark definition. Mark fields take
precedence.

## Generated Groups

- `ScrollbarBase`: a transparent, float-wide base for undeclared cells.
- `ScrollbarTrack`: backgrounds for explicitly declared tracks.
- `ScrollbarThumb` and `ScrollbarThumbPressed`.
- `Scrollbar<MarkType>`.
- `Scrollbar<MarkType>Thumb` and `Scrollbar<MarkType>ThumbPressed`.

Examples include `ScrollbarSearch`, `ScrollbarSearchThumb`,
`ScrollbarSearchThumbPressed`, `ScrollbarMark`, and `ScrollbarErrorThumb`.
Track backgrounds and content layers combine in the declared layer order.

In automatic mode, the scrollbar also creates the legacy `Handle` names:
`ScrollbarHandle`, `ScrollbarHandlePressed`, `Scrollbar<MarkType>Handle`, and
`Scrollbar<MarkType>HandlePressed`. These names are default links to their
canonical `Thumb` equivalents. They are not separately owned definitions.

The canonical names above belong to the root configuration. In automatic mode,
each profile also gets its own internal groups. As a result, windows that are
visible at the same time can use different track, thumb, blend, mark, overlap,
and pressed definitions.

## Minimap Groups

Static minimap groups keep these default links:

| Group | Default link |
| --- | --- |
| `ScrollbarMinimapBase` | `NormalFloat` |
| `ScrollbarMinimapContent` | `Comment` |
| `ScrollbarMinimapViewport` | `CursorLine` |
| `ScrollbarMinimapCursor` | `Cursor` |

Every enabled ordinary overlay type uses a distinct public group named
`ScrollbarMinimap<Type>`, for example `ScrollbarMinimapSearch`. In automatic
mode, each minimap profile also gets its own internal groups. These groups copy
the configured source. They do not link automatically to the final
`Scrollbar<Type>` groups.

To share manual colors, you can link the public names explicitly:

```lua
vim.api.nvim_set_hl(0, "ScrollbarMinimapSearch", { link = "ScrollbarSearch" })
vim.api.nvim_set_hl(0, "ScrollbarMinimapError", { link = "ScrollbarError" })
```

## Manual Groups

With `scrollbar.set_highlights = false`, the plugin creates and changes no
scrollbar groups, including the base group and the legacy aliases. A manual
configuration must define the canonical Thumb names. It is not sufficient to
define only the old Handle names.

In manual mode, every profile uses the same canonical groups. As a result,
profile-specific highlight sources and blend values need
`set_highlights = true`. There is no public API for profile-specific manual
highlights.

With `minimap.set_highlights = false`, the plugin writes no minimap groups.
Every minimap profile uses the canonical `ScrollbarMinimap<Type>` names. Define
those groups manually.

## Related

- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
