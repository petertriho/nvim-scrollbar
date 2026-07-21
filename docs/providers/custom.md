# Custom Providers

Custom providers publish data through `require("scrollbar.providers")`. They
can own ordinary typed marks for scrollbar lanes or minimap overlays, semantic
byte spans for minimap content, exact byte points for minimap cells, or any
combination of those channels.

## Configure Mark Types

Every emitted ordinary `mark.type` must be configured for at least one
consumer. Scrollbar marks use `text`, `priority`, and `highlight`; minimap
overlay specs use only `priority` and `highlight`:

```lua
require("scrollbar").setup({
    scrollbar = {
        marks = {
            Bookmark = {
                text = { ".", "*", "#" },
                priority = 1,
                highlight = "Special",
            },
        },
    },
    minimap = {
        enabled = true,
        overlays = {
            types = {
                Bookmark = { priority = 2, highlight = "Special" },
            },
        },
    },
})
```

Custom provider names or options do **not** go under `providers`. That table
is a strict built-in allow-list in both the scrollbar and minimap config and
rejects unknown keys. Keep provider-specific configuration in your own module
or closure, and register the provider through the manager API.

For a new scrollbar type, `text`, `priority`, and `highlight` are required. For
a minimap-only type, `priority` and `highlight` are required. Partial tables are
valid only when a derived or built-in fallback supplies missing fields.

Mark type names must match `^[%a_][%w_]*$`. `text` is a string or dense list of
density variants, `priority` is a non-negative integer where lower values win
within one lane, and
`highlight` is a non-empty group name or an `nvim_set_hl()` definition table.
Names must also leave public highlight ownership unambiguous: minimap `Base`,
`Content`, `Viewport`, and `Cursor` are reserved, and setup rejects pairs such
as scrollbar `MinimapSearch` plus minimap `Search` because both would own
`ScrollbarMinimapSearch`. Scrollbar names such as `Track`, `Handle`, and
`SearchThumb` are likewise rejected when they collide with fixed, overlap,
pressed, or legacy groups.
An emitted mark may supply its own non-empty `text` override. `Mark` is special:
provider text is used only while `scrollbar.marks.Mark.text = {}`; a non-empty
configured `Mark` list replaces provider text.

## Registration

Register before or after scrollbar setup:

```lua
local providers = require("scrollbar.providers")

providers.register({
    name = "bookmarks",
    refresh_owner = { buffer = "manager" },
    refresh = function(bufnr)
        return {
            { line = 0, type = "Bookmark" },
            { line = vim.api.nvim_buf_line_count(bufnr) - 1, type = "Bookmark", text = "B" },
        }
    end,
})

require("scrollbar").setup({
    scrollbar = {
        marks = {
            Bookmark = {
                text = { ".", "*", "#" },
                priority = 1,
                highlight = "Special",
            },
        },
    },
})

providers.unregister("bookmarks")
```

Omitting `targets` makes a custom provider scrollbar-only. To publish for the
minimap, declare it explicitly:

```lua
local providers = require("scrollbar.providers")

providers.register({
    name = "semantic_bookmarks",
    targets = { minimap = true },
    refresh_owner = { minimap_buffer = "manager" },
    refresh_minimap = function(bufnr)
        local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, true)[1] or ""
        if line == "" then
            return {}
        end
        return {
            {
                line = 0,
                start_col = 0,
                end_col = #line,
                highlight = "Special",
                priority = 100,
            },
        }
    end,
})
```

Ordinary minimap overlays still come from `refresh` or `refresh_window`; target
the minimap and configure the type under `minimap.overlays.types`:

```lua
providers.register({
    name = "minimap_bookmarks",
    targets = { minimap = true },
    refresh_owner = { buffer = "manager" },
    refresh = function()
        return { { line = 0, type = "Bookmark" } }
    end,
})
```

When `targets` is present, omitted target fields are `false`; at least one of
`scrollbar` or `minimap` must be `true`. Unknown target keys and non-boolean
values are registration errors. `refresh_minimap` and
`refresh_minimap_window` require `targets.minimap = true`.

- Names must be non-empty and unique; duplicate registration raises an error
  and does not replace the existing provider.
- Registration before setup defers activation. Registration after setup runs
  `setup`, then immediately performs initial eligible refreshes.
