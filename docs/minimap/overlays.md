# Minimap Overlays

The minimap subscribes to the same `lua/scrollbar/store.lua` and provider
lifecycle as the scrollbar. Providers publish into independent store channels,
while the scrollbar and minimap render those snapshots separately. The minimap
never mutates provider output while projecting it.

The channels are:

| Channel | Scope | Minimap role |
| --- | --- | --- |
| `marks` | Buffer or window | Ordinary row overlays using configured mark types. |
| `minimap_spans` | Buffer | Source byte ranges composed into squashed cell color. |
| `minimap_points` | Window | Exact source byte positions projected to one minimap cell. |

## Mark Types

By default `overlays.types` copies `priority` and `highlight` from configured
scrollbar marks, excluding `Cursor`. Derivation scans the compiled scrollbar
root first, then profiles in declaration order. Root definitions win for types
they contain; the first profile defining a profile-only type supplies its
fallback. The copied tables are isolated from scrollbar config. The built-in
catalog is:

| Mark type | Source |
| --- | --- |
| `Search` | Search provider (and `compact_search` if used) |
| `Error`, `Warn`, `Info`, `Hint` | Diagnostic providers (built-in, ALE, Coc) |
| `Mark` | Native marks provider |
| `Misc` | Diagnostic fallback and custom provider use. |
| `GitAdd`, `GitChange`, `GitDelete` | gitsigns.nvim |
| `MiniDiffAdd`, `MiniDiffChange`, `MiniDiffDelete` | mini.diff |
| `SignifyAdd`, `SignifyChange`, `SignifyDelete` | vim-signify |
| `VGitAdd`, `VGitChange`, `VGitDelete` | vgit.nvim |

Override or disable selected types with keyed entries. Unspecified defaults
remain enabled:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        overlays = {
            enabled = true,
            types = {
                Error = { priority = 0, highlight = "DiagnosticError" },
                Hint = false,
            },
        },
    },
})
```

Set `overlays.enabled = false` to disable ordinary mark overlays. Semantic spans
and minimap points remain active through their provider channels.

Custom scrollbar types are inherited automatically, so a minimap override can
be partial:

```lua
require("scrollbar").setup({
    scrollbar = {
        marks = {
            CustomReview = {
                text = "!",
                priority = 8,
                highlight = "Special",
            },
        },
    },
    minimap = {
        enabled = true,
        overlays = { types = { CustomReview = { priority = 2 } } },
    },
})
```

A minimap-only custom type is also valid, but has no fallback and therefore
must provide both fields:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        overlays = {
            types = {
                MinimapOnly = { priority = 1, highlight = "Special" },
            },
        },
    },
})
```

Custom names cannot claim an existing public minimap group. `Base`, `Content`,
`Viewport`, and `Cursor` are reserved for static layers. Setup also rejects
cross-subsystem collisions such as scrollbar type `MinimapSearch` combined with
minimap type `Search`.

## Projection

For each published mark the minimap computes a 1-based minimap row using
`v_ratio = max(1, source_line_count / minimap_height)` and
`floor(mark.line / v_ratio) + 1`, clamped to `[1, minimap_height]`. This is a
terminal-row line-mode projection, not the doubled logical-row mapping used for
content and points. After one winning overlay is selected for a row, the
renderer applies the selected compiled minimap group (for example
`ScrollbarMinimapError`, or an internal automatic-profile group) only to
contiguous runs of occupied squash cells on that row.

Occupancy is read from the underlying squash cells, not the displayed glyph,
so custom `content_glyphs` do not change ordinary overlay projection. A fully
empty projected row receives no ordinary overlay extmark, and that signal is
intentionally invisible rather than replaced by an edge marker or full-row
fallback.

Collisions resolve by **`minimap.overlays.types.<Type>.priority`, lowest wins**.
This is independent of scrollbar lane priority. Ties resolve by alphabetical provider name;
further ties resolve by list order within one provider. The winning ordinary
overlay receives renderer priority `3` through `13`. Semantic spans are already
part of cell color, while published points use their own extmark priorities;
the built-in cursor point uses `14` and appears above ordinary overlays.
Ordinary mark collisions are lower-wins, whereas semantic span and minimap
point priorities are higher-wins.

Compact search snapshots are iterated directly with
`search_compact.each`. The minimap does not expand the compact blob into a
temporary mark list.

## Live Updates

The minimap scheduler uses `store.subscribe(callback)`. A changed publication
emits one channel-aware event:

```lua
{
    scope = "buffer", -- or "window"
    channel = "marks", -- or "minimap_spans" / "minimap_points"
    target = bufnr, -- or winid for window scope
    provider = "provider_name",
}
```

Buffer events invalidate every selected minimap window displaying that buffer;
window events invalidate only their source window. The scheduler coalesces the
result through `minimap.update.interval_ms`. Publishing identical output emits
no event.

The store advances mark, minimap-span, and minimap-point revisions
independently. Mark and point changes reproject without a new squash. Enabled
parent-executed span changes advance the renderer's semantic input revision and
request fresh cells for each active dimension. Worker-native Treesitter spans
are published alongside an already accepted cell result, so that publication
does not request the same squash again.

## Read-Only Contract

Ordinary mark projection consumes:

```
{ source_line, minimap_row, mark_type, priority, highlight, provider }
```

Here `highlight` is already the compiled renderer-facing minimap group.

Custom providers can also target the minimap directly with
`targets = { minimap = true }`, `refresh_minimap` for buffer spans, and
`refresh_minimap_window` for window points. These lists are complete
provider-owned replacements and are validated independently from marks.

## Manual Refresh

`:MinimapRefresh` calls the requested minimap providers' `refresh` and
`refresh_minimap` callbacks for current source buffers, then calls
`refresh_window` and `refresh_minimap_window` for current source windows.
Scrollbar-only providers are not refreshed. The command queues rendering but
preserves `:MinimapHide` and autohide-concealed state.

## Related

- [Configuration](configuration.md)
- [Layout](layout.md)
- [Custom providers](../providers/custom.md)
