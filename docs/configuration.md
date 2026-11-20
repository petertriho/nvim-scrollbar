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

    -- Floats of label mode, hover, and the glance window
    peek = {},
    glance = {},
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
        qflist = false,
        loclist = false,
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
        Qflist = { text = { "-", "=" }, priority = 6, highlight = "QuickFixLine" },
        Loclist = { text = { "-", "=" }, priority = 6, highlight = "QuickFixLine" },
    },
    scrollbar = {
        -- Global options
        enabled = true,
        show = true,
        visibility = "all", -- "all" or "active"
        autohide = false, -- true, or { delay_ms = 1000 }
        max_lines = false,
        floats = false, -- true, or a table, see Floats
        jump = { -- see Jump and Glance
            labels = "asdfghjklqwertyuiopzxcvbnm",
            offset = 0,
        },
        hover = false, -- true, or { delay_ms = 300 }
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
        track = {
            highlight = "PmenuSbar",
            inactive_highlight = nil, -- see Inactive Windows
        },
        thumb = {
            text = " ",
            blend = 30,
            highlight = "PmenuThumb",
            inactive_highlight = nil,
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
    peek = { -- see Jump and Glance
        position = "scrollbar", -- "scrollbar", "cursor", or "center"
        context = 5,
        width = 0.6,
        window = {},
    },
    glance = { -- see Jump and Glance
        list = "line", -- "line", "mark", or "type"
        height = 18,
        keys = {
            jump = "<CR>",
            close = { "q", "<Esc>" },
            preview = "<Tab>",
        },
        window = {},
    },
})
```

## Scrollbar Options

### Global Options

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | When `false`, the scrollbar requests no providers, shows no floats, and creates no `:Scrollbar*` commands except `:ScrollbarGlance`. Use this for a minimap-only setup. |
| `show` | `true` | Initial master visibility. `false` starts hidden. `:ScrollbarShow` shows the scrollbar. |
| `visibility` | `"all"` | `"all"` shows a scrollbar in every eligible window. `"active"` shows only the scrollbar of the active window. |
| `autohide` | `false` | `true` conceals each scrollbar after 1000 ms without activity in its window. `{ delay_ms = n }` sets the delay. |
| `max_lines` | `false` | A buffer with more lines than this number gets no scrollbar. |
| `floats` | `false` | Floats that get a scrollbar. The built-in kinds are the list and the preview of the snacks.nvim picker, and the results and the preview of the Telescope picker. A `when` function selects other floats. See [Floats](floats.md). |
| `jump.labels` | `"asdfghjklqwertyuiopzxcvbnm"` | Labels of label mode. See [Jump and Glance](jump-and-glance.md#labels). |
| `jump.offset` | `0` | Columns from each mark cell to its label. `0` puts the label on the mark cell. See [Jump and Glance](jump-and-glance.md#labels). |
| `hover` | `false` | `true` opens the peek float when the pointer stays on a mark cell for 300 ms. `{ delay_ms = n }` sets the delay. See [Hover](jump-and-glance.md#hover). |
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
| `hide_if_all_visible` | `false` | Hides the whole scrollbar when the window shows the whole buffer. See [Documents That Fit](visibility.md#documents-that-fit). |
| `mouse` | `true` | Makes the float take mouse input and adds the mouse mappings. See [Mouse](mouse.md). |
| `layout` | see Defaults | Columns and layers. See [Layout](#layout). |
| `track.highlight` | `"PmenuSbar"` | Track highlight: a group name or an `nvim_set_hl()` table. |
| `track.inactive_highlight` | `nil` | Track highlight of an inactive source window. See [Inactive Windows](highlights.md#inactive-windows). |
| `thumb.text` | `" "` | One string with a positive display width and no control characters, or a function. See [Text Functions](#text-functions). |
| `thumb.blend` | `30` | Integer from `0` to `100`. The text below the thumb shows through it with this blend. |
| `thumb.highlight` | `"PmenuThumb"` | A group name or an `nvim_set_hl()` table. |
| `thumb.inactive_highlight` | `nil` | Thumb highlight of an inactive source window. See [Inactive Windows](highlights.md#inactive-windows). |
| `thumb.hide_if_all_visible` | `true` | Hides only the thumb when the window shows the whole buffer. |
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
  show before a `'breakat'` character such as `-`. When the pad would move
  that character under the scrollbar, the character, or the word in front of
  it, also moves to the next row.
- The plugin removes the pads in the same cases in which it restores an option.

The pads have these limits:

- The pads do not count concealed text (`'conceallevel'`), other inline
  virtual text such as LSP inlay hints, the `list` and `column` items of
  `'breakindentopt'`, or the `n` flag of `'cpoptions'`. On a line with one of
  these, a row can end too early, or text can be under the scrollbar.
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
| `qflist`, `loclist` | `types` (default `{}`), see [Entry types](providers/qflist.md#entry-types) | Both |
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
- `text` is a string, a dense list of strings, or a function. Each string
  must have a positive display width and no control characters. A list gives
  density variants. A scrollbar row with n marks of one type, from all
  providers, uses entry n. A row with more marks than entries uses the last
  entry. For example, `{ "-", "=", "≡" }` shows `-` for one mark, `=` for two
  marks, and `≡` for three or more marks. Only `Mark.text` can be an empty
  list. An empty list keeps the literal mark names from the built-in marks
  provider. A function returns the text, for example a line number. See
  [Text Functions](#text-functions). The minimap does not use `text`.
- `priority` is a non-negative integer. In one mark lane, the lower number wins
  a collision. Separate mark layers use their declared stack order instead.
- `highlight` is a non-empty group name or an `nvim_set_hl()` definition table.
- `highlight_channel` is `"fg"` (the default) or `"bg"`. It selects the color
  of a `highlight` group name that the mark shows. If the group has no color
  for that channel, the mark uses the other channel. A table `highlight`
  ignores it. See [Highlights](highlights.md#sources).

  ```lua
  marks = {
      Search = { highlight_channel = "bg" }, -- the background of Search
  }
  ```

- `inactive_highlight` is the highlight of the mark in an inactive source
  window. It takes the same values as `highlight`. It has no default, so the
  mark keeps `highlight`.
- `inactive_highlight_channel` is `"fg"` or `"bg"`. It selects the channel of
  an `inactive_highlight` group name. Without it, the mark uses the channel
  of `highlight_channel`. See [Inactive Windows](highlights.md#inactive-windows).

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

## Text Functions

The `text` of a mark type and `scrollbar.thumb.text` can be a function. The
function gets a context table and returns the text as a string. Use it, for
example, to show line numbers beside the marks or in the thumb. The
[recipes](#recipes) are ready-made functions for the common cases.

### Recipes

`require("scrollbar.recipes")` has ready-made text functions. Each recipe
makes a text function. Call it, with an optional options table:

```lua
local recipes = require("scrollbar.recipes")

