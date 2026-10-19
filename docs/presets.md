# Presets

A preset is a named set of appearance options. The scrollbar and the minimap
each have their own catalog. You select a preset with `preset` at the root of
the `scrollbar` or `minimap` block, or in a profile of that block. A preset
never changes global options, providers, exclusions, or the shared mark types.
The [showcase](https://github.com/petertriho/nvim-scrollbar/issues/120) has a
screenshot and the setup of every preset.

## Scrollbar Presets

The scrollbar presets set `layout`, `thumb.blend`, and, for `emacs`,
`placement`. The scrollbar catalog has twelve colorscheme-aware layouts:

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
- `zed`: the same three-lane layout as `vscode`. Zed also draws Git,
  highlight, and diagnostic markers in three columns below the thumb.
- `intellij`: a Git lane on the inner side, beside one track/thumb column. The
  other marks are above the thumb in that column, and diagnostics win
  collisions.
- `gvim`: a solid, two-column conventional scrollbar without annotations.
- `eclipse`: one track/thumb column beside an outer overview ruler that shows
  every mark type.
- `sublime`: a translucent thumb without a track, with only search marks above
  it.
- `emacs`: a west-anchored bar at the outer edge of its own gutter reservation,
  with a diagnostic fringe on the inner side.
- `xcode`: a translucent thumb without a track and without marks.

The presets with editor names approximate the scrollbar and annotation
structure of each editor in terminal cells. They do not claim pixel-perfect GUI
fidelity. Some of them have the same layout as another preset, because each
name also pairs with the minimap preset of the same name. See
[Pair the Presets](#pair-the-presets).

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

## Minimap Presets

The minimap presets set `scale`, `encoding`, `columns_per_dot`, `width`, and
`viewport`. `sublime` and `minimal` also set `marks = false`, which hides the
mark overlays. A minimap preset never sets `placement`, `blend`, `height`,
`hide_on_cursor`, or `mouse`. See [The Map](minimap/README.md#the-map) for the
meaning of the grid options.

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "overview",
    },
})
```

| Preset | `scale` | `encoding` | `columns_per_dot` | `width` | Marks |
| --- | --- | --- | --- | --- | --- |
| `vscode` | `"fixed"` | `"braille"` | `4` | `15` | Shown |
| `sublime` | `"fixed"` | `"braille"` | `2` | `20` | Hidden |
| `zed` | `"fixed"` | `"braille"` | `4` | `10` | Shown |
| `xcode` | `"fixed"` | `"block"` | `4` | `12` | Shown |
| `overview` | `"fit"` | `"braille"` | `4` | `10` | Shown |
| `compact` | `"fixed"` | `"braille"` | `8` | `8` | Shown |
| `minimal` | `"fixed"` | `"braille"` | `4` | `12` | Hidden |
| `blocks` | `"fit"` | `"block"` | `4` | `16` | Shown |

Every minimap preset sets `viewport = true`.

- General/editor looks: `vscode`, `sublime`, `zed`, `xcode`. `sublime` uses
  narrow dot columns for a wide, detailed map without overlays. `xcode` draws
  blocks.
- Task-oriented looks: `overview` shows the whole buffer. `compact` is a
  narrow map with wide dot columns. `minimal` is a map without overlays.
  `blocks` shows the whole buffer as blocks.

## Pair the Presets

`vscode`, `sublime`, `zed`, `xcode`, and `minimal` are in both catalogs. Set
both to get the scrollbar and the minimap of one editor:

```lua
require("scrollbar").setup({
    scrollbar = { preset = "zed" },
    minimap = {
        enabled = true,
        preset = "zed",
    },
})
```

The two `preset` options are independent. A scrollbar preset does not select
a minimap preset.

## Customize a Preset

Options next to `preset` win over the preset. Use this to change part of a
built-in preset:

```lua
require("scrollbar").setup({
    scrollbar = {
        preset = "intellij",
        thumb = { blend = 15 },
        layout = {
            columns = {
                { "track", "thumb" },
                { { types = { "Error", "Warn" } }, "marks" },
            },
        },
    },
})
```

The same rule applies to a minimap preset. A `marks` table next to the preset
replaces the `marks = false` of `sublime` or `minimal`, so the overlays show:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "minimal",
        marks = { Hint = false },
    },
})
```

To reuse the same options in several places, put them in a Lua table. See
[Profiles](configuration.md#profiles).

## Precedence

The scrollbar and the minimap use the same precedence. Later layers win:

1. The plugin defaults.
2. The root `preset`.
3. The root options.
4. The profile `preset`.
5. The profile options.

A profile preset wins over the root options. Root values that the profile
preset does not set stay in effect. Dense lists, such as `layout.columns`,
descriptor `types`, and mark `text`, replace the earlier value. See
[Precedence](configuration.md#precedence).

## Related

- [Configuration](configuration.md)
- [Minimap](minimap/README.md)
- [Minimap configuration](minimap/configuration.md#profiles)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
