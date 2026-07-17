# Presets

Presets are setup-local presentation baselines. They can change `layout`,
`track`, `thumb`, `marks`, and `float.placement`; they cannot change providers,
visibility, geometry mode, mouse behavior, exclusions, autohide, or performance
options.

## Built-ins

```lua
require("scrollbar").setup({ preset = "vscode" })
require("scrollbar").setup({ preset = "zed" })
require("scrollbar").setup({ preset = "intellij" })
```

These are colorscheme-aware terminal-cell approximations:

- `vscode`: three overview-ruler columns. Git-family types use the inner lane,
  remaining types use the center catch-all, and diagnostics use the outer lane.
  Track and thumb span all three; marks are below the thumb.
- `zed`: one compact `track -> thumb -> marks` column, so marks remain above the
  thumb.
- `intellij`: one track/thumb column beside a transparent diagnostic and
  catch-all stripe.

The exact tested structures are:

```lua
-- vscode
layout = {
    direction = "auto",
    columns = {
        { "track", { kind = "marks", types = {
            "GitAdd", "GitChange", "GitDelete",
            "MiniDiffAdd", "MiniDiffChange", "MiniDiffDelete",
            "SignifyAdd", "SignifyChange", "SignifyDelete",
            "VGitAdd", "VGitChange", "VGitDelete",
        } }, "thumb" },
        { "track", "marks", "thumb" },
        { "track", { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } }, "thumb" },
    },
}

-- zed
layout = { direction = "auto", columns = { { "track", "thumb", "marks" } } }

-- intellij
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb" },
        { { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } }, "marks" },
    },
}
```

`vscode` and `zed` set `thumb.blend = 20`; `intellij` sets it to `25`.

## Local Presets

```lua
require("scrollbar").setup({
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
})
```

One optional `extends` parent is supported. Declaration order does not matter.
Unknown names, unknown parents, cycles, malformed definitions, and disallowed
fields are errors. A local entry named `vscode`, `zed`, or `intellij` overlays
that built-in rather than erasing it.

Registries do not persist across setup calls. Inputs and resolved outputs are
deep-copied, so mutation cannot change built-ins or a later setup. Dense lists
such as `layout.columns`, selector `types`, and mark `text` replace atomically.

## Precedence

1. Neutral plugin defaults.
2. Selected built-in or local preset, including its parent.
3. Root setup options.

Preset `float` accepts only `placement`. Root `float.zindex` and
`float.hide_on_cursor` remain runtime behavior and are never preset-controlled.

## Related

- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Migration](migration.md)
