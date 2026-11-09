# Configuration

`require("scrollbar").setup()` validates every option. Unknown keys and invalid
values are setup errors, and the previous configuration stays active. Every
call starts from fresh defaults. It does not merge with a previous setup call.

## Structure

The configuration has shared sections and one block for each renderer:

```lua
require("scrollbar").setup({
    -- Shared by the scrollbar and the minimap
    set_highlights = true,
    exclude = {},   -- buffers that get no scrollbar or minimap
    providers = {}, -- data sources, their options, and their renderers
    marks = {},     -- mark types and their presentation

    -- Renderer blocks
    scrollbar = {},
    minimap = {},   -- disabled by default, see the minimap documentation
})
```

Each renderer block has two kinds of options:

- **Global options** apply to every window of that renderer. You set them only
  at the root of the block.
- **Appearance options** can change for each window. You set them at the root
  of the block, in a [preset](presets.md), or in a [profile](#profiles).

The [minimap configuration](minimap/configuration.md) documents the `minimap`
block.

## Defaults

```lua
require("scrollbar").setup({
    set_highlights = true,
    exclude = {
        buftypes = { "terminal" },
        filetypes = {
            "blink-cmp-menu",
            "dropbar_menu",
            "dropbar_menu_fzf",
            "DressingInput",
            "cmp_docs",
            "cmp_menu",
            "noice",
            "prompt",
            "snacks_picker_input",
            "TelescopePrompt",
        },
        unfocusable = true,
        when = false,
    },
    providers = {
        cursor = true,
        diagnostic = true,
        search = true,
        marks = true,
        gitsigns = false,
        mini_diff = false,
        signify = false,
        vgit = false,
        ale = false,
        coc = false,
        treesitter = true, -- the minimap only
        lsp_semantic_tokens = false,
    },
    marks = {
        Cursor = { text = { "•" }, priority = 0, highlight = "Normal" },
        Mark = { text = {}, priority = 1, highlight = "Special" },
        Search = { text = { "-", "=" }, priority = 1, highlight = "Search" },
        Error = { text = { "-", "=" }, priority = 2, highlight = "DiagnosticVirtualTextError" },
        Warn = { text = { "-", "=" }, priority = 3, highlight = "DiagnosticVirtualTextWarn" },
        Info = { text = { "-", "=" }, priority = 4, highlight = "DiagnosticVirtualTextInfo" },
        Hint = { text = { "-", "=" }, priority = 5, highlight = "DiagnosticVirtualTextHint" },
        Misc = { text = { "-", "=" }, priority = 6, highlight = "Normal" },
        GitAdd = { text = { "┃" }, priority = 7, highlight = "GitSignsAdd" },
        GitChange = { text = { "┃" }, priority = 7, highlight = "GitSignsChange" },
        GitDelete = { text = { "▁" }, priority = 7, highlight = "GitSignsDelete" },
        MiniDiffAdd = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignAdd" },
        MiniDiffChange = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignChange" },
        MiniDiffDelete = { text = { "▒" }, priority = 7, highlight = "MiniDiffSignDelete" },
        SignifyAdd = { text = { "┃" }, priority = 7, highlight = "SignifySignAdd" },
        SignifyChange = { text = { "┃" }, priority = 7, highlight = "SignifySignChange" },
        SignifyDelete = { text = { "▁" }, priority = 7, highlight = "SignifySignDelete" },
        VGitAdd = { text = { "┃" }, priority = 7, highlight = "GitSignsAdd" },
        VGitChange = { text = { "┃" }, priority = 7, highlight = "GitSignsChange" },
        VGitDelete = { text = { "▁" }, priority = 7, highlight = "GitSignsDelete" },
    },
    scrollbar = {
        -- Global options
        enabled = true,
        show = true,
        visibility = "all", -- "all" or "active"
        autohide = false, -- true, or { delay_ms = 1000 }
        max_lines = false,
        floats = false, -- true, or a table, see Floats
        throttle_ms = 16,
        events = { -- see Events
            "BufEnter", "BufWinEnter",
            "WinEnter", "TabEnter", "TermEnter", "CmdwinLeave",
            "CursorMoved", "CursorMovedI",
            "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT",
            "WinScrolled", "WinResized", "VimResized",
            "OptionSet", "ColorScheme",
            "WinClosed", "BufDelete", "BufWipeout", "TabClosed",
        },

        -- Appearance options
        preset = nil,
        unit = "line", -- "line" or "screenline"
        placement = {
            relative = "window", -- "window" or "editor"
            anchor = "NE", -- "NW", "NE", "SW", or "SE"
            row = 0,
            col = 0,
            gutter = "inner", -- "inner", "outer", or "overlap"
            zindex = 30,
        },
        hide_on_cursor = true, -- true, false, or "row"
        hide_if_all_visible = false,
        mouse = true,
        layout = {
            direction = "auto", -- "auto", "ltr", or "rtl"
            columns = {
                { "track", "thumb", "marks" },
            },
        },
        track = { highlight = "PmenuSbar" },
        thumb = {
            text = " ",
            blend = 30,
            highlight = "PmenuThumb",
            hide_if_all_visible = true,
        },
        overlap = { -- see Overlap
            reserve = true,
            show_through = false, -- false, or a blend from 1 to 100
            marks = "glyph", -- "glyph" or "tint"
        },
        marks = {}, -- overrides of the shared mark types
        window = { -- see Window
            border = "none",
            wo = {},
        },

        profiles = nil,
    },
})
```

## Scrollbar Options

### Global Options

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | When `false`, the scrollbar requests no providers, shows no floats, and creates no `:Scrollbar*` commands. Use this for a minimap-only setup. |
| `show` | `true` | Initial master visibility. `false` starts hidden. `:ScrollbarShow` shows the scrollbar. |
| `visibility` | `"all"` | `"all"` shows a scrollbar in every eligible window. `"active"` shows only the scrollbar of the active window. |
| `autohide` | `false` | `true` conceals each scrollbar after 1000 ms without activity in its window. `{ delay_ms = n }` sets the delay. |
| `max_lines` | `false` | A buffer with more lines than this number gets no scrollbar. |
| `floats` | `false` | Floats that get a scrollbar. The built-in kinds are the list and the preview of the snacks.nvim picker, and the results and the preview of the Telescope picker. A `when` function selects other floats. See [Floats](floats.md). |
| `throttle_ms` | `16` | Renders that are queued within this interval combine into one frame. `0` renders as fast as possible. |
| `events` | see Defaults | Autocommand events that update the scrollbar. See [Events](#events). |

[Visibility](visibility.md) documents `show`, `visibility`, and `autohide`.

### Appearance Options

| Option | Default | Meaning |
| --- | --- | --- |
| `preset` | `nil` | Name of a [built-in preset](presets.md#scrollbar-presets). |
| `unit` | `"line"` | `"line"` counts buffer lines. `"screenline"` counts screen lines, so it accounts for wrapped lines and closed folds. See [Units](layout-and-geometry.md#units). |
| `placement` | see Defaults | Position of the float. See [Layout and geometry](layout-and-geometry.md). |
| `hide_on_cursor` | `true` | `true` hides the scrollbar of the active window while the cursor is inside the scrollbar. `"row"` clears only the row of the scrollbar under the cursor. See [Cursor Intersection](visibility.md#cursor-intersection). |
| `hide_if_all_visible` | `false` | Hides the whole scrollbar when the buffer fits in the window. |
| `mouse` | `true` | Makes the float take mouse input and adds the mouse mappings. See [Mouse](mouse.md). |
| `layout` | see Defaults | Columns and layers. See [Layout](#layout). |
| `track.highlight` | `"PmenuSbar"` | Track highlight: a group name or an `nvim_set_hl()` table. |
| `thumb.text` | `" "` | One string with a positive display width and no control characters. |
| `thumb.blend` | `30` | Integer from `0` to `100`. The text below the thumb shows through it with this blend. |
| `thumb.highlight` | `"PmenuThumb"` | A group name or an `nvim_set_hl()` table. |
| `thumb.hide_if_all_visible` | `true` | Hides only the thumb when the buffer fits in the window. |
| `overlap.reserve` | `true` | `true`, `false`, or `"virtual_text"` (experimental). Keeps the text away from an east scrollbar. See [Overlap](#overlap). |
| `overlap.show_through` | `false` | `false`, or a blend from `1` to `100`. The text below the scrollbar shows through the track, the thumb, and the empty cells. |
| `overlap.marks` | `"glyph"` | `"glyph"` draws the text of each mark. `"tint"` draws each mark as a background in the color of the mark. |
| `marks` | `{}` | Overrides of the shared mark types for the scrollbar. See [Marks](#marks). |
| `window` | see Defaults | Border, title, footer, and window options of the float. See [Window](#window). |

`placement.gutter` applies to window-relative floats with a west anchor (`NW`
or `SW`). `"inner"` reserves blank gutter cells for the scrollbar after the
existing gutter. `"outer"` reserves them before the existing gutter.
`"overlap"` reserves no cells.

When the minimap is on the same side as the scrollbar, `minimap.placement.stack`
arranges the two floats. See
[Placement Beside the Scrollbar](minimap/configuration.md#placement-beside-the-scrollbar).

### Window

`window` configures the float itself. Its keys go to `nvim_open_win()`, and
`window.wo` holds window-local options. The default `border = "none"` opens the
float without a border, also when you set `'winborder'`.

```lua
require("scrollbar").setup({
    scrollbar = {
        window = {
            border = "rounded",
            wo = { winhighlight = "FloatBorder:DiagnosticInfo" },
        },
    },
})
```

- `window` accepts each `nvim_open_win()` key that the renderer does not set,
  for example `border`, `title`, `title_pos`, `footer`, and `footer_pos`.
  Neovim validates the values during setup.
- Setup rejects the keys that the renderer sets: `relative`, `win`, `bufpos`,
  `anchor`, `row`, `col`, `width`, `height`, `zindex`, `focusable`, `mouse`,
  `hide`, `style`, `external`, `split`, `vertical`, `noautocmd`, and `fixed`.
  The error names the option that controls the key, for example
  `placement.anchor`.
- `window.wo` accepts window options. They apply after the defaults of the
  renderer, so your values win. Setup rejects `number`, `relativenumber`,
  `signcolumn`, `foldcolumn`, `statuscolumn`, and `wrap`, because they change
  the text area of the float.
- The entries of `wo.winhighlight` add to the mapping of the renderer. An entry
  for a group replaces the entry of the renderer for that group.
- The frame stays inside the text area of the window. The border rows make the
  track shorter, and the border columns make the float wider. See
  [Border](layout-and-geometry.md#border).
- The frame uses `ScrollbarFloatBorder`, `ScrollbarFloatTitle`, and
  `ScrollbarFloatFooter`. See [Frame Groups](highlights.md#frame-groups).
- A profile can set its own `window`. A profile clears a title of the root
  with `title = ""`. When the `window` of a float changes, the float opens
  again.
- To use the border of other floats, set `border = vim.o.winborder`. This works
  when `'winborder'` is a style name, such as `"rounded"`.
- The renderer sets the `'winblend'` of the float, so the float does not get
  the global `'winblend'`. `wo.winblend` makes the whole scrollbar
  see-through. It also sets the blend of the track and the empty cells when
  `overlap.show_through` is `false`.

### Overlap

The scrollbar float covers the last columns of the text area. `overlap`
controls how the scrollbar shares these cells with the text. `reserve` is on
by default, and the other options are off. A profile can set `overlap`.

```lua
require("scrollbar").setup({
    scrollbar = {
        overlap = {
            reserve = true,
            show_through = 60,
            marks = "tint",
        },
    },
})
```

`reserve = true` (the default) keeps the text away from the scrollbar. Set
`reserve = false` to leave the window options alone. The reservation applies
only to a window-relative scrollbar with an east anchor (`NE` or `SE`) on a
normal window. For a west anchor, use `placement.gutter`. The reservation counts the
columns that the float covers, including its border and a negative
`placement.col`. When the scrollbar is beside the minimap and nearer the text,
the reservation also includes the minimap.

- Without `'wrap'`, the plugin sets the window-local `'sidescrolloff'` to the
  number of covered columns. The text scrolls sideways before the cursor gets
  under the scrollbar, so the scrollbar stays visible. A larger
  `'sidescrolloff'` stays. Neovim applies `'sidescrolloff'` on both sides, so
  the left margin also grows when the window is scrolled sideways.
- With `'wrap'`, the plugin sets the window-local `'wrapcolumn'`, so the text
  wraps before the scrollbar. Neovim releases without `'wrapcolumn'` get no
  reservation for `'wrap'`. A smaller `'wrapcolumn'` stays.
- The reservation changes only a value that it set. If you change the option,
  your value becomes the new original value. The plugin restores the original
  value when the scrollbar is hidden, is disposed, becomes ineligible, or the
  reservation ends.
- Autohide also ends the reservation while it conceals the scrollbar. With
  `'wrap'`, the text wraps again at the window edge until the scrollbar shows.

`reserve = "virtual_text"` is experimental. Its behavior can change in a later
release without a deprecation. It changes only a window with `'wrap'` on a
Neovim release without `'wrapcolumn'`. In other windows, and with
`'wrapcolumn'`, it does the same as `reserve = true`.

The plugin inserts blank inline virtual text (a pad) at each wrap point of the
lines that the window shows. The pad fills the rest of the screen row. Thus
the row ends before the scrollbar, and the next character starts the next
row. The scrollbar covers no text.

- The pads are extmarks on the lines that the window can show. The plugin
  updates them before the redraw after a scroll, a resize, a text change, a
  buffer change, a fold command, and a change of an option that changes the
  wrapping.
- Each window has its own pads, because the pad positions depend on the width
  of the window. The plugin uses the experimental `nvim__ns_set()` to show the
  pads of a window only in that window. Without that function, a buffer gets
  pads only while one window shows it.
- The pads count tabs, `'tabstop'`, `'vartabstop'`, wide characters, control
  characters, combining characters, `'list'`, `'showbreak'`, `'breakindent'`
  with the `shift`, `min`, and `sbr` items of `'breakindentopt'`, and
  `'linebreak'` with `'breakat'`.
- A blank space in the covered columns hides no text, so it gets no pad. When
  `'list'` shows spaces, a space gets a pad like other characters.
- With `'linebreak'`, a pad moves a word that does not fit before the
  scrollbar to the next row. Neovim 0.13 counts the pads in a word and in the
  `'breakat'` characters after it as a part of the word. Thus the pad goes
  before the `'breakat'` character in front of the word. A blank cell can then
  show before a `'breakat'` character such as `-`, or the character can start
  the next row with the word.
- The plugin removes the pads in the same cases in which it restores an option.

The pads have these limits:

- The pads do not count concealed text (`'conceallevel'`), other inline
  virtual text such as LSP inlay hints, the `list` and `column` items of
  `'breakindentopt'`, or the `n` flag of `'cpoptions'`. On a line with one of
  these, a row can end too early, or text can be under the scrollbar.
- With `'linebreak'` in Neovim 0.13, a `'breakat'` character such as `-` can
  be under the scrollbar when the word after it is not wider than the
  scrollbar. When a tab is the `'breakat'` character in front of a word, a
  pad can show in the middle of a row.
- The pads are part of the virtual columns. On a wrapped line after a pad,
  `'colorcolumn'`, `'cursorcolumn'`, `virtcol()`, and the `|` command count the
  pad cells.
- With `unit = "screenline"`, the thumb counts the rows that the pads add only
  after the plugin measures the lines again. A scroll does not start a new
  measurement, so the thumb can be off by a few rows.

The pads make Neovim slower, because Neovim measures and draws the inline
virtual text. These times are from a 120x48 window in tmux with Neovim 0.12.6.
The buffer had 10,000 lines of 150 ASCII cells, 1,000 ASCII cells, or 150
bytes of UTF-8 text with tabs.

| Operation | `reserve = true` | `reserve = "virtual_text"` |
| --------- | ---------------- | -------------------------- |
| `:redraw!` | 210 to 270 µs | 300 to 510 µs (+41% to +91%) |
| `<C-d>`, a render, and a redraw | 220 to 340 µs | 530 to 990 µs (+117% to +194%) |
| One typed character and a redraw | 47 to 93 µs | 129 to 301 µs (+85% to +224%) |

`show_through` is a blend from `1` to `100`. The text below the scrollbar shows
through the track and the thumb with this blend, and it shows through the
empty cells with no change. The thumb uses the larger value of `thumb.blend`
and `show_through`. Higher values show more text and less of the scrollbar.
The text shows through only a cell that holds a space, so the text of a mark
or a thumb glyph, such as `"█"`, still covers the text.

`marks = "tint"` draws each mark as spaces with the color of the mark as the
background. With `show_through`, the text shows on top of the color. A tint
has no glyph, so named marks lose their letters. The tint groups are
`Scrollbar<MarkType>Tint`. See [Highlights](highlights.md#blend).

Neovim implements the blend as UI pseudo-transparency. It works best with
`'termguicolors'`. Without it, Neovim approximates the blended colors in the
terminal palette.

For the cursor, see also `hide_on_cursor = "row"` in
[Cursor Intersection](visibility.md#cursor-intersection).

## Providers

`providers` enables the built-in data sources. Each entry is `false`, `true`,
or a table:

```lua
providers = {
    gitsigns = true,                                -- both renderers
    diagnostic = { minimap = false },               -- scrollbar only
    coc = { scrollbar = false },                    -- minimap only
    search = { incsearch = true, minimap = false }, -- options and renderers
    treesitter = false,                             -- no syntax colors in the minimap
}
```

- `false` turns the provider off.
- `true` turns the provider on for every enabled renderer that supports it.
- A table turns the provider on. It holds the provider options and the
  optional `scrollbar` and `minimap` booleans. Both booleans default to
  `true`.
- `{ scrollbar = false, minimap = false }` is the same as `false`.
- A renderer with `enabled = false` requests no providers.

Each provider runs once, even when both renderers use it. A renderer shows only
the output of the providers that target it.

| Provider | Options | Renderers |
| --- | --- | --- |
| `search` | `incsearch` (boolean), `backend` (`"worker"` or `"sync"`, default `"worker"`) | Both |
| `marks` | `letters` (default `true`), `numbers` (default `false`) | Both |
| `treesitter`, `lsp_semantic_tokens` | None | Minimap only. `scrollbar = true` is a setup error. |
| All other built-ins | None | Both |

If you omit `search.incsearch`, the search provider follows `vim.o.incsearch`.
The table contains only the built-in providers. To add a data source, use the
[custom provider API](providers/custom.md). See the
[provider overview](providers/README.md) for each provider.

## Exclude

`exclude.buftypes` and `exclude.filetypes` list the buffers that get no
scrollbar or minimap. Each value is a table keyed by name, or a list:

```lua
exclude = {
    buftypes = {
        terminal = { minimap = false }, -- excluded from the scrollbar only
        quickfix = true,                -- excluded from both renderers
    },
    filetypes = {
        NvimTree = true,                  -- adds to the defaults
        markdown = { scrollbar = false }, -- excluded from the minimap only
        noice = false,                    -- removes a default entry
    },
}
```

- `true` excludes the name from both renderers.
- `false` does not exclude it. Use this to remove a default entry.
- A table excludes the name from every renderer that the table does not set to
  `false`.
- A table keyed by name merges with the defaults.
- A list, such as `filetypes = { "NvimTree" }`, replaces the defaults and
  applies to both renderers. An empty table, `{}`, removes all default
  entries.
- A table that mixes list entries and keyed entries is a setup error.

`exclude.unfocusable` excludes the normal windows that are not focusable.
Plugins open such windows with `focusable = false` as decorations, for example
the line-number and connector panes of a diff view. The default is `true`. The
value takes the same forms as one entry above:

```lua
exclude = {
    unfocusable = false,                -- these windows get both renderers
    -- unfocusable = { minimap = false }, -- excluded from the scrollbar only
}
```

`exclude.unfocusable` applies only to normal windows.

`exclude.when` is `false` or a function. The function gets a table for each
window that the other rules accept, normal or floating. If it returns a truthy
value, the window gets no bar from that renderer:

```lua
{
    renderer = "scrollbar", -- or "minimap"
    winid = source_win,
    bufnr = source_buf,
    filetype = vim.bo[source_buf].filetype,
    buftype = vim.bo[source_buf].buftype,
    bufname = vim.api.nvim_buf_get_name(source_buf),
}
```

This example keeps both renderers off the tabs of diffbandit.nvim:

```lua
exclude = {
    when = function(context)
        local diffbandit = package.loaded.diffbandit
        return diffbandit ~= nil
            and diffbandit.is_running({ tab = vim.api.nvim_win_get_tabpage(context.winid) })
    end,
}
```

- The plugin calls `when` often, also before each render. Keep the function
  fast, free of side effects, and non-blocking.
- Each render calls `when` again. A change of the state that `when` reads
  applies at the next render of the window.
- If `when` raises an error, the window is not excluded. A notification
  appears once for each renderer and distinct error message until the next
  setup, for example
  `[nvim-scrollbar] scrollbar exclude.when matcher failed: <message>`.

Invalid and unloaded buffers are never eligible. Each renderer also excludes
its own floats. A floating window is a source only when the
[`floats`](floats.md) option of the renderer block admits it.
`max_lines` in each renderer block is a separate eligibility limit.

## Marks

The top-level `marks` table defines the mark types. Providers publish marks of
these types, and both renderers use the same definitions:

```lua
marks = {
    Error = { highlight = { fg = "#ff5555" } },                -- changes a default type
    Todo = { text = "T", priority = 4, highlight = "Todo" },   -- adds a new type
    Hint = false,                                              -- hides a type in both renderers
}
```

- A table merges with the default definition of that type. A new type must set
  `text`, `priority`, and `highlight`. Type names match `^[%a_][%w_]*$`.
  The frame groups reserve the names `FloatBorder`, `FloatTitle`, and
  `FloatFooter`. See [Frame Groups](highlights.md#frame-groups).
- `false` hides the type in both renderers. The type stays registered, so
  providers can still publish it. A renderer override table can show it again.
- `text` is a string or a dense list of strings. Each string must have a
  positive display width and no control characters. A list gives density
  variants. Only `Mark.text` can be an empty list. An empty list keeps the
  literal mark names from the built-in marks provider. The minimap does not use
  `text`.
- `priority` is a non-negative integer. In one mark lane, the lower number wins
  a collision. Separate mark layers use their declared stack order instead.
- `highlight` is a non-empty group name or an `nvim_set_hl()` definition table.

Each renderer block has its own `marks` table with overrides for that
renderer:

```lua
scrollbar = {
    marks = {
        Error = { text = "E" }, -- changes the scrollbar only
        GitAdd = false,         -- hides a type in the scrollbar only
    },
}
```

- A table merges with the shared definition. It can set only the fields that
  the renderer uses.
- `false` hides one type. `marks = false` hides all types.
- An override can name only a registered type. To add a type, add it to the
  top-level `marks` table.
- Presets and profiles can set renderer `marks`. In a later layer, a table
  for a type shows that type again, even when an earlier layer set it to
  `false`. A `marks` table after `marks = false` shows all types again.

Ordinary text is clipped to its lane, and multi-cell glyphs are not split. If a
collision leaves room for only part of a multi-cell glyph, the whole glyph is
omitted.

## Events

`scrollbar.events` lists the autocommand events that update the scrollbar.
The value is a table keyed by event name, or a list:

```lua
scrollbar = {
    events = {
        CursorMovedI = false,                  -- removes a default event
        FocusGained = true,                    -- adds an event
        User = { pattern = "GitSignsUpdate" }, -- adds an event with a pattern
    },
}
```

- `true` adds the event. `false` removes it. A table adds the event with the
  `pattern` in the table.
- A table keyed by event name merges with the defaults.
- A list replaces the defaults. Each list entry is an event name, or a table
  with `event` and `pattern`:

  ```lua
  events = { "WinScrolled", "TextChanged", { event = "User", pattern = "GitSignsUpdate" } }
  ```

- Any autocommand event is valid. Event names are not case-sensitive.
- The result must contain at least one event.
- An unknown event name, a duplicate event, and a table that mixes list
  entries and keyed entries are setup errors. To match more than one
  pattern, give `pattern` a list instead of repeating the event.

`pattern` is a string or a list of strings. It is the autocommand pattern, so
it has the same meaning as in `:autocmd`. For example, it matches the file name
for buffer events, the option name for `OptionSet`, and the name for `User`.
Without `pattern`, an event matches everything, except `OptionSet`, which
matches only the options that change the scrollbar layout. A `pattern`
replaces that list of options.

The events in this table have a specific update. Every other event, such as
`FocusGained` or `BufLeave`, renders all windows.

| Event | Update |
| --- | --- |
| `BufEnter`, `BufWinEnter` | Renders the windows that show the buffer. Checks again which windows get a scrollbar. |
| `WinEnter`, `TabEnter`, `TermEnter`, `CmdwinLeave` | Renders all windows. Checks again which windows get a scrollbar. |
| `CursorMoved`, `CursorMovedI` | Renders the current window. |
| `TextChanged`, `TextChangedI`, `TextChangedP`, `TextChangedT` | Renders the windows that show the changed buffer. |
| `WinScrolled` | Renders the scrolled windows. |
| `WinResized` | Renders the resized windows. |
| `VimResized` | Renders all windows. |
| `OptionSet` | Renders all windows when an option that changes the layout changes, such as `number`, `wrap`, or `foldmethod`. |
| `ColorScheme` | Sets the highlight groups again when `set_highlights` is `true`, and renders all windows. |
| `WinClosed`, `BufDelete`, `BufWipeout`, `TabClosed` | Renders all windows. |

With `autohide`, only `CursorMoved`, `CursorMovedI`, and `WinScrolled` reveal a
concealed scrollbar. See [Autohide](visibility.md#autohide).

Providers update their marks on their own events. `events` does not change
when a provider updates.

## Layout

`layout.columns` is a non-empty dense list of logical display columns. Each
column is a non-empty list of layers, from bottom to top:

```lua
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb" },
        { { types = { "Error", "Warn", "Info", "Hint" } }, "marks" },
    },
}
```

The string layers are `"track"`, `"thumb"`, and `"marks"`. A plain `"marks"`
layer is the catch-all for the mark types that no descriptor selects. A
descriptor is a table with these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `types` | dense string list | Required. The mark types of this lane. Unknown names are allowed. |
| `max_width` | positive integer | Total width of a lane that explicitly selects `Mark` |

Adjacent occurrences with the same selector form one lane. A catch-all lane,
an explicitly selected type, and the thumb can each occupy only one contiguous
span. Track layers can appear in any columns. Track, thumb, and marks are all
optional. Cells with no interactive rendered layer are transparent and inert.

`direction = "auto"` reads the declared columns from inner to outer. East
anchors keep the declared order, and west anchors mirror it. `"ltr"` and
`"rtl"` force the physical screen order. See
[Layout and geometry](layout-and-geometry.md).

## Profiles

`profiles` is an ordered list of window-specific variants. Each profile has a
required `match` and any appearance options, including `preset`:

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
                match = { buftypes = { "quickfix" } },
                preset = "search",
            },
            {
                match = {
                    filetypes = { "lua" },
                    when = function(context)
                        return vim.b[context.bufnr].scrollbar_review == true
                    end,
                },
                preset = "review",
                thumb = { blend = 10 },
                mouse = false,
            },
        },
    },
})
```

In this image, `zed` is the root preset, the Lua split uses `review`, and the
Markdown split uses `minimal`. The Makefile split matches no profile, so it
uses `zed`:

![Three splits with the review, minimal, and zed presets selected by filetype profiles](https://github.com/user-attachments/assets/90ffcc9a-f6f3-45de-859a-cf385079953c)

`match` must contain at least one matcher:

- `filetypes`: non-empty dense string list.
- `buftypes`: non-empty dense string list.
- `when`: predicate function.
- `floats`: `true`, or a non-empty dense list of float kinds. See
  [Floats](floats.md#profiles).

A profile with `floats` matches only float sources. A profile without `floats`
matches only normal windows.

A profile matches only when all of its matchers match. The `filetypes` and
`buftypes` matchers run before `when`. If one of them fails, the `when`
callback does not run. Profiles are tested in declaration order. The first
match wins, and profiles never merge with each other. If no profile matches,
the root options apply.

`when` receives this table:

```lua
{
    winid = source_win,
    bufnr = source_buf,
    filetype = vim.bo[source_buf].filetype,
    buftype = vim.bo[source_buf].buftype,
    bufname = vim.api.nvim_buf_get_name(source_buf),
}
```

Profile selection is not cached. The predicates run again each time a
selection is necessary, including before every render. Keep them fast, free of
side effects, and non-blocking.

If a callback raises an error, that render uses the root options. A
notification appears once for each distinct pair of profile index and error
message. Later calls continue to evaluate the callback, so the profile recovers
without another setup.

A profile accepts only appearance options. A global option in a profile is a
setup error.

To reuse options in several profiles, use a Lua table:

```lua
local focused = { preset = "intellij", thumb = { blend = 15 } }

scrollbar = {
    profiles = {
        vim.tbl_extend("force", { match = { filetypes = { "lua" } } }, focused),
        vim.tbl_extend("force", { match = { filetypes = { "python" } } }, focused),
    },
}
```

## Precedence

Setup resolves the root and each profile once. Later layers win:

1. The plugin defaults.
2. The root `preset`.
3. The root options.
4. The profile `preset`.
5. The profile options.

A profile preset wins over the root options. For example, if the root sets
`layout` and a profile sets `preset = "minimal"`, that profile uses the
`minimal` layout. Root values that the profile preset does not set stay in
effect.

Tables merge key by key. Dense lists replace the earlier value. This applies to
`layout.columns`, descriptor `types`, and mark `text`. Renderer `marks`
overrides apply on top of the shared `marks` definitions.

## Validation

- `visibility`: `"all"` or `"active"`.
- `floats`: `false`, `true`, or a table with the keys `snacks`, `telescope`,
  and `when`. `snacks` and `telescope` are booleans or tables of booleans.
  `when` is a function. See [Floats](floats.md).
- `match.floats`: `true`, or a dense list of `"snacks_list"`,
  `"snacks_preview"`, `"telescope_results"`, `"telescope_preview"`, and
  `"custom"`.
- `unit`: `"line"` or `"screenline"`.
- `placement.relative`: `"window"` or `"editor"`.
- `placement.anchor`: `"NW"`, `"NE"`, `"SW"`, or `"SE"`.
- `placement.gutter`: `"inner"`, `"outer"`, or `"overlap"`.
- `placement.row` and `placement.col`: signed integers.
- `placement.zindex`, `autohide.delay_ms`, descriptor `max_width`, and a
  numeric `max_lines`: positive integers.
- `throttle_ms` and mark priorities: non-negative integers.
- `events`: a list or a table keyed by autocommand event name. See
  [Events](#events).
- `thumb.blend`: an integer from `0` to `100`.
- `thumb.text`: one string with a positive display width and no control
  characters.
- `window`: Neovim validates the keys and the window options during setup.
  For this check, setup opens a hidden float and closes it at once. The default
  `window` opens no float. See [Window](#window).
- Unknown keys at every level are errors.

Error messages give the full path of the option, for example
`scrollbar.profiles[2].thumb.blend must be an integer between 0 and 100`. A
removed v1 option also names its replacement, for example
`unknown option 'scrollbar.update' (use 'throttle_ms' and 'events')`.

## Related

- [Presets](presets.md)
- [Minimap configuration](minimap/configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Visibility](visibility.md)
- [Floats](floats.md)
- [Providers](providers/README.md)
- [Highlights](highlights.md)
- [Migration](migration.md)
