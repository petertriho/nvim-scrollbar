# MiniDiff Provider

The `mini_diff` provider renders hunks reported by
[mini.diff](https://github.com/nvim-mini/mini.diff). It is disabled by default,
supports every source configured in mini.diff, and has no provider-specific
options.

## Setup

Configure mini.diff before scrollbar so its module and initial buffer data are
available when the provider performs its one-time dependency lookup:

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

If mini.diff loads after scrollbar, rerun `require("scrollbar").setup()` with
your configuration. `:ScrollbarRefresh` does not retry a failed dependency
lookup.

## Data And Marks

The provider calls `require("mini.diff").get_buf_data(bufnr)` and reads its
public `hunks` list. Mapping is direct and does not depend on the source name:

| mini.diff hunk type | Scrollbar mark type | Range |
| --- | --- | --- |
| `add` | `MiniDiffAdd` | All buffer lines in the hunk |
| `change` | `MiniDiffChange` | All buffer lines in the hunk, including unequal reference/buffer counts |
| `delete` | `MiniDiffDelete` | One surviving position, clamped to the first buffer line |

Unknown hunk types are ignored. Missing or disabled-buffer data and an empty
hunk list replace existing MiniDiff marks with an empty list.

## Updates And Refreshes

- Setup performs an initial refresh of eligible loaded buffers.
- The provider always owns one managed `User MiniDiffUpdated` autocmd while
  enabled, including when mini.diff was missing during setup.
- `MiniDiffUpdated` refreshes only the event buffer.
- `:ScrollbarRefresh` rereads mini.diff data for buffers in current source
  windows.
- Collection errors clear only `mini_diff` marks for the affected buffer.
- Disabling or reconfiguring the provider removes its autocmd and stored marks.

## Appearance

The three default mark types use `▒`, column `1`, priority `7`, and mini.diff's
sign highlights:

```lua
marks = {
    MiniDiffAdd = { text = { "▒" }, column = 1, priority = 7, highlight = "MiniDiffSignAdd" },
    MiniDiffChange = { text = { "▒" }, column = 1, priority = 7, highlight = "MiniDiffSignChange" },
    MiniDiffDelete = { text = { "▒" }, column = 1, priority = 7, highlight = "MiniDiffSignDelete" },
}
```

Override `text`, `column`, `priority`, or `highlight` under the top-level
`marks` table as usual.

## Limitations

- Calling `MiniDiff.disable()` directly does not emit `MiniDiffUpdated`, so old
  marks can remain until `:ScrollbarRefresh` or another refresh path rereads the
  now-missing buffer data.
- The provider does not poll, patch mini.diff lifecycle functions, or filter by
  source name.
- Enabling both `mini_diff` and `gitsigns` is supported, but their marks can
  overlap. Disable one or customize columns and priorities if needed.
- A dependency missing during setup is not resolved dynamically. The owned
  autocmd remains safe but cannot collect data until scrollbar setup is rerun.

## Troubleshooting

- No marks after enabling: confirm `MiniDiff.get_buf_data(0)` returns a table
  with hunks and that mini.diff was configured before scrollbar.
- mini.diff loaded late: rerun scrollbar setup; refresh alone cannot attach it.
- Marks remain after `MiniDiff.disable()`: run `:ScrollbarRefresh`.
- Duplicate diff marks: disable either `gitsigns` or `mini_diff`, or place their
  mark types in different columns.
- Unexpected colors: inspect `MiniDiffSignAdd`, `MiniDiffSignChange`, and
  `MiniDiffSignDelete`, or override the mark highlights.

## Related Links

- [mini.diff](https://github.com/nvim-mini/mini.diff)
- [Provider index](README.md)
- [Gitsigns provider](gitsigns.md)
- [Highlight configuration](../highlights.md)
