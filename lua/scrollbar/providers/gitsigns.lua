local M = { name = "gitsigns" }

---@class ScrollbarGitsignsModule
---@field get_hunks fun(bufnr: integer): table[]?

---@type { module: ScrollbarGitsignsModule?, context: ScrollbarProviderContext? }
local state = {
    module = nil,
    context = nil,
}

---@param bufnr integer
---@return ScrollbarMark[]
local function collect_marks(bufnr)
    if state.module == nil then
        return {}
    end

    local marks = {}
    local hunks = state.module.get_hunks(bufnr) or {}
    for _, hunk in ipairs(hunks) do
        if hunk.type == "add" then
            for line = hunk.added.start, hunk.added.start + hunk.added.count - 1 do
                table.insert(marks, { line = line - 1, type = "GitAdd" })
            end
        elseif hunk.type == "change" then
            local added_end = hunk.added.start + hunk.added.count - hunk.removed.count + 1
            for line = hunk.added.start + hunk.removed.count, added_end do
                table.insert(marks, { line = line - 1, type = "GitAdd" })
            end
            for line = hunk.added.start, hunk.added.start + hunk.removed.count - 1 do
                table.insert(marks, { line = line - 1, type = "GitChange" })
            end
        elseif hunk.type == "delete" then
            table.insert(marks, { line = hunk.added.start - 1, type = "GitDelete" })
        end
    end
    return marks
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function update_buffer(context, bufnr)
    local ok, marks = pcall(collect_marks, bufnr)
    if ok then
        context.set_marks(bufnr, marks)
    else
        context.clear_marks(bufnr)
    end
end

---@param context ScrollbarProviderContext
---@param args table
local function update_affected_buffers(context, args)
    local buffers = {}
    local data = type(args.data) == "table" and args.data or {}
    local event_buffer = data.buffer or data.bufnr
    if type(event_buffer) == "number" and vim.api.nvim_buf_is_valid(event_buffer) then
        buffers[event_buffer] = true
    else
        for _, winid in ipairs(context.source_windows()) do
            local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
            if ok then
                buffers[bufnr] = true
            end
        end
    end

    local ordered = vim.tbl_keys(buffers)
    table.sort(ordered)
    for _, bufnr in ipairs(ordered) do
        update_buffer(context, bufnr)
    end
end

---@param context ScrollbarProviderContext
M.setup = function(context)
    state.context = context
    local ok, gitsigns = pcall(require, "gitsigns")
    state.module = ok and gitsigns or nil
    if state.module == nil then
        return
    end

    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "GitSignsUpdate",
        desc = "Update scrollbar gitsigns marks",
        callback = function(args)
            if state.context ~= context then
                return
            end
            update_affected_buffers(context, args)
        end,
    })
end

---@param bufnr integer
---@return ScrollbarMark[]
M.refresh = function(bufnr)
    return collect_marks(bufnr)
end

M.dispose = function()
    state.module = nil
    state.context = nil
end

return M
