local utils = require("scrollbar.utils")
local render = require("scrollbar").throttled_render

local M = {}

---@param bufnr number
local function get_gitsigns_marks(bufnr)
    local config = require("scrollbar.config").get()
    -- NOTE: get_hunks sometimes returns nil
    local hunks = require("gitsigns").get_hunks(bufnr) or {}

    local gitsigns_marks = {}

    for _, hunk in ipairs(hunks) do
        if hunk.type == "add" then
            for line = hunk.added.start, hunk.added.start + hunk.added.count - 1 do
                table.insert(gitsigns_marks, {
                    line = line - 1,
                    text = config.marks.GitAdd.text,
                    type = "GitAdd",
                    level = 1,
                })
            end
        elseif hunk.type == "change" then
            -- A change can consist of both added and removed lines. In order to
            -- use the same rendering as gitsigns, we need to separate the
            -- changes within a single hunk.
            for line = hunk.added.start + hunk.removed.count, hunk.added.start + hunk.added.count - hunk.removed.count + 1 do
                table.insert(gitsigns_marks, {
                    line = line - 1,
                    text = config.marks.GitAdd.text,
                    type = "GitAdd",
                    level = 3,
                })
            end

            for line = hunk.added.start, hunk.added.start + hunk.removed.count - 1 do
                table.insert(gitsigns_marks, {
                    line = line - 1,
                    text = config.marks.GitChange.text,
                    type = "GitChange",
                    level = 1,
                })
            end
        elseif hunk.type == "delete" then
            -- NOTE: deleted lines are "collapsed" into a single mark that represents the deletion.
            -- This is the same approach that gitsigns used for the signcolumn.
            table.insert(gitsigns_marks, {
                line = hunk.added.start - 1,
                text = config.marks.GitDelete.text,
                type = "GitDelete",
                level = 1,
            })
        end
    end

    return gitsigns_marks
end

---@param bufnr number
local function set_marks_in_buf(bufnr)
    local scrollbar_marks = utils.get_scrollbar_marks(bufnr)
    scrollbar_marks.gitsigns = get_gitsigns_marks(bufnr)
    utils.set_scrollbar_marks(bufnr, scrollbar_marks)
end

M.handler = {
    show = function()
        -- NOTE: gitsigns does not include information which buffer was updated.
        -- To avoid inconsistencies, the best bet is to update all buffers.
        -- This could be taxing on performance, but the impact was not measured
        -- during the initial implementation.
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) then
                set_marks_in_buf(bufnr)
            end
        end

        render()
    end,
}

function M.setup()
    if not pcall(require, "gitsigns") then
        vim.notify(
            "[scrollbar.nvim] gitsigns.nvim module not available. Gitsigns handler was not loaded.",
            vim.log.levels.WARN
        )
        return
    end

    local augroup = vim.api.nvim_create_augroup("ScrollbarGitSigns", {})

    vim.api.nvim_create_autocmd("User", {
        pattern = "GitSignsUpdate",
        group = augroup,
        desc = "Update scrollbar marks after gitsigns updates",
        callback = M.handler.show,
    })
    M.handler.show()
end

return M
