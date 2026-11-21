--- The glance window, in the style of glance.nvim
--- (https://github.com/dnlhc/glance.nvim): a frame across the source window
--- with a list of the marks on the right and a preview pane on the left. The
--- actions and the keys of each pane follow the design of glance.nvim. The
--- code is not from glance.nvim.
---
--- - `glance.frame` sets the place and the size of the frame of both panes.
---   The default frame opens under the cursor line, or above it when there is
---   no room, and spans the text area of the source window. The list pane
---   takes `glance.list.width` on `glance.list.side`, and the preview pane
---   takes the rest.
--- - The frame runs again when the screen or the source window changes size.
---   When it no longer fits, the glance window closes.
--- - The list has focus. Native motions move the selection, and the preview
---   follows. The keys of `glance.keys.list` are buffer-local keys of the list.
--- - The preview pane is a window on the source buffer, so an edit in it
---   changes the buffer. `<C-w>p` returns to the list, and the list then
---   builds again from the current marks. The list has no other update.
--- - Neovim has no window-local keys, so the keys of `glance.keys.preview` are
---   buffer-local keys of the source buffer while the preview pane has focus.
---   A buffer-local key of the source buffer with the same lhs comes back when
---   the pane loses focus.
--- - Each action uses the selected entry of the list, also from the preview
---   pane.
--- - The frame closes on a close key, on `:q` in either pane, when focus goes
---   to a window outside the frame, when the source window closes, and on
---   setup.

local config = require("scrollbar.config")
local frame = require("scrollbar.navigate.frame")
local move = require("scrollbar.navigate.move")
local peek = require("scrollbar.navigate.peek")
local targets = require("scrollbar.navigate.targets")
local window_config = require("scrollbar.config.window")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarGlance")
-- An extmark on the source buffer at the line of the selected entry. It moves
-- with the edits in the preview, so the list selects the same place again
-- after a rebuild.
local SELECTION_NAMESPACE = vim.api.nvim_create_namespace("ScrollbarGlanceSelection")
local SELECTION_ID = 1
local AUGROUP = "ScrollbarGlance"
local HEADER_GROUP = "ScrollbarGlanceHeader"
local LINE_NR_GROUP = "ScrollbarGlanceLineNr"
local NO_ROOM = "glance: the current window has no room for the glance window"

---@class ScrollbarGlanceSpan
---@field start_col integer Zero-based byte column
---@field end_col integer Zero-based byte column, exclusive
---@field group string

---@class ScrollbarGlanceSession
---@field source_win integer
---@field source_buf integer
---@field list_win integer
---@field list_buf integer
---@field preview_win integer
---@field mode ScrollbarGlanceEntries
---@field window ScrollbarWindowConfig
---@field list_config ScrollbarGlanceListConfig
---@field frame_value ScrollbarFrameValue
---@field types? table<string, true>
---@field entries ScrollbarNavigateEntry[]
---@field spans ScrollbarGlanceSpan[][] Highlight spans of each list row
---@field focused integer The frame window that had focus last
---@field augroup integer
---@field closing boolean
---@field keys ScrollbarGlanceKeys
---@field actions table<string, fun()>
---@field preview_maps? ScrollbarGlancePreviewMap[] The preview keys on the source buffer while the pane has focus

---@class ScrollbarGlancePreviewMap
---@field lhs string
---@field desc string
---@field replaced? table The buffer-local map of the source buffer that the key hides, from `maparg()`

---@type ScrollbarGlanceSession?
local session

---@param winid? integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end

---@param message string
local function notify(message)
    vim.notify("[nvim-scrollbar] " .. message, vim.log.levels.WARN)
end

-- The list highlights come from a decoration provider, so a long list needs
-- extmarks only for the rows on the screen.
vim.api.nvim_set_decoration_provider(NAMESPACE, {
    on_win = function(_, _, bufnr)
        return session ~= nil and bufnr == session.list_buf
    end,
    on_line = function(_, _, bufnr, row)
        local current = session
        local spans = current and current.spans[row + 1] or nil
        if spans == nil then
            return
        end
        for _, span in ipairs(spans) do
            vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, row, span.start_col, {
                end_col = span.end_col,
                hl_group = span.group,
                ephemeral = true,
            })
        end
    end,
})

