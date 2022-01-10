local utils = require("scrollbar.utils")

local M = {}
M.handlers = {}

-- Register a function that returns marks for a given buffer
--
-- @param name Name of the handler
-- @param lines_fun function that maps bufnr -> list of marks
-- @param text marker text
-- @param type marker type as defined in config
-- @param level mark level
function M.register(name, lines_fun, text, type, level)
    M.handlers = vim.tbl_deep_extend(
        "force",
        M.handlers,
        { {
            name = name,
            lines_fun = lines_fun,
            text = text or "-",
            type = type or "Misc",
            level = level or 1
        } }
    )
end

function M.show()
    local bufnr = vim.api.nvim_get_current_buf()
    local scrollbar_marks = utils.get_scrollbar_marks(bufnr)

    for _, handler in ipairs(M.handlers) do
        local handler_scrollbar_marks = {}
        for _, result in pairs(handler.lines_fun(bufnr)) do
            table.insert(handler_scrollbar_marks, {
                line = result,
                text = handler.text,
                type = handler.type,
                level = handler.level,
            })
        end
        scrollbar_marks[handler.name] = handler_scrollbar_marks
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
