# Quickfix List Provider

The `qflist` provider publishes marks for the entries of the current quickfix
list, for example the results of `:grep`, `:vimgrep`, or `:make`, and the
lists that `vim.diagnostic.setqflist()` or a picker creates. It is disabled by
default and has no external dependency.

## Setup And Defaults

`providers.qflist` is a boolean, or a table with the `types` option and the
`scrollbar` and `minimap` target flags:

```lua
require("scrollbar").setup({
    providers = {
        qflist = true,
    },
})
```

By default, each entry publishes a `Qflist` mark:

| Mark type | Text | Priority | Highlight source |
| --- | --- | --- | --- |
| `Qflist` | `{ "-", "=" }` | `6` | `QuickFixLine` |

`QuickFixLine` is the group that Neovim uses for the current entry in the
quickfix window. If your colorscheme gives it only a background, the marks use
that background color. See [Highlights](../highlights.md#sources).

## Entry Types

An entry can have a type letter: `E` (error), `W` (warning), `I` (info), or
`N` (note). Entries from `:grep`, `:vimgrep`, and most pickers have no type.
The `types` option maps a letter to a mark type, or to `false`, which drops the
entries of that type:

```lua
require("scrollbar").setup({
    providers = {
        qflist = {
            types = { E = "Error", W = "Warn", I = false },
        },
    },
})
```

With this setup, an error entry publishes an `Error` mark, a warning entry
publishes a `Warn` mark, and an info entry publishes no mark. A note entry and
an entry without a type publish `Qflist`.

- The keys are `E`, `W`, `I`, and `N`. Another key is a setup error.
- The provider compares the type of an entry without case, so `e` matches `E`.
- A value is `false` or a mark type from the top-level `marks` table. A type
  that is not in that table is a setup error.
- An entry with another letter, or with no type, always publishes `Qflist`.

## Data And Scope

The provider reads the current list of the quickfix stack. It publishes one
mark for each entry that meets all of these conditions:

- The entry is valid. These are the entries that `:cnext` visits.
- The entry has a buffer.
- The entry has a line number of 1 or more.

The mark goes on the line of the entry. The provider ignores `end_lnum`. Two
entries on one line give two marks, so the row shows the next density variant.

Marks are buffer-scoped. Every source window that shows the buffer shares
them. A buffer that is not loaded, excluded, or longer than `max_lines` gets no
marks. A buffer that the list names gets its marks when it loads.

The marks stay while the list has entries. To clear them, replace the list,
for example with `:cexpr []`.

## Updates

- A quickfix command, such as `:grep`, `:vimgrep`, `:make`, or `:cexpr`,
  updates the marks through `QuickFixCmdPost`.
- `setqflist()`, `:colder`, and `:cnewer` fire no event. When Neovim waits for
  input (`SafeState`), the provider compares the `id` and the `changedtick`
  of the current list. If one of them changed, the provider reads the list
  again.
- Neovim moves the entries when you insert or delete lines above them. When
  the line count of a buffer with marks changes, the provider reads the list
  again 100 ms after the last change of the line count. A long list then costs
  no time for each key.
- `:ScrollbarRefresh` reads the list again at once when it or the buffer
  changed.

An edit that moves lines but keeps the line count, such as `:move`, leaves the
marks on the old lines until the next update or `:ScrollbarRefresh`.

## Customization

Change the `Qflist` type in the top-level `marks` table:

```lua
require("scrollbar").setup({
    providers = {
        qflist = true,
    },
    marks = {
        Qflist = { text = { "q", "Q" }, priority = 2, highlight = "Directory" },
    },
})
```

Route the type to its own lane in the scrollbar `layout`. See
[Configuration](../configuration.md#layout).

## Limitations And Troubleshooting

- The provider shows only the current list of the stack.
- A list that `vim.diagnostic.setqflist()` creates repeats the marks of the
  [`diagnostic` provider](diagnostic.md). The two providers use different mark
  types, so the marks keep their own colors.
- To examine the source data, run
  `:lua print(vim.inspect(vim.fn.getqflist()))`. The provider marks only the
  entries with `valid = 1`, a `bufnr`, and an `lnum` of 1 or more.
- If source data exists but marks do not appear, do these steps:
  1. Examine `providers.qflist`, the top-level `exclude` table, `max_lines`,
     layout routing, and priorities.
  2. Run `:ScrollbarRefresh`.

## Related

- [Provider index](README.md)
- [Highlights](../highlights.md)
- [Configuration](../configuration.md)
