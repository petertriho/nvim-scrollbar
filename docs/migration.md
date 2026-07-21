# Migrating From Earlier Releases

This release restructures the top-level config into per-subsystem blocks, rejects
the old coordinate schema, and removes implicit provider refresh ownership.
There is no compatibility normalization.

## Top-Level Schema Restructure

Every existing top-level config key now lives under `scrollbar = { ... }`. A new
optional `minimap = { ... }` block sits beside it. Both are passed to the same
`require("scrollbar").setup()` call.

Old flat shape:

```lua
require("scrollbar").setup({
    visibility = "active",
    autohide = { enabled = true },
    providers = { search = { incsearch = true } },
})
```

New nested shape:

```lua
require("scrollbar").setup({
    scrollbar = {
        visibility = "active",
        autohide = { enabled = true },
        providers = { search = { incsearch = true } },
    },
})
```

Every scrollbar option — `show`, `visibility`, `max_lines`, `autohide`,
`render`, `float`, `layout`, `track`, `mouse`, `thumb`, `marks`, `providers`,
`excluded_buftypes`, `excluded_filetypes`, `preset`, `presets`, and `profiles` —
moves verbatim into the `scrollbar` block. No scrollbar default changed.

The `minimap` block defaults to `enabled = false`; omitting it does not change
scrollbar behavior. Passing an unknown top-level key (for example a legacy
`float = { ... }`) is now a setup error.

## Configurable Update Cadence

`render.interval_ms` moved to `update.interval_ms`. A new `update.events` list
controls which Neovim autocmds schedule scrollbar invalidations; the default
preserves today's exact set, so existing behavior is unchanged.

Old shape:

```lua
require("scrollbar").setup({
    scrollbar = {
        render = { interval_ms = 16 },
    },
})
```

New shape:

```lua
require("scrollbar").setup({
    scrollbar = {
        update = { interval_ms = 16 },
    },
})
```

