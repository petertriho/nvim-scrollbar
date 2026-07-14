# ALE Provider

The `ale` provider renders diagnostics from
[ALE](https://github.com/dense-analysis/ale). It is disabled by default and has
no provider-specific options.

## Setup

Install ALE and enable the provider:

```lua
require("scrollbar").setup({
    providers = {
        ale = true,
    },
})
```

The provider reads ALE's existing diagnostic state. It does not start a lint
run or configure linters.

## Data And Severity Mapping

Marks come from `vim.g.ale_buffer_info[tostring(bufnr)].loclist`. ALE's
one-based `lnum` values are converted to zero-based scrollbar lines.

| ALE `type` | Scrollbar mark type |
| --- | --- |
| Exactly `"E"` | `Error` |
| Every other value | `Warn` |

In particular, non-error ALE entries are not mapped to `Info` or `Hint`; all
non-`E` types use `Warn`.

## Updates And Refreshes

- Setup performs an initial read for eligible loaded buffers.
- `User ALELintPost` replaces marks for that event's buffer only.
- If ALE supplies no event buffer, the current buffer is used.
- `:ScrollbarRefresh` rereads ALE state for buffers in current source windows.

The ALE event listener is installed even when ALE has not loaded yet. If ALE is
loaded later, the next `ALELintPost` event starts populating marks without
rerunning scrollbar setup.

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

Changing these types also changes other providers that publish `Error` or
`Warn` marks.

## Limitations And Failure Behavior

- The provider depends on ALE's internal `g:ale_buffer_info` location-list
  shape; it does not call an ALE API to request diagnostics.
- Missing ALE state, missing buffer state, or a missing `loclist` produces an
  empty mark list.
- A malformed entry or collection failure clears only ALE marks for the
  affected buffer. Other providers remain active.
- Stale ALE data remains stale until ALE emits `ALELintPost` or a manual
  scrollbar refresh rereads the global state.
- Standard scrollbar buffer eligibility rules still apply.

## Troubleshooting

- Confirm ALE has linted the buffer with `:ALEInfo`.
- Inspect the source data with
  `:lua print(vim.inspect(vim.g.ale_buffer_info[tostring(vim.api.nvim_get_current_buf())]))`.
- Run `:ScrollbarRefresh` after ALE state has changed if no `ALELintPost` event
  reached the provider.
- If informational ALE entries look like warnings, that is expected: every
  non-`E` type maps to `Warn`.

## Related Links

- [ALE](https://github.com/dense-analysis/ale)
- [Provider index](README.md)
- [Highlight configuration](../highlights.md)
