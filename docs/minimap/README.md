# Minimap

`nvim-scrollbar` ships an independent minimap subsystem that renders a
horizontally-and-vertically squashed view of the current source buffer in a
floating window. The minimap has its own config slice, scheduler, renderer,
worker, mouse handler, presets, profiles, visibility, and commands. Toggling
its rendering never shows or hides the scrollbar.

Provider collection is intentionally shared. One provider manager owns each
active provider instance, and both renderers consume its shared store. The
scrollbar and minimap still apply independent eligibility, provider demand,
projection, scheduling, and rendering rules.

The minimap defaults to **disabled**. Enabling it does not show, hide, move, or
resize the scrollbar. Shared providers still use one effective option set, so
an explicit minimap `search` or `marks` table can also become the option set for
that provider's scrollbar consumer.

## Quick Start

```lua
require("scrollbar").setup({
    scrollbar = {},
    minimap = {
        enabled = true,
    },
})
```

The default placement is `window`-relative at the north-east corner, so each
source window gets its own solid 16-column minimap. The visible float uses
**half-block characters** (` `, `▀`, `▄`, `█`) to represent source density at
2x vertical resolution. Occupied cells are monochrome by default. Enable
Treesitter color with `minimap.providers.treesitter = true`, while the default
cursor provider publishes an exact byte point that accents the projected cell
without replacing its glyph. The viewport is a non-destructive tint, ordinary
mark overlays tint occupied cells, and semantic spans participate in the
squash itself.

## User Commands

| Command | Behavior |
| --- | --- |
| `:MinimapShow` | Makes the minimap visible and re-arms autohide deadlines if enabled. |
| `:MinimapHide` | Hides every minimap float and clears pending hide deadlines. |
| `:MinimapToggle` | Flips between `Show` and `Hide`. |
| `:MinimapRefresh` | Runs minimap provider refresh callbacks for marks, spans, and points, then invalidates rendering without revealing a hidden or autohide-concealed minimap. |

Commands are created when setup runs with `minimap.enabled = true`.

## Topics

- [Configuration](configuration.md): full schema, defaults, and validation
- [Layout](layout.md): float placement, anchor math, viewport tint, cursor cell
- [Overlays](overlays.md): store projection, mark types, collision priority
- [Mouse](mouse.md): click + drag semantics and focus restoration
- [Treesitter provider](../providers/treesitter.md): parser requirements and backend behavior
- [LSP semantic tokens](../providers/lsp_semantic_tokens.md): requests, encodings, priorities, and refresh limits

## See Also

- [Scrollbar configuration](../configuration.md)
- [Migration](../migration.md)
- [Development](../development.md)