- `unregister(name)` returns `true` when it removed a provider and `false` when
  no provider had that name.
- `get(name)` returns the registered provider table or `nil`.

> **Avoid built-in names:** `cursor`, `diagnostic`, `search`, `marks`,
> `gitsigns`, `mini_diff`, `signify`, `vgit`, `ale`, `coc`, `treesitter`, and
> `lsp_semantic_tokens`. Registering one before root setup shadows that built-in.
> Registering afterward fails only when the name is currently registered, which
> is normally true for default-on providers but not necessarily for optional or
> explicitly disabled providers. Built-in enable/disable options never manage or
> remove a custom provider using the same name.

## Provider Interface

```lua
---@alias ScrollbarProviderRefreshOwner "manager"|"provider"

---@class ScrollbarProviderRefreshOwnership
---@field buffer? ScrollbarProviderRefreshOwner
---@field window? ScrollbarProviderRefreshOwner
---@field minimap_buffer? ScrollbarProviderRefreshOwner
---@field minimap_window? ScrollbarProviderRefreshOwner

---@class ScrollbarProvider
---@field name string
---@field targets? { scrollbar?: boolean, minimap?: boolean }
---@field refresh_owner? ScrollbarProviderRefreshOwnership
---@field setup? fun(context: ScrollbarProviderContext)
---@field refresh? fun(bufnr: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field refresh_window? fun(winid: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field refresh_minimap? fun(bufnr: integer, context: ScrollbarProviderContext): ScrollbarMinimapSourceSpan[]?
---@field refresh_minimap_window? fun(winid: integer, context: ScrollbarProviderContext): ScrollbarMinimapSourcePoint[]?
---@field dispose? fun(context: ScrollbarProviderContext)
```

`refresh` publishes ordinary marks shared by every accepted source window
displaying a buffer. `refresh_window` publishes ordinary marks owned by one
source window. The minimap can project those marks as row overlays when the
provider targets it and the mark type is allowed by `minimap.overlays.types`.
An allowed type is one present in the selected effective keyed map.

`refresh_minimap` publishes semantic spans shared by minimap source windows for
a buffer. `refresh_minimap_window` publishes exact points owned by one minimap
source window. All four callback outputs are independently stored and replaced.

Ownership scopes must correspond exactly to callbacks:

| Callback | Required `refresh_owner` scope |
| --- | --- |
| `refresh` | `buffer` |
| `refresh_window` | `window` |
| `refresh_minimap` | `minimap_buffer` |
| `refresh_minimap_window` | `minimap_window` |

Implement any combination of callbacks and declare exactly the corresponding
scopes; omit `refresh_owner` when no refresh callback exists. Each owner must be
exactly `"manager"` or `"provider"`. Missing owners, owner keys without matching
callbacks, unknown scope keys, and non-table `refresh_owner` values are
registration errors. Provider tables may still use private top-level fields for
their own configuration.

## Automatic Refresh Rules

After successful activation, the manager attempts each implemented callback for
the provider's current eligible buffers or source windows, regardless of owner.
Each callback still applies its channel policy, so minimap callbacks publish only
to minimap-eligible targets. Ownership controls only subsequent automatic
dispatch:

| Scope and owner | Automatic behavior |
| --- | --- |
| Buffer `"manager"` | The manager calls `refresh` on `BufEnter`, `TextChanged`, `TextChangedI`, and `TextChangedP` |
| Buffer `"provider"` | The manager sends no automatic buffer refresh; the provider owns subscriptions and publication |
| Window `"manager"` | The manager calls `refresh_window` on `BufWinEnter` and `WinEnter` |
| Window `"provider"` | The manager sends no automatic window refresh; the provider owns subscriptions and publication |
| Minimap buffer `"manager"` | The manager calls `refresh_minimap` on `BufEnter`, `TextChanged`, `TextChangedI`, and `TextChangedP` |
| Minimap buffer `"provider"` | The manager sends no automatic minimap-buffer refresh |
| Minimap window `"manager"` | The manager calls `refresh_minimap_window` on `BufWinEnter` and `WinEnter` |
| Minimap window `"provider"` | The manager sends no automatic minimap-window refresh |

