--- A change counter for the text of a buffer. `b:changedtick` also increases
--- when a write resets 'modified', so a result keyed by changedtick goes stale
--- on every `:w` of a modified buffer. The text tick is changedtick minus the
--- increases that came only from writes, so it changes only with the text.
---
--- A write that increases changedtick by exactly one and leaves the buffer
--- unmodified changed no text. A text change marks the buffer modified, so a
--- text change between `BufWritePre` and `BufWritePost` makes the write reset
--- 'modified' too, and the increase is at least two. This holds when a
--- `BufWritePre` autocmd formats the buffer before or after the one here.

local M = {}

local AUGROUP_NAME = "ScrollbarTextTick"

---@type table<integer, integer> Increases of changedtick that came only from writes
local write_increases = {}
---@type table<integer, integer> changedtick at `BufWritePre`
local before_write = {}

---@param bufnr integer 0 for the current buffer
---@return integer
M.get = function(bufnr)
    if bufnr == 0 then
        bufnr = vim.api.nvim_get_current_buf()
    end
    return vim.api.nvim_buf_get_changedtick(bufnr) - (write_increases[bufnr] or 0)
end

M.setup = function()
    M.dispose()
    local group = vim.api.nvim_create_augroup(AUGROUP_NAME, { clear = true })
    vim.api.nvim_create_autocmd("BufWritePre", {
        group = group,
        callback = function(args)
            before_write[args.buf] = vim.api.nvim_buf_get_changedtick(args.buf)
        end,
    })
    vim.api.nvim_create_autocmd("BufWritePost", {
        group = group,
        callback = function(args)
            local bufnr = args.buf
            local before = before_write[bufnr]
            before_write[bufnr] = nil
            if
                before ~= nil
                and not vim.bo[bufnr].modified
                and vim.api.nvim_buf_get_changedtick(bufnr) == before + 1
            then
                write_increases[bufnr] = (write_increases[bufnr] or 0) + 1
            end
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        callback = function(args)
            write_increases[args.buf] = nil
            before_write[args.buf] = nil
        end,
    })
end

M.dispose = function()
    pcall(vim.api.nvim_del_augroup_by_name, AUGROUP_NAME)
    write_increases = {}
    before_write = {}
end

return M
