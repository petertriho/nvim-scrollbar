local M = { name = "vgit", update_delay_ms = 50 }

---@class ScrollbarVgitSign
---@field col integer
---@field name string

---@class ScrollbarVgitGitBuffer
---@field bufnr integer
---@field state { signs: ScrollbarVgitSign[] }?

---@class ScrollbarVgitBufferStore
---@field get fun(buffer: { bufnr: integer }): ScrollbarVgitGitBuffer?
---@field on? fun(event_types: string|string[], handler: fun(git_buffer: ScrollbarVgitGitBuffer, event_type: string))

---@class ScrollbarVgitSubscription
---@field store ScrollbarVgitBufferStore
---@field generation integer

---@type { context: ScrollbarProviderContext?, generation: integer, subscription: ScrollbarVgitSubscription? }
local state = {
    context = nil,
    generation = 0,
    subscription = nil,
}

---@type table<integer, integer>
local pending_generation = {}

---@return ScrollbarVgitBufferStore?
local function get_store()
    local ok, store = pcall(require, "vgit.git.git_buffer_store")
    if not ok or type(store) ~= "table" or type(store.get) ~= "function" then
        return nil
    end
    return store
end

---@return table?
local function get_usage_main()
    local ok, settings = pcall(require, "vgit.settings.signs")
    if not ok or type(settings) ~= "table" or type(settings.get) ~= "function" then
        return nil
    end
    local usage_ok, usage = pcall(settings.get, settings, "usage")
    if not usage_ok or type(usage) ~= "table" or type(usage.main) ~= "table" then
        return nil
    end
    return usage.main
end

---@return table<string, string>
local function name_to_type_map()
    local main = get_usage_main()
    if main == nil then
        return {}
    end
    return {
        [main.add] = "VGitAdd",
        [main.remove] = "VGitDelete",
        [main.change] = "VGitChange",
    }
end

---@type fun(store: ScrollbarVgitBufferStore)
local ensure_subscription

---@param bufnr integer
---@return ScrollbarMark[]
local function collect_marks(bufnr)
    local store = get_store()
    if store == nil then
        return {}
    end

    ensure_subscription(store)

    local git_buffer = store.get({ bufnr = bufnr })
    if type(git_buffer) ~= "table" then
        return {}
    end

    local state_table = git_buffer.state
    if type(state_table) ~= "table" then
        return {}
    end

    local name_map = name_to_type_map()
    local marks = {}
    for _, sign in ipairs(state_table.signs or {}) do
        local mark_type = name_map[sign.name]
        if mark_type ~= nil and type(sign.col) == "number" and sign.col == math.floor(sign.col) and sign.col >= 0 then
            table.insert(marks, { line = sign.col, type = mark_type })
        end
    end
    return marks
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function update_buffer(context, bufnr)
    if not context.is_buffer_eligible(bufnr) then
        context.clear_marks(bufnr)
        return
    end
    local ok, marks = pcall(collect_marks, bufnr)
    if ok then
        context.set_marks(bufnr, marks)
    else
        context.clear_marks(bufnr)
    end
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function schedule_update(context, bufnr)
    if not context.is_buffer_eligible(bufnr) then
        context.clear_marks(bufnr)
        return
    end
    pending_generation[bufnr] = (pending_generation[bufnr] or 0) + 1
    local generation = pending_generation[bufnr]
    vim.defer_fn(function()
        if pending_generation[bufnr] ~= generation then
            return
        end
        if state.context ~= context then
            return
        end
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end
        update_buffer(context, bufnr)
    end, M.update_delay_ms)
end

---@param store ScrollbarVgitBufferStore
ensure_subscription = function(store)
    local generation = state.generation
    local subscription = state.subscription
    if subscription ~= nil and subscription.store == store and subscription.generation == generation then
        return
    end

    state.subscription = nil
    if state.context == nil or type(store.on) ~= "function" then
        return
    end

    ---@type ScrollbarVgitSubscription
    local token = {
        store = store,
        generation = generation,
    }
    local ok = pcall(store.on, { "attach", "reload", "change", "sync" }, function(git_buffer)
        if state.subscription ~= token or state.generation ~= token.generation then
            return
        end
        local context = state.context
        if context == nil then
            return
        end
        if type(git_buffer) ~= "table" then
            return
        end
        local bufnr = git_buffer.bufnr
        if type(bufnr) ~= "number" then
            return
        end
        schedule_update(context, bufnr)
    end)
    if ok and state.context ~= nil and state.generation == generation and state.subscription == nil then
        state.subscription = token
    end
end

---@param context ScrollbarProviderContext
M.setup = function(context)
    state.subscription = nil
    state.generation = state.generation + 1
    state.context = context

    local store = get_store()
    if store ~= nil then
        ensure_subscription(store)
    end
end

---@param bufnr integer
---@return ScrollbarMark[]
M.refresh = function(bufnr)
    return collect_marks(bufnr)
end

M.dispose = function()
    state.subscription = nil
    state.context = nil
    pending_generation = {}
end

return M
