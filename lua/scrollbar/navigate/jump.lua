--- Label mode: labels on the mark cells of the scrollbar of the current
--- window, in the style of flash.nvim.
---
--- - A lowercase label jumps to the line of its cell, the line that a click
---   uses. The jump adds a jumplist entry first.
--- - An uppercase label opens the peek float at the line, and label mode stays.
---   The label of the peeked cell shows in uppercase. `<CR>` jumps to the
---   peeked line.
--- - `<Esc>` closes the peek and ends label mode. Any other key ends label mode
---   and is dropped.
---
--- The targets freeze when label mode starts. The labels go to the cells
--- nearest to the cursor first, and the cells past the last label have none.
--- Label mode reveals an autohidden scrollbar and holds its hide delay, and it
--- shows a float that `hide_on_cursor` hides. It draws the labels again after
--- each render of its window. It ends when the float closes, when the float
--- changes size, or when the source buffer of the window changes.
---
--- With `scrollbar.jump.offset = 0`, the labels are overlay extmarks in their
--- own namespace on the float buffer, with a priority above the rows of the
--- renderer, so a render that writes a row again keeps them on top. With
--- another offset, each label is a float of one cell, relative to the
--- scrollbar float, so the mark cells stay visible. Neovim places a float
--- relative to a float again when a window opens or closes or the layout
--- changes, but not when only the parent float moves with
--- `nvim_win_set_config`. Label mode places the label floats again after each
--- render, so they follow the scrollbar float in both cases.

local config = require("scrollbar.config")
local float = require("scrollbar.shared.float")
local move = require("scrollbar.navigate.move")
local peek = require("scrollbar.navigate.peek")
local targets = require("scrollbar.navigate.targets")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("ScrollbarJumpLabels")
local AUGROUP = "ScrollbarJump"
local LABEL_GROUP = "ScrollbarJumpLabel"
-- Above the rows of the renderer, which have the default priority 4096.
local LABEL_PRIORITY = 10000
local CR = vim.keycode("<CR>")
-- With 'mousemoveevent', for example from hover, a pointer move is a key. It
-- does not end label mode.
local MOUSE_MOVE = vim.keycode("<MouseMove>")
-- A callback that ends label mode feeds this key, so that the wait for a key
-- returns. `getcharstr()` drops `<Ignore>`, and a user rarely has this key.
local WAKEUP = vim.keycode("<F35>")

---@class ScrollbarJumpTarget: ScrollbarNavigateCell
---@field label? string

---@class ScrollbarJumpLabelFloat
---@field win integer
---@field buf integer

---@class ScrollbarJumpSession
---@field source_win integer
---@field source_buf integer
---@field float_win integer
---@field float_buf integer
---@field width integer
---@field height integer
---@field anchor_offset integer Text row of the source window of the first content row of the float
---@field left_side integer Border columns on the left side of the float
---@field offset integer Columns from each mark cell to its label
---@field zindex integer z-index of the label floats, above the scrollbar float
---@field label_floats table<string, ScrollbarJumpLabelFloat> Floats of the labels by label, for a nonzero offset
---@field targets ScrollbarJumpTarget[]
---@field by_label table<string, ScrollbarJumpTarget>
---@field types? table<string, true>
---@field peeked? ScrollbarJumpTarget
---@field ended boolean
---@field waiting boolean
---@field redraw_scheduled boolean

---@type ScrollbarJumpSession?
local session

---@param message string
local function notify(message)
    vim.notify("[nvim-scrollbar] " .. message, vim.log.levels.WARN)
end

---@param session_state ScrollbarJumpSession
---@param target ScrollbarJumpTarget
---@return string text The label, in uppercase while the peek float shows its line
local function label_text(session_state, target)
    local label = target.label or ""
    if session_state.peeked == target then
        return label:upper()
    end
    return label
end

--- Show the label of `target` in its float, and open the float first if
--- necessary. The position counts from the first content cell of the
--- scrollbar float, so the border columns of the float count in the offset.
---@param session_state ScrollbarJumpSession
---@param target ScrollbarJumpTarget
local function draw_float(session_state, target)
    local placement = {
        relative = "win",
        win = session_state.float_win,
        row = target.row,
        col = target.col - 1 + session_state.offset,
        width = 1,
        height = 1,
        zindex = session_state.zindex,
    }
    local label_float = session_state.label_floats[target.label]
    if label_float == nil or not vim.api.nvim_win_is_valid(label_float.win) then
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
        placement.style = "minimal"
        placement.border = "none"
        placement.focusable = false
        placement.mouse = false
        placement.noautocmd = true
        local ok, win = pcall(vim.api.nvim_open_win, buf, false, placement)
        if not ok then
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
            return
        end
        -- `winblend = 0` keeps the label opaque under a global 'winblend'.
        float.configure_window(win, peek.OWNED_VAR, "NormalFloat:" .. LABEL_GROUP, 0)
        label_float = { win = win, buf = buf }
        session_state.label_floats[target.label] = label_float
    else
        vim.api.nvim_win_set_config(label_float.win, placement)
    end
    vim.api.nvim_buf_set_lines(label_float.buf, 0, -1, false, { label_text(session_state, target) })
