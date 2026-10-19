# Diagnostic Provider

The diagnostic provider is enabled by default. It publishes marks for the
native Neovim diagnostics of each eligible buffer. It has no external
dependency.

## Setup And Defaults

`providers.diagnostic` is a boolean, or a table that contains only the
`scrollbar` and `minimap` target flags. The provider has no other options.

```lua
require("scrollbar").setup({
    providers = {
        diagnostic = true,
    },
})
```

Each diagnostic severity maps to a configured mark type:

| Neovim severity | Mark type | Text | Priority | Highlight source |
| --- | --- | --- | --- | --- |
| `ERROR` | `Error` | `{ "-", "=" }` | `2` | `DiagnosticVirtualTextError` |
| `WARN` | `Warn` | `{ "-", "=" }` | `3` | `DiagnosticVirtualTextWarn` |
| `INFO` | `Info` | `{ "-", "=" }` | `4` | `DiagnosticVirtualTextInfo` |
| `HINT` | `Hint` | `{ "-", "=" }` | `5` | `DiagnosticVirtualTextHint` |
| Unknown | `Misc` | `{ "-", "=" }` | `6` | `Normal` |

The two text values are density variants. When multiple marks of the same type
compress into one rendered row, the row uses the second variant. Lower numeric
priorities win overlaps.

## Data And Scope

The provider reads `vim.diagnostic.get(bufnr)`, which includes diagnostics from
all native diagnostic namespaces. It emits one mark for each diagnostic.

Marks are buffer-scoped. Every source window that shows the buffer shares
them. Invalid, unloaded, excluded, or over-`max_lines` buffers produce no
diagnostic marks.

This provider does not read ALE or Coc data, unless those tools also publish
into `vim.diagnostic`. ALE and Coc have separate dedicated providers, which are
disabled by default.

## Updates

The provider collects existing diagnostics during setup. On `DiagnosticChanged`,
it replaces the marks of the affected buffer. An empty diagnostic list clears
the marks of that buffer. `:ScrollbarRefresh` does an explicit refresh for
eligible source buffers.

## Customization

Customize the severity mark types in the top-level `marks` registry, and route
them in the scrollbar `layout`:

```lua
require("scrollbar").setup({
    marks = {
        Error = {
            text = { "E", "!" },
            priority = 1,
            highlight = "DiagnosticError",
        },
        Warn = {
            text = "W",
            priority = 2,
            highlight = "DiagnosticWarn",
        },
    },
    scrollbar = {
        layout = {
            columns = {
                { { types = { "Error" } } },
                { { types = { "Warn" } }, "marks" },
            },
        },
    },
})
```

`Error`, `Warn`, `Info`, and `Hint` are shared mark types. A change to them
also changes the enabled ALE or Coc marks of the same type. To keep the
providers apart in the two renderers, use the provider targets, for example
`diagnostic = { minimap = false }` and `coc = { scrollbar = false }`. For
provider-specific styling, disable this provider. Then publish distinct types
from a [custom provider](custom.md).

## Limitations And Troubleshooting

- There are no built-in namespace, source, severity, or message filters. The
  provider mirrors the complete result of `vim.diagnostic.get(bufnr)`.
- Rendering can combine marks that map to the same scrollbar row. Density,
  lanes, stack order, and priorities determine the visible cells. A click on a
  visible mark uses its exact stored source-line target.
- To examine the source data, run
  `:lua print(vim.inspect(vim.diagnostic.get(0)))`. If the result is empty, the
  cause is upstream of the scrollbar provider.
- If source data exists but marks do not appear, do these steps:
  1. Examine `providers.diagnostic`, the top-level `exclude` table,
     `max_lines`, layout routing, and priorities.
  2. Run `:ScrollbarRefresh`.

## Related

- [Provider index](README.md)
- [Custom providers](custom.md)
- [Configuration](../configuration.md)
