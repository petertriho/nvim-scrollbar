local utils = require("scrollbar.utils")
local render = require("scrollbar").throttled_render

local M = {}

M.handler = {
    show = function(bufnr)
        local config = require("scrollbar.config").get()

        local line = vim.fn.line(".") - 1
        bufnr = bufnr or vim.api.nvim_get_current_buf()

        local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
        scrollbar_marks.cursor = {
            {
                line = line,
                text = config.marks["Cursor"].text,
                type = "Cursor",
                level = 1,
            },
        }
        utils.set_scrollbar_marks(bufnr, scrollbar_marks)
        render()
    end,
    hide = function(bufnr)
        bufnr = bufnr or vim.api.nvim_get_current_buf()
        local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
        if scrollbar_marks.cursor then
            scrollbar_marks.cursor = nil
            utils.set_scrollbar_marks(bufnr, scrollbar_marks)
            render()
        end
    end,
}

M.setup = function()
    local config = require("scrollbar.config").get()
    config.handlers.cursor = true

    local augroup = vim.api.nvim_create_augroup("ScrollbarCursor", {})
    vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI", "CursorMoved", "CursorMovedI" }, {
        group = augroup,
        callback = function(event)
            M.handler.show(event.buf)
        end,
        desc = "Render scrollbar cursor",
    })
end

return M
