--- The context of a glance picker. `glance()` builds one context and passes it
--- to the picker. The builtin, snacks, and Telescope pickers use only the
--- context, the same as a user function, so the context is a public contract:
--- a later change only adds fields.
---
--- - `items` holds the entries of the list in list order, with one-based
---   lines. "type" mode has no header items. Each item has the mark type of
---   its group in `group`, and the items keep the group order.
--- - `format` gives the columns of a row as highlight chunks, so that every
---   picker shows the same row. The column widths come from `items`.
--- - `jump` and `quickfix` do the same move and write the same quickfix list
---   for every picker. They do not close a picker. A picker closes its
---   windows first.
--- - `refresh` reads the marks again with the same mode and types.

local move = require("scrollbar.navigate.move")
local targets = require("scrollbar.navigate.targets")

local M = {}

M.LINE_NR_GROUP = "ScrollbarGlanceLineNr"
M.QUICKFIX_TITLE = "Scrollbar glance"

---@param message string
local function notify(message)
    vim.notify("[nvim-scrollbar] " .. message, vim.log.levels.WARN)
end

---@param source_buf integer
---@param line integer Zero-based
---@return string
local function buffer_line(source_buf, line)
    return vim.api.nvim_buf_get_lines(source_buf, line, line + 1, false)[1] or ""
end

