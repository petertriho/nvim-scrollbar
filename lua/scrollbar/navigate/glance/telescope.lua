--- The Telescope glance picker. It uses only the glance context.
---
--- - Each row is `ctx.format(item)`. The ordinal is the mark types, the line
---   number, and the line text of the item.
--- - The preview copies the lines of the source buffer, so it shows unsaved
---   edits. The vimgrep previewer of Telescope reads a named file from the
---   disk instead.
--- - The list selects `ctx.selected`.
--- - `select_default`, `select_horizontal`, and `select_vertical` close the
---   picker and call `ctx.jump`. `send_to_qflist` and
---   `send_selected_to_qflist` close the picker and call `ctx.quickfix`.
---   Other actions of Telescope do not change.

local M = {}

M.TITLE = "Scrollbar glance"

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarGlanceTelescope")
-- Name of the one preview buffer of a picker. The previewer then copies the
-- source lines once, not for each selection.
local PREVIEW_NAME = "scrollbar-glance-preview"
local LOADED_VAR = "scrollbar_glance_preview"

---@param message string
local function notify_error(message)
    vim.notify("[nvim-scrollbar] " .. message, vim.log.levels.ERROR)
end

---@param item ScrollbarGlanceItem
---@return string
local function ordinal(item)
    return table.concat(item.types, " ") .. " " .. item.lnum .. " " .. item.text
end

--- The text of a row and its highlights, in the format of Telescope: byte
--- ranges `{ start, finish }`, zero-based, `finish` exclusive.
---@param chunks ScrollbarGlanceChunk[]
---@return string text
---@return table highlights
local function display(chunks)
    local parts = {}
    local highlights = {}
    local length = 0
    for _, chunk in ipairs(chunks) do
        local text = chunk[1]
        if chunk[2] ~= nil then
            highlights[#highlights + 1] = { { length, length + #text }, chunk[2] }
        end
        parts[#parts + 1] = text
        length = length + #text
    end
    return table.concat(parts), highlights
end

---@param ctx ScrollbarGlanceContext
---@param previewers table `telescope.previewers`
---@param putils table `telescope.previewers.utils`
---@return table
local function previewer(ctx, previewers, putils)
    return previewers.new_buffer_previewer({
        title = "Preview",
        get_buffer_by_name = function()
            return PREVIEW_NAME
        end,
        define_preview = function(self, entry)
            local bufnr = self.state.bufnr
            if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_valid(ctx.source_buf) then
                return
            end
            if not vim.b[bufnr][LOADED_VAR] then
                vim.b[bufnr][LOADED_VAR] = true
                local lines = vim.api.nvim_buf_get_lines(ctx.source_buf, 0, -1, false)
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                local filetype = vim.bo[ctx.source_buf].filetype
                if filetype ~= "" then
                    putils.highlighter(bufnr, filetype)
                end
            end
            local line = math.min(entry.lnum, vim.api.nvim_buf_line_count(bufnr)) - 1
            vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
            vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, line, 0, {
                end_row = line + 1,
                hl_group = "TelescopePreviewLine",
                hl_eol = true,
            })
            -- A new preview buffer shows in the window only after this
            -- function, so the cursor moves later.
            vim.schedule(function()
                local winid = self.state and self.state.winid
                if winid == nil or not vim.api.nvim_win_is_valid(winid) then
                    return
                end
                if vim.api.nvim_win_get_buf(winid) ~= bufnr then
                    return
                end
                vim.api.nvim_win_set_cursor(winid, { line + 1, 0 })
                vim.api.nvim_win_call(winid, function()
                    vim.cmd("normal! zz")
                end)
            end)
        end,
    })
end

--- Open the picker. `opts` go to `pickers.new()`, for example a theme.
---@param ctx ScrollbarGlanceContext
---@param opts? table
M.open = function(ctx, opts)
    local ok, pickers = pcall(require, "telescope.pickers")
    if not ok then
        notify_error('glance: picker "telescope" needs telescope.nvim')
        return
    end
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")
    local putils = require("telescope.previewers.utils")
    opts = opts or {}

    ---@param prompt_bufnr integer
    ---@param split? "split"|"vsplit"
    local function jump(prompt_bufnr, split)
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry == nil then
            return
        end
        -- The close ends insert mode only after the key. The move waits for
        -- it, so that the jumplist entry has the right column and the source
        -- window does not stay in insert mode.
        if vim.fn.mode():sub(1, 1) == "i" then
            vim.schedule(function()
                ctx.jump(entry.value, { split = split })
            end)
        else
            ctx.jump(entry.value, { split = split })
        end
    end

    ---@param prompt_bufnr integer
    ---@param selected_only boolean
    local function quickfix(prompt_bufnr, selected_only)
        local picker = action_state.get_current_picker(prompt_bufnr)
        local items = {}
        if selected_only then
            for _, entry in ipairs(picker:get_multi_selection()) do
                items[#items + 1] = entry.value
            end
        end
        if #items == 0 then
            for entry in picker.manager:iter() do
                items[#items + 1] = entry.value
            end
        end
        actions.close(prompt_bufnr)
        ctx.quickfix(items)
    end

    pickers
        .new(opts, {
            prompt_title = M.TITLE,
            finder = finders.new_table({
                results = ctx.items,
                entry_maker = function(item)
                    return {
                        value = item,
                        ordinal = ordinal(item),
                        display = function(entry)
                            return display(ctx.format(entry.value))
                        end,
                        bufnr = ctx.source_buf,
                        lnum = item.lnum,
                    }
                end,
            }),
            sorter = conf.generic_sorter(opts),
            previewer = previewer(ctx, previewers, putils),
            default_selection_index = ctx.selected > 0 and ctx.selected or nil,
            attach_mappings = function(prompt_bufnr)
                actions.select_default:replace(function()
                    jump(prompt_bufnr)
                end)
                actions.select_horizontal:replace(function()
                    jump(prompt_bufnr, "split")
                end)
                actions.select_vertical:replace(function()
                    jump(prompt_bufnr, "vsplit")
                end)
                actions.send_to_qflist:replace(function()
                    quickfix(prompt_bufnr, false)
                end)
                actions.send_selected_to_qflist:replace(function()
                    quickfix(prompt_bufnr, true)
                end)
                return true
            end,
        })
        :find()
end

return M
