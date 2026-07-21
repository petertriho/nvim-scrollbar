# Highlights

Scrollbar and minimap automatic highlight generation are independent. With the
corresponding `set_highlights = true`, setup force-refreshes private plugin-owned
definitions and profile-internal groups after setup. It refreshes them after
`ColorScheme` when that subsystem keeps the event in its configured update
list. Public root groups are created only as `default = true` links, so existing
user or colorscheme definitions are preserved.

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

The resting thumb defaults to `PmenuThumb`. Pressed thumb backgrounds are
derived from `PmenuSel`. `thumb.blend` is added when the resolved or direct
definition does not already set `blend`. Mark-over-thumb groups deep-merge the
thumb background and mark definition, with mark fields taking precedence.

## Generated Groups

- `ScrollbarBase`: transparent float-wide base for undeclared cells.
- `ScrollbarTrack`: explicit declared track backgrounds.
- `ScrollbarThumb` and `ScrollbarThumbPressed`.
- `Scrollbar<MarkType>`.
- `Scrollbar<MarkType>Thumb` and `Scrollbar<MarkType>ThumbPressed`.

Examples include `ScrollbarSearch`, `ScrollbarSearchThumb`,
`ScrollbarSearchThumbPressed`, `ScrollbarMark`, and `ScrollbarErrorThumb`.
Renderer extmarks use deterministic stack priorities with `hl_mode = "combine"`
so track backgrounds and content layers compose in declared order.

Automatic scrollbar mode also creates legacy `Handle` names:
`ScrollbarHandle`, `ScrollbarHandlePressed`, `Scrollbar<MarkType>Handle`, and
`Scrollbar<MarkType>HandlePressed`. They are default links to their canonical
`Thumb` equivalents, not separately owned definitions.

The canonical names above belong to the root config. Each compiled profile gets
a stable internal automatic namespace based on declaration index, for example
`ScrollbarProfile1.Track`, `ScrollbarProfile1.Thumb`,
`ScrollbarProfile1.ThumbPressed`, `ScrollbarProfile1.Error`, and
`ScrollbarProfile1.ErrorThumb`. Simultaneous windows can therefore use different
track, thumb, blend, mark, overlap, and pressed definitions. Internal profile
names are implementation details and receive no legacy `Handle` aliases.

## Minimap Groups

Static minimap groups retain these default links:

| Group | Default link |
| --- | --- |
| `ScrollbarMinimapBase` | `NormalFloat` |
| `ScrollbarMinimapContent` | `Comment` |
| `ScrollbarMinimapViewport` | `CursorLine` |
| `ScrollbarMinimapCursor` | `Cursor` |

Every enabled ordinary overlay type uses a distinct public group named
`ScrollbarMinimap<Type>`, for example `ScrollbarMinimapSearch`. Automatic
profiles use internal names such as `ScrollbarMinimapProfile1.Search` so their
definitions can differ simultaneously. The configured source is copied; these
groups do not link to final `Scrollbar<Type>` groups automatically.

Users who want shared manual colors can link the public names explicitly:

```lua
vim.api.nvim_set_hl(0, "ScrollbarMinimapSearch", { link = "ScrollbarSearch" })
vim.api.nvim_set_hl(0, "ScrollbarMinimapError", { link = "ScrollbarError" })
```

## Manual Groups

With `scrollbar.set_highlights = false`, setup and `ColorScheme` handling create
or modify no scrollbar canonical groups, base group, private groups, profile
groups, or legacy aliases. Manual configurations must define the canonical
Thumb names used by renderer extmarks. Defining only old Handle names is
insufficient.

Manual mode intentionally uses the same canonical groups for every profile and
creates no `ScrollbarProfile*` groups. Profile-specific highlight sources and
blend values therefore require `set_highlights = true`; there is no public
profile-specific manual highlight API.

With `minimap.set_highlights = false`, setup and `ColorScheme` handling write no
static, public, private, or profile minimap groups. Every minimap profile uses
canonical `ScrollbarMinimap<Type>` names; define those groups manually. There is
no public profile-specific manual API.

## Related

- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
