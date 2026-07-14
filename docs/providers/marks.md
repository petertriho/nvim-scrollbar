# Marks Provider

The marks provider is enabled by default. It renders supported Vim named marks
for each eligible loaded buffer and emits the `Mark` type.

## Setup And Defaults

`providers.marks` accepts `false`, `true`, or a table:

```lua
require("scrollbar").setup({
    providers = {
        marks = {
            letters = true,
            numbers = false,
            max_width = 8,
        },
    },
})
```

| Option | Default | Meaning |
| --- | --- | --- |
| `letters` | `true` | Include `a-z` and `A-Z` |
| `numbers` | `false` | Include `0-9` |
| `max_width` | unset | Use collapsed rendering; a positive integer enables bounded expansion |

`true` uses those category defaults in collapsed mode. `false` disables the
provider. Unknown keys and invalid types are rejected. If set, `max_width` must
be a positive integer greater than or equal to `float.width`.

The emitted `Mark` type defaults to:

| Option | Default |
| --- | --- |
| `marks.Mark.text` | `{}` |
| `marks.Mark.column` | `1` |
| `marks.Mark.priority` | `1` |
| `marks.Mark.highlight` | `"Special"` |

## Literal Names

The built-in provider supplies each mark's literal one-character name as mark
text. Literal names are displayed only while `marks.Mark.text` is the default
empty list. If `marks.Mark.text` is non-empty, its configured glyphs replace the
names:

```lua
marks = {
    Mark = {
        text = { "·", "•", "#" },
        column = 1,
        priority = 1,
        highlight = "Special",
    },
}
```

In collapsed mode, the configured list is used as normal density variants. In
expanded mode, every individually visible built-in mark uses the first variant.

## Mark Categories And Scope

- Lowercase `a-z` marks are buffer-local.
- Uppercase `A-Z` marks are global file marks. They are shown only on the
  eligible, loaded target buffer recorded by the mark.
- Numbered `0-9` marks are global file marks, normally restored from ShaDa.
  They cannot be set directly with `m{char}` and are opt-in with
  `numbers = true`.
- Special marks such as `.`, `^`, `[`, `]`, `<`, and `>` are not included.

The provider never loads a buffer or file solely to display an uppercase or
numbered mark. Its result is buffer-scoped, so all source windows displaying an
eligible target buffer share the same named marks.

## Collapsed Mode

With `providers.marks = true`, or with a table that omits `max_width`, rendering
uses the ordinary collapsed compositor. If several names map to one rendered
row, only one representative is visible.

Marks are ordered by source line and then literal name. Consequently names on
the same line sort as `0-9`, then `A-Z`, then `a-z`. The first visible
representative owns the exact click target for that cell; clicking it jumps to
that representative's source line, not to every mark compressed into the row.

## Expanded Mode

Set `max_width` to allow colliding built-in named marks to occupy separate
horizontal cells:

```lua
require("scrollbar").setup({
    providers = {
        marks = { max_width = 8 },
    },
})
```

- `max_width` caps the total effective float width; it is not a count of extra
  columns. `float.width` remains the fixed base track and handle width.
- The effective width grows only as needed and can grow or shrink independently
  per source window as rendered-row density changes.
- Expansion is limited by the active window or editor placement container,
  unless the configured base width already exceeds that container.
- `NW` and `SW` placements add columns to the right. `NE` and `SE` placements
  add columns to the left. The original base track and handle screen cells stay
  pinned while the float grows inward.
- Visible names retain source-line/name order from left to right. If the cap or
  container cannot fit every name, the deterministic ordered prefix is kept,
  the tail is omitted, and no synthetic `+` indicator is added.
- Every visible expanded name owns its exact source-line click target. Omitted
  names have no click cell.

Expansion applies only to `Mark` values emitted by the built-in provider named
`marks`. A custom provider that emits `type = "Mark"` remains in normal
collapsed composition even when built-in expansion is enabled.

## Mouse Targets

Mark navigation requires `mouse.enabled = true` and a user `mouse` option that
enables the current mode, such as `vim.o.mouse = "a"`.

Clicking a visible collapsed representative or expanded name jumps to its exact
source line, opens only the containing fold, centers the source view, and
restores source-window focus. A mark over the handle remains an exact mark click
when pressed and released without movement; moving after the press starts a
handle drag instead.

## Updates And Neovim Versions

Marks are collected during setup and refreshed on `BufEnter`, `BufWinEnter`,
`TextChanged`, `TextChangedI`, `TextChangedP`, and `TextChangedT`.
`:ScrollbarRefresh` also recollects them explicitly.

- Neovim 0.11 through 0.12.1 reconciles visible source buffers on `SafeState`
  because mark-change events are not complete enough for this provider.
- Neovim 0.12.2 and newer uses `MarkSet` for the default letter-only path and
  does not install `SafeState` polling for that path.
- Enabling numbered marks retains `SafeState` reconciliation on every supported
  version because explicit ShaDa reads and writes can change `0-9` without a
  `MarkSet` event.

Normal buffer-entry and text-change refreshes remain active on all supported
versions.

## Troubleshooting

- Use `:marks` to inspect Neovim's current named marks. An uppercase or numbered
  mark targeting an unloaded or ineligible buffer is intentionally absent.
- If letters are missing, verify `letters = true`; if numbers are missing,
  verify `numbers = true` and that ShaDa or another command has populated them.
- If glyphs appear instead of names, set `marks.Mark.text = {}` or remove the
  override.
- If expansion does not increase width, verify that `max_width` exceeds the base
  width, the placement container has room, and multiple names actually map to
  the same rendered row.
- If a visible name cannot be clicked, check `mouse.enabled`, `vim.o.mouse`, and
  whether `float.hide_on_cursor` has temporarily hidden the scrollbar.

## Related

- [Provider index](README.md)
- [Custom providers](custom.md)
- [Mark configuration](../configuration.md#marks-and-columns)
- [Wide scrollbars](../layout-and-geometry.md#wide-scrollbars)
- [Mouse](../mouse.md)
