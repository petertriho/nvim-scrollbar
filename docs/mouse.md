# Mouse

Mouse support installs normal-mode, buffer-local mappings for `<LeftMouse>`,
`<LeftDrag>`, and `<LeftRelease>` in scrollbar scratch buffers. It never changes
`vim.o.mouse`; users must enable the desired modes, for example:

```lua
vim.o.mouse = "a"
```

## Layer Ownership

- A visible mark owns exact source-line navigation.
- A declared track cell outside the thumb navigates directly when content fits
  and proportionally when it is taller than the scrollbar.
- A transparent cell with no declared track, active thumb, or visible mark is
  inert and restores source-window focus.
- Pressing an active thumb and moving drags its one contiguous rectangle while
  preserving the vertical grab offset. Multi-column thumb spans drag as one.
- A visible mark above the thumb keeps both ownership channels: release without
  movement clicks the mark; movement starts a thumb drag.
- If the thumb is above a mark layer, the hidden mark has no hit target.

Navigation opens only folds containing the target with `zv`, centers with `zz`,
and restores source focus after release or cancellation. Pressed canonical Thumb
groups remain active throughout a drag.

With autohide enabled, interactive presses pause that source window's hide
deadline. Release or cancellation starts a fresh full delay. Inert transparent
cells do not hold the scheduler.

## Disabling

`mouse.enabled = false` makes floats non-focusable and installs no mappings. A
float temporarily hidden by `float.hide_on_cursor` does not capture mouse input.

## Related

- [Layout and geometry](layout-and-geometry.md)
- [Highlights](highlights.md)
- [Marks provider](providers/marks.md)
