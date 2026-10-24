# Floats

By default, the scrollbar and the minimap show only on normal windows. The
`floats` option of each block also shows them on these floating windows:

- The list and the preview of the snacks.nvim picker. The minimap does not
  support the list.
- The results and the preview of the Telescope picker.
- Other floats that a `when` function selects.

```lua
require("scrollbar").setup({
    scrollbar = { floats = true },
    minimap = { enabled = true, floats = true },
})
```

## The `floats` Option

`floats` is a global option of the `scrollbar` block and of the `minimap`
block. The default is `false`. A profile cannot set it, but a profile can
match float sources with [`match.floats`](#profiles).

| Value | Effect |
| --- | --- |
| `false` | No float is a source window. |
| `true` | Every built-in kind of the block is on. For the minimap, this is every built-in kind except `snacks_list`. |
| A table | Only the kinds that the table turns on are on. |

The table form:

```lua
scrollbar = {
    floats = {
        snacks = { list = true, preview = true }, -- or true, or false
        telescope = { results = true, preview = true }, -- or true, or false
        when = function(context)
            return context.filetype == "lazy"
        end,
    },
}
```

- `snacks = true` turns on the list and the preview. `telescope = true` turns
  on the results and the preview.
- A key that you do not set is off. For example, `snacks = { list = true }`
  turns on only the list.
- `when` selects other floats. See [Other Floats](#other-floats).

## Kinds

Each source window has a kind. A normal window has the kind `"normal"`. A
float source has one of these kinds:

| Kind | Window | Key | Minimap |
| --- | --- | --- | --- |
| `snacks_list` | The list of a snacks.nvim picker | `snacks.list` | Not supported |
| `snacks_preview` | The preview of a snacks.nvim picker | `snacks.preview` | Supported |
| `telescope_results` | The results of a Telescope picker | `telescope.results` | Supported |
| `telescope_preview` | The preview of a Telescope picker | `telescope.preview` | Supported |
| `custom` | A float that `when` accepts | `when` | Supported |

The plugin never loads snacks.nvim or Telescope. It reads the state of a
picker only after snacks.nvim loads `snacks.picker.core.picker` or Telescope
loads `telescope.state`.

The input window of snacks and the prompt window of Telescope get no bar. They
are not built-in kinds, and the default [`exclude`](#eligibility) table
excludes their filetypes, also when `when` accepts them.

The minimap cannot draw the snacks list, because the list buffer holds only
the visible rows. A `snacks.list` key in `minimap.floats` is a setup error:

```text
minimap.floats.snacks.list is not supported. The minimap cannot draw the snacks list, because its buffer holds only the visible rows
```

## Other Floats

`when` receives this table:

```lua
{
    winid = source_win,
    bufnr = source_buf,
    filetype = vim.bo[source_buf].filetype,
    buftype = vim.bo[source_buf].buftype,
    bufname = vim.api.nvim_buf_get_name(source_buf),
    config = vim.api.nvim_win_get_config(source_win),
}
```

If `when` returns a truthy value, the float is a source window with the kind
`"custom"`.

- `when` runs only for the floats that are not built-in kinds. Only the
  `snacks` and `telescope` keys decide a window of a built-in kind.
- `when` never runs for the floats of the scrollbar and the minimap, or for
  external windows.
- The plugin calls `when` often, also before each render. Keep the function
  fast, free of side effects, and non-blocking.
- If `when` raises an error, the float is not a source window. A notification
  appears once for each distinct error message until the next setup, for
  example `[nvim-scrollbar] scrollbar floats.when matcher failed: <message>`.

This example shows the bars on the lazy.nvim and mason.nvim windows:

```lua
scrollbar = {
    floats = {
        when = function(context)
            return context.filetype == "lazy" or context.filetype == "mason"
        end,
    },
}
```

## Eligibility

A float source follows the same eligibility rules as a normal window:

- The top-level `exclude` table applies. The default list excludes the
  `snacks_picker_input` and `TelescopePrompt` filetypes, and several
  completion and notification floats. See
  [Exclude](configuration.md#exclude).
- `max_lines` applies. For the snacks list, `max_lines` counts the items of the
  list, not the lines of its buffer.

## Profiles

`match.floats` selects float sources for a profile:

- `true` matches every float source.
- A dense list of kinds matches only those kinds, for example
  `{ "snacks_preview", "custom" }`.

A profile with `match.floats` matches only float sources. A profile without
`match.floats` matches only normal windows. The other matchers of the profile
also apply, and the first profile that matches wins. The minimap rejects
`"snacks_list"` in `match.floats`.

```lua
scrollbar = {
    floats = true,
    profiles = {
        {
            match = { floats = { "snacks_preview", "telescope_preview" } },
            unit = "screenline",
        },
        {
            match = { floats = true },
            placement = { gutter = "overlap" },
        },
    },
}
```

## Visibility

With `visibility = "active"`, the bars of the picker that has focus show:

- While the snacks input has focus, the bars of the list and the preview show.
  While the Telescope prompt has focus, the bars of the results and the preview
  show.
- While the list or the preview has focus, the bars of the same picker show.
- When focus leaves the picker, these bars hide, and the bar of the active
  window shows.

With `placement.relative = "editor"`, only the bar of the active source window
shows, also in a picker. The input and the prompt are not source windows, so
no editor-relative bar shows while they have focus.

## Z-Index

A bar on a float source uses the z-index of the source + 1.
`placement.zindex` applies only to normal windows.

When the scrollbar and the minimap overlap (`placement.stack = "above"` or
`"below"`), the bottom float uses the z-index of the source + 1. The top float
uses the z-index of the source + 2. Thus no bar goes under its source.

## Placement

The bars use the placement of their configuration:

- A window-relative bar follows its source float. Neovim does not move a float
  that is relative to a floating window when that window moves. Thus each
  render after a move applies the bar configuration again.
- An editor-relative bar uses the edges of the editor, not the edges of the
  float.
- With a west anchor, `gutter = "inner"` and `gutter = "outer"` reserve gutter
  cells in the float through `statuscolumn`. The picker text shifts by the
  width of these cells.

Snacks resets `statuscolumn` when its preview shows another buffer. The render
after `BufWinEnter` restores the reservation, so the preview text can shift for
one redraw. To keep the text in place, set `gutter = "overlap"` in a float
profile, as in the example in [Profiles](#profiles).

## Wrapped Previews

A preview that wraps long lines shows fewer buffer lines than it has rows.
With `unit = "line"`, the thumb counts buffer lines. To count screen lines, set
`unit = "screenline"` in a float profile, as in the example in
[Profiles](#profiles).

## The snacks.nvim List

The snacks list is virtual: its buffer holds only the visible rows. Thus the
plugin reads the position from the list object of snacks: the item count, the
first visible item, the height, and the order. These fields are private to
snacks.nvim.

- The plugin wraps the `render` method of the snacks list class once. Thus
  each render of a list also renders its bar.
- If snacks.nvim removes or renames a field of the list, the list gets no bar.
  The other windows are not affected.
- If the list class has no `render` method, the bar of the list changes only
  when another event renders it.
- The thumb always uses the `"line"` unit, also with `unit = "screenline"`.
- The list shows no marks. The providers do not apply to it.
- In a reversed list, the first item is on the bottom row. The `telescope`
  layout preset of snacks reverses the list. The thumb follows the order on the
  screen.
- A click on the track or a drag of the thumb selects the item at that
  position. The preview follows the selection.

## Text Changes

A picker writes its results while its prompt has focus. Neovim fires no
`TextChanged` event for a buffer that is not current. Thus each renderer
attaches to the buffer of each float source, except the snacks list. After a
change, it renders the windows of that buffer again. When no float source shows
the buffer, the renderer detaches from it at the next change.

## Limits

- With the default `sorting_strategy = "descending"`, Telescope keeps blank
  rows above the results. The thumb counts these rows. Thus it stays near the
  bottom of the track and moves less than the selection. With
  `sorting_strategy = "ascending"`, the thumb counts only the results.
- When a float source moves but keeps its size, Neovim fires no event. Its bars
  stay at the old position until the next render. Snacks and Telescope resize
  their windows when the windows move, so the bars of these windows follow.
- The snacks explorer shows its list in a split window, not in a float. It is a
  normal window, so its bar counts the lines of its buffer, which are only the
  visible rows.
- External windows of a multigrid UI get no bars.

## Related

- [Configuration](configuration.md)
- [Minimap configuration](minimap/configuration.md)
- [Visibility](visibility.md)
- [Layout and geometry](layout-and-geometry.md)
- [Mouse](mouse.md)
