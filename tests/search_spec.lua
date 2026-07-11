vim.opt.runtimepath:prepend(vim.fn.getcwd())

local function assert_equal(expected, actual, message)
    if not vim.deep_equal(expected, actual) then
        error(string.format("%s\nexpected: %s\nactual: %s", message, vim.inspect(expected), vim.inspect(actual)))
    end
end

local function search_marks()
    return require("scrollbar.utils").get_scrollbar_marks(0).search
end

local function mark_lines()
    local marks = search_marks()
    if marks == nil then
        return nil
    end

    return vim.tbl_map(function(mark)
        return mark.line
    end, marks)
end

local function inspect_during_cmdline(keys)
    local called = false
    local marks

    vim.keymap.set("c", "<F5>", function()
        called = true
        vim.g.search_spec_mode = vim.api.nvim_get_mode().mode
        marks = vim.deepcopy(search_marks())
        return vim.keycode("<C-c>")
    end, { expr = true })
    vim.api.nvim_feedkeys(keys .. vim.keycode("<F5>"), "xt", false)
    vim.keymap.del("c", "<F5>")
    assert(called, "command-line inspection mapping did not run")

    if marks == nil then
        return nil
    end

    return vim.tbl_map(function(mark)
        return mark.line
    end, marks)
end

local search = require("scrollbar.handlers.search")
search.setup()

local function scan(lines, pattern)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.fn.setreg("/", pattern)
    vim.fn.search(pattern, "cw")
    local view = vim.fn.winsaveview()
    search.refresh()
    assert_equal(view, vim.fn.winsaveview(), "search scans should preserve the complete window view")

    return vim.tbl_map(function(mark)
        return mark.line
    end, search_marks())
end

vim.o.hlsearch = true
vim.o.wrapscan = false

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "start", "direct", "direct" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("/direct<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1, 2 }, mark_lines())
    end),
    "search.setup() should process accepted searches"
)

assert_equal(
    { 0, 0, 2 },
    scan({ "foo foo", "middle", "foo" }, "foo"),
    "accepted searches should create zero-based marks for every match"
)
assert_equal({ 0, 1, 2 }, scan({ "one", "two", "three" }, "^"), "zero-width patterns should terminate")
assert_equal({ 0, 0 }, scan({ "foo bar", "none" }, [[foo\|bar]]), "escaped Vim regexes should find all matches")
assert_equal(
    { 0, 3 },
    scan({ "foo", "middle", "bar", "foo bar" }, [[foo\_.\{-}bar]]),
    "multiline Vim regexes should use their starting lines"
)

vim.o.ignorecase = true
assert_equal({ 1 }, scan({ "foo", "Foo" }, [[\CFoo]]), "pattern case atoms should override case options")
assert_equal({ 0, 1 }, scan({ "foo", "Foo" }, "foo"), "ignorecase should affect native scans")
vim.o.smartcase = true
assert_equal({ 1 }, scan({ "foo", "Foo" }, "Foo"), "smartcase should affect native scans")
vim.o.smartcase = false
vim.o.ignorecase = false

local config = require("scrollbar.config").get()
local previous_search_config = vim.deepcopy(config.handlers.search)
local valid, validation_error = pcall(search.setup, { live = "yes" })
assert_equal(false, valid, "invalid direct setup options should fail")
assert(validation_error:match("live must be a boolean"), validation_error)
assert_equal(previous_search_config, config.handlers.search, "invalid options should not mutate search state")
valid, validation_error = pcall(require("scrollbar").setup, { handlers = { search = { live = "yes" } } })
assert_equal(false, valid, "invalid root setup options should fail")
assert(validation_error:match("live must be a boolean"), validation_error)
assert_equal(previous_search_config, config.handlers.search, "invalid root options should not mutate search state")

require("scrollbar").setup({
    set_highlights = false,
    throttle_ms = 0,
    autocmd = { render = {} },
    handlers = {
        cursor = false,
        diagnostic = false,
        gitsigns = false,
        search = true,
        ale = false,
    },
})
assert_equal({ live = false }, config.handlers.search, "handlers.search = true should enable accepted searches")
assert_equal({ 1 }, mark_lines(), "handlers.search = true should scan accepted patterns")
assert_equal(
    1,
    #vim.api.nvim_get_autocmds({ group = "scrollbar_search", event = "CmdlineLeave" }),
    "root setup should register accepted search updates"
)

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "start", "roottrue", "roottrue" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("/roottrue<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1, 2 }, mark_lines())
    end),
    "handlers.search = true should process accepted searches"
)

search.setup({ live = false })
assert_equal({ live = false }, config.handlers.search, "direct table setup should enable accepted searches")
assert_equal(
    1,
    #vim.api.nvim_get_autocmds({ group = "scrollbar_search", event = "CmdlineLeave" }),
    "setup should be idempotent"
)

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "beta", "alpha" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("/alpha<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return search_marks() and #search_marks() == 2
    end),
    "accepted forward searches should refresh marks"
)

vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.api.nvim_feedkeys(vim.keycode("?beta<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return search_marks() and #search_marks() == 1 and search_marks()[1].line == 1
    end),
    "accepted backward searches should refresh marks"
)

vim.api.nvim_buf_set_lines(0, 1, 2, false, { "beta beta" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
assert_equal({ 1, 1 }, mark_lines(), "buffer edits should refresh accepted search marks")
assert_equal({ 1, 1 }, inspect_during_cmdline("/alpha"), "live = false should not preview command-line patterns")
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1, 1 }, mark_lines())
    end),
    "cancelled non-live searches should preserve accepted results"
)

search.setup({ live = true })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "start", "accepted", "preview", "preview" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("/accepted<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1 }, mark_lines())
    end),
    "live mode should retain accepted results"
)