---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

---@class ScrollbarGlanceGeometry
---@field preview table<string, any> Position keys and content size of the preview pane
---@field list table<string, any> Position keys and content size of the list pane

--- Split the frame into the list pane on `list.side` and the preview pane on
--- the other side. Nil when a pane has no room for one content cell.
---@param source_win integer
---@param placed ScrollbarFrame
---@param sides ScrollbarWindowSides
---@param list ScrollbarGlanceListConfig
---@return ScrollbarGlanceGeometry?
M._split = function(source_win, placed, sides, list)
    local width = placed.width
    local list_frame
    if list.width < 1 then
        -- The preview gets the rounded-down part, so the default 0.4 gives
        -- the same widths as a 60% preview.
        list_frame = width - math.floor(width * (1 - list.width))
    else
        list_frame = math.min(list.width, width)
    end
    local preview_frame = width - list_frame
    local frame_cols = sides.left + sides.right
    local height = placed.height - sides.top - sides.bottom
    if height < 1 or list_frame - frame_cols < 1 or preview_frame - frame_cols < 1 then
        return nil
    end
    local list_col, preview_col
    if list.side == "left" then
        list_col, preview_col = placed.col, placed.col + list_frame
    else
        preview_col, list_col = placed.col, placed.col + preview_frame
    end
    local function pane(col, frame_width)
        local result = { width = frame_width - frame_cols, height = height }
        frame.apply_position(placed, source_win, result)
        result.col = col
        return result
    end
    return { preview = pane(preview_col, preview_frame), list = pane(list_col, list_frame) }
end

--- The geometry of the panes for `glance.frame`. Nil, with the reason, when
--- the frame failed or has no room.
---@param source_win integer
---@param sides ScrollbarWindowSides
---@param value ScrollbarFrameValue
---@param list ScrollbarGlanceListConfig
---@return ScrollbarGlanceGeometry? geometry
---@return "no_room"|"failed"? reason
local function geometry(source_win, sides, value, list)
    local placed, reason = frame.layout("glance", "glance.frame", value, source_win, sides)
    if placed == nil then
        return nil, reason
    end
    local result = M._split(source_win, placed, sides, list)
    if result == nil then
        return nil, "no_room"
    end
    return result, nil
end

---@param source_win integer
---@param window ScrollbarWindowConfig
---@param pane table<string, any> Position keys and content size
---@return table<string, any>
local function pane_config(source_win, window, pane)
    local result = {}
    for key, value in pairs(window.open) do
        result[key] = value
    end
    for key, value in pairs(pane) do
        result[key] = value
    end
    if result.relative == "win" then
        result.win = source_win
    end
    result.focusable = true
    return result
end

local HIDDEN_PANE = { relative = "win", row = 0, col = 0, width = 1, height = 1 }

