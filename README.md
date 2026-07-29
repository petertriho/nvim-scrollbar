<div align="center">
  <h1>nvim-scrollbar</h1>
  <h5>Extensible floating scrollbars for Neovim</h5>
</div>

![diagnostics](./assets/diagnostics.gif)

`nvim-scrollbar` renders one floating scrollbar per source window, with
independent thumbs for split windows, declarative typed mark lanes, optional
screen-row-accurate geometry, and mouse navigation. It also ships an
**separately rendered minimap subsystem** — a separately-enabled floating minimap
with a monochrome code texture, independently blendable base surface, viewport
tint, exact cursor-cell accent, cursor-overlap yielding, click-to-jump,
drag-to-scroll, and diagnostic/gitsigns/search overlays.

## Requirements

- Neovim 0.11 or newer
- The user's Neovim `mouse` option must enable the desired modes for mouse
  interaction, for example `set mouse=a`. The plugin never changes `mouse`.
- Optional integrations:
  [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim),
  [mini.diff](https://github.com/nvim-mini/mini.diff),
  [vim-signify](https://github.com/mhinz/vim-signify),
  [vgit.nvim](https://github.com/tanvirtin/vgit.nvim),
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

The scrollbar defaults enable cursor, diagnostic, search, and named-mark
providers for every eligible source window. A small customized setup might
look like:

```lua
require("scrollbar").setup({
    scrollbar = {
        preset = "zed",
        autohide = {
            enabled = true,
        },
        providers = {
            search = { incsearch = true },
            marks = { numbers = true },
        },
    },
})
```

Because this example enables autohide, scrollbars begin concealed and are
revealed by cursor movement or scrolling in the affected source window.

The built-in catalog includes `vscode`, `zed`, `intellij`, `minimal`, `review`,
`search`, `navigate`, `gvim`, `eclipse`, `sublime`, `emacs`, and `xcode`.
Ordered contextual profiles can select a precompiled variant per source window:

```lua
require("scrollbar").setup({
    scrollbar = {
        preset = "zed",
        profiles = {
            {
                match = { filetypes = { "markdown", "text" } },
                preset = "minimal",
            },
            {
                match = { filetypes = { "lua" } },
                preset = "review",
            },
        },
    },
})
```

Profiles use first-match precedence. Providers, scheduling, exclusions,
visibility, and autohide remain root-owned.

Unknown keys and invalid values are rejected. See the
[complete configuration reference](docs/configuration.md) for every default and
accepted value.

## Minimap

The minimap is an independent subsystem: it has its own config slice,
scheduler, renderer, mouse handler, presets, and profiles. It defaults to
**disabled**. Its rendering lifecycle does not control the scrollbar, although
enabled built-in providers may be shared by both renderers.

```lua
require("scrollbar").setup({
    scrollbar = {},
    minimap = {
        enabled = true,
    },
})
```

The default placement is window-relative at the north-east corner — one solid
16-column minimap per source window — with monochrome full-block content, a
tint-only viewport, an exact cursor-cell accent, and store-published overlays
on. Each terminal minimap row represents one source-line bucket, and occupied
cells render with the configurable single-width `content_glyph` (`"█"` by
default). Its default providers are cursor, diagnostic, search, and named marks.
Treesitter and LSP semantic-token coloring are separate opt-in providers:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        providers = {
            treesitter = true,
            lsp_semantic_tokens = true,
        },
    },
})
```

`minimap.float.blend` controls the full float and may vary by profile.
Root-only `minimap.background.blend = false` inherits that setting; a numeric
value overrides only the base surface and works independently when the
full-float blend is zero. The default `minimap.float.hide_on_cursor = true`
temporarily hides only the active source's existing minimap when the editing
cursor overlaps it, then restores the same resources when the cursor leaves.

Ordinary overlays have independent minimap priority and highlight sources. The
keyed map deep-merges with specs derived from scrollbar marks; use `false` to
disable one derived type:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        overlays = {
            types = {
                Search = { priority = 0, highlight = "IncSearch" },
                Hint = false,
            },
        },
    },
})
```

Automatic overlay groups use distinct public names such as
`ScrollbarMinimapSearch`; existing user definitions of public scrollbar and
minimap groups are preserved.

See the [minimap documentation](docs/minimap/README.md) for the full schema,
layout, overlays, and mouse behavior.

## Providers

| Provider | Scrollbar | Minimap | Source | Dependency |
| --- | --- | --- | --- | --- |
| [`cursor`](docs/providers/cursor.md) | on | on | Source-window cursor | None |
| [`diagnostic`](docs/providers/diagnostic.md) | on | on | Neovim `vim.diagnostic` | None |
| [`search`](docs/providers/search.md) | on | on | Native `/` and `?` search | None |
| [`marks`](docs/providers/marks.md) | on | on | Letter marks; optional numbered marks | None |
| [`gitsigns`](docs/providers/gitsigns.md) | off | off | Git hunks | gitsigns.nvim |
| [`mini_diff`](docs/providers/mini_diff.md) | off | off | mini.diff hunks | mini.diff |
| [`signify`](docs/providers/signify.md) | off | off | vim-signify hunks | vim-signify |
| [`vgit`](docs/providers/vgit.md) | off | off | vgit hunks | vgit.nvim |
| [`ale`](docs/providers/ale.md) | off | off | ALE location list | ALE |
| [`coc`](docs/providers/coc.md) | off | off | Coc diagnostic list | coc.nvim |
| [`treesitter`](docs/providers/treesitter.md) | unavailable | off | Treesitter highlight captures | Installed parser |
| [`lsp_semantic_tokens`](docs/providers/lsp_semantic_tokens.md) | unavailable | off | LSP semantic tokens | Attached LSP client |

The scrollbar and minimap provider tables are strict built-in allow-lists.
When both request the same built-in, one provider instance serves their union;
each renderer still filters the shared output through its own enabled-provider
set. A disabled minimap contributes no built-in provider demand.

See the [provider overview](docs/providers/README.md) for shared configuration
rules, dependencies, update behavior, and links to every provider. New data
sources can be added through the [custom provider API](docs/providers/custom.md).

## Documentation

### Guides

- [Configuration](docs/configuration.md): complete defaults, validation,
  eligibility, mark presentation, layout lanes, and priorities
- [Presets](docs/presets.md): all twelve built-ins, focused filtering, local
  inheritance, and override precedence
- [Visibility](docs/visibility.md): source-window visibility, autohide,
  hide-on-cursor behavior, commands, and Lua APIs
- [Layout and geometry](docs/layout-and-geometry.md): placement, line and screen
  geometry, rendering cadence, and wide scrollbars
- [Mouse](docs/mouse.md): clicks, mark navigation, thumb dragging, and focus
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
- [Signify](docs/providers/signify.md)
- [Vgit](docs/providers/vgit.md)
- [ALE](docs/providers/ale.md)
- [Coc](docs/providers/coc.md)
- [Treesitter](docs/providers/treesitter.md)
- [LSP semantic tokens](docs/providers/lsp_semantic_tokens.md)
- [Custom providers](docs/providers/custom.md)

### Minimap Guides

- [Minimap overview](docs/minimap/README.md)
- [Minimap configuration](docs/minimap/configuration.md)
- [Minimap layout](docs/minimap/layout.md)
- [Minimap overlays](docs/minimap/overlays.md)
- [Minimap mouse](docs/minimap/mouse.md)

## License

[MIT](LICENSE)
