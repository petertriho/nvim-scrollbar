# Diagnostic Provider

The diagnostic provider is enabled by default and renders Neovim's native
diagnostics for each eligible buffer. It has no external dependency.

## Setup And Defaults

`providers.diagnostic` is a boolean; provider-specific table options are not
accepted.

```lua
require("scrollbar").setup({
    providers = {
        diagnostic = true,
    },
})
```

Diagnostics map to configured mark types as follows:

| Neovim severity | Mark type | Text | Priority | Highlight source |
| --- | --- | --- | --- | --- |
| `ERROR` | `Error` | `{ "-", "=" }` | `2` | `DiagnosticVirtualTextError` |
| `WARN` | `Warn` | `{ "-", "=" }` | `3` | `DiagnosticVirtualTextWarn` |
| `INFO` | `Info` | `{ "-", "=" }` | `4` | `DiagnosticVirtualTextInfo` |
| `HINT` | `Hint` | `{ "-", "=" }` | `5` | `DiagnosticVirtualTextHint` |
| Unknown | `Misc` | `{ "-", "=" }` | `6` | `Normal` |

All five types default to column `1`. The two text values are density variants:
multiple marks of the same type compressed into one rendered row use the second
variant. Lower numeric priorities win overlaps.

## Data And Scope

The provider reads `vim.diagnostic.get(bufnr)`, including diagnostics from all
native diagnostic namespaces. It emits one zero-based mark per diagnostic and
sorts marks by source line, then mark type.

Marks are buffer-scoped and are shared by every source window displaying that
buffer. Invalid, unloaded, excluded, or over-`max_lines` buffers produce no
diagnostic marks.

ALE and Coc data are not read through this provider unless those tools also
publish into `vim.diagnostic`; their dedicated providers are separate and are
disabled by default.

## Updates

The provider collects existing diagnostics during setup and replaces the
affected buffer's marks on `DiagnosticChanged`. An empty diagnostic list clears
its marks. `:ScrollbarRefresh` performs an explicit refresh for eligible source
buffers.

Only the changed buffer is recollected, but all source windows displaying that
buffer are rerendered from the shared result.

## Customization

Customize the severity mark types under `marks`:

```lua
require("scrollbar").setup({
    float = { width = 2 },
    marks = {
        Error = {
            text = { "E", "!" },
            column = 1,
            priority = 1,
            highlight = "DiagnosticError",
        },
        Warn = {
            text = "W",
            column = 2,
            priority = 2,
            highlight = "DiagnosticWarn",
        },
    },
})
```

`Error`, `Warn`, `Info`, and `Hint` are shared mark types. Changing them also
changes enabled ALE or Coc marks of the same type. For provider-specific
filtering or styling, disable this provider and publish distinct types from a
[custom provider](custom.md).

## Limitations And Troubleshooting

- There are no built-in namespace, source, severity, or message filters. The
  provider mirrors the complete result of `vim.diagnostic.get(bufnr)`.
- Rendering can combine marks that map to the same scrollbar row. Density,
  columns, and priorities determine the visible cells; clicking a visible mark
  uses its exact stored source-line target.
- To verify the source data, run
  `:lua print(vim.inspect(vim.diagnostic.get(0)))`. If it is empty, the issue is
  upstream of the scrollbar provider.
- If source data exists but marks do not appear, check `providers.diagnostic`,
  buffer exclusions, `max_lines`, mark columns and priorities, then run
  `:ScrollbarRefresh`.

## Related

- [Provider index](README.md)
- [Custom providers](custom.md)
- [Configuration](../configuration.md)
