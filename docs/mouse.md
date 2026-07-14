# Mouse

Mouse support installs normal-mode, buffer-local mappings for `<LeftMouse>`,
`<LeftDrag>`, and `<LeftRelease>` in scrollbar scratch buffers. It does not
install mappings in other modes or globally, and it never changes `vim.o.mouse`.

The user's Neovim `mouse` option must enable the desired modes, for example:

```lua
vim.o.mouse = "a"
```

## Interaction

- Clicking a visible mark jumps to that mark's exact source line.
- Clicking empty track space jumps directly by row when the document fits and
  proportionally when it is taller than the track. Rows below short content
  clamp to the final source line.
- Pressing on the handle and moving drags it while preserving the grab offset.
- A pressed handle uses a `PmenuSel`-derived background until release or valid
  cancellation, even when the pointer moves outside it during a drag.
- A mark over the handle is an exact mark click if released without movement;
  moving starts a handle drag.
- Navigation moves the source cursor, opens the fold or nested folds containing
  the target with `zv` without opening unrelated folds, centers with `zz`, and
  restores source-window focus on completion or cancel.
- With autohide enabled, pressing or dragging pauses that source window's hide
  deadline. Release or cancellation starts a fresh full delay.

## Disabling Mouse Support

Set `mouse.enabled = false` to make scrollbar floats non-focusable and omit the
buffer-local mappings. Even when enabled, interaction works only in modes
allowed by the user's `mouse` option.

A scrollbar temporarily hidden by `float.hide_on_cursor` does not capture mouse
input. Interaction returns when that same float becomes visible again.

## Related

- [README](../README.md)
- [Visibility](visibility.md)
- [Layout and geometry](layout-and-geometry.md)
- [Marks provider](providers/marks.md)
