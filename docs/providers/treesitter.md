# Treesitter Minimap Provider

The Treesitter provider colors occupied minimap cells from Treesitter highlight
captures. It targets only the minimap and is enabled by default. It runs only
when the minimap is enabled.

![A minimap with dots in the colors of the Treesitter captures](https://github.com/user-attachments/assets/511ed7bc-1e2d-4f43-9067-e7561c7a261e)

## Setup

The provider needs no setup. To turn it off:

```lua
require("scrollbar").setup({
    providers = {
        treesitter = false,
    },
    minimap = {
        enabled = true,
    },
})
```

`providers.treesitter` is a boolean, or a table that contains only the
`scrollbar` and `minimap` target flags. The provider runs only when the minimap
is enabled. Setup rejects `scrollbar = true`. A minimap profile cannot select
the provider.

## Requirements

The provider maps the filetype to a language with
`vim.treesitter.language.get_lang`. The source buffer must have a Treesitter
language mapping, an installed parser, and a `highlights` query. If one of
these items is missing, the minimap content stays monochrome, and setup does
not fail.

Only captures on one line color the minimap. The provider ignores captures that
span more than one line. It captures only the lines of the map slice that the
minimap squashes. See [Backends](../minimap/configuration.md#backends).

## Backend Behavior

With the default `minimap.backend = "worker"`, Treesitter parsing and capture
collection run in a separate headless Neovim process. This process does not
load your configuration or plugins. The parser and query files must be on the
runtime path of that process.

With `minimap.backend = "sync"`, Treesitter collection runs in the main Neovim
process.

## Priority

Treesitter spans use priority `100`. The LSP semantic-token provider uses `200`
through `202`, so overlapping LSP spans override Treesitter captures.

Treesitter color applies only to occupied source columns. It does not fill
whitespace or change the minimap dots. When a cell covers columns with
different captures, the capture with the highest priority wins. If the
priorities are equal, the capture that comes first wins.

## Related

- [Minimap](../minimap/README.md)
- [Minimap configuration](../minimap/configuration.md)
- [LSP semantic tokens](lsp_semantic_tokens.md)