end

---@param session_state ScrollbarJumpSession
local function close_floats(session_state)
    for _, label_float in pairs(session_state.label_floats) do
        if vim.api.nvim_win_is_valid(label_float.win) then
            pcall(vim.api.nvim_win_close, label_float.win, true)
        end
    end
    session_state.label_floats = {}
end

---@param session_state ScrollbarJumpSession
local function draw(session_state)
    if session_state.offset ~= 0 then
        if vim.api.nvim_win_is_valid(session_state.float_win) then
            for _, target in ipairs(session_state.targets) do
                if target.label ~= nil then
                    draw_float(session_state, target)
                end
            end
        end
        return
    end
    local float_buf = session_state.float_buf
    if not vim.api.nvim_buf_is_valid(float_buf) then
        return
    end
    vim.api.nvim_buf_clear_namespace(float_buf, NAMESPACE, 0, -1)
    local line_count = vim.api.nvim_buf_line_count(float_buf)
    for _, target in ipairs(session_state.targets) do
        if target.label ~= nil and target.row < line_count then
            vim.api.nvim_buf_set_extmark(float_buf, NAMESPACE, target.row, 0, {
                virt_text = { { label_text(session_state, target), LABEL_GROUP } },
                virt_text_win_col = target.col - 1,
                hl_mode = "replace",
                priority = LABEL_PRIORITY,
            })
        end
    end
end

--- End label mode from a callback. A wait for a key returns at once.
---@param session_state ScrollbarJumpSession
local function stop(session_state)
    if session_state.ended then
        return
    end
    session_state.ended = true
    if session_state.waiting then
        vim.api.nvim_feedkeys(WAKEUP, "n", false)
    end
end

---@param session_state ScrollbarJumpSession
---@param state ScrollbarWindowState
local function on_render(session_state, state)
    if state.source_win ~= session_state.source_win or session_state.ended then
        return
    end
    if
        state.float_buf ~= session_state.float_buf
        or state.source_buf ~= session_state.source_buf
        or state.width ~= session_state.width
        or state.height ~= session_state.height
    then
        stop(session_state)
        return
    end
    draw(session_state)
    -- `getcharstr()` does not redraw the screen. The redraw waits until the
    -- render of each window is done.
    if session_state.waiting and not session_state.redraw_scheduled then
        session_state.redraw_scheduled = true
        vim.schedule(function()
            session_state.redraw_scheduled = false
            if session_state.waiting and not session_state.ended then
                vim.cmd("redraw")
            end
        end)
    end
end

--- Sort the cells by the distance of their line from the cursor line, and give
--- a label to each cell while labels remain.
---@param cells ScrollbarNavigateCell[]
---@param cursor_line integer
---@param labels string
---@return ScrollbarJumpTarget[] targets
---@return table<string, ScrollbarJumpTarget> by_label
local function assign_labels(cells, cursor_line, labels)
    local order = {}
    for index, cell in ipairs(cells) do
        order[index] = cell
    end
    table.sort(order, function(left, right)
        local left_distance = math.abs(left.line - cursor_line)
        local right_distance = math.abs(right.line - cursor_line)
        if left_distance ~= right_distance then
            return left_distance < right_distance
        end
        if left.row ~= right.row then
            return left.row < right.row
        end
        return left.col < right.col
    end)
    local by_label = {}
    for index, target in ipairs(order) do
        if index > #labels then
            break
        end
        local label = labels:sub(index, index)
        ---@cast target ScrollbarJumpTarget
        target.label = label
        by_label[label] = target
    end
    ---@type ScrollbarJumpTarget[]
    local labeled = cells
    return labeled, by_label
end

---@param session_state ScrollbarJumpSession
---@param target ScrollbarJumpTarget
local function open_peek(session_state, target)
    session_state.peeked = target
    local free_col
    if session_state.offset ~= 0 then
        -- The column of the label in the source window. The peek float does
        -- not cover it.
        local float_col = vim.fn.win_screenpos(session_state.float_win)[2]
        local source_col = vim.fn.win_screenpos(session_state.source_win)[2]
        free_col = float_col - source_col + session_state.left_side + target.col - 1 + session_state.offset
    end
    peek.open(session_state.source_win, target.line, {
        anchor_row = session_state.anchor_offset + target.row,
        types = session_state.types,
        free_col = free_col,
    })
    draw(session_state)
end

---@param session_state ScrollbarJumpSession
---@param target ScrollbarJumpTarget
local function jump(session_state, target)
    peek.close()
    if move.line(session_state.source_win, session_state.source_buf, target.line, true) then
        local scheduler = package.loaded["scrollbar.scheduler"]
        if scheduler ~= nil then
            scheduler.invalidate_window(session_state.source_win)
        end
    end