On `BufWinEnter`, manager-owned window marks and minimap points are cleared
before their corresponding new window association is refreshed. They are also
cleared when the window is no longer eligible. Provider-owned window channels
must manage their own event-time clearing.

`setup` and `dispose` describe resource lifecycle only. A provider may acquire
resources in `setup` while retaining manager scheduling by choosing
`"manager"`, or choose `"provider"` and subscribe to its own events. An empty,
present, or omitted `setup` has no scheduling meaning.

Manual refresh is ownership-independent but consumer-aware:

- `:ScrollbarRefresh` calls `refresh` and `refresh_window` only for providers
  consumed by the scrollbar. It never calls minimap span or point callbacks.
- `:MinimapRefresh` calls ordinary `refresh` and `refresh_window` for providers
  consumed by the minimap, plus `refresh_minimap` and
  `refresh_minimap_window`. It excludes scrollbar-only providers.
- Both commands use their renderer's current source buffers/windows, queue that
  renderer, and do not reveal hidden or autohide-concealed floats.

The Lua manager APIs support the same filtering:

```lua
local providers = require("scrollbar.providers")

providers.refresh(bufnr, { consumer = "minimap", channel = "minimap_spans" })
providers.refresh_window(winid, { consumer = "minimap", channel = "minimap_points" })
```

Omit the options to attempt every active channel. Valid buffer channels are
`marks` and `minimap_spans`; valid window channels are `marks` and
`minimap_points`.

## Event-Driven Example

```lua
local function collect(bufnr)
    -- Replace this with provider-owned state collection.
    return { { line = 0, type = "Bookmark" } }
end

require("scrollbar.providers").register({
    name = "bookmark_events",
    refresh_owner = { buffer = "provider" },

    setup = function(context)
        local group = context.create_augroup("updates")
        vim.api.nvim_create_autocmd("User", {
            group = group,
            pattern = "BookmarksChanged",
            callback = function(args)
                local bufnr = args.buf ~= 0 and args.buf or vim.api.nvim_get_current_buf()
                if context.is_buffer_eligible(bufnr) then
                    context.set_marks(bufnr, collect(bufnr))
                else
                    context.clear_marks(bufnr)
                end
            end,
        })
    end,

    refresh = function(bufnr)
        return collect(bufnr)
    end,
})
```

The `refresh` method supplies the initial and manual-refresh path. The provider's
own event supplies automatic updates because the buffer scope is provider-owned.

## Publishing Semantics

Every provider/target/channel list is a complete replacement, not an
incremental patch.

- Returning a list replaces that callback's ordinary marks, minimap spans, or
  minimap points.
- Returning `{}` explicitly stores an empty replacement and clears visible
  output for that channel.
- Returning `nil` from any refresh callback means "do not publish" and normally
  leaves that list unchanged. Policy is checked again after the callback, so a
  target that became ineligible during collection is cleared instead.
- Passing `nil` to a context setter is not the same as returning `nil`; it is an
  invalid list. Use the corresponding clear method.

The scrollbar and minimap have independent eligibility policies. For a custom
provider, `is_buffer_eligible`, `is_source_window`, and `source_windows` query
the union selected by `targets`. Ordinary mark setters use that union. Minimap
span and point setters always require minimap eligibility.

Buffer-scoped publication does not require the buffer to be displayed or
currently selected. Window-scoped publication requires a valid normal
non-renderer window in the relevant current source-window set, after that
renderer applies eligibility, `visibility`, profiles, and editor-relative
placement.

Policy is enforced before payload validation for valid targets. Publishing to a
valid but ineligible target silently clears only this provider's corresponding
stored channel and returns `false`. Repeating the rejection emits no store event
when nothing was stored. Invalid IDs still use normal validation and warning
behavior. Clear operations are unconditional and remain available regardless of
policy.

### Ordinary Mark Schema

Ordinary lists are dense arrays whose entries contain only:

```lua
{
    line = 0,          -- required zero-based source line
    type = "Bookmark", -- required configured scrollbar or minimap type
    text = "B",        -- optional printable, positive-width override
}
```

Ordinary collision priority is consumer-specific: scrollbar lanes read
`scrollbar.marks.<Type>.priority`, while projected minimap rows read
`minimap.overlays.types.<Type>.priority`. Both use lower numeric values first.

### Minimap Span Schema

