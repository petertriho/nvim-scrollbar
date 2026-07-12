local M = { name = "search" }

---@class ScrollbarSearchCommandlineState
---@field bufnr integer
---@field pattern string
---@field visible boolean

---@type ScrollbarProviderContext?
local active_context

---@type ScrollbarSearchProviderConfig
local options = { live = false }

---@type ScrollbarSearchCommandlineState?
local commandline

---@type table<integer, string>
local scanned_signatures = {}

local function search_is_visible()
    return vim.o.hlsearch and vim.v.hlsearch ~= 0 and vim.fn.getreg("/") ~= ""
end

---@param bufnr integer
---@param pattern string
---@return string
local function search_signature(bufnr, pattern)
    return table.concat({
        pattern,
        tostring(vim.o.ignorecase),
        tostring(vim.o.smartcase),
        tostring(vim.o.magic),
        vim.bo[bufnr].iskeyword,
    }, "\0")
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@return integer?
local function source_window(context, bufnr)
    local current = vim.api.nvim_get_current_win()
    if
        vim.api.nvim_win_is_valid(current)
        and vim.api.nvim_win_get_config(current).relative == ""
        and vim.api.nvim_win_get_buf(current) == bufnr
    then
        return current
    end

    for _, winid in ipairs(context.source_windows(bufnr)) do
        if vim.api.nvim_win_is_valid(winid) then
            return winid
        end
    end
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@param pattern string
---@return ScrollbarMark[]?
local function scan(context, bufnr, pattern)
    local winid = source_window(context, bufnr)
    if winid == nil then
        return nil
    end

    local call_ok, scan_result = pcall(vim.api.nvim_win_call, winid, function()
        local view = vim.fn.winsaveview()
        local ok, result = pcall(function()
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

            local marks = {}
            for index, position in ipairs(matches) do
                marks[index] = { line = position[1] - 1, type = "Search" }
            end
            return marks
        end)
        vim.fn.winrestview(view)
        return { ok, result }
    end)

    if not call_ok or not scan_result[1] then
        return nil
    end
    return scan_result[2]
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function clear_buffer(context, bufnr)
    scanned_signatures[bufnr] = nil
    context.clear_marks(bufnr)
end

---@param context ScrollbarProviderContext
local function clear_all(context)
    scanned_signatures = {}
    context.clear_marks()
end

---@param context ScrollbarProviderContext
---@param bufnr integer
---@param pattern string
---@param ignore_visibility? boolean
---@return boolean
local function refresh_pattern(context, bufnr, pattern, ignore_visibility)
    if pattern == "" or (not ignore_visibility and not search_is_visible()) then
        clear_buffer(context, bufnr)
        return false
    end

    if source_window(context, bufnr) == nil then
        return false
    end

    local marks = scan(context, bufnr, pattern)
    if marks == nil then
        clear_buffer(context, bufnr)
        return false
    end

    if context.set_marks(bufnr, marks) then
        scanned_signatures[bufnr] = search_signature(bufnr, pattern)
        return true
    end
    return false
end

---@param context ScrollbarProviderContext
---@param bufnr? integer
local function sync_visibility(context, bufnr)
    if not search_is_visible() then
        clear_all(context)
        return
    end

    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local pattern = vim.fn.getreg("/")
    if scanned_signatures[bufnr] ~= search_signature(bufnr, pattern) then
        refresh_pattern(context, bufnr, pattern)
    end
end

---@param context ScrollbarProviderContext
---@param callback fun()
local function schedule(context, callback)
    vim.schedule(function()
        if active_context == context then
            callback()
        end
    end)
end

---@param context ScrollbarProviderContext
function M.setup(context)
    local search_options = context.config.providers.search
    if search_options == false then
        error("search provider cannot be set up while disabled")
    end

    active_context = context
    options = search_options
    commandline = nil
    scanned_signatures = {}

    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("CmdlineEnter", {
        group = group,
        pattern = { "/", "?" },
        callback = function()
            commandline = {
                bufnr = vim.api.nvim_get_current_buf(),
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
                refresh_pattern(context, vim.api.nvim_get_current_buf(), vim.fn.getcmdline(), true)
            end
        end,
    })
    vim.api.nvim_create_autocmd("CmdlineLeave", {
        group = group,
        callback = function(args)
            local cmdtype = args.match
            local aborted = vim.v.event.abort == true or vim.v.event.abort == 1
            local previous = commandline
            local bufnr = vim.api.nvim_get_current_buf()
            commandline = nil

            schedule(context, function()
                if commandline ~= nil then
                    return
                end
                if cmdtype ~= "/" and cmdtype ~= "?" then
                    sync_visibility(context, bufnr)
                elseif aborted and previous ~= nil then
                    if previous.visible and previous.pattern ~= "" then
                        refresh_pattern(context, previous.bufnr, previous.pattern, true)
                    else
                        clear_buffer(context, previous.bufnr)
                    end
                else
                    refresh_pattern(context, bufnr, vim.fn.getreg("/"))
                end
            end)
        end,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = group,
        callback = function(args)
            refresh_pattern(context, args.buf, vim.fn.getreg("/"))
        end,
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = group,
        callback = function(args)
            refresh_pattern(context, args.buf, vim.fn.getreg("/"))
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(args)
            scanned_signatures[args.buf] = nil
            if commandline ~= nil and commandline.bufnr == args.buf then
                commandline = nil
            end
        end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "SafeState" }, {
        group = group,
        callback = function(args)
            sync_visibility(context, args.buf)
        end,
    })
    vim.api.nvim_create_autocmd("OptionSet", {
        group = group,
        pattern = { "hlsearch", "ignorecase", "smartcase", "magic", "iskeyword" },
        callback = function(args)
            local bufnr = args.buf
            schedule(context, function()
                sync_visibility(context, bufnr)
            end)
        end,
    })
end

---@param bufnr integer
---@param context ScrollbarProviderContext
function M.refresh(bufnr, context)
    refresh_pattern(context, bufnr, vim.fn.getreg("/"))
end

---@param context ScrollbarProviderContext
function M.dispose(context)
    if active_context ~= context then
        return
    end
    active_context = nil
    commandline = nil
    scanned_signatures = {}
end

return M
