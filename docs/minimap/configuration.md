# Minimap Configuration

You configure the minimap in the top-level `minimap` block that you pass to
`require("scrollbar").setup`. The `minimap` block is independent of the
`scrollbar` block. Each block has its own schema, presets, and profiles. The
two blocks share the built-in providers. For an overview of the minimap, see
[Minimap](README.md).

The minimap defaults to `enabled = false`. If you omit the block, the scrollbar
behavior does not change.

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
        background = { blend = false },
        float = {
            zindex = 50,
            blend = 0,
            hide_on_cursor = true,
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
        content_glyph = "█",
    },
})
```

### Fields

| Field | Type | Default | Description |
| --- | --- | --- | --- |
| `enabled` | boolean | `false` | Main toggle. When `false`, the minimap does not render, and setup creates no minimap commands. |
| `visibility` | `"all"` \| `"active"` | `"all"` | Uses the same visibility rules as the scrollbar. |
| `set_highlights` | boolean | `true` | Creates the static minimap groups and the ordinary `ScrollbarMinimap<Type>` overlay groups as default links, so user definitions are kept. The groups refresh on setup, and on `ColorScheme` when that event is in `update.events`. |
| `max_lines` | false \| integer | `false` | Skips rendering for buffers that have more than this number of lines. |
| `autohide.enabled` | boolean | `false` | Shows the minimaps of source windows on configured cursor or scroll activity. Then hides each minimap after its inactivity deadline. |
| `autohide.delay_ms` | integer | `1000` | Delay before the minimap hides, after the last activity in a source window. |
| `background.blend` | false \| integer | `false` | Blend policy for the base surface. Only the root configuration accepts it. `false` uses the selected `float.blend`. A value in `0..100` overrides only the `ScrollbarMinimapBase` surface. |
| `float.zindex` | integer | `50` | `nvim_open_win` z-index. |
| `float.blend` | integer | `0` | Profile-aware pseudo-transparency for the full float, 0-100. It stays the default blend for the base and for all layers with a background, unless `background.blend` or an explicit highlight blend overrides it. |
| `float.hide_on_cursor` | boolean | `true` | Temporarily hides the minimap of the active source window while the editing cursor overlaps the screen rectangle of the minimap. Profiles can override this option. Presets cannot. |
| `float.placement.relative` | `"window"` \| `"editor"` | `"window"` | Reference for the float position. `"editor"` renders only the minimap of the active source window (one editor-wide float that tracks focus). |
| `float.placement.anchor` | `"NW"` \| `"NE"` \| `"SW"` \| `"SE"` | `"NE"` | Corner used as the row/col origin. |
| `float.placement.row` | integer | `0` | Row offset from the anchor. |
| `float.placement.col` | integer | `0` | Column offset from the anchor. |
| `float.placement.gutter` | `"avoid"` \| `"overlap"` | `"overlap"` | Reserved for parity with the scrollbar. The minimap does not reserve `statuscolumn` cells. |
| `float.placement.gutter_position` | `"inner"` \| `"outer"` | `"inner"` | Reserved for parity with the scrollbar. |
| `width` | false \| integer | `16` | Width of the minimap grid in cells. `false` falls back to 16 columns. |
| `height` | false \| integer | `false` | Height of the minimap grid. `false` uses the height of the source window. |
| `mouse.enabled` | boolean | `true` | When `true`, attaches the `<LeftMouse>`, `<LeftDrag>`, and `<LeftRelease>` keymaps. |
| `backend` | `"worker"` \| `"sync"` | `"worker"` | Selects where Treesitter collection and squashing run: in a child Neovim process, or in the main Neovim process. It does not change provider-specific backends such as `providers.search.backend`. |
| `update.events` | string[] | See below | Closed allow-list of Neovim autocmds that schedule a re-render. |
| `update.interval_ms` | integer | `50` | Coalescing interval between renders. `0` flushes as fast as possible. |
| `excluded_buftypes` | string[] | `{}` | Skips buffers whose `buftype` matches. |
| `excluded_filetypes` | string[] | `{}` | Skips buffers whose `filetype` matches. |
| `overlays.enabled` | boolean | `true` | Controls whether ordinary provider marks show on the minimap. |
| `overlays.types` | table<string, false \| `{ priority?, highlight? }`> | derived scrollbar specs except `Cursor` | Ordinary overlay specs, keyed by type. Entries deep-merge with the derived defaults. `false` disables one type. A minimap-only custom type must supply both fields. |
| `providers` | table | See below | Built-in provider demand for the minimap, at setup level. Presets and profiles cannot override this table. |
| `show_viewport` | boolean | `true` | Applies a non-destructive background tint to the projected viewport rows. |
| `content_glyph` | string | `"█"` | Glyph shown for every occupied canonical cell. It must be non-empty and have a display width of exactly one. Setup accepts single-width ASCII, Unicode, and Nerd Font glyphs. This option changes only the presentation. |
| `preset` | string | — | Name of a preset to apply (built-in or user-defined). |
| `presets` | table | — | User-defined preset definitions. |
| `profiles` | table[] | — | Ordered profile variants. The first match wins. |

## Blend Layers

`float.blend` and `background.blend` control different layers:

- `float.blend` is the profile-aware blend for the full float. If
  `background.blend = false`, the float uses the selected `float.blend`.
- Only the root configuration accepts a numeric `background.blend`. It
  changes only the base surface that comes from `ScrollbarMinimapBase`. It
  works even when `float.blend = 0`. As a result, the base can blend while the
  viewport, cursor, overlay, and semantic backgrounds stay solid.
- An explicit `blend` in a source highlight is kept. Groups that have only a
  foreground keep their text or glyph above the base surface.

The plugin never rewrites the public `ScrollbarMinimap*` groups. A profile can
change `float.blend`, but not `background.blend`.

Neovim implements `winblend` and highlight `blend` as UI pseudo-transparency,
not as per-pixel alpha. The result depends on the active colorscheme and UI.

## Cursor Yielding

With `float.hide_on_cursor = true`, the minimap of the active source window
hides while the editing cursor is inside its screen rectangle. The minimap
shows again when the cursor leaves. Stored cursor positions in inactive splits
do not hide their minimaps. This option is independent of
`minimap.providers.cursor`. For more information, see
[Visibility](../visibility.md).

The check runs when the minimap renders. If you remove `CursorMoved` and
`CursorMovedI` from `update.events`, the hidden state changes only at the next
configured event. To skip the check, set `float.hide_on_cursor = false`.

## Provider Defaults

`minimap.providers` uses the same built-in providers as the scrollbar. A
built-in provider is active when the scrollbar or the minimap requests it. A
disabled minimap requests no providers. Each renderer applies its own
eligibility rules and shows only the providers that it enables.

| Provider | Default | Minimap output |
| --- | --- | --- |
| `cursor` | `true` | Cursor point. |
| `diagnostic` | `true` | Diagnostic marks. |
| `search` | `{ backend = "worker" }` | Search marks. `true` normalizes to the same backend. |
| `marks` | `{ letters = true, numbers = false }` | Native mark positions. |
| `gitsigns` | `false` | Git marks from gitsigns.nvim. |
| `mini_diff` | `false` | Git marks from mini.diff. |
| `signify` | `false` | Git marks from vim-signify. |
| `vgit` | `false` | Git marks from vgit.nvim. |
| `ale` | `false` | ALE diagnostic marks. |
| `coc` | `false` | coc.nvim diagnostic marks. |
| `treesitter` | `false` | Syntax colors from Treesitter. |
| `lsp_semantic_tokens` | `false` | Syntax colors from LSP semantic tokens. |

`search` and `marks` are the only entries that accept a table. If both
renderers request one of these providers with explicit tables, the tables must
normalize to equal options. Conflicting scrollbar and minimap options are setup
errors. All other built-ins are booleans. For more information, see the
[Treesitter](../providers/treesitter.md) and
[LSP semantic-token](../providers/lsp_semantic_tokens.md) guides.

## Update Events

Most scrollbar-specific events do not change the minimap content. For this
reason, the default event list is shorter than the scrollbar event list:

```
BufEnter, BufWinEnter, WinEnter, WinScrolled, WinResized, VimResized,
CursorMoved, CursorMovedI, TextChanged, TextChangedI, TextChangedP,
TextChangedT, WinClosed, BufDelete, BufWipeout, ColorScheme
```

`update.events` accepts the same closed allow-list as the scrollbar. See
[Configuration](../configuration.md#update-cadence). An unknown or duplicate
event name is a setup error.

If you remove `CursorMoved`, cursor movement no longer starts a minimap render,
a cursor-hiding check, or autohide activity. Provider events stay active. As a
result, the cursor provider still updates the cursor point until you set
`minimap.providers.cursor = false`.

## Backends

- `"worker"` (default) runs Treesitter collection and squashing in one
  embedded headless child Neovim process.
- `"sync"` runs them in the main Neovim process. It starts no child process.

Treesitter collection runs only when `minimap.providers.treesitter = true`. If
the worker fails, the minimap switches to the sync backend. A later `setup()`
may try to start a new worker. LSP semantic-token requests always run in the
main process, for both backends.

## Presets

The minimap includes a starter preset named `default`:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        preset = "default",
    },
})
```

