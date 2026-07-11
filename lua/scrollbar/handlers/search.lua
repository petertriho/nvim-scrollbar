local utils = require("scrollbar.utils")

local M = {}

local AUGROUP = "scrollbar_search"
local options = { live = false }
local commandline
local scanned_patterns = {}

local function render()
    require("scrollbar").throttled_render()
end

local function search_is_visible()
    return vim.o.hlsearch and vim.v.hlsearch ~= 0 and vim.fn.getreg("/") ~= ""
end

local function search_signature(pattern)
    return table.concat({
        pattern,
        tostring(vim.o.ignorecase),
        tostring(vim.o.smartcase),
        tostring(vim.o.magic),
        vim.bo.iskeyword,
    }, "\0")
end

local function scan(pattern)
    local view = vim.fn.winsaveview()
    local ok, positions = pcall(function()
        local matches = {}
        local seen = {}

        local function collect()
            local position = { vim.fn.line("."), vim.fn.col(".") }
            local key = string.format("%d:%d", position[1], position[2])

            if not seen[key] then
                seen[key] = true
                table.insert(matches, position)
            end

            return true
        end

        vim.fn.searchpos(pattern, "Wnc", 0, 0, collect)
        vim.fn.searchpos(pattern, "bWnc", 0, 0, collect)
        table.sort(matches, function(a, b)
            return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
        end)

        return matches
    end)

    vim.fn.winrestview(view)

    if not ok then
        return nil
    end

    return positions
end

local function set_marks(bufnr, positions, pattern)
    local config = require("scrollbar.config").get()
    local text = config.marks.Search.text
    local marks = {}

    if type(text) == "table" then
        text = text[1]
    end

    for _, position in ipairs(positions) do
        table.insert(marks, {
            line = position[1] - 1,
            text = text,
            type = "Search",
            level = 1,
        })
    end

    local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
    scrollbar_marks.search = marks
    utils.set_scrollbar_marks(bufnr, scrollbar_marks)
    scanned_patterns[bufnr] = search_signature(pattern)
    render()
end

local function refresh_pattern(pattern, ignore_visibility)
    if pattern == "" or (not ignore_visibility and not search_is_visible()) then
        M.clear()
        return false
    end

    local positions = scan(pattern)
    if positions == nil then
        M.clear()
        return false
    end

    set_marks(vim.api.nvim_get_current_buf(), positions, pattern)
    return true
end

function M.validate_options(value, allow_disabled)
    if value == nil or value == true then
        return { live = false }
    end

    if value == false and allow_disabled then
        return false
    end

    if type(value) ~= "table" then
        error("[scrollbar.nvim] handlers.search must be false, true, or { live = boolean }", 2)
    end

    for key in pairs(value) do
        if key ~= "live" then
            error(string.format("[scrollbar.nvim] unknown search option %s; expected only 'live'", vim.inspect(key)), 2)
        end
    end

    if value.live ~= nil and type(value.live) ~= "boolean" then
        error("[scrollbar.nvim] handlers.search.live must be a boolean", 2)
    end

    return { live = value.live or false }
end

function M.clear(bufnr, should_render)
    bufnr = bufnr or vim.api.nvim_get_current_buf()

    local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
    scanned_patterns[bufnr] = nil
    if scrollbar_marks.search == nil then
        return false
    end

    scrollbar_marks.search = nil
    utils.set_scrollbar_marks(bufnr, scrollbar_marks)

    if should_render ~= false and bufnr == vim.api.nvim_get_current_buf() then
        render()
    end

    return true
end

function M.clear_all()
    local changed = {}
    local active_winid = vim.api.nvim_get_current_win()
    local active_only = require("scrollbar.config").get().show_in_active_only

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and M.clear(bufnr, false) then
            changed[bufnr] = true
        end
    end

    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(winid) and changed[vim.api.nvim_win_get_buf(winid)] then
            vim.api.nvim_win_call(winid, function()
                if active_only and winid ~= active_winid then
                    require("scrollbar").clear()
                else
                    require("scrollbar").render()
                end
            end)
        end
    end
end

function M.refresh(pattern)
    return refresh_pattern(pattern or vim.fn.getreg("/"), false)
end

function M.sync_visibility()
    local bufnr = vim.api.nvim_get_current_buf()
    local pattern = vim.fn.getreg("/")

    if not search_is_visible() then
        if next(scanned_patterns) then
            M.clear_all()
        else
            M.clear(bufnr)
        end
    elseif scanned_patterns[bufnr] ~= search_signature(pattern) then
        M.refresh(pattern)
    end
end

function M.preview(pattern)
    return refresh_pattern(pattern, true)
end

function M.disable()
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP)
    M.clear_all()
    commandline = nil
    scanned_patterns = {}
end

function M.setup(value)
    local validated = M.validate_options(value, true)
    if validated == false then
        M.disable()
        require("scrollbar.config").get().handlers.search = false
        return
    end

    options = validated
    require("scrollbar.config").get().handlers.search = options

    local group = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
    vim.api.nvim_create_autocmd("CmdlineEnter", {
        group = group,
        pattern = { "/", "?" },
        callback = function()
            commandline = {
                pattern = vim.fn.getreg("/"),
                visible = search_is_visible(),
            }
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineChanged", {
        group = group,
        pattern = { "/", "?" },
        callback = function()
            if options.live then
                M.preview(vim.fn.getcmdline())
            end
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        callback = function(args)
            local cmdtype = args.match
            local aborted = vim.v.event.abort == true or vim.v.event.abort == 1
            local previous = commandline
            commandline = nil

            vim.schedule(function()
                if commandline then
                    return
                elseif cmdtype ~= "/" and cmdtype ~= "?" then
                    M.sync_visibility()
                elseif aborted and previous then
                    if previous.visible and previous.pattern ~= "" then
                        M.preview(previous.pattern)
                    else
                        M.clear()
                    end
                else
                    M.refresh()
                end
            end)
        end,
    })
    vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI" }, {
        group = group,
        callback = function()
            M.refresh()
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "SafeState" }, {
        group = group,
        callback = M.sync_visibility,
    })
    vim.api.nvim_create_autocmd("OptionSet", {
        group = group,
        pattern = { "hlsearch", "ignorecase", "smartcase", "magic", "iskeyword" },
        callback = function()
            vim.schedule(M.sync_visibility)
        end,
    })

    if search_is_visible() then
        M.refresh()
    end
end

return M
