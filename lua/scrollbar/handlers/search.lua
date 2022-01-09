local utils = require("scrollbar.utils")
local render = require("scrollbar").render

local M = {}

M.handler = {
    show = function(plist)
        local config = require("scrollbar.config").get()

        if config.handlers.search then
            local search_scrollbar_marks = {}

            for _, result in pairs(plist) do
                table.insert(search_scrollbar_marks, {
                    line = result[1] - 1,
                    text = "-",
                    type = "Search",
                    level = 1,
                })
            end

            local bufnr = vim.api.nvim_get_current_buf()
            local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
            scrollbar_marks.search = search_scrollbar_marks
            utils.set_scrollbar_marks(bufnr, scrollbar_marks)
            render()
        end
    end,
    hide = function()
        if not vim.v.event.abort then
            local cmdl = vim.trim(vim.fn.getcmdline())
            if #cmdl > 2 then
                for _, cl in ipairs(vim.split(cmdl, "|")) do
                    if ("nohlsearch"):match(vim.trim(cl)) then
                        local bufnr = vim.api.nvim_get_current_buf()
                        local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
                        scrollbar_marks.search = nil
                        utils.set_scrollbar_marks(bufnr, scrollbar_marks)
                        render()
                        break
                    end
                end
            end
        end
    end,
}

M.setup = function(overrides)
    local config = require("scrollbar.config").get()
    config.handlers.search = true

    local hlslens_config = vim.tbl_deep_extend("force", {
        build_position_cb = function(plist, _, _, _)
            M.handler.show(plist.start_pos)
        end,
    }, overrides or {})

    require("hlslens").setup(hlslens_config)

    vim.cmd([[
        augroup scrollbar_search_hide
            autocmd!
            autocmd CmdlineLeave : lua require('scrollbar.handlers.search').handler.hide()
        augroup END
    ]])
end

return M
