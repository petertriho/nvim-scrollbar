# Coc Provider

The `coc` provider renders diagnostics returned by
[coc.nvim](https://github.com/neoclide/coc.nvim). It is disabled by default and
has no provider-specific options.

## Setup

Install coc.nvim and enable the provider:

```lua
require("scrollbar").setup({
    providers = {
        coc = true,
    },
})
```

The provider calls `CocActionAsync("diagnosticList", callback)` and does not
configure Coc extensions or diagnostic production.

## Data And Severity Mapping

Each successful response is treated as the complete diagnostic list across
URIs, grouped by Neovim buffer, and published as a full replacement of the
provider cache.

| Coc severity | Scrollbar mark type |
| --- | --- |
| `Error` | `Error` |
| `Warning` | `Warn` |
| `Information` | `Info` |
| `Hint` | `Hint` |

Diagnostics without a supported severity, URI, range start, numeric line, or
valid Neovim buffer are ignored.

## Updates And Refreshes

- Setup immediately starts one asynchronous `diagnosticList` request.
- `User CocDiagnosticChange` starts another asynchronous full-list request.
- A successful callback replaces all cached Coc marks. Buffers present in the
  previous cache but absent from the new response are published with no marks.
- Callbacks belonging to an old scrollbar setup or a disposed provider are
  ignored.
- No callback completion ordering is promised for multiple requests that are
  in flight at the same time.

`:ScrollbarRefresh` republishes the existing Coc cache for buffers in current
source windows and rerenders it; it does not start a new
`CocActionAsync("diagnosticList", ...)` request. A normal
`CocDiagnosticChange` event starts a fresh request.

## Appearance

Coc uses the shared diagnostic mark types:

```lua
require("scrollbar").setup({
    providers = { coc = true },
    marks = {
        Error = { text = "E" },
        Warn = { text = "W" },
        Info = { text = "I" },
        Hint = { text = "H" },
    },
})
```

The normal `text`, `column`, `priority`, and `highlight` options apply. Changes
to these shared types also affect other diagnostic providers.

## Failure And Stale-Data Behavior

- If `CocActionAsync` is unavailable or throws while starting a request, setup
  remains usable and the current cache is unchanged.
- If a callback reports an error, that response is ignored and the previous
  marks remain visible. They can therefore be stale until a later successful
  `CocDiagnosticChange` request completes.
- A successful non-table response is treated as an empty full list and clears
  the previous cache.
- Store validation can reject marks that do not fit the current buffer; only
  this provider's marks for that buffer are cleared.
- Disposing or reconfiguring scrollbar clears Coc's cache and marks. Late
  callbacks from that older setup cannot restore them.

## Troubleshooting

- Confirm Coc is running with `:CocInfo` and that Coc reports diagnostics for
  the file.
- Run `:doautocmd User CocDiagnosticChange` to ask the provider to start a new
  asynchronous list request. `:ScrollbarRefresh` is not equivalent.
- If old marks remain after a Coc error, wait for or trigger another successful
  diagnostic-change request.
- If severity colors are unexpected, inspect or override the shared `Error`,
  `Warn`, `Info`, and `Hint` mark configurations.

## Related Links

- [coc.nvim](https://github.com/neoclide/coc.nvim)
- [Provider index](README.md)
- [Highlight configuration](../highlights.md)
