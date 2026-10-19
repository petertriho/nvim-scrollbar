# Presets

Scrollbar presets are setup-local baselines for presentation. A preset can
change `layout`, `track`, `thumb`, `marks`, and `float.placement`. A preset
cannot change providers, visibility, geometry mode, mouse behavior, exclusions,
autohide, or performance options.

## Built-ins

The built-in catalog has twelve colorscheme-aware layouts:

- General/editor layouts: `vscode`, `zed`, `intellij`, `gvim`, `eclipse`,
  `sublime`, `emacs`, `xcode`.
- Task-oriented layouts: `minimal`, `review`, `search`, `navigate`.

```lua
require("scrollbar").setup({
    scrollbar = {
        preset = "review",
    },
})
```

### General/Editor Layouts

- `vscode`: three overview-ruler columns. Git-family types use the inner lane,
  the other types use the catch-all lane in the center, and diagnostics use the
  outer lane. The track and the thumb span all three columns. Marks are below
  the thumb.
- `zed`: one compact `track -> thumb -> marks` column, so marks stay above the
  thumb.
- `intellij`: one track/thumb column beside a transparent stripe for diagnostic
  and catch-all marks.
- `gvim`: a solid, two-column conventional scrollbar without annotations.
- `eclipse`: a bar with lanes for diagnostic, navigation, and catch-all
  annotations.
- `sublime`: a translucent thumb without a track, with all marks above it.
- `emacs`: a west-anchored bar at the outer edge of its own gutter reservation,
  with a diagnostic fringe on the inner side.
- `xcode`: a compact bar with navigation and diagnostic stripes.

The presets with editor names approximate the scrollbar and annotation
structure of each editor in terminal cells. They do not configure the separate
minimap, and they do not claim pixel-perfect GUI fidelity.

### Task-Oriented

- `minimal`: a thumb-only overlay with no track and no marks.
- `review`: separate Git-family, track/thumb, and diagnostic lanes. This preset
  intentionally omits search, cursor, named, and uncategorized marks.
- `search`: one compact track/thumb column with only cursor and search marks.
- `navigate`: a track/thumb/cursor column beside an expandable lane for named
  marks. This preset intentionally omits diagnostic, search, Git, and catch-all
  marks.

[`lua/scrollbar/presets.lua`](../lua/scrollbar/presets.lua) defines the
exact layout and `thumb.blend` value of each built-in preset.

## Local Presets

```lua
require("scrollbar").setup({
    scrollbar = {
        preset = "focused",
        presets = {
            focused = {
                extends = "intellij",
                thumb = { blend = 15 },
                layout = {
                    columns = {
                        { "track", "thumb" },
                        { { kind = "marks", types = { "Error", "Warn" } }, "marks" },
                    },
                },
            },
        },
        thumb = { text = " " }, -- Root values win last.
    },
})
```

A local preset can have one optional `extends` parent. The order of the
declarations does not matter. Unknown names, unknown parents, cycles, malformed
definitions, and disallowed fields are errors. A local entry with the name of a
built-in overlays that built-in. It does not erase the built-in.

Local presets do not persist across setup calls. Dense lists, such as
`layout.columns`, selector `types`, and mark `text`, replace atomically.

## Precedence

Later layers win:

1. The neutral plugin defaults.
2. The selected built-in or local preset, including its parent.
3. The root setup options.

A preset `float` accepts only `placement`. Set `float.zindex` and
`float.hide_on_cursor` in the root options or in a profile `config`.

## Minimap Presets

The minimap has a separate setup-local preset registry. Its one built-in preset
is `default`, with `width = 16`, `height = false`, window-relative north-east
placement, overlays enabled, and viewport tint enabled:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "default",
    },
})
```

Minimap preset definitions accept only these fields:

| Field | Allowed value |
| --- | --- |
| `extends` | One parent preset name. |
| `width` | `false` or a positive integer. `false` gives a width of `16`. |
| `height` | `false` or a positive integer. |
| `float.placement` | `relative`, `anchor`, `row`, `col`, `gutter`, and `gutter_position`. |
| `overlays` | `enabled` and `types`. |
| `show_viewport` | Boolean. |
| `autohide` | `enabled` and `delay_ms`. |
| `visibility` | `"all"` or `"active"`. |

`background`, `float.zindex`, `float.blend`, `float.hide_on_cursor`,
`providers`, `backend`, `mouse`, exclusions, `update`, `content_glyph`, and
`enabled` are not preset fields. You set `background.blend` only in the root
minimap options. A preset can set `visibility` and `autohide`, but a profile
cannot. A profile can set `float.zindex`, `float.blend`, and
`float.hide_on_cursor`.

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "review-map",
        presets = {
            ["review-map"] = {
                extends = "default",
                width = 12,
                float = {
                    placement = { anchor = "NW", col = 1 },
                },
                overlays = {
                    types = {
                        Error = { priority = 0 },
                        Hint = false,
                        GitChange = { highlight = "DiffChange" },
                    },
                },
                show_viewport = false,
            },
        },
        providers = {
            diagnostic = true,
            gitsigns = true,
        },
    },
})
```

Minimap presets use the same rules as scrollbar presets for inheritance, local
overrides of a built-in name, and precedence. The precedence is the neutral
defaults, then the selected preset chain, then the root minimap options. Keyed
`overlays.types` entries deep-merge through these layers. A later layer can
re-enable a type that an earlier layer set to `false`.

## Related

- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Minimap configuration](minimap/configuration.md)
- [Migration](migration.md)
