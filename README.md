<div align="center">
  <h1>nvim-scrollbar</h1>
  <h5>Extensible floating scrollbars for Neovim</h5>
</div>

![diagnostics](./assets/diagnostics.gif)

`nvim-scrollbar` renders one floating scrollbar per source window, with
independent handles for split windows, typed mark providers, optional
screen-row-accurate geometry, and mouse navigation.

## Requirements

- Neovim 0.11 or newer
- The user's Neovim `mouse` option must enable the desired modes for mouse
  interaction, for example `set mouse=a`. The plugin never changes `mouse`.
- Optional integrations:
  [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim),
  [mini.diff](https://github.com/nvim-mini/mini.diff),
  [ALE](https://github.com/dense-analysis/ale), and
  [coc.nvim](https://github.com/neoclide/coc.nvim)

## Installation

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "petertriho/nvim-scrollbar",
    opts = {},
}
```

`opts = {}` calls `require("scrollbar").setup({})` automatically. Put any
configuration overrides inside `opts`.

[vim-plug](https://github.com/junegunn/vim-plug):

```vim
Plug 'petertriho/nvim-scrollbar'
```

With vim-plug or another manual installation, configure the plugin from Lua:

```lua
require("scrollbar").setup()
```

## Quick Start

The defaults enable cursor, diagnostic, search, and named-mark providers for
every eligible source window. A small customized setup might look like:

```lua
require("scrollbar").setup({
    autohide = {
        enabled = true,
    },
    providers = {
        search = { incsearch = true },
        marks = { numbers = true, max_width = 8 },
    },
})
```

Because this example enables autohide, scrollbars begin concealed and are
revealed by cursor movement or scrolling in the affected source window.

Unknown keys and invalid values are rejected. See the
[complete configuration reference](docs/configuration.md) for every default and
accepted value.

## Providers

| Provider | Default | Source | Dependency |
| --- | --- | --- | --- |
| [`cursor`](docs/providers/cursor.md) | on | Source-window cursor | None |
| [`diagnostic`](docs/providers/diagnostic.md) | on | Neovim `vim.diagnostic` | None |
| [`search`](docs/providers/search.md) | on | Native `/` and `?` search | None |
| [`marks`](docs/providers/marks.md) | on | Letter marks; optional numbered marks | None |
| [`gitsigns`](docs/providers/gitsigns.md) | off | Git hunks | gitsigns.nvim |
| [`mini_diff`](docs/providers/mini_diff.md) | off | mini.diff hunks | mini.diff |
| [`ale`](docs/providers/ale.md) | off | ALE location list | ALE |
| [`coc`](docs/providers/coc.md) | off | Coc diagnostic list | coc.nvim |

See the [provider overview](docs/providers/README.md) for shared configuration
rules, dependencies, update behavior, and links to every provider. New data
sources can be added through the [custom provider API](docs/providers/custom.md).

## Documentation

### Guides

- [Configuration](docs/configuration.md): complete defaults, validation,
  eligibility, mark text, columns, and priorities
- [Visibility](docs/visibility.md): source-window visibility, autohide,
  hide-on-cursor behavior, commands, and Lua APIs
- [Layout and geometry](docs/layout-and-geometry.md): placement, line and screen
  geometry, rendering cadence, and wide scrollbars
- [Mouse](docs/mouse.md): clicks, mark navigation, handle dragging, and focus
  behavior
- [Highlights](docs/highlights.md): generated groups, direct definitions,
  blending, and manual highlights
- [Migration](docs/migration.md): changes required from earlier releases
- [Development](docs/development.md): tests, quality checks, benchmarks, and CI

### Provider Guides

- [Provider overview](docs/providers/README.md)
- [Cursor](docs/providers/cursor.md)
- [Diagnostics](docs/providers/diagnostic.md)
- [Search](docs/providers/search.md)
- [Marks](docs/providers/marks.md)
- [Gitsigns](docs/providers/gitsigns.md)
- [MiniDiff](docs/providers/mini_diff.md)
- [ALE](docs/providers/ale.md)
- [Coc](docs/providers/coc.md)
- [Custom providers](docs/providers/custom.md)

## License

[MIT](LICENSE)
