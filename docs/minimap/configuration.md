# Minimap Configuration

The minimap is configured via the top-level `minimap` block passed to
`require("scrollbar").setup`. Its rendering block is independent of the
`scrollbar` rendering block; each owns its own schema, scheduler, renderer,
mouse, presets, and profiles. Provider lifecycle and storage are shared, with
one provider instance serving the enabled scrollbar and minimap consumers.

The minimap defaults to `enabled = false`. Omitting the block does not
change scrollbar behavior.

## Schema

```lua
require("scrollbar").setup({
    scrollbar = {},
    minimap = {
        enabled = false,
        visibility = "all",
        set_highlights = true,
        max_lines = false,
        autohide = { enabled = false, delay_ms = 1000 },
        float = {
            zindex = 50,
            blend = 0,
            placement = {
                relative = "window",
                anchor = "NE",
                row = 0,
                col = 0,
                gutter = "overlap",
                gutter_position = "inner",
            },
        },
        width = 16,
        height = false,
        mouse = { enabled = true },
        backend = "worker",
        update = {
            events = {
                "BufEnter", "BufWinEnter", "WinEnter", "WinScrolled",
                "WinResized", "VimResized", "CursorMoved", "CursorMovedI",
                "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT",
                "WinClosed", "BufDelete", "BufWipeout", "ColorScheme",
            },
            interval_ms = 50,
        },
        excluded_buftypes = {},
        excluded_filetypes = {},
        overlays = {
            enabled = true,
            types = {}, -- derived from configured scrollbar marks except Cursor
        },
        providers = {
            cursor = true,
            diagnostic = true,
            search = { backend = "worker" },
            marks = { letters = true, numbers = false },
            gitsigns = false,
            mini_diff = false,
            signify = false,
            vgit = false,
            ale = false,
            coc = false,
            treesitter = false,
            lsp_semantic_tokens = false,
        },
        show_viewport = true,
        content_glyphs = { top = "▀", bottom = "▄", both = "█" },
    },
})
```

### Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `false` | Master toggle. When `false`, no worker, scheduler, renderer, or minimap commands remain active. |
| `visibility` | `"all"` \| `"active"` | `"all"` | Matches the scrollbar's visibility semantics. |
| `set_highlights` | boolean | `true` | Generates static minimap groups and ordinary `ScrollbarMinimap<Type>` overlay groups. Public names are user-preserving default links; private and profile-internal definitions refresh on setup and on `ColorScheme` when that event remains in `update.events`. |
| `max_lines` | false \| integer | `false` | Skip rendering for buffers with more than this many lines. |
| `autohide.enabled` | boolean | `false` | Reveal source minimaps on configured cursor/scroll activity, then conceal each after its inactivity deadline. |
| `autohide.delay_ms` | integer | `1000` | Hide delay after the last activity in a source window. |
| `float.zindex` | integer | `50` | `nvim_open_win` z-index. |
| `float.blend` | integer | `0` | Floating-window pseudo-transparency (`winblend`), 0-100. The default `0` keeps the minimap surface solid. |
| `float.placement.relative` | `"window"` \| `"editor"` | `"window"` | Float positioning reference. `"editor"` renders only the active source window's minimap (one editor-wide float that tracks focus). |
| `float.placement.anchor` | `"NW"` \| `"NE"` \| `"SW"` \| `"SE"` | `"NE"` | Corner used as the row/col origin. |
| `float.placement.row` | integer | `0` | Row offset from the anchor. |
| `float.placement.col` | integer | `0` | Column offset from the anchor. |
| `float.placement.gutter` | `"avoid"` \| `"overlap"` | `"overlap"` | Reserved for parity with the scrollbar; the minimap does not reserve `statuscolumn` cells. |
| `float.placement.gutter_position` | `"inner"` \| `"outer"` | `"inner"` | Reserved for parity with the scrollbar. |
| `width` | false \| integer | `16` | Minimap grid width in cells. `false` falls back to 16 columns. |
| `height` | false \| integer | `false` | Minimap grid height. `false` means the source window height. |
| `mouse.enabled` | boolean | `true` | Attaches `<LeftMouse>`, `<LeftDrag>`, `<LeftRelease>` keymaps when `true`. |
| `backend` | `"worker"` \| `"sync"` | `"worker"` | Selects an incrementally mirrored child process or inline parent execution for optional Treesitter collection, semantic composition, and squashing. It does not change provider-specific backends such as `providers.search.backend`. |
| `update.events` | string[] | See below | Closed allow-list of Neovim autocmds that schedule a re-render. |
| `update.interval_ms` | integer | `50` | Coalescing interval between renders. `0` flushes as fast as possible. |
| `excluded_buftypes` | string[] | `{}` | Skip buffers whose `buftype` matches. |
| `excluded_filetypes` | string[] | `{}` | Skip buffers whose `filetype` matches. |
| `overlays.enabled` | boolean | `true` | Whether store marks project onto the minimap. |
| `overlays.types` | table<string, false \| `{ priority?, highlight? }`> | derived scrollbar specs except `Cursor` | Keyed ordinary-overlay specs. Entries deep-merge with derived defaults; `false` disables one type. A minimap-only custom type must supply both fields. |
| `providers` | table | See below | Setup-level built-in provider demand for the minimap. Presets and profiles cannot override this table. |
| `show_viewport` | boolean | `true` | Apply a non-destructive background tint across projected viewport rows. |
| `content_glyphs` | table | `{ top = "▀", bottom = "▄", both = "█" }` | Glyphs used for squashed content cells: `top` for upper-half-filled, `bottom` for lower-half-filled, `both` for both-halves-filled. Each must be a single-width glyph. Set e.g. `{ top = "▘", bottom = "▖", both = "▌" }` for small quadrant squares, or any chars (including Nerd Font glyphs). Defaults to the classic half/full blocks. |
| `preset` | string | — | Name of a preset to apply (built-in or user-defined). |
| `presets` | table | — | User-defined preset definitions. |
| `profiles` | table[] | — | Ordered profile variants; first match wins. |