`render` still carries `geometry`. `update.events` accepts the closed allow-list
documented in [Configuration](configuration.md#update-cadence).

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
    scrollbar = {
        float = {
            placement = {
                gutter = "overlap",
            },
        },
    },
})
```

Other placement fields continue to use their defaults unless overridden.

## Custom Provider Refresh Ownership

Every custom provider with `refresh`, `refresh_window`, `refresh_minimap`, or
`refresh_minimap_window` must now declare who owns automatic refresh for each
implemented scope:

```lua
refresh_owner = {
    buffer = "manager",          -- required with refresh
    window = "provider",         -- required with refresh_window
    minimap_buffer = "provider", -- required with refresh_minimap
    minimap_window = "manager",  -- required with refresh_minimap_window
}
```

The four callback/scope pairs are:

| Callback | Publication | Required owner key |
| --- | --- | --- |
| `refresh` | Buffer-scoped marks | `buffer` |
| `refresh_window` | Window-scoped marks | `window` |
| `refresh_minimap` | Buffer-scoped minimap spans | `minimap_buffer` |
| `refresh_minimap_window` | Window-scoped minimap points | `minimap_window` |

Use this direct mapping to retain earlier behavior:

| Earlier provider shape | Required migration |
| --- | --- |
| `refresh` without `setup` | Add `refresh_owner = { buffer = "manager" }` |
| `refresh_window` without `setup` | Add `refresh_owner = { window = "manager" }` |
| Refresh callbacks with `setup` | Add `"provider"` for every implemented scope |
| Multiple refresh callbacks | Declare every matching key; the owners may differ |

The earlier `setup` rule is removed. `setup` and `dispose` now describe resource
lifecycle only and never select scheduling. A provider that used `setup` only
to acquire resources may deliberately choose `"manager"` and remove duplicate
provider-owned event subscriptions. A `"provider"` owner receives no manager
automatic events for that scope and must publish from its own subscriptions.

Initial activation calls every applicable callback for both owner values.
`:ScrollbarRefresh` recollects scrollbar mark channels, while
`:MinimapRefresh` recollects both mark and minimap-specific channels requested
by the minimap. `providers.refresh(bufnr)` and
`providers.refresh_window(winid)` remain ownership-independent and can be
filtered by consumer and channel as described below. Manager-owned window and
minimap-window refresh keeps the existing clear-before-refresh behavior on
`BufWinEnter` and clears the corresponding data when the window becomes
ineligible.

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

Automatic generation no longer overwrites public canonical or legacy groups.
The plugin refreshes private definitions and installs public names only as
default links. A user definition made before setup or after setup therefore
survives plugin setup and `ColorScheme` callbacks.

## Earlier Removals

- Neovim 0.11 or newer is required.
- `show_in_active_only` became `visibility = "active"` or `"all"`.
- `folds` became `render.geometry = "line"` or `"screen"`.
- `throttle_ms` became `update.interval_ms` (via `render.interval_ms`).
- The user `autocmd` table was removed.
- The old `handlers` table and direct handler setup APIs became managed
  providers under `require("scrollbar.providers")`.
- `b:scrollbar_marks` was replaced by provider context publication.
- Mark `level` was removed; density comes from row/type/lane buckets.
- Standalone `color`, `color_nr`, `gui`, and `cterm` options remain removed; use
  `highlight` sources or direct highlight tables.

## Minimap Subsystem

A new optional `minimap = { ... }` block sits beside `scrollbar = { ... }`
at the top level. The block defaults to `enabled = false`, so omitting it
does not change scrollbar behavior.

```lua
require("scrollbar").setup({
    scrollbar = {},
    minimap = {
        enabled = true,
    },
})
```

The minimap has its own validator, scheduler, renderer, mouse handler, presets,
profiles, and visibility commands. Runtime visibility is independent:
`MinimapShow`, `MinimapHide`, and `MinimapToggle` do not show or hide the
scrollbar, and the corresponding scrollbar commands do not show or hide the
minimap.

This independence is not complete lifecycle isolation. Both configs are
validated and committed atomically by the same `setup()` call, both renderers
consume the shared provider store, and rerunning `setup()` rebuilds both
subsystems. `minimap.enabled` and `scrollbar.show` are setup-time values, not
mutable runtime switches; rerun `setup()` to change them. See the
[minimap documentation](minimap/README.md) for the complete schema.

An enabled minimap setup registers `MinimapShow`, `MinimapHide`,
`MinimapToggle`, and `MinimapRefresh`.

### Ordinary overlay schema and highlights

`minimap.overlays.types` changed from a dense string list to a keyed map. There
is no compatibility path for the old list.

Before:

```lua
minimap = {
    overlays = {
        types = { "Error", "Warn" },
    },
}
```

After:

```lua
minimap = {
    overlays = {
        types = {
            Error = { priority = 0 }, -- inherits its derived highlight
            Warn = {},               -- inherits both derived fields
            Hint = false,            -- disables one derived type
        },
    },
}
```

Entries deep-merge with defaults derived from compiled scrollbar marks.
Derivation excludes `Cursor`, scans the scrollbar root first, and then takes
each profile-only type from the first scrollbar profile that defines it. A
custom minimap-only type has no fallback and must provide both `priority` and
`highlight`.

The new public groups require unambiguous ownership. Minimap types `Base`,
`Content`, `Viewport`, and `Cursor` are reserved for static layers, and setup
rejects cross-subsystem pairs such as scrollbar `MinimapSearch` plus minimap
`Search` because both map to `ScrollbarMinimapSearch`.
It also rejects scrollbar custom names such as `Track`, `Handle`, or
`SearchThumb` when their canonical groups collide with fixed, overlap, pressed,
or legacy public groups.

Ordinary minimap rendering no longer uses `Scrollbar<Type>` groups:

| Previous ordinary minimap group | New group |
| --- | --- |
| `ScrollbarSearch` | `ScrollbarMinimapSearch` |
| `ScrollbarError` | `ScrollbarMinimapError` |
| `Scrollbar<Type>` | `ScrollbarMinimap<Type>` |

`ScrollbarMinimapBase`, `ScrollbarMinimapContent`,
`ScrollbarMinimapViewport`, and `ScrollbarMinimapCursor` are static groups.
Automatic profile names such as `ScrollbarMinimapProfile1.Search` are internal.
With `minimap.set_highlights = false`, every variant uses the canonical public
names and the plugin writes no minimap groups.

To retain shared manual colors, link both public surfaces explicitly:

```lua
vim.api.nvim_set_hl(0, "ScrollbarMinimapSearch", { link = "ScrollbarSearch" })
vim.api.nvim_set_hl(0, "ScrollbarMinimapError", { link = "ScrollbarError" })
```

### Removed provider shortcuts

Two minimap shortcuts were removed in favor of the shared provider model:

| Removed option | Replacement |
| --- | --- |
| `minimap.syntax_highlighting` | `minimap.providers.treesitter` |
| `minimap.show_cursor_row` | `minimap.providers.cursor` |

Old:

```lua
minimap = {
    enabled = true,
    syntax_highlighting = true,
    show_cursor_row = false,
}
```

New:

```lua
minimap = {
    enabled = true,
    providers = {
        treesitter = true,
        cursor = false,
    },
}
```

Both old keys are setup errors wherever they are supplied. There are no
aliases, compatibility normalization, or deprecation shims.

### Provider demand and shared options

Built-in provider activation is the union of scrollbar demand and demand from
an enabled minimap. A shared provider is instantiated once when either consumer
requests it. `minimap.enabled = false` contributes no built-in provider demand,
so its provider settings neither activate providers nor conflict with active
scrollbar settings.

The store is shared, but rendering is filtered independently. A provider
enabled only for the minimap does not appear in the scrollbar, and a provider
enabled only for the scrollbar does not appear in minimap overlays, semantic
spans, or points.

`search` and `marks` are the two shared providers with table options. When both
consumers request one provider:

- An explicit table on either side takes precedence over `true`.
- Two explicit tables are accepted when their normalized values are equal. For
  example, `search = {}` equals `search = { backend = "worker" }`, and
  `marks = {}` equals `marks = { letters = true, numbers = false }`.
- Two explicit tables with different normalized values fail setup with a
  conflict naming both config paths. The failure is atomic: the previous
  scrollbar config, minimap config, compiled profiles, and provider plan remain
  active.

### Custom minimap providers

A custom provider with no `targets` field remains scrollbar-only. Opt into the
minimap explicitly, either alone or beside the scrollbar:

```lua
targets = { minimap = true }
-- or
targets = { scrollbar = true, minimap = true }
```

Minimap-specific callbacks use the two new store channels. They publish dense
complete-replacement lists in zero-based source-buffer byte coordinates:

```lua
require("scrollbar.providers").register({
    name = "semantic_example",
    targets = { minimap = true },
    refresh_owner = {
        minimap_buffer = "manager",
        minimap_window = "provider",
    },

    refresh_minimap = function(bufnr, context)
        return {
            {
                line = 0,
                start_col = 0, -- inclusive byte column
                end_col = 4,   -- exclusive byte column
                highlight = "@keyword",
                priority = 100,
            },
        }
    end,

    refresh_minimap_window = function(winid, context)
        return {
            {
                line = 0,
                col = 4, -- byte column
                highlight = "Cursor",
                priority = 20,
            },
        }
    end,
})
```

Span fields are `line`, `start_col`, `end_col`, `highlight`, and `priority`;
point fields are `line`, `col`, `highlight`, and `priority`. Lines and columns
are zero-based, columns are byte offsets, span ends are exclusive, and higher
priority values win composition. A minimap callback requires
`targets.minimap = true` and the matching `minimap_buffer` or `minimap_window`
refresh owner. The exact four-scope ownership rules are listed in
[Custom Provider Refresh Ownership](#custom-provider-refresh-ownership).

Custom providers always execute in the parent Neovim process. Adding a private
`execution = "worker"` field does not move custom setup or callbacks into the
minimap worker. Parent-published spans are copied to the worker as data when the
worker backend performs squash composition; only the built-in Treesitter
provider owns worker execution.

### Provider-aware refresh

The Lua refresh APIs now accept `consumer` and `channel` filters:

```lua
local providers = require("scrollbar.providers")

