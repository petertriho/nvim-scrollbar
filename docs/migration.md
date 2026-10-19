# Migrating From v1

This guide lists the changes from v1 to v2 that need a change in your
configuration. v2 rejects unknown options and has no compatibility layer for
v1 options. A v1 configuration fails setup until you migrate it. A call
without options, `require("scrollbar").setup()`, works in both versions.

## Stay On v1

If you are not ready to migrate, pin the `v1` branch.

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "petertriho/nvim-scrollbar",
    branch = "v1",
    opts = {},
}
```

[packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use({ "petertriho/nvim-scrollbar", branch = "v1" })
```

[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'petertriho/nvim-scrollbar', { 'branch': 'v1' }
```

## Requirements

- v2 needs Neovim 0.11 or newer. v1 needed Neovim 0.5.1.
- Search marks no longer need
  [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens).

## Configuration Shape

Move all v1 options into a `scrollbar` block:

Old:

```lua
require("scrollbar").setup({
    show_in_active_only = true,
    handle = { text = " " },
    handlers = { gitsigns = true },
})
```

New:

```lua
require("scrollbar").setup({
    scrollbar = {
        visibility = "active",
        thumb = { text = " " },
        providers = { gitsigns = true },
    },
})
```

The top level accepts only `scrollbar` and `minimap`. Any other top-level key
is a setup error. The `minimap` block is optional and is disabled by default.

## Options

These options keep their names and meaning: `show`, `set_highlights`,
`max_lines`, `hide_if_all_visible`, `excluded_buftypes`, `excluded_filetypes`,
and `marks.<Type>.text`, `priority`, and `highlight`.

| v1 option | v2 replacement |
| --- | --- |
| `show_in_active_only = true` | `visibility = "active"` |
| `show_in_active_only = false` | `visibility = "all"` (the default) |
| `folds` | `render.geometry`. `"screen"` accounts for closed folds and wrapped lines. `"line"` (the default) does not. There is no line-count limit. |
| `throttle_ms` | `update.interval_ms` |
| `handle` | `thumb` |
| `handle.text`, `handle.blend`, `handle.hide_if_all_visible` | `thumb.text`, `thumb.blend`, `thumb.hide_if_all_visible` |
| `handle.highlight` | `thumb.highlight` |
| `handle.color`, `handle.color_nr` | A `thumb.highlight` table, for example `{ bg = "#3b4261", ctermbg = 238 }` |
| `marks.<Type>.color`, `gui`, `cterm`, `color_nr` | A `marks.<Type>.highlight` table. See [Colors](#colors). |
| `autocmd.render` | `update.events` |
| `autocmd.clear` | Removed. To show only the active window, use `visibility = "active"`. |
| `handlers` | `providers`. See [Handlers](#handlers). |
| `handlers.handle = false` | Remove `"thumb"` from `layout.columns`, for example `layout = { columns = { { "track", "marks" } } }` |

The default `update.events` list contains every v1 `autocmd.render` event.
Unknown event names are setup errors. See
[Configuration](configuration.md#update-cadence).

### Colors

v2 has no `color`, `color_nr`, `gui`, or `cterm` options. Put a
`nvim_set_hl()` definition table in `highlight` instead:

- For a mark, `color` becomes `fg` and `color_nr` becomes `ctermfg`.
- For the thumb, `color` becomes `bg` and `color_nr` becomes `ctermbg`.
- `gui = "bold"` becomes `bold = true`.
- `cterm = "bold"` becomes `cterm = { bold = true }`.

If a thumb table does not set `blend`, the plugin adds `thumb.blend`.

Old:

```lua
local colors = require("tokyonight.colors").setup()

require("scrollbar").setup({
    handle = {
        color = colors.bg_highlight,
    },
    marks = {
        Search = { color = colors.orange },
        Error = { color = colors.error },
        Warn = { color = colors.warning },
        Info = { color = colors.info },
        Hint = { color = colors.hint },
        Misc = { color = colors.purple },
    },
})
```

New:

```lua
local colors = require("tokyonight.colors").setup()

require("scrollbar").setup({
    scrollbar = {
        thumb = {
            highlight = { bg = colors.bg_highlight },
        },
        marks = {
            Search = { highlight = { fg = colors.orange } },
            Error = { highlight = { fg = colors.error } },
            Warn = { highlight = { fg = colors.warning } },
            Info = { highlight = { fg = colors.info } },
            Hint = { highlight = { fg = colors.hint } },
            Misc = { highlight = { fg = colors.purple } },
        },
    },
})
```

See [Highlights](highlights.md).

## Handlers

v1 handlers are v2 providers. Enable them in `scrollbar.providers`:

| v1 handler | v2 provider |
| --- | --- |
| `cursor` | `cursor` (enabled by default) |
| `diagnostic` | `diagnostic` (enabled by default) |
| `search` | `search` (enabled by default) |
| `gitsigns` | `gitsigns` |
| `ale` | `ale` |
| `handle` | No provider. See the `handlers.handle` row in [Options](#options). |

The `scrollbar.handlers` modules are removed. Delete every call to
`require("scrollbar.handlers.<name>").setup()` and to its `handler.show` or
`handler.hide` functions.

The v1 `diagnostic` handler also showed coc.nvim diagnostics. In v2, coc.nvim
diagnostics need `providers.coc = true`.

v2 also has providers for native marks, mini.diff, vim-signify, vgit.nvim, and
coc.nvim. See [Providers](providers/README.md).

### Search

The v2 search provider reads the native `/` and `?` search. It does not use
nvim-hlslens. Delete these v1 search integrations:

- The `require("scrollbar.handlers.search").setup()` call.
- A `build_position_cb` that calls
  `require("scrollbar.handlers.search").handler.show()`.
- A `CmdlineLeave` autocmd that calls
  `require("scrollbar.handlers.search").handler.hide()`.

If you passed nvim-hlslens options to the v1 search setup, pass them to
`require("hlslens").setup()` instead. See [Search](providers/search.md).

### Gitsigns

Old:

```lua
require("gitsigns").setup()
require("scrollbar.handlers.gitsigns").setup()
```

New:

```lua
require("gitsigns").setup()
require("scrollbar").setup({
    scrollbar = {
        providers = { gitsigns = true },
    },
})
```

See [Gitsigns](providers/gitsigns.md).

## Custom Handlers

`require("scrollbar.handlers").register(name, fn)` becomes
`require("scrollbar.providers").register()`, which takes a provider table.

Old:

```lua
require("scrollbar.handlers").register("my_marks", function(bufnr)
    return {
        { line = 0 },
        { line = 1, text = "x", type = "Warn" },
        { line = 2, type = "Error" },
    }
end)
```

New:

```lua
require("scrollbar.providers").register({
    name = "my_marks",
    refresh_owner = { buffer = "manager" },
    refresh = function(bufnr)
        return {
            { line = 0, type = "Misc" },
            { line = 1, text = "x", type = "Warn" },
            { line = 2, type = "Error" },
        }
    end,
})
```

- `refresh_owner = { buffer = "manager" }` is required with `refresh`. With
  this owner, the plugin calls `refresh` on `BufEnter`, `TextChanged`,
  `TextChangedI`, and `TextChangedP`.
- v1 called a handler on every `autocmd.render` event, including
  `WinScrolled`. If your marks must update on other events, use
  `refresh_owner = { buffer = "provider" }` and publish the marks from your
  own autocmds.
- Every mark needs a `type`. v1 used `Misc` when `type` was missing. The type
  must be configured in `scrollbar.marks`.
- Remove `level`. A mark can have only `line`, `type`, and `text`. A mark with
  another field fails validation.
- The `b:scrollbar_marks` buffer variable is removed. Publish marks through a
  provider.

See [Custom providers](providers/custom.md).

## Functions And Commands

| v1 | v2 |
| --- | --- |
| `:ScrollbarShow`, `:ScrollbarHide`, `:ScrollbarToggle` | Unchanged |
| `require("scrollbar.utils").show()` | `require("scrollbar").show()` |
| `require("scrollbar.utils").hide()` | `require("scrollbar").hide()` |
| `require("scrollbar.utils").toggle()` | `require("scrollbar").toggle()` |
| `require("scrollbar").render()`, `clear()`, `throttled_render()`, `on_scroll()` | Removed |

To collect provider marks again and render, use the new `:ScrollbarRefresh`
command or `require("scrollbar").refresh()`.

## Highlight Names

The scrollbar uses `Thumb` names where v1 used `Handle` names:

| v1 group | v2 group |
| --- | --- |
| `ScrollbarHandle` | `ScrollbarThumb` |
| `Scrollbar<Type>Handle` | `Scrollbar<Type>Thumb` |

v2 also uses `ScrollbarBase`, `ScrollbarTrack`, `ScrollbarThumbPressed`, and
`Scrollbar<Type>ThumbPressed`.

With `set_highlights = true`, the plugin creates the `Handle` names as default
links to the `Thumb` names. To change a color, define the `Thumb` name. A
public group that you define before or after setup stays in effect. v1
replaced these groups on setup and on `ColorScheme`.

With `set_highlights = false`, define the `Thumb` names. The `Handle` names
have no effect. See [Highlights](highlights.md).

## Default Changes

These defaults changed. Where the v2 column names an option, change that
option to get closer to the v1 behavior.

| Behavior | v1 | v2 |
| --- | --- | --- |
| Drawing | Virtual text at the right edge of the window | A floating window at the north-east corner of each source window |
| Mouse | No mouse support | `mouse.enabled = true`. Clicks also need `vim.o.mouse`. |
| Cursor over the scrollbar | No effect | `float.hide_on_cursor = true` hides the scrollbar while the cursor is in its cells |
| Update interval | `throttle_ms = 100` | `update.interval_ms = 16` |
| Thumb highlight | `CursorColumn` | `PmenuThumb` |
| Track | None | `track.highlight = "PmenuSbar"`, in the default layout |
| Search marks | Off, needed nvim-hlslens | `providers.search = true` |
| Native marks | None | `providers.marks = true` shows letter marks as `Mark` |
| `GitAdd` and `GitChange` text | `┆` | `┃` |
| Closed folds | Counted in buffers up to 1000 lines (`folds = 1000`) | Not counted (`render.geometry = "line"`) |
| coc.nvim diagnostics | Shown by the `diagnostic` handler | `providers.coc = false` |

## New In v2

- A minimap. See [Minimap](minimap/README.md).
- Declarative column layouts. See [Layout and geometry](layout-and-geometry.md).
- Presets. See [Presets](presets.md).
- Contextual profiles and autohide. See [Configuration](configuration.md) and
  [Visibility](visibility.md).
- Mouse navigation. See [Mouse](mouse.md).

## Related

- [Configuration](configuration.md)
- [Providers](providers/README.md)
- [Custom providers](providers/custom.md)
- [Highlights](highlights.md)
