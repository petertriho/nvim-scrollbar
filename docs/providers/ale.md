# ALE Provider

The `ale` provider publishes marks for the diagnostics from
[ALE](https://github.com/dense-analysis/ale). It is disabled by default and has
no provider-specific options.

## Setup

Install ALE. Then enable the provider:

```lua
require("scrollbar").setup({
    providers = {
        ale = true,
    },
})
```

The provider reads the diagnostics that ALE already has. It does not start a
lint run, and it does not configure linters.

## Marks

| ALE `type` | Mark type |
| --- | --- |
| Exactly `"E"` | `Error` |
| Every other value | `Warn` |

The provider never maps ALE entries to `Info` or `Hint`.

## Appearance

ALE uses the shared `Error` and `Warn` mark types:

```lua
require("scrollbar").setup({
    providers = { ale = true },
    marks = {
        Error = { text = "E", highlight = "DiagnosticError" },
        Warn = { text = "W", highlight = "DiagnosticWarn" },
    },
})
```

A change to these types also changes the marks of other providers that publish
`Error` or `Warn` marks. To show ALE marks in only one renderer, use a provider
target, for example `ale = { minimap = false }`.

## Updates

- Setup does an initial read of the eligible loaded buffers.
- `User ALELintPost` replaces the marks of the event buffer.
- `:ScrollbarRefresh` rereads the ALE state of the buffers in the current
  source windows.

If ALE loads after scrollbar, the next `ALELintPost` event shows the ALE marks.
You do not have to run scrollbar setup again.

## Limitations

- The provider depends on the internal shape of the ALE variable
  `g:ale_buffer_info`. It does not call an ALE API to request diagnostics.
- Stale ALE data stays stale until ALE emits `ALELintPost` or
  `:ScrollbarRefresh` rereads it.

## Troubleshooting

- Use `:ALEInfo` to make sure that ALE linted the buffer.
- Inspect the source data with
  `:lua print(vim.inspect(vim.g.ale_buffer_info[tostring(vim.api.nvim_get_current_buf())]))`.
- If the ALE state changed and no `ALELintPost` event followed, run
  `:ScrollbarRefresh`.
- If informational ALE entries look like warnings, the provider works
  correctly. Every type other than `E` maps to `Warn`.

## Related Links

- [ALE](https://github.com/dense-analysis/ale)
- [Provider index](README.md)
- [Highlight configuration](../highlights.md)
