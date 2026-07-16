# Providers

Configure built-in providers under `providers` in `require("scrollbar").setup()`.
Provider marks are rendered only on eligible source windows; `max_lines`,
`excluded_buftypes`, and `excluded_filetypes` control that eligibility.

## Built-ins

`Window` scope means each source window has independent marks. `Buffer` scope
means every source window showing the buffer shares the same provider marks.

| Provider | Default | Data source | Scope | Mark types | Dependency |
| --- | --- | --- | --- | --- | --- |
| [`cursor`](cursor.md) | on | Source-window cursor | Window | `Cursor` | None |
| [`diagnostic`](diagnostic.md) | on | `vim.diagnostic` | Buffer | `Error`, `Warn`, `Info`, `Hint`, `Misc` | None |
| [`search`](search.md) | on | Native `/` and `?` search | Buffer | `Search` | None |
| [`marks`](marks.md) | on | Named letter marks; optional numbered marks | Buffer | `Mark` | None |
| [`gitsigns`](gitsigns.md) | off | Git hunks | Buffer | `GitAdd`, `GitChange`, `GitDelete` | [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) |
| [`mini_diff`](mini_diff.md) | off | Hunks from any configured mini.diff source | Buffer | `MiniDiffAdd`, `MiniDiffChange`, `MiniDiffDelete` | [mini.diff](https://github.com/nvim-mini/mini.diff) |
| [`signify`](signify.md) | off | Hunks read from placed `Signify*` signs | Buffer | `SignifyAdd`, `SignifyChange`, `SignifyDelete` | [vim-signify](https://github.com/mhinz/vim-signify) |
| [`vgit`](vgit.md) | off | Hunks read from vgit's internal buffer store | Buffer | `VGitAdd`, `VGitChange`, `VGitDelete` | [vgit.nvim](https://github.com/tanvirtin/vgit.nvim) |
| [`ale`](ale.md) | off | ALE location list | Buffer | `Error`, `Warn` | [ALE](https://github.com/dense-analysis/ale) |
| [`coc`](coc.md) | off | Coc diagnostic list, partitioned by target buffer | Buffer | `Error`, `Warn`, `Info`, `Hint` | [coc.nvim](https://github.com/neoclide/coc.nvim) |

See [Custom providers](custom.md) to publish another data source or apply
provider-specific filtering.

## Setup

```lua
require("scrollbar").setup({
    providers = {
        cursor = true,
        diagnostic = true,
        search = true,
        marks = true,
        gitsigns = false,
        mini_diff = false,
        signify = false,
        vgit = false,
        ale = false,
        coc = false,
    },
})
```

`false` disables a built-in. `true` enables its defaults. `search` and `marks`
also accept provider-specific tables:

```lua
providers = {
    search = { incsearch = false, backend = "worker" },
    marks = { letters = true, numbers = false, max_width = 8 },
}
```

`search = true` normalizes to `{ backend = "worker" }`. With `incsearch`
omitted, incremental previews dynamically follow Neovim's current
`vim.o.incsearch` value. Set `incsearch = true` or `false` to override that
behavior without changing the native option. `marks = true` defaults to
`letters = true`, `numbers = false`, and collapsed width (`max_width` unset).

## Strict Configuration

- Unknown keys are errors. The `providers` table accepts only the ten
  built-in names; register custom providers through the provider API instead of
  adding a custom key here.
- `cursor`, `diagnostic`, `gitsigns`, `mini_diff`, `signify`, `vgit`, `ale`,
  and `coc` must be booleans.
- A `search` table accepts only optional `incsearch` (boolean) and `backend`
  (`"worker"` or `"sync"`). A `marks` table accepts only `letters`, `numbers`,
  and `max_width`.
- `providers.marks.max_width` must be a positive integer at least as large as
  `float.width`.
- Provider output types are styled separately under `marks.<Type>`. Each mark
  definition accepts only `text`, `column`, `priority`, and `highlight`.
  Columns are one-based and must fit within `float.width`; priorities are
  non-negative integers and lower values win overlaps.
- Mark `text` is a string or dense list of strings with positive display width.
  Only `marks.Mark.text` may be empty, which enables literal names from the
  built-in marks provider. Highlights are a non-empty group name or an
  `nvim_set_hl()`-compatible table.
- Every `setup()` call is normalized from the documented defaults rather than
  incrementally modifying the previous setup.

## Updates And Loading

Providers perform an initial refresh during setup. `:ScrollbarRefresh` (or
`require("scrollbar").refresh()`) refreshes each buffer currently shown in an
eligible source window, refreshes those source windows, and queues a rerender.
Provider-specific events are described on each page.
Refreshes can rerender an already revealed scrollbar but do not reveal one
concealed by autohide.

The optional integrations are safe to enable when their dependency is absent;
they produce no marks instead of preventing scrollbar setup. The gitsigns,
mini.diff, and signify providers always own their `User` update autocmd while
enabled, even when the dependency is initially unavailable. The vgit provider
hooks into vgit's internal event bus (`git_buffer_store.on`) instead of owning
autocmds. Configure and load the upstream plugin before
`require("scrollbar").setup()` for deterministic initial data. If it loads
later, the provider adopts its module from `package.loaded` on the next
provider event or `:ScrollbarRefresh`; scrollbar does not configure the upstream
plugin itself.

Gitsigns, mini.diff, signify, and vgit may all be enabled. Their marks are stored
separately, but all describe diff data and can overlap visually; disable
overlapping providers or adjust mark columns and priorities if that duplication
is not desired. ALE and Coc can begin updating from their integration events
after they load, though loading them first still gives predictable initial
state.

## Related

- [README](../../README.md)
- [Configuration](../configuration.md)
- [Layout and geometry](../layout-and-geometry.md)
- [MiniDiff](mini_diff.md)
- [Signify](signify.md)
- [Vgit](vgit.md)
- [Custom providers](custom.md)
