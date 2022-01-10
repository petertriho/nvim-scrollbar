local utils = require("scrollbar.utils")
local render = require("scrollbar").render

local M = {}

function M.process(lines)
    local results = {}
    for _, line in pairs(lines) do
        local row = line:match("^(%d+):.*$")
        table.insert(results, { row })
    end
    return results
end

function M.search(cb)
    local config = require("scrollbar.config").get()
    local bufnr = vim.api.nvim_get_current_buf()

    local command = config.search.command

    if vim.fn.executable(command) ~= 1 then
        vim.notify(command .. " was not found on your path", vim.log.levels.ERROR)
        return
    end

    local ok, Job = pcall(require, "plenary.job")
    if not ok then
        vim.notify("search requires https://github.com/nvim-lua/plenary.nvim", vim.log.levels.ERROR)
        return
    end

    local ok, Path = pcall(require, "plenary.path")
    if not ok then
        vim.notify("search requires https://github.com/nvim-lua/plenary.nvim", vim.log.levels.ERROR)
        return
    end

    local search_regex = vim.fn.getreginfo("/").regcontents[1]
    local search_path = vim.fn.expand("%:p")
    if not Path:new(search_path):exists() then
      return
    end

    local args = vim.tbl_flatten({ config.search.args, search_regex, search_path })
    Job
        :new({
            command = command,
            args = args,
            on_exit = vim.schedule_wrap(function(j, code)
                if code == 2 then
                    local error = table.concat(j:stderr_result(), "\n")
                    vim.notify(command .. " failed with code " .. code .. "\n" .. error, vim.log.levels.ERROR)
                end
                local lines = j:result()
                cb(M.process(lines))
            end),
        })
        :start()
end

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

    if not config.search.use_builtin then
        local hlslens_config = vim.tbl_deep_extend("force", {
            build_position_cb = function(plist, _, _, _)
                M.handler.show(plist.start_pos)
            end,
        }, overrides or {})

        require("hlslens").setup(hlslens_config)
    else
        if config.autocmd and config.autocmd.render and #config.autocmd.render > 0 then
            vim.cmd(string.format(
                [[
          augroup scrollbar_search_show
              autocmd!
              autocmd %s * lua require('scrollbar.handlers.search').search(require('scrollbar.handlers.search').handler.show)
          augroup END
          ]],
                table.concat(config.autocmd.render, ",")
            ))
        end
        vim.cmd([[
      ]])
    end

    vim.cmd([[
        augroup scrollbar_search_hide
            autocmd!
            autocmd CmdlineLeave : lua require('scrollbar.handlers.search').handler.hide()
        augroup END
    ]])
end

return M
