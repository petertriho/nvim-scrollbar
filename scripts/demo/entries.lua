-- The images for the README, the docs, and the showcase issue. `init.lua` runs
-- the `setup` source of an entry, and the showcase prints the same source, so
-- an image and its snippet cannot differ.

---@class DemoContext
---@field root string Repository root
---@field split fun(path: string, command?: string): integer Open `path` in a new split and return its window
---@field label fun(winid: integer, text: string) Show `text` in the winbar of `winid`

---@class DemoEntry
---@field id string File stem of the image
---@field kind "png"|"gif"
---@field title string
---@field label string Statusline text. The tapes wait for it, so it must not contain `/`.
---@field description string Markdown
---@field setup string Lua source that configures the plugin
---@field line? integer Cursor line. The default is `M.line`.
---@field search? boolean When `false`, the demo sets no search pattern
---@field settle_ms? integer Time before the statusline shows `label`
---@field prepare? fun(demo: DemoContext)
---@field docs? string The doc that embeds the image
---@field section? string Showcase section id
---@field file? string Set from `id` and `kind`

local M = {}

-- The buffer of every image. It is short enough for a thumb of a few rows.
M.file = "lua/scrollbar/mouse.lua"
M.line = 226
M.search_pattern = "pcall"

M.sections = {
    { id = "defaults", title = "Defaults" },
    { id = "scrollbar", title = "Scrollbar presets" },
    { id = "minimap", title = "Minimap presets" },
    { id = "recipes", title = "Config recipes" },
    { id = "author", title = "Author's setup" },
}

---@param winid integer
---@param name string
---@param value any
local function set_window_variable(winid, name, value)
    vim.w[winid][name] = value
end

---@param winid integer
---@param line integer
local function center(winid, line)
    vim.api.nvim_win_call(winid, function()
        vim.api.nvim_win_set_cursor(winid, { line, 0 })
        vim.cmd("normal! zz")
    end)
end

