local utils = require("scrollbar.utils")
local render = require("scrollbar").throttled_render

local M = {}

M.handler = {
    show = function(plist)
        local config = require("scrollbar.config").get()

        if config.handlers.search then
            local search_scrollbar_marks = {}

            for _, result in pairs(plist) do
                table.insert(search_scrollbar_marks, {
                    line = result[1] - 1,
                    text = config.marks["Search"].text[1],
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
    hide = function(bufnr)
        bufnr = bufnr or vim.api.nvim_get_current_buf()
        local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
        if scrollbar_marks.search then
            scrollbar_marks.search = nil
            utils.set_scrollbar_marks(bufnr, scrollbar_marks)
            render()
        end
    end,
}

M.hide_all = function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            M.handler.hide(bufnr)
        end
    end
end

M.nohlsearch = function()
    if vim.v.hlsearch == 0 then
        M.hide_all()
        return
    end

    vim.schedule(function()
        local pattern = vim.fn.getreg("/")
        if pattern == "" then
            M.hide_all()
            return
        end
    end)

    if not vim.v.event.abort then
        local cmdl = vim.trim(vim.fn.getcmdline())
        if #cmdl > 2 then
            for _, cl in ipairs(vim.split(cmdl, "|")) do
                if ("nohlsearch"):match(vim.trim(cl)) then
                    M.hide_all()
                    return
                end
            end
        end
    end
end

M.setup = function(overrides)
    local ok, hlslens = pcall(require, "hlslens")

    if not ok then
        vim.notify("[scrollbar.nvim] hlslens module not available. Search handler was not loaded.", vim.log.levels.WARN)
        return
    end

    local config = require("scrollbar.config").get()
    config.handlers.search = true

    -- Directly modify hlslens.config to bypass Lua module caching issue
    local hlslens_config = require("hlslens.config")
    hlslens_config.build_position_cb = function(plist, _, _, _)
        M.handler.show(plist.start_pos)
    end

    -- Apply user overrides if provided
    if overrides then
        for k, v in pairs(overrides) do
            hlslens_config[k] = v
        end
    end

    vim.cmd([[
        augroup scrollbar_search_hide
            autocmd!
            autocmd CmdlineLeave : lua require('scrollbar.handlers.search').nohlsearch()
            autocmd CursorMoved * lua require('scrollbar.handlers.search').nohlsearch()
        augroup END
    ]])
end

return M
