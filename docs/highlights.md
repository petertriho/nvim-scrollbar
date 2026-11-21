# Highlights

The scrollbar and the minimap generate automatic highlights independently. When
the top-level `set_highlights = true` (the default), setup creates the scrollbar
groups. It also creates the minimap groups when the minimap is enabled. A setup
during start-up creates the groups after the first screen. See
[Start-up](configuration.md#start-up). The plugin updates these groups after
each `ColorScheme` event. The plugin creates
public groups only as `default = true` links, so it keeps existing user or
colorscheme definitions.

## Sources

- A string `track.highlight` or `thumb.highlight` contributes its resolved
  background.
- A string `highlight` of a mark type contributes the resolved color of the
  channel that `highlight_channel` selects: `"fg"` (the default) or `"bg"`. The
  mark shows that color as its foreground. The top-level
  `marks.<Type>.highlight` applies to both renderers.
  `scrollbar.marks.<Type>.highlight` and `minimap.marks.<Type>.highlight`
  override it for one renderer. The same rules apply to `highlight_channel`.
- If the group of a mark has no color for the selected channel, the mark uses
  the other channel. Thus a group that sets only `bg`, such as `QuickFixLine` in
  some colorschemes, still gives a visible mark. The GUI color and the color
  number fall back separately. A group with neither color gives black, and a
  missing group gives the foreground of `Normal`.
- The plugin uses a table as a direct `nvim_set_hl()` definition. A table
  ignores `highlight_channel`.

A resolved color has a GUI color and a color number for a terminal without
`'termguicolors'`:

- The number is the `ctermbg` or the `ctermfg` of the group. A mark takes the
  number of the channel that `highlight_channel` selects. When the group sets
  `cterm.reverse`, the terminal swaps the two, so the background comes from
  `ctermfg` and the foreground comes from `ctermbg`.
- When the group has no number for the channel, the plugin uses the nearest
  color of the 256-color palette to the GUI color. Thus the default track and
  thumb show also when `PmenuSbar` and `PmenuThumb` have no cterm colors. A
  mark whose selected channel has no number and no GUI color takes the number
  of the other channel.
- The plugin does not copy `cterm.reverse`. A generated group combines with
  the groups below it, and Neovim drops the attribute in a cell that blends.

A table keeps its own cterm keys. Without `ctermfg` or `ctermbg`, the table has
no color without `'termguicolors'`.

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
- The `Inactive` groups of the elements that have an inactive color, for
  example `ScrollbarThumbInactive`. See [Inactive Windows](#inactive-windows).

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

## Covered Marks

A scrollbar mark type with `highlight_from = "covered"` shows in the colors of
the mark that it covers. See [Marks](configuration.md#marks) for the rules.
The option adds no groups. The cell uses the groups of the covered mark type:

- `Scrollbar<Type>` in a row without the thumb.
- `Scrollbar<Type>Thumb` over the thumb, and `Scrollbar<Type>ThumbPressed`
  over the pressed thumb.
- `Scrollbar<Type>Tint` with `overlap.marks = "tint"`.
- The inactive groups of the covered type in an inactive window. The
  `inactive_highlight` of the covering mark applies only when the mark covers
  no mark.

For example, with `marks.Cursor.highlight_from = "covered"`, the cursor mark on
a row with an Error mark uses `ScrollbarError`, or `ScrollbarErrorThumb` over
the thumb. A cursor mark that covers no mark uses `ScrollbarCursor`.

## Inactive Windows

The scrollbar and the minimap of an inactive source window can use other
colors. These source windows are active:

- The current window. When a scrollbar float or a minimap float has focus,
  for example during a drag, its source window is active.
- The source windows of a snacks.nvim or Telescope picker that has focus. For
  example, while the picker input has focus, the list and the preview are
  active.

All other source windows are inactive. While a float that is not a source
window has focus, such as an LSP hover window, all source windows are
inactive. This is the same rule as for `visibility = "active"`. See
[Source Windows](visibility.md#source-windows).

Set `inactive_highlight` beside the `highlight` of an element:

```lua
require("scrollbar").setup({
    marks = {
        Error = { inactive_highlight = "Comment" },
        Warn = { inactive_highlight = "Comment" },
    },
    scrollbar = {
        thumb = { inactive_highlight = "CursorLine" },
    },
})
```

| Option | Inactive group |
| --- | --- |
| `scrollbar.track.inactive_highlight` | `ScrollbarTrackInactive` |
| `scrollbar.thumb.inactive_highlight` | `ScrollbarThumbInactive` |
| `marks.<Type>.inactive_highlight` | `Scrollbar<Type>Inactive` and `ScrollbarMinimap<Type>Inactive` |

`inactive_highlight` follows the rules of `highlight`:

- The value is a group name or an `nvim_set_hl()` table.
- The track and the thumb take the background of a group name.
- A mark takes the channel that `inactive_highlight_channel` selects. Without
  it, the mark takes the channel of `highlight_channel`. The fallback to the
  other channel is the same as in [Sources](#sources).
- `scrollbar.marks.<Type>` and `minimap.marks.<Type>` override the top-level
  `marks.<Type>` for one renderer. Presets and profiles can set the keys.

### When an Element Uses Its Inactive Group

An element uses its inactive group in an inactive window when one of these
conditions is true:

- The configuration sets its `inactive_highlight`.
- A user or a colorscheme defines its public inactive group, for example
  `ScrollbarThumbInactive`.

Otherwise, the plugin creates no inactive group for the element, and the
element keeps its normal group. A configuration without inactive colors and
without public inactive groups thus renders the same as before. The only extra
work is the check for the public groups, which takes microseconds.

The plugin looks for the public inactive groups at setup, after each
`ColorScheme` event, and on `:ScrollbarRefresh` and `:MinimapRefresh`. It does
not look for them during a render. To define the groups in your own
`ColorScheme` autocommand, create the autocommand before you call `setup()`.
If you define a group at another time, run `:ScrollbarRefresh` or
`:MinimapRefresh`.

The plugin sets the colors again when it renders a window. `WinEnter`, which
is in the default `events`, renders all windows. If you remove `WinEnter` from
`events`, a window changes its colors only at its next render.

`visibility = "active"` and editor-relative placement show only the
scrollbars of active windows, so the inactive colors do not show there.

### Inactive Groups

In automatic mode, the plugin generates an inactive group in the same way as
the normal group. An element without its own `inactive_highlight` copies the
final normal definition. Such an element uses its inactive group because a
user or a colorscheme defines the public group, or because it merges a part
that has an inactive color.

- `ScrollbarTrackInactive` and `ScrollbarThumbInactive` take the blend of the
  track and of the thumb.
- `Scrollbar<Type>Inactive` takes no blend, as the normal mark group.
- `Scrollbar<Type>ThumbInactive` merges two parts: the inactive thumb, or else
  the normal thumb, and the inactive mark, or else the normal mark. It is used
  when the thumb or the mark has an inactive color. Thus a dim thumb stays dim
  behind each mark.
- `Scrollbar<Type>TintInactive` takes its background from the inactive mark,
  or else the normal mark. The plugin creates it only with
  `overlap.marks = "tint"`.
- `ScrollbarMinimap<Type>Inactive` is the inactive group of a minimap mark.

The pressed thumb has no inactive groups. A press on a scrollbar makes its
source window active.

Each profile gets its own inactive groups, for example
`ScrollbarProfile1.ThumbInactive`. A profile with the same options for a group
as the root copies the final root group, as for the normal groups. A profile
can set its own `inactive_highlight`. It cannot remove an `inactive_highlight`
of the root.

The minimap also has three static inactive groups:
`ScrollbarMinimapContentInactive`, `ScrollbarMinimapViewportInactive`, and
`ScrollbarMinimapCursorInactive`. The plugin never creates them. Define them
to change the plain content, the viewport, and the cursor of an inactive
minimap:

```lua
vim.api.nvim_set_hl(0, "ScrollbarMinimapViewportInactive", { bg = "#20232d" })
vim.api.nvim_set_hl(0, "ScrollbarMinimapCursorInactive", { link = "NonText" })
```

The base and the syntax colors of the minimap do not change.

With `set_highlights = false`, the plugin creates no inactive group. Define
the inactive groups yourself. A defined group is enough. You do not need the
option.

Setup reserves the names of the inactive groups. For example, a mark type
`ErrorInactive` beside the mark type `Error` is a setup error, because both
claim `ScrollbarErrorInactive`.

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

## Navigation Groups

Label mode and the glance pickers use static groups. The plugin creates them as
default links:

| Group | Default link | Use |
| --- | --- | --- |
| `ScrollbarJumpLabel` | `Substitute` | The labels of label mode |
| `ScrollbarGlanceHeader` | `Title` | The group headers of the glance window |
| `ScrollbarGlanceLineNr` | `LineNr` | The line numbers of the glance list, in every picker |

The glyphs of the glance list use the `Scrollbar<Type>` group of each mark
type. The groups own these names, so `JumpLabel`, `GlanceHeader`, and
`GlanceLineNr` are not valid mark types. See
[Jump and Glance](jump-and-glance.md).

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

For the inactive versions of these groups, see
[Inactive Windows](#inactive-windows).

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
To use label mode or the glance pickers in manual mode, define the
[navigation groups](#navigation-groups).

## Related

- [Configuration](configuration.md)
- [Jump and Glance](jump-and-glance.md)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
