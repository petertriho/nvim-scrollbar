# Providers

Built-in providers publish ordinary typed marks, minimap semantic spans, or
minimap points for eligible source targets. The top-level `providers` table
controls collection. The mark types and the scrollbar `layout` control
rendering.

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
| [`treesitter`](treesitter.md) | unavailable | on | Buffer minimap byte spans | Installed parser |
| [`lsp_semantic_tokens`](lsp_semantic_tokens.md) | unavailable | off | Buffer minimap byte spans | Attached LSP client |

You configure every built-in provider once, in the top-level `providers`
table. These are the defaults:

```lua
require("scrollbar").setup({
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
        treesitter = true,
        lsp_semantic_tokens = false,
    },
})
```

Each entry is `false`, `true`, or a table:

- `false` turns off the provider.
- `true` turns on the provider for every enabled renderer that supports it.
- A table turns on the provider. It holds the provider options and the
  optional `scrollbar` and `minimap` booleans, which default to `true`.

```lua
require("scrollbar").setup({
    providers = {
        gitsigns = true,                                -- both renderers
        diagnostic = { minimap = false },               -- scrollbar only
        coc = { scrollbar = false },                    -- minimap only
        search = { incsearch = true, minimap = false }, -- options and targets
    },
})
```

Only `search` and `marks` have options. See [Search](search.md) and
[Marks](marks.md). `treesitter` and `lsp_semantic_tokens` support only the
minimap, so `scrollbar = true` on them is a setup error. Unknown provider
names and unknown option keys are also errors. To add a
custom data source, register it through the [custom provider API](custom.md).

## Shared Providers

A built-in provider runs once, with one option set, when at least one enabled
renderer requests it. Each renderer shows only the output of the providers
that target it. A provider does not refresh for a renderer that it does not
target. A disabled renderer requests no providers. See
[Configuration](../configuration.md#providers).

Provider targets control what runs. Mark types control what shows. Each
provider publishes types from the top-level `marks` registry, which sets
`text`, `priority`, and `highlight` for both renderers. `scrollbar.marks.<Type>`
and `minimap.marks.<Type>` override these fields for one renderer, or hide the
type with `false`. A hidden type is still accepted from providers. It is not
drawn. Route the scrollbar types into explicit or catch-all lanes under
scrollbar `layout`. See [Configuration](../configuration.md#marks).

In one scrollbar lane or one minimap row, the lower numeric priority wins.
Minimap spans and points use the opposite direction: the higher numeric value
wins.

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
