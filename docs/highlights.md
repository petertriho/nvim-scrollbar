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
already set `blend`, the plugin adds the blend of the thumb, and it adds the
blend of the track to the track. See [Blend](#blend). Mark-over-thumb groups
deep-merge the thumb background and the mark definition. Mark fields take
precedence.

A user or a colorscheme can define a public group, for example
`ScrollbarThumb` or `ScrollbarSearch`. The overlap groups then merge that
definition instead of the generated definition. Thus a mark keeps its color
over the thumb, and the thumb keeps its background behind the mark. The plugin
reads these definitions at setup and after each `ColorScheme` event.

## Generated Groups

- `ScrollbarBase`: a float-wide base for undeclared cells, without colors.
- `ScrollbarTrack`: backgrounds for explicitly declared tracks.
- `ScrollbarThumb` and `ScrollbarThumbPressed`.
- `Scrollbar<MarkType>`.
- `Scrollbar<MarkType>Thumb` and `Scrollbar<MarkType>ThumbPressed`.
- `Scrollbar<MarkType>Tint`: the background of a tint mark. The plugin creates
  it only with `overlap.marks = "tint"`. Its background is the foreground of
  the mark group, or else the background of the mark group.

Examples include `ScrollbarSearch`, `ScrollbarSearchThumb`,
`ScrollbarSearchThumbPressed`, `ScrollbarMark`, and `ScrollbarErrorThumb`.
Track backgrounds and content layers combine in the declared layer order.

In automatic mode, the scrollbar also creates the legacy `Handle` names:
`ScrollbarHandle`, `ScrollbarHandlePressed`, `Scrollbar<MarkType>Handle`, and
`Scrollbar<MarkType>HandlePressed`. These names are default links to their
canonical `Thumb` equivalents. They are not separately owned definitions.

The canonical names above belong to the root configuration. In automatic mode,
each profile also gets its own internal groups, including its own base. As a
result, windows that are visible at the same time can use different base,
track, thumb, blend, mark, overlap, tint, and pressed definitions.

A profile copies the final definition of a root group when the profile has the
same options for that group as the root. The final definition is the user or
colorscheme definition of the public group, or else the generated definition.
These options select each group:

- Base: the blend of the base.
- Track: `track.highlight` and the blend of the track.
- Thumb: `thumb.highlight` and the blend of the thumb.
- Pressed thumb: the blend of the thumb.
- Mark: the `highlight` of the mark type.
- Overlap and pressed overlap: the options of the thumb or the pressed thumb,
  and the `highlight` of the mark type.
- Tint: the `highlight` of the mark type and the blend of the track.

[Blend](#blend) gives the rules for each blend.

For example, a profile that sets only `placement` uses the `ScrollbarSearch`
definition of a colorscheme. A profile that sets `thumb.blend` generates its own
thumb groups and overlap groups.

## Blend

Neovim blends the cells of a float only when the float has `'winblend'`
greater than `0`. A cell then takes the `blend` of its highlight group. A
cell with a group that does not set `blend` takes the `'winblend'` of the
float. A space cell with a blend shows the character of the window below it.

The plugin sets the `'winblend'` of the scrollbar float, so the float does not
get the global `'winblend'`, and each generated group sets its own `blend`:

| Group | Blend |
| --- | --- |
| Base | `100` with `overlap.show_through`, else `window.wo.winblend`, else `0` |
| Track and tint | `overlap.show_through`, else `window.wo.winblend`, else `0` |
| Thumb and pressed thumb | The larger value of `thumb.blend` and `overlap.show_through` |
| Mark | No blend. A mark takes the blend of the layer below it |

The `'winblend'` of the float is `window.wo.winblend` when you set it.
Otherwise, it is `overlap.show_through` when you set it. Otherwise, it is `1`
when the thumb blends or `hide_on_cursor = "row"`, and `0` when no cell
blends. Because the groups set their own blend, a value of `1` only turns
blending on. A public group of a user or a colorscheme that does not set
`blend` gets the `'winblend'` of the float.

With `overlap.show_through`, a glyph mark that has no track or thumb below it
gets the internal `ScrollbarGenerated.Surface<blend>` group, so the glyph does
not fade into the text. `hide_on_cursor = "row"` uses the internal
`ScrollbarGenerated.Clear` group. These internal groups set only a blend and a
special color. Neovim drops a group that sets only a blend. A special color
shows only with an underline style, so it does not change a cell. The plugin
creates these groups also in manual mode, because they hold no colors to
customize.

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

## Search Highlights

The scrollbar and the minimap do not show search highlights. `'hlsearch'` is a
global option, so Neovim matches the last search pattern in every window,
floats included. The rows of each float are overlay virtual text on empty
buffer lines. Thus the pattern matches no text of the float, and the marks
keep their colors. Tools that read the buffer of a float, such as `:Inspect`,
find only empty lines.

As a backstop, the `winhighlight` of each float maps `Search`, `CurSearch`, and
`IncSearch` to `Scrollbar.NoSearch`. The plugin does not define this group, so
it is empty. The overlays cover the cells of the float, so the mapping has no
visible effect.

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
mode, each minimap profile also gets its own internal groups. A profile with
the same `highlight` for a mark type as the root copies the final root group.
That is the user or colorscheme definition of `ScrollbarMinimap<Type>`, or else
the generated definition. A profile with another `highlight` copies its own
source. These groups do not link automatically to the final `Scrollbar<Type>`
groups.

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

In manual mode, set `blend` in your groups yourself. A group without `blend`
gets the `'winblend'` of the float. See [Blend](#blend). With
`overlap.show_through`, give `ScrollbarBase` `blend = 100`, so the empty cells
do not dim the text. With `overlap.marks = "tint"`, define the
`Scrollbar<MarkType>Tint` groups.

With the same option, the plugin also writes no minimap groups. Every minimap
profile then uses the canonical `ScrollbarMinimap<Type>` names. Define those
groups manually.

The floats still map their frames to the [frame groups](#frame-groups). When
you use a border, a title, or a footer in manual mode, define those groups too.

## Related

- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
