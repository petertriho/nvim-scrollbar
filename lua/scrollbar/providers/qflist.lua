local list_marks = require("scrollbar.providers.list_marks")

local OWN_TYPE = "Qflist"

---@class ScrollbarQflistPublished
---@field line_count integer The line count of the buffer at publication
---@field changedtick integer The changedtick of the buffer at publication

local state = {
    ---@type ScrollbarProviderContext?
    context = nil,
    -- The signature of the collected list. `:colder` and `:cnewer` change only
    -- `id`. A new list, or a change of the current list, changes
    -- `changedtick`.
    ---@type integer?
    id = nil,
    ---@type integer?
    changedtick = nil,
    ---@type table<integer, ScrollbarMark[]>
    marks = {},
    -- The buffers with published marks. When lines are inserted or deleted
    -- above the entries, Neovim moves the entries but keeps the changedtick of
    -- the list. Thus a new line count of such a buffer also starts a
    -- collection.
    ---@type table<integer, ScrollbarQflistPublished>
    published = {},
    -- The line counts that started the pending timer.
    ---@type string?
    pending = nil,
    ---@type ScrollbarListTimer?
    timer = nil,
}

---@param context? ScrollbarProviderContext
local function reset(context)
    if state.timer ~= nil then
        state.timer.close()
    end
    state.context = context
    state.id = nil
    state.changedtick = nil
    state.marks = {}
    state.published = {}
    state.pending = nil
    state.timer = nil
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function publish(context, bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then
        state.published[bufnr] = nil
        return
    end
    local marks = state.marks[bufnr]
    -- set_marks clears the marks of a buffer that is not eligible.
    if marks ~= nil and context.set_marks(bufnr, marks) then
        state.published[bufnr] = {
            line_count = vim.api.nvim_buf_line_count(bufnr),
            changedtick = vim.api.nvim_buf_get_changedtick(bufnr),
        }
        return
    end
    state.published[bufnr] = nil
    context.clear_marks(bufnr)
end

--- Read the current list, then publish the buffers whose marks can change.
---@param context ScrollbarProviderContext
local function collect(context)
    if state.timer ~= nil then
        state.timer.stop()
    end
    state.pending = nil
    local list = vim.fn.getqflist({ id = 0, changedtick = 0, items = 0 })
    local previous = state.published
    state.id = list.id
    state.changedtick = list.changedtick
    state.marks = list_marks.by_buffer(list.items or {}, list_marks.types(context.config.providers.qflist), OWN_TYPE)
    state.published = {}

    local affected = {}
    for bufnr in pairs(previous) do
        affected[bufnr] = true
    end
    -- An unloaded buffer is not eligible. BufWinEnter publishes it when it
    -- loads.
    for bufnr in pairs(state.marks) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            affected[bufnr] = true
        end
    end
    local ordered = vim.tbl_keys(affected)
    table.sort(ordered)
    for _, bufnr in ipairs(ordered) do
        publish(context, bufnr)
    end
end

--- Whether the current list is another list, or changed, since the last
--- collection. The check reads no entries.
---@return boolean
local function list_changed()
    local info = vim.fn.getqflist({ id = 0, changedtick = 0 })
    return info.id ~= state.id or info.changedtick ~= state.changedtick
end

--- The new line counts of the buffers with published marks, or nil when no
--- line count changed.
---@return string?
local function moved_lines()
    local key
    for bufnr, published in pairs(state.published) do
        local line_count = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_line_count(bufnr) or -1
        if line_count ~= published.line_count then
            key = (key and key .. "," or "") .. bufnr .. ":" .. line_count
        end
    end
    return key
end

--- Collect at once after a change of the list. After a change of only the line
--- counts, collect when the line counts stay the same for the delay.
---@param context ScrollbarProviderContext
local function check(context)
    if list_changed() then
        collect(context)
        return
    end
    local moved = moved_lines()
    if moved == state.pending then
        return
    end
    state.pending = moved
    local timer = assert(state.timer, "qflist timer is missing")
    if moved == nil then
        timer.stop()
    else
        timer.restart()
    end
end

---@type ScrollbarProvider
return {
    name = "qflist",
    targets = { scrollbar = true, minimap = true },
    refresh_owner = { buffer = "provider" },
    setup = function(context)
        reset(context)
        state.timer = list_marks.timer(list_marks.LINE_MOVE_DELAY_MS, function()
            if state.context == context and (list_changed() or moved_lines() ~= nil) then
                collect(context)
            end
        end)
        local group = context.create_augroup("events")
        -- setqflist(), `:colder`, and `:cnewer` fire no event, so SafeState
        -- compares the signature of the list. The check costs one
        -- getqflist() call without the entries.
        vim.api.nvim_create_autocmd({ "QuickFixCmdPost", "SafeState" }, {
            group = group,
            callback = function()
                check(context)
            end,
            desc = "Update scrollbar quickfix marks",
        })
        vim.api.nvim_create_autocmd("BufWinEnter", {
            group = group,
            callback = function(args)
                check(context)
                if state.marks[args.buf] ~= nil or state.published[args.buf] ~= nil then
                    publish(context, args.buf)
                end
            end,
            desc = "Update scrollbar quickfix marks",
        })
    end,
    refresh = function(bufnr, context)
        -- A manual refresh collects at once. It also catches an edit that
        -- keeps the line count, such as `:move`.
        local published = state.published[bufnr]
        if
            list_changed()
            or moved_lines() ~= nil
            or (published ~= nil and vim.api.nvim_buf_get_changedtick(bufnr) ~= published.changedtick)
        then
            collect(context)
        end
        publish(context, bufnr)
        return nil
    end,
    dispose = function(context)
        context.clear_marks()
        reset(nil)
    end,
}