end

--- Read keys until label mode ends.
---@param session_state ScrollbarJumpSession
local function read_keys(session_state)
    while not session_state.ended do
        -- `getcharstr()` does not redraw the screen, so the labels and the
        -- peek float show only after this redraw.
        vim.cmd("redraw")
        session_state.waiting = true
        local ok, key = pcall(vim.fn.getcharstr)
        session_state.waiting = false
        if not ok or session_state.ended then
            return
        end
        if key ~= MOUSE_MOVE then
            local target = session_state.by_label[key]
            local peek_target = key:match("^%u$") and session_state.by_label[key:lower()] or nil
            if target ~= nil then
                jump(session_state, target)
                return
            elseif peek_target ~= nil then
                open_peek(session_state, peek_target)
            elseif key == CR and session_state.peeked ~= nil then
                jump(session_state, session_state.peeked)
                return
            else
                -- `<Esc>` and every other key end label mode. The key is
                -- dropped.
                return
            end
        end
    end
end

--- Whether label mode is active.
---@return boolean
M.active = function()
    return session ~= nil
end

--- End label mode, for example on a new setup.
M.cancel = function()
    if session ~= nil then
        stop(session)
    end
end

---@class ScrollbarJumpOptions
---@field types? table<string, true> Mark types that get labels. Nil labels every type except `Cursor`

--- Start label mode in the current window. The function returns when label
--- mode ends.
---@param options? ScrollbarJumpOptions
M.run = function(options)
    options = options or {}
    if session ~= nil then
        return
    end
    local source_win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_config(source_win).relative ~= "" then
        notify("jump works only in a normal window")
        return
    end
    local renderer = require("scrollbar.renderer")
    local scheduler = require("scrollbar.scheduler")

    renderer.reveal(source_win)
    local held = scheduler.hold_window(source_win)
    float.show_over_cursor(source_win, true)
    local augroup
    local remove_listener

    local function restore()
        float.show_over_cursor(source_win, false)
        if held then
            scheduler.resume_window(source_win)
        end
        scheduler.invalidate_window(source_win)
    end

    scheduler.invalidate_window(source_win)
    scheduler.flush()
    local state = renderer.get_state(source_win)
    if state == nil then
        restore()
        notify("jump: the current window has no scrollbar")
        return
    end
    local cells = targets.cells(source_win, options.types)
    if #cells == 0 then
        restore()
        notify("jump: the scrollbar has no marks to jump to")
        return
    end

    local cursor_line = vim.api.nvim_win_get_cursor(source_win)[1] - 1
    local jump_config = config.get().jump
    local labeled, by_label = assign_labels(cells, cursor_line, jump_config.labels)
    ---@type ScrollbarJumpSession
    local current = {
        source_win = source_win,
        source_buf = state.source_buf,
        float_win = state.float_win,
        float_buf = state.float_buf,
        width = state.width,
        height = state.height,
        anchor_offset = state.config.placement.row + state.sides.top,
        left_side = state.sides.left,
        offset = jump_config.offset,
        zindex = (state.float_config.zindex or 50) + 1,
        label_floats = {},
        targets = labeled,
        by_label = by_label,
        types = options.types,
        ended = false,
        waiting = false,
        redraw_scheduled = false,
    }
    session = current

    local ok, err = xpcall(function()
        remove_listener = renderer.on_render(function(rendered)
            on_render(current, rendered)
        end)
        augroup = vim.api.nvim_create_augroup(AUGROUP, { clear = true })
        vim.api.nvim_create_autocmd("WinClosed", {
            group = augroup,
            callback = function(args)
                local closed = tonumber(args.match)
                if closed == current.float_win or closed == current.source_win then
                    stop(current)
                end
            end,
        })
        vim.api.nvim_create_autocmd({ "BufWinEnter", "BufWipeout" }, {
            group = augroup,
            callback = function(args)
                if
                    args.buf == current.float_buf
                    or not vim.api.nvim_win_is_valid(current.source_win)
                    or vim.api.nvim_win_get_buf(current.source_win) ~= current.source_buf
                then
                    stop(current)
                end
            end,
        })
        draw(current)
        read_keys(current)
    end, debug.traceback)

    session = nil
    current.ended = true
    if remove_listener ~= nil then
        remove_listener()
    end
    if augroup ~= nil then
        pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end
    peek.close()
    close_floats(current)
    if vim.api.nvim_buf_is_valid(current.float_buf) then
        vim.api.nvim_buf_clear_namespace(current.float_buf, NAMESPACE, 0, -1)
    end
    restore()
    if not ok then
        error(err, 0)
    end
end

M.NAMESPACE = NAMESPACE

--- The label floats of the active label mode, by label. For tests.
---@return table<string, integer>
M._label_floats = function()
    local result = {}
    if session ~= nil then
        for label, label_float in pairs(session.label_floats) do
            result[label] = label_float.win
        end
    end
    return result
end

return M