require("scrollbar").setup({
    marks = {
        GitAdd = { text = recipes.marks.line_number() },
    },
})
```

The recipes for the marks:

| Recipe | Shows | Example |
| --- | --- | --- |
| `recipes.marks.line_number()` | The line of the mark. A click on the mark goes to this line. | `153` |
| `recipes.marks.relative_number()` | The number of lines between the cursor line and the line of the mark. | `12` |
| `recipes.marks.count()` | The number of marks of the type in the row. A number with more digits than `width` shows `+`. | `3`, `+` |
| `recipes.marks.label()` | The text of the mark from its provider and the line, for example the name of a named mark. Without provider text, only the line. | `a:42`, `42` |

The recipes for the thumb:

| Recipe | Shows | Example |
| --- | --- | --- |
| `recipes.thumb.top_line()` | The first line that the window shows, on the first thumb row. | `41` |
| `recipes.thumb.range()` | The first visible line on the first thumb row, and the last visible line on the last thumb row. | `41`, `78` |
| `recipes.thumb.percent()` | The position of the view as Vim's `'ruler'` shows it, on the first thumb row: `Top`, `Bot`, `All`, or the percentage of the lines above the view. | `45%` |

Each recipe takes these options:

- `width`: pads the text with spaces to this many cells. A wider text does not
  change. For `count`, `width` is also the limit, and its default is `1`.
- `align`: `"right"` (the default) or `"left"`. It sets the side of the text
  when `width` pads it.

For example, `recipes.marks.line_number({ width = 4 })` puts three spaces
before `7` and one space before `153`. The spaces are a part of the mark, so a
click on them also goes to the line.

Call each recipe with `()`. `text = recipes.marks.line_number`, without the
call, shows no text, and an error message names the missing call.

`relative_number` is the only mark recipe that reads the cursor line. The
scrollbar builds its marks again on each change of the cursor line. The other
recipes add no work when the cursor moves.

`relative_number` counts each line, also the lines of a closed fold. Vim's
`j` with a count and `'relativenumber'` count a closed fold as one line. Thus
`12j` can stop before the mark when a closed fold is between the cursor and
the mark. A click on the mark always goes to its line.

### Line Numbers Beside the Marks

This configuration shows the line number of each Git mark in a lane of four
columns, inward of the track. The numbers are right-aligned, so that they are
beside the track:

```lua
local line_number = require("scrollbar.recipes").marks.line_number({ width = 4 })

