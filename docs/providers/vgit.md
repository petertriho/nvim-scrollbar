# Vgit Provider

The `vgit` provider publishes marks for the live-gutter hunks of
[vgit.nvim](https://github.com/tanvirtin/vgit.nvim). It is disabled by default
and has no provider-specific options.

## Setup

Configure and load vgit before scrollbar:

```lua
require("vgit").setup()

require("scrollbar").setup({
    providers = {
        vgit = true,
    },
})
```

With lazy.nvim:

```lua
{
    "petertriho/nvim-scrollbar",
    dependencies = {
        {
            "tanvirtin/vgit.nvim",
            version = false,
            opts = {},
        },
    },
    opts = {
        providers = { vgit = true },
    },
}
```

If vgit loads after scrollbar, run `:ScrollbarRefresh` after vgit attaches to
the buffer. After this refresh, vgit events update the marks automatically.
Scrollbar does not configure vgit itself.

## Marks

| vgit sign | Mark type |
| --- | --- |
| `add` | `VGitAdd` |
| `change` | `VGitChange` |
| `remove` | `VGitDelete` |

The provider uses the sign names from your vgit configuration, so custom sign
names also map correctly. It ignores other signs.

## Appearance

The three mark types have these defaults:

```lua
require("scrollbar").setup({
    marks = {
        VGitAdd = { text = { "┃" }, priority = 7, highlight = "GitSignsAdd" },
        VGitChange = { text = { "┃" }, priority = 7, highlight = "GitSignsChange" },
        VGitDelete = { text = { "▁" }, priority = 7, highlight = "GitSignsDelete" },
    },
})
```

To change a mark type, override its `text`, `priority`, or `highlight` in the
top-level `marks` table. To change it in one renderer only, use
`scrollbar.marks` or `minimap.marks`.

## Updates

- Setup does an initial refresh of the eligible loaded buffers.
- When vgit attaches to a buffer, reloads it, sees a text edit, or syncs with
  the Git index, the marks of that buffer update after a short delay.
- `:ScrollbarRefresh` rereads the vgit data of the buffers in the current
  source windows.

## Limitations

- The provider shows only the hunks of the vgit live gutter. If you disable the
  live gutter, the provider shows no marks. The provider never runs Git itself.
- If vgit is not available, the provider shows no marks, and scrollbar setup
  still succeeds.
- The provider reads internal vgit data. After a vgit upgrade, the provider can
  stop showing marks without an error.
- In very large repositories where `git diff` is slow, marks may be stale for a
  short time, until the next vgit event or `:ScrollbarRefresh`.
- You can enable `vgit` together with `gitsigns`, `mini_diff`, or `signify`.
  Each provider publishes its own marks, so the marks can overlap. If you do not
  want the overlap, disable one provider, or put the mark types in different
  lanes or give them different priorities.

## Troubleshooting

- No marks after you enable the provider: make sure that the live gutter of vgit
  is enabled and shows signs in the sign column. Then run `:ScrollbarRefresh`.
- vgit loaded late: after vgit attaches to the buffer, run `:ScrollbarRefresh`.
  This first refresh is necessary. After it, vgit events update the marks
  automatically.
- Marks disappear after a vgit upgrade: the upgrade possibly changed the
  internal vgit data that the provider reads.
- Unexpected colors: inspect `GitSignsAdd`, `GitSignsChange`, and
  `GitSignsDelete`, or override the mark highlights.

## Related Links

- [vgit.nvim](https://github.com/tanvirtin/vgit.nvim)
- [Provider index](README.md)
- [Gitsigns provider](gitsigns.md)
- [MiniDiff provider](mini_diff.md)
- [Signify provider](signify.md)
- [Highlight configuration](../highlights.md)
