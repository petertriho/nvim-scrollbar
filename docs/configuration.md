# Configuration

`require("scrollbar").setup()` validates unknown keys, scalar types, enums,
dense lists, layout spans, and presentation values. Every call starts from fresh
defaults. It does not merge with a previous setup call.

The top-level configuration has two blocks: `scrollbar` and `minimap`. All
scrollbar options go in the `scrollbar` block. The `minimap` block is optional,
is disabled by default, and has separate documentation.

```lua
require("scrollbar").setup({
    scrollbar = {
        -- ...all scrollbar options...
    },
    minimap = {
        enabled = false, -- full schema documented with the minimap subsystem
    },
})
```

Setup rejects unknown top-level keys. Pass every scrollbar option inside the
`scrollbar` block, even if you leave `minimap` at its default.

## Defaults

```lua
require("scrollbar").setup({
    scrollbar = {
        preset = nil,
        presets = nil,
        profiles = nil,
        show = true,
        visibility = "all", -- "all" or "active"
        set_highlights = true,
        max_lines = false,
        hide_if_all_visible = false,
        autohide = { enabled = false, delay_ms = 1000 },
        update = {
            interval_ms = 16,
            events = {
                "BufEnter", "BufWinEnter", "WinEnter", "TabEnter", "TermEnter", "CmdwinLeave",
                "CursorMoved", "CursorMovedI", "TextChanged", "TextChangedI", "TextChangedP",
                "TextChangedT", "WinScrolled", "WinResized", "VimResized", "OptionSet",
                "ColorScheme", "WinClosed", "BufDelete", "BufWipeout", "TabClosed",
            },
        },
        render = { geometry = "line" },
        float = {
            zindex = 50,
            hide_on_cursor = true,
            placement = {
                relative = "window", -- "window" or "editor"
                anchor = "NE", -- "NW", "NE", "SW", or "SE"
                row = 0,
                col = 0,
                gutter = "avoid", -- "avoid" or "overlap"
                gutter_position = "inner", -- "inner" or "outer"
            },
        },
        layout = {
            direction = "auto", -- "auto", "ltr", or "rtl"
            columns = {
                { "track", "thumb", "marks" },
            },
        },
        track = { highlight = "PmenuSbar" },
        mouse = { enabled = true },
        thumb = {
            text = " ",
            blend = 30,
            highlight = "PmenuThumb",
            hide_if_all_visible = true,
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
        },
        excluded_buftypes = { "terminal" },
        excluded_filetypes = {
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
})
```

`search = true` normalizes to `{ backend = "worker" }`. If you omit
`providers.search.incsearch`, the search provider follows the current
`vim.o.incsearch` value. `marks = true` normalizes to
`{ letters = true, numbers = false }`.

The minimap has its own provider defaults:

```lua
minimap = {
    enabled = false,
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
        treesitter = false,
        lsp_semantic_tokens = false,
    },
}
```

When `minimap.enabled = false`, setup still validates these values. They do not
enable providers and do not conflict with the scrollbar provider options.

## Layout

`layout.columns` is a non-empty dense list of logical display columns. Each
column is a non-empty list of layers, from bottom to top:

```lua
layout = {
    direction = "auto",
    columns = {
        { "track", "thumb" },
        {
            { kind = "marks", types = { "Error", "Warn", "Info", "Hint" } },
            "marks",
        },
    },
}
```

The string layers are `"track"`, `"thumb"`, and `"marks"`. A plain `"marks"`
layer is the catch-all for the mark types that no explicit descriptor selects.
A descriptor has these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | `"marks"` | Required tag |
| `types` | dense string list | Explicit mark types. Unknown names are allowed. |
| `max_width` | positive integer | Total width of a lane that explicitly selects `Mark` |

Adjacent occurrences with the same selector form one lane. A catch-all lane,
an explicitly selected type, and the thumb can each occupy only one contiguous
span. Track layers can appear in any columns. Track, thumb, and marks are all
optional. Cells with no interactive rendered layer are transparent and inert.

`direction = "auto"` reads the declared columns from inner to outer. East
anchors keep the declared order, and west anchors mirror it. `"ltr"` and
`"rtl"` force the physical screen order. See
[Layout and geometry](layout-and-geometry.md).

## Marks

Each `marks.<Type>` accepts only `text`, `priority`, and `highlight`. New custom
types must provide all three. Type names match `^[%a_][%w_]*$`.

- `text` is a string or a dense list of strings. Each string must have a
  positive display width and no control characters. A list gives density
  variants. Only `marks.Mark.text` can be an empty list. An empty list keeps
  the literal mark names from the built-in marks provider.
- `priority` is a non-negative integer. In one mark lane, the lower number wins
  a collision. Separate mark layers use their declared stack order instead.
- `highlight` is a non-empty group name or an `nvim_set_hl()` definition table.

Ordinary text is clipped to its lane, and multi-cell glyphs are not split. If a
collision would show only part of a multi-cell glyph, the whole glyph is
omitted.

## Providers

`scrollbar.providers` is a strict allow-list of built-ins. It contains only
`cursor`, `diagnostic`, `search`, `marks`, `gitsigns`, `mini_diff`, `signify`,
`vgit`, `ale`, and `coc`. `minimap.providers` accepts those names plus
`treesitter` and `lsp_semantic_tokens`. Unknown keys in either block are setup
errors. You register custom providers through the
[custom provider API](providers/custom.md), not in either configuration table.

`search` is a boolean, or a table that contains only `incsearch` (boolean) and
`backend` (`"worker"` or `"sync"`). `marks` is a boolean, or a table that
contains only the booleans `letters` and `numbers`. Every other built-in option
is a boolean. The layout controls the presentation width, not the provider.

