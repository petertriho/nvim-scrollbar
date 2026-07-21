local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            for _, module in ipairs({
                "scrollbar.config",
                "scrollbar.providers",
                "scrollbar.providers.lsp_semantic_tokens",
                "scrollbar.store",
            }) do
                package.loaded[module] = nil
            end
            require("scrollbar.config").set({ scrollbar = {}, minimap = { enabled = true } })
        end,
        post_case = function()
            local providers = package.loaded["scrollbar.providers"]
            if providers then
                providers.dispose()
            end
        end,
    },
})

local function new_buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].filetype = "lua"
    MiniTest.finally(function()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_buf_delete(bufnr, { force = true })
        end
    end)
    return bufnr
end

local function show_buffer(bufnr)
    local previous = vim.api.nvim_get_current_win()
    vim.cmd("botright new")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    MiniTest.finally(function()
        if vim.api.nvim_win_is_valid(winid) then
            vim.api.nvim_win_close(winid, true)
        end
        if vim.api.nvim_win_is_valid(previous) then
            vim.api.nvim_set_current_win(previous)
        end
    end)
    return winid
end

local function new_client(id, options)
    local requests = {}
    local cancelled = {}
    local provider = {
        legend = {
            tokenTypes = options.token_types or { "variable" },
            tokenModifiers = options.token_modifiers or {},
        },
        full = options.full == true and true or nil,
        range = options.range == true and true or nil,
    }
    local client = {
        id = id,
        offset_encoding = options.encoding or "utf-16",
        server_capabilities = { semanticTokensProvider = provider },
        requests = requests,
        cancelled = cancelled,
    }
    client.supports_method = function(_, method)
        if method == "textDocument/semanticTokens/full" then
            return options.full == true
        end
        if method == "textDocument/semanticTokens/range" then
            return options.range == true
        end
        return false
    end
    client.request = function(_, method, params, handler, bufnr)
        local request = {
            id = id * 100 + #requests + 1,
            method = method,
            params = params,
            handler = handler,
            bufnr = bufnr,
        }
        requests[#requests + 1] = request
        return true, request.id
    end
    client.cancel_request = function(_, request_id)
        cancelled[#cancelled + 1] = request_id
        return true
    end
    return client
end

local function setup_provider(bufnr, winid, clients)
    local by_id = {}
    for _, client in ipairs(clients) do
        by_id[client.id] = client
    end
    local attached = by_id
    local original_get_clients = vim.lsp.get_clients
    local original_get_client_by_id = vim.lsp.get_client_by_id
    local refresh_handler = vim.lsp.handlers["workspace/semanticTokens/refresh"]
    vim.lsp.get_clients = function(filter)
        if filter and filter.bufnr and filter.bufnr ~= bufnr then
            return {}
        end
        local result = vim.tbl_values(attached)
        table.sort(result, function(left, right)
            return left.id < right.id
        end)
        return result
    end
    vim.lsp.get_client_by_id = function(client_id)
        return attached[client_id]
    end
    MiniTest.finally(function()
        vim.lsp.get_clients = original_get_clients
        vim.lsp.get_client_by_id = original_get_client_by_id
    end)

    local provider = require("scrollbar.providers.lsp_semantic_tokens")
    provider.debounce_ms = 0
    local providers = require("scrollbar.providers")
    providers.register(provider)
    providers.setup({
        consumer_policies = {
            minimap = {
                source_windows = function(target)
                    if target == nil or target == bufnr then
                        return { winid }
                    end
                    return {}
                end,
                is_buffer_eligible = function(target)
                    return target == bufnr
                end,
                is_source_window = function(target)
                    return target == winid
                end,
            },
        },
    })
    return {
        provider = provider,
        providers = providers,
        attached = attached,
        refresh_handler = refresh_handler,
    }
end

local function respond(client, index, bufnr, err, result)
    local request = assert(client.requests[index], "missing mocked LSP request")
    request.handler(err, result, { client_id = client.id, bufnr = bufnr })
end

local function wait_for_requests(clients, count)
    return vim.wait(1000, function()
        local total = 0
        for _, client in ipairs(clients) do
            total = total + #client.requests
        end
        return total >= count
    end)
end

T["requests full or whole-document range and decodes all offset encodings"] = function()
    local bufnr = new_buffer({ "a😀b", "cd" })
    local winid = show_buffer(bufnr)
    local utf8 = new_client(3, {
        encoding = "utf-8",
        full = true,
        token_types = { "variable" },
        token_modifiers = { "readonly" },
    })
    local utf16 = new_client(1, {
        encoding = "utf-16",
        range = true,
        token_types = { "function" },
        token_modifiers = { "declaration" },
    })
    local utf32 = new_client(2, {
        encoding = "utf-32",
        full = true,
        token_types = { "class" },
    })
    local harness = setup_provider(bufnr, winid, { utf8, utf16, utf32 })
    expect.equality(wait_for_requests({ utf8, utf16, utf32 }, 3), true)

    expect.equality(utf8.requests[1].method, "textDocument/semanticTokens/full")
    expect.equality(utf32.requests[1].method, "textDocument/semanticTokens/full")
    expect.equality(utf16.requests[1].method, "textDocument/semanticTokens/range")
    expect.equality(utf16.requests[1].params.range, {
        start = { line = 0, character = 0 },
        ["end"] = { line = 2, character = 0 },
    })

    -- All three tokens select the same emoji using their negotiated units.
    respond(utf8, 1, bufnr, nil, { data = { 0, 1, 4, 0, 1 } })
    respond(utf16, 1, bufnr, nil, { data = { 0, 1, 2, 0, 1 } })
    respond(utf32, 1, bufnr, nil, { data = { 0, 1, 1, 0, 0 } })

    local provider = harness.provider
    expect.equality(provider.priorities.base > require("scrollbar.providers.treesitter").priority, true)
    local spans = require("scrollbar.store").get_minimap_spans(bufnr).lsp_semantic_tokens
    expect.equality(spans, {
        {
            line = 0,
            start_col = 1,
            end_col = 5,
            highlight = "@lsp.type.function.lua",
            priority = provider.priorities.base,
        },
        {
            line = 0,
            start_col = 1,
            end_col = 5,
            highlight = "@lsp.mod.declaration.lua",
            priority = provider.priorities.modifier,
        },
        {
            line = 0,
            start_col = 1,
            end_col = 5,
            highlight = "@lsp.typemod.function.declaration.lua",
            priority = provider.priorities.type_modifier,
        },
        {
            line = 0,
            start_col = 1,
            end_col = 5,
            highlight = "@lsp.type.class.lua",
            priority = provider.priorities.base,
        },
        {
            line = 0,
            start_col = 1,
            end_col = 5,
            highlight = "@lsp.type.variable.lua",
            priority = provider.priorities.base,
        },
        {
            line = 0,
            start_col = 1,
            end_col = 5,
            highlight = "@lsp.mod.readonly.lua",
            priority = provider.priorities.modifier,
        },
        {
            line = 0,
            start_col = 1,
            end_col = 5,
            highlight = "@lsp.typemod.variable.readonly.lua",
            priority = provider.priorities.type_modifier,
        },
    })
    expect.equality(vim.lsp.handlers["workspace/semanticTokens/refresh"], harness.refresh_handler)
end

T["splits multiline tokens and keeps prior output through stale and error responses"] = function()
    local bufnr = new_buffer({ "ab", "cd" })
    local winid = show_buffer(bufnr)
    local client = new_client(4, { encoding = "utf-8", full = true, token_types = { "string" } })
    local harness = setup_provider(bufnr, winid, { client })
    expect.equality(wait_for_requests({ client }, 1), true)

    respond(client, 1, bufnr, nil, { data = { 0, 1, 3, 0, 0 } })
    local store = require("scrollbar.store")
    expect.equality(store.get_minimap_spans(bufnr).lsp_semantic_tokens, {
        {
            line = 0,
            start_col = 1,
            end_col = 2,
            highlight = "@lsp.type.string.lua",
            priority = harness.provider.priorities.base,
        },
        {
            line = 1,
            start_col = 0,
            end_col = 1,
            highlight = "@lsp.type.string.lua",
            priority = harness.provider.priorities.base,
        },
    })

    harness.providers.refresh(bufnr, { consumer = "minimap", channel = "minimap_spans" })
    harness.providers.refresh(bufnr, { consumer = "minimap", channel = "minimap_spans" })
    expect.equality(wait_for_requests({ client }, 3), true)
    expect.equality(client.cancelled, { client.requests[2].id })

    respond(client, 2, bufnr, nil, { data = { 0, 0, 1, 0, 0 } })
    expect.equality(#store.get_minimap_spans(bufnr).lsp_semantic_tokens, 2)
    respond(client, 3, bufnr, { message = "server failed" }, nil)
    expect.equality(#store.get_minimap_spans(bufnr).lsp_semantic_tokens, 2)

    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { "xy" })
    vim.api.nvim_exec_autocmds("TextChanged", { buffer = bufnr })
    expect.equality(wait_for_requests({ client }, 4), true)
    respond(client, 4, bufnr, nil, { data = { 0, 0, 2, 0, 0 } })
    expect.equality(store.get_minimap_spans(bufnr).lsp_semantic_tokens, {
        {
            line = 0,
            start_col = 0,
            end_col = 2,
            highlight = "@lsp.type.string.lua",
            priority = harness.provider.priorities.base,
        },
    })
end

T["attach token-update detach and dispose isolate client lifecycle"] = function()
    local bufnr = new_buffer({ "abc" })
    local winid = show_buffer(bufnr)
    local first = new_client(1, { full = true, token_types = { "variable" } })
    local second = new_client(2, { full = true, token_types = { "function" } })
    local harness = setup_provider(bufnr, winid, { first })
    expect.equality(wait_for_requests({ first }, 1), true)
    respond(first, 1, bufnr, nil, { data = { 0, 0, 1, 0, 0 } })

    harness.attached[second.id] = second
    vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = second.id } })
    expect.equality(wait_for_requests({ first, second }, 3), true)
    respond(first, 2, bufnr, nil, { data = { 0, 0, 1, 0, 0 } })
    respond(second, 1, bufnr, nil, { data = { 0, 1, 1, 0, 0 } })
    expect.equality(#require("scrollbar.store").get_minimap_spans(bufnr).lsp_semantic_tokens, 2)

    vim.api.nvim_exec_autocmds("LspTokenUpdate", {
        buffer = bufnr,
        data = { client_id = first.id, token = {} },
    })
    expect.equality(wait_for_requests({ first, second }, 5), true)

    harness.attached[first.id] = nil
    vim.api.nvim_exec_autocmds("LspDetach", { buffer = bufnr, data = { client_id = first.id } })
    local spans = require("scrollbar.store").get_minimap_spans(bufnr).lsp_semantic_tokens
    expect.equality(#spans, 1)
    expect.equality(spans[1].highlight, "@lsp.type.function.lua")

    harness.providers.dispose()
    expect.equality(require("scrollbar.store").get_minimap_spans(bufnr), {})
    expect.equality(#second.cancelled > 0, true)
end

return T
