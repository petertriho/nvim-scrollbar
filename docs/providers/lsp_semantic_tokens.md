# LSP Semantic Tokens Minimap Provider

The LSP semantic-token provider requests document tokens from attached clients
and publishes source byte spans for minimap color. It targets only the minimap
and is disabled by default.

## Setup

```lua
require("scrollbar").setup({
    providers = {
        lsp_semantic_tokens = true,
    },
    minimap = {
        enabled = true,
    },
})
```

`providers.lsp_semantic_tokens` is a boolean, or a table that contains only the
`scrollbar` and `minimap` target flags. The provider runs only when the minimap
is enabled. Setup rejects `scrollbar = true`. A minimap profile cannot select
the provider. Each eligible buffer also needs at least one attached
client with a semantic-token legend and support for full-document or range
requests.

When the provider activates, every eligible loaded buffer gets an initial
refresh. A buffer without a supporting attached client gets no LSP semantic
spans.

## Requests

Each refresh sends a request to every attached supporting client. The provider
prefers `textDocument/semanticTokens/full`. If the full method is not
available, the provider uses `textDocument/semanticTokens/range` with a range
that covers the whole buffer. A client that supports neither method contributes
no spans.

The provider schedules requests after `LspAttach`, `TextChanged`,
`TextChangedI`, `TextChangedP`, and `LspTokenUpdate`. `LspDetach` removes only
the spans of the detached client. `:MinimapRefresh` also schedules requests for
the current minimap source buffers. It does not show hidden minimaps.

## Layers And Priority

Every decoded token can publish three highlight layers:

| Layer | Highlight form | Priority |
| --- | --- | --- |
| Type | `@lsp.type.<type>.<filetype>` | `200` |
| Modifier | `@lsp.mod.<modifier>.<filetype>` | `201` |
| Type plus modifier | `@lsp.typemod.<type>.<modifier>.<filetype>` | `202` |

Higher numeric semantic priority wins. Thus, the type-plus-modifier layer
overrides the modifier and type layers. All LSP layers override the Treesitter
priority `100`. The groups are normal Neovim highlight groups, and they follow
the user's LSP highlight configuration.

## Stale Results

While a new request is pending, the spans that a client already published stay
visible. Errors, malformed responses, and stale responses also leave the last
valid spans intact. A detach removes the spans of that client immediately. When
no supporting client remains for a buffer, the provider removes the spans of
that buffer.

## Cost And Refresh Limits

The provider sends its own LSP requests. It does not reuse the semantic-token
cache of Neovim. Thus, if native semantic tokens are also active, the language
server may receive duplicate full or range requests. Enable this provider only
when minimap semantic color justifies the server cost and the decoding cost.

The provider does not replace
`vim.lsp.handlers["workspace/semanticTokens/refresh"]` or install another global
handler. A server refresh notification updates the minimap only if Neovim later
emits `LspTokenUpdate` or another watched event. If a server sends only the
workspace refresh notification, run `:MinimapRefresh`. You can also trigger a
normal edit or attachment refresh.

## Related

- [Minimap](../minimap/README.md)
- [Minimap configuration](../minimap/configuration.md)
- [Treesitter provider](treesitter.md)
