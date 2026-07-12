local SEVERITY_TYPES = {
    [vim.diagnostic.severity.ERROR] = "Error",
    [vim.diagnostic.severity.WARN] = "Warn",
    [vim.diagnostic.severity.INFO] = "Info",
    [vim.diagnostic.severity.HINT] = "Hint",
}

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

---@param bufnr integer
---@param context ScrollbarProviderContext
---@return ScrollbarMark[]?
local function collect(bufnr, context)
    if not is_buffer_eligible(bufnr, context) then
        return nil
    end

    local marks = {}
    for _, diagnostic in ipairs(vim.diagnostic.get(bufnr)) do
        table.insert(marks, {
            line = diagnostic.lnum,
            type = SEVERITY_TYPES[diagnostic.severity] or "Misc",
        })
    end
    table.sort(marks, function(left, right)
        if left.line == right.line then
            return left.type < right.type
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

---@type ScrollbarProvider
return {
    name = "diagnostic",
    setup = function(context)
        local group = context.create_augroup("events")
        vim.api.nvim_create_autocmd("DiagnosticChanged", {
            group = group,
            callback = function(args)
                update(args.buf, context)
            end,
            desc = "Update scrollbar diagnostic marks",
        })
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
