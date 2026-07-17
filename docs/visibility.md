# Visibility

Visibility is controlled globally, per source window, and by buffer eligibility.

## Source Windows

- `visibility = "all"` creates an independent scrollbar for every eligible
  normal window. Two windows showing the same buffer retain different thumbs.
- `visibility = "active"` keeps only the active source window's scrollbar.
- `float.placement.relative = "editor"` also renders only the active source
  window, regardless of `visibility`, so editor-relative floats cannot overlap.

`visibility` is always root-owned. With contextual profiles and root
`visibility = "all"`, placement is resolved per source: window-relative
variants may remain visible together, while an editor-relative variant is
eligible only when its own source is active. Switching a predicate reconciles
or closes only the affected source state.

## Global Visibility

`show = false` starts with master visibility disabled. Calling `show()`,
`hide()`, or `toggle()` changes this global state across all eligible windows.

| Command | Lua API | Effect |
| --- | --- | --- |
| `:ScrollbarShow` | `require("scrollbar").show()` | Enable master visibility; with autohide, reveal and arm every eligible window |
| `:ScrollbarHide` | `require("scrollbar").hide()` | Disable master visibility, hide floats, and cancel autohide deadlines and holds |
| `:ScrollbarToggle` | `require("scrollbar").toggle()` | Toggle master visibility, even when autohide has concealed every float |
| `:ScrollbarRefresh` | `require("scrollbar").refresh()` | Refresh providers and rerender without revealing concealed autohide windows |

## Autohide

With `autohide.enabled = true`, each eligible window starts concealed and is
revealed by its own `CursorMoved`, `CursorMovedI`, or `WinScrolled` activity.
That window is hidden independently after `autohide.delay_ms` of inactivity.

Provider updates, option changes, resizes, colorscheme changes, and
`:ScrollbarRefresh` can rerender a revealed scrollbar but do not reveal a
concealed one. Pressing or dragging a scrollbar pauses that source window's
deadline; release or cancellation starts a fresh full delay.

Autohide, master visibility, exclusions, and `max_lines` are root-owned and
cannot be changed by a profile.

## Documents That Fit

- `hide_if_all_visible = true` hides the entire scrollbar when the document
  fits in the source window.
- `thumb.hide_if_all_visible = true` hides only the thumb when the document
  fits. The track and provider marks can remain visible.
- `max_lines` is an eligibility limit, not a visibility toggle: buffers above
  the configured logical line count receive no scrollbar.

`hide_if_all_visible` and `thumb.hide_if_all_visible` may vary by profile;
`max_lines` may not.

## Cursor Intersection

`float.hide_on_cursor = true` temporarily hides the active source window's whole
scrollbar when the editing cursor enters any cell in the float's actual screen
rectangle. Moving the cursor away restores the same float, buffer, rows,
highlights, and mouse mappings.

Only the cursor in `nvim_get_current_win()` triggers this behavior. Stored
cursor positions in inactive splits do not hide their scrollbars. The check uses
the full effective float width, anchors, and placement offsets.

The test compares cursor and float screen coordinates only; it does not inspect
source lines or visible text.

While hidden, the scrollbar does not capture mouse input, so those cells reach
the source window. Set `float.hide_on_cursor = false` to keep the overlay visible
under the cursor.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Mouse](mouse.md)