require("scrollbar").setup({
    providers = { gitsigns = true },
    marks = {
        GitAdd = { text = line_number },
        GitChange = { text = line_number },
        GitDelete = { text = line_number },
    },
    scrollbar = {
        layout = {
            columns = {
                { { types = { "GitAdd", "GitChange", "GitDelete" } } },
                { { types = { "GitAdd", "GitChange", "GitDelete" } } },
                { { types = { "GitAdd", "GitChange", "GitDelete" } } },
                { { types = { "GitAdd", "GitChange", "GitDelete" } } },
                { "track", "thumb", "marks" },
            },
        },
    },
})
```

A click on a number moves the cursor to that line. See [Mouse](mouse.md).

For relative line numbers, use `relative_number`:

```lua
local recipes = require("scrollbar.recipes")
local relative_number = recipes.marks.relative_number({ width = 4 })
```

With a west anchor, the lane is on the right side of the track. Use
`align = "left"` there to keep the numbers beside the track.

### Mark Text Functions

The scrollbar calls a mark text function once for each group of marks of one
type in one row. The function replaces the density variants. Use `ctx.count`
to change the text for dense rows. For example, this function shows the same
text as `recipes.marks.line_number({ width = 4 })`:

```lua
local function line_number(ctx)
    return string.format("%4d", ctx.line + 1)
end
```

The context has these fields. Lines and rows are zero-based.

| Field | Meaning |
| --- | --- |
| `winid` | The source window. |
| `bufnr` | The source buffer. |
| `type` | The mark type. |
| `line` | The line that a click on the mark goes to. |
| `lines` | The lines of all marks of the group, in ascending order. A copy. |
| `count` | The number of marks of the group. |
| `text` | The text of the mark from its provider, for example the name of a named mark, or `nil`. |
| `row` | The scrollbar row. |
| `line_count` | The number of lines of the source buffer. |
| `cursor_line` | The cursor line of the source window. |

- The scrollbar calls the function only when it builds the marks again: when
  the marks, their rows, the layout, or the window size change. A function
  that reads `ctx.cursor_line` or `ctx.line_count` makes the scrollbar build
  the marks again when that value changes. Make the result depend only on the
  context. A function that reads other state, for example `vim.fn.line(".")`,
  shows old text.
- `lines`, `line_count`, and `cursor_line` are read on demand. Thus
  `vim.inspect(ctx)` shows them only after the function reads them.
- The function wins over the text from the provider. To keep a provider text,
  return `ctx.text`. For example, `ctx.text .. ":" .. (ctx.line + 1)` shows
  `a:42` for a named mark.
- In an expanded named-mark lane, each named mark is its own group:
  `count` is `1`, and `lines` holds only `line`. The lane grows by the width of
  the texts. A named mark that does not fit, and the marks after it, are
  omitted. See [Named-Mark Lanes](layout-and-geometry.md#named-mark-lanes).

### Thumb Text Functions

The scrollbar calls a thumb text function on every render, once for each thumb
row. The result shows once, from the first thumb column. The other thumb cells
stay blank. A string `thumb.text` repeats across the thumb as before. This
example shows the top line in the first thumb row of a thumb of four columns,
with the `top_line` recipe. The marks are in their own column, so that no mark
covers the number:

```lua
require("scrollbar").setup({
    scrollbar = {
        layout = {
            columns = {
                { "track", "thumb" },
                { "track", "thumb" },
                { "track", "thumb" },
                { "track", "thumb" },
                { "track", "marks" },
            },
        },
        thumb = {
            text = require("scrollbar.recipes").thumb.top_line(),
        },
    },
})
```

The recipe does the same as this function:

```lua
local function top_line(ctx)
    if ctx.index == 0 then
        return tostring(ctx.top_line + 1)
    end
end
```

The context has these fields. Lines and rows are zero-based.

| Field | Meaning |
| --- | --- |
| `winid` | The source window. |
| `bufnr` | The source buffer. |
| `index` | The row in the thumb. The first thumb row is `0`. |
| `row` | The scrollbar row. |
| `first_row` and `last_row` | The first and the last thumb row. |
| `height` | The number of scrollbar rows. |
| `top_line` and `bottom_line` | The first and the last line that the window shows. |
| `line_count` | The number of lines of the source buffer. |
| `cursor_line` | The cursor line of the source window. |

On the list of a snacks.nvim picker, `top_line`, `bottom_line`, and
`line_count` count list items, and `cursor_line` is `nil`.

Keep a thumb text function fast, because it runs on every render.

### Results and Errors

- A result must be a string with no control characters. `nil` and `""` show
  no text: a mark group is hidden, and a thumb row stays blank.
- A function that raises an error, or returns another value, shows no text.
  The plugin shows one error message for each function and message.
- The text fills the cells of its lane, or of the thumb, from the first
  column. The edge of the lane cuts a longer text. The default layout has one
  column, so a line number needs a wider lane. See [Layout](#layout).
- With `overlap.marks = "tint"`, the tint covers the cells of the whole text.

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

![Three splits with the review, minimal, and zed presets selected by filetype profiles](https://github.com/user-attachments/assets/6e6ab82f-d3d9-464d-954c-cd756148b396)

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
    renderer = "scrollbar", -- "minimap" in a minimap profile
}
```

