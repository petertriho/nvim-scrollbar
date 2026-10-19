-- Neovim init for the README, docs, and showcase images. The VHS tapes start
-- `nvim --clean -u scripts/demo/init.lua lua/scrollbar/mouse.lua` with
-- `DEMO_ENTRY` set to an entry id of `entries.lua`. The diagnostics, hunks,
-- marks, and search pattern are fixed, so every image shows the same data.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")

vim.opt.runtimepath:prepend(root .. "/deps/tokyonight.nvim")
vim.opt.runtimepath:prepend(root .. "/deps/mini.nvim")
vim.opt.runtimepath:prepend(root)

local catalog = dofile(root .. "/scripts/demo/entries.lua")
local entry = catalog.find(vim.env.DEMO_ENTRY)

local DEFAULT_SETTLE_MS = 1500

-- Lines of `catalog.file`. Each mark lands on the first non-blank line at or
-- after its line.
local DIAGNOSTICS = {
    { 45, vim.diagnostic.severity.ERROR, "Undefined field `relative`." },
    { 224, vim.diagnostic.severity.ERROR, "Cannot compare `integer?` with `integer`." },
    { 389, vim.diagnostic.severity.ERROR, "Missing argument `source_win`." },
    { 120, vim.diagnostic.severity.WARN, "Unused local `view`." },
    { 219, vim.diagnostic.severity.WARN, "Need check nil." },
    { 330, vim.diagnostic.severity.WARN, "Redundant return value." },
    { 405, vim.diagnostic.severity.WARN, "Unused local `active`." },
    { 228, vim.diagnostic.severity.INFO, "Line is longer than 100 columns." },
    { 300, vim.diagnostic.severity.INFO, "Function has 9 upvalues." },
    { 70, vim.diagnostic.severity.HINT, "Unnecessary `do` block." },
    { 160, vim.diagnostic.severity.HINT, "Consider `math.min`." },
    { 410, vim.diagnostic.severity.HINT, "Unused function `restore_source`." },
}

-- Line ranges of the buffer that differ from the mini.diff reference text.
local HUNKS = {
    { kind = "add", first = 95, last = 98 },
    { kind = "change", first = 140, last = 142 },
    { kind = "delete", after = 185, count = 2 },
    { kind = "change", first = 270, last = 272 },
    { kind = "add", first = 350, last = 353 },
}

local MARKS = { a = 30, b = 110, c = 200, d = 290, e = 380 }

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

-- The statusline shows the label once the demo is ready. The tapes wait for it.
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

-- Autocommands restore the search pattern when they finish, so set it here.
if entry.search ~= false then
    vim.fn.setreg("/", catalog.search_pattern)
end

assert(load(entry.setup, "=" .. entry.id))()

---@param lines string[]
---@param line integer
---@return integer
local function non_blank(lines, line)
    while lines[line] and lines[line]:match("^%s*$") do
        line = line + 1
    end
    return line
end

---@param bufnr integer
local function set_diagnostics(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local namespace = vim.api.nvim_create_namespace("scrollbar_demo")
    local diagnostics = {}
    for _, item in ipairs(DIAGNOSTICS) do
        local line = non_blank(lines, item[1])
        local text = lines[line] or ""
        table.insert(diagnostics, {
            lnum = line - 1,
            col = #text:match("^%s*"),
            end_col = #text,
            severity = item[2],
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
    for _, hunk in ipairs(HUNKS) do
        if hunk.kind == "delete" then
            deleted[hunk.after] = hunk.count
        else
            for line = hunk.first, hunk.last do
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
    for name, line in pairs(MARKS) do
        vim.api.nvim_buf_set_mark(bufnr, name, line, 0, {})
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

    local line = math.min(entry.line or catalog.line, vim.api.nvim_buf_line_count(bufnr))
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd("normal! zz")

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
