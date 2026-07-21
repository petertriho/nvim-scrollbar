# Providers

Built-in providers publish ordinary typed marks, minimap semantic spans, or
minimap points for eligible source targets. Provider configuration controls
collection; scrollbar `layout` and minimap presentation control rendering.

## Built-ins

| Provider | Scrollbar | Minimap | Scope and output | Dependency |
| --- | --- | --- | --- | --- |
| [`cursor`](cursor.md) | on | on | Window `Cursor` mark and minimap point | None |
| [`diagnostic`](diagnostic.md) | on | on | Buffer `Error`, `Warn`, `Info`, `Hint`, `Misc` marks | None |
| [`search`](search.md) | on | on | Buffer `Search` marks | None |
| [`marks`](marks.md) | on | on | Buffer `Mark` marks | None |
| [`gitsigns`](gitsigns.md) | off | off | Buffer `GitAdd`, `GitChange`, `GitDelete` marks | gitsigns.nvim |
| [`mini_diff`](mini_diff.md) | off | off | Buffer `MiniDiffAdd`, `MiniDiffChange`, `MiniDiffDelete` marks | mini.diff |
| [`signify`](signify.md) | off | off | Buffer `SignifyAdd`, `SignifyChange`, `SignifyDelete` marks | vim-signify |
| [`vgit`](vgit.md) | off | off | Buffer `VGitAdd`, `VGitChange`, `VGitDelete` marks | vgit.nvim |
| [`ale`](ale.md) | off | off | Buffer `Error`, `Warn` marks | ALE |
| [`coc`](coc.md) | off | off | Buffer `Error`, `Warn`, `Info`, `Hint` marks | coc.nvim |
| [`treesitter`](treesitter.md) | unavailable | off | Buffer minimap byte spans | Installed parser |
| [`lsp_semantic_tokens`](lsp_semantic_tokens.md) | unavailable | off | Buffer minimap byte spans | Attached LSP client |

```lua
require("scrollbar").setup({
    scrollbar = {
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
        },
    },
    minimap = {
        enabled = true,
        providers = {
            cursor = true,
            diagnostic = true,
            search = true,
            marks = true,
            gitsigns = false,
            mini_diff = false,
            signify = false,
            vgit = false,
            ale = false,
            coc = false,
            treesitter = false,
            lsp_semantic_tokens = false,
        },
    },
})
```

`search` accepts `incsearch` and `backend` (`"worker"` or `"sync"`). Omitting
`incsearch` follows `vim.o.incsearch`. `marks` accepts only `letters` and
`numbers`. All other built-ins are booleans.

The allow-lists are strict. `scrollbar.providers` accepts the first ten names in
the table; `minimap.providers` accepts all twelve. Unknown keys are errors;
register custom data sources through the [custom provider API](custom.md).

## Shared Built-in Plan

The two provider blocks compile into one effective built-in plan. A built-in
requested by either renderer has one provider instance, one lifecycle, and one
normalized option set. Ordinary marks are stored once, while each renderer
independently filters them through its own enabled-provider set. Minimap spans
and points are minimap-only channels.

For the table-valued `search` and `marks` options, a table on one side overrides
`true` on the other. Two normalized tables must be equal; equal tables are
accepted and conflicting tables reject the whole setup atomically. A disabled
minimap contributes no demand, option selection, or conflict.

Scrollbar presentation is configured under `scrollbar.marks.<Type>` with
`text`, `priority`, and `highlight`; route those types into explicit or
catch-all lanes under scrollbar `layout`. Ordinary minimap presentation is
configured independently under `minimap.overlays.types.<Type>` with `priority`
and `highlight`. Lower numeric priority wins within one scrollbar lane or one
projected minimap row. Minimap spans and points use the opposite priority
direction: higher numeric values win.

Providers refresh initially during setup. `:ScrollbarRefresh` refreshes ordinary
mark callbacks only for providers consumed by the scrollbar.
`:MinimapRefresh` refreshes ordinary mark callbacks for minimap consumers plus
their minimap span and point callbacks. It does not refresh scrollbar-only
providers. Both commands operate on their renderer's current source buffers and
windows, queue rendering, and preserve hidden/autohide-concealed state.

Changed store publication sends provider- and channel-aware notifications.
The scrollbar scheduler listens to ordinary marks; the minimap scheduler listens
to ordinary marks, spans, and points. The built-in search provider may keep its
matches in a private compact representation, but compact publication still uses
the ordinary `marks` notification channel and is projected without expanding a
public mark list. These notifications are independent of either renderer's
`update.events` autocmd list.

Optional integrations safely emit no marks when their dependency is
unavailable. Treesitter collection runs with the minimap squash backend; LSP
semantic-token collection runs in the parent and publishes spans for transfer
to the minimap worker.

Multiple diff providers may be enabled together. Their data remains separately
owned but can overlap visually; use typed layout lanes, priorities, or disable
duplicated sources.

## Related

- [Configuration](../configuration.md)
- [Layout and geometry](../layout-and-geometry.md)
- [Treesitter](treesitter.md)
- [LSP semantic tokens](lsp_semantic_tokens.md)
- [Custom providers](custom.md)
