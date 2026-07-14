local M = { name = "coc" }

local SEVERITY_TYPES = {
    Error = "Error",
    Warning = "Warn",
    Information = "Info",
    Hint = "Hint",
}

local state = {
    context = nil,
    generation = 0,
    request_sequence = 0,
    marks = {},
}

---@param diagnostic any
---@return integer? bufnr
---@return ScrollbarMark? mark
local function diagnostic_mark(diagnostic)
    if type(diagnostic) ~= "table" or type(diagnostic.location) ~= "table" then
        return nil, nil
    end

    local location = diagnostic.location
    local mark_type = SEVERITY_TYPES[diagnostic.severity]
    local start = type(location.range) == "table" and location.range.start or nil
    if type(location.uri) ~= "string" or mark_type == nil or type(start) ~= "table" or type(start.line) ~= "number" then
        return nil, nil
    end

    local ok, bufnr = pcall(vim.uri_to_bufnr, location.uri)
    if not ok or not vim.api.nvim_buf_is_valid(bufnr) then
        return nil, nil
    end
    return bufnr, { line = start.line, type = mark_type }
end

---@param context ScrollbarProviderContext
---@param generation integer
---@param request_sequence integer
---@param err any
---@param diagnostic_list any
local function apply_diagnostics(context, generation, request_sequence, err, diagnostic_list)
    if generation ~= state.generation or request_sequence ~= state.request_sequence or context ~= state.context then
        return
    end
    if err ~= nil and err ~= vim.NIL then
        return
    end
    if type(diagnostic_list) ~= "table" then
        diagnostic_list = {}
    end

    local next_marks = {}
    for _, diagnostic in ipairs(diagnostic_list) do
        local bufnr, mark = diagnostic_mark(diagnostic)
        if bufnr ~= nil and mark ~= nil then
            next_marks[bufnr] = next_marks[bufnr] or {}
            table.insert(next_marks[bufnr], mark)
        end
    end

    local affected = {}
    for bufnr in pairs(state.marks) do
        affected[bufnr] = true
    end
    for bufnr in pairs(next_marks) do
        affected[bufnr] = true
    end
    state.marks = next_marks

    local ordered = vim.tbl_keys(affected)
    table.sort(ordered)
    for _, bufnr in ipairs(ordered) do
        context.set_marks(bufnr, next_marks[bufnr] or {})
    end
end

---@param context ScrollbarProviderContext
---@param generation integer
local function request_diagnostics(context, generation)
    state.request_sequence = state.request_sequence + 1
    local request_sequence = state.request_sequence
    pcall(vim.fn.CocActionAsync, "diagnosticList", function(err, diagnostic_list)
        apply_diagnostics(context, generation, request_sequence, err, diagnostic_list)
    end)
end

---@param context ScrollbarProviderContext
M.setup = function(context)
    state.generation = state.generation + 1
    state.context = context
    state.request_sequence = 0
    state.marks = {}
    local generation = state.generation
    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "CocDiagnosticChange",
        desc = "Update scrollbar Coc diagnostics",
        callback = function()
            request_diagnostics(context, generation)
        end,
    })
    request_diagnostics(context, generation)
end

---@param bufnr integer
---@return ScrollbarMark[]
M.refresh = function(bufnr)
    return vim.deepcopy(state.marks[bufnr] or {})
end

M.dispose = function()
    state.generation = state.generation + 1
    state.context = nil
    state.request_sequence = 0
    state.marks = {}
end

return M
