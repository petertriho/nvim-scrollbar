local utils = require("scrollbar.utils")

local M = {}
M.handlers = {}

-- Register a function that returns marks for a given buffer
-- @param name Name of the handler
-- @param handler Function that maps bufnr -> list of tables { line, text, type, level }
function M.register(name, handler)
    table.insert(M.handlers, {
        name = name,
        handler = handler,
    })
end

function M.show()
    local bufnr = vim.api.nvim_get_current_buf()
    local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
    local config = require("scrollbar.config").get()

    for _, handler_reg in ipairs(M.handlers) do
        local handler_scrollbar_marks = {}
        for _, result in pairs(handler_reg.handler(bufnr)) do
            local mark_type = result.type or "Misc"
            table.insert(handler_scrollbar_marks, {
                line = result.line,
                text = result.text or config.marks[mark_type].text[1],
                type = mark_type,
                level = result.level or 1,
            })
        end
        scrollbar_marks[handler_reg.name] = handler_scrollbar_marks
    end

    utils.set_scrollbar_marks(bufnr, scrollbar_marks)
end

function M.hide()
    local bufnr = vim.api.nvim_get_current_buf()
    local scrollbar_marks = utils.get_scrollbar_marks(bufnr)

    for _, handler in ipairs(M.handlers) do
        scrollbar_marks[handler.name] = nil
    end

    utils.set_scrollbar_marks(bufnr, scrollbar_marks)
end

return M
