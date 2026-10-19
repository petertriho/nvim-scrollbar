# Coc Provider

The `coc` provider publishes marks for the diagnostics that
[coc.nvim](https://github.com/neoclide/coc.nvim) returns. It is disabled by
default and has no provider-specific options.

## Setup

Install coc.nvim. Then enable the provider:

```lua
require("scrollbar").setup({
    providers = {
        coc = true,
    },
})
```

The provider asks coc.nvim for its full diagnostic list. It does not configure
Coc extensions, and it does not configure how Coc produces diagnostics.

## Marks

| Coc severity | Mark type |
| --- | --- |
| `Error` | `Error` |
| `Warning` | `Warn` |
| `Information` | `Info` |
| `Hint` | `Hint` |

The provider ignores a diagnostic that has no supported severity or that
belongs to no valid Neovim buffer.

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

The standard `text`, `priority`, and `highlight` options apply. A change to
these shared types also affects other diagnostic providers. To show Coc marks
in only one renderer, use a provider target, for example
`coc = { scrollbar = false }`.

## Updates

- Setup requests the diagnostic list.
- `User CocDiagnosticChange` requests the diagnostic list again.
- Each successful response replaces all Coc marks. A buffer that is not in the
  new response loses its Coc marks.
- `:ScrollbarRefresh` shows the marks from the last response again. It does not
  request a new diagnostic list.

## Limitations

- If coc.nvim is not available, scrollbar setup still succeeds, and the current
  marks do not change.
- If Coc reports an error, the provider ignores that response. The previous
  marks stay visible until a later request succeeds.

## Troubleshooting

- Use `:CocInfo` to make sure that Coc is running and that Coc reports
  diagnostics for the file.
- To make the provider request a new diagnostic list, run
  `:doautocmd User CocDiagnosticChange`. `:ScrollbarRefresh` is not equivalent.
- If old marks stay after a Coc error, wait for another successful
  diagnostic-change request, or start one.
- If severity colors are unexpected, inspect or override the shared `Error`,
  `Warn`, `Info`, and `Hint` mark configurations.

## Related Links

- [coc.nvim](https://github.com/neoclide/coc.nvim)
- [Provider index](README.md)
- [Highlight configuration](../highlights.md)
