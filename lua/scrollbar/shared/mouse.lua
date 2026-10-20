--- Shared mouse plumbing for the scrollbar and the minimap floats.
---
--- `new` builds one controller for one renderer. The controller owns the
--- runtime (renderer, scheduler, augroup, float focus watcher), the active
--- interaction, the buffer-local mouse mappings of the floats, and the
--- lifecycle of an interaction:
---
--- - A press that the policy accepts focuses the float. If the policy marks
---   the press as held, the press first holds the autohide deadline of its
---   source window.
--- - The end of an interaction returns focus to the source window, resumes a
---   held deadline with a full delay, and attaches the mappings again.
--- - A closed float or source window, or a deleted buffer, cancels the
---   interaction.
---
--- Each renderer keeps its own policy: what a press starts, and what a drag
--- and a release do.

local float_focus = require("scrollbar.shared.float_focus")

local M = {}

local MAPPINGS = { "<LeftMouse>", "<LeftDrag>", "<LeftRelease>" }

---@alias ScrollbarMouseCoreState ScrollbarWindowState|ScrollbarMinimapRendererState
---@alias ScrollbarMouseCoreInteraction ScrollbarInteractionState|ScrollbarMinimapMouseInteraction

---@class ScrollbarMouseCoreRenderer
---@field get_state_by_float fun(float_win: integer): ScrollbarMouseCoreState?
---@field set_state_callback fun(callback: fun(state: ScrollbarMouseCoreState)?)
---@field set_handle_pressed? fun(float_win: integer, pressed: boolean): boolean

---@class ScrollbarMouseCoreScheduler
---@field invalidate_window fun(winid: integer): boolean
---@field hold_window? fun(winid: integer): boolean
---@field resume_window? fun(winid: integer): boolean

---@class ScrollbarMouseCoreOptions
---@field renderer? ScrollbarMouseCoreRenderer
---@field scheduler? ScrollbarMouseCoreScheduler

---@class ScrollbarMouseCoreRuntime
---@field renderer ScrollbarMouseCoreRenderer
---@field scheduler ScrollbarMouseCoreScheduler
---@field augroup integer
---@field attached table<integer, true>
---@field unwatch fun()

---@class ScrollbarMouseCoreSpec
---@field name string Augroup name and namespace of the key listener
---@field renderer string Module of the default renderer
---@field scheduler string Module of the default scheduler
---@field start fun(state: ScrollbarMouseCoreState, row: integer, col: integer, screen_row: integer, screen_col: integer): ScrollbarMouseCoreInteraction? Interaction of a press inside the float, or nil to ignore the press
---@field on_press? fun(current: ScrollbarMouseCoreInteraction, state: ScrollbarMouseCoreState, active: ScrollbarMouseCoreRuntime) Runs after the hold and before the float takes focus
---@field drag fun(current: ScrollbarMouseCoreInteraction)
---@field release fun(current: ScrollbarMouseCoreInteraction) The controller ends the interaction after this call
---@field on_finish? fun(current: ScrollbarMouseCoreInteraction, active?: ScrollbarMouseCoreRuntime)

---@class ScrollbarMouseCore
---@field setup fun(options?: ScrollbarMouseCoreOptions)
---@field dispose fun()
---@field press fun(float_win?: integer)
---@field drag fun()
---@field release fun()
---@field cancel fun()
---@field attach fun(state: ScrollbarMouseCoreState)
---@field get_interaction fun(): ScrollbarMouseCoreInteraction?
---@field interaction_state fun(current: ScrollbarMouseCoreInteraction): ScrollbarMouseCoreState?
---@field navigate fun(current: ScrollbarMouseCoreInteraction, line: integer): boolean
---@field invalidate fun(current: ScrollbarMouseCoreInteraction)

