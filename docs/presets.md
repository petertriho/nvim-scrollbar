# Presets

A preset is a named set of scrollbar appearance options. You select one with
`preset` at the root of the `scrollbar` block or in a
[profile](configuration.md#profiles). The built-in presets set `layout`,
`thumb.blend`, and, for `emacs`, `placement`. A preset never changes global
options, providers, exclusions, or the shared mark types. The minimap has no
presets.

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
name also pairs with the minimap preset of the same name.

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

To reuse the same options in several places, put them in a Lua table. See
[Profiles](configuration.md#profiles).

## Precedence

Later layers win:

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
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
