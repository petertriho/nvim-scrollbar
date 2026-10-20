# Visibility

Visibility is controlled globally, per source window, and by buffer eligibility.

## Source Windows

- `visibility = "all"` creates an independent scrollbar for every eligible
  normal window. Two windows that show the same buffer keep different thumbs.
- `visibility = "active"` keeps only the scrollbar of the active source window.
- `placement.relative = "editor"` also renders only the active source window,
  for every `visibility` value. As a result, editor-relative floats cannot
  overlap.

`visibility` is a global option, so a profile cannot set it. With contextual
profiles and `visibility = "all"`, each source window gets the placement of its
own profile. Window-relative profiles can stay visible together. A scrollbar
with an editor-relative profile shows only when its source window is active.
Profile predicates run again before each render. If a different profile starts
to match a source window, only the scrollbar of that window changes.

## Global Visibility

`scrollbar.enabled = false` turns off the scrollbar. Setup creates no
scrollbar floats and no scrollbar commands, and the scrollbar requests no
providers. Use it, for example, when you want only the minimap.

`scrollbar.show = false` starts with master visibility disabled. A call to
`show()`, `hide()`, or `toggle()` changes this global state for all eligible
windows.

| Command | Lua API | Effect |
| --- | --- | --- |
| `:ScrollbarShow` | `require("scrollbar").show()` | Enables master visibility. With autohide, shows every eligible window and starts its hide delay |
| `:ScrollbarHide` | `require("scrollbar").hide()` | Disables master visibility, hides floats, and cancels pending autohide delays |
| `:ScrollbarToggle` | `require("scrollbar").toggle()` | Toggles master visibility, also when autohide has concealed every float |
| `:ScrollbarRefresh` | `require("scrollbar").refresh()` | Refreshes providers and rerenders, but does not reveal concealed autohide windows |

## Autohide

With `autohide = true`, each eligible window starts concealed. The
`CursorMoved`, `CursorMovedI`, or `WinScrolled` activity of that window reveals
it, if the event is in [`events`](configuration.md#events). After 1000 ms of
inactivity, autohide conceals that window independently. To change the delay,
use `autohide = { delay_ms = 500 }`.

![The scrollbar shows while the window scrolls and hides after one second without activity](https://github.com/user-attachments/assets/1efa7a90-fcc2-4950-b527-0853efb23760)

Provider updates, option changes, resizes, colorscheme changes, and
`:ScrollbarRefresh` can rerender a revealed scrollbar. They do not reveal a
concealed scrollbar. A press or drag on a scrollbar pauses the deadline of that
source window. Release or cancellation starts a new full delay.

Autohide, master visibility, and `max_lines` are global options. The top-level
`exclude` table also applies to every profile. A profile cannot change them.

## Documents That Fit

- `hide_if_all_visible = true` hides the entire scrollbar when the document
  fits in the source window.
- `thumb.hide_if_all_visible = true` hides only the thumb when the document
  fits. The track and provider marks can stay visible.
- `max_lines` is an eligibility limit, not a visibility toggle. A buffer with
  more logical lines than the configured count gets no scrollbar.

A profile can change `hide_if_all_visible` and `thumb.hide_if_all_visible`. A
profile cannot change `max_lines`.

## Cursor Intersection

`scrollbar.hide_on_cursor = true` (the default) applies to the scrollbar of the
active source window. When the editing cursor enters any cell of the float, the
whole scrollbar hides. When the cursor moves away, the scrollbar shows again.

Only the cursor of the current window triggers this behavior. Stored cursor
positions in inactive splits do not hide their scrollbars. The check uses the
full float rectangle, including the placement offsets. It compares only screen
coordinates and does not examine the text.

While the scrollbar is hidden, it does not capture mouse input. Mouse input on
those cells goes to the source window. To keep the scrollbar visible under the
cursor, set `scrollbar.hide_on_cursor = false`.

The minimap has the same option, `minimap.hide_on_cursor`, which is also
`true` by default. It applies only to the minimap of the active source window,
and it does not need the `cursor` provider. The minimap does this check when
it renders, which includes each cursor movement. To turn off the check, set
`minimap.hide_on_cursor = false`.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Mouse](mouse.md)
