# Signify Provider

The `signify` provider renders hunks reported by
[vim-signify](https://github.com/mhinz/vim-signify). It is disabled by default,
reads the `Signify*` signs that vim-signify places, and has no provider-specific
options.

## Setup

Configure and load vim-signify before scrollbar so `g:loaded_signify` is set and
its initial signs are placed during the first provider refresh:

```lua
" vim-signify is a Vim plugin; load it from your plugin manager first.
" Then configure scrollbar from Lua:

require("scrollbar").setup({
    scrollbar = {
        providers = {
            signify = true,
        },
    },
})
```

With lazy.nvim:

```lua
{
    "petertriho/nvim-scrollbar",
    dependencies = {
        { "mhinz/vim-signify" },
    },
    opts = {
        providers = { signify = true },
    },
}
```

If vim-signify loads after scrollbar, the provider picks it up on the next
`User Signify` event or `:ScrollbarRefresh` once `g:loaded_signify = 1` is set.
Scrollbar does not configure vim-signify itself.

## Data And Marks

vim-signify has no `get_hunks()` API, so the provider reads the signs it places
with `vim.fn.sign_getplaced(bufnr, { group = "*" })` (vim-signify uses the
default sign group, so all groups must be queried). Each placed `Signify*` sign
is mapped to one of three mark types:

| vim-signify sign name | Scrollbar mark type |
| --- | --- |
| `SignifyAdd` | `SignifyAdd` |
| `SignifyChange`, `SignifyChangeDelete` | `SignifyChange` |
| `SignifyRemoveFirstLine`, `SignifyDeleteMore`, `SignifyDelete<N>` | `SignifyDelete` |

Unknown sign names are ignored. The 1-based `lnum` of each placed sign is
converted to a zero-based mark `line`. When vim-signify is not loaded
(`g:loaded_signify` is not `1`) or no `Signify*` signs are placed, the provider
publishes an empty list.

## Updates And Refreshes

- Setup performs an initial refresh of eligible loaded buffers.
- The provider always owns one managed `User Signify` autocmd while enabled,
  including when vim-signify was missing during setup.
- `User Signify` carries no buffer, so the provider refreshes every buffer shown
  in an eligible source window (the same fan-out gitsigns uses when its event
  omits the buffer).
- `:ScrollbarRefresh` rereads placed signs for buffers in current source
  windows.
- Collection errors clear only `signify` marks for the affected buffer.
- Disabling or reconfiguring the provider removes its autocmd and stored marks.

## Appearance

The three default mark types use `┃` for additions and changes and `▁` for
deletions, priority `7`, and vim-signify's sign highlights:

```lua
marks = {
    SignifyAdd = { text = { "┃" }, priority = 7, highlight = "SignifySignAdd" },
    SignifyChange = { text = { "┃" }, priority = 7, highlight = "SignifySignChange" },
    SignifyDelete = { text = { "▁" }, priority = 7, highlight = "SignifySignDelete" },
}
```

Override `text`, `priority`, or `highlight` under the top-level
`marks` table as usual.

## Limitations

- vim-signify places its signs in the default sign group, so the provider
  queries `group = "*"`. Other plugins' signs are ignored because only `Signify*`
  names are mapped.
- `:SignifyDisable` or stale signs after an external change may not emit
  `User Signify`, so run `:SignifyRefresh` then `:ScrollbarRefresh` to force an
  update.
- The first-line-delete and change+delete distinctions are collapsed into the
  three mark types above for parity with the `gitsigns` and `mini_diff` diff
  providers.
- Enabling `signify` alongside `gitsigns` or `mini_diff` is supported, but their
  diff marks can overlap. Disable one or customize typed lanes and priorities if
  needed.

## Troubleshooting

- No marks after enabling: confirm `echo g:loaded_signify` reports `1` and that
  `Signify*` signs are visible in the sign column, then run `:ScrollbarRefresh`.
- vim-signify loaded late: wait for `User Signify` or run `:ScrollbarRefresh`
  after vim-signify has attached to the buffer.
- Marks remain after `:SignifyDisable`: run `:SignifyRefresh` then
  `:ScrollbarRefresh`.
- Duplicate diff marks: disable `gitsigns`, `mini_diff`, or `signify`, or place
  their mark types in different lanes.
- Unexpected colors: inspect `SignifySignAdd`, `SignifySignChange`, and
  `SignifySignDelete`, or override the mark highlights.

## Related Links

- [vim-signify](https://github.com/mhinz/vim-signify)
- [Provider index](README.md)
- [Gitsigns provider](gitsigns.md)
- [MiniDiff provider](mini_diff.md)
- [Highlight configuration](../highlights.md)