Profile selection is not cached. The predicates run again each time a
selection is necessary, including before every render. Keep them fast, free of
side effects, and non-blocking. The [predicate recipes](#predicate-recipes)
are ready-made predicates, for example for the search state.

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

### Predicate Recipes

`require("scrollbar.recipes").when` has ready-made predicates for
`match.when`. They also work in `floats.when` and `exclude.when`, and in the
minimap profiles. As with the [text recipes](#recipes), call each recipe to
get its predicate:

```lua
local when = require("scrollbar.recipes").when

require("scrollbar").setup({
    scrollbar = {
        profiles = {
            {
                match = { when = when.searching() },
                layout = {
                    columns = { { "track", "thumb", { types = { "Search" } } } },
                },
            },
            {
                match = { when = when.negate(when.active()) },
                layout = { columns = { { "track", "thumb" } } },
            },
        },
    },
})
```

The first profile shows only the search marks while a search is visible. The
second profile shows no marks in the windows without focus.

| Recipe | Matches | The window renders again on |
| --- | --- | --- |
| `when.searching()` | A visible accepted search, or an open `/` or `?` command line. `when.searching({ cmdline = false })` ignores the command line. | An update of the `search` provider. See [Search-Only Layout](providers/search.md#search-only-layout). |
| `when.diff()` | A window with `'diff'` set. | The `OptionSet` event of `diff`, for example after `:diffthis` or `:diffoff`. |
| `when.line_count({ min = 1000, max = 50000 })` | A buffer with at least `min` lines and at most `max` lines. Set one bound or both. | A text change. |
| `when.active()` | The active windows of the renderer, by the rule of `visibility = "active"`: the current window, the source window of a focused scrollbar or minimap, and the windows of a focused picker. | `WinEnter` and `TabEnter`. |
| `when.filetypes({ "lazy", "mason" })` | A buffer with one of the filetypes. Use it in `floats.when`, which has no `filetypes` key. | The next render of the window. |
| `when.any(a, b, ...)` | The windows that one of the predicates matches. | The events of its predicates. |
| `when.all(a, b, ...)` | The windows that each predicate matches. | The events of its predicates. |
| `when.negate(a)` | The windows that the predicate does not match. | The events of its predicate. |

- A predicate reads its state when a window renders. The last column says
  which event renders the window when that state changes. Another render, for
  example after a cursor move, also applies the change.
- `when.active()` uses `renderer` of the context. In a minimap profile, it
  follows the active rule of the minimap. Do not use it in `floats.when`. The
  active rule checks the floats, so `when.active()` returns `false` there.
- `when.searching()` uses the visibility rule of the
  [search provider](providers/search.md#visibility-requirements). Without the
  `search` provider, a layout change after `:nohlsearch` waits for the next
  render.
- A predicate factory rejects invalid arguments when you call it, for example
  `when.line_count({})`. A factory without its call, such as
  `when = when.diff`, matches nothing and shows an error message that names
  the missing call.

## Peek and Glance

The top-level `peek` block configures the peek float of label mode and hover.
The top-level `glance` block configures the glance window. Both blocks are
global, so profiles do not change them. See
[Jump and Glance](jump-and-glance.md#options) for each option.

```lua
require("scrollbar").setup({
    scrollbar = {
        hover = true,
    },
    peek = {
        position = "cursor",
        window = { border = "rounded" },
    },
    glance = {
        list = "type",
        keys = { close = "q" },
    },
})
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
  characters, or a function.
- Mark `text`: a string, a dense list of strings, or a function. A list
  cannot hold a function.
- `window`: Neovim validates the keys and the window options during setup.
  For this check, setup opens a hidden float and closes it at once. The default
  `window` opens no float. See [Window](#window).
- `scrollbar.jump`, `scrollbar.hover`, `peek`, and `glance`: see
  [Jump and Glance](jump-and-glance.md#options).
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
- [Jump and Glance](jump-and-glance.md)
- [Providers](providers/README.md)
- [Highlights](highlights.md)
- [Migration](migration.md)