## Provider Defaults

`minimap.providers` uses the same built-in provider manager and store as the
scrollbar. Demand is compiled once during setup: a built-in provider is active
when at least one supported consumer requests it. A disabled minimap contributes
no demand. Collection and resource ownership are shared, but each consumer
keeps independent eligibility and rendering.

| Provider | Default | Minimap output |
| --- | --- | --- |
| `cursor` | `true` | Window mark plus exact minimap point. |
| `diagnostic` | `true` | Diagnostic marks. |
| `search` | `{ backend = "worker" }` | Search marks; `true` normalizes to the same backend. |
| `marks` | `{ letters = true, numbers = false }` | Native mark positions. |
| `gitsigns` | `false` | Git marks from gitsigns.nvim. |
| `mini_diff` | `false` | Git marks from mini.diff. |
| `signify` | `false` | Git marks from vim-signify. |
| `vgit` | `false` | Git marks from vgit.nvim. |
| `ale` | `false` | ALE diagnostic marks. |
| `coc` | `false` | coc.nvim diagnostic marks. |
| `treesitter` | `false` | Source byte spans collected in the selected minimap backend. |
| `lsp_semantic_tokens` | `false` | Parent-side semantic-token spans. |

`search` and `marks` are the only table-valued entries. If both consumers
request one of them with explicit tables, those tables must normalize to equal
options; conflicting scrollbar and minimap options are setup errors. All other
built-ins are booleans. See the dedicated [Treesitter](../providers/treesitter.md)
and [LSP semantic-token](../providers/lsp_semantic_tokens.md) guides.

## Update Events

The default events list is intentionally narrower than the scrollbar's,
because most scrollbar-specific events do not affect minimap content:

```
BufEnter, BufWinEnter, WinEnter, WinScrolled, WinResized, VimResized,
CursorMoved, CursorMovedI, TextChanged, TextChangedI, TextChangedP,
TextChangedT, WinClosed, BufDelete, BufWipeout, ColorScheme
```

Dropping `CursorMoved` removes the minimap scheduler's own cursor-activity
invalidation and autohide activity handling. It does not disable provider-owned
events: the default cursor provider can still publish a new minimap point until
`minimap.providers.cursor = false`. Every accepted event name is validated
against a closed allow-list at setup; typos are setup errors.

## Backends

The minimap ships two interchangeable backends:

- `"worker"` (default) starts one embedded headless child Neovim and mirrors
  requested source buffers into it using an initial chunked snapshot followed
  by incremental line deltas. The child is launched via
  `vim.fn.jobstart({ vim.v.progpath, "--embed", "--headless",
  "-u", "NONE", "-i", "NONE", "--noplugin" }, { rpc = true })`, runs
  injected minimap code, and returns the cell grid.
- `"sync"` reads the parent buffer and runs the same semantic composition and
  squash inline on the main thread. It starts no minimap child process.

Both backends feed the same pure `squash.lua` algorithm, so cell output is
bit-identical for the same text and spans. On worker failure the active runtime
switches to the sync path; a later `setup()` may attempt to start a new worker.