---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
M.clamp = function(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

---@param winid integer
---@return boolean
local function valid_window(winid)
    return type(winid) == "number" and vim.api.nvim_win_is_valid(winid)
end
M.valid_window = valid_window

---@param state ScrollbarMouseCoreState
---@return boolean
local function valid_state(state)
    return valid_window(state.source_win)
        and valid_window(state.float_win)
        and vim.api.nvim_buf_is_valid(state.source_buf)
        and vim.api.nvim_buf_is_valid(state.float_buf)
        and vim.api.nvim_win_get_buf(state.source_win) == state.source_buf
        and vim.api.nvim_win_get_buf(state.float_win) == state.float_buf
end

---@param current ScrollbarMouseCoreInteraction
---@return boolean
local function valid_source(current)
    return valid_window(current.source_win)
        and vim.api.nvim_buf_is_valid(current.source_buf)
        and vim.api.nvim_win_get_buf(current.source_win) == current.source_buf
end
M.valid_source = valid_source

--- Pointer position relative to the content of `float_win`, also when the
--- pointer is outside it during a drag. A border cell is outside the content.
---@param float_win integer
---@param sides ScrollbarWindowSides Border size of each side of the float
---@return integer mouse_winid
---@return integer row 0-based row relative to the content
---@return integer col 1-based column relative to the content
---@return integer screen_row
---@return integer screen_col
M.mouse_position = function(float_win, sides)
    local mouse = vim.fn.getmousepos()
    -- `winrow`, `wincol`, and `win_screenpos` count the border.
    if mouse.winid == float_win then
        return mouse.winid, mouse.winrow - 1 - sides.top, mouse.wincol - sides.left, mouse.screenrow, mouse.screencol
    end
    local position = vim.fn.win_screenpos(float_win)
    return mouse.winid,
        mouse.screenrow - position[1] - sides.top,
        mouse.screencol - position[2] + 1 - sides.left,
        mouse.screenrow,
        mouse.screencol
end

---@param spec ScrollbarMouseCoreSpec
---@return ScrollbarMouseCore
M.new = function(spec)
    ---@type ScrollbarMouseCoreRuntime?
    local runtime

    ---@type ScrollbarMouseCoreInteraction?
    local interaction

    local core = {}

    ---@param active ScrollbarMouseCoreRuntime
    ---@param float_buf integer
    local function detach(active, float_buf)
        if not active.attached[float_buf] then
            return
        end
        for _, lhs in ipairs(MAPPINGS) do
            pcall(vim.keymap.del, "n", lhs, { buffer = float_buf })
        end
        active.attached[float_buf] = nil
    end

    ---@param callback fun()
    ---@param fallback_source? integer
    ---@return fun()
    local function guarded(callback, fallback_source)
        return function()
            local ok = xpcall(callback, debug.traceback)
            if not ok then
                if interaction ~= nil then
                    core.cancel()
                elseif fallback_source ~= nil then
                    float_focus.restore(fallback_source)
                end
            end
        end
    end

    ---@param current ScrollbarMouseCoreInteraction
    ---@param resume_deadline boolean
    local function finish(current, resume_deadline)
        if spec.on_finish ~= nil then
            spec.on_finish(current, runtime)
        end
        interaction = nil
        float_focus.restore(current.source_win)
        local active = runtime
        if resume_deadline and current.held and active ~= nil then
            pcall(active.scheduler.resume_window, current.source_win)
        end
        if active ~= nil then
            local state = active.renderer.get_state_by_float(current.float_win)
            if state ~= nil then
                core.attach(state)
            end
        end
    end

    --- The state of the float of the interaction, or nil when the float, its
    --- source window, or their buffers changed since the press.
    ---@param current ScrollbarMouseCoreInteraction
    ---@return ScrollbarMouseCoreState?
    core.interaction_state = function(current)
        local active = runtime
        if active == nil then
            return nil
        end
        local state = active.renderer.get_state_by_float(current.float_win)
        if
            state == nil
            or state.source_win ~= current.source_win
            or state.source_buf ~= current.source_buf
            or state.float_buf ~= current.float_buf
            or not valid_state(state)
        then
            return nil
        end
        return state
    end

    ---@param current ScrollbarMouseCoreInteraction
    core.invalidate = function(current)
        local active = runtime
        if active ~= nil then
            pcall(active.scheduler.invalidate_window, current.source_win)
        end
    end

    --- Move the source cursor to the 0-based `line`, open folds at it, and
    --- center it.
    ---@param current ScrollbarMouseCoreInteraction
    ---@param line integer
    ---@return boolean
    core.navigate = function(current, line)
        if not valid_source(current) then
            return false
        end
        local line_count = vim.api.nvim_buf_line_count(current.source_buf)
        line = M.clamp(line, 0, math.max(0, line_count - 1))
        local ok = pcall(vim.api.nvim_win_call, current.source_win, function()
            vim.api.nvim_win_set_cursor(current.source_win, { line + 1, 0 })
            vim.cmd("normal! zv")
            vim.cmd("normal! zz")
        end)
        if ok then
            core.invalidate(current)
        end
        return ok
    end

    ---@param float_win? integer
    core.press = function(float_win)
        local active = runtime
        if active == nil then
            return
        end
        if interaction ~= nil then
            core.cancel()
        end

        local state = active.renderer.get_state_by_float(float_win or vim.fn.getmousepos().winid)
        if state == nil or not valid_state(state) or not state.config.mouse then
            return
        end
        local _, row, col, screen_row, screen_col = M.mouse_position(state.float_win, state.sides)
        if row < 0 or row >= state.height or col < 1 or col > state.width then
            return
        end
        local current = spec.start(state, row, col, screen_row, screen_col)
        if current == nil then
            return
        end

        interaction = current
        if current.held then
            pcall(active.scheduler.hold_window, state.source_win)
        end
        if spec.on_press ~= nil then
            spec.on_press(current, state, active)
        end
        if valid_window(state.float_win) then
            pcall(vim.api.nvim_set_current_win, state.float_win)
        end
    end

    core.drag = function()
        local current = interaction
        if current ~= nil then
            spec.drag(current)
        end
    end

    core.release = function()
        local current = interaction
        if current == nil then
            return
        end
        spec.release(current)
        if interaction == current then
            finish(current, true)
        end
    end

    core.cancel = function()
        local current = interaction
        if current ~= nil then
            finish(current, true)
        end
    end

    --- Attach the mouse mappings to the float buffer of `state`. A float keeps
    --- its mappings during its own interaction even when its configuration
    --- turns the mouse off, so the release still arrives.
    ---@param state ScrollbarMouseCoreState
    core.attach = function(state)
        local active = runtime
        if active == nil or not valid_state(state) then
            return
        end
        local current = interaction
        if not state.config.mouse and (current == nil or current.float_buf ~= state.float_buf) then
            detach(active, state.float_buf)
            return
        end
        if active.attached[state.float_buf] then
            return
        end

        vim.keymap.set(
            "n",
            "<LeftMouse>",
            guarded(function()
                core.press(state.float_win)
            end, state.source_win),
            { buffer = state.float_buf, nowait = true, silent = true }
        )
        vim.keymap.set("n", "<LeftDrag>", guarded(core.drag), {
            buffer = state.float_buf,
            nowait = true,
            silent = true,
        })
        vim.keymap.set("n", "<LeftRelease>", guarded(core.release), {
            buffer = state.float_buf,
            nowait = true,
            silent = true,
        })
        active.attached[state.float_buf] = true
    end

    ---@param options? ScrollbarMouseCoreOptions
    core.setup = function(options)
        core.dispose()
        options = options or {}
        local active_renderer = options.renderer or require(spec.renderer)
        local active_scheduler = options.scheduler or require(spec.scheduler)
        local augroup = vim.api.nvim_create_augroup(spec.name, { clear = true })
        runtime = {
            renderer = active_renderer,
            scheduler = active_scheduler,
            augroup = augroup,
            attached = {},
            unwatch = float_focus.watch({
                name = spec.name,
                group = augroup,
                get_state = active_renderer.get_state_by_float,
                interacting = function()
                    return interaction ~= nil
                end,
                press = function(float_win, source_win)
                    guarded(function()
                        core.press(float_win)
                    end, source_win)()
                end,
            }),
        }

        vim.api.nvim_create_autocmd("WinClosed", {
            group = augroup,
            callback = function(args)
                local current = interaction
                local closed = tonumber(args.match)
                if current ~= nil and (closed == current.float_win or closed == current.source_win) then
                    core.cancel()
                end
            end,
        })
        vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
            group = augroup,
            callback = function(args)
                local active = runtime
                if active ~= nil then
                    active.attached[args.buf] = nil
                end
                local current = interaction
                if current ~= nil and (args.buf == current.float_buf or args.buf == current.source_buf) then
                    core.cancel()
                end
            end,
        })

        active_renderer.set_state_callback(core.attach)
    end

    core.dispose = function()
        local active = runtime
        if active == nil then
            return
        end
        if interaction ~= nil then
            finish(interaction, false)
        end
        runtime = nil
        active.unwatch()
        active.renderer.set_state_callback(nil)
        for float_buf in pairs(active.attached) do
            detach(active, float_buf)
        end
        pcall(vim.api.nvim_del_augroup_by_id, active.augroup)
    end

    --- A copy of the active interaction, or nil when no active interaction
    --- holds the autohide deadline.
    ---@return ScrollbarMouseCoreInteraction?
    core.get_interaction = function()
        return interaction and interaction.held and vim.deepcopy(interaction) or nil
    end

    return core
end

return M
