# Mouse

Mouse support installs normal-mode, buffer-local mappings for `<LeftMouse>`,
`<LeftDrag>`, and `<LeftRelease>` in the scrollbar floats. It never changes
`vim.o.mouse`. You must enable the modes that you want, for example:

```lua
vim.o.mouse = "a"
```

## Click and Drag

- A click on a visible mark moves to the exact source line of the mark.
- A click on a declared track cell outside the thumb also navigates. When the
  content fits, the cell goes directly to its line. When the content is taller
  than the scrollbar, the cell goes to the proportional position.
- A transparent cell with no declared track, active thumb, or visible mark
  does nothing. A click on it returns focus to the source window.
- A press on an active thumb followed by movement drags the thumb. The drag
  keeps the vertical grab offset. A thumb that spans more than one column drags
  as one rectangle.
- If a visible mark is above the thumb, a release without movement clicks the
  mark, and movement starts a thumb drag.
- If the thumb is above a mark layer, the hidden mark is not clickable.

Navigation opens only the folds that contain the target with `zv`, and centers
with `zz`. After release or cancellation, focus returns to the source window.
The pressed thumb highlight stays active during the full drag.

Each window uses the mouse options of its own profile, so windows that are open
at the same time can be interactive or inert independently. If a different
profile starts to match during a click or drag, the change applies from the
next interaction.

When autohide is enabled, a press on an interactive cell pauses the hide delay
of that source window. Release or cancellation starts a new full delay.

## Focus

The floats are not focusable, so window commands such as `<C-w>w` skip them.
The cursor stays in a float only during a click or a drag.

- The mappings work in Normal mode. A click in Insert mode or another mode does
  nothing.
- Neovim reports fast clicks on one cell as a double, triple, or quadruple
  click. The floats take each of these as a single click.
- If a command or a plugin enters a float without a click, focus returns to the
  window that it left.

The minimap float uses the same focus rules.

## Disabling

`scrollbar.mouse = false` makes mouse input pass through the floats and
installs no mappings. A profile can change `mouse` for the windows that it matches. A float
that `hide_on_cursor` hides does not capture mouse input.

## Related

- [Layout and geometry](layout-and-geometry.md)
- [Highlights](highlights.md)
- [Marks provider](providers/marks.md)
- [Minimap](minimap/README.md)
