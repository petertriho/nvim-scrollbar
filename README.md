<div align="center">
  <h1>nvim-scrollbar</h1>
  <h5>Extensible floating scrollbars for Neovim</h5>
</div>

![The default scrollbar and minimap while scrolling past diagnostics, Git hunks, and search matches](https://github.com/user-attachments/assets/b3d11b3b-6112-459b-b0f8-a7d77cca3470)

`nvim-scrollbar` adds a floating scrollbar to each window. Marks on the
scrollbar show where the diagnostics, search matches, Git changes, and other
items are. A click on a mark moves the cursor there. An optional minimap shows
a compressed view of the buffer. The plugin adds less than 0.1 ms to a
keystroke.

## Jump and Glance

Label mode puts a label on each scrollbar mark. Type a label to jump to its
mark, or type it in uppercase to peek at the lines first. Glance lists the
marks in a builtin window, snacks.nvim, Telescope, or a custom picker. With
`scrollbar.hover`, the peek also opens when the pointer rests on a mark. Label
mode is inspired by [flash.nvim](https://github.com/folke/flash.nvim), and the
glance window by [glance.nvim](https://github.com/dnlhc/glance.nvim).

![Label mode: labels on the scrollbar marks, a peek float from an uppercase label, and a jump](https://github.com/user-attachments/assets/e0980b14-b9e9-4a03-9da5-bae29f0a2f07)

![The glance window: a list of the marks, a preview that follows the selection, an edit in the preview, and a jump](https://github.com/user-attachments/assets/65d29073-e2c5-4fb3-9f43-310737593faa)

![Hover: the peek float opens while the pointer rests on a mark of the scrollbar](https://github.com/user-attachments/assets/02a49328-44e8-4c3a-b2c8-e20ec6bdb71e)

```lua
vim.keymap.set("n", "<leader>j", function()
    require("scrollbar").jump()
end, { desc = "Jump to a scrollbar mark" })

vim.keymap.set("n", "<leader>p", function()
    require("scrollbar").peek()
end, { desc = "Peek at a scrollbar mark" })

vim.keymap.set("n", "<leader>g", function()
    require("scrollbar").glance()
end, { desc = "Glance at the marks" })
```

The commands are `:ScrollbarJump [types]`, `:ScrollbarPeek [types]`, and
`:ScrollbarGlance [types]`. See [Jump and Glance](docs/jump-and-glance.md).

## Requirements

- Neovim 0.11 or newer
- For mouse support, a `mouse` value such as `set mouse=a`
- Optional integrations:
  [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim),
  [mini.diff](https://github.com/nvim-mini/mini.diff),
  [vim-signify](https://github.com/mhinz/vim-signify),
  [vgit.nvim](https://github.com/tanvirtin/vgit.nvim),
  [ALE](https://github.com/dense-analysis/ale), and
  [coc.nvim](https://github.com/neoclide/coc.nvim)

## Installation

If you upgrade from v1, read the [migration guide](docs/migration.md), or pin
`branch = "v1"`.

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "petertriho/nvim-scrollbar",
    lazy = false,
    opts = {},
}
```

If you add `keys` to the spec, keep `lazy = false`. Otherwise no scrollbar
shows until the first key press.

[vim-plug](https://github.com/junegunn/vim-plug), then call `setup()` from Lua:

```vim
Plug 'petertriho/nvim-scrollbar'
```

```lua
require("scrollbar").setup()
```

## Quick Start

```lua
require("scrollbar").setup({
    providers = {
        search = { incsearch = true },
        marks = { numbers = true },
    },
    scrollbar = {
        preset = "zed",
        autohide = true,
    },
})
```

With `autohide`, a scrollbar shows when its window scrolls or its cursor
moves, and hides after 1 second without activity.

Scrollbar presets: `vscode`, `zed`, `intellij`, `minimal`, `review`, `search`,
`navigate`, `gvim`, `eclipse`, `sublime`, `emacs`, and `xcode`. The
[showcase](https://github.com/petertriho/nvim-scrollbar/issues/120) shows each
scrollbar and minimap preset.

Profiles change the appearance of matching windows. The first match applies:

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

Setup rejects unknown keys and invalid values. See the
[configuration reference](docs/configuration.md).

## Minimap

The minimap is off by default. It uses the same `providers`, `marks`, and
`exclude` tables as the scrollbar:

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
    },
})
```

By default, it draws the buffer as Braille dots, with Treesitter colors when
the buffer has a parser. Its presets are `vscode`, `sublime`, `zed`, `xcode`, `overview`,
`compact`, `minimal`, and `blocks`. See the
[minimap documentation](docs/minimap/README.md).

## Pickers and Floats

With `floats = true` in the `scrollbar` or `minimap` block, that bar also shows
on the list and preview of the snacks.nvim and Telescope pickers, and on the
snacks.nvim zen and zoom windows. A `when` function adds other floats:

```lua
require("scrollbar").setup({
    scrollbar = {
        floats = {
            snacks = true,
            telescope = true,
            when = require("scrollbar.recipes").when.filetypes({ "lazy" }),
        },
    },
})
```

Jump, peek, glance, and hover also work on these floats. See
[Floats](docs/floats.md).

## Providers

| Provider | Scrollbar | Minimap | Source | Dependency |
| --- | --- | --- | --- | --- |
| [`cursor`](docs/providers/cursor.md) | on | on | Source-window cursor | None |
| [`diagnostic`](docs/providers/diagnostic.md) | on | on | Neovim `vim.diagnostic` | None |
| [`search`](docs/providers/search.md) | on | on | Native `/` and `?` search | None |
| [`marks`](docs/providers/marks.md) | on | on | Letter marks, and optional numbered marks | None |
| [`gitsigns`](docs/providers/gitsigns.md) | off | off | Git hunks | gitsigns.nvim |
| [`mini_diff`](docs/providers/mini_diff.md) | off | off | mini.diff hunks | mini.diff |
| [`signify`](docs/providers/signify.md) | off | off | vim-signify hunks | vim-signify |
| [`vgit`](docs/providers/vgit.md) | off | off | vgit hunks | vgit.nvim |
| [`ale`](docs/providers/ale.md) | off | off | ALE location list | ALE |
| [`coc`](docs/providers/coc.md) | off | off | Coc diagnostic list | coc.nvim |
| [`qflist`](docs/providers/qflist.md) | off | off | Quickfix list | None |
| [`loclist`](docs/providers/loclist.md) | off | off | Location list of each window | None |
| [`treesitter`](docs/providers/treesitter.md) | unavailable | on | Treesitter highlight captures | Installed parser |
| [`lsp_semantic_tokens`](docs/providers/lsp_semantic_tokens.md) | unavailable | off | LSP semantic tokens | Attached LSP client |

Set each provider in `providers` to `true`, `false`, or a table of options. See
the [provider overview](docs/providers/README.md), or add your own with the
[custom provider API](docs/providers/custom.md).

## Documentation

- [Configuration](docs/configuration.md): every option and default
- [Presets](docs/presets.md): scrollbar and minimap presets
- [Visibility](docs/visibility.md): autohide, hide-on-cursor, and commands
- [Floats](docs/floats.md): pickers and other floats
- [Layout and geometry](docs/layout-and-geometry.md): lanes, placement, and
  units
- [Mouse](docs/mouse.md): clicks and thumb dragging
- [Jump and Glance](docs/jump-and-glance.md): label mode, peek, glance, and
  hover
- [Providers](docs/providers/README.md): built-in and custom providers
- [Minimap](docs/minimap/README.md) and
  [minimap configuration](docs/minimap/configuration.md)
- [Highlights](docs/highlights.md): highlight groups and blending
- [Migration](docs/migration.md): changes from earlier releases
- [Development](docs/development.md): tests, benchmarks, and CI

## License

[MIT](LICENSE)
