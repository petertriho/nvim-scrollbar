-- Neovim init for the README, docs, and showcase images. The VHS tapes start
-- `nvim --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua` with
-- `DEMO_ENTRY` set to an entry id of `entries.lua`. The diagnostics, hunks,
-- marks, and search pattern come from `entries.lua`, so every image shows the
-- same data.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

vim.opt.runtimepath:prepend(root .. "/deps/tokyonight.nvim")
vim.opt.runtimepath:prepend(root .. "/deps/mini.nvim")
vim.opt.runtimepath:prepend(root)

local catalog = dofile(root .. "/scripts/demo/entries.lua")
local entry = catalog.find(vim.env.DEMO_ENTRY)

local DEFAULT_SETTLE_MS = 1500

-- The fraction of the buffer that CTRL-D scrolls. The tapes press CTRL-D a fixed
-- number of times, so each press moves the same part of the scrollbar and the
-- minimap whatever the length of the buffer.
local SCROLL_FRACTION = 0.04

vim.o.swapfile = false
vim.o.termguicolors = true
vim.o.mouse = "a"
vim.o.number = true
vim.o.relativenumber = true
vim.o.cursorline = true
vim.o.signcolumn = "no"
vim.o.laststatus = 3
vim.o.cmdheight = 0
vim.o.showmode = false
vim.o.ruler = false
vim.o.showcmd = false
vim.o.hlsearch = true
vim.o.incsearch = true
vim.opt.shortmess:append("FI")

-- The statusline shows the label when the demo is ready. The tapes wait for it.
vim.o.statusline = " %f"

require("tokyonight").setup({
    style = "night",
    on_highlights = function(highlights, colors)
        highlights.ScrollbarSearch = { fg = colors.orange }
        highlights.ScrollbarMinimapSearch = { fg = colors.orange }
        highlights.ScrollbarMinimapCursor = { fg = colors.fg, bg = colors.fg }
    end,
})
vim.cmd.colorscheme("tokyonight")

local minidiff = require("mini.diff")
minidiff.setup({
    source = minidiff.gen_source.none(),
    view = { style = "sign" },
})

vim.diagnostic.config({ virtual_text = true, signs = false })

-- Autocommands restore the search pattern when they finish, so the pattern is
-- set here, outside an autocommand.
if entry.search ~= false then
    vim.fn.setreg("/", catalog.search_pattern)
end

assert(load(entry.setup, "=" .. entry.id))()

---@param lines string[]
---@param line integer
---@return integer
local function non_blank(lines, line)
    while line < #lines and lines[line]:match("^%s*$") do
        line = line + 1
    end
    return line
end

---@param bufnr integer
local function set_diagnostics(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local namespace = vim.api.nvim_create_namespace("scrollbar_demo")
    local diagnostics = {}
    for _, item in ipairs(catalog.diagnostics) do
        local line = non_blank(lines, catalog.line_at(item[1], #lines))
        local text = lines[line] or ""
        table.insert(diagnostics, {
            lnum = line - 1,
            col = #text:match("^%s*"),
            end_col = #text,
            severity = vim.diagnostic.severity[item[2]],
            message = item[3],
            source = "lua_ls",
        })
    end
    vim.diagnostic.set(namespace, bufnr, diagnostics)
end

---@param bufnr integer
local function set_hunks(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local added, changed, deleted = {}, {}, {}
    for _, hunk in ipairs(catalog.hunks) do
        local first = catalog.line_at(hunk.position, #lines)
        if hunk.kind == "delete" then
            deleted[first] = hunk.count
        else
            for line = first, first + hunk.count - 1 do
                (hunk.kind == "add" and added or changed)[line] = true
            end
        end
    end

    local reference = {}
    for line, text in ipairs(lines) do
        if changed[line] then
            table.insert(reference, text .. " -- before")
        elseif not added[line] then
            table.insert(reference, text)
        end
        for index = 1, deleted[line] or 0 do
            table.insert(reference, "-- removed line " .. index)
        end
    end
    minidiff.set_ref_text(bufnr, reference)
end

---@param bufnr integer
local function set_marks(bufnr)
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    for name, position in pairs(catalog.marks) do
        vim.api.nvim_buf_set_mark(bufnr, name, catalog.line_at(position, line_count), 0, {})
    end
end

---@type DemoContext
local demo = {
    root = root,
    split = function(path, command)
        vim.cmd((command or "vsplit") .. " " .. vim.fn.fnameescape(path))
        return vim.api.nvim_get_current_win()
    end,
    label = function(winid, text)
        vim.wo[winid].winbar = " " .. text:gsub("%%", "%%%%")
    end,
}

local function start()
    local bufnr = vim.api.nvim_get_current_buf()
    set_diagnostics(bufnr)
    set_hunks(bufnr)
    set_marks(bufnr)

    local line_count = vim.api.nvim_buf_line_count(bufnr)
    vim.api.nvim_win_set_cursor(0, { catalog.line_at(entry.position or catalog.position, line_count), 0 })
    vim.cmd("normal! zz")
    vim.wo.scroll = math.max(1, math.floor(line_count * SCROLL_FRACTION + 0.5))

    if entry.prepare then
        entry.prepare(demo)
    end
    require("scrollbar").refresh()

    vim.defer_fn(function()
        vim.o.statusline = " %f%=" .. entry.label:gsub("%%", "%%%%") .. " "
    end, entry.settle_ms or DEFAULT_SETTLE_MS)
end

vim.api.nvim_create_autocmd("VimEnter", {
    once = true,
    callback = function()
        vim.schedule(start)
    end,
})
