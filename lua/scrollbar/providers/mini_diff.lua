local M = { name = "mini_diff" }

---@class ScrollbarMiniDiffHunk
---@field type string
---@field buf_start integer
---@field buf_count integer

---@class ScrollbarMiniDiffBufferData
---@field hunks? ScrollbarMiniDiffHunk[]

---@class ScrollbarMiniDiffModule
---@field get_buf_data fun(bufnr: integer): ScrollbarMiniDiffBufferData?

---@type { module: ScrollbarMiniDiffModule?, context: ScrollbarProviderContext? }
local state = {
    module = nil,
    context = nil,
}

---@return ScrollbarMiniDiffModule?
local function get_module()
    local loaded = package.loaded["mini.diff"]
    if state.module == nil and type(loaded) == "table" then
        state.module = loaded
    end
    return state.module
end

local MARK_TYPES = {
    add = "MiniDiffAdd",
    change = "MiniDiffChange",
    delete = "MiniDiffDelete",
}

---@param bufnr integer
---@return ScrollbarMark[]
local function collect_marks(bufnr)
    local mini_diff = get_module()
    if mini_diff == nil then
        return {}
    end

    local data = mini_diff.get_buf_data(bufnr)
    if data == nil then
        return {}
    end

    local marks = {}
    for _, hunk in ipairs(data.hunks or {}) do
        local mark_type = MARK_TYPES[hunk.type]
        if mark_type ~= nil then
            local range_from = math.max(hunk.buf_start, 1)
            local range_count = math.max(hunk.buf_count, 1)
            for line = range_from, range_from + range_count - 1 do
                table.insert(marks, { line = line - 1, type = mark_type })
            end
        end
    end
    return marks
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function update_buffer(context, bufnr)
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
end

---@param context ScrollbarProviderContext
M.setup = function(context)
    state.context = context
    local ok, mini_diff = pcall(require, "mini.diff")
    state.module = ok and mini_diff or nil

    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("User", {
        group = group,
        pattern = "MiniDiffUpdated",
        desc = "Update scrollbar mini.diff marks",
        callback = function(args)
            if state.context ~= context or not vim.api.nvim_buf_is_valid(args.buf) then
                return
            end
            update_buffer(context, args.buf)
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
