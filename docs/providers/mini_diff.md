# MiniDiff Provider

The `mini_diff` provider publishes marks for the hunks that
[mini.diff](https://github.com/nvim-mini/mini.diff) reports. It supports every
source that is configured in mini.diff. It is disabled by default and has no
provider-specific options.

![Scrollbar marks for added, changed, and deleted mini.diff hunks](https://github.com/user-attachments/assets/9e45ec88-a6da-4225-b6e0-c5f67f7dd7f8)

## Setup

Configure mini.diff before scrollbar, so that its data is available at the
first refresh:

```lua
require("mini.diff").setup()

require("scrollbar").setup({
    providers = {
        mini_diff = true,
    },
})
```

With lazy.nvim:

```lua
{
    "petertriho/nvim-scrollbar",
    dependencies = {
        {
            "nvim-mini/mini.diff",
            version = false,
            opts = {},
        },
    },
    opts = {
        providers = { mini_diff = true },
    },
}
```

If mini.diff loads after scrollbar, the provider starts to use it at the next
`MiniDiffUpdated` event or `:ScrollbarRefresh`. Scrollbar does not call
`require("mini.diff").setup()`.

## Marks

| mini.diff hunk type | Mark type | Range |
| --- | --- | --- |
| `add` | `MiniDiffAdd` | All buffer lines in the hunk |
| `change` | `MiniDiffChange` | All buffer lines in the hunk, also when the reference and buffer counts are not equal |
| `delete` | `MiniDiffDelete` | One surviving position, clamped to the first buffer line |

The provider ignores unknown hunk types. If mini.diff has no data for a buffer,
that buffer has no MiniDiff marks.

## Appearance

The three mark types have these defaults:

```lua
require("scrollbar").setup({
    marks = {
        MiniDiffAdd = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignAdd" },
        MiniDiffChange = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignChange" },
        MiniDiffDelete = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignDelete" },
    },
})
```

To change a mark type, override its `text`, `priority`, or `highlight` in the
top-level `marks` table. To change it in one renderer only, use
`scrollbar.marks` or `minimap.marks`.

## Updates

- Setup does an initial refresh of the eligible loaded buffers.
- `User MiniDiffUpdated` refreshes the event buffer.
- `:ScrollbarRefresh` rereads the mini.diff data of the buffers in the current
  source windows.

## Limitations

- A direct call to `MiniDiff.disable()` does not emit `MiniDiffUpdated`. Old
  marks can stay until `:ScrollbarRefresh`.
- If mini.diff is not available, the provider shows no marks, and scrollbar
  setup still succeeds.
- You can enable `mini_diff` together with `gitsigns`, `signify`, or `vgit`.
  Each provider publishes its own marks, so the marks can overlap. If you do not
  want the overlap, disable one provider, or put the mark types in different
  lanes or give them different priorities.

## Troubleshooting

- No marks after you enable the provider: make sure that
  `MiniDiff.get_buf_data(0)` returns a table with hunks. Also make sure that
  mini.diff was configured before scrollbar.
- mini.diff loaded late: wait for `MiniDiffUpdated`, or run
  `:ScrollbarRefresh`. Make sure that mini.diff itself is configured.
- Marks stay after `MiniDiff.disable()`: run `:ScrollbarRefresh`.
- Unexpected colors: inspect `MiniDiffSignAdd`, `MiniDiffSignChange`, and
  `MiniDiffSignDelete`, or override the mark highlights.

## Related Links

- [mini.diff](https://github.com/nvim-mini/mini.diff)
- [Provider index](README.md)
- [Gitsigns provider](gitsigns.md)
- [Signify provider](signify.md)
- [Vgit provider](vgit.md)
- [Highlight configuration](../highlights.md)
