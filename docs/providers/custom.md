# Custom Providers

Custom providers publish data through `require("scrollbar.providers")`. A
custom provider can own one or more of these channels:

- Ordinary typed marks for scrollbar lanes or minimap overlays.
- Semantic byte spans for minimap content.
- Exact byte points for minimap cells.

## Configure Mark Types

You must configure every ordinary `mark.type` that a provider emits for at
least one consumer. Scrollbar marks use `text`, `priority`, and `highlight`.
Minimap overlay specs use only `priority` and `highlight`:

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

Do not put custom provider names or options under `providers`. That table
is a strict built-in allow-list in both the scrollbar and the minimap
configuration, and it rejects unknown keys. Keep provider-specific
configuration in your own module or closure. Register the provider through the
manager API.

A new scrollbar type needs `text`, `priority`, and `highlight`. A minimap-only
type needs `priority` and `highlight`. A partial table is valid only when a
derived or built-in fallback supplies the missing fields.

Mark type names and the `text`, `priority`, and `highlight` fields follow the
rules in [Mark configuration](../configuration.md#marks).

Names must also give each public highlight group one clear owner:

- The minimap names `Base`, `Content`, `Viewport`, and `Cursor` are reserved.
- Setup rejects pairs such as scrollbar `MinimapSearch` and minimap `Search`.
  If setup accepted the pair, both names would own `ScrollbarMinimapSearch`.
- Setup also rejects scrollbar names such as `Track`, `Handle`, and
  `SearchThumb` when they collide with fixed, overlap, pressed, or legacy
  groups.

An emitted mark can supply its own non-empty `text` override. `Mark` is an
exception. Provider text applies only while `scrollbar.marks.Mark.text = {}`. A
non-empty configured `Mark` list replaces the provider text.

## Registration

Register the provider before or after scrollbar setup:

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

If you omit `targets`, the custom provider is scrollbar-only. To publish for
the minimap, declare the minimap target explicitly:

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

Ordinary minimap overlays still come from `refresh` or `refresh_window`. For
these overlays, target the minimap. Also configure the type under
`minimap.overlays.types`:

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

When `targets` is present, omitted target fields are `false`. At least one of
`scrollbar` or `minimap` must be `true`. Unknown target keys and non-boolean
values are registration errors. `refresh_minimap` and
`refresh_minimap_window` require `targets.minimap = true`.

- Names must be non-empty and unique. A duplicate registration raises an error
  and does not replace the existing provider.
- Registration before setup defers activation. Registration after setup runs
  `setup`, then immediately runs the initial refreshes for eligible targets.
- `unregister(name)` returns `true` when it removes a provider, and `false`
  when no provider has that name.
- `get(name)` returns the registered provider table or `nil`.

> **Avoid built-in names:** `cursor`, `diagnostic`, `search`, `marks`,
> `gitsigns`, `mini_diff`, `signify`, `vgit`, `ale`, `coc`, `treesitter`, and
> `lsp_semantic_tokens`. A registration with one of these names before root
> setup shadows that built-in. After root setup, a registration fails only when
> the name is currently registered. A default-on built-in is normally
> registered. An optional or disabled built-in is not necessarily registered.
> The built-in enable and disable options never manage or remove a custom
> provider with the same name.

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

`refresh` publishes ordinary marks that every accepted source window of a
buffer shares. `refresh_window` publishes ordinary marks that one source window
owns. The minimap projects these marks as row overlays only when the provider
targets the minimap and the effective `minimap.overlays.types` map has an entry
for the mark type that is not `false`.

`refresh_minimap` publishes semantic spans that the minimap source windows of a
buffer share. `refresh_minimap_window` publishes exact points that one minimap
source window owns. Each callback replaces only its own output.

The ownership scopes must match the callbacks exactly:

| Callback | Required `refresh_owner` scope |
| --- | --- |
| `refresh` | `buffer` |
| `refresh_window` | `window` |
| `refresh_minimap` | `minimap_buffer` |
| `refresh_minimap_window` | `minimap_window` |

You can implement any combination of callbacks. Declare exactly the scopes that
match the implemented callbacks. If no refresh callback exists, omit
`refresh_owner`. Each owner must be exactly `"manager"` or `"provider"`.

These are registration errors:

- A missing owner.
- An owner key without a matching callback.
- An unknown scope key.
- A `refresh_owner` value that is not a table.

Provider tables can still use private top-level fields for their own
configuration.

## Automatic Refresh Rules

After a successful activation, the manager attempts each implemented callback
for the current eligible buffers or source windows of the provider, regardless
of owner. Each callback still applies its channel policy, so minimap callbacks
publish only to minimap-eligible targets. Ownership controls only the automatic
dispatch after activation:

| Scope and owner | Automatic behavior |
| --- | --- |
| Buffer `"manager"` | The manager calls `refresh` on `BufEnter`, `TextChanged`, `TextChangedI`, and `TextChangedP` |
| Buffer `"provider"` | The manager sends no automatic buffer refresh. The provider owns subscriptions and publication |
| Window `"manager"` | The manager calls `refresh_window` on `BufWinEnter` and `WinEnter` |
| Window `"provider"` | The manager sends no automatic window refresh. The provider owns subscriptions and publication |
| Minimap buffer `"manager"` | The manager calls `refresh_minimap` on `BufEnter`, `TextChanged`, `TextChangedI`, and `TextChangedP` |
| Minimap buffer `"provider"` | The manager sends no automatic minimap-buffer refresh |
| Minimap window `"manager"` | The manager calls `refresh_minimap_window` on `BufWinEnter` and `WinEnter` |
| Minimap window `"provider"` | The manager sends no automatic minimap-window refresh |

On `BufWinEnter`, the manager clears manager-owned window marks and minimap
points before it refreshes the new window association. The manager also clears
them when the window is no longer eligible. Provider-owned window channels must
manage their own clearing when events occur.

`setup` and `dispose` describe only the resource lifecycle. A provider can
acquire resources in `setup` and keep manager scheduling with the `"manager"`
owner. Alternatively, the provider can choose `"provider"` and subscribe to its
own events. An empty, present, or omitted `setup` has no effect on scheduling.

Manual refresh does not depend on the owner, but it depends on the consumer:

- `:ScrollbarRefresh` calls `refresh` and `refresh_window` only for providers
  that the scrollbar consumes. It never calls minimap span or point callbacks.
- `:MinimapRefresh` calls ordinary `refresh` and `refresh_window` for providers
  that the minimap consumes. It also calls `refresh_minimap` and
  `refresh_minimap_window`. It excludes scrollbar-only providers.
- Both commands use the current source buffers and windows of their renderer,
  and they queue that renderer. They do not show hidden or autohide-concealed
  floats.

The Lua manager APIs support the same filtering:

```lua
local providers = require("scrollbar.providers")

providers.refresh(bufnr, { consumer = "minimap", channel = "minimap_spans" })
providers.refresh_window(winid, { consumer = "minimap", channel = "minimap_points" })
```

To attempt every active channel, omit the options. The valid buffer channels
are `marks` and `minimap_spans`. The valid window channels are `marks` and
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

The `refresh` method supplies the initial refresh and the manual refresh.
Because the provider owns the buffer scope, the provider's own event supplies
the automatic updates.

## Publishing Semantics

Each list for one provider, target, and channel is a complete replacement, not
an incremental patch.

- A returned list replaces the ordinary marks, minimap spans, or minimap points
  of that callback.
- A returned `{}` explicitly stores an empty replacement and clears the visible
  output for that channel.
- A `nil` return from any refresh callback means "do not publish". It normally
  leaves that list unchanged. Policy is checked again after the callback, so a
  target that became ineligible during collection is cleared instead.
- Passing `nil` to a context setter is not the same as returning `nil`. A `nil`
  argument is an invalid list. Use the corresponding clear method.

The scrollbar and the minimap have independent eligibility policies. For a
custom provider, `is_buffer_eligible`, `is_source_window`, and `source_windows`
query the union that `targets` selects. Ordinary mark setters use that union.
Minimap span and point setters always require minimap eligibility.

Buffer-scoped publication does not require the buffer to be shown or currently
selected. Window-scoped publication requires a valid normal non-renderer window
in the relevant current source-window set. That renderer selects the set after
it applies eligibility, `visibility`, profiles, and editor-relative placement.

For valid targets, the policy check occurs before payload validation. A
publication to a valid but ineligible target returns `false`. It also silently
clears only the corresponding stored channel of this provider. Invalid IDs
still get the normal validation and warning behavior. Clear operations are
unconditional and stay available regardless of policy.

### Ordinary Mark Schema

An ordinary list is a dense array. Each entry contains only these fields:

```lua
{
    line = 0,          -- required zero-based source line
    type = "Bookmark", -- required configured scrollbar or minimap type
    text = "B",        -- optional printable, positive-width override
}
```

The collision priority of ordinary marks depends on the consumer. Scrollbar
lanes read `scrollbar.marks.<Type>.priority`. Projected minimap rows read
`minimap.overlays.types.<Type>.priority`. Both use lower numeric values first.

### Minimap Span Schema

A minimap span list is a dense array. Each entry contains exactly these
required fields:

```lua
{
    line = 0,            -- zero-based source line
    start_col = 0,       -- zero-based byte offset, inclusive
    end_col = 4,         -- zero-based byte offset, exclusive; > start_col
    highlight = "String", -- non-empty highlight group
    priority = 100,      -- any finite integer; higher values win
}
```

Columns are byte offsets in the source line. They are not character,
codepoint, or display columns. For multibyte text, emit valid byte boundaries.
Spans color only occupied minimap cells. They do not fill empty cells.

### Minimap Point Schema

A minimap point list is a dense array. Each entry contains exactly these
required fields:

```lua
{
    line = 0,                         -- zero-based source line
    col = 4,                          -- zero-based source byte offset
    highlight = "ScrollbarMinimapCursor",
    priority = 200,                   -- any finite integer; higher values win
}
```

Points project to exact minimap cells for one source window. The projection
converts their byte columns to display columns.

### Minimap Priorities

Span and point priorities are independent of the ordinary overlay priorities in
`minimap.overlays.types`. For spans and points, higher values win:

- Where spans overlap, the span with the higher `priority` colors the cell. The
  Treesitter built-in uses `100`. The LSP semantic-token built-in uses `200`
  through `202`.
- Ordinary overlays draw with priorities `3` through `13`, and the built-in
  cursor point uses `14`. To draw a custom point above ordinary overlays, give
  it a `priority` above `13`.

### Validation

Each complete list is validated atomically. These faults reject a list:

- A negative or non-integer position.
- An unknown or missing field.
- An invalid highlight.
- An invalid ordinary type or text.
- A malformed list.

Each fault clears only the failing channel of this provider for that target,
returns `false`, and emits a rate-limited warning. Other channels and
providers stay intact.

As a narrow allowance for races, otherwise-valid entries whose zero-based
`line` is past the current EOF are silently omitted in all three schemas. The
remaining valid entries are published. A list that contains only stale entries
becomes an accepted empty replacement. A stale line does not hide another
malformed field on the same entry.

## Context Operations

| Context member | Behavior |
| --- | --- |
| `config` | Deep-copied snapshot of the normalized `scrollbar` configuration. Changes to the snapshot do not change the root configuration |
| `set_marks(bufnr, marks)` | Apply the union policy, validate, and replace buffer-scoped ordinary marks. Return whether the publication was accepted |
| `clear_marks(bufnr?)` | Unconditionally clear one buffer. Without `bufnr`, clear all buffer marks that this provider owns |
| `set_window_marks(winid, marks)` | Apply the union policy, validate, and replace the ordinary marks local to one current source window |
| `clear_window_marks(winid?)` | Unconditionally clear one window. Without `winid`, clear all window marks that this provider owns |
| `set_minimap_spans(bufnr, spans)` | Apply the minimap policy, validate, and replace buffer-scoped semantic byte spans |
| `clear_minimap_spans(bufnr?)` | Unconditionally clear one buffer. Without `bufnr`, clear all minimap spans that this provider owns |
| `set_minimap_points(winid, points)` | Apply the minimap policy, validate, and replace the byte points local to one minimap source window |
| `clear_minimap_points(winid?)` | Unconditionally clear one window. Without `winid`, clear all minimap points that this provider owns |
| `create_augroup(name)` | Create a provider-owned, namespaced augroup. Cleanup removes it |
| `add_cleanup(fn)` | Register a provider-owned cleanup callback |
| `on_text_change(fn, events?)` | Optional. Subscribe `fn` to the shared dispatch for `TextChanged`, `TextChangedI`, `TextChangedP`, and `TextChangedT`. See [Shared Event Dispatch](#shared-event-dispatch) |
| `on_cursor_activity(fn, events?)` | Optional. Subscribe `fn` to the shared dispatch for `CursorMoved` and `CursorMovedI`. See [Shared Event Dispatch](#shared-event-dispatch) |
| `is_buffer_eligible(bufnr)` | Query live eligibility across the declared target union of the provider |
| `is_source_window(winid)` | Query live source membership across the declared target union of the provider |
| `source_windows(bufnr?)` | Return a de-duplicated copy of the source-window list for the target union. A `bufnr` filters the list by buffer |
| `invalidate_buffer(bufnr)` | No effect after `require("scrollbar").setup()`. Publication already queues rendering |
| `invalidate_window(winid)` | No effect after `require("scrollbar").setup()`. Publication already queues rendering |

Setters return whether the publication was accepted. A `false` result can mean
a policy rejection or a validation failure. If the difference matters, query
the policy before you publish. Clear methods return whether any stored list
changed. A publication of an identical list returns `true` and queues no
render.

For asynchronous work, use the policy queries to avoid unnecessary collection.
Always treat the setter as the final authority, because eligibility can change
between collection and publication. A window provider must republish when its
window becomes a source window again. A manager-owned window scope can rely on
the `refresh_window` activation events of the manager.

### Shared Event Dispatch

`on_text_change` and `on_cursor_activity` let a provider use the autocmds of
the scrollbar instead of its own autocmds. A keystroke or a cursor move then
costs one autocmd invocation, not one per provider.

`fn` receives the autocmd arguments. It runs only for the events that
`scrollbar.update.events` lists, and not for buffers that the plugin owns. To
receive an event that `update.events` does not list, name it in `events`.

These context members can be `nil`. When the shared dispatch is inactive, a
hook can also return `false` or `nil`. In both cases, the provider gets no
events from the shared dispatch. If the provider needs these events, it must
register its own autocmds with `context.create_augroup`. The built-in cursor
provider shows this pattern.

## Execution

Custom provider code always runs in the main Neovim process. The minimap worker
never runs `setup`, the four refresh callbacks, provider-owned autocmds, timers,
jobs, or cleanup callbacks. Registration has no option for worker execution.

## Lifecycle And Cleanup

- Root `require("scrollbar").setup()` reconfigures the manager. Registered
  custom providers stay registered. Successful instances are disposed,
  cleaned, and activated again with a fresh context.
- Unregistration calls `dispose` after a successful setup. It also runs the
  registered cleanup callbacks in reverse order, removes the provider
  augroups, and clears all four kinds of output that the provider owns.
- Provider marks and spans are removed when their buffer is deleted. Window
  marks and points are removed when their window closes.
- Use `create_augroup` for autocmds. Use `add_cleanup` for timers, jobs,
  subscriptions, or other resources. Stop asynchronous work during cleanup.
  Guard late callbacks with your own active flag or generation. A retained
  context is not a cancellation token.
- Resource acquisition in `setup` does not require provider-owned refresh. If
  the standard manager events are sufficient, use a `"manager"` owner. Avoid
  duplicate provider subscriptions for the same scope.

## Failure Isolation

The manager guards calls to `setup`, all four refresh callbacks, `dispose`, and
registered cleanup callbacks.

- A setup failure disables that provider instance. The manager runs the
  cleanup callbacks already registered with `context.add_cleanup` and removes
  the augroups created through `context.create_augroup`. It also clears the
  published channels of the provider, warns, and lets other providers
  activate. Unregistered timers, jobs, subscriptions, and similar resources
  stay the responsibility of the provider.
- A refresh failure clears only the corresponding channel of the failing
  provider for that buffer or window. Other channels and providers continue.
- A dispose or cleanup failure causes a warning. It does not stop the cleanup
  of the remaining resources and publications.
- Equivalent setup, refresh, dispose, and validation warnings are suppressed
  until the relevant operation recovers. Cleanup warnings are rate-limited for
  the registration lifetime of the provider.

This boundary does not wrap code that provider-owned autocmds, timers, jobs, or
external callbacks invoke later. Handle errors inside those callbacks. Cancel
or detach them during cleanup.

## Troubleshooting

- Unknown option under `providers`: remove the custom key. Register the
  provider through `require("scrollbar.providers").register()`.
- Registration reports a missing `refresh_owner` scope: declare one owner for
  every implemented refresh callback. A missing owner has no compatibility
  fallback.
- `mark.type is not configured`: before the provider first publishes, add the
  type under `scrollbar.marks`, `minimap.overlays.types`, or both.
- `refresh_minimap requires targets.minimap`: declare
  `targets = { minimap = true }` or a dual-target table.
- No automatic updates with a `"provider"` owner: subscribe to the necessary
  events and publish through the context. If the fixed manager event list fits
  the provider, choose `"manager"` instead.
- Output disappears after one invalid item: validation replaces the list
  atomically and clears only the rejected channel. Read the warning to find
  the exact field.
- Marks come back after you unregister the provider: cancel the asynchronous
  work. Ignore late callbacks from the old provider generation.
- Window-specific state appears in every split: publish the state through
  `refresh_window`/`set_window_marks` or
  `refresh_minimap_window`/`set_minimap_points`. Do not use the buffer-scoped
  operations.
- A setter returns `false` without a warning: the current renderer policy
  rejected the valid target. Query `is_buffer_eligible` or `is_source_window`.
- Inactive window output does not appear later: window publication is accepted
  only for current source windows. When the window becomes selected, republish
  the output.
- Minimap priority seems reversed: ordinary overlays use
  `minimap.overlays.types` priority, where lower values win. Minimap spans and
  points use integer priority, where higher values win.

## Related Links

- [Provider index](README.md)
- [Mark configuration](../configuration.md#marks)
- [Highlights](../highlights.md)
