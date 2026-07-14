local LOWERCASE_START = string.byte("a")
local LOWERCASE_END = string.byte("z")
local UPPERCASE_START = string.byte("A")
local UPPERCASE_END = string.byte("Z")
local NUMBERED_START = string.byte("0")
local NUMBERED_END = string.byte("9")

---@param bufnr integer
---@param context ScrollbarProviderContext
---@return boolean
local function is_buffer_eligible(bufnr, context)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        return false
    end
    if vim.tbl_contains(context.config.excluded_buftypes, vim.bo[bufnr].buftype) then
        return false
    end
    if vim.tbl_contains(context.config.excluded_filetypes, vim.bo[bufnr].filetype) then
        return false
    end
    if context.config.max_lines and vim.api.nvim_buf_line_count(bufnr) > context.config.max_lines then
        return false
    end
    return true
end

---@param marks ScrollbarMark[]
---@param line_count integer
---@param row integer
---@param name string
local function add_mark(marks, line_count, row, name)
    if row > 0 and row <= line_count then
        table.insert(marks, { line = row - 1, type = "Mark", text = name })
    end
end

---@param bufnr integer
---@param context ScrollbarProviderContext
---@return ScrollbarMark[]?
local function collect(bufnr, context)
    if not is_buffer_eligible(bufnr, context) then
        return nil
    end

    local marks = {}
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local provider_config = context.config.providers.marks
    if provider_config == false then
        return nil
    end
    if provider_config.letters then
        for byte = LOWERCASE_START, LOWERCASE_END do
            local name = string.char(byte)
            local position = vim.api.nvim_buf_get_mark(bufnr, name)
            add_mark(marks, line_count, position[1], name)
        end
        for byte = UPPERCASE_START, UPPERCASE_END do
            local name = string.char(byte)
            local position = vim.api.nvim_get_mark(name, {})
            if position[3] == bufnr then
                add_mark(marks, line_count, position[1], name)
            end
        end
    end
    if provider_config.numbers then
        for byte = NUMBERED_START, NUMBERED_END do
            local name = string.char(byte)
            local position = vim.api.nvim_get_mark(name, {})
            if position[3] == bufnr then
                add_mark(marks, line_count, position[1], name)
            end
        end
    end

    table.sort(marks, function(left, right)
        if left.line == right.line then
            return left.text < right.text
        end
        return left.line < right.line
    end)
    return marks
end

---@param bufnr integer
---@param context ScrollbarProviderContext
local function update(bufnr, context)
    local marks = collect(bufnr, context)
    if marks == nil or #marks == 0 then
        context.clear_marks(bufnr)
    else
        context.set_marks(bufnr, marks)
    end
end

---@param context ScrollbarProviderContext
local function reconcile_source_buffers(context)
    local seen = {}
    for _, winid in ipairs(context.source_windows()) do
        if vim.api.nvim_win_is_valid(winid) then
            local bufnr = vim.api.nvim_win_get_buf(winid)
            if not seen[bufnr] then
                seen[bufnr] = true
                update(bufnr, context)
            end
        end
    end
end

local function has_complete_mark_set_events()
    local version = vim.version()
    return version.major > 0 or version.minor > 12 or (version.minor == 12 and version.patch >= 2)
end

---@param context ScrollbarProviderContext
---@return string?
local function mark_set_pattern(context)
    local provider_config = context.config.providers.marks
    if provider_config == false then
        return nil
    end
    local names = ""
    if provider_config.letters then
        names = names .. "a-zA-Z"
    end
    if provider_config.numbers then
        names = names .. "0-9"
    end
    if names == "" then
        return nil
    end
    return "[" .. names .. "]"
end

---@type ScrollbarProvider
return {
    name = "marks",
    setup = function(context)
        local group = context.create_augroup("events")
        vim.api.nvim_create_autocmd(
            { "BufEnter", "BufWinEnter", "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" },
            {
                group = group,
                callback = function(args)
                    update(args.buf, context)
                end,
                desc = "Update scrollbar marks",
            }
        )

        local pattern = mark_set_pattern(context)
        if pattern == nil then
            return
        end

        local has_mark_set = has_complete_mark_set_events()
        if has_mark_set then
            vim.api.nvim_create_autocmd("MarkSet", {
                group = group,
                pattern = pattern,
                callback = function()
                    reconcile_source_buffers(context)
                end,
                desc = "Reconcile scrollbar marks",
            })
        end

        local provider_config = context.config.providers.marks
        if not has_mark_set or (provider_config ~= false and provider_config.numbers) then
            vim.api.nvim_create_autocmd("SafeState", {
                group = group,
                callback = function()
                    reconcile_source_buffers(context)
                end,
                desc = "Reconcile scrollbar marks",
            })
        end
    end,
    refresh = function(bufnr, context)
        local marks = collect(bufnr, context)
        if marks == nil or #marks == 0 then
            context.clear_marks(bufnr)
            return nil
        end
        return marks
    end,
    dispose = function(context)
        context.clear_marks()
    end,
}
