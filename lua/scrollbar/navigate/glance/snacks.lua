--- The snacks.nvim glance picker. It uses only the glance context.
---
--- - Each row is `ctx.format(item)`. The filter text is the mark types, the
---   line number, and the line text of the item.
--- - The preview shows the source buffer at the line of the item, so it shows
---   unsaved edits.
--- - The list selects `ctx.selected`. With an empty prompt, the rows keep the
---   order of `ctx.items`.
--- - `confirm`, and the `split` and `vsplit` actions that run it, close the
---   picker and call `ctx.jump`. The `qflist` and `qflist_all` actions close
---   the picker and call `ctx.quickfix`. Other actions of snacks do not
---   change.

local M = {}

M.TITLE = "Scrollbar glance"

---@param message string
local function notify_error(message)
    vim.notify("[nvim-scrollbar] " .. message, vim.log.levels.ERROR)
end

---@param item ScrollbarGlanceItem
---@return string
local function filter_text(item)
    return table.concat(item.types, " ") .. " " .. item.lnum .. " " .. item.text
end

---@param entries table[] Items of the snacks picker
---@return ScrollbarGlanceItem[]
local function glance_items(entries)
    local result = {}
    for index, entry in ipairs(entries) do
        result[index] = entry.glance
    end
    return result
end

--- Open the picker. `opts` merge over the defaults and go to
--- `Snacks.picker.pick()`.
---@param ctx ScrollbarGlanceContext
---@param opts? table
M.open = function(ctx, opts)
    local ok, Snacks = pcall(require, "snacks")
    if not ok or type(Snacks) ~= "table" or Snacks.picker == nil then
        notify_error('glance: picker "snacks" needs snacks.nvim')
        return
    end

    local items = {}
    for index, item in ipairs(ctx.items) do
        items[index] = {
            text = filter_text(item),
            buf = ctx.source_buf,
            pos = { item.lnum, 0 },
            glance = item,
        }
    end
    local selected = ctx.selected

    local function confirm(picker, entry, action, waited)
        -- The same as the jump action of snacks: a move from insert mode waits
        -- until insert mode ends, so that the source window does not stay in
        -- insert mode. Insert mode ends after the key, so one wait is enough.
        if not waited and vim.fn.mode():sub(1, 1) == "i" then
            vim.cmd.stopinsert()
            vim.schedule(function()
                confirm(picker, entry, action, true)
            end)
            return
        end
        picker:close()
        if entry == nil then
            return
        end
        local cmd = type(action) == "table" and action.cmd or nil
        ctx.jump(entry.glance, { split = (cmd == "split" or cmd == "vsplit") and cmd or nil })
    end

    local defaults = {
        title = M.TITLE,
        items = items,
        format = function(entry)
            return ctx.format(entry.glance)
        end,
        preview = "file",
        main = { current = true },
        on_show = function(picker)
            if selected > 0 then
                picker.list:view(selected)
            end
        end,
        confirm = confirm,
        actions = {
            qflist = function(picker)
                picker:close()
                local chosen = picker:selected()
                ctx.quickfix(glance_items(#chosen > 0 and chosen or picker:items()))
            end,
            qflist_all = function(picker)
                picker:close()
                ctx.quickfix(glance_items(picker:items()))
            end,
        },
    }
    Snacks.picker.pick(vim.tbl_deep_extend("force", defaults, opts or {}))
end

return M
