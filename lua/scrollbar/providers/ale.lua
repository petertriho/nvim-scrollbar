local M = {
    name = "ale",
    targets = { scrollbar = true, minimap = true },
    refresh_owner = { buffer = "provider" },
}

local state = {
    context = nil,
}

---@param bufnr integer
---@return ScrollbarMark[]
local function collect_marks(bufnr)
    local buffer_info = vim.g.ale_buffer_info
    if type(buffer_info) ~= "table" then
        return {}
    end

    local info = buffer_info[tostring(bufnr)]
    if type(info) ~= "table" or type(info.loclist) ~= "table" then
        return {}
    end

    local marks = {}
    for _, entry in pairs(info.loclist) do
        table.insert(marks, {
            line = entry.lnum - 1,
            type = entry.type == "E" and "Error" or "Warn",
        })
    end
    return marks
end

---@param context ScrollbarProviderContext
M.setup = function(context)
    state.context = context
    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "ALELintPost",
        desc = "Update scrollbar ALE marks",
        callback = function(args)
            if state.context ~= context then
                return
            end
            local bufnr = args.buf ~= 0 and args.buf or vim.api.nvim_get_current_buf()
            if not context.is_buffer_eligible(bufnr) then
                context.clear_marks(bufnr)
                return
            end
            local ok, marks = pcall(collect_marks, bufnr)
            if ok then
                context.set_marks(bufnr, marks)
            else
                context.clear_marks(bufnr)
            end
        end,
    })
end

---@param bufnr integer
---@return ScrollbarMark[]
M.refresh = function(bufnr)
    return collect_marks(bufnr)
end

M.dispose = function()
    state.context = nil
end

return M
