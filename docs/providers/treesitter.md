# Treesitter Minimap Provider

The Treesitter provider colors occupied minimap cells from Treesitter highlight
captures. It targets only the minimap and is disabled by default.

## Setup

```lua
require("scrollbar").setup({
    providers = {
        treesitter = true,
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

The source buffer must have a Treesitter language mapping, an installed parser,
and a `highlights` query. The provider maps the filetype to a language with
`vim.treesitter.language.get_lang`. If one of these is missing, the minimap
content stays monochrome. Setup does not fail.

Only captures on one line color the minimap. Captures that span more than one
line are ignored.

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
whitespace or replace minimap glyphs.

## Related

- [Minimap](../minimap/README.md)
- [Minimap configuration](../minimap/configuration.md)
- [LSP semantic tokens](lsp_semantic_tokens.md)
