# Migrating From Earlier Releases

This release intentionally rejects the old coordinate schema and implicit
provider refresh ownership. There is no compatibility normalization.

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

## West Gutter Placement

Window-relative `NW` and `SW` placements now default to `gutter = "avoid"`, so
the renderer reserves blank `statuscolumn` cells for the scrollbar instead of
covering existing gutter or buffer-text cells. East anchors and editor-relative
placements are unchanged.

To preserve the earlier window-edge origin for west placements, use:

```lua
require("scrollbar").setup({
    float = {
        placement = {
            gutter = "overlap",
        },
    },
})
```

Other placement fields continue to use their defaults unless overridden.

## Custom Provider Refresh Ownership

Every custom provider with `refresh` or `refresh_window` must now declare who
owns automatic refresh for each implemented scope:

```lua
refresh_owner = {
    buffer = "manager",  -- required when refresh is present
    window = "provider", -- required when refresh_window is present
}
```

Use this direct mapping to retain earlier behavior:

| Earlier provider shape | Required migration |
| --- | --- |
| `refresh` without `setup` | Add `refresh_owner = { buffer = "manager" }` |
| `refresh_window` without `setup` | Add `refresh_owner = { window = "manager" }` |
| Refresh callbacks with `setup` | Add `"provider"` for every implemented scope |
| Both refresh callbacks | Declare both keys; the owners may differ |

The earlier `setup` rule is removed. `setup` and `dispose` now describe resource
lifecycle only and never select scheduling. A provider that used `setup` only
to acquire resources may deliberately choose `"manager"` and remove duplicate
provider-owned event subscriptions. A `"provider"` owner receives no manager
automatic events for that scope and must publish from its own subscriptions.

Initial activation, `:ScrollbarRefresh`, `providers.refresh(bufnr)`, and
`providers.refresh_window(winid)` continue to call applicable callbacks for
both owner values. Manager-owned window refresh keeps the existing
clear-before-refresh behavior on `BufWinEnter` and clears marks when the window
becomes ineligible.

The ownership table must match the callbacks exactly. Missing owners, extra
scope keys without callbacks, unknown keys, invalid owner values, and non-table
`refresh_owner` fields fail during registration. Omission is an intentional
breaking error; there is no compatibility shim or deprecation period.

## Custom Provider Publication Policy

The v2 provider context now exposes live renderer-backed policy queries:

```lua
context.is_buffer_eligible(bufnr)
context.is_source_window(winid)
context.source_windows(bufnr)
```

`set_marks` and `set_window_marks` now return whether publication was accepted,
not only whether mark validation succeeded. A valid target rejected by current
policy is cleared silently and returns `false`; malformed data for an eligible
target and invalid IDs retain validation warnings. Clear operations remain
unconditional.

Buffer publication requires an eligible valid, loaded, non-renderer-owned
buffer within the configured exclusion and `max_lines` rules. It does not
require a currently displayed source window. Window publication requires exact
current membership in `source_windows()`, including active-visibility and
editor-relative profile selection.

Custom window providers can no longer prepublish marks for inactive or
editor-unselected windows. Republish when the window becomes a source, or use
`refresh_owner = { window = "manager" }` to let the manager call
`refresh_window` on source activation. For asynchronous providers, preflight
before expensive work but still handle a
setter returning `false`, because eligibility can change before publication.
There is no compatibility shim or feature flag on the v2 line.

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
