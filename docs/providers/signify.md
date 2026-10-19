# Signify Provider

The `signify` provider publishes marks for the hunks that
[vim-signify](https://github.com/mhinz/vim-signify) reports. It reads the
`Signify*` signs that vim-signify places. It is disabled by default and has no
provider-specific options.

## Setup

Configure and load vim-signify before scrollbar, so that its signs are
available at the first refresh:

```lua
-- vim-signify is a Vim plugin. Load it from your plugin manager first.
-- Then configure scrollbar from Lua:

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
        scrollbar = {
            providers = { signify = true },
        },
    },
}
```

If vim-signify loads after scrollbar, the provider starts to use it at the next
`User Signify` event or `:ScrollbarRefresh` after vim-signify sets
`g:loaded_signify = 1`. Scrollbar does not configure vim-signify itself.

## Marks

| vim-signify sign name | Mark type |
| --- | --- |
| `SignifyAdd` | `SignifyAdd` |
| `SignifyChange`, `SignifyChangeDelete` | `SignifyChange` |
| `SignifyRemoveFirstLine`, `SignifyDeleteMore`, `SignifyDelete<N>` | `SignifyDelete` |

The provider ignores other sign names, so the signs of other plugins do not
create marks.

## Appearance

The three mark types have these defaults:

```lua
require("scrollbar").setup({
    scrollbar = {
        marks = {
            SignifyAdd = { text = { "┃" }, priority = 7, highlight = "SignifySignAdd" },
            SignifyChange = { text = { "┃" }, priority = 7, highlight = "SignifySignChange" },
            SignifyDelete = { text = { "▁" }, priority = 7, highlight = "SignifySignDelete" },
        },
    },
})
```

To change a mark type, override its `text`, `priority`, or `highlight` in the
`scrollbar.marks` table.

## Updates

- Setup does an initial refresh of the eligible loaded buffers.
- `User Signify` names no buffer. Thus the provider refreshes the buffers in all
  source windows.
- `:ScrollbarRefresh` rereads the placed signs of the buffers in the current
  source windows.

## Limitations

- `:SignifyDisable`, or stale signs after an external change, may not emit
  `User Signify`. To force an update, run `:SignifyRefresh`, then run
  `:ScrollbarRefresh`.
- If vim-signify is not loaded, the provider shows no marks, and scrollbar
  setup still succeeds.
- You can enable `signify` together with `gitsigns`, `mini_diff`, or `vgit`.
  Each provider publishes its own marks, so the marks can overlap. If you do not
  want the overlap, disable one provider, or put the mark types in different
  lanes or give them different priorities.

## Troubleshooting

- No marks after you enable the provider: make sure that `echo g:loaded_signify`
  reports `1`. Make sure that `Signify*` signs are visible in the sign column.
  Then run `:ScrollbarRefresh`.
- vim-signify loaded late: wait for `User Signify`. Or, after vim-signify
  attaches to the buffer, run `:ScrollbarRefresh`.
- Marks stay after `:SignifyDisable`: run `:SignifyRefresh`, then run
  `:ScrollbarRefresh`.
- Unexpected colors: inspect `SignifySignAdd`, `SignifySignChange`, and
  `SignifySignDelete`, or override the mark highlights.

## Related Links

- [vim-signify](https://github.com/mhinz/vim-signify)
- [Provider index](README.md)
- [Gitsigns provider](gitsigns.md)
- [MiniDiff provider](mini_diff.md)
- [Vgit provider](vgit.md)
- [Highlight configuration](../highlights.md)
