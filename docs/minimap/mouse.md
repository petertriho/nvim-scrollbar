# Minimap Mouse

The minimap ships its own mouse module. It installs buffer-local keymaps
for `<LeftMouse>`, `<LeftDrag>`, and `<LeftRelease>` on each minimap
float, independent of the scrollbar mouse module. The two never share
state; toggling one does not affect the other.

The minimap never changes `vim.o.mouse`. Users must enable the desired
modes, for example:

```lua
vim.o.mouse = "a"
```

## Click

A `<LeftMouse>` press inside the minimap float:

1. Projects the 0-based minimap row back to a 0-based source line via
   `floor(row * v_ratio)`, clamped to `[0, source_line_count - 1]`.
2. Sets the source window cursor to the projected 1-based line at column `0`.
3. Runs `normal! zv` (open folds) and `normal! zz` (center) inside the
   source window.
4. Schedules a minimap invalidation. When enabled, the cursor provider publishes
   the exact new point for rendering.

Line mode only — the projection does not account for wrapped rows or
folds beyond their first line. See [Layout](layout.md) for the
projection math.

## Drag

A `<LeftDrag>` event continues the in-flight interaction. Each drag event
projects the latest row to a source line and runs the same navigate +
invalidate sequence as a click. Navigation happens for every drag event;
only the resulting render invalidations are coalesced through the minimap
scheduler's `update.interval_ms`.

The minimap float owns focus during the interaction. Navigation itself runs in
the source window with `nvim_win_call`, and `nvim_set_current_win` restores the
source on release or cancellation.

## Release and Cancellation

A `<LeftRelease>` projects the final row, navigates one last time, and
restores source focus. If the press or drag is cancelled (for example by
the source window closing), no navigation is rolled back; focus is restored to
the source when possible, or to the first available non-floating window.

## Disabling

`minimap.mouse.enabled = false` makes the float non-focusable and installs
no keymaps after setup is rerun. A profile that selects `mouse.enabled = false`
detaches mappings when that minimap state is rendered.

## Autohide Interaction

The mouse module does not pause autohide deadlines through the scheduler's
hold/resume API. It queues ordinary invalidations only; any deadline changes
come from the scheduler's normal activity events. Release and cancellation
restore focus but do not explicitly extend the deadline.

## Out of Scope

Visual-mode interactions, multi-cursor support, and right-click menus are
not implemented in v1. Drag-through-handle acceleration tricks are also
out of scope; drag uses the same line-mode projection as click.

## Related

- [Layout](layout.md)
- [Configuration](configuration.md)
- [Scrollbar mouse](../mouse.md)
