# Migrating From Earlier Releases

This release intentionally rejects the old coordinate schema. There is no
compatibility normalization.

## Declarative Layout Migration

| Removed option | Replacement |
| --- | --- |
| `float.width` | Number of entries in `layout.columns` |
| top-level `handle` | top-level `thumb` |
| `handle.column` and `handle.width` | Repeat `"thumb"` across one contiguous column span |
| `marks.<Type>.column` | Put the type in an explicit mark descriptor, or use catch-all `"marks"` |
| `providers.marks.max_width` | `max_width` on a lane explicitly selecting `Mark` |

Old one-column configuration:

```lua
float = { width = 1 }
handle = { column = 1, width = 1 }
marks = { Search = { column = 1 } }
```

New equivalent:

```lua
layout = { columns = { { "track", "thumb", "marks" } } }
```

Old wide ruler:

```lua
float = { width = 3 }
handle = { column = 3, width = 1 }
marks = {
    Search = { column = 1 },
    Error = { column = 2 },
}
```

New typed lanes:

```lua
layout = {
    columns = {
        { { kind = "marks", types = { "Search" } } },
        { { kind = "marks", types = { "Error" } }, "marks" },
        { "track", "thumb" },
    },
}
```

Old named-mark expansion:

```lua
providers = { marks = { max_width = 8 } }
```

New lane-local expansion:

```lua
providers = { marks = true }
layout = {
    columns = {
        { "track", "thumb", { kind = "marks", types = { "Mark" }, max_width = 8 } },
        { "marks" },
    },
}
```

The numerical meaning changed: the old value capped total float width; the new
value caps only the `Mark` lane, including its declared base cells.

## Highlight Names

Renderer extmarks now use canonical `ScrollbarThumb`,
`ScrollbarThumbPressed`, `Scrollbar<Type>Thumb`, and
`Scrollbar<Type>ThumbPressed` groups. Automatic highlight mode generates
equivalent legacy Handle aliases. With `set_highlights = false`, no aliases are
generated; manual users must define canonical Thumb groups and `ScrollbarBase`.

## Earlier Removals

- Neovim 0.11 or newer is required.
- `show_in_active_only` became `visibility = "active"` or `"all"`.
- `folds` became `render.geometry = "line"` or `"screen"`.
- `throttle_ms` became `render.interval_ms`.
- The user `autocmd` table was removed.
- The old `handlers` table and direct handler setup APIs became managed
  providers under `require("scrollbar.providers")`.
- `b:scrollbar_marks` was replaced by provider context publication.
- Mark `level` was removed; density comes from row/type/lane buckets.
- Standalone `color`, `color_nr`, `gui`, and `cterm` options remain removed; use
  `highlight` sources or direct highlight tables.

## Related

- [Configuration](configuration.md)
- [Presets](presets.md)
- [Layout and geometry](layout-and-geometry.md)
- [Highlights](highlights.md)