local live_preview = inspect_during_cmdline("/preview")
assert_equal("c", vim.g.search_spec_mode, "inspection should run while the command line is active")
assert_equal({ 2, 3 }, live_preview, "live mode should preview valid patterns")
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1 }, mark_lines())
    end),
    "cancelling should restore accepted results after a live preview"
)

assert_equal({ 2, 3 }, inspect_during_cmdline("?preview"), "live mode should preview backward search patterns")
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1 }, mark_lines())
    end),
    "cancelling a backward live preview should restore accepted results"
)

assert_equal(nil, inspect_during_cmdline([[/\(]]), "invalid live patterns should hide previews")
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1 }, mark_lines())
    end),
    "cancelling an invalid live pattern should restore accepted results"
)

vim.api.nvim_feedkeys(vim.keycode("/preview<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 2, 3 }, mark_lines())
    end),
    "accepted live searches should commit their results"
)

local current_bufnr = vim.api.nvim_get_current_buf()
local globally_hidden_bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(globally_hidden_bufnr, 0, -1, false, { "preview" })
vim.api.nvim_win_set_buf(0, globally_hidden_bufnr)
assert_equal({ 0 }, mark_lines(), "buffer entry should cache marks before global clearing")
vim.api.nvim_win_set_buf(0, current_bufnr)
vim.api.nvim_feedkeys(vim.keycode(":nohlsearch<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return search_marks() == nil
            and require("scrollbar.utils").get_scrollbar_marks(globally_hidden_bufnr).search == nil
    end),
    ":nohlsearch should clear search marks"
)
assert_equal(
    nil,
    require("scrollbar.utils").get_scrollbar_marks(globally_hidden_bufnr).search,
    ":nohlsearch should clear search marks from other loaded buffers"
)

vim.api.nvim_feedkeys(vim.keycode("/preview<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 2, 3 }, mark_lines())
    end),
    "a new accepted search should restore hidden marks"
)

vim.o.hlsearch = false
assert(
    vim.wait(1000, function()
        return search_marks() == nil
    end),
    "set nohlsearch should clear search marks"
)
vim.o.hlsearch = true

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("/preview<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 2, 3 }, mark_lines())
    end),
    "search marks should return after hlsearch is re-enabled"
)

search.clear()
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
assert_equal({ 2, 3 }, mark_lines(), "cursor movement should restore newly visible native highlighting")

vim.fn.setreg("/", "accepted")
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
assert_equal({ 1 }, mark_lines(), "cursor movement should refresh a changed native search pattern")
vim.fn.setreg("/", "preview")
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
assert_equal({ 2, 3 }, mark_lines(), "cursor movement should restore the active pattern for later checks")

local scrollbar_marks = require("scrollbar.utils").get_scrollbar_marks(0)
scrollbar_marks.search = { { line = 99, text = "-", type = "Search", level = 1 } }
require("scrollbar.utils").set_scrollbar_marks(0, scrollbar_marks)
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
assert_equal({ 99 }, mark_lines(), "ordinary cursor movement should not rescan visible searches")
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = 0 })
assert_equal({ 2, 3 }, mark_lines(), "insert-mode edits should refresh accepted search marks")

vim.fn.setreg("/", "")
vim.api.nvim_exec_autocmds("CursorMoved", { buffer = 0 })
assert_equal(nil, search_marks(), "an empty accepted pattern should clear search marks")

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("/preview<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 2, 3 }, mark_lines())
    end),
    "accepted marks should be available before changing buffers"
)

local hidden_bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(hidden_bufnr, 0, -1, false, { "preview" })
local entered_bufnr = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(entered_bufnr, 0, -1, false, { "start", "preview preview" })
vim.api.nvim_win_set_buf(0, entered_bufnr)
assert_equal({ 1, 1 }, mark_lines(), "BufWinEnter should refresh the newly visible buffer")
assert_equal(
    nil,
    require("scrollbar.utils").get_scrollbar_marks(hidden_bufnr).search,
    "hidden buffers should not be scanned eagerly"
)

vim.api.nvim_buf_set_lines(0, 1, 2, false, { "preview" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = 0 })
assert_equal({ 1 }, mark_lines(), "visible buffer edits should replace stale search marks")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "old old", "unique" })
vim.fn.setreg("/", "old")
vim.api.nvim_exec_autocmds("SafeState", {})
assert_equal({ 0, 0 }, mark_lines(), "SafeState should synchronize the current accepted pattern")
vim.api.nvim_win_set_cursor(0, { 2, 0 })
local unique_cursor = vim.api.nvim_win_get_cursor(0)
pcall(vim.cmd, "normal! *")
assert_equal(unique_cursor, vim.api.nvim_win_get_cursor(0), "a failed unique-word search should not move the cursor")
vim.api.nvim_exec_autocmds("SafeState", {})
assert_equal({ 1 }, mark_lines(), "SafeState should detect normal searches that do not move the cursor")

vim.api.nvim_buf_set_lines(0, 0, -1, false, { "foo", "Foo" })
vim.fn.setreg("/", "foo")
vim.api.nvim_exec_autocmds("SafeState", {})
assert_equal({ 0 }, mark_lines(), "case-sensitive state should start with one match")
vim.o.ignorecase = true
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 0, 1 }, mark_lines())
    end),
    "match-affecting option changes should refresh search marks"
)
vim.o.ignorecase = false
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 0 }, mark_lines())
    end),
    "restoring match-affecting options should refresh search marks"
)

require("scrollbar").setup({ handlers = { search = { live = false } } })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "start", "root", "root" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode("/root<CR>"), "xt", false)
assert(
    vim.wait(1000, function()
        return vim.deep_equal({ 1, 2 }, mark_lines())
    end),
    "root { live = false } setup should process accepted searches"
)

print("search_spec: ok")
