# Highlights

With `set_highlights = true`, setup generates scrollbar highlight groups from
the configured track, handle, and mark highlight sources. Groups are regenerated
after `ColorScheme`.

## Highlight Sources

A string names a source highlight group whose current color is copied into the
generated scrollbar group:

- `track.highlight` and `handle.highlight` contribute only their background.
- Each `marks.<Type>.highlight` contributes only its foreground.

A table is passed to `nvim_set_hl()` as a direct definition and may contain any
attributes supported by the active Neovim version.

```lua
require("scrollbar").setup({
    track = {
        highlight = "PmenuSbar",
    },
    handle = {
        highlight = { bg = "#3b4261", blend = 20 },
    },
    marks = {
        Search = {
            highlight = { fg = "#ff9e64", bold = true },
        },
    },
})
```

Generated groups are not highlight links. With `set_highlights = true`, they are
regenerated after `ColorScheme`, so string-source colors are sampled again.
Direct tables define the generated group explicitly.

## Handle Composition

The resting handle defaults to `PmenuThumb`; its pressed background always
comes from `PmenuSel`. Custom handle highlights change the resting handle, not
the pressed source.

For the resting handle, `handle.blend` is added only when the direct or resolved
handle definition does not already contain `blend`; a direct table's own value
wins. The uncovered pressed-handle group uses the `PmenuSel`-derived background
with `handle.blend`. Overlap groups are deep-merged, so a direct mark definition
can override `blend` as well as other attributes. Normal Neovim highlight
semantics still apply to combinations such as `link` with other attributes.

## Generated Groups

- `ScrollbarTrack` styles the track background.
- `ScrollbarHandle` styles uncovered handle cells.
- `ScrollbarHandlePressed` styles uncovered held-handle cells.
- `Scrollbar<MarkType>` styles a mark outside the handle.
- `Scrollbar<MarkType>Handle` styles a mark overlapping the resting handle.
- `Scrollbar<MarkType>HandlePressed` styles a mark overlapping the held handle.

Examples include `ScrollbarSearch`, `ScrollbarSearchHandle`,
`ScrollbarSearchHandlePressed`, `ScrollbarError`, and
`ScrollbarErrorHandle`. Named marks use `ScrollbarMark`,
`ScrollbarMarkHandle`, and `ScrollbarMarkHandlePressed`.

`ScrollbarFloat` is not generated; use `ScrollbarTrack` for manual track
styling.

## Manual Groups

Set `set_highlights = false` to define generated groups yourself. Direct
highlight tables also follow this switch and are not applied when it is false.
Setup and `ColorScheme` handling leave manual groups untouched.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Providers](providers/README.md)
