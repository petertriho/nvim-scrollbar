local M = { name = "signify" }

---@type { context: ScrollbarProviderContext? }
local state = {
    context = nil,
}

local MARK_TYPES = {
    SignifyAdd = "SignifyAdd",
    SignifyChange = "SignifyChange",
    SignifyChangeDelete = "SignifyChange",
    SignifyRemoveFirstLine = "SignifyDelete",
    SignifyDeleteMore = "SignifyDelete",
}

---@param name string
---@return string?
local function mark_type_for(name)
    if MARK_TYPES[name] ~= nil then
        return MARK_TYPES[name]
    end
    if name:sub(1, 13) == "SignifyDelete" then -- SignifyDelete<N>
        return "SignifyDelete"
    end
    return nil
end

---@return boolean
local function is_available()
    return vim.g.loaded_signify == 1
end

---@param bufnr integer
---@return ScrollbarMark[]
local function collect_marks(bufnr)
    if not is_available() then
        return {}
    end

    local placed = vim.fn.sign_getplaced(bufnr, { group = "*" })
    local signs = placed[1] and placed[1].signs or {}
    local marks = {}
    for _, sign in ipairs(signs) do
        local mark_type = mark_type_for(sign.name)
        if mark_type ~= nil and type(sign.lnum) == "number" and sign.lnum >= 1 then
            table.insert(marks, { line = sign.lnum - 1, type = mark_type })
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
local function update_affected_buffers(context)
    local buffers = {}
    for _, winid in ipairs(context.source_windows()) do
        local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
        if ok then
            buffers[bufnr] = true
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

    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "Signify",
        desc = "Update scrollbar signify marks",
        callback = function()
            if state.context ~= context then
                return
            end
            update_affected_buffers(context)
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