---@type DemoEntry[]
local entries = {
    -- README and docs
    {
        id = "hero",
        kind = "gif",
        title = "nvim-scrollbar",
        label = "nvim-scrollbar",
        description = "The default scrollbar and minimap while scrolling past diagnostics, Git hunks, and search matches.",
        line = 1,
        search = false,
        docs = "README.md",
        setup = [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    minimap = { enabled = true },
})
]],
    },
    {
        id = "search",
        kind = "gif",
        title = "Incremental search",
        label = "search = { incsearch = true }",
        description = "Search marks follow the pattern while you type it.",
        line = 1,
        search = false,
        docs = "docs/providers/search.md",
        setup = [[
require("scrollbar").setup({
    providers = {
        search = { incsearch = true },
    },
})
]],
    },
    {
        id = "minimap",
        kind = "gif",
        title = "Minimap",
        label = "minimap = { enabled = true }",
        description = "The minimap scrolls with the source window and tints the viewport.",
        line = 1,
        docs = "docs/minimap/README.md",
        setup = [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    minimap = { enabled = true },
})
]],
    },
    {
        id = "autohide",
        kind = "gif",
        title = "Autohide",
        label = "autohide = true",
        description = "The scrollbar shows while you scroll and hides after one second without activity.",
        line = 1,
        search = false,
        docs = "docs/visibility.md",
        setup = [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    scrollbar = { autohide = true },
})
]],
    },
    {
        id = "diagnostics",
        kind = "png",
        title = "Diagnostics",
        label = "diagnostic provider",
        description = "Diagnostic marks of each severity.",
        docs = "docs/providers/diagnostic.md",
        search = false,
        setup = [[
require("scrollbar").setup({
    providers = {
        cursor = false,
        search = false,
        marks = false,
    },
})
]],
    },
    {
        id = "git-hunks",
        kind = "png",
        title = "Git hunks",
        label = "mini_diff provider",
        description = "Added, changed, and deleted hunks from mini.diff.",
        docs = "docs/providers/mini_diff.md",
        search = false,
        setup = [[
require("scrollbar").setup({
    providers = {
        cursor = false,
        diagnostic = false,
        search = false,
        marks = false,
        mini_diff = true,
    },
})
]],
    },
    {
        id = "marks",
        kind = "png",
        title = "Named marks",
        label = "marks provider",
        description = "The letters of the marks `a` to `e`.",
        docs = "docs/providers/marks.md",
        search = false,
        setup = [[
require("scrollbar").setup({
    providers = {
        cursor = false,
        diagnostic = false,
        search = false,
    },
})
]],
    },
    {
        id = "treesitter",
        kind = "png",
        title = "Treesitter colors",
        label = "treesitter provider",
        description = "The minimap draws the dots in the colors of the Treesitter captures.",
        docs = "docs/providers/treesitter.md",
        search = false,
        setup = [[
require("scrollbar").setup({
    providers = {
        cursor = false,
        diagnostic = false,
        search = false,
        marks = false,
    },
    scrollbar = { enabled = false },
    minimap = { enabled = true },
})
]],
    },

    -- Shared by the docs and the showcase
    {
        id = "profiles",
        kind = "png",
        title = "Profiles by filetype",
        label = "profiles",
        description = "`zed` at the root, `review` for Lua, and `minimal` for Markdown. The Makefile split uses the root preset.",
        docs = "docs/configuration.md",
        section = "recipes",
        setup = [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    scrollbar = {
        preset = "zed",
        profiles = {
            {
                match = { filetypes = { "markdown", "text" } },
                preset = "minimal",
            },
            {
                match = { filetypes = { "lua" } },
                preset = "review",
            },
        },
    },
})
]],
        prepare = function(demo)
            local lua_win = vim.api.nvim_get_current_win()
            local markdown_win = demo.split("README.md", "rightbelow vsplit")
            local make_win = demo.split("Makefile", "rightbelow vsplit")
            vim.cmd("wincmd =")
            demo.label(lua_win, "lua: review")
            demo.label(markdown_win, "markdown: minimal")
            demo.label(make_win, "make: zed (root)")
            vim.api.nvim_win_set_cursor(markdown_win, { 60, 0 })
            vim.api.nvim_set_current_win(lua_win)
        end,
    },
    {
        id = "gutter-modes",
        kind = "png",
        title = "West gutter modes",
        label = "placement.gutter",
        description = 'A west scrollbar with `gutter = "inner"`, `"outer"`, and `"overlap"`. Each split sets `vim.w.gutter` to select a profile.',
        docs = "docs/layout-and-geometry.md",
        section = "recipes",
        setup = [[
local function gutter(mode)
    return {
        match = {
            when = function(context)
                return vim.w[context.winid].gutter == mode
            end,
        },
        placement = { anchor = "NW", gutter = mode },
    }
end

require("scrollbar").setup({
    providers = { mini_diff = true },
    scrollbar = {
        profiles = { gutter("inner"), gutter("outer"), gutter("overlap") },
    },
})
]],
        prepare = function(demo)
            local inner = vim.api.nvim_get_current_win()
            local outer = demo.split(M.file, "rightbelow vsplit")
            local overlap = demo.split(M.file, "rightbelow vsplit")
            vim.cmd("wincmd =")
            for winid, mode in pairs({ [inner] = "inner", [outer] = "outer", [overlap] = "overlap" }) do
                set_window_variable(winid, "gutter", mode)
                demo.label(winid, 'gutter = "' .. mode .. '"')
                vim.wo[winid].wrap = false
                center(winid, M.line)
            end
            vim.api.nvim_set_current_win(inner)
        end,
    },
    {
        id = "units",
        kind = "png",
        title = "Line and screen-line units",
        label = "unit",
        description = "Wrapped lines and a closed fold. The left split counts buffer lines. The right split sets `vim.w.screenline` and counts screen lines.",
        docs = "docs/layout-and-geometry.md",
        section = "recipes",
        line = 255,
        setup = [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    scrollbar = {
        profiles = {
            {
                match = {
                    when = function(context)
                        return vim.w[context.winid].screenline == true
                    end,
                },
                unit = "screenline",
            },
        },
    },
})
]],
        prepare = function(demo)
            local line_win = vim.api.nvim_get_current_win()
            local screen_win = demo.split(M.file, "rightbelow vsplit")
            vim.cmd("wincmd =")
            set_window_variable(screen_win, "screenline", true)
            demo.label(line_win, 'unit = "line"')
            demo.label(screen_win, 'unit = "screenline"')
            for _, winid in ipairs({ line_win, screen_win }) do
                vim.wo[winid].wrap = true
                vim.wo[winid].foldmethod = "manual"
                vim.api.nvim_win_call(winid, function()
                    vim.cmd("268,330fold")
                end)
                center(winid, 255)
            end
            vim.api.nvim_set_current_win(line_win)
        end,
    },
}

-- Showcase: defaults
vim.list_extend(entries, {
    {
        id = "defaults",
        kind = "png",
        title = "Default scrollbar",
        label = "setup()",
        description = "No options. The cursor, diagnostic, search, and named-mark providers are on. Git providers are off by default.",
        section = "defaults",
        setup = [[
require("scrollbar").setup({})
]],
    },
    {
        id = "defaults-minimap",
        kind = "png",
        title = "Default scrollbar and minimap",
        label = "minimap = { enabled = true }",
        description = "The default 16-column Braille minimap beside the scrollbar.",
        section = "defaults",
        setup = [[
require("scrollbar").setup({
    minimap = { enabled = true },
})
]],
    },
})

