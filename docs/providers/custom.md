# Custom Providers

Custom providers publish typed, zero-based source-line marks through
`require("scrollbar.providers")`. They can own buffer-wide marks, window-local
marks, or both.

## Configure Mark Types

Every emitted `mark.type` must exist in the top-level `marks` configuration:

```lua
require("scrollbar").setup({
    marks = {
        Bookmark = {
            text = { ".", "*", "#" },
            priority = 1,
            highlight = "Special",
        },
    },
})
```

Custom provider names or options do **not** go under `providers`. That table
accepts only the built-in keys and rejects unknown keys. Keep provider-specific
configuration in your own module or closure, and register the provider through
the manager API.

For a new custom mark type, `text`, `priority`, and `highlight` are all
required. Partial tables are valid only when overriding a built-in type whose
missing fields are supplied by the defaults.

Mark type names must match `^[%a_][%w_]*$`. `text` is a string or dense list of
density variants, `priority` is a non-negative integer where lower values win
within one lane, and
`highlight` is a non-empty group name or an `nvim_set_hl()` definition table.
An emitted mark may supply its own non-empty `text` override. `Mark` is special:
provider text is used only while `marks.Mark.text = {}`; a non-empty configured
`Mark` list replaces provider text.

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
    marks = {
        Bookmark = {
            text = { ".", "*", "#" },
            priority = 1,
            highlight = "Special",
        },
    },
})

providers.unregister("bookmarks")
```

- Names must be non-empty and unique; duplicate registration raises an error
  and does not replace the existing provider.
- Registration before setup defers activation. Registration after setup runs
  `setup`, then immediately performs initial eligible refreshes.
- `unregister(name)` returns `true` when it removed a provider and `false` when
  no provider had that name.
- `get(name)` returns the registered provider table or `nil`.

> **Avoid built-in names:** `cursor`, `diagnostic`, `search`, `marks`,
> `gitsigns`, `mini_diff`, `signify`, `vgit`, `ale`, and `coc`. Registering one before root setup shadows that
> built-in. Registering afterward fails only when the name is currently
> registered, which is normally true for default-on providers but not
> necessarily for optional or explicitly disabled providers. Built-in
> enable/disable options never manage or remove a custom provider using the same
> name.

## Provider Interface

```lua
---@alias ScrollbarProviderRefreshOwner "manager"|"provider"

---@class ScrollbarProviderRefreshOwnership
---@field buffer? ScrollbarProviderRefreshOwner
---@field window? ScrollbarProviderRefreshOwner

