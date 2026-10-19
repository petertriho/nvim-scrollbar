# Providers

Built-in providers publish ordinary typed marks, minimap semantic spans, or
minimap points for eligible source targets. Provider configuration controls
collection. Scrollbar `layout` and minimap presentation control rendering.

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

`search` and `marks` also accept option tables. See [Search](search.md) and
[Marks](marks.md). All other built-ins are booleans.

The allow-lists are strict. `scrollbar.providers` accepts the first ten names in
the table. `minimap.providers` accepts all twelve. Unknown keys are errors. To
add a custom data source, register it through the
[custom provider API](custom.md).

## Shared Providers

A built-in provider runs once when the scrollbar, the minimap, or both enable
it. Each renderer shows only the output of the providers that it enables. The
two blocks share the `search` and `marks` options. For the rules, see
[Configuration](../configuration.md#providers). A disabled minimap does not
enable providers or affect the shared options.

You configure scrollbar presentation under `scrollbar.marks.<Type>` with
`text`, `priority`, and `highlight`. Route those types into explicit or
catch-all lanes under scrollbar `layout`. You configure ordinary minimap
presentation independently under `minimap.overlays.types.<Type>` with
`priority` and `highlight`. In one scrollbar lane or one minimap row, the lower
numeric priority wins. Minimap spans and points use the opposite direction: the
higher numeric value wins.

## Refresh

Providers do their first refresh during setup. `:ScrollbarRefresh` refreshes
only the providers that the scrollbar uses. `:MinimapRefresh` refreshes only
the providers that the minimap uses, including their minimap spans and points.
Both commands use the current source buffers and windows of their renderer and
queue rendering. They do not show a hidden float or a float that autohide
concealed.

## Optional Integrations

If the dependency of an optional integration is unavailable, the integration
safely emits no marks.

You can enable more than one diff provider at the same time. Each provider owns
its data separately, but the marks can overlap visually. If they overlap, use
typed layout lanes or priorities, or disable the duplicated sources.

## Related

- [Configuration](../configuration.md)
- [Layout and geometry](../layout-and-geometry.md)
- [Treesitter](treesitter.md)
- [LSP semantic tokens](lsp_semantic_tokens.md)
- [Custom providers](custom.md)
