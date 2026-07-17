# Vgit Provider

The `vgit` provider renders hunks reported by [vgit.nvim](https://github.com/tanvirtin/vgit.nvim).
It is disabled by default, mirrors vgit's live-gutter diff hunks onto the scrollbar,
and has no provider-specific options.

## Setup

Configure and load vgit before scrollbar so its internal buffer store and sign
settings are populated during the first provider refresh:

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

If vgit loads after scrollbar, the provider picks up its modules on the next
internal event or `:ScrollbarRefresh`. Scrollbar does not configure vgit itself.

## Data And Marks

The provider reads vgit's internal buffer store via
`require("vgit.git.git_buffer_store").get({ bufnr = bufnr })` and inspects the
returned buffer's `state.signs` list. Each sign's `name` is reverse-mapped
through `require("vgit.settings.signs"):get("usage").main`, so customized sign
names still map correctly:

| vgit `usage.main` key | Sign name (default) | Scrollbar mark type | Line |
| --- | --- | --- | --- |
| `add` | `GitSignsAdd` | `VGitAdd` | `sign.col` (already 0-based) |
| `change` | `GitSignsChange` | `VGitChange` | `sign.col` |
| `remove` | `GitSignsDelete` | `VGitDelete` | `sign.col`, clamped to the first line (`0`) |

Unknown sign names and signs with non-integer or negative `col` are ignored.
When vgit is absent, the buffer has no store entry, or `state.signs` is empty,
the provider replaces existing VGit marks with an empty list.

## Updates And Refreshes

- Setup performs an initial refresh of eligible loaded buffers.
- The provider hooks into vgit's **internal event bus** via
  `git_buffer_store.on`, registering for the `attach`, `reload`, `change`, and
  `sync` events. These fire at the exact moments vgit processes a buffer:
  initial attach, reload, text edit (`on_lines`), and git-index sync
  respectively. This is the same mechanism vgit's own LiveGutter uses.
- Because vgit computes `state.signs` asynchronously (plenary.async coroutines
  that shell out to git), each event triggers a **deferred refresh** (50 ms by
  default) rather than reading the store immediately. The delay lets vgit's
  debounced `diff()` complete before the scrollbar reads the updated signs.
  Rapid events for the same buffer are coalesced — only the last one runs.
- `:ScrollbarRefresh` rereads vgit data for buffers in current source windows.
- Collection errors clear only `vgit` marks for the affected buffer.
- Disabling or reconfiguring the provider clears its stored marks. The internal
  event handler is registered once and guarded by a context check, so it
  becomes a no-op after disposal and reactivates on the next setup.

## Appearance

The three default mark types use `┃` for additions and changes and `▁` for
deletions, priority `7`, and vgit's own sign highlights:

```lua
marks = {
    VGitAdd = { text = { "┃" }, priority = 7, highlight = "GitSignsAdd" },
    VGitChange = { text = { "┃" }, priority = 7, highlight = "GitSignsChange" },
    VGitDelete = { text = { "▁" }, priority = 7, highlight = "GitSignsDelete" },
}
```

Override `text`, `priority`, or `highlight` under the top-level
`marks` table as usual.

## Limitations

- The provider relies on vgit's undocumented internal modules
  (`git_buffer_store`, `GitBuffer.state.signs`, and `settings.signs`). Every
  access is defensive: unexpected shapes yield zero marks instead of errors,
  but an upstream refactor can silently stop producing marks until retested.
- Marks appear only once vgit's live gutter has fetched the buffer. Disabling
  vgit's live gutter leaves `state.signs` empty, so the scrollbar emits no
  VGit marks either. The provider never forces a fetch or shells out to git
  itself.
- The deferred refresh adds a 50 ms delay between vgit's sign computation and
  the scrollbar update. In very large repositories where `git diff` takes
  longer, marks may be briefly stale until the next event or
  `:ScrollbarRefresh`.
- Enabling `vgit` alongside `gitsigns`, `mini_diff`, or `signify` is supported,
  but all describe diff data and their marks can overlap visually. Disable the
  others or adjust typed lanes and priorities if the duplication is not
  desired.

## Troubleshooting

- No marks after enabling: confirm vgit's live gutter is enabled and shows
  signs in the sign column, then run `:ScrollbarRefresh`.
- vgit loaded late: run `:ScrollbarRefresh` after vgit has attached to the
  buffer, or trigger any edit to fire the internal `change` event.
- Marks vanish after a vgit upgrade: an internal module shape may have changed;
  confirm `require("vgit.git.git_buffer_store").get({ bufnr = 0 })` still
  returns a buffer with `state.signs`.
- Duplicate diff marks: disable `gitsigns`, `mini_diff`, `signify`, or `vgit`,
  or place their mark types in different lanes.
- Unexpected colors: inspect `GitSignsAdd`, `GitSignsChange`, and
  `GitSignsDelete`, or override the mark highlights.

## Related Links

- [vgit.nvim](https://github.com/tanvirtin/vgit.nvim)
- [Provider index](README.md)
- [Gitsigns provider](gitsigns.md)
- [MiniDiff provider](mini_diff.md)
- [Signify provider](signify.md)
- [Highlight configuration](../highlights.md)