---@class ScrollbarProvider
---@field name string
---@field refresh_owner? ScrollbarProviderRefreshOwnership
---@field setup? fun(context: ScrollbarProviderContext)
---@field refresh? fun(bufnr: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field refresh_window? fun(winid: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field dispose? fun(context: ScrollbarProviderContext)
```

`refresh` publishes marks shared by every source window displaying a buffer.
`refresh_window` publishes marks owned by one source window. If both methods are
present, both lists participate in rendering and collision resolution.

Ownership scopes must correspond exactly to callbacks:

| Provider callbacks | Required `refresh_owner` keys |
| --- | --- |
| Neither callback | Omit `refresh_owner` |
| `refresh` only | `buffer` only |
| `refresh_window` only | `window` only |
| Both callbacks | Both `buffer` and `window` |

Each owner must be exactly `"manager"` or `"provider"`. Missing owners, owner
keys without matching callbacks, unknown scope keys, and non-table
`refresh_owner` values are registration errors. Provider tables may still use
private top-level fields for their own configuration.

## Automatic Refresh Rules

Every activated provider receives one initial refresh for each eligible loaded
buffer and eligible source window after successful activation, regardless of owner.
Ownership controls only subsequent automatic dispatch:

| Scope and owner | Automatic behavior |
| --- | --- |
| Buffer `"manager"` | The manager calls `refresh` on `BufEnter`, `TextChanged`, `TextChangedI`, and `TextChangedP` |
| Buffer `"provider"` | The manager sends no automatic buffer refresh; the provider owns subscriptions and publication |
| Window `"manager"` | The manager calls `refresh_window` on `BufWinEnter` and `WinEnter` |
| Window `"provider"` | The manager sends no automatic window refresh; the provider owns subscriptions and publication |

On `BufWinEnter`, manager-owned window marks are cleared before the new window
association is refreshed. They are also cleared when the window is no longer
eligible. Provider-owned window refresh must manage its own event-time clearing.

`setup` and `dispose` describe resource lifecycle only. A provider may acquire
resources in `setup` while retaining manager scheduling by choosing
`"manager"`, or choose `"provider"` and subscribe to its own events. An empty,
present, or omitted `setup` has no scheduling meaning.

`:ScrollbarRefresh` calls both refresh methods for current source buffers and
windows regardless of owner. The Lua manager's `refresh(bufnr)` and
`refresh_window(winid)` APIs are also ownership-independent.

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

Marks are complete replacements per provider and target, not incremental
patches.

- Returning a mark list replaces that buffer or window list.
- Returning `{}` explicitly replaces it with an empty list and clears visible
  marks.
- Returning `nil` from `refresh` or `refresh_window` means "do not publish" and
  normally leaves the current list unchanged. Policy is checked again after the
  callback, so a target that becomes ineligible during collection is cleared
  instead. A manager-owned window provider on `BufWinEnter` is also called after
  the manager has cleared the old window association.
- Passing `nil` to `context.set_marks` or `context.set_window_marks` is not the
  same as returning `nil`; it is an invalid mark list, so use the clear methods
  instead.

A buffer is eligible when its ID is valid, it is loaded, it is not owned by the
scrollbar renderer, its `buftype` and `filetype` are not excluded, and its line
count does not exceed `max_lines`. Buffer-scoped publication does not require
the buffer to be displayed or currently selected.

A window is a current source window only when it is a valid normal non-renderer
window displaying an eligible buffer and is selected by root `visibility` plus
the effective profile's editor-relative placement rule. Window-scoped marks
cannot be prepublished to inactive or editor-unselected windows.

Policy is enforced before payload validation for valid targets. Publishing to a
valid ineligible buffer, or to a valid window outside the current source set,
silently clears only this provider's stored list for that target and returns
`false`. Repeating the rejection does not invalidate rendering when nothing was
stored. Invalid IDs still use the normal validation path and warning behavior.
Clear operations are unconditional and remain available regardless of policy.

Each complete list is validated before publication. It must be a dense array,
and every mark must contain only:

```lua
{
    line = 0,          -- integer within the current buffer
    type = "Bookmark", -- configured mark type
    text = "B",        -- optional, printable, positive-width string
}
```

Providers should normally publish only lines within the current buffer. As a
narrow exception for providers racing with buffer edits, marks whose `line` is
a non-negative integer past the current EOF are silently omitted after their
other fields are validated. Valid survivors are published, the context setter
returns `true`, and a list containing only such stale marks is accepted as an
empty replacement.

Validation remains atomic for every other error. Negative or non-integer lines,
unknown fields, unconfigured types, invalid text, and malformed lists clear this
provider's existing list for that target, return `false` from the context
setter, and emit a rate-limited warning. A past-EOF line does not hide another
malformed field on the same mark. Rejection does not clear another provider's
marks.

## Context Operations

| Context member | Behavior |
| --- | --- |
| `config` | Deep-copied normalized setup snapshot; mutations do not change root configuration |
| `set_marks(bufnr, marks)` | Policy-check, validate, and replace buffer-scoped marks; return whether publication was accepted |
| `clear_marks(bufnr?)` | Unconditionally clear one buffer, or all buffer marks owned by this provider when omitted |
| `set_window_marks(winid, marks)` | Policy-check, validate, and replace marks local to one current source window; return whether publication was accepted |
| `clear_window_marks(winid?)` | Unconditionally clear one window, or all window marks owned by this provider when omitted |
| `create_augroup(name)` | Create a provider-owned, namespaced augroup removed during cleanup |
| `add_cleanup(fn)` | Register a provider-owned cleanup callback |
| `is_buffer_eligible(bufnr)` | Query live renderer-backed buffer eligibility |
| `is_source_window(winid)` | Query exact live membership in the current selected source-window set |
| `source_windows(bufnr?)` | Return a copied current source-window list, optionally filtered by buffer |
| `invalidate_buffer(bufnr)` | Queue rendering for windows displaying the buffer without changing marks |
| `invalidate_window(winid)` | Queue rendering for one source window without changing marks |

Setters return whether publication was accepted. `false` can mean policy
rejection or validation failure; preflight with the policy queries when the
distinction matters. Clear methods return whether any stored list changed.
Publishing an identical accepted list returns `true` without a render
invalidation.

For asynchronous work, use the policy queries to avoid unnecessary collection,
but always treat the setter as the final authority because eligibility can
change between collection and publication. A window provider must republish
when its window becomes a source again; a manager-owned window scope can rely on
the manager's `refresh_window` activation events.

## Lifecycle And Cleanup

- Root `require("scrollbar").setup()` reconfigures the manager. Registered
  custom providers remain registered, but successful instances are disposed,
  cleaned, and activated again with a fresh context.
- Unregistration calls `dispose` after a successful setup, runs registered
  cleanup callbacks in reverse order, removes provider augroups, clears both
  scopes, and invalidates affected targets.
- Provider marks are also removed when their buffer is deleted or their window
  closes.
- Use `create_augroup` for autocmds and `add_cleanup` for timers, jobs,
  subscriptions, or other resources. Stop asynchronous work during cleanup and
  guard late callbacks with your own active flag or generation; a retained
  context is not a cancellation token.
- Resource acquisition in `setup` does not require provider-owned refresh. Use a
  `"manager"` owner when the standard manager events are sufficient, and avoid
  installing duplicate provider subscriptions for the same scope.

## Failure Isolation

The manager guards calls to `setup`, `refresh`, `refresh_window`, `dispose`, and
registered cleanup callbacks.

- A setup failure disables that provider instance, runs cleanup callbacks
  already registered with `context.add_cleanup`, removes augroups created
  through `context.create_augroup`, clears its marks, warns, and allows other
  providers to activate. Unregistered timers, jobs, subscriptions, and similar
  resources remain the provider's responsibility.
- A refresh failure clears only the failing provider's list for that buffer or
  window. Other providers continue.
- A dispose or cleanup failure warns but does not prevent remaining resource and
  mark cleanup.
- Equivalent setup, refresh, dispose, and validation warnings are suppressed
  until the relevant operation recovers. Cleanup warnings are rate-limited for
  the provider's registration lifetime.

This boundary does not wrap code invoked later by provider-owned autocmds,
timers, jobs, or external callbacks. Handle errors inside those callbacks and
remove or invalidate them during cleanup.

## Troubleshooting

- Unknown option under `providers`: remove the custom key and register the
  provider through `require("scrollbar.providers").register()`.
- Registration reports a missing `refresh_owner` scope: declare one owner for
  every implemented refresh callback; omission has no compatibility fallback.
- `mark.type is not configured`: add the type under top-level `marks` before
  the provider first publishes.
- No automatic updates with a `"provider"` owner: subscribe to the required
  events and publish through the context, or choose `"manager"` when the fixed
  manager event list fits the provider.
- Marks disappear after one invalid item: validation replaces atomically and
  clears the rejected target list; inspect the warning for the exact field.
- Marks leak back after unregistering: cancel asynchronous work and ignore late
  callbacks from the old provider generation.
- Window-specific state appears in every split: publish it through
  `refresh_window` or `set_window_marks`, not the buffer-scoped operations.
- A setter returns `false` without a warning: the valid target was rejected by
  current renderer policy; query `is_buffer_eligible` or `is_source_window`.
- Inactive window marks do not appear later: window publication is accepted only
  for current source windows, so republish when the window becomes selected.

## Related Links

- [Provider index](README.md)
- [Mark configuration](../configuration.md#marks)
- [Highlights](../highlights.md)
