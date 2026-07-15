# Gitsigns Provider

The `gitsigns` provider renders Git hunks reported by
[gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim). It is disabled by
default and has no provider-specific options.

## Setup

Load and configure gitsigns before calling `require("scrollbar").setup()`:

```lua
require("gitsigns").setup()

require("scrollbar").setup({
    providers = {
        gitsigns = true,
    },
})
```

For lazy.nvim, declaring gitsigns as a dependency gives it the required load
order:

```lua
{
    "petertriho/nvim-scrollbar",
    dependencies = { "lewis6991/gitsigns.nvim" },
    opts = {
        providers = { gitsigns = true },
    },
}
```

> **Load order is significant.** The provider tries to load `gitsigns` once
> during scrollbar setup. If gitsigns loads later, rerun
> `require("scrollbar").setup()` with your configuration after it is available.
> `:ScrollbarRefresh` alone does not attach the missing integration.

Gitsigns and [mini.diff](mini_diff.md) can be enabled together, but their diff
marks may overlap because each provider publishes its own view of changes.

## Data And Marks

The provider calls `require("gitsigns").get_hunks(bufnr)` and translates the
current hunk list into these configured mark types:

| Hunk content | Mark type | Intended result |
| --- | --- | --- |
| Added lines | `GitAdd` | Marks added source lines |
| Changed lines | `GitChange` | Marks modified source lines |
| Extra added lines in a changed hunk | `GitAdd` | Distinguishes additions from modifications |
| Deletion | `GitDelete` | Places one marker at the deletion position |

This describes the user-visible categories rather than relying on internal hunk
count arithmetic.

## Updates And Refreshes

- Setup performs an initial refresh of eligible loaded buffers.
- `User GitSignsUpdate` refreshes the buffer named by the event when available.
- If the event has no usable buffer, all buffers shown in eligible source
  windows are refreshed.
- `:ScrollbarRefresh` rereads hunks for buffers in current source windows.
- An empty hunk list replaces existing gitsigns marks with an empty list.

Refreshes read gitsigns' current cache; they do not run Git or force gitsigns to
recompute hunks.

## Appearance

Customize the three built-in mark types under the top-level `marks` table:

```lua
require("scrollbar").setup({
    providers = { gitsigns = true },
    marks = {
        GitAdd = { text = "+", highlight = "DiffAdd" },
        GitChange = { text = "~", highlight = "DiffChange" },
        GitDelete = { text = "_", highlight = "DiffDelete" },
    },
})
```

The normal mark options are available: `text`, `column`, `priority`, and
`highlight`.

## Limitations And Failure Behavior

- Only gitsigns hunks are represented; untracked-file and repository-level
  status are outside this provider.
- Deletions have no surviving source range, so each deletion is represented by
  one mark.
- Missing gitsigns at setup produces no marks and does not break scrollbar
  setup.
- If hunk collection fails, only this provider's marks for the affected buffer
  are cleared. Other providers continue to render.
- Standard scrollbar eligibility rules still apply, including excluded buffer
  types, excluded filetypes, and `max_lines`.

## Troubleshooting

- No marks and no `GitSignsUpdate` autocmd: verify gitsigns loaded before
  scrollbar, then rerun scrollbar setup.
- No marks in one buffer: check `:Gitsigns debug_messages` and confirm
  `require("gitsigns").get_hunks(0)` returns hunks.
- Marks use unexpected colors: inspect `GitSignsAdd`, `GitSignsChange`, and
  `GitSignsDelete`, or override the scrollbar mark highlights shown above.
- Recent hunks are missing: let gitsigns update first, then use
  `:ScrollbarRefresh` to republish its current hunk cache.

## Related Links

- [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
- [Provider index](README.md)
- [Highlight configuration](../highlights.md)