--- The rows of the list and their highlight spans.
---@param source_buf integer
---@param entries ScrollbarNavigateEntry[]
---@return string[] rows
---@return ScrollbarGlanceSpan[][] spans
local function list_rows(source_buf, entries)
    local number_width = 1
    local glyph_width = 1
    for _, entry in ipairs(entries) do
        if entry.kind == "entry" then
            number_width = math.max(number_width, #tostring(entry.line + 1))
            glyph_width = math.max(glyph_width, vim.fn.strdisplaywidth(entry.marks[1].glyph))
        end
    end
    local grouped = entries[1] ~= nil and entries[1].kind == "header"
    local indent = grouped and "   " or " "

    local rows = {}
    local spans = {}
    for index, entry in ipairs(entries) do
        local mark = entry.marks[1]
        if entry.kind == "header" then
            local count = 0
            local seen = {}
            for _, header_mark in ipairs(entry.marks) do
                if not seen[header_mark.line] then
                    seen[header_mark.line] = true
                    count = count + 1
                end
            end
            local text = string.format(" %s (%d)", entry.type, count)
            rows[index] = text
            spans[index] = { { start_col = 1, end_col = #text, group = HEADER_GROUP } }
        else
            local glyph = mark.glyph .. string.rep(" ", glyph_width - vim.fn.strdisplaywidth(mark.glyph))
            local number = string.format("%" .. number_width .. "d", entry.line + 1)
            local source_line = vim.api.nvim_buf_get_lines(source_buf, entry.line, entry.line + 1, false)[1] or ""
            local text = source_line:gsub("^%s+", ""):gsub("\t", " ")
            local glyph_start = #indent
            local number_start = glyph_start + #glyph + 1
            rows[index] = indent .. glyph .. " " .. number .. "  " .. text
            spans[index] = {
                { start_col = glyph_start, end_col = glyph_start + #mark.glyph, group = mark.group },
                { start_col = number_start, end_col = number_start + #number, group = LINE_NR_GROUP },
            }
        end
    end
    return rows, spans
end

--- The row of the first entry at or after `line`, or of the last entry. A
--- header is never selected.
---@param entries ScrollbarNavigateEntry[]
---@param line integer
---@return integer row One-based
local function entry_row(entries, line)
    local last = 1
    for index, entry in ipairs(entries) do
        if entry.kind == "entry" then
            if entry.line >= line then
                return index
            end
            last = index
        end
    end
    return last
end

---@param current ScrollbarGlanceSession
---@return ScrollbarNavigateEntry?
local function selected_entry(current)
    if not valid_window(current.list_win) then
        return nil
    end
    local row = vim.api.nvim_win_get_cursor(current.list_win)[1]
    return current.entries[row]
end

--- Show the line of the selected entry in the preview. On a header, the
--- preview shows the first entry of the group.
---@param current ScrollbarGlanceSession
local function update_preview(current)
    local entry = selected_entry(current)
    if entry == nil or not valid_window(current.preview_win) then
        return
    end
    local line = clamp(entry.line, 0, vim.api.nvim_buf_line_count(current.source_buf) - 1)
    vim.api.nvim_win_set_cursor(current.preview_win, { line + 1, 0 })
    vim.api.nvim_win_call(current.preview_win, function()
        vim.cmd("normal! zz")
    end)
    pcall(vim.api.nvim_buf_set_extmark, current.source_buf, SELECTION_NAMESPACE, line, 0, { id = SELECTION_ID })
end

---@param current ScrollbarGlanceSession
---@param rows string[]
local function write_list(current, rows)
    local buf = current.list_buf
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, rows)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

--- Build the list again from the current marks, and select the entry at the
--- tracked line again.
---@param current ScrollbarGlanceSession
local function rebuild(current)
    local entries = targets.entries(current.source_win, current.mode, current.types)
    local rows, spans = list_rows(current.source_buf, entries)
    if #rows == 0 then
        rows = { " No marks" }
        spans = {}
    end
    current.entries = entries
    current.spans = spans
    write_list(current, rows)
    local ok, position =
        pcall(vim.api.nvim_buf_get_extmark_by_id, current.source_buf, SELECTION_NAMESPACE, SELECTION_ID, {})
    local line = ok and position[1] or 0
    if #entries > 0 then
        vim.api.nvim_win_set_cursor(current.list_win, { entry_row(entries, line), 0 })
        update_preview(current)
    end
end

---@param action string
---@return string
local function key_desc(action)
    return "Scrollbar glance: " .. action
end

--- Map the keys of the preview pane on the source buffer, and keep the
--- buffer-local maps that they hide.
---@param current ScrollbarGlanceSession
local function set_preview_keys(current)
    if current.preview_maps ~= nil or not vim.api.nvim_buf_is_valid(current.source_buf) then
        return
    end
    local maps = {}
    vim.api.nvim_buf_call(current.source_buf, function()
        for action, lhs_list in pairs(current.keys.preview) do
            local desc = key_desc(action)
            for _, lhs in ipairs(lhs_list) do
                local existing = vim.fn.maparg(lhs, "n", false, true)
                maps[#maps + 1] = {
                    lhs = lhs,
                    desc = desc,
                    replaced = existing.buffer == 1 and existing or nil,
                }
                vim.keymap.set("n", lhs, current.actions[action], {
                    buffer = current.source_buf,
                    nowait = true,
                    silent = true,
                    desc = desc,
                })
            end
        end
    end)
    current.preview_maps = maps
end

--- Remove the keys of the preview pane from the source buffer, and map the
--- hidden buffer-local maps again.
---@param current ScrollbarGlanceSession
local function clear_preview_keys(current)
    local maps = current.preview_maps
    current.preview_maps = nil
    if maps == nil or not vim.api.nvim_buf_is_valid(current.source_buf) then
        return
    end
    vim.api.nvim_buf_call(current.source_buf, function()
        for _, map in ipairs(maps) do
            local present = vim.fn.maparg(map.lhs, "n", false, true)
            -- A map that another plugin set while the pane had focus stays.
            if present.buffer == 1 and present.desc == map.desc then
                pcall(vim.keymap.del, "n", map.lhs, { buffer = current.source_buf })
                if map.replaced ~= nil then
                    vim.fn.mapset("n", false, map.replaced)
                end
            end
        end
    end)
end

--- Close the frame. With `focus_source`, focus goes back to the source window.
---@param focus_source? boolean
M.close = function(focus_source)
    local current = session
    if current == nil then
        return
    end
    session = nil
    current.closing = true
    pcall(vim.api.nvim_del_augroup_by_id, current.augroup)
    clear_preview_keys(current)
    if vim.api.nvim_buf_is_valid(current.source_buf) then
        vim.api.nvim_buf_clear_namespace(current.source_buf, SELECTION_NAMESPACE, 0, -1)
    end
    if focus_source and valid_window(current.source_win) then
        pcall(vim.api.nvim_set_current_win, current.source_win)
    end
    for _, win in ipairs({ current.list_win, current.preview_win }) do
        if valid_window(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
    if vim.api.nvim_buf_is_valid(current.list_buf) then
        pcall(vim.api.nvim_buf_delete, current.list_buf, { force = true })
    end
end

--- Close the frame and move to the line of the selected entry.
---@param current ScrollbarGlanceSession
---@param command? "split"|"vsplit" Ex command that opens a new window from the source window first
local function jump(current, command)
    local entry = selected_entry(current)
    if entry == nil or entry.kind ~= "entry" then
        return
    end
    local target_win = current.source_win
    local source_buf = current.source_buf
    M.close(true)
    if command ~= nil then
        if vim.api.nvim_get_current_win() ~= target_win then
            return
        end
        vim.cmd(command)
        target_win = vim.api.nvim_get_current_win()
    end
    if move.line(target_win, source_buf, entry.line, true) then
        local scheduler = package.loaded["scrollbar.scheduler"]
        if scheduler ~= nil then
            scheduler.invalidate_window(target_win)
        end
    end
end

--- Select the next entry in the direction of `step`, and show it in the
--- preview. The selection skips headers and wraps around.
---@param current ScrollbarGlanceSession
---@param step 1|-1
local function select_entry(current, step)
    local count = #current.entries
    if count == 0 or not valid_window(current.list_win) then
        return
    end
    local row = vim.api.nvim_win_get_cursor(current.list_win)[1]
    for _ = 1, count do
        row = (row - 1 + step) % count + 1
        if current.entries[row].kind == "entry" then
            vim.api.nvim_win_set_cursor(current.list_win, { row, 0 })
            update_preview(current)
            return
        end
    end
end

--- Put one quickfix item for each listed line in a new quickfix list, close
--- the frame, and open the quickfix window.
---@param current ScrollbarGlanceSession
local function quickfix(current)
    local by_line = {}
    local lines = {}
    for _, entry in ipairs(current.entries) do
        if entry.kind == "entry" then
            local item = by_line[entry.line]
            if item == nil then
                item = { types = {}, seen = {} }
                by_line[entry.line] = item
                lines[#lines + 1] = entry.line
            end
            for _, mark in ipairs(entry.marks) do
                if not item.seen[mark.type] then
                    item.seen[mark.type] = true
                    item.types[#item.types + 1] = mark.type
                end
            end
        end
    end
    table.sort(lines)
    local items = {}
    for index, line in ipairs(lines) do
        local text = vim.api.nvim_buf_get_lines(current.source_buf, line, line + 1, false)[1] or ""
        items[index] = {
            bufnr = current.source_buf,
            lnum = line + 1,
            col = 1,
            text = table.concat(by_line[line].types, ", ") .. ": " .. vim.trim(text),
        }
    end
    vim.fn.setqflist({}, " ", { title = "Scrollbar glance", items = items })
    M.close(true)
    vim.cmd("copen")
end

---@param current ScrollbarGlanceSession
---@return table<string, fun()>
local function actions(current)
    local function focus(win)
        return function()
            if valid_window(win) then
                vim.api.nvim_set_current_win(win)
            end
        end
    end
    return {
        jump = function()
            jump(current)
        end,
        jump_split = function()
            jump(current, "split")
        end,
        jump_vsplit = function()
            jump(current, "vsplit")
        end,
        next = function()
            select_entry(current, 1)
        end,
        previous = function()
            select_entry(current, -1)
        end,
        focus_preview = focus(current.preview_win),
        focus_list = focus(current.list_win),
        quickfix = function()
            quickfix(current)
        end,
        close = function()
            M.close(true)
        end,
    }
end

---@param current ScrollbarGlanceSession
local function set_list_keys(current)
    for action, lhs_list in pairs(current.keys.list) do
        for _, lhs in ipairs(lhs_list) do
            vim.keymap.set("n", lhs, current.actions[action], {
                buffer = current.list_buf,
                nowait = true,
                silent = true,
                desc = key_desc(action),
            })
        end
    end
end

--- Run the frame again after a resize and move both panes. The glance window
--- closes when the frame no longer fits.
---@param current ScrollbarGlanceSession
local function relayout(current)
    if current.closing or session ~= current then
        return
    end
    for _, win in ipairs({ current.source_win, current.list_win, current.preview_win }) do
        if not valid_window(win) then
            return
        end
    end
    local sides = window_config.sides(current.preview_win)
    local result, reason = geometry(current.source_win, sides, current.frame_value, current.list_config)
    if result == nil then
        if reason == "no_room" then
            notify(NO_ROOM)
        end
        M.close(true)
        return
    end
    vim.api.nvim_win_set_config(current.preview_win, pane_config(current.source_win, current.window, result.preview))
    vim.api.nvim_win_set_config(current.list_win, pane_config(current.source_win, current.window, result.list))
end

---@param current ScrollbarGlanceSession
local function watch(current)
    local group = current.augroup
    frame.on_resize(group, function()
        return current.source_win
    end, function()
        relayout(current)
    end)
    vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        buffer = current.list_buf,
        callback = function()
            update_preview(current)
        end,
    })
    vim.api.nvim_create_autocmd("WinEnter", {
        group = group,
        callback = function()
            if current.closing then
                return
            end
            local win = vim.api.nvim_get_current_win()
            local previous = current.focused
            if win == current.list_win then
                current.focused = win
                if previous == current.preview_win then
                    rebuild(current)
                end
            elseif win == current.preview_win then
                current.focused = win
                set_preview_keys(current)
            else
                -- Focus went outside the frame. It stays where it went.
                vim.schedule(function()
                    if session == current then
                        M.close(false)
                    end
                end)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinLeave", {
        group = group,
        callback = function()
            if vim.api.nvim_get_current_win() == current.preview_win then
                clear_preview_keys(current)
            end
        end,
    })
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            local closed = tonumber(args.match)
            if closed == current.list_win or closed == current.preview_win or closed == current.source_win then
                -- Another window cannot close while `WinClosed` runs.
                vim.schedule(function()
                    if session == current then
                        M.close(true)
                    end
                end)
            end
        end,
    })
end

---@class ScrollbarGlanceOptions
---@field types? table<string, true> Mark types of the list. Nil lists every type except `Cursor`

--- Open the glance window for the current window.
---@param options? ScrollbarGlanceOptions
M.open = function(options)
    options = options or {}
    if session ~= nil then
        M.close(true)
    end
    local source_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(source_win).relative ~= "" then
        notify("glance works only in a normal window")
        return
    end
    local glance_config = config.get_glance()
    local entries = targets.entries(source_win, glance_config.list.entries, options.types)
    if #entries == 0 then
        notify("glance: the current window has no marks")
        return
    end
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local window = glance_config.window

    -- Without a `border` key, the panes apply 'winborder', so the sides are
    -- known only after a pane opens. The preview opens hidden.
    local initial = pane_config(source_win, window, HIDDEN_PANE)
    initial.hide = true
    initial.style = "minimal"
    initial.noautocmd = true
    local opened, preview_win = pcall(vim.api.nvim_open_win, source_buf, false, initial)
    if not opened then
        notify("glance failed: " .. tostring(preview_win))
        return
    end
    peek.configure_window(preview_win, window, { winfixbuf = true })
    local sides = window_config.sides(preview_win)
    local panes, reason = geometry(source_win, sides, glance_config.frame, glance_config.list)
    if panes == nil then
        pcall(vim.api.nvim_win_close, preview_win, true)
        -- A failed frame function has notified.
        if reason == "no_room" then
            notify(NO_ROOM)
        end
        return
    end
    local preview_config = pane_config(source_win, window, panes.preview)
    preview_config.hide = false
    vim.api.nvim_win_set_config(preview_win, preview_config)

    local list_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = list_buf })
    vim.api.nvim_set_option_value("filetype", "scrollbar_glance", { buf = list_buf })
    vim.api.nvim_set_option_value("modifiable", false, { buf = list_buf })
    local list_config = pane_config(source_win, window, panes.list)
    list_config.style = "minimal"
    list_config.noautocmd = true
    local list_ok, list_win = pcall(vim.api.nvim_open_win, list_buf, true, list_config)
    if not list_ok then
        pcall(vim.api.nvim_win_close, preview_win, true)
        pcall(vim.api.nvim_buf_delete, list_buf, { force = true })
        notify("glance failed: " .. tostring(list_win))
        return
    end
    for name, value in pairs({ cursorline = true, wrap = false, winfixbuf = true }) do
        vim.api.nvim_set_option_value(name, value, { win = list_win })
    end
    for name, value in pairs(window.wo) do
        vim.api.nvim_set_option_value(name, value, { win = list_win })
    end
    if window.winhighlight then
        vim.api.nvim_set_option_value("winhighlight", window.winhighlight.value, { win = list_win })
    end
    vim.api.nvim_win_set_var(list_win, peek.OWNED_VAR, true)

    local cursor_line = vim.api.nvim_win_get_cursor(source_win)[1] - 1
    vim.api.nvim_buf_set_extmark(source_buf, SELECTION_NAMESPACE, cursor_line, 0, { id = SELECTION_ID })
    ---@type ScrollbarGlanceSession
    local current = {
        source_win = source_win,
        source_buf = source_buf,
        list_win = list_win,
        list_buf = list_buf,
        preview_win = preview_win,
        mode = glance_config.list.entries,
        window = window,
        list_config = glance_config.list,
        frame_value = glance_config.frame,
        types = options.types,
        entries = {},
        spans = {},
        focused = list_win,
        augroup = vim.api.nvim_create_augroup(AUGROUP, { clear = true }),
        closing = false,
        keys = glance_config.keys,
        actions = {},
    }
    current.actions = actions(current)
    session = current
    rebuild(current)
    set_list_keys(current)
    watch(current)
end

--- The state of the open glance window, for tests and the dispose path.
---@return { source_win: integer, list_win: integer, list_buf: integer, preview_win: integer, entries: ScrollbarNavigateEntry[], spans: ScrollbarGlanceSpan[][] }?
M.get = function()
    local current = session
    if current == nil then
        return nil
    end
    return {
        source_win = current.source_win,
        list_win = current.list_win,
        list_buf = current.list_buf,
        preview_win = current.preview_win,
        entries = current.entries,
        spans = current.spans,
    }
end

return M
