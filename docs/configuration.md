# Configuration

`require("scrollbar").setup()` validates unknown keys, scalar types, enums,
dense lists, layout spans, and presentation values. Every call starts from fresh
defaults; it does not merge with a previous setup call.

## Defaults

```lua
require("scrollbar").setup({
    preset = nil,
    presets = nil,
    profiles = nil,
    show = true,
    visibility = "all", -- "all" or "active"
    set_highlights = true,
    max_lines = false,
    hide_if_all_visible = false,
    autohide = { enabled = false, delay_ms = 1000 },
    render = { interval_ms = 16, geometry = "line" },
    float = {
        zindex = 50,
        hide_on_cursor = true,
        placement = {
            relative = "window", -- "window" or "editor"
            anchor = "NE", -- "NW", "NE", "SW", or "SE"
            row = 0,
            col = 0,
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
})
```

`search = true` normalizes to `{ backend = "worker" }`. Omitting
`providers.search.incsearch` follows the current `vim.o.incsearch` value.
`marks = true` normalizes to `{ letters = true, numbers = false }`.

## Layout

`layout.columns` is a non-empty dense list of logical display columns. Every
column is a non-empty bottom-to-top layer list:

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

String layers are `"track"`, `"thumb"`, and `"marks"`. Plain `"marks"` is
the catch-all for types not claimed by an explicit descriptor. Descriptor
fields are:

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | `"marks"` | Required tag |
| `types` | dense string list | Explicit mark types; unknown names are allowed |
| `max_width` | positive integer | Total width of a lane explicitly selecting `Mark` |

Adjacent occurrences with the same selector form one lane. A catch-all lane,
an explicitly selected type, and the thumb may each occupy only one contiguous
span. Track layers may appear in any columns. Track, thumb, and marks are all
optional; cells with no interactive rendered layer are transparent and inert.

`direction = "auto"` treats declarations as inner-to-outer: east anchors keep
the declared order and west anchors mirror it. `"ltr"` and `"rtl"` force
physical screen order. See [Layout and geometry](layout-and-geometry.md).

## Marks

Each `marks.<Type>` accepts only `text`, `priority`, and `highlight`. New custom
types must provide all three. Type names match `^[%a_][%w_]*$`.

- `text` is a string or dense list of positive-display-width strings without
  control characters. Lists are density variants. Only `marks.Mark.text` may
  be empty, which preserves literal names from the built-in marks provider.
- `priority` is a non-negative integer. Lower numbers win collisions within one
  mark lane. Separate mark layers use their declared stack order instead.
- `highlight` is a non-empty group name or an `nvim_set_hl()` definition table.

Ordinary text is clipped to its lane without splitting multi-cell glyphs.
Multi-cell glyphs are omitted atomically if a collision would expose only part
of the glyph.

## Providers

`cursor`, `diagnostic`, `gitsigns`, `mini_diff`, `signify`, `vgit`, `ale`, and
`coc` are booleans. `search` is a boolean or a table containing `incsearch`
(boolean) and `backend` (`"worker"` or `"sync"`). `marks` is a boolean or a
table containing only `letters` and `numbers`, both booleans. Presentation
width belongs to the layout, not the provider.

## Validation

- `visibility`: `"all"` or `"active"`.
- `render.geometry`: `"line"` or `"screen"`.
- `render.interval_ms`, `thumb.blend`, and mark priorities: non-negative
  integers. `thumb.blend` is at most `100`.
- `autohide.delay_ms`, `float.zindex`, layout `max_width`, and a numeric
  `max_lines`: positive integers.
- `float.placement.relative`: `"window"` or `"editor"`.
- `float.placement.anchor`: `"NW"`, `"NE"`, `"SW"`, or `"SE"`.
- `float.placement.row` and `col`: signed integers.
- `thumb.text`: one positive-display-width string without control characters.
- Exclusion options: dense string lists.
- Unknown keys at every schema level are errors.

Dense lists replace atomically instead of merging by index. This includes
`layout.columns`, descriptor `types`, mark `text`, and exclusion lists.

## Presets

`preset` and `presets` exist only during one setup call and are removed from the
normalized runtime config. Built-ins are `vscode`, `zed`, `intellij`, `minimal`,
`review`, `search`, `navigate`, `gvim`, `eclipse`, `sublime`, `emacs`, and
`xcode`.
Preset definitions may set only `layout`, `track`, `thumb`, `marks`, and
`float.placement`, plus one optional `extends` parent. Root setup values win over
the selected preset. See [Presets](presets.md).

## Contextual Profiles

`profiles` is a setup-local dense ordered list. Each entry has a required
`match`, an optional `preset`, and an optional render-safe `config`:

```lua
require("scrollbar").setup({
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
})
```

`match` must contain at least one matcher:

- `filetypes`: non-empty dense string list.
- `buftypes`: non-empty dense string list.
- `when`: predicate function.

All supplied matchers are ANDed. Filetype and buftype checks run before `when`,
so callbacks are skipped when a declarative check already fails. Profiles are
tested in declaration order; the first match wins and profiles are never merged.
No match selects the root normalized config with stable variant ID `0`.

`when` receives exactly:

```lua
{
    winid = source_win,
    bufnr = source_buf,
    filetype = vim.bo[source_buf].filetype,
    buftype = vim.bo[source_buf].buftype,
    bufname = vim.api.nvim_buf_get_name(source_buf),
}
```

Selection is not cached. Predicates are reevaluated whenever a selection is
needed, including before every source render, so keep them fast, side-effect
free, and non-blocking. A callback error selects the root config for that render
and notifies once per distinct profile-index/error-message pair. Later calls
continue evaluating the callback, so recovery does not require another setup.

Profile `config` accepts only:

- `layout`, `track`, `thumb`, and `marks`.
- `render.geometry`, but not `render.interval_ms`.
- `float.zindex`, `float.hide_on_cursor`, and `float.placement`.
- `mouse.enabled`.
- `hide_if_all_visible`.

Every other root field is rejected, including `show`, `visibility`,
`set_highlights`, `max_lines`, `autohide`, providers, exclusions, and setup
registries. `preset` belongs beside `match`, never inside `config`.

Each variant is validated and compiled once during setup with this precedence:

1. Plugin defaults.
2. The profile preset, or the root preset when omitted.
3. Root setup options, excluding `preset`, `presets`, and `profiles`.
4. Profile `config`.

Setup-local presets are available while all variants compile. The root and all
variants are committed atomically only after every profile succeeds.

Providers, provider options, exclusions, `show`, `visibility`, `max_lines`,
autohide, render interval, scheduling, and automatic-highlight policy remain
root-owned. Profiles control only the validated presentation, geometry,
placement, fit-hiding, and mouse fields above.

## Eligibility

`max_lines`, `excluded_buftypes`, and `excluded_filetypes` control whether a
source buffer receives a scrollbar or accepts provider publication.
Scrollbar-owned scratch buffers are always excluded, as are invalid or unloaded
buffers. The same renderer-backed buffer policy is enforced for direct context
setters, provider refresh results, and built-in publication paths.

Buffer-scoped publication depends only on buffer eligibility; the buffer does
not need a currently selected window. Window-scoped publication requires exact
membership in the current source-window set: a normal non-renderer window with
an eligible buffer, selected by root `visibility` and the effective profile's
editor-relative placement. Policy changes alone do not continuously purge
provider stores; rejection and clearing occur at the next publication or
refresh attempt. Visibility and autohide are documented in
[Visibility](visibility.md).

## Related

- [Presets](presets.md)
- [Layout and geometry](layout-and-geometry.md)
- [Providers](providers/README.md)
- [Highlights](highlights.md)
