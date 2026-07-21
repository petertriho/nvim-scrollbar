# Treesitter Minimap Provider

The Treesitter provider colors occupied minimap cells from Treesitter highlight
captures. It targets only the minimap and is disabled by default.

## Setup

```lua
require("scrollbar").setup({
    minimap = {
        enabled = true,
        providers = {
            treesitter = true,
        },
    },
})
```

`minimap.providers.treesitter` is a setup-level boolean. It cannot be selected
by a minimap preset or profile.

## Requirements

The source buffer must have a Treesitter language mapping, an installed parser,
and a `highlights` query. The language is resolved from the filetype with
`vim.treesitter.language.get_lang`. Missing mappings, parsers, trees, roots, or
queries degrade to monochrome minimap content without failing setup.

Only single-line capture nodes become spans. Each span uses zero-based source
byte columns and the capture group `@capture_name`.

## Backend Behavior

With the default minimap `backend = "worker"`, language resolution happens in
the parent, while parser startup, parsing, query lookup, capture collection,
semantic composition, and squashing happen in the embedded child Neovim. The
child starts with `-u NONE -i NONE --noplugin`, so the parser and query files
must still be discoverable through that Neovim's runtime paths; plugin setup
code is not executed there.

With `backend = "sync"`, collection and squashing run in the parent Neovim. The
same provider code and squash algorithm are used in both modes. Accepted worker
captures are published to the shared `minimap_spans` store channel for the
buffer, but that publication reuses the accepted cell result instead of
requesting a duplicate squash.

## Priority

Treesitter spans use priority `100`. Higher numeric semantic priorities win
inside the squash. The LSP semantic-token provider uses `200` through `202`, so
overlapping LSP layers override Treesitter captures. Equal-priority ties use
provider name and then publication order.

Treesitter color applies only to occupied source columns. It does not fill
whitespace or replace minimap glyphs.

## Related

- [Minimap configuration](../minimap/configuration.md)
- [Minimap layout](../minimap/layout.md)
- [LSP semantic tokens](lsp_semantic_tokens.md)
