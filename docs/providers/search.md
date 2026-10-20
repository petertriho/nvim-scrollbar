# Search Provider

The built-in search provider adds scrollbar marks for matches from the native
`/` and `?` search of Neovim. The provider is enabled by default and has no
optional dependency.

![Search marks appear while a pattern is typed, then n jumps between the matches](https://github.com/user-attachments/assets/45b02437-b7c7-4b25-a684-c7d5244a313c)

## Configuration

The default configuration uses the worker backend and the current `incsearch`
option of Neovim:

```lua
require("scrollbar").setup({
    providers = {
        search = {
            backend = "worker",
        },
    },
})
```

`providers.search = true` is equivalent to that table. To disable search marks,
set `providers.search` to `false`.

| Option | Default | Meaning |
| --- | --- | --- |
| `incsearch` | omitted (`nil`) | Uses the value of `vim.o.incsearch`. An explicit `true` or `false` overrides it. |
| `backend` | `"worker"` | `"worker"` or `"sync"`. The selected backend runs every accepted, incremental, and edit-driven scan. |

The table also accepts the `scrollbar` and `minimap` target flags. If you omit
`incsearch`, a change to the native option takes effect without another setup.
An explicit `incsearch` value does not change the native option of Neovim.

## Accepted And Incremental Modes

In accepted-search mode, the provider updates marks after you accept a `/` or
`?` search. You can force this mode for large buffers when you do not want
typing on the search command line to start preview scans:

```lua
require("scrollbar").setup({
    providers = {
        search = { incsearch = false },
    },
})
```

`incsearch = true` forces previews of the current command-line pattern, even
when the native Neovim option is disabled:

```lua
require("scrollbar").setup({
    providers = {
        search = { incsearch = true },
    },
})
```

Incremental previews have this behavior:

- The provider supports both forward and backward command lines.
- An empty incremental pattern leaves the previous accepted result visible.
- An invalid incremental pattern produces no preview marks.
- If you cancel the command line, the provider restores the previous accepted
  result when that result was natively visible.
- If you accept the command line, the provider commits the new accepted-search
  result.

After an edit, the provider scans the buffer again with the current accepted
pattern. The provider does not scan a hidden buffer. It scans the buffer when
an eligible source window shows it.

## Visibility Requirements

Accepted search marks use the native search-highlight visibility of Neovim. The
provider shows them only when all of these conditions are true:

- `hlsearch` is enabled.
- `v:hlsearch` is nonzero.
- The `/` search register is nonempty.
- The buffer is displayed in an eligible source window.

`:nohlsearch`, `set nohlsearch`, and an empty search register each clear the
accepted search marks. A later accepted search can make them visible again. The
provider does not enable `hlsearch` or undo `:nohlsearch` for you.

While an incremental `/` or `?` command line is active, the provider can show
the preview even when the previous accepted search is hidden. After the command
line closes, accepted marks again obey the native visibility rules above.

The scrollbar also does not show search marks in these cases:

- It is excluded.
- Master visibility is disabled.
- `max_lines` limits it.
- Autohide conceals it.
- It is hidden because the document fits.

See [Visibility](../visibility.md).

## Vim Regular Expressions

The provider uses the native Vim regular-expression engine of Neovim, not Lua
patterns. Both backends support normal Vim search behavior. This includes:

- escaped alternation
- zero-width matches
- multiline matches
- `ignorecase`, `smartcase`, `magic`, and buffer-local `iskeyword`
- pattern atoms such as `\c` and `\C`

The provider keeps multiple matches on one line. It marks a multiline match at
its start line.

The worker backend uses only the buffer text and the `ignorecase`,
`smartcase`, `magic`, and buffer-local `iskeyword` options. Other editor
options and window or editor state are not available to the worker. This
includes:

- customized options that atoms such as `\i`, `\f`, or `\p` use
- cursor-, Visual-, or mark-dependent atoms such as `\%#`, `\%V`, and `\%'m`

For those patterns, use `backend = "sync"`. The synchronous backend runs in an
eligible source window and preserves the view of that window. The same buffer
can appear in multiple windows with different window-local context. In that
case, the selected source window can still affect the results.

## Backends

### Worker

`backend = "worker"` is the default. The provider starts one embedded headless
Neovim process from `vim.v.progpath`. All searched buffers share this process.
Scans run outside the event loop of the parent Neovim.

A new setup stops the existing worker before it starts a replacement. If the
new configuration selects the synchronous backend, no replacement starts. The
worker also stops when the parent Neovim exits.

### Synchronous

If you do not want to start a child process, use the synchronous backend. Also
use it if a pattern depends on source-window state that the worker does not
have:

```lua
require("scrollbar").setup({
    providers = {
        search = { backend = "sync" },
    },
})
```

The synchronous backend runs the scan on the main loop of Neovim. Each scan has
fixed time and line limits. When a scan reaches a limit, the provider publishes
the matches that it found so far. As a result, marks can be incomplete for
very large buffers or slow patterns.

The synchronous backend also supports incremental scans:

```lua
require("scrollbar").setup({
    providers = {
        search = {
            incsearch = true,
            backend = "sync",
        },
    },
})
```

## Performance Guidance

- For large buffers, dense matches, or patterns that may be expensive, keep the
  default worker backend.
- If incremental feedback is not essential, set `incsearch = false`. This
  applies especially while you edit large files.
- Use the synchronous backend for state-dependent Vim patterns, or for
  environments that do not permit the embedded child process. The synchronous
  backend is not a performance optimization.
- Every scan runs the real Vim regular-expression engine. As a result,
  pathological patterns can stay expensive.

## Worker Fallback

If the worker cannot start or exits unexpectedly, the provider warns once. Then
it uses the synchronous backend for the rest of that setup.

After a failure, the worker does not restart automatically within the same
setup. A new `require("scrollbar").setup(...)` call replaces that setup.
Depending on the new configuration, the new setup can start a new worker.

## Appearance

Search marks use the `Search` mark type. To put the type in its own lane, use
`scrollbar.layout`. Customize the glyphs, the priority, or the highlight in the
top-level `marks.Search`:

```lua
require("scrollbar").setup({
    marks = {
        Search = {
            text = { "s", "S" },
            priority = 1,
            highlight = { fg = "#ff9e64", bold = true },
        },
    },
})
```

The text list contains density variants. When multiple matches compress into
the same rendered row, the row uses later entries. For the complete appearance
rules, see [Highlights](../highlights.md) and
[Layout and geometry](../layout-and-geometry.md).

## Troubleshooting

### No accepted search marks

- Examine the results of `:set hlsearch?`, `:echo v:hlsearch`, and `:echo @/`.
- After `:nohlsearch`, accept a new `/` or `?` search to restore native
  visibility.
- Make sure that `providers.search` is enabled.
- Make sure that the buffer is displayed in an eligible source window.

If marks exist but the scrollbar is not visible, examine these items: master
visibility, autohide, the top-level `exclude` table, `max_lines`, and the
hide-if-all-visible options. `:ScrollbarRefresh` refreshes data, but it does not
show a window that autohide conceals.

### No incremental preview

Examine the result of `:set incsearch?`. If `providers.search.incsearch` is
omitted, the provider uses that native value. To force previews regardless of
the native option, set `providers.search.incsearch = true`.

Incremental preview applies only while you edit a `/` or `?` command line. An
empty pattern keeps the accepted marks. By design, an invalid Vim pattern
produces no preview.

### Worker fallback warning

The warning gives the reason after this text:

```text
[nvim-scrollbar] search worker failed; using synchronous fallback:
```

Search continues with the synchronous fallback. If your environment
intentionally blocks an embedded headless Neovim process, configure
`backend = "sync"`.

### Results differ for a stateful pattern

If the pattern depends on cursor, Visual, mark, or other window or editor
state, select `backend = "sync"`. If several windows show the buffer, the
synchronous scan still uses one eligible source window as its context.

### Editing pauses during search

Examine the configured backend. Then look for a worker fallback warning. With
the synchronous backend, or after a worker fallback, scans run on the main
loop of Neovim. For expensive searches, prefer the worker backend and set
`incsearch = false`. You can also reduce the cost of the buffer or the pattern.

### Marks look briefly out of date

While a new scan runs, the previous accepted marks stay visible. This behavior
prevents flicker during rapid searches and continuous edits. A new accepted
search or `:ScrollbarRefresh` can request a refresh, but a slow scan must still
finish before new marks show.

## Related Links

- [Provider index](README.md)
- [Visibility and commands](../visibility.md)
- [Highlights](../highlights.md)
- [Layout and geometry](../layout-and-geometry.md)
