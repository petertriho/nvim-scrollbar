local bit = require("bit")

local M = {
    name = "lsp_semantic_tokens",
    targets = { scrollbar = false, minimap = true },
    refresh_owner = { minimap_buffer = "provider" },
    debounce_ms = 80,
    priorities = {
        base = 200,
        modifier = 201,
        type_modifier = 202,
    },
}

---@class ScrollbarLspSemanticClientState
---@field generation integer
---@field version integer
---@field request_id? integer
---@field spans ScrollbarMinimapSourceSpan[]

---@class ScrollbarLspSemanticBufferState
---@field generation integer
---@field schedule_generation integer
---@field clients table<integer, ScrollbarLspSemanticClientState>

---@type { context: ScrollbarProviderContext?, generation: integer, buffers: table<integer, ScrollbarLspSemanticBufferState> }
local state = {
    context = nil,
    generation = 0,
    buffers = {},
}

---@param value any
---@return boolean
local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
end

---@param client table
---@param method string
---@param bufnr integer
---@return boolean
local function supports_method(client, method, bufnr)
    if type(client.supports_method) ~= "function" then
        return true
    end
    local ok, supported = pcall(client.supports_method, client, method, bufnr)
    return ok and supported == true
end

---@param client table
---@param bufnr integer
---@return string?
local function request_method(client, bufnr)
    local capabilities = client.server_capabilities
    local semantic = type(capabilities) == "table" and capabilities.semanticTokensProvider or nil
    if type(semantic) ~= "table" then
        return nil
    end
    if
        semantic.full ~= nil
        and semantic.full ~= false
        and supports_method(client, "textDocument/semanticTokens/full", bufnr)
    then
        return "textDocument/semanticTokens/full"
    end
    if
        semantic.range ~= nil
        and semantic.range ~= false
        and supports_method(client, "textDocument/semanticTokens/range", bufnr)
    then
        return "textDocument/semanticTokens/range"
    end
end

---@param line string
---@param encoding string
---@return integer
local function unit_length(line, encoding)
    local ok, length = pcall(vim.str_utfindex, line, encoding)
    return ok and length or #line
end

