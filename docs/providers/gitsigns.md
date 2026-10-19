# Gitsigns Provider

The `gitsigns` provider publishes marks for the Git hunks that
[gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) reports. It is
disabled by default and has no provider-specific options.

## Setup

Load and configure gitsigns before you call `require("scrollbar").setup()`:

```lua
require("gitsigns").setup()

require("scrollbar").setup({
    scrollbar = {
        providers = {
            gitsigns = true,
        },
    },
})
```

With lazy.nvim, a gitsigns dependency makes marks available during the initial
scrollbar refresh:

```lua
{
    "petertriho/nvim-scrollbar",
    dependencies = { "lewis6991/gitsigns.nvim" },
    opts = {
        scrollbar = {
            providers = { gitsigns = true },
        },
    },
}
```

We recommend that you load and configure gitsigns first, but it is not
required. If gitsigns loads after scrollbar, the provider starts to use it at
the next `GitSignsUpdate` event or `:ScrollbarRefresh`. Scrollbar does not call
`require("gitsigns").setup()`.

## Marks

| Hunk content | Mark type |
| --- | --- |
| Added lines | `GitAdd` |
| Changed lines | `GitChange` |
| Extra added lines in a changed hunk | `GitAdd` |
| Deletion | `GitDelete`, one mark at the deletion position |

## Appearance

The three mark types have these defaults:

```lua
require("scrollbar").setup({
    scrollbar = {
        marks = {
            GitAdd = { text = { "┃" }, priority = 7, highlight = "GitSignsAdd" },
            GitChange = { text = { "┃" }, priority = 7, highlight = "GitSignsChange" },
            GitDelete = { text = { "▁" }, priority = 7, highlight = "GitSignsDelete" },
        },
    },
})
```

To change a mark type, override its `text`, `priority`, or `highlight` in the
`scrollbar.marks` table.

## Updates

- Setup does an initial refresh of the eligible loaded buffers.
- `User GitSignsUpdate` refreshes the buffer that the event names. If the event
  names no valid buffer, the provider refreshes the buffers in all source
  windows.
- `:ScrollbarRefresh` rereads the hunks of the buffers in the current source
  windows.

A refresh reads the hunks that gitsigns already computed. It does not run Git,
and it does not make gitsigns compute the hunks again.

## Limitations

- The marks show only gitsigns hunks. They do not show untracked-file status or
  repository status.
- If gitsigns is not available, the provider shows no marks, and scrollbar
  setup still succeeds.
- You can enable `gitsigns` together with `mini_diff`, `signify`, or `vgit`.
  Each provider publishes its own marks, so the marks can overlap. If you do not
  want the overlap, disable one provider, or put the mark types in different
  lanes or give them different priorities.

## Troubleshooting

- No marks after gitsigns loads late: wait for `GitSignsUpdate`, or run
  `:ScrollbarRefresh`. Make sure that gitsigns itself is configured.
- No marks in one buffer: examine `:Gitsigns debug_messages`. Make sure that
  `require("gitsigns").get_hunks(0)` returns hunks.
- Recent hunks are missing: let gitsigns update first. Then run
  `:ScrollbarRefresh`.
- Unexpected colors: inspect `GitSignsAdd`, `GitSignsChange`, and
  `GitSignsDelete`, or override the mark highlights.

## Related Links

- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
- [Provider index](README.md)
- [MiniDiff provider](mini_diff.md)
- [Signify provider](signify.md)
- [Vgit provider](vgit.md)
- [Highlight configuration](../highlights.md)
