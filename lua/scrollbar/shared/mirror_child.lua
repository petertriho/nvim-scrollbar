--- Child side of the buffer mirror protocol. `scrollbar.shared.mirror` sends
--- this file as source to a headless child Neovim. The child runs with
--- `--noplugin` and cannot `require()` plugin modules, so this file uses only
--- the `vim` API.
---
--- The child keeps one scratch buffer for each mirrored parent buffer. A
--- snapshot (`snapshot_start`, `snapshot_chunk`, `snapshot_complete`) copies
--- the text, and each `delta` applies one parent `on_lines` change. The id of
--- a mirror changes with each snapshot, and its version changes with each
--- delta. Thus a request whose mirror id and version match sees exactly the
--- parent text.
---
--- A worker adds its own request kinds to `handlers` and can set the
--- `on_snapshot_start` and `on_snapshot_complete` hooks.

local M = {}

---@class ScrollbarMirrorChildMirror
---@field child_buf? integer
---@field id integer
---@field version integer
---@field complete boolean
---@field lines? string[] Snapshot lines received so far, until the snapshot completes

---@class ScrollbarMirrorChildOptions
---@field callback_global string Parent global that receives the events of `send`
---@field child_global string Child global that the parent dispatch calls
---@field timing? boolean Send `mirror_complete` and `delta_complete` events

---@class ScrollbarMirrorChild
---@field send fun(event: string, payload: table)
---@field mirror fun(bufnr: integer): ScrollbarMirrorChildMirror?
---@field current fun(payload: { bufnr: integer, mirror: { id: integer, version: integer } }): ScrollbarMirrorChildMirror?
---@field handlers table<string, fun(payload: table)>
---@field on_snapshot_start? fun(mirror: ScrollbarMirrorChildMirror, payload: table)
---@field on_snapshot_complete? fun(mirror: ScrollbarMirrorChildMirror, payload: table)

---@param session string
---@param options ScrollbarMirrorChildOptions
---@return ScrollbarMirrorChild
M.new = function(session, options)
    ---@type table<integer, ScrollbarMirrorChildMirror>
    local mirrors = {}
    local timing = options.timing == true
    local callback_source = string.format(
        [[
local session, event, payload = ...
local callback = rawget(_G, %q)
if callback ~= nil then
    callback(session, event, payload)
end
]],
        options.callback_global
    )

    ---@param event string
    ---@param payload table
    local function send(event, payload)
        vim.rpcnotify(1, "nvim_exec_lua", callback_source, { session, event, payload })
    end

    ---@type ScrollbarMirrorChild
    local child = {
        send = send,
        mirror = function(bufnr)
            return mirrors[bufnr]
        end,
        -- The mirror of a request, or nil after a `mirror_invalid` event when
        -- the mirror does not hold the text that the request was made for.
        current = function(payload)
            local mirror = mirrors[payload.bufnr]
            if
                mirror == nil
                or not mirror.complete
                or mirror.id ~= payload.mirror.id
                or mirror.version ~= payload.mirror.version
            then
                send("mirror_invalid", { bufnr = payload.bufnr, id = payload.mirror.id })
                return nil
            end
            return mirror
        end,
        handlers = {},
    }

    ---@param mirror ScrollbarMirrorChildMirror
    ---@return integer
    local function ensure_buffer(mirror)
        if mirror.child_buf == nil or not vim.api.nvim_buf_is_valid(mirror.child_buf) then
            mirror.child_buf = vim.api.nvim_create_buf(false, true)
        end
        return mirror.child_buf
    end

    ---@param mirror ScrollbarMirrorChildMirror
    local function delete_buffer(mirror)
        if mirror.child_buf ~= nil and vim.api.nvim_buf_is_valid(mirror.child_buf) then
            pcall(vim.api.nvim_buf_delete, mirror.child_buf, { force = true })
        end
    end

    local function handle(kind, payload)
        if kind == "snapshot_start" then
            local previous = mirrors[payload.bufnr]
            local mirror = {
                child_buf = previous and previous.child_buf or nil,
                id = payload.id,
                version = payload.version,
                complete = false,
                lines = {},
            }
            mirrors[payload.bufnr] = mirror
            if child.on_snapshot_start ~= nil then
                child.on_snapshot_start(mirror, payload)
            end
        elseif kind == "snapshot_chunk" then
            local mirror = mirrors[payload.bufnr]
            if mirror ~= nil and mirror.id == payload.id and mirror.lines ~= nil and #mirror.lines == payload.start then
                for _, line in ipairs(payload.lines) do
                    mirror.lines[#mirror.lines + 1] = line
                end
            end
        elseif kind == "snapshot_complete" then
            local mirror = mirrors[payload.bufnr]
            if
                mirror == nil
                or mirror.id ~= payload.id
                or mirror.lines == nil
                or #mirror.lines ~= payload.line_count
            then
                send("mirror_invalid", { bufnr = payload.bufnr, id = payload.id })
                return
            end
            local child_buf = ensure_buffer(mirror)
            vim.api.nvim_buf_set_lines(child_buf, 0, -1, false, mirror.lines)
            mirror.lines = nil
            mirror.version = payload.version
            mirror.complete = true
            if timing then
                send("mirror_complete", {
                    bufnr = payload.bufnr,
                    id = payload.id,
                    version = payload.version,
                    changedtick = payload.changedtick,
                })
            end
            if child.on_snapshot_complete ~= nil then
                child.on_snapshot_complete(mirror, payload)
            end
        elseif kind == "delta" then
            local mirror = mirrors[payload.bufnr]
            if
                mirror == nil
                or not mirror.complete
                or mirror.id ~= payload.id
                or mirror.version ~= payload.from_version
            then
                send("mirror_invalid", { bufnr = payload.bufnr, id = payload.id })
                return
            end
            vim.api.nvim_buf_set_lines(mirror.child_buf, payload.first, payload.last, false, payload.lines)
            mirror.version = payload.version
            if timing then
                send("delta_complete", {
                    bufnr = payload.bufnr,
                    id = payload.id,
                    version = payload.version,
                    changedtick = payload.changedtick,
                })
            end
        elseif kind == "detach" then
            local mirror = mirrors[payload.bufnr]
            if mirror ~= nil then
                delete_buffer(mirror)
            end
            mirrors[payload.bufnr] = nil
        elseif kind == "dispose" then
            for _, mirror in pairs(mirrors) do
                delete_buffer(mirror)
            end
            mirrors = {}
        else
            local handler = child.handlers[kind]
            if handler ~= nil then
                handler(payload)
            end
        end
    end

    -- selene: allow(global_usage)
    _G[options.child_global] = {
        session = session,
        handle = handle,
        fail = function(reason)
            send("failure", { reason = reason })
        end,
    }
    return child
end

return M