A built-in provider runs once when the scrollbar, the minimap, or both enable
it. Each renderer shows only the output of the providers that it enables. The
`search` and `marks` options are shared between the two blocks:

- If one block has a table and the other has `true`, the provider uses the
  table.
- If both blocks have tables, setup accepts them when their normalized values
  are equal.
- If the normalized tables conflict, setup fails. The previous configuration
  stays active.

Treesitter and LSP semantic tokens are minimap-only built-ins. See
[Treesitter](providers/treesitter.md) and
[LSP semantic tokens](providers/lsp_semantic_tokens.md).

## Update Cadence

`update` controls which events update the scrollbar and how often it renders.

- `interval_ms` (default `16`) combines the renders that are queued within this
  interval into one frame. This includes the renders that provider updates
  queue.
- `events` (default: the full set in [Defaults](#defaults)) is a dense list of
  Neovim autocmd event names. Only the listed events update the scrollbar for
  geometry, cursor activity, and window or buffer lifecycle changes. Provider
  updates do not depend on this list. A provider update renders the scrollbar
  even when the event that caused it is not in `update.events`. The closed
  allow-list is:

  `BufEnter`, `BufWinEnter`, `WinEnter`, `TabEnter`, `TermEnter`, `CmdwinLeave`,
  `CursorMoved`, `CursorMovedI`, `TextChanged`, `TextChangedI`, `TextChangedP`,
  `TextChangedT`, `WinScrolled`, `WinResized`, `VimResized`, `OptionSet`,
  `ColorScheme`, `WinClosed`, `BufDelete`, `BufWipeout`, `TabClosed`.

  Unknown event names and duplicates are setup errors.

## Validation

- `visibility`: `"all"` or `"active"`.
- `render.geometry`: `"line"` or `"screen"`.
- `update.interval_ms`, `thumb.blend`, and mark priorities: non-negative
  integers. `thumb.blend` is at most `100`.
- `autohide.delay_ms`, `float.zindex`, layout `max_width`, and a numeric
  `max_lines`: positive integers.
- `float.placement.relative`: `"window"` or `"editor"`.
- `float.placement.anchor`: `"NW"`, `"NE"`, `"SW"`, or `"SE"`.
- `float.placement.gutter`: `"avoid"` or `"overlap"`.
- `float.placement.gutter_position`: `"inner"` or `"outer"`.
- `float.placement.row` and `col`: signed integers.
- `thumb.text`: one positive-display-width string without control characters.
- Exclusion options: dense string lists.
- Unknown keys at every schema level are errors.

Dense lists replace atomically. They do not merge by index. This rule applies
to `layout.columns`, descriptor `types`, mark `text`, and exclusion lists.

## Presets

`preset` and `presets` apply only to the setup call that contains them. The
built-in presets are `vscode`, `zed`, `intellij`, `minimal`, `review`,
`search`, `navigate`, `gvim`, `eclipse`, `sublime`, `emacs`, and `xcode`.

A preset definition can set only `layout`, `track`, `thumb`, `marks`, and
`float.placement`, plus one optional `extends` parent. Root setup values win over
the selected preset. See [Presets](presets.md).

## Contextual Profiles

`profiles` is a setup-local dense ordered list. Each entry has a required
`match`, an optional `preset`, and an optional render-safe `config`:

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
                config = {
                    thumb = { blend = 10 },
                    mouse = { enabled = false },
                },
            },
        },
    },
})
```

`match` must contain at least one matcher:

- `filetypes`: non-empty dense string list.
- `buftypes`: non-empty dense string list.
- `when`: predicate function.

A profile matches only when all of its supplied matchers match. The `filetypes`
and `buftypes` matchers run before `when`. If one of these declarative matchers
fails, the `when` callback does not run. Profiles are tested in declaration
order. The first match wins, and profiles never merge. If no profile matches,
the root configuration applies.

`when` receives exactly this table:

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
selection is necessary, including before every source render. Keep them fast,
free of side effects, and non-blocking.

If a callback raises an error, that render uses the root configuration. A
notification appears once for each distinct pair of profile index and error
message. Later calls continue to evaluate the callback. As a result, the
profile recovers without another setup.

Profile `config` accepts only:

- `layout`, `track`, `thumb`, and `marks`.
- `render.geometry`, but not `update.interval_ms` or `update.events`.
- `float.zindex`, `float.hide_on_cursor`, and `float.placement`.
- `mouse.enabled`.
- `hide_if_all_visible`.

Setup rejects every other root field, including `show`, `visibility`,
`set_highlights`, `max_lines`, `autohide`, providers, exclusions, and setup
registries. `preset` goes next to `match`, never inside `config`.

Setup resolves each profile once, with this precedence:

1. Plugin defaults.
2. The profile preset. If the profile omits `preset`, the root preset.
3. Root setup options, excluding `preset`, `presets`, and `profiles`.
4. Profile `config`.

Profiles can use the local presets of the same setup call. If one profile is
not valid, setup fails and the previous configuration stays active.

## Eligibility

`max_lines`, `excluded_buftypes`, and `excluded_filetypes` control scrollbar
eligibility. The minimap has an independent policy in its own root
configuration, with its own `enabled`, `visibility`, exclusions, `max_lines`,
profiles, and placement. As a result, the scrollbar and the minimap can show
in different windows. Invalid and unloaded buffers are never eligible. Each
renderer also excludes its own float buffers. Floating windows never get a
scrollbar or a minimap.

Visibility and autohide are documented in [Visibility](visibility.md).

## Related

- [Presets](presets.md)
- [Layout and geometry](layout-and-geometry.md)
- [Providers](providers/README.md)
- [Highlights](highlights.md)
