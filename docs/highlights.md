# Highlights

The scrollbar and the minimap generate automatic highlights independently. When
the top-level `set_highlights = true` (the default), setup creates the scrollbar
groups. It also creates the minimap groups when the minimap is enabled. The
plugin updates these groups after each `ColorScheme` event. The plugin creates
public groups only as `default = true` links, so it keeps existing user or
colorscheme definitions.

## Sources

- A string `track.highlight` or `thumb.highlight` contributes its resolved
  background.
- A string `highlight` of a mark type contributes its resolved foreground. The
  top-level `marks.<Type>.highlight` applies to both renderers.
  `scrollbar.marks.<Type>.highlight` and `minimap.marks.<Type>.highlight`
  override it for one renderer.
- The plugin uses a table as a direct `nvim_set_hl()` definition.

```lua
require("scrollbar").setup({
    marks = {
        Search = { highlight = { fg = "#ff9e64", bold = true } },
    },
    scrollbar = {
        track = { highlight = "PmenuSbar" },
        thumb = { highlight = { bg = "#3b4261", blend = 20 } },
    },
})
```

The resting thumb uses `PmenuThumb` by default. The plugin derives pressed thumb
backgrounds from `PmenuSel`. When the resolved or direct definition does not
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

## Frame Groups

The border, the title, and the footer of each float use static groups. The
plugin creates them as default links:

| Group | Default link | Float |
| --- | --- | --- |
| `ScrollbarFloatBorder` | `FloatBorder` | Scrollbar |
| `ScrollbarFloatTitle` | `FloatTitle` | Scrollbar |
| `ScrollbarFloatFooter` | `FloatFooter` | Scrollbar |
| `ScrollbarMinimapFloatBorder` | `FloatBorder` | Minimap |
| `ScrollbarMinimapFloatTitle` | `FloatTitle` | Minimap |
| `ScrollbarMinimapFloatFooter` | `FloatFooter` | Minimap |

The `winhighlight` of each float maps `FloatBorder`, `FloatTitle`, and
`FloatFooter` to these groups. All profiles use the same groups. To change the
frame of one profile, set `window.wo.winhighlight` in that profile:

```lua
require("scrollbar").setup({
    scrollbar = {
        window = { border = "rounded" },
        profiles = {
            {
                match = { filetypes = { "help" } },
                window = { wo = { winhighlight = "FloatBorder:DiagnosticInfo" } },
            },
        },
    },
})
```

The entries of `window.wo.winhighlight` add to the mapping of the renderer.
An entry for a group replaces the entry of the renderer for that group. See
[Window](configuration.md#window).

The groups own these names, so `FloatBorder`, `FloatTitle`, and `FloatFooter`
are not valid mark types. A scrollbar mark type with one of these names claims
the same group as the frame, and setup fails. The minimap rejects the names as
minimap mark types.

## Minimap Groups

Static minimap groups keep these default links:

| Group | Default link |
| --- | --- |
| `ScrollbarMinimapBase` | `Normal` |
| `ScrollbarMinimapContent` | `Comment` |
| `ScrollbarMinimapViewport` | `Visual` |
| `ScrollbarMinimapCursor` | `Cursor` |

Every mark type that the minimap shows uses a distinct public group named
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

With the top-level `set_highlights = false`, the plugin creates and changes no
scrollbar groups, including the base group and the legacy aliases. A manual
configuration must define the canonical Thumb names. It is not sufficient to
define only the legacy Handle names.

In manual mode, every profile uses the same canonical groups. As a result,
profile-specific highlight sources and blend values need
`set_highlights = true`. There is no public API for profile-specific manual
highlights.

With the same option, the plugin also writes no minimap groups. Every minimap
profile then uses the canonical `ScrollbarMinimap<Type>` names. Define those
groups manually.

The floats still map their frames to the [frame groups](#frame-groups). When
you use a border, a title, or a footer in manual mode, define those groups too.

## Related

- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
