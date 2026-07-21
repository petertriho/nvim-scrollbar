# LSP Semantic Tokens Minimap Provider

The LSP semantic-token provider requests document tokens from attached clients
and publishes source byte spans for minimap color. It targets only the minimap
and is disabled by default.

## Setup

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        providers = {
            lsp_semantic_tokens = true,
        },
    },
})
```

`minimap.providers.lsp_semantic_tokens` is a setup-level boolean. Each eligible
buffer also needs at least one attached client with a semantic-token legend and
support for full-document or range requests.

On provider activation, every eligible loaded buffer receives an initial
refresh. Buffers without a supporting attached client simply publish no LSP
semantic spans.

## Requests

Each refresh cycle requests every attached supporting client independently. The
provider prefers `textDocument/semanticTokens/full`; if full is unavailable, it
falls back to `textDocument/semanticTokens/range` with a range covering the
whole buffer. Clients supporting neither method contribute no spans.

The provider decodes each client's negotiated `offset_encoding`: `utf-8`,
`utf-16`, and `utf-32` are converted to zero-based byte columns before
publication. Unknown encodings fall back to UTF-16. Tokens crossing source
lines are split into one span per line.

Requests are debounced by 80 ms and scheduled after `LspAttach`, `TextChanged`,
`TextChangedI`, `TextChangedP`, and `LspTokenUpdate`. `LspDetach` removes only
the detached client's spans. `:MinimapRefresh` also schedules requests for the
current minimap source buffers without revealing hidden minimaps.

## Layers And Priority

Every decoded token can publish three highlight layers:

| Layer | Highlight form | Priority |
| --- | --- | --- |
| Type | `@lsp.type.<type>.<filetype>` | `200` |
| Modifier | `@lsp.mod.<modifier>.<filetype>` | `201` |
| Type plus modifier | `@lsp.typemod.<type>.<modifier>.<filetype>` | `202` |

Higher numeric semantic priority wins, so type-modifier layers override
modifier and type layers, and all LSP layers override Treesitter priority
`100`. The groups are normal Neovim highlight groups and follow the user's LSP
highlight configuration.

## Stale Results

Client output is retained while a replacement request is pending. Starting a
new request cancels the prior request for that client when possible, but its
published spans remain visible. Responses are ignored when their request
generation, buffer `changedtick`, client attachment, or provider generation is
stale. Errors and malformed responses also leave the last valid spans intact.

Valid new output replaces only that client's cached spans. The published store
snapshot is the concatenation of current client caches in client-ID order. A
detach removes that client immediately; when no supported clients remain, the
provider publishes an empty replacement.

## Cost And Refresh Limits

These are independent LSP requests made through `client.request`; the provider
does not reuse Neovim's private semantic-token cache. If native semantic tokens
are also active, the language server may therefore receive duplicate full or
range requests. Enable this provider only when minimap semantic color justifies
that server and decoding cost.

The provider does not replace
`vim.lsp.handlers["workspace/semanticTokens/refresh"]` or install another global
handler. A server refresh notification updates the minimap only if Neovim later
emits `LspTokenUpdate` or another watched event. For servers that send only the
workspace refresh notification, run `:MinimapRefresh` or trigger a normal edit
or attachment refresh.

No private Neovim LSP state or global handler override is required, which keeps
the provider isolated from native semantic-token internals at the cost of the
possible duplicate requests above.

## Related

- [Minimap configuration](../minimap/configuration.md)
- [Minimap layout](../minimap/layout.md)
- [Treesitter provider](treesitter.md)