Custom presets use the same `extends` inheritance rules as the scrollbar.
Keyed overlay entries deep-merge through the preset chain and the root options:

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

`providers`, `background.blend`, and `content_glyph` stay at the minimap root,
but a profile can override `content_glyph`. Presets cannot set the background
policy, `content_glyph`, or `float.hide_on_cursor`. For the exact allow-list,
see [Presets](../presets.md#minimap-presets).

## Profiles

Minimap profiles work like scrollbar profiles. They match on `filetypes`,
`buftypes`, and `when` predicates, and the first match wins. Each variant can
set `preset` and `config`:

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

If a `when` predicate raises an error, that render uses the root
configuration. A notification appears once for each distinct pair of profile
and error message.

Profile `config` accepts only `width`, `height`, `float` (`zindex`, `blend`,
`hide_on_cursor`, and `placement`), `overlays`, `show_viewport`, `mouse`, and
`content_glyph`. Setup rejects every other field, including `background` and
`providers`. The root `background.blend` and the root providers apply to every
window.

Overlay specs resolve in this order:

1. Derived scrollbar defaults.
2. The selected minimap preset.
3. Root minimap entries.
4. The matching minimap profile.

If a derived default exists, a later `{}` or partial spec can re-enable an
earlier `false` entry. Scrollbar and minimap profiles are independent. They are
not paired by declaration index.

## Highlights

When `set_highlights = true`, the minimap defines these static public groups
with theme-owned default links:

| Group | Default link | Role |
| --- | --- | --- |
| `ScrollbarMinimapBase` | `NormalFloat` | Base float surface. |
| `ScrollbarMinimapContent` | `Comment` | Monochrome highlight for occupied cells without a syntax capture. |
| `ScrollbarMinimapViewport` | `CursorLine` | Projected viewport background tint. |
| `ScrollbarMinimapCursor` | `Cursor` | Exact projected cursor-cell accent. |

Each enabled ordinary type also gets a public `ScrollbarMinimap<Type>` group,
such as `ScrollbarMinimapError`, `ScrollbarMinimapSearch`, or
`ScrollbarMinimapGitAdd`. A string source contributes its resolved foreground.
A direct table is copied. A public definition that already exists is not
overwritten. In automatic mode, each profile gets its own internal groups, so
that profiles that show at the same time can use different definitions.

With `set_highlights = false`, setup and `ColorScheme` write no minimap groups.
Every profile renders through the canonical `ScrollbarMinimap<Type>` names. In
this manual mode, define those names yourself. A colorscheme may clear user
groups. If it does, reapply them from your own `ColorScheme` callback:

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

The validator applies the same strict allow-list rules as the scrollbar, at
every level. These inputs fail setup with an error that starts with
`[nvim-scrollbar]`:

- Unknown top-level keys or built-in provider keys.
- Unknown nested keys.
- Invalid enum values.
- Event lists that are not dense.
- Duplicate events.
- Numeric overlay keys.
- Malformed type names.
- Unknown spec fields.
- Invalid priorities or highlights.
- Incomplete minimap-only specs.

`content_glyph` must be a non-empty string with a display width of one. `Base`,
`Content`, `Viewport`, and `Cursor` are reserved, because their canonical names
belong to the static minimap layers.

Setup also rejects a scrollbar and minimap type pair that claims the same
public highlight group, such as scrollbar `MinimapSearch` and minimap `Search`.
The same ownership check rejects scrollbar names such as `Track`, `Handle`, or
`SearchThumb` when they collide with fixed, overlap, pressed, or legacy groups.

## Related

- [Minimap](README.md)
- [Presets](../presets.md)
- [Treesitter provider](../providers/treesitter.md)
- [LSP semantic tokens](../providers/lsp_semantic_tokens.md)
- [Migration](../migration.md)
