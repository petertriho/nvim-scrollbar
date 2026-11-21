--- The frame of the peek float and of the glance window: the place and the
--- size of the outer box, border included. `peek.frame` and
--- `glance.builtin.frame` take a preset name or a frame function. The
--- recipes in `require("scrollbar.recipes").frame` build frame functions with
--- options, and each preset is its recipe without options.
---
--- A frame function gets a new context on each call and returns
--- `{ relative?, row, col, width, height }` in cells, or nil when the window
--- has no room. `row` and `col` are relative to the text area of the source
--- window, or to the editor area with `relative = "editor"`. The plugin
--- rounds the result down and clamps it into its area. A function that
--- errors or returns an invalid result notifies once for each message, and
--- nothing opens.

local stack = require("scrollbar.shared.stack")

local M = {}

---@type string[]
M.PRESETS = { "scrollbar", "cursor", "center" }

-- Default outer sizes of each kind. A number up to 1 is a part of the text
-- area, and a whole number above 1 is cells.
local DEFAULT_SIZE = {
    peek = { width = 0.6, height = 11 },
    glance = { width = 1, height = 18 },
}

---@type table<string, true>
local notified = {}

---@param path string
---@param message string
local function notify_once(path, message)
    local key = path .. "\0" .. message
    if notified[key] then
        return
    end
    notified[key] = true
    vim.notify(string.format("[nvim-scrollbar] %s %s", path, message), vim.log.levels.ERROR)
end

--- Forget the notifications, so that the next failure notifies again.
M.reset = function()
    notified = {}
end

