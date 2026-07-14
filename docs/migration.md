# Migrating From Earlier Releases

The current release intentionally has no compatibility aliases or fallback
renderer. Update older configurations and integrations as follows:

- Neovim 0.11 or newer is required; pre-0.11 compatibility branches were
  removed.
- `show_in_active_only` was removed. Use
  [`visibility = "active"` or `"all"`](visibility.md#source-windows).
- `folds` was removed. Use fast `render.geometry = "line"` or opt into
  [`render.geometry = "screen"`](layout-and-geometry.md#geometry-modes) for
  folds, wraps, filler, and virtual lines.
- `throttle_ms` was removed. Use `render.interval_ms` for latest-state frame
  [coalescing](layout-and-geometry.md#geometry-modes).
- The user-configurable `autocmd` table was removed. Runtime events are owned
  internally.
- The old `handlers` table was replaced by `providers`.
- Direct setup APIs such as `require("scrollbar.handlers.search").setup()` and
  `require("scrollbar.handlers.gitsigns").setup()` were removed.
- `require("scrollbar.handlers").register(name, fn)` was removed. Register a
  managed provider with `require("scrollbar.providers").register(provider)`.
- `b:scrollbar_marks` was removed. Providers publish marks through their
  context; direct buffer-variable writes are ignored.
- Mark `level` was removed. Density is derived from marks compressed into the
  same rendered row, type, and column bucket.
- Old standalone `color`, `color_nr`, `gui`, and `cterm` keys remain removed
  from handle and mark configuration. Use a highlight group name or a direct
  `highlight = { ... }` table, or define generated `Scrollbar*` groups with
  `set_highlights = false`.

## Related

- [README](../README.md)
- [Configuration](configuration.md)
- [Visibility](visibility.md)
- [Layout and geometry](layout-and-geometry.md)
- [Providers](providers/README.md)
- [Custom providers](providers/custom.md)
- [Highlights](highlights.md)