Treesitter is collected only when `minimap.providers.treesitter = true`: in the
child for `"worker"`, or in the parent for `"sync"`. Parent-executed semantic
providers such as LSP publish spans to the shared store. Before a worker squash,
the parent sends those spans as a semantic snapshot with a revision; stale
worker results whose buffer version, generation, or semantic revision no longer
matches are discarded. LSP requests themselves always run in the parent and
are independent of this backend setting.

## Presets

A starter `default` preset is shipped:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "default",
    },
})
```

Custom presets use the same `extends` inheritance rules as the scrollbar.
Keyed overlay entries deep-merge through the preset chain and root options:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "narrow",
        presets = {
            narrow = {
                extends = "default",
                width = 10,
                overlays = {
                    types = {
                        Error = { priority = 0 },
                        Hint = false,
                    },
                },
                show_viewport = false,
            },
        },
        providers = {
            treesitter = true,
        },
    },
})
```

Provider demand remains at the minimap root because presets are presentation
only. See [Presets](../presets.md#minimap-presets) for the exact allow-list.

## Profiles

Profiles work exactly like the scrollbar's: first-match precedence on
`filetypes`, `buftypes`, and `when` predicates, with per-variant `preset`
and `config` overrides:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        profiles = {
            {
                match = { filetypes = { "lua" } },
                config = { width = 60 },
            },
        },
    },
})
```

A predicate error falls back to the root config and notifies once per
distinct error message.

Profile `config` blocks may override display options such as dimensions,
placement, overlays, mouse behavior, and content glyphs. They cannot set
`providers`; the selected root setup demand applies to every window for the
shared provider lifecycle.

Overlay specs resolve in this order: derived scrollbar defaults, selected
minimap preset, root minimap entries, then the matching minimap profile. A
later `{}` or partial spec can re-enable an earlier `false` entry when a derived
fallback exists. Scrollbar and minimap profiles are independent; they are not
paired by declaration index.

## Highlights

When `set_highlights = true`, the minimap defines these static public groups
with theme-owned default links:

| Group | Default link | Role |
| --- | --- | --- |
| `ScrollbarMinimapBase` | `NormalFloat` | Solid float surface. |
| `ScrollbarMinimapContent` | `Comment` | Monochrome highlight for occupied cells without a syntax capture. |
| `ScrollbarMinimapViewport` | `CursorLine` | Projected viewport background tint. |
| `ScrollbarMinimapCursor` | `Cursor` | Exact projected cursor-cell accent. |

Each enabled ordinary type also receives a public `ScrollbarMinimap<Type>`
group, such as `ScrollbarMinimapError`, `ScrollbarMinimapSearch`, or
`ScrollbarMinimapGitAdd`. String sources contribute their resolved foreground;
direct tables are copied. Public definitions that already exist are not
overwritten. Automatic profiles use internal groups such as
`ScrollbarMinimapProfile1.Search` so simultaneous variants remain isolated.

With `set_highlights = false`, setup and `ColorScheme` write no minimap groups,
and every profile renders through canonical `ScrollbarMinimap<Type>` names.
Define those names yourself in manual mode. A colorscheme may clear user groups,
so reapply them from your own `ColorScheme` callback when needed:

```lua
local function set_minimap_highlights()
    vim.api.nvim_set_hl(0, "ScrollbarMinimapBase", { bg = "#161821" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapContent", { fg = "#657080" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapViewport", { bg = "#252a38" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapCursor", { fg = "#ffffff", bg = "#7aa2f7" })
    vim.api.nvim_set_hl(0, "ScrollbarMinimapSearch", { fg = "#ff9e64" })
end

set_minimap_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = set_minimap_highlights })
```

## Validation

The validator mirrors the scrollbar's strict-whitelist rules at every
level. Unknown top-level or built-in provider keys, unknown nested keys,
invalid enum values, non-dense event lists, duplicate events, numeric overlay
keys, malformed type names, unknown spec fields, invalid priorities or
highlights, and incomplete minimap-only specs all fail setup with a
`[scrollbar.nvim]`-prefixed error. The old dense string-list overlay schema is
not accepted. `Base`, `Content`, `Viewport`, and `Cursor` are reserved because
their canonical names belong to static minimap layers. Setup also rejects a
scrollbar/minimap type pair that would claim the same public highlight group,
such as scrollbar `MinimapSearch` and minimap `Search`. The same ownership check
rejects scrollbar names such as `Track`, `Handle`, or `SearchThumb` when they
would collide with fixed, overlap, pressed, or legacy groups.

## Related

- [Layout](layout.md)
- [Overlays](overlays.md)
- [Mouse](mouse.md)
- [Treesitter provider](../providers/treesitter.md)
- [LSP semantic tokens](../providers/lsp_semantic_tokens.md)
- [Migration](../migration.md)