local SCROLLBAR_PRESETS = {
    {
        "vscode",
        "Three overview-ruler columns. Git marks use the inner lane, diagnostics the outer lane, and the other marks the center lane. Marks are below the thumb.",
    },
    {
        "zed",
        "The same three-lane layout as `vscode`. Zed draws Git, highlight, and diagnostic markers in three columns.",
    },
    {
        "intellij",
        "A Git lane on the inner side, beside one track and thumb column. Other marks are above the thumb, and diagnostics win collisions.",
    },
    { "minimal", "A thumb-only overlay with no track and no marks." },
    {
        "review",
        "Separate Git, track and thumb, and diagnostic lanes. No search, cursor, named, or uncategorized marks.",
    },
    { "search", "One compact track and thumb column with only cursor and search marks." },
    {
        "navigate",
        "A track, thumb, and cursor column beside an expandable lane for named marks. No other marks.",
    },
    { "gvim", "A solid, two-column conventional scrollbar without annotations." },
    { "eclipse", "One track and thumb column beside an outer overview ruler that shows every mark type." },
    { "sublime", "A translucent thumb without a track, with only search marks above it." },
    {
        "emacs",
        "A west-anchored bar at the outer edge of its own gutter reservation, with a diagnostic fringe on the inner side.",
    },
    { "xcode", "A translucent thumb without a track and without marks." },
}

for _, preset in ipairs(SCROLLBAR_PRESETS) do
    local name, description = preset[1], preset[2]
    table.insert(entries, {
        id = "scrollbar-" .. name,
        kind = "png",
        title = name,
        label = string.format('scrollbar.preset = "%s"', name),
        description = description,
        section = "scrollbar",
        setup = string.format(
            [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    scrollbar = { preset = "%s" },
})
]],
            name
        ),
    })
end

-- When a scrollbar preset of the same name exists, a minimap preset pairs with
-- it. See docs/presets.md#pair-the-presets.
local MINIMAP_PRESETS = {
    { "vscode", "Braille, 4 columns per dot, 15 cells wide." },
    { "sublime", "Narrow dot columns for a wide, detailed map without mark overlays. 20 cells wide." },
    { "zed", "Braille, 4 columns per dot, 10 cells wide." },
    { "xcode", "Blocks instead of Braille dots. 12 cells wide." },
    { "overview", "The whole buffer fits in the float. 10 cells wide." },
    { "compact", "A narrow map with wide dot columns: 8 columns per dot, 8 cells wide." },
    { "minimal", "A 12-cell map without mark overlays." },
    { "blocks", "The whole buffer as blocks. 16 cells wide." },
}

for _, preset in ipairs(MINIMAP_PRESETS) do
    local name, description = preset[1], preset[2]
    local paired = vim.tbl_contains({ "vscode", "sublime", "zed", "xcode", "minimal" }, name)
    local setup
    if paired then
        description = description .. string.format(" Paired with the `%s` scrollbar preset.", name)
        setup = string.format(
            [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    scrollbar = { preset = "%s" },
    minimap = {
        enabled = true,
        preset = "%s",
    },
})
]],
            name,
            name
        )
    else
        description = description .. " With the default scrollbar."
        setup = string.format(
            [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    minimap = {
        enabled = true,
        preset = "%s",
    },
})
]],
            name
        )
    end
    table.insert(entries, {
        id = "minimap-" .. name,
        kind = "png",
        title = name,
        label = string.format('minimap.preset = "%s"', name),
        description = description,
        section = "minimap",
        setup = setup,
    })
end

vim.list_extend(entries, {
    {
        id = "recipe-minimap-grid",
        kind = "png",
        title = "Minimap scale and encoding",
        label = 'scale = 2, encoding = "block"',
        description = "Two source lines in each dot row, blocks instead of Braille, and narrow dot columns.",
        section = "recipes",
        setup = [[
require("scrollbar").setup({
    providers = { mini_diff = true },
    minimap = {
        enabled = true,
        scale = 2,
        encoding = "block",
        columns_per_dot = 2,
    },
})
]],
    },
    {
        id = "author",
        kind = "png",
        title = "Author's setup",
        label = "author's setup",
        description = "A west scrollbar in the outer gutter, with thin Git marks. The scrollbar replaces the sign column.",
        section = "author",
        setup = [[
vim.o.signcolumn = "no"

require("scrollbar").setup({
    providers = {
        mini_diff = true,
    },
    scrollbar = {
        placement = { anchor = "NW", gutter = "outer" },
        layout = {
            direction = "auto",
            columns = {
                { "track", "thumb", "marks" },
            },
        },
        marks = {
            GitAdd = { text = "│" },
            GitChange = { text = "│" },
            GitDelete = { text = "│" },
            MiniDiffAdd = { text = "│" },
            MiniDiffChange = { text = "│" },
            MiniDiffDelete = { text = "│" },
        },
    },
})
]],
    },
})

for _, entry in ipairs(entries) do
    entry.file = entry.id .. "." .. entry.kind
end

M.entries = entries

---@param id string?
---@return DemoEntry
M.find = function(id)
    for _, entry in ipairs(entries) do
        if entry.id == id then
            return entry
        end
    end
    error(string.format("unknown demo entry '%s'", tostring(id)))
end

return M