---@param source_buf integer
---@param entries ScrollbarNavigateEntry[]
---@return ScrollbarGlanceItem[]
local function to_items(source_buf, entries)
    local items = {}
    local group
    for _, entry in ipairs(entries) do
        if entry.kind == "header" then
            group = entry.type
        else
            local marks = {}
            local types = {}
            local seen = {}
            for index, mark in ipairs(entry.marks) do
                marks[index] = {
                    type = mark.type,
                    provider = mark.provider,
                    text = mark.text,
                    priority = mark.priority,
                    glyph = mark.glyph,
                    hl = mark.group,
                }
                if not seen[mark.type] then
                    seen[mark.type] = true
                    types[#types + 1] = mark.type
                end
            end
            local text = buffer_line(source_buf, entry.line):gsub("^%s+", ""):gsub("\t", " ")
            items[#items + 1] = {
                lnum = entry.line + 1,
                text = text,
                glyph = marks[1].glyph,
                hl = marks[1].hl,
                type = entry.type,
                types = types,
                marks = marks,
                group = group,
            }
        end
    end
    return items
end

--- The index of the first item at or after the zero-based `line`, else of the
--- last item. 0 without items.
---@param items ScrollbarGlanceItem[]
---@param line integer
---@return integer
M.index_at = function(items, line)
    for index, item in ipairs(items) do
        if item.lnum - 1 >= line then
            return index
        end
    end
    return #items
end

---@class ScrollbarGlanceWidths
---@field number integer
---@field glyph integer
---@field group integer

-- The display width of each glyph and type name. The strings come from the
-- mark types, so the cache stays small, and a long list calls
-- `strdisplaywidth` only a few times.
local display_widths = {}

---@param text string
---@return integer
local function display_width(text)
    local width = display_widths[text]
    if width == nil then
        width = vim.fn.strdisplaywidth(text)
        display_widths[text] = width
    end
    return width
end

---@param items ScrollbarGlanceItem[]
---@return ScrollbarGlanceWidths
local function widths(items)
    local result = { number = 1, glyph = 1, group = 0 }
    for _, item in ipairs(items) do
        result.number = math.max(result.number, #tostring(item.lnum))
        result.glyph = math.max(result.glyph, display_width(item.glyph))
        if item.group ~= nil then
            result.group = math.max(result.group, display_width(item.group))
        end
    end
    return result
end

---@param source_win integer
---@param source_buf integer
---@return boolean
local function shows_source(source_win, source_buf)
    return vim.api.nvim_win_is_valid(source_win) and vim.api.nvim_win_get_buf(source_win) == source_buf
end

--- One quickfix item for each line of `items`, in line order. The text of an
--- item is the mark types of the line and the text of the line.
---@param source_buf integer
---@param items ScrollbarGlanceItem[]
---@return table[]
local function quickfix_items(source_buf, items)
    local by_line = {}
    local lines = {}
    for _, item in ipairs(items) do
        local entry = by_line[item.lnum]
        if entry == nil then
            entry = { types = {}, seen = {} }
            by_line[item.lnum] = entry
            lines[#lines + 1] = item.lnum
        end
        for _, mark_type in ipairs(item.types) do
            if not entry.seen[mark_type] then
                entry.seen[mark_type] = true
                entry.types[#entry.types + 1] = mark_type
            end
        end
    end
    table.sort(lines)
    local result = {}
    for index, lnum in ipairs(lines) do
        result[index] = {
            bufnr = source_buf,
            lnum = lnum,
            col = 1,
            text = table.concat(by_line[lnum].types, ", ") .. ": " .. vim.trim(buffer_line(source_buf, lnum - 1)),
        }
    end
    return result
end

--- The context for the marks of `source_win`.
---@param source_win integer
---@param mode ScrollbarGlanceEntries
---@param types? table<string, true> Mark types of the list. Nil lists every type except `Cursor`
---@return ScrollbarGlanceContext
M.new = function(source_win, mode, types)
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    ---@type ScrollbarGlanceContext
    local ctx
    ---@type ScrollbarGlanceWidths
    local column_widths

    ---@return ScrollbarGlanceItem[]
    local function refresh()
        local items = {}
        local cursor_line = 0
        if shows_source(source_win, source_buf) then
            items = to_items(source_buf, targets.entries(source_win, mode, types))
            cursor_line = vim.api.nvim_win_get_cursor(source_win)[1] - 1
        end
        ctx.items = items
        ctx.selected = M.index_at(items, cursor_line)
        column_widths = widths(items)
        return items
    end

    ---@param item ScrollbarGlanceItem
    ---@param opts? ScrollbarGlanceFormatOptions
    ---@return ScrollbarGlanceChunk[]
    local function format(item, opts)
        local chunks = {}
        if item.group ~= nil and not (opts ~= nil and opts.group == false) then
            chunks[1] = { item.group, "Scrollbar" .. item.group }
            chunks[2] = { string.rep(" ", column_widths.group - display_width(item.group)) .. "  " }
        end
        chunks[#chunks + 1] = { item.glyph, item.hl }
        chunks[#chunks + 1] = { string.rep(" ", column_widths.glyph - display_width(item.glyph)) .. " " }
        chunks[#chunks + 1] = { string.format("%" .. column_widths.number .. "d", item.lnum), M.LINE_NR_GROUP }
        chunks[#chunks + 1] = { "  " .. item.text }
        return chunks
    end

    ---@param item ScrollbarGlanceItem
    ---@param opts? ScrollbarGlanceJumpOptions
    ---@return boolean moved
    local function jump(item, opts)
        local split = opts and opts.split or nil
        if split ~= nil and split ~= "split" and split ~= "vsplit" then
            error(string.format('glance: opts.split must be "split" or "vsplit", not %s', vim.inspect(split)), 2)
        end
        if not shows_source(source_win, source_buf) then
            notify("glance: the source window is closed or shows another buffer")
            return false
        end
        if vim.api.nvim_get_current_win() ~= source_win then
            vim.api.nvim_set_current_win(source_win)
        end
        local target_win = source_win
        if split ~= nil then
            vim.cmd(split)
            target_win = vim.api.nvim_get_current_win()
        end
        if not move.line(target_win, source_buf, item.lnum - 1, true) then
            return false
        end
        local scheduler = package.loaded["scrollbar.scheduler"]
        if scheduler ~= nil then
            scheduler.invalidate_window(target_win)
        end
        return true
    end

    ---@param items? ScrollbarGlanceItem[]
    local function quickfix(items)
        if not vim.api.nvim_buf_is_valid(source_buf) then
            notify("glance: the source buffer is closed")
            return
        end
        local list = quickfix_items(source_buf, items or ctx.items)
        vim.fn.setqflist({}, " ", { title = M.QUICKFIX_TITLE, items = list })
        vim.cmd("copen")
    end

    ctx = {
        source_win = source_win,
        source_buf = source_buf,
        mode = mode,
        items = {},
        selected = 0,
        format = format,
        jump = jump,
        quickfix = quickfix,
        refresh = refresh,
    }
    refresh()
    return ctx
end

return M
