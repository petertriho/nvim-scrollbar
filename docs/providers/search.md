# Search Provider

The built-in search provider adds scrollbar marks for matches from Neovim's
native `/` and `?` search. It is enabled by default and has no optional
dependency.

## Configuration

The default configuration is accepted-search mode with the worker backend:

```lua
require("scrollbar").setup({
    providers = {
        search = {
            live = false,
            backend = "worker",
        },
    },
})
```

`providers.search = true` is equivalent to that table. Set it to `false` to
disable search marks.

The table accepts these fields:

| Option | Default | Meaning |
| --- | --- | --- |
| `live` | `false` | Preview valid patterns while the `/` or `?` command line changes. |
| `backend` | `"worker"` | Use `"worker"` or `"sync"` for every accepted, live, and edit-driven scan. |

Live mode uses the configured backend. It is not always synchronous: with the
default configuration, both accepted searches and live previews are scanned by
the worker.

## Accepted And Live Modes

Accepted-search mode updates marks after a `/` or `?` search is accepted. This
is the default and is usually the best choice for large buffers because typing
on the search command line does not start preview scans.

Live mode previews the current command-line pattern after a short debounce:

```lua
require("scrollbar").setup({
    providers = {
        search = { live = true },
    },
})
```

Live behavior follows these rules:

- Forward and backward command lines are both supported.
- Pending live changes are debounced and coalesced. An obsolete scan that has
  already started may finish, but its result cannot replace the newest request.
- An empty live pattern leaves the previous accepted result visible.
- An invalid live pattern produces no preview marks.
- Cancelling the command line restores the previous accepted result when that
  result was natively visible.
- Accepting the command line commits the new accepted-search result.

## Visibility Requirements

Accepted search marks follow Neovim's native search-highlight visibility. They
are shown only when all of the following are true:

- `hlsearch` is enabled.
- `v:hlsearch` is nonzero.
- The `/` search register is nonempty.
- The buffer is displayed in an eligible scrollbar source window.

`:nohlsearch`, `set nohlsearch`, or an empty search register clears accepted
search marks. A later accepted search can make them visible again. The provider
does not enable `hlsearch` or undo `:nohlsearch` for you.

During an active live `/` or `?` command line, the preview may be displayed even
when the previous accepted search is hidden. Once the command line closes,
accepted marks return to the native visibility rules above.

Search marks can also be unavailable because the scrollbar itself is excluded,
globally hidden, limited by `max_lines`, concealed by autohide, or hidden because
the document fits. See [Visibility](../visibility.md). Provider
updates and `:ScrollbarRefresh` do not reveal a scrollbar concealed by
autohide.

## Vim Regular Expressions

The provider uses Neovim's native Vim regular-expression engine, not Lua
patterns. Both backends support normal Vim search behavior, including escaped
alternation, zero-width matches, multiline matches, `ignorecase`, `smartcase`,
`magic`, buffer-local `iskeyword`, and pattern atoms such as `\c` and `\C`.
Multiple matches on one line are retained, and a multiline match is marked at
its starting line.

The worker mirrors buffer text plus `ignorecase`, `smartcase`, `magic`, and
buffer-local `iskeyword`. Patterns whose meaning depends only on that state
produce the same results as the synchronous backend while keeping the expensive
scan off the parent event loop.

Other editor options and window or editor state are not generally mirrored.
This includes customized options used by atoms such as `\i`, `\f`, or `\p`, and
cursor-, Visual-, or mark-dependent atoms such as `\%#`, `\%V`, and `\%'m`. Use
`backend = "sync"` for those patterns. The synchronous backend runs in an
eligible source window and preserves its view; if the same buffer appears in
multiple windows with different window-local context, the selected source
window can still matter.

## Backends

### Worker

`backend = "worker"` is the default. The provider starts an embedded headless
Neovim process from `vim.v.progpath` and shares it across searched buffers. A
buffer is mirrored when its first worker scan is requested; subsequent edits
keep that mirror synchronized until the buffer is deleted or the worker is
disposed. Scans run outside the parent Neovim event loop.

There is at most one active search worker for each plugin setup. Reconfiguring
the plugin disposes the existing worker before starting its replacement; a
configuration that selects the synchronous backend starts no replacement.
Parent Neovim shutdown also disposes the worker.

### Synchronous

Use the synchronous backend to avoid starting a child process or when a pattern
depends on source-window state that the worker does not mirror:

```lua
require("scrollbar").setup({
    providers = {
        search = { backend = "sync" },
    },
})
```

The synchronous backend uses the same native Vim-regex scan on the parent main
loop. It preserves the selected source window's view, but an expensive pattern
or a large dense result set can pause editing until the scan completes.

Live synchronous scanning is also supported:

```lua
require("scrollbar").setup({
    providers = {
        search = {
            live = true,
            backend = "sync",
        },
    },
})
```

## Requests And Updates

Requests are tracked independently per buffer. Accepted searches run on the next
safe main-loop turn; live changes and edit-driven rescans use short debounces.
Rapid replacements are coalesced, and only the newest request whose buffer
version, pattern, options, and visibility are still current may publish.

The previous accepted result normally remains visible while its replacement is
pending. This avoids flicker during rapid searches and continuous edits. It also
means briefly seeing old marks while a slow current scan is running is expected.