Minimap span lists are dense arrays whose entries contain exactly these required
fields:

```lua
{
    line = 0,            -- zero-based source line
    start_col = 0,       -- zero-based byte offset, inclusive
    end_col = 4,         -- zero-based byte offset, exclusive; > start_col
    highlight = "String", -- non-empty highlight group
    priority = 100,      -- any finite integer; higher values win
}
```

Columns are byte offsets in the source line, not character, codepoint, or
display columns. Emit valid byte boundaries when working with multibyte text.
Spans color occupied squashed content cells; they do not create density.

### Minimap Point Schema

Minimap point lists are dense arrays whose entries contain exactly these
required fields:

```lua
{
    line = 0,                         -- zero-based source line
    col = 4,                          -- zero-based source byte offset
    highlight = "ScrollbarMinimapCursor",
    priority = 200,                   -- any finite integer; higher values win
}
```

Points project to exact minimap cells for one source window. Their byte columns
are converted to display columns during projection.

Every complete list is validated atomically. A negative/non-integer position,
unknown or missing field, invalid highlight, invalid ordinary type/text, or
malformed list clears only this provider's failing channel for that target,
returns `false`, and emits a rate-limited warning. Other channels and providers
remain intact.

As a narrow race allowance, otherwise-valid entries whose zero-based `line` is
past the current EOF are silently omitted in all three schemas. Valid survivors
are published, and a list containing only stale entries becomes an accepted
empty replacement. A stale line does not hide another malformed field on the
same entry.

## Context Operations

| Context member | Behavior |
| --- | --- |
| `config` | Deep-copied normalized `scrollbar` config snapshot; mutations do not change root configuration |
| `set_marks(bufnr, marks)` | Union-policy-check, validate, and replace buffer-scoped ordinary marks; return whether publication was accepted |
| `clear_marks(bufnr?)` | Unconditionally clear one buffer, or all buffer marks owned by this provider when omitted |
| `set_window_marks(winid, marks)` | Union-policy-check, validate, and replace ordinary marks local to one current source window |
| `clear_window_marks(winid?)` | Unconditionally clear one window, or all window marks owned by this provider when omitted |
| `set_minimap_spans(bufnr, spans)` | Minimap-policy-check, validate, and replace buffer-scoped semantic byte spans |
| `clear_minimap_spans(bufnr?)` | Unconditionally clear one buffer, or all minimap spans owned by this provider when omitted |
| `set_minimap_points(winid, points)` | Minimap-policy-check, validate, and replace byte points local to one minimap source window |
| `clear_minimap_points(winid?)` | Unconditionally clear one window, or all minimap points owned by this provider when omitted |
| `create_augroup(name)` | Create a provider-owned, namespaced augroup removed during cleanup |
| `add_cleanup(fn)` | Register a provider-owned cleanup callback |
| `is_buffer_eligible(bufnr)` | Query live eligibility across the provider's declared target union |
| `is_source_window(winid)` | Query live source membership across the provider's declared target union |
| `source_windows(bufnr?)` | Return the copied, de-duplicated target-union source-window list, optionally filtered by buffer |
| `invalidate_buffer(bufnr)` | Invoke an optional manager invalidation hook; normal top-level setup relies on store publication events instead |
| `invalidate_window(winid)` | Invoke an optional manager invalidation hook; normal top-level setup relies on store publication events instead |

Setters return whether publication was accepted. `false` can mean policy
rejection or validation failure; preflight with the policy queries when the
distinction matters. Clear methods return whether any stored list changed.
Publishing or clearing changed data emits a provider- and channel-aware store
event. The scrollbar scheduler subscribes to ordinary marks; the minimap
scheduler subscribes to ordinary marks, spans, and points. An identical accepted
list returns `true` without a store event or render queue.

The built-in search provider's compact representation and `_set_search_compact`
context hook are private implementation details. Custom providers publish
ordinary public mark lists; they do not publish compact blobs.

For asynchronous work, use the policy queries to avoid unnecessary collection,
but always treat the setter as the final authority because eligibility can
change between collection and publication. A window provider must republish
when its window becomes a source again; a manager-owned window scope can rely on
the manager's `refresh_window` activation events.

## Parent Execution And Worker Transfer

