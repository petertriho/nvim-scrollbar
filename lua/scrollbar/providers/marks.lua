local LOWERCASE_START = string.byte("a")
local LOWERCASE_END = string.byte("z")
local UPPERCASE_START = string.byte("A")
local UPPERCASE_END = string.byte("Z")
local NUMBERED_START = string.byte("0")
local NUMBERED_END = string.byte("9")

--- Line count each buffer was last reconciled at. Text edits can only move
--- mark lines when the number of lines changes (inserts/deletes above them);
--- ordinary keystrokes leave counts stable and skip the reconcile entirely.
--- MarkSet and SafeState still reconcile unconditionally.
local reconciled_line_counts = {}

---@param marks ScrollbarMark[]
---@param line_count integer
---@param row integer
---@param name string
local function add_mark(marks, line_count, row, name)
    if row > 0 and row <= line_count then
        table.insert(marks, { line = row - 1, type = "Mark", text = name })
    end
end

---@param entry table getmarklist entry { mark: "'a", pos: [line, col, bufnr] }
---@return string? name
local function entry_name(entry)
    local name = entry.mark
    if type(name) == "string" then
        name = name:sub(2)
        if #name == 1 then
            return name
        end
    end
    return nil
end

---@param byte integer
---@return boolean
local function is_lowercase_name(name)
    local byte = name:byte()
    return byte >= LOWERCASE_START and byte <= LOWERCASE_END
end

---@param name string
---@return boolean
local function is_uppercase_name(name)
    local byte = name:byte()
    return byte >= UPPERCASE_START and byte <= UPPERCASE_END
end

---@param name string
---@return boolean
local function is_numbered_name(name)
    local byte = name:byte()
    return byte >= NUMBERED_START and byte <= NUMBERED_END
end

---@param bufnr integer
---@param context ScrollbarProviderContext
---@return ScrollbarMark[]?
local function collect(bufnr, context)
    if not context.is_buffer_eligible(bufnr) then
        return nil
    end

    local marks = {}
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local provider_config = context.config.providers.marks
    if provider_config == false then
        return nil
    end
    -- One getmarklist call per scope replaces one nvim_get_mark call per
    -- letter (62 API round-trips and their per-call table allocations on
    -- every reconcile).
    local wants_letter = provider_config.letters == true
    local wants_number = provider_config.numbers == true
    if wants_letter then
        for _, entry in ipairs(vim.fn.getmarklist(bufnr)) do
            local name = entry_name(entry)
            if name ~= nil and is_lowercase_name(name) then
                add_mark(marks, line_count, entry.pos[2], name)
            end
        end
    end
    if wants_letter or wants_number then
        for _, entry in ipairs(vim.fn.getmarklist()) do
            local pos = entry.pos
            if pos[1] == bufnr then
                local name = entry_name(entry)
                if name ~= nil then
                    local wanted_name = is_uppercase_name(name) and wants_letter
                        or (is_numbered_name(name) and wants_number)
                    if wanted_name then
                        add_mark(marks, line_count, pos[2], name)
                    end
                end
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
    if not vim.api.nvim_buf_is_valid(bufnr) then
        reconciled_line_counts[bufnr] = nil
        return
    end
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local marks = collect(bufnr, context)
    reconciled_line_counts[bufnr] = line_count
    if marks == nil or #marks == 0 then
        context.clear_marks(bufnr)
    else
        context.set_marks(bufnr, marks)
    end
end

---Text changes can only move mark lines when the buffer's line count
---changes; keystrokes that keep the count skip the reconcile. MarkSet and
---SafeState reconcile unconditionally, so mark creation and exotic edits
---stay covered.
---@param bufnr integer
---@param context ScrollbarProviderContext
local function update_after_text_change(bufnr, context)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        reconciled_line_counts[bufnr] = nil
        return
    end
    if reconciled_line_counts[bufnr] == vim.api.nvim_buf_line_count(bufnr) then
        return
    end
    update(bufnr, context)
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
    targets = { scrollbar = true, minimap = true },
    refresh_owner = { buffer = "provider" },
    setup = function(context)
        local group = context.create_augroup("events")
        -- Eligibility events re-establish publication state unconditionally;
        -- text-change events only need reconciliation when the buffer's line
        -- count changed (the only way typing can move mark lines).
        vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
            group = group,
            callback = function(args)
                update(args.buf, context)
            end,
            desc = "Update scrollbar marks",
        })
        local text_change_events = { "TextChanged", "TextChangedI", "TextChangedP", "TextChangedT" }
        if type(context.on_text_change) == "function" then
            -- Ride the scheduler's TextChanged dispatch: one autocmd
            -- invocation per keystroke covers scheduling and reconciliation.
            context.on_text_change(function(args)
                update_after_text_change(args.buf, context)
            end, text_change_events)
        else
            vim.api.nvim_create_autocmd(text_change_events, {
                group = group,
                callback = function(args)
                    update_after_text_change(args.buf, context)
                end,
                desc = "Update scrollbar marks",
            })
        end

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
        reconciled_line_counts = {}
    end,
}
