# Location List Provider

The `loclist` provider publishes marks for the entries of the location list of
each window, for example the results of `:lgrep`, `:lvimgrep`, or `:lmake`, and
the lists that `vim.diagnostic.setloclist()` or a linter creates. It is
disabled by default and has no external dependency.

## Setup And Defaults

`providers.loclist` is a boolean, or a table with the `types` option and the
`scrollbar` and `minimap` target flags:

```lua
require("scrollbar").setup({
    providers = {
        loclist = true,
    },
})
```

By default, each entry publishes a `Loclist` mark:

| Mark type | Text | Priority | Highlight source |
| --- | --- | --- | --- |
| `Loclist` | `{ "-", "=" }` | `6` | `QuickFixLine` |

`QuickFixLine` is the group that Neovim uses for the current entry in the list
window. If your colorscheme gives it only a background, the marks use that
background color. See [Highlights](../highlights.md#sources).

## Entry Types

The `types` option works as for the quickfix list. It maps the entry type
letters `E`, `W`, `I`, and `N` to a mark type, or to `false`, which drops the
entries of that type. An entry with another letter, or with no type, publishes
`Loclist`:

```lua
require("scrollbar").setup({
    providers = {
        loclist = {
            types = { E = "Error", W = "Warn" },
        },
    },
})
```

See [Entry types](qflist.md#entry-types) for the rules.

## Data And Scope

Each window has its own location list. The provider reads the current list of
the location list stack of each source window. It publishes one mark for each
entry that meets all of these conditions:

- The entry is valid. These are the entries that `:lnext` visits.
- The entry points at the buffer that the window shows.
- The entry has a line number of 1 or more.

The mark goes on the line of the entry. The provider ignores `end_lnum`. Two
entries on one line give two marks, so the row shows the next density variant.

Marks are window-scoped. Two windows that show one buffer can have different
lists, so each window shows the marks of its own list. The window that `:lopen`
opens shows the list buffer, so it gets no marks.

The marks stay while the list has entries. To clear them, replace the list,
for example with `:lexpr []`.

## Updates

- A location list command, such as `:lgrep`, `:lvimgrep`, `:lmake`, or
  `:lexpr`, updates the marks through `QuickFixCmdPost`.
- `setloclist()`, `:lolder`, and `:lnewer` fire no event. When Neovim waits for
  input (`SafeState`), the provider compares the `id` and the `changedtick` of
  the current list of each source window. If one of them changed, the provider
  reads the list again.
- Neovim moves the entries when you insert or delete lines above them. When
  the line count of the buffer of a window changes, the provider reads the
  list of that window again 100 ms after the last change of the line count. A
  long list then costs no time for each key.
- A window that shows another buffer updates at once. A window that you enter
  updates at once if its list or its line count changed.
- `:ScrollbarRefresh` reads the list of each source window again at once.

An edit that moves lines but keeps the line count, such as `:move`, leaves the
marks on the old lines until the next update or `:ScrollbarRefresh`.

## Customization

Change the `Loclist` type in the top-level `marks` table:

```lua
require("scrollbar").setup({
    providers = {
        loclist = true,
    },
    marks = {
        Loclist = { text = { "l", "L" }, priority = 2, highlight = "Directory" },
    },
})
```

Route the type to its own lane in the scrollbar `layout`. See
[Configuration](../configuration.md#layout).

## Limitations And Troubleshooting

- The provider shows only the current list of the stack of each window.
- A list that `vim.diagnostic.setloclist()` creates repeats the marks of the
  [`diagnostic` provider](diagnostic.md). ALE can also fill the location list
  with the problems that the `diagnostic` or [`ale`](ale.md) provider already
  shows. The providers use different mark types, so the marks keep their own
  colors.
- To examine the source data, run
  `:lua print(vim.inspect(vim.fn.getloclist(0)))`. The provider marks only the
  entries with `valid = 1`, the `bufnr` of the window, and an `lnum` of 1 or
  more.
- If source data exists but marks do not appear, do these steps:
  1. Examine `providers.loclist`, the top-level `exclude` table, `max_lines`,
     layout routing, and priorities.
  2. Run `:ScrollbarRefresh`.

## Related

- [Provider index](README.md)
- [Quickfix list](qflist.md)
- [Highlights](../highlights.md)
- [Configuration](../configuration.md)
