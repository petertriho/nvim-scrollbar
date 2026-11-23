# Jumplist Provider

The `jumplist` provider shows where `<C-o>` and `<C-i>` go from each window.
It publishes a `JumpOlder` mark on the line that `<C-o>` goes to, and a
`JumpNewer` mark on the line that `<C-i>` goes to. It is disabled by default
and has no external dependency.

## Setup And Defaults

`providers.jumplist` is a boolean, or a table that contains only the
`scrollbar` and `minimap` target flags. The provider has no other options.

```lua
require("scrollbar").setup({
    providers = {
        jumplist = true,
    },
})
```

The provider emits two mark types:

| Mark type | Key | Text | Priority | Highlight source |
| --- | --- | --- | --- | --- |
| `JumpOlder` | `<C-o>` | `{ "<" }` | `1` | `Special` |
| `JumpNewer` | `<C-i>` | `{ ">" }` | `1` | `Special` |

To show only one of the targets, hide the other type in the top-level `marks`
table. A hidden type also stays out of label mode and the glance list:

```lua
require("scrollbar").setup({
    providers = {
        jumplist = true,
    },
    marks = {
        JumpNewer = false, -- show only the <C-o> target
    },
})
```

To hide a type in one renderer only, use `scrollbar.marks.<Type> = false` or
`minimap.marks.<Type> = false`.

## Data And Scope

Each window has its own jumplist. The provider reads the list of each source
window with `getjumplist()`, and marks at most two lines:

- `JumpOlder` goes on the entry that `<C-o>` goes to.
- `JumpNewer` goes on the entry that `<C-i>` goes to. After a jump, you are at
  the end of the list, so `<C-i>` has no target and no `JumpNewer` mark shows.
  The mark shows after `<C-o>`.

A target in another buffer gets no mark, because the key leaves the buffer of
the window. The provider shows no other entry in its place.

Marks are window-scoped. Two windows that show one buffer have separate
jumplists, so each window shows its own targets.

## Updates

A read of the jumplist costs about 55 µs for a list of 100 entries, and
Neovim gives no event when the list changes. Thus the provider reads the list
on these events, but not for each key in Insert mode:

- `CursorMoved`, `BufWinEnter`, and `WinEnter` read the list of the current
  window.
- `InsertLeave` reads the list of the current window.
- An edit that inserts or deletes lines moves the entries in every window of
  the buffer. After `TextChanged` in Normal mode and after `InsertLeave`, the
  provider reads the list of each window of the buffer whose line count
  changed.
- `:ScrollbarRefresh` reads the list of each source window at once.

These changes show only at the next update or at `:ScrollbarRefresh`:

- `:clearjumps`.
- A jump from Insert mode, such as `<C-o>G`, shows when you leave Insert mode.

## Customization

Change the two types in the top-level `marks` table:

```lua
require("scrollbar").setup({
    providers = {
        jumplist = true,
    },
    marks = {
        JumpOlder = { text = "↑", priority = 2, highlight = "Directory" },
        JumpNewer = { text = "↓", priority = 2, highlight = "Directory" },
    },
})
```

Route the types to their own lane in the scrollbar `layout`. See
[Configuration](../configuration.md#layout).

## Limitations And Troubleshooting

- The provider shows only the targets of a single `<C-o>` and `<C-i>`. It does
  not show the targets of a count, such as `3<C-o>`.
- The `Cursor` mark has priority `0`, so it covers a target on the cursor line
  in a shared lane.
- `JumpOlder` and `JumpNewer` have priority `1`, the same as `Mark` and
  `Search`. To show the targets over other marks, give them their own lane.
- To examine the source data, run
  `:lua print(vim.inspect(vim.fn.getjumplist()))`. The second item is the
  zero-based index of the current position. In Lua indexes, `<C-o>` goes to
  item `index` and `<C-i>` goes to item `index + 2` of the list.
- If marks do not appear, do these steps:
  1. Examine `providers.jumplist`, the top-level `exclude` table, `max_lines`,
     layout routing, and priorities.
  2. Run `:ScrollbarRefresh`.

## Related

- [Provider index](README.md)
- [Change list](changelist.md)
- [Jump and Glance](../jump-and-glance.md)
- [Configuration](../configuration.md)