---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
M.clamp = function(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

local clamp = M.clamp

---@param source_win integer
---@return { width: integer, height: integer, textoff: integer, screen_col: integer }
local function window_area(source_win)
    local winbar = vim.api.nvim_get_option_value("winbar", { win = source_win })
    local info = vim.fn.getwininfo(source_win)[1]
    return {
        width = vim.api.nvim_win_get_width(source_win),
        height = math.max(0, vim.api.nvim_win_get_height(source_win) - (winbar == "" and 0 or 1)),
        textoff = info.textoff,
        screen_col = vim.fn.win_screenpos(source_win)[2] - 1,
    }
end

--- The area between the tabline and the command line.
---@return { width: integer, height: integer } area
---@return integer top Screen row of row 0 of the area
local function editor_area()
    local top = 0
    local showtabline = vim.o.showtabline
    if showtabline == 2 or (showtabline == 1 and #vim.api.nvim_list_tabpages() > 1) then
        top = 1
    end
    local bottom = vim.o.cmdheight + (vim.o.laststatus == 3 and 1 or 0)
    return { width = vim.o.columns, height = math.max(0, vim.o.lines - top - bottom) }, top
end

--- The side of the floats of the source window and their inward edge: the
--- column next to the float that is nearest to the text. Without a float, the
--- side is east and the edge is the right edge of the window.
---@param source_win integer
---@param area { width: integer, screen_col: integer }
---@return "E"|"W" side
---@return integer edge Zero-based column relative to the window. On the east side, the first column of the floats
local function float_edge(source_win, area)
    local side, edge
    for _, renderer in ipairs({ "scrollbar", "minimap" }) do
        local footprint = stack.footprint(renderer, source_win)
        if footprint ~= nil and (side == nil or footprint.side == side) then
            local origin = stack.resolve(renderer, source_win, footprint) or footprint.origin
            local inward
            if footprint.side == "W" then
                inward = origin + footprint.col + footprint.width
            else
                inward = origin + footprint.col - footprint.width
            end
            if footprint.relative == "editor" then
                inward = inward - area.screen_col
            end
            if side == nil then
                side, edge = footprint.side, inward
            elseif side == "W" then
                edge = math.max(edge, inward)
            else
                edge = math.min(edge, inward)
            end
        end
    end
    if side == nil then
        return "E", area.width
    end
    return side, math.max(0, math.min(edge, area.width))
end

--- The columns of the window that do not cover the scrollbar, the minimap, or
--- the column of a label.
---@param source_win integer
---@param area { width: integer, textoff: integer, screen_col: integer }
---@param free_col? integer
---@return ScrollbarFrameFree
local function free_columns(source_win, area, free_col)
    local side, edge = float_edge(source_win, area)
    local first_col = area.textoff
    local last_col = area.width
    if side == "E" then
        last_col = edge
    else
        first_col = math.max(first_col, edge)
    end
    -- A free column on the side of the text moves the frame past it.
    if free_col ~= nil then
        if side == "E" and free_col < last_col then
            last_col = math.max(first_col, free_col)
        elseif side == "W" and free_col >= first_col then
            first_col = math.min(last_col, free_col + 1)
        end
    end
    return { side = side, first_col = first_col, last_col = last_col }
end

---@class ScrollbarFrameContextOptions
---@field anchor_row? integer Zero-based text row of the mark. Default: the cursor row
---@field free_col? integer Zero-based column of a label that the frame does not cover

--- A new frame context.
---@param kind "peek"|"glance"
---@param source_win integer
---@param sides ScrollbarWindowSides
---@param options? ScrollbarFrameContextOptions
---@return ScrollbarFrameContext context
---@return integer top Screen row of row 0 of the editor area
M.context = function(kind, source_win, sides, options)
    options = options or {}
    local area = window_area(source_win)
    local editor, top = editor_area()
    local cursor_row = vim.api.nvim_win_call(source_win, vim.fn.winline) - 1
    return {
        kind = kind,
        winid = source_win,
        bufnr = vim.api.nvim_win_get_buf(source_win),
        win = { width = area.width, height = area.height, textoff = area.textoff },
        editor = editor,
        sides = { top = sides.top, right = sides.right, bottom = sides.bottom, left = sides.left },
        cursor_row = cursor_row,
        anchor_row = options.anchor_row or cursor_row,
        free = free_columns(source_win, area, options.free_col),
    },
        top
end

---@param value number
---@return boolean
local function is_size(value)
    return type(value) == "number"
        and value == value
        and value > 0
        and value < math.huge
        and (value <= 1 or value == math.floor(value))
end

M.is_size = is_size

--- Cells of a size: a part of `measure`, rounded down, or a count of cells.
---@param value number
---@param measure integer
---@return integer
local function cells(value, measure)
    if value <= 1 then
        return math.floor(value * measure)
    end
    return value
end

---@param ctx ScrollbarFrameContext
---@param options ScrollbarFrameRecipeOptions
---@param width_measure integer
---@param height_measure integer
---@return integer width
---@return integer height
local function size(ctx, options, width_measure, height_measure)
    local defaults = DEFAULT_SIZE[ctx.kind] or DEFAULT_SIZE.peek
    return cells(options.width or defaults.width, width_measure),
        cells(options.height or defaults.height, height_measure)
end

---@type table<ScrollbarFramePreset, fun(ctx: ScrollbarFrameContext, options: ScrollbarFrameRecipeOptions): ScrollbarFrameResult?>
M.place = {}

--- Beside the scrollbar and the minimap floats, with the content rows
--- centered on the anchor row.
M.place.scrollbar = function(ctx, options)
    local win = ctx.win
    local free = ctx.free
    local width, height = size(ctx, options, win.width - win.textoff, win.height)
    width = math.min(width, free.last_col - free.first_col)
    height = math.min(height, win.height)
    if width < 1 or height < 1 then
        return nil
    end
    local content_rows = height - ctx.sides.top - ctx.sides.bottom
    return {
        row = ctx.anchor_row - ctx.sides.top - math.floor(content_rows / 2),
        col = free.side == "E" and free.last_col - width or free.first_col,
        width = width,
        height = height,
    }
end

--- Below the cursor line, else above it. When neither side has room, the
--- frame takes the larger side and loses rows.
M.place.cursor = function(ctx, options)
    local win = ctx.win
    local text_width = win.width - win.textoff
    local width, height = size(ctx, options, text_width, win.height)
    width = math.min(width, text_width)
    height = math.min(height, win.height)
    if width < 1 or height < 1 then
        return nil
    end
    local frame_rows = ctx.sides.top + ctx.sides.bottom
    local cursor = ctx.cursor_row
    local below = win.height - cursor - 1
    local above = cursor
    -- Below the cursor line. When no side has room for one content row, the
    -- clamp keeps the frame in the window, over the cursor line.
    local row = cursor + 1
    if height > below then
        if height <= above then
            row = cursor - height
        elseif math.max(below, above) - frame_rows >= 1 then
            if below >= above then
                height = below
            else
                height = above
                row = 0
            end
        end
    end
    return { row = row, col = win.textoff, width = width, height = height }
end

--- At the center of the text area, or of the editor area with
--- `relative = "editor"`.
M.place.center = function(ctx, options)
    if options.relative == "editor" then
        local editor = ctx.editor
        local width, height = size(ctx, options, editor.width, editor.height)
        width = math.min(width, editor.width)
        height = math.min(height, editor.height)
        if width < 1 or height < 1 then
            return nil
        end
        return {
            relative = "editor",
            row = math.floor((editor.height - height) / 2),
            col = math.floor((editor.width - width) / 2),
            width = width,
            height = height,
        }
    end
    local win = ctx.win
    local text_width = win.width - win.textoff
    local width, height = size(ctx, options, text_width, win.height)
    width = math.min(width, text_width)
    height = math.min(height, win.height)
    if width < 1 or height < 1 then
        return nil
    end
    return {
        row = math.floor((win.height - height) / 2),
        col = win.textoff + math.floor((text_width - width) / 2),
        width = width,
        height = height,
    }
end

local NO_OPTIONS = {}

---@param value ScrollbarFrameValue
---@return fun(ctx: ScrollbarFrameContext): any
local function frame_function(value)
    if type(value) == "function" then
        return value
    end
    local place = M.place[value]
    return function(ctx)
        return place(ctx, NO_OPTIONS)
    end
end

local FIELDS = { "row", "col", "width", "height" }

--- Check a result and round it down. Nil, with a message, for an invalid
--- result.
---@param result any
---@return ScrollbarFrame? frame
---@return string? message
local function checked(result)
    if type(result) ~= "table" then
        return nil, string.format("returned a %s, not a table", type(result))
    end
    local relative = result.relative
    if relative ~= nil and relative ~= "win" and relative ~= "editor" then
        return nil, 'returned an invalid \'relative\': it must be "win" or "editor"'
    end
    ---@type ScrollbarFrame
    local rounded = { relative = relative or "win", row = 0, col = 0, width = 0, height = 0 }
    for _, field in ipairs(FIELDS) do
        local value = result[field]
        if value == nil then
            return nil, string.format("returned no '%s'", field)
        end
        if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
            return nil, string.format("returned an invalid '%s': it must be a finite number", field)
        end
        rounded[field] = math.floor(value)
    end
    for _, field in ipairs({ "width", "height" }) do
        if rounded[field] < 1 then
            return nil, string.format("returned a '%s' below 1", field)
        end
    end
    return rounded, nil
end

---@class ScrollbarFrame
---@field relative "win"|"editor"
---@field row integer Zero-based. For `"win"`, relative to the window. For `"editor"`, relative to the screen
---@field col integer
---@field width integer Outer columns, border included
---@field height integer Outer rows, border included

--- Run the frame of `value` and clamp the result into its area.
---@param path string Option that names the frame in a notification, for example `"glance.builtin.frame"`
---@param value ScrollbarFrameValue
---@param ctx ScrollbarFrameContext
---@param top integer Screen row of row 0 of the editor area
---@return ScrollbarFrame? frame
---@return "no_room"|"failed"? reason Nil with a frame. `"failed"` has notified
M.run = function(path, value, ctx, top)
    local ok, result = pcall(frame_function(value), ctx)
    if not ok then
        notify_once(path, "failed: " .. tostring(result))
        return nil, "failed"
    end
    if result == nil then
        return nil, "no_room"
    end
    local frame, message = checked(result)
    if frame == nil then
        notify_once(path, message or "returned an invalid result")
        return nil, "failed"
    end
    local area = frame.relative == "editor" and ctx.editor or ctx.win
    frame.width = math.min(frame.width, area.width)
    frame.height = math.min(frame.height, area.height)
    if frame.width < 1 or frame.height < 1 then
        return nil, "no_room"
    end
    frame.row = clamp(frame.row, 0, area.height - frame.height)
    frame.col = clamp(frame.col, 0, area.width - frame.width)
    if frame.relative == "editor" then
        frame.row = frame.row + top
    end
    return frame, nil
end

--- Build a context and run the frame.
---@param kind "peek"|"glance"
---@param path string
---@param value ScrollbarFrameValue
---@param source_win integer
---@param sides ScrollbarWindowSides
---@param options? ScrollbarFrameContextOptions
---@return ScrollbarFrame? frame
---@return "no_room"|"failed"? reason
M.layout = function(kind, path, value, source_win, sides, options)
    local ctx, top = M.context(kind, source_win, sides, options)
    return M.run(path, value, ctx, top)
end

--- Run `callback` on `VimResized`, and on `WinResized` when the source window
--- changed size. A resize of a float of the frame alone does not run it, so a
--- new layout does not start another one.
---@param group integer
---@param source_win fun(): integer?
---@param callback fun()
M.on_resize = function(group, source_win, callback)
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            callback()
        end,
    })
    vim.api.nvim_create_autocmd("WinResized", {
        group = group,
        callback = function()
            -- The vim.v.event type does not list the `windows` key of WinResized.
            local event = vim.v.event or {} ---@type table<string, any>
            local winid = source_win()
            for _, resized in ipairs(event.windows or {}) do
                if resized == winid then
                    callback()
                    return
                end
            end
        end,
    })
end

--- The `nvim_open_win` position keys of a frame.
---@param frame ScrollbarFrame
---@param source_win integer
---@param result table<string, any> Receives `relative`, `win`, `row`, and `col`
M.apply_position = function(frame, source_win, result)
    result.relative = frame.relative
    result.win = frame.relative == "win" and source_win or nil
    result.row = frame.row
    result.col = frame.col
end

return M