providers.refresh(bufnr, {
    consumer = "minimap",
    channel = "minimap_spans",
})

providers.refresh_window(winid, {
    consumer = "minimap",
    channel = "minimap_points",
})
```

Buffer refresh channels are `marks` and `minimap_spans`; window refresh
channels are `marks` and `minimap_points`. Omitting `channel` refreshes every
matching channel for the selected consumer. `:MinimapRefresh` uses minimap
consumer filtering, skips scrollbar-only providers, refreshes shared marks plus
spans and points, invalidates minimap windows, and preserves the current hidden
or shown state. `:ScrollbarRefresh` uses scrollbar filtering and does not invoke
minimap-only channels.

### Treesitter and LSP semantic color

`minimap.providers.treesitter = true` uses the built-in Treesitter highlight
query. With the default worker backend, parser startup, parsing, query capture,
and squash composition run in the child Neovim; with the sync backend they run
in the parent. Treesitter needs an installed parser and highlight query, but no
language server, and provides broad syntax coverage at the cost of parser and
query work.

`minimap.providers.lsp_semantic_tokens = true` requests full tokens when the
server supports them and otherwise requests a whole-buffer range from each
attached semantic-token-capable client. It runs asynchronously in the parent,
depends on server support and latency, and can provide more semantic detail.
Its priorities are higher than Treesitter's, so overlapping LSP token type,
modifier, and type-modifier spans override Treesitter captures. Both providers
may be enabled together.

The LSP provider deliberately retains the last successful spans while a newer
request is pending and also retains them after stale, failed, or malformed
responses. They are replaced by a later successful response and removed when a
client detaches, the buffer becomes ineligible, or the provider is disposed.

The provider listens to attach, detach, text-change, and `LspTokenUpdate`
events, but it does not replace or wrap
`vim.lsp.handlers["workspace/semanticTokens/refresh"]`. A server-originated
refresh that does not also lead Neovim to emit `LspTokenUpdate` therefore does
not immediately refresh the minimap; use `:MinimapRefresh` or wait for another
handled event.

### Default placement and width

The minimap default placement changed from `editor`-relative to
`window`-relative, and the default `width` changed from `80` to `16`. Each
source window now gets its own minimap at its north-east corner by default,
matching the scrollbar's default.

To restore the previous single editor-wide minimap that tracked the focused
window:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        float = { placement = { relative = "editor" } },
        width = 80,
    },
})
```

## Related

- [Configuration](configuration.md)
- [Presets](presets.md)
- [Layout and geometry](layout-and-geometry.md)
- [Highlights](highlights.md)
- [Minimap](minimap/README.md)