The provider also notices changes to the accepted search register, search
visibility, and match-affecting options during normal editor events. Entering a
displayed buffer requests its result; hidden buffers are not scanned eagerly
solely to populate scrollbar marks.

## Rescanning After Edits

Changes reported by Neovim's normal, Insert-mode, and completion-related text
events schedule a debounced rescan of the current accepted pattern for that
buffer. Repeated edits collapse into one current request, and stale results from
an older buffer version are rejected.

With the worker backend, already searched buffers are kept synchronized as they
change. With the synchronous backend, the eventual rescan runs on the parent
main loop. In both cases, buffers without an eligible source window are deferred
until they are displayed.

## Performance Guidance

- Keep the default worker backend for large buffers, dense matches, or patterns
  that may be expensive.
- Prefer accepted mode when live feedback is not essential, especially while
  editing large files.
- Use synchronous mode for state-dependent Vim patterns or environments that do
  not permit the embedded child process, not as a performance optimization.
- Search requests and edit rescans are coalesced, but every eventual scan still
  executes the real Vim regex. Pathological patterns can therefore remain
  expensive.
- The worker handles one scan at a time and prioritizes current requests. Rapid
  changes may leave a pending request briefly visible in worker status, but
  obsolete results are not published.

## Worker Fallback

If the worker cannot start or exits unexpectedly, the provider warns once and
switches that setup to the debounced synchronous scanner. Current and future
requests continue through the fallback, but expensive scans can then pause the
parent Neovim process.

The worker is not automatically restarted within the same setup after failure.
Running `require("scrollbar").setup(...)` again replaces the failed setup and may
start a new worker, depending on the new configuration.

## Worker Status

Inspect worker state with:

```vim
:lua print(vim.inspect(require("scrollbar.providers.search_worker").status()))
```

Or from Lua:

```lua
local status = require("scrollbar.providers.search_worker").status()
```

Important fields are:

| Field | Interpretation |
| --- | --- |
| `state` | `"starting"`, `"ready"`, `"failed"`, or `"disposed"`. |
| `job_id` | Neovim job ID while a worker process is active; otherwise `nil`. |
| `session` | Opaque worker generation identifier; changes when the worker is replaced. |
| `mirrors` | Buffers attached because a worker scan was requested. `complete = false` means initial synchronization is still in progress. |
| `in_flight` | The one request currently being scanned, or `nil`. |
| `pending_count` | Number of buffers with a newer request waiting to run. |
| `max_in_flight` | Highest observed scan concurrency for this worker; normal operation is at most `1`. |
| `argv` | Command used to start the worker. |

Interpret `state` in configuration context:

- `ready` with a non-nil `job_id` is the normal healthy worker state.
- `starting` is normal briefly after setup while the child initializes.
- `failed` means the provider has switched to synchronous fallback. A nil
  `job_id` is expected in this state.
- `disposed` is normal when `backend = "sync"`, when the provider is disabled or
  disposed, and after shutdown. It does not by itself indicate a failure.

## Appearance

Search marks use the `Search` mark type. Customize their glyphs, column,
priority, or highlight through `marks.Search`:

```lua
require("scrollbar").setup({
    marks = {
        Search = {
            text = { "s", "S" },
            column = 1,
            priority = 1,
            highlight = { fg = "#ff9e64", bold = true },
        },
    },
})
```

The text list contains density variants: later entries are used when multiple
matches compress into the same rendered row. See
[Highlights](../highlights.md) and
[Wide scrollbars](../layout-and-geometry.md#wide-scrollbars) for the complete appearance
rules.

## Troubleshooting

### No accepted search marks

Check `:set hlsearch?`, `:echo v:hlsearch`, and `:echo @/`. After
`:nohlsearch`, accept a new `/` or `?` search to restore native visibility. Also
confirm that `providers.search` is enabled and that the buffer is displayed in
an eligible source window.

If marks exist but the scrollbar is not visible, check global visibility,
autohide, excluded buffer/file types, `max_lines`, and the hide-if-all-visible
settings. `:ScrollbarRefresh` refreshes data but does not reveal an autohide
window.

### No live preview

Confirm `providers.search.live = true`. Live preview applies only while editing
a `/` or `?` command line. Empty patterns retain accepted marks, and invalid Vim
patterns intentionally produce no preview.

### Worker reports `failed`

Search should continue through synchronous fallback. Review the warning and the
status `argv` for process-start restrictions. Configure `backend = "sync"` if
the environment intentionally disallows an embedded headless Neovim process.

### Results differ for a stateful pattern

If the pattern depends on cursor, Visual, mark, or other window/editor state,
select `backend = "sync"`. For a buffer displayed in several windows, remember
that the synchronous scan still uses one eligible source window as its context.

### Editing pauses during search

Check the configured backend and worker status. A synchronous configuration or
a `failed` worker runs scans on the parent event loop. Prefer the worker backend
and disable live mode for expensive searches.

### Marks look briefly out of date

This is normally the pending-result behavior: existing accepted marks remain
until the newest valid request completes. A new accepted search or
`:ScrollbarRefresh` can request a refresh, but slow current scans still need to
finish before new marks publish.

## Related Links

- [Provider index](README.md)
- [Provider setup and strict configuration](README.md#setup)
- [Visibility and commands](../visibility.md)
- [Highlights](../highlights.md)
- [Wide scrollbars](../layout-and-geometry.md#wide-scrollbars)
