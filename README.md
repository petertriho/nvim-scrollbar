<div align="center">
  <h1>nvim-scrollbar</h1>
  <h5>Extensible Neovim Scrollbar</h5>
</div>

![diagnostics](./assets/diagnostics.gif)

## Features

- Diagnostics
- Search (requires [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens))

## Requirements

- Neovim >= 0.5.1
- [nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens) (optional)

## Installation

[vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'petertriho/nvim-scrollbar'
```

[packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use("petertriho/nvim-scrollbar")
```

## Setup

```lua
require("scrollbar").setup()

```

### Search

![search](./assets/search.gif)

If you also want to configure [hlslens](https://github.com/kevinhwang91/nvim-hlslens), add the following to your setup:

```lua
require("scrollbar.handlers.search").setup()
```

OR

```lua
require("hlslens").setup({
   build_position_cb = function(plist, _, _, _)
        require("scrollbar.handlers.search").handler.show(plist.start_pos)
   end,
})

vim.cmd([[
    augroup scrollbar_search_hide
        autocmd!
        autocmd CmdlineLeave : lua require('scrollbar.handlers.search').handler.hide()
    augroup END
]])
```

## Config

### Defaults

```lua
require("scrollbar").setup({
    show = true,
    set_highlights = true,
    folds = 1000, -- handle folds, set to number to disable folds if no. of lines in buffer exceeds this
    max_lines = false, -- disables if no. of lines in buffer exceeds this
    handle = {
        text = " ",
        color = nil,
        cterm = nil,
        highlight = "CursorColumn",
        hide_if_all_visible = true, -- Hides handle if all lines are visible
    },
    marks = {
        Search = {
            text = { "-", "=" },
            priority = 0,
            color = nil,
            cterm = nil,
            highlight = "Search",
        },
        Error = {
            text = { "-", "=" },
            priority = 1,
            color = nil,
            cterm = nil,
            highlight = "DiagnosticVirtualTextError",
        },
        Warn = {
            text = { "-", "=" },
            priority = 2,
            color = nil,
            cterm = nil,
            highlight = "DiagnosticVirtualTextWarn",
        },
        Info = {
            text = { "-", "=" },
            priority = 3,
            color = nil,
            cterm = nil,
            highlight = "DiagnosticVirtualTextInfo",
        },
        Hint = {
            text = { "-", "=" },
            priority = 4,
            color = nil,
            cterm = nil,
            highlight = "DiagnosticVirtualTextHint",
        },
        Misc = {
            text = { "-", "=" },
            priority = 5,
            color = nil,
            cterm = nil,
            highlight = "Normal",
        },
    },
    excluded_buftypes = {
        "terminal",
    },
    excluded_filetypes = {
        "prompt",
        "TelescopePrompt",
    },
    autocmd = {
        render = {
            "BufWinEnter",
            "TabEnter",
            "TermEnter",
            "WinEnter",
            "CmdwinLeave",
            "TextChanged",
            "VimResized",
            "WinScrolled",
        },
    },
    handlers = {
        diagnostic = true,
        search = false, -- Requires hlslens to be loaded, will run require("scrollbar.handlers.search").setup() for you
    },
})
```

## Colors/Highlights

Color takes precedence over highlight i.e. if color is defined, that will be
used to define the highlight instead of highlight.

Mark type highlights are in the format of `Scrollbar<MarkType>` and
`Scrollbar<MarkType>Handle`. If you wish to define these yourself, add
`set_highlights = false` to the setup.

- `ScrollbarHandle`
- `ScrollbarSearchHandle`
- `ScrollbarSearch`
- `ScrollbarErrorHandle`
- `ScrollbarError`
- `ScrollbarWarnHandle`
- `ScrollbarWarn`
- `ScrollbarInfoHandle`
- `ScrollbarInfo`
- `ScrollbarHintHandle`
- `ScrollbarHint`
- `ScrollbarMiscHandle`
- `ScrollbarMisc`

### Example config with [tokyonight.nvim](https://github.com/folke/tokyonight.nvim) colors

```lua
local colors = require("tokyonight.colors").setup()

require("scrollbar").setup({
    handle = {
        color = colors.bg_highlight,
    },
    marks = {
        Search = { color = colors.orange },
        Error = { color = colors.error },
        Warn = { color = colors.warning },
        Info = { color = colors.info },
        Hint = { color = colors.hint },
        Misc = { color = colors.purple },
    }
})
```

## Custom Handlers

One can define custom handlers consisting of a name and a lua function that returns a list of marks as follows:

```lua
require("scrollbar.handlers").register(name, handler_function)
```

`handler_function` receives the buffer number as argument and must return a list of tables with `line`, `text`, `type`, and `level` keys. Only the `line` key is required.


| Key     | Description                                                   |
|---------|---------------------------------------------------------------|
| `line`  | The line number. *Required*.                                  |
| `text`  | Marker text. Defaults to global settings depending on `type`. |
| `type`  | The marker type. Default is `Misc`.                           |
| `level` | Marker level. Default is `1`.                                 |

E.g. the following marks the first three lines in every buffer.

```lua
require("scrollbar.handlers").register("my_marks", function(bufnr)
    return {
        { line = 0 },
        { line = 1, text = "x", type = "Warn" },
        { line = 2, type = "Error" }
    }
end)
```

## Acknowledgements

- [kevinhwang91/nvim-hlslens](https://github.com/kevinhwang91/nvim-hlslens) for implementation on how to hide search results

## License

[MIT](https://choosealicense.com/licenses/mit/)