---@param line string
---@param encoding string
---@param index integer
---@return integer
local function byte_index(line, encoding, index)
    local ok, result = pcall(vim.str_byteindex, line, encoding, index, false)
    return ok and result or math.min(index, #line)
end

---@param name string
---@param filetype string
---@return string
local function highlight_group(name, filetype)
    if filetype == "" then
        return name
    end
    return name .. "." .. filetype
end

---@param spans ScrollbarMinimapSourceSpan[]
---@param line integer
---@param start_col integer
---@param end_col integer
---@param token_type string
---@param modifiers string[]
---@param filetype string
local function append_layers(spans, line, start_col, end_col, token_type, modifiers, filetype)
    spans[#spans + 1] = {
        line = line,
        start_col = start_col,
        end_col = end_col,
        highlight = highlight_group("@lsp.type." .. token_type, filetype),
        priority = M.priorities.base,
    }
    for _, modifier in ipairs(modifiers) do
        spans[#spans + 1] = {
            line = line,
            start_col = start_col,
            end_col = end_col,
            highlight = highlight_group("@lsp.mod." .. modifier, filetype),
            priority = M.priorities.modifier,
        }
    end
    for _, modifier in ipairs(modifiers) do
        spans[#spans + 1] = {
            line = line,
            start_col = start_col,
            end_col = end_col,
            highlight = highlight_group("@lsp.typemod." .. token_type .. "." .. modifier, filetype),
            priority = M.priorities.type_modifier,
        }
    end
end

---@param bufnr integer
---@param client table
---@param data any
---@return ScrollbarMinimapSourceSpan[]?
local function decode_tokens(bufnr, client, data)
    if type(data) ~= "table" or #data % 5 ~= 0 then
        return nil
    end
    local semantic = type(client.server_capabilities) == "table" and client.server_capabilities.semanticTokensProvider
        or nil
    local legend = type(semantic) == "table" and semantic.legend or nil
    local token_types = type(legend) == "table" and legend.tokenTypes or nil
    local token_modifiers = type(legend) == "table" and legend.tokenModifiers or nil
    if type(token_types) ~= "table" or type(token_modifiers) ~= "table" then
        return nil
    end

    local encoding = client.offset_encoding
    if encoding ~= "utf-8" and encoding ~= "utf-16" and encoding ~= "utf-32" then
        encoding = "utf-16"
    end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local filetype = vim.bo[bufnr].filetype
    local eol_units = vim.bo[bufnr].fileformat == "dos" and 2 or 1
    local spans = {}
    local token_line
    local token_start = 0

    for index = 1, #data, 5 do
        local delta_line = data[index]
        local delta_start = data[index + 1]
        local length = data[index + 2]
        local type_index = data[index + 3]
        local modifier_mask = data[index + 4]
        if
            not is_integer(delta_line)
            or delta_line < 0
            or not is_integer(delta_start)
            or delta_start < 0
            or not is_integer(length)
            or length < 0
            or not is_integer(type_index)
            or type_index < 0
            or not is_integer(modifier_mask)
            or modifier_mask < 0
        then
            return nil
        end

        token_line = token_line and token_line + delta_line or delta_line
        token_start = delta_line == 0 and token_start + delta_start or delta_start
        local token_type = token_types[type_index + 1]
        if type(token_type) == "string" and token_type ~= "" and length > 0 then
            local modifiers = {}
            for modifier_index, modifier in ipairs(token_modifiers) do
                if
                    type(modifier) == "string"
                    and modifier ~= ""
                    and bit.band(modifier_mask, bit.lshift(1, modifier_index - 1)) ~= 0
                then
                    modifiers[#modifiers + 1] = modifier
                end
            end

            local line = token_line
            local start_units = token_start
            local remaining = length
            while remaining > 0 and line < #lines do
                local source_line = lines[line + 1]
                local total_units = unit_length(source_line, encoding)
                local segment_start = math.min(start_units, total_units)
                local available = total_units - segment_start
                if available > 0 then
                    local take = math.min(remaining, available)
                    local start_col = byte_index(source_line, encoding, segment_start)
                    local end_col = byte_index(source_line, encoding, segment_start + take)
                    if end_col > start_col then
                        append_layers(spans, line, start_col, end_col, token_type, modifiers, filetype)
                    end
                    remaining = remaining - take
                end
                if remaining > 0 and line < #lines - 1 then
                    remaining = math.max(0, remaining - eol_units)
                end
                line = line + 1
                start_units = 0
            end
        end
    end
    return spans
end

---@param client table?
---@param client_state ScrollbarLspSemanticClientState
local function cancel_request(client, client_state)
    if client_state.request_id == nil then
        return
    end
    if client ~= nil and type(client.cancel_request) == "function" then
        pcall(client.cancel_request, client, client_state.request_id)
    end
    client_state.request_id = nil
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function publish(context, bufnr)
    local buffer = state.buffers[bufnr]
    local spans = {}
    if buffer ~= nil then
        local client_ids = vim.tbl_keys(buffer.clients)
        table.sort(client_ids)
        for _, client_id in ipairs(client_ids) do
            vim.list_extend(spans, buffer.clients[client_id].spans)
        end
    end
    context.set_minimap_spans(bufnr, spans)
end

---@param bufnr integer
---@param client_id integer
---@param context ScrollbarProviderContext
local function remove_client(bufnr, client_id, context)
    local buffer = state.buffers[bufnr]
    if buffer == nil then
        return
    end
    local client_state = buffer.clients[client_id]
    if client_state == nil then
        return
    end
    cancel_request(vim.lsp.get_client_by_id(client_id), client_state)
    buffer.clients[client_id] = nil
    publish(context, bufnr)
end

---@param bufnr integer
local function remove_buffer(bufnr)
    local buffer = state.buffers[bufnr]
    if buffer == nil then
        return
    end
    for client_id, client_state in pairs(buffer.clients) do
        cancel_request(vim.lsp.get_client_by_id(client_id), client_state)
    end
    state.buffers[bufnr] = nil
end

---@param bufnr integer
---@param method string
---@return table
local function request_params(bufnr, method)
    local params = { textDocument = vim.lsp.util.make_text_document_params(bufnr) }
    if method == "textDocument/semanticTokens/range" then
        params.range = {
            start = { line = 0, character = 0 },
            ["end"] = { line = vim.api.nvim_buf_line_count(bufnr), character = 0 },
        }
    end
    return params
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function request_buffer(context, bufnr)
    if state.context ~= context then
        return
    end
    if not context.is_buffer_eligible(bufnr) or not vim.api.nvim_buf_is_valid(bufnr) then
        remove_buffer(bufnr)
        context.clear_minimap_spans(bufnr)
        return
    end

    local buffer = state.buffers[bufnr]
    if buffer == nil then
        buffer = { generation = 0, schedule_generation = 0, clients = {} }
        state.buffers[bufnr] = buffer
    end
    buffer.generation = buffer.generation + 1
    local generation = buffer.generation
    local version = vim.api.nvim_buf_get_changedtick(bufnr)

    local ok_clients, clients = pcall(vim.lsp.get_clients, { bufnr = bufnr })
    if not ok_clients or type(clients) ~= "table" then
        return
    end
    table.sort(clients, function(left, right)
        return left.id < right.id
    end)

    local active = {}
    for _, client in ipairs(clients) do
        local client_id = client.id
        local method = type(client_id) == "number" and request_method(client, bufnr) or nil
        if method ~= nil and type(client.request) == "function" then
            active[client_id] = true
            local client_state = buffer.clients[client_id]
            if client_state == nil then
                client_state = { generation = 0, version = 0, spans = {} }
                buffer.clients[client_id] = client_state
            end
            cancel_request(client, client_state)
            client_state.generation = generation
            client_state.version = version

            local completed = false
            local ok_params, params = pcall(request_params, bufnr, method)
            if ok_params then
                local ok_request, success, request_id = pcall(
                    client.request,
                    client,
                    method,
                    params,
                    function(err, response)
                        completed = true
                        local current_context = state.context
                        local current_buffer = state.buffers[bufnr]
                        local current_client = current_buffer and current_buffer.clients[client_id] or nil
                        if
                            current_context ~= context
                            or current_client ~= client_state
                            or client_state.generation ~= generation
                            or client_state.version ~= version
                            or not vim.api.nvim_buf_is_valid(bufnr)
                            or vim.api.nvim_buf_get_changedtick(bufnr) ~= version
                            or vim.lsp.get_client_by_id(client_id) == nil
                        then
                            return
                        end
                        client_state.request_id = nil
                        if err ~= nil or type(response) ~= "table" then
                            return
                        end
                        local spans = decode_tokens(bufnr, client, response.data)
                        if spans == nil then
                            return
                        end
                        client_state.spans = spans
                        publish(context, bufnr)
                    end,
                    bufnr
                )
                if ok_request and success == true and not completed and is_integer(request_id) then
                    client_state.request_id = request_id
                end
            end
        end
    end

    local removed = false
    for client_id, client_state in pairs(buffer.clients) do
        if not active[client_id] then
            cancel_request(vim.lsp.get_client_by_id(client_id), client_state)
            buffer.clients[client_id] = nil
            removed = true
        end
    end
    if removed or next(buffer.clients) == nil then
        publish(context, bufnr)
    end
end

---@param context ScrollbarProviderContext
---@param bufnr integer
local function schedule_buffer(context, bufnr)
    local buffer = state.buffers[bufnr]
    if buffer == nil then
        buffer = { generation = 0, schedule_generation = 0, clients = {} }
        state.buffers[bufnr] = buffer
    end
    buffer.schedule_generation = buffer.schedule_generation + 1
    local schedule_generation = buffer.schedule_generation
    local provider_generation = state.generation
    local function run()
        local current = state.buffers[bufnr]
        if
            state.context == context
            and state.generation == provider_generation
            and current == buffer
            and buffer.schedule_generation == schedule_generation
        then
            request_buffer(context, bufnr)
        end
    end
    if M.debounce_ms <= 0 then
        run()
    else
        vim.defer_fn(run, M.debounce_ms)
    end
end

---@param context ScrollbarProviderContext
M.setup = function(context)
    state.generation = state.generation + 1
    state.context = context
    state.buffers = {}

    local group = context.create_augroup("events")
    vim.api.nvim_create_autocmd("LspAttach", {
        group = group,
        callback = function(args)
            schedule_buffer(context, args.buf)
        end,
        desc = "Refresh minimap LSP semantic tokens after attach",
    })
    vim.api.nvim_create_autocmd("LspDetach", {
        group = group,
        callback = function(args)
            local client_id = type(args.data) == "table" and args.data.client_id or nil
            if type(client_id) == "number" then
                remove_client(args.buf, client_id, context)
            end
        end,
        desc = "Remove detached minimap LSP semantic tokens",
    })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = group,
        callback = function(args)
            schedule_buffer(context, args.buf)
        end,
        desc = "Refresh minimap LSP semantic tokens after edits",
    })
    vim.api.nvim_create_autocmd("LspTokenUpdate", {
        group = group,
        callback = function(args)
            schedule_buffer(context, args.buf)
        end,
        desc = "Refresh minimap LSP semantic tokens after native updates",
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = group,
        callback = function(args)
            remove_buffer(args.buf)
        end,
        desc = "Dispose minimap LSP semantic token state",
    })
end

---@param bufnr integer
---@param context ScrollbarProviderContext
M.refresh_minimap = function(bufnr, context)
    schedule_buffer(context, bufnr)
end

---@param context ScrollbarProviderContext
M.dispose = function(context)
    state.generation = state.generation + 1
    for bufnr in pairs(state.buffers) do
        remove_buffer(bufnr)
    end
    state.buffers = {}
    state.context = nil
    context.clear_minimap_spans()
end

return M