Custom provider code always runs in the parent Neovim process. `setup`, all four
refresh callbacks, provider-owned autocmds, timers, jobs, and cleanup callbacks
are never serialized into or executed inside the minimap worker.
Registration exposes no custom worker-execution mode; a private `execution`
field does not opt a custom provider into child execution.

With `minimap.backend = "worker"`, accepted parent-published minimap spans are
deep-copied into a revisioned semantic snapshot and transferred with the source
buffer mirror before squashing. Ordinary marks stay in the parent-side overlay
path, and minimap points are projected in the parent after worker cells return.
The Treesitter built-in is the only provider whose collection may execute in the
minimap worker; with the sync backend it runs inline. The LSP semantic-token
built-in and every custom provider remain parent-executed.

## Lifecycle And Cleanup

- Root `require("scrollbar").setup()` reconfigures the manager. Registered
  custom providers remain registered, but successful instances are disposed,
  cleaned, and activated again with a fresh context.
- Unregistration calls `dispose` after a successful setup, runs registered
  cleanup callbacks in reverse order, removes provider augroups, and clears all
  four owned publication surfaces. Changed clears notify the subscribed
  schedulers.
- Provider marks and spans are removed when their buffer is deleted; window
  marks and points are removed when their window closes.
- Use `create_augroup` for autocmds and `add_cleanup` for timers, jobs,
  subscriptions, or other resources. Stop asynchronous work during cleanup and
  guard late callbacks with your own active flag or generation; a retained
  context is not a cancellation token.
- Resource acquisition in `setup` does not require provider-owned refresh. Use a
  `"manager"` owner when the standard manager events are sufficient, and avoid
  installing duplicate provider subscriptions for the same scope.

## Failure Isolation

The manager guards calls to `setup`, all four refresh callbacks, `dispose`, and
registered cleanup callbacks.

- A setup failure disables that provider instance, runs cleanup callbacks
  already registered with `context.add_cleanup`, removes augroups created
  through `context.create_augroup`, clears its published channels, warns, and
  allows other providers to activate. Unregistered timers, jobs, subscriptions,
  and similar resources remain the provider's responsibility.
- A refresh failure clears only the failing provider's corresponding channel for
  that buffer or window. Other channels and providers continue.
- A dispose or cleanup failure warns but does not prevent remaining resource and
  publication cleanup.
- Equivalent setup, refresh, dispose, and validation warnings are suppressed
  until the relevant operation recovers. Cleanup warnings are rate-limited for
  the provider's registration lifetime.

This boundary does not wrap code invoked later by provider-owned autocmds,
timers, jobs, or external callbacks. Handle errors inside those callbacks and
cancel or detach them during cleanup.

## Troubleshooting

- Unknown option under `providers`: remove the custom key and register the
  provider through `require("scrollbar.providers").register()`.
- Registration reports a missing `refresh_owner` scope: declare one owner for
  every implemented refresh callback; omission has no compatibility fallback.
- `mark.type is not configured`: add the type under `scrollbar.marks`,
  `minimap.overlays.types`, or both before the provider first publishes.
- `refresh_minimap requires targets.minimap`: declare
  `targets = { minimap = true }` or a dual-target table.
- No automatic updates with a `"provider"` owner: subscribe to the required
  events and publish through the context, or choose `"manager"` when the fixed
  manager event list fits the provider.
- Output disappears after one invalid item: validation replaces atomically and
  clears only the rejected channel; inspect the warning for the exact field.
- Marks leak back after unregistering: cancel asynchronous work and ignore late
  callbacks from the old provider generation.
- Window-specific state appears in every split: publish it through
  `refresh_window`/`set_window_marks` or
  `refresh_minimap_window`/`set_minimap_points`, not the buffer-scoped
  operations.
- A setter returns `false` without a warning: the valid target was rejected by
  current renderer policy; query `is_buffer_eligible` or `is_source_window`.
- Inactive window output does not appear later: window publication is accepted
  only for current source windows, so republish when the window becomes
  selected.
- Minimap priority appears reversed: ordinary overlays use lower-wins
  `minimap.overlays.types` priority, while minimap spans and points use
  higher-wins integer priority.

## Related Links

- [Provider index](README.md)
- [Mark configuration](../configuration.md#marks)
- [Highlights](../highlights.md)
