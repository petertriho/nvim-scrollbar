# Change List Provider

The `changelist` provider shows where `g;` and `g,` go from each window. It
publishes a `ChangeOlder` mark on the line that `g;` goes to, and a
`ChangeNewer` mark on the line that `g,` goes to. It is disabled by default
and has no external dependency.

## Setup And Defaults

`providers.changelist` is a boolean, or a table that contains only the
`scrollbar` and `minimap` target flags. The provider has no other options.

```lua
require("scrollbar").setup({
    providers = {
        changelist = true,
    },
})
```

The provider emits two mark types:

| Mark type | Key | Text | Priority | Highlight source |
| --- | --- | --- | --- | --- |
| `ChangeOlder` | `g;` | `{ "«" }` | `1` | `Changed` |
| `ChangeNewer` | `g,` | `{ "»" }` | `1` | `Changed` |

The glyphs are different from the `<` and `>` of the
[`jumplist` provider](jumplist.md), because the default colorscheme gives
`Changed` and `Special` the same color.

To show only one of the targets, hide the other type in the top-level `marks`
table. A hidden type also stays out of label mode and the glance list:

```lua
require("scrollbar").setup({
    providers = {
        changelist = true,
    },
    marks = {
        ChangeNewer = false, -- show only the g; target
    },
})
```

To hide a type in one renderer only, use `scrollbar.marks.<Type> = false` or
`minimap.marks.<Type> = false`.

## Data And Scope

The change list belongs to the buffer, and each window keeps its own position
in it. The provider reads the list with `getchangelist()` in each source
window, and marks at most two lines:

- `ChangeOlder` goes on the entry that `g;` goes to. After an edit, this is
  the latest change.
- `ChangeNewer` goes on the entry that `g,` goes to. The mark shows after
  `g;`.

After an edit, your position is at the end of the list. There, `g,` goes to
the latest change, which is also the `ChangeOlder` line, so no `ChangeNewer`
mark shows. At the last entry, `g,` fails with `E663`, so no `ChangeNewer` mark
shows either.

When a window starts to show a buffer, Neovim gives it a position from the
window history of the buffer. This position can be the first entry, so a new
split can show a `ChangeNewer` mark before you press `g;`. The marks always
show the targets from the position of the window.

Marks are window-scoped. Two windows that show one buffer can be at different
positions in the list, so each window shows its own targets.

## Updates

The provider reads the list on these events, but not for each key in Insert
mode:

- `CursorMoved`, `BufWinEnter`, and `WinEnter` read the list of the current
  window.
- Each edit can add an entry and move the other entries, in every window of
  the buffer. After `TextChanged` in Normal mode and after `InsertLeave`, the
  provider reads the list of each window of the buffer.
- `:ScrollbarRefresh` reads the list of each source window at once.

While you type in Insert mode, the marks keep their lines from before the
insert. They update when you leave Insert mode.

## Customization

Change the two types in the top-level `marks` table:

```lua
require("scrollbar").setup({
    providers = {
        changelist = true,
    },
    marks = {
        ChangeOlder = { text = "c", priority = 2, highlight = "DiffChange" },
        ChangeNewer = { text = "C", priority = 2, highlight = "DiffChange" },
    },
})
```

Route the types to their own lane in the scrollbar `layout`. See
[Configuration](../configuration.md#layout).

## Limitations And Troubleshooting

- The provider shows only the targets of a single `g;` and `g,`. It does not
  show the targets of a count, such as `3g;`.
- Neovim adds a change list entry only for the first change of an undo block.
  More changes in the same block move that entry. Thus a mapping or a script
  that makes several edits gives one entry.
- The `Cursor` mark has priority `0`, so it covers a target on the cursor line
  in a shared lane. Right after an edit, `ChangeOlder` is on the cursor line.
- `ChangeOlder` and `ChangeNewer` have priority `1`, the same as `Mark` and
  `Search`. To show the targets over other marks, give them their own lane.
- To examine the source data, run
  `:lua print(vim.inspect(vim.fn.getchangelist()))`. The second item is the
  zero-based index of the current position. In Lua indexes, `g;` goes to item
  `index` and `g,` goes to item `index + 2` of the list.
- If marks do not appear, do these steps:
  1. Examine `providers.changelist`, the top-level `exclude` table,
     `max_lines`, layout routing, and priorities.
  2. Run `:ScrollbarRefresh`.

## Related

- [Provider index](README.md)
- [Jumplist](jumplist.md)
- [Jump and Glance](../jump-and-glance.md)
- [Configuration](../configuration.md)
