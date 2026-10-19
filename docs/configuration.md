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
            "TelescopePrompt",
        },
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
        throttle_ms = 16,

        -- Appearance options
        preset = nil,
        unit = "line", -- "line" or "screenline"
        placement = {
            relative = "window", -- "window" or "editor"
            anchor = "NE", -- "NW", "NE", "SW", or "SE"
            row = 0,
            col = 0,
            gutter = "inner", -- "inner", "outer", or "overlap"
            zindex = 50,
        },
        hide_on_cursor = true,
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
        marks = {}, -- overrides of the shared mark types

        profiles = nil,
    },
})
```

## Scrollbar Options

### Global Options

| Option | Default | Meaning |
| --- | --- | --- |
| `enabled` | `true` | When `false`, the scrollbar requests no providers, shows no floats, and creates no `:Scrollbar*` commands. Use this for a minimap-only setup. |
| `show` | `true` | Initial master visibility. `false` starts hidden. `:ScrollbarShow` shows it. |
| `visibility` | `"all"` | `"all"` shows a scrollbar in every eligible window. `"active"` shows only the scrollbar of the active window. |
| `autohide` | `false` | `true` hides each scrollbar after 1000 ms without activity in its window. `{ delay_ms = n }` sets the delay. |
| `max_lines` | `false` | A buffer with more lines than this number gets no scrollbar. |
| `throttle_ms` | `16` | Renders that are queued within this interval combine into one frame. `0` renders as fast as possible. |

[Visibility](visibility.md) documents `show`, `visibility`, and `autohide`.

### Appearance Options

| Option | Default | Meaning |
| --- | --- | --- |
| `preset` | `nil` | Name of a [built-in preset](presets.md#built-ins). |
| `unit` | `"line"` | `"line"` counts buffer lines. `"screenline"` counts screen lines, so it accounts for wrapped lines and closed folds. See [Units](layout-and-geometry.md#units). |
| `placement` | see Defaults | Position of the float. See [Layout and geometry](layout-and-geometry.md). |
| `hide_on_cursor` | `true` | Hides the scrollbar of the active window while the cursor is inside it. |
| `hide_if_all_visible` | `false` | Hides the whole scrollbar when the buffer fits in the window. |
| `mouse` | `true` | Makes the float focusable and adds the mouse mappings. See [Mouse](mouse.md). |
| `layout` | see Defaults | Columns and layers. See [Layout](#layout). |
| `track.highlight` | `"PmenuSbar"` | Track highlight: a group name or an `nvim_set_hl()` table. |
| `thumb.text` | `" "` | One string with a positive display width and no control characters. |
| `thumb.blend` | `30` | Integer from `0` to `100`. |
| `thumb.highlight` | `"PmenuThumb"` | A group name or an `nvim_set_hl()` table. |
| `thumb.hide_if_all_visible` | `true` | Hides only the thumb when the buffer fits in the window. |
| `marks` | `{}` | Overrides of the shared mark types for the scrollbar. See [Marks](#marks). |

`placement.gutter` applies to window-relative floats with a west anchor (`NW`
or `SW`). `"inner"` and `"outer"` reserve blank gutter cells for the
scrollbar, after or before the existing gutter. `"overlap"` reserves no cells.

When the minimap is on the same side as the scrollbar, `minimap.placement.stack`
arranges the two floats. See
[Placement Beside the Scrollbar](minimap/configuration.md#placement-beside-the-scrollbar).

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

Invalid and unloaded buffers are never eligible. Each renderer also excludes
its own floats, and floating windows never get a scrollbar or a minimap.
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
collision would show only part of a multi-cell glyph, the whole glyph is
omitted.

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
- `unit`: `"line"` or `"screenline"`.
- `placement.relative`: `"window"` or `"editor"`.
- `placement.anchor`: `"NW"`, `"NE"`, `"SW"`, or `"SE"`.
- `placement.gutter`: `"inner"`, `"outer"`, or `"overlap"`.
- `placement.row` and `placement.col`: signed integers.
- `placement.zindex`, `autohide.delay_ms`, descriptor `max_width`, and a
  numeric `max_lines`: positive integers.
- `throttle_ms` and mark priorities: non-negative integers.
- `thumb.blend`: an integer from `0` to `100`.
- `thumb.text`: one string with a positive display width and no control
  characters.
- Unknown keys at every level are errors.

Error messages give the full path of the option, for example
`scrollbar.profiles[2].thumb.blend must be an integer between 0 and 100`. A
removed v1 option also names its replacement, for example
`unknown option 'scrollbar.update' (use 'throttle_ms'. The update events are fixed)`.

## Related

- [Presets](presets.md)
- [Minimap configuration](minimap/configuration.md)
- [Layout and geometry](layout-and-geometry.md)
- [Visibility](visibility.md)
- [Providers](providers/README.md)
- [Highlights](highlights.md)
- [Migration](migration.md)
