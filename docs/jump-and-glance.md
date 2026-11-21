# Jump and Glance

These features move to the marks of the scrollbar and show the lines of the
marks:

- **Label mode** (`jump()`) shows a label on each mark cell of the scrollbar
  of the current window. A lowercase label moves the cursor to the mark. An
  uppercase label opens the peek float at the mark.
- The **peek float** shows the source buffer around one mark.
- The **glance window** (`glance()`) shows a list of the marks and a preview
  pane. You can move in the list, edit the buffer in the preview, and jump to
  a mark.
- **Hover** opens the peek float when the mouse pointer stays on a mark cell
  of the scrollbar.

The plugin sets no keymaps for these features. See
[Recommended Keymaps](#recommended-keymaps).

## Recommended Keymaps

```lua
local scrollbar = require("scrollbar")

vim.keymap.set("n", "<leader>j", function()
    scrollbar.jump()
end, { desc = "Jump to a scrollbar mark" })

vim.keymap.set("n", "<leader>J", function()
    scrollbar.jump({ types = { "Error", "Warn" } })
end, { desc = "Jump to an error or a warning" })

vim.keymap.set("n", "<leader>g", function()
    scrollbar.glance()
end, { desc = "Glance at the marks" })
```

## Label Mode

![Label mode: labels on the scrollbar marks, a peek float from an uppercase label, and a jump](https://github.com/user-attachments/assets/e0980b14-b9e9-4a03-9da5-bae29f0a2f07)

`require("scrollbar").jump()` and `:ScrollbarJump` start label mode in the
current window. Label mode is inspired by
[flash.nvim](https://github.com/folke/flash.nvim). It reads the keys that you
type until it ends:

| Key | Result |
| --- | --- |
| A lowercase label | Moves the cursor to the line of the mark and ends label mode. |
| An uppercase label | Opens the peek float at the line of the mark. Label mode continues, and the label shows in uppercase. Another uppercase label moves the peek float. |
| `<CR>` | When the peek float is open, moves the cursor to the line of the peek float and ends label mode. |
| `<Esc>` | Closes the peek float and ends label mode. |
| Any other key | Ends label mode. Neovim does not run the key. |

A move goes to the line that a click on the same cell goes to. The move adds
an entry to the jumplist first, so `<C-o>` goes back. Then it moves to the
start of the line, opens the folds that contain the line (`zv`), and centers
the line (`zz`). See [Mouse](mouse.md#click-and-drag).

### Labels

- The labels come from `scrollbar.jump.labels`. The cells with the lines
  nearest to the cursor line get the labels first.
- When the scrollbar has more mark cells than labels, the far cells get no
  label.
- A mark that the thumb covers gets no label, because a click cannot reach it
  either.
- `Cursor` marks get a label only when `types` names `Cursor`.
- The labels stay when the scrollbar renders again. A mark that arrives after
  label mode starts gets no label.
- By default, a label covers its mark cell. With `scrollbar.jump.offset`, the
  label shows that number of columns from its mark cell, so the mark stays
  visible. A positive offset is to the right, and a negative offset is to the
  left. The border columns of the scrollbar float count in the offset. Neovim
  keeps a label inside the editor.

To put the labels beside the scrollbar, on the side of the text, use an offset
that goes past the scrollbar float. For example, for a scrollbar of one column
without a border:

```lua
require("scrollbar").setup({
    scrollbar = {
        -- -1 for the default east scrollbar, 1 for a west scrollbar.
        jump = { offset = -1 },
    },
})
```

When the labels are beside the scrollbar, a peek float at the scrollbar opens
past the label column.

### Scrollbar State

- Label mode needs the scrollbar. With `scrollbar.enabled = false`, `jump()`
  shows a notification, and `:ScrollbarJump` does not exist.
- Label mode works only in a normal window. In a float, such as the list of a
  picker, it shows a notification.
- When the window has no scrollbar or no marks, label mode shows a
  notification and does not start.
- With [autohide](visibility.md#autohide), label mode shows the scrollbar and
  stops the hide delay until it ends.
- When `hide_on_cursor` hides the scrollbar, label mode shows it until it ends.
- Label mode ends when the scrollbar float closes, when the float changes
  size, or when the window shows another buffer.

## Peek Float

The peek float is a float on the source buffer. It shows the line of a mark at
its center. It shows the source buffer itself, so it also shows the
diagnostics, the signs, and the other extmarks of the buffer.

- One peek float shows at a time. Label mode and hover open it.
- The float does not take focus, and the autocmds of other plugins do not see
  it.
- The scrollbar and the minimap never show on the peek float, also when
  `floats.when` selects every float.
- The float has line numbers, the cursor line, `signcolumn = "auto"`, no
  wrap, and no closed folds. `peek.window.wo` changes these options.
- When the float has a top border and `peek.window` has no `title`, the title
  shows the mark types of the line and the line number, for example
  ` Error, Warn · 61 `.

`peek.frame` sets the place and the size of the float. It takes a preset or a
function. See [Frame](#frame).

| Preset | Float |
| --- | --- |
| `"scrollbar"` | Beside the scrollbar, centered on the row of the mark. When the minimap is on the same side, the float is beside the minimap. |
| `"cursor"` | Below the cursor line, or above it when there is no space below. When neither side has space, the float uses the larger side and gets fewer rows. |
| `"center"` | At the center of the window. |

The presets make a float of 11 rows by 60% of the width of the text area,
border included. The float stays inside the source window.

## Glance Window

![The glance window: a list of the marks, a preview that follows the selection, an edit in the preview, and a jump](https://github.com/user-attachments/assets/65d29073-e2c5-4fb3-9f43-310737593faa)

`require("scrollbar").glance()` and `:ScrollbarGlance` open the glance window
of the current window. The glance window is inspired by
[glance.nvim](https://github.com/dnlhc/glance.nvim): its frame, its actions,
and the keys of each pane follow the design of glance.nvim. The glance window
has two panes in one frame. The list of the marks is on the right, and the
preview pane is on the left.

- `glance.frame` sets the place and the size of the frame of both panes. It
  takes a preset or a function. See [Frame](#frame). The default `"cursor"`
  opens the frame below the cursor line, or above it when there is no space
  below. When neither side has space for 18 rows, the frame uses the larger
  side. The presets make a frame of 18 rows, border included, with the width
  of the text area.
- The list takes `glance.list.width` of the frame on the side of
  `glance.list.side`, 40% on the right by default. The preview pane takes the
  rest.
- The list gets the focus. It selects the first entry at or after the cursor
  line.
- The glance window works only in a normal window. In a float, such as the
  list of a picker, it shows a notification. When the window has no marks, it
  shows a notification.

### List

The list reads the mark store, so it also works when the window shows no
scrollbar. It reads the providers that the scrollbar uses. With
`scrollbar.enabled = false`, it reads the providers that the minimap uses. It
holds only the mark types that the renderer shows in the window. The search
matches are `Search` entries.

`glance.list.entries` sets the entries of the list:

| Value | Entries |
| --- | --- |
| `"line"` | One entry for each line with a mark. The entry shows the mark with the highest priority. |
| `"mark"` | One entry for each mark. A line with two marks has two entries. |
| `"type"` | One group for each mark type, with one entry for each line. A header shows the type name and the number of lines. The groups are in mark priority order, then in name order. |

Each entry shows the glyph of its mark, the line number, and the text of the
line:

```text
 -  21  local function setup()
 ┃  61  return M
```

- The glyph is the first item of the `text` list of the mark type. A `Mark`
  entry shows the letter of the mark. A type without a fixed glyph, for
  example a type with a text function, shows `•`.
- The glyph uses the `Scrollbar<Type>` group of its mark type. The line
  number uses `ScrollbarGlanceLineNr`, and a header uses
  `ScrollbarGlanceHeader`.
- A header is not a jump target. On a header, the preview shows the first
  entry of the group, and the jump key does nothing.
- The list buffer has the filetype `scrollbar_glance`.

### Keys

`glance.keys.list` sets the keys of the list, and `glance.keys.preview` sets
the keys of the preview pane. An action without a default key has no key
until you set one. "No" means that the pane does not have the action.

| Action | List | Preview pane | Result |
| --- | --- | --- | --- |
| `jump` | `<CR>` | No | Moves the cursor to the line of the selected entry and closes the glance window. The move is the same as a label mode move, so `<C-o>` goes back. |
| `jump_split` | No default | No default | Opens a split of the source window, and then does the same move in the new window. |
| `jump_vsplit` | No default | No default | The same as `jump_split`, with a vertical split. |
| `next` | No default | No default | Selects the next entry and shows it in the preview. Headers are skipped. After the last entry, the first entry is next. The focus stays in the pane. |
| `previous` | No default | No default | Selects the previous entry, in the same way as `next`. |
| `focus_preview` | `<Tab>` | No | Puts the focus in the preview pane. |
| `focus_list` | No | No default | Puts the focus in the list. |
| `quickfix` | No default | No | Puts each line of the list in a new quickfix list with the title "Scrollbar glance", closes the glance window, and opens the quickfix window. The text of an item is the mark types of the line and the text of the line. |
| `close` | `q`, `<Esc>` | No default | Closes the glance window. The focus goes back to the source window. |

Each action uses the selected entry of the list, also from the preview pane.
The usual motions, for example `j`, `k`, `G`, and `/`, move the selection.
The preview shows the line of the selected entry.

These keys are close to the keys of glance.nvim:

```lua
require("scrollbar").setup({
    glance = {
        keys = {
            list = {
                jump = { "<CR>", "o" },
                jump_split = "<leader>-",
                jump_vsplit = "<leader>\\",
                next = { "<C-j>", "<Tab>" },
                previous = { "<C-k>", "<S-Tab>" },
                focus_preview = "<C-h>",
                quickfix = "Q",
                close = { "q", "<Esc>", "<C-q>" },
            },
            preview = {
                jump_split = "<leader>-",
                jump_vsplit = "<leader>\\",
                next = { "<C-j>", "<Tab>" },
                previous = { "<C-k>", "<S-Tab>" },
                focus_list = "<C-l>",
                close = { "Q", "<C-q>" },
            },
        },
    },
})
```

### Preview Pane

The preview pane is a window on the source buffer, so an edit in it changes
the buffer.

- By default, the preview pane has no keys of the plugin. To go back to the
  list, use `<C-w>p` or `<C-w>w`, or set a `focus_list` key.
- Neovim has no keys for one window, so the keys of `glance.keys.preview` are
  buffer-local keys of the source buffer while the preview pane has the focus.
  They hide your buffer-local keys with the same lhs. Your keys come back when
  the preview pane loses the focus or the glance window closes.
- From a pane, `<C-w>h`, `<C-w>j`, `<C-w>k`, and `<C-w>l` go to the source
  window, so the glance window closes. A global map to one of them, such as
  `<C-l>` to `<C-w>l`, does the same, unless a key of the pane replaces it.
- When the focus goes back to the list from the preview pane, the list reads
  the marks again. It selects the entry at the line that the preview showed,
  also when your edits moved the line.
- The list does not change at other times. A mark that arrives while the list
  has the focus shows after the next return from the preview pane, or in the
  next glance window.

### Closing

The glance window closes when one of these occurs:

- You type a close key in the list.
- You use `:q` in the list or in the preview pane.
- The focus goes to a window outside the frame. The focus stays in that
  window.
- The source window closes.
- `setup()` runs.

## Hover

![Hover: the peek float opens while the pointer rests on a mark of the scrollbar](https://github.com/user-attachments/assets/02a49328-44e8-4c3a-b2c8-e20ec6bdb71e)

With `scrollbar.hover`, the peek float opens when the mouse pointer stays on a
mark cell of the scrollbar for `delay_ms`:

```lua
require("scrollbar").setup({
    scrollbar = {
        hover = { delay_ms = 300 }, -- or true
    },
})
```

- Hover works only on scrollbars with `mouse = true` in normal windows. It
  does not work on the minimap or on the scrollbars of floats.
- The peek float uses `peek.frame`. With `"scrollbar"`, it is centered on the
  row of the mark.
- Hover shows no labels, and it does nothing during label mode.
- The peek float closes when the pointer leaves the cell, when you type a key,
  or when the source window scrolls. A pointer move to another mark cell
  opens the peek float of that mark after the delay.
- Hover needs mouse support in Neovim, for example `vim.o.mouse = "a"`.

Neovim reports pointer moves only with `'mousemoveevent'`. When hover is on,
`setup()` sets `'mousemoveevent'`. A later `setup()` without hover restores
the option only when the plugin set it. `'mousemoveevent'` is a global
option, so other plugins also see the pointer moves.

## Options

```lua
require("scrollbar").setup({
    scrollbar = {
        jump = {
            labels = "asdfghjklqwertyuiopzxcvbnm",
            offset = 0,
        },
        hover = false, -- true, or { delay_ms = 300 }
    },
    peek = {
        frame = "scrollbar", -- "scrollbar", "cursor", "center", or a function
        window = {},
    },
    glance = {
        frame = "cursor", -- "scrollbar", "cursor", "center", or a function
        list = {
            entries = "line", -- "line", "mark", or "type"
            width = 0.4,
            side = "right", -- "right" or "left"
        },
        keys = {
            list = {
                jump = "<CR>",
                jump_split = false,
                jump_vsplit = false,
                next = false,
                previous = false,
                focus_preview = "<Tab>",
                quickfix = false,
                close = { "q", "<Esc>" },
            },
            preview = {
                jump_split = false,
                jump_vsplit = false,
                next = false,
                previous = false,
                focus_list = false,
                close = false,
            },
        },
        window = {},
    },
})
```

`scrollbar.jump` and `scrollbar.hover` are global options of the scrollbar
block. `peek` and `glance` are top-level blocks. Profiles do not change these
options.

| Option | Default | Meaning |
| --- | --- | --- |
| `scrollbar.jump.labels` | `"asdfghjklqwertyuiopzxcvbnm"` | The labels, in order. Only lowercase ASCII letters, each one time. The uppercase letter of a label opens the peek float. |
| `scrollbar.jump.offset` | `0` | Columns from each mark cell to its label. A negative offset is to the left. `0` puts the label on the mark cell. See [Labels](#labels). |
| `scrollbar.hover` | `false` | `true` opens the peek float after 300 ms. `{ delay_ms = n }` sets the delay. |
| `peek.frame` | `"scrollbar"` | Place and size of the peek float: a preset or a function. See [Frame](#frame). |
| `peek.window` | `{}` | Border, title, footer, and window options of the peek float. See [Window](#window). |
| `glance.frame` | `"cursor"` | Place and size of the frame of both panes: a preset or a function. See [Frame](#frame). |
| `glance.list.entries` | `"line"` | Entries of the list. See [List](#list). |
| `glance.list.width` | `0.4` | Width of the list pane, border included. A number less than `1` is a part of the frame width, and a whole number above `1` is cells. The preview pane takes the rest. |
| `glance.list.side` | `"right"` | Side of the list pane: `"right"` or `"left"`. The preview pane takes the other side. |
| `glance.keys.list` | See [Keys](#keys) | Keys of the actions in the list. |
| `glance.keys.preview` | See [Keys](#keys) | Keys of the actions in the preview pane. |
| `glance.window` | `{}` | Border, title, footer, and window options of both panes. See [Window](#window). |

Each value in `glance.keys.list` and `glance.keys.preview` is a key, a list of
keys, or `false`. `false` removes the keys of the action. Setup rejects a key
that two actions of one pane use. The list and the preview pane can use the
same key.

### Window

`peek.window` and `glance.window` configure the floats. They accept the same
keys as [`scrollbar.window`](configuration.md#window), with these differences:

- Without a `border` key, the floats use `'winborder'` as it is when they
  open. With the default empty `'winborder'`, the floats have no border.
  `window.border` sets a border for the floats only.
- `window.wo` also accepts `number`, `relativenumber`, `signcolumn`,
  `foldcolumn`, `statuscolumn`, and `wrap`. These options apply after the
  defaults of the float.
- Setup rejects the keys that the plugin sets: `relative`, `win`, `bufpos`,
  `anchor`, `row`, `col`, `width`, `height`, `focusable`, `hide`, `style`,
  `external`, `split`, `vertical`, `noautocmd`, and `fixed`. The error names
  the option to use, for example `peek.frame` for `height`.
- The keys of `glance.window` apply to both panes.

```lua
require("scrollbar").setup({
    peek = {
        window = {
            border = "rounded",
            wo = { relativenumber = true },
        },
    },
    glance = {
        window = { border = "single" },
    },
})
```

### Frame

`peek.frame` and `glance.frame` set the place and the size of the frame: the
outer box of the float, border included. For the glance window, the frame
holds both panes. The value is a preset name or a frame function.
`require("scrollbar.recipes").frame` has recipes that make frame functions.
Each preset is its recipe without options, so `"cursor"` is the same as
`recipes.frame.cursor()`.

| Recipe | Options | Frame |
| --- | --- | --- |
| `recipes.frame.scrollbar()` | `width`, `height` | Beside the scrollbar, with the content rows centered on the row of the mark. When the minimap is on the same side, the frame is beside the minimap. The frame does not cover the scrollbar, the minimap, or a label. For glance, the row of the mark is the cursor row. |
| `recipes.frame.cursor()` | `width`, `height` | Below the cursor line, or above it when there is no space below. When neither side has space, the frame uses the larger side and gets fewer rows. It starts at the left edge of the text area. |
| `recipes.frame.center()` | `width`, `height`, `relative` | At the center of the text area. With `relative = "editor"`, at the center of the editor area. |

`width` and `height` include the border:

- A number up to `1` is a part of the text area: the window width without
  the gutter, and the rows of the window without the winbar. `1` is the full
  size.
- A whole number above `1` is a count of cells.
- With `relative = "editor"`, a part measures the editor area.
- A size larger than the area shrinks to the area.

Without `width` or `height`, a recipe uses the default size of the float:

| Float | `width` | `height` |
| --- | --- | --- |
| Peek | `0.6` | `11` |
| Glance | `1` | `18` |

Call each recipe with `()`, as the [text recipes](configuration.md#recipes).
A recipe checks its options when you call it.

```lua
local frame = require("scrollbar.recipes").frame

require("scrollbar").setup({
    peek = {
        frame = frame.cursor({ height = 15 }),
    },
    glance = {
        frame = frame.center({ relative = "editor", width = 0.8, height = 0.7 }),
        list = { width = 40, side = "left" },
    },
})
```

#### Frame Functions

A frame function gets a context table and returns the frame, or `nil` when
the window has no space for the float. The plugin calls the function each
time the float opens or moves.

| Context field | Meaning |
| --- | --- |
| `kind` | `"peek"` or `"glance"`. |
| `winid`, `bufnr` | The source window and its buffer. |
| `win` | `{ width, height, textoff }`: the columns of the window, the rows of the window without the winbar, and the columns of the gutter. |
| `editor` | `{ width, height }`: the editor area. |
| `sides` | `{ top, right, bottom, left }`: the border cells of one pane, `0` or `1` each. |
| `cursor_row` | The zero-based row of the cursor line in the window. |
| `anchor_row` | The zero-based row of the mark: the row of the label in label mode, or the row of the pointer in hover. For glance, `cursor_row`. |
| `free` | `{ side, first_col, last_col }`: the columns of the window that do not cover the scrollbar, the minimap, or a label. `side` is the side of the scrollbar, `"E"` or `"W"`. `last_col` is not part of the range. |

| Result field | Meaning |
| --- | --- |
| `relative` | `"win"` (the default) or `"editor"`. |
| `row`, `col` | The zero-based position of the frame. With `"win"`, `row` is relative to the first row below the winbar, and `col` to the first column of the window. With `"editor"`, both are relative to the editor area. |
| `width`, `height` | The size of the frame in cells, border included. |

- The plugin rounds the numbers down.
- The plugin shrinks a frame that is larger than its area, then moves it into
  the area. With `"win"`, the area is the window, so a frame can cover the
  gutter.
- The editor area is the space between the tabline and the command line. It
  does not include the tabline when it shows, a global statusline
  (`laststatus = 3`), or the command line. Row `0` is the first row below the
  tabline.
- When the panes have no space for one cell of content, the glance window
  shows a notification, and the peek float does not open.
- When the function fails or returns an invalid result, the float does not
  open, and a notification shows. The same message shows only one time until
  the next `setup()`.

This function puts the glance frame in the bottom half of the window:

```lua
require("scrollbar").setup({
    glance = {
        frame = function(ctx)
            local height = math.floor(ctx.win.height / 2)
            return {
                row = ctx.win.height - height,
                col = ctx.win.textoff,
                width = ctx.win.width - ctx.win.textoff,
                height = height,
            }
        end,
    },
})
```

#### Resize

When the screen changes size (`VimResized`), or when the source window
changes size (`WinResized`), an open peek float or glance window runs its
frame again and moves to the new frame. The glance window keeps its list, its
selection, and the focus. When the new frame does not fit, the float closes:
the glance window shows a notification and puts the focus in the source
window. A size change of another window does nothing.

## Lua API and Commands

| Lua | Command | Result |
| --- | --- | --- |
| `require("scrollbar").jump(opts)` | `:ScrollbarJump [types]` | Starts label mode. The command exists only when the scrollbar is enabled. |
| `require("scrollbar").glance(opts)` | `:ScrollbarGlance [types]` | Opens the glance window. The command always exists after `setup()`. |

`opts.types` is a list of mark type names, for example
`{ "Error", "Warn" }`. Without `types`, every mark type except `Cursor` is
used. The commands take the names as arguments, and they complete the names
of the registered mark types.

- An unknown mark type name gives an error notification, and nothing opens.
- Before `setup()`, `jump()` and `glance()` show a notification and do
  nothing.

## Highlights

| Group | Default link | Use |
| --- | --- | --- |
| `ScrollbarJumpLabel` | `Substitute` | The labels of label mode |
| `ScrollbarGlanceHeader` | `Title` | The group headers of the glance list |
| `ScrollbarGlanceLineNr` | `LineNr` | The line numbers of the glance list |

With `set_highlights = false`, the plugin does not create these groups. See
[Highlights](highlights.md#navigation-groups).

## Related

- [Configuration](configuration.md)
- [Mouse](mouse.md)
- [Visibility](visibility.md)
- [Highlights](highlights.md)
