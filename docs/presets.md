# Presets

Presets are setup-local presentation baselines. They can change `layout`,
`track`, `thumb`, `marks`, and `float.placement`; they cannot change providers,
visibility, geometry mode, mouse behavior, exclusions, autohide, or performance
options.

## Built-ins

The catalog contains twelve colorscheme-aware layouts:

- General/editor layouts: `vscode`, `zed`, `intellij`, `gvim`, `eclipse`,
  `sublime`, `emacs`, `xcode`.
- Task-oriented: `minimal`, `review`, `search`, `navigate`.

```lua
require("scrollbar").setup({ preset = "review" })
```

### General/Editor Layouts

- `vscode`: three overview-ruler columns. Git-family types use the inner lane,
  remaining types use the center catch-all, and diagnostics use the outer lane.
  Track and thumb span all three; marks are below the thumb.
- `zed`: one compact `track -> thumb -> marks` column, so marks remain above the
  thumb.
- `intellij`: one track/thumb column beside a transparent diagnostic and
  catch-all stripe.
- `gvim`: a solid two-column conventional scrollbar without annotations.
- `eclipse`: a bar plus diagnostic, navigation, and catch-all annotation lanes.
- `sublime`: a trackless translucent thumb with all marks above it.
- `emacs`: a west-anchored bar at the outer edge of a dedicated gutter
  reservation, with an inward diagnostic fringe.
- `xcode`: a compact bar with navigation and diagnostic stripes.

Editor-named presets approximate scrollbar and annotation structure in terminal
cells. They do not implement minimaps or claim pixel-perfect GUI fidelity.

### Task-Oriented

- `minimal`: a thumb-only overlay with no track or marks.
- `review`: separate Git-family, track/thumb, and diagnostic lanes. Search,
  cursor, named, and uncategorized marks are intentionally omitted.
- `search`: one compact track/thumb column with only cursor and search marks.
- `navigate`: a track/thumb/cursor column beside an expandable named-mark lane.
  Diagnostics, search, Git, and catch-all marks are intentionally omitted.

The exact tested structures are:

```lua
local DIAGNOSTICS = { "Error", "Warn", "Info", "Hint" }
local GIT_TYPES = {
    "GitAdd", "GitChange", "GitDelete",
    "MiniDiffAdd", "MiniDiffChange", "MiniDiffDelete",
    "SignifyAdd", "SignifyChange", "SignifyDelete",
    "VGitAdd", "VGitChange", "VGitDelete",
}

-- vscode
layout = {
    direction = "auto",
    columns = {
        { "track", { kind = "marks", types = GIT_TYPES }, "thumb" },
        { "track", "marks", "thumb" },
        { "track", { kind = "marks", types = DIAGNOSTICS }, "thumb" },
    },
}

-- zed
layout = { direction = "auto", columns = { { "track", "thumb", "marks" } } }

-- intellij
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb" },
        { { kind = "marks", types = DIAGNOSTICS }, "marks" },
    },
}

-- minimal
layout = { direction = "auto", columns = { { "thumb" } } }

-- review
layout = {
    direction = "auto",
    columns = {
        { { kind = "marks", types = GIT_TYPES } },
        { "track", "thumb" },
        { { kind = "marks", types = DIAGNOSTICS } },
    },
}

-- search
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb", { kind = "marks", types = { "Cursor", "Search" } } },
    },
}

-- navigate
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb", { kind = "marks", types = { "Cursor" } } },
        { { kind = "marks", types = { "Mark" }, max_width = 8 } },
    },
}

-- gvim
layout = {
    direction = "auto",
    columns = { { "track", "thumb" }, { "track", "thumb" } },
}

-- eclipse
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb" },
        { { kind = "marks", types = DIAGNOSTICS } },
        { { kind = "marks", types = { "Cursor", "Search", "Mark" } } },
        { "marks" },
    },
}

-- sublime
layout = { direction = "auto", columns = { { "thumb", "marks" } } }

-- emacs
float = { placement = { anchor = "NW", gutter = "avoid", gutter_position = "outer" } }
layout = {
    direction = "auto",
    columns = {
        { { kind = "marks", types = DIAGNOSTICS } },
        { "track", "thumb" },
    },
}

-- xcode
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb" },
        { { kind = "marks", types = { "Cursor", "Search", "Mark" } } },
        { { kind = "marks", types = DIAGNOSTICS } },
    },
}
```

`gvim` and `emacs` use `thumb.blend = 0`, `sublime` uses `60`, `intellij`
and `xcode` use `25`, and the other built-ins use `20`.

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
fields are errors. A local entry with any built-in name overlays that built-in
rather than erasing it.

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
