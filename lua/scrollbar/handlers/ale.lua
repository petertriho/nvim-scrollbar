local utils = require("scrollbar.utils")
local config = require("scrollbar.config").get()

local M = {}

local function ale_marks_for(bufnr)
    local ale_buffer_info = vim.g.ale_buffer_info[tostring(bufnr)]
    if ale_buffer_info == nil then return {} end

    local ale_loclist = ale_buffer_info.loclist

    local rv = {}
    for _,loclist_entry in pairs(ale_loclist) do
        local mark_type = "Warn"
        if loclist_entry.type == 'E' then
            mark_type = "Error"
        end

        table.insert(rv, {
            line = loclist_entry.lnum,
            type = mark_type,
            text = config.marks[mark_type].text[1],
            level = config.marks[mark_type].priority
        })
    end

    return rv
end

local function update_ale_marks()
    local bufnr = vim.api.nvim_get_current_buf()
    local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
    scrollbar_marks.alesigns = ale_marks_for(bufnr)
    utils.set_scrollbar_marks(bufnr, scrollbar_marks)
    require("scrollbar").throttled_render()
end

function M.setup(opts)
    local options = opts or {}
    config = vim.tbl_deep_extend("force", config, options)

    local augroup = vim.api.nvim_create_augroup("ScrollbarALE", {})

    vim.api.nvim_create_autocmd("User", {
        pattern = "ALELintPost",
        group = augroup,
        desc = "Update scrollbar marks after ALE does linting",
        callback = update_ale_marks,
    })
end

return M
