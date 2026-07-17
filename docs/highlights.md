# Highlights

With `set_highlights = true`, setup generates scrollbar groups from the
configured track, thumb, and mark sources and regenerates them after
`ColorScheme`.

## Sources

- A string `track.highlight` or `thumb.highlight` contributes its resolved
  background.
- A string `marks.<Type>.highlight` contributes its resolved foreground.
- A table is used as a direct `nvim_set_hl()` definition.

```lua
require("scrollbar").setup({
    track = { highlight = "PmenuSbar" },
    thumb = { highlight = { bg = "#3b4261", blend = 20 } },
    marks = {
        Search = { highlight = { fg = "#ff9e64", bold = true } },
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

Automatic mode also generates equivalent legacy `Handle` names:
`ScrollbarHandle`, `ScrollbarHandlePressed`, `Scrollbar<MarkType>Handle`, and
`Scrollbar<MarkType>HandlePressed`. These aliases exist only when the plugin
owns highlight generation.

The canonical names above belong to the root config. Each compiled profile gets
a stable internal automatic namespace based on declaration index, for example
`ScrollbarProfile1Track`, `ScrollbarProfile1Thumb`,
`ScrollbarProfile1ThumbPressed`, `ScrollbarProfile1Error`, and
`ScrollbarProfile1ErrorThumb`. Simultaneous windows can therefore use different
track, thumb, blend, mark, overlap, and pressed definitions. Internal profile
names are implementation details and receive no legacy `Handle` aliases. Setup
and every `ColorScheme` event regenerate the root and all profile groups.

## Manual Groups

With `set_highlights = false`, setup and `ColorScheme` handling create or modify
no canonical groups, base group, or legacy aliases. Manual configurations must
define the canonical Thumb names used by renderer extmarks. Defining only old
Handle names is insufficient in manual mode.

Manual mode intentionally uses the same canonical groups for every profile and
creates no `ScrollbarProfile*` groups. Profile-specific highlight sources and
blend values therefore require `set_highlights = true`; there is no public
profile-specific manual highlight API.

## Related

- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
