local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.lines = 48
vim.o.columns = 120
vim.o.swapfile = false

local warmup_count = 10
local iteration_count = 300

local store = require("scrollbar.store")
local providers = require("scrollbar.providers")

local function percentile(sorted, fraction)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function statistics(samples)
    table.sort(samples)
    return { median = percentile(samples, 0.5), p95 = percentile(samples, 0.95) }
end

local line_count = 50000
local lines = {}
for index = 1, line_count do
    lines[index] = "local value_" .. index .. " = " .. (index * 2)
end
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
local winid = vim.api.nvim_open_win(buf, true, { relative = "editor", row = 0, col = 0, width = 80, height = 24 })

-- Register realistic provider entries so store notifications reach the
-- scheduler path exactly as they do for the built-in providers.
for _, name in ipairs({ "diagnostic", "gitsigns", "marks", "cursor", "treesitter" }) do
    providers.register({ name = name })
end

require("scrollbar.config").set({
    scrollbar = {
        set_highlights = false,
        excluded_buftypes = {},
        excluded_filetypes = {},
        update = { interval_ms = 0 },
        providers = {
            search = false,
            ale = false,
            coc = false,
        },
    },
    minimap = { enabled = false },
})
require("scrollbar").setup({})

local function spread(count, line_count, type, text)
    local marks = {}
    for index = 1, count do
        marks[index] = {
            line = math.floor((index - 1) * (line_count - 1) / math.max(1, count - 1)),
            type = type,
            text = text,
        }
    end
    return marks
end

-- Provider-shaped payloads at realistic densities for a 50k-line buffer.
local payloads = {
    { provider = "diagnostic", channel = "marks", marks = spread(200, line_count, "Error") },
    { provider = "gitsigns", channel = "marks", marks = spread(1500, line_count, "GitAdd") },
    { provider = "marks", channel = "marks", marks = spread(100, line_count, "Mark", "'") },
    { provider = "treesitter", channel = "spans", marks = {} },
    { provider = "cursor", channel = "window", marks = { { line = 1234, type = "Cursor" } } },
}
for index = 1, 5000 do
    payloads[4].marks[index] = {
        line = math.floor((index - 1) * (line_count - 1) / 4999),
        start_col = 0,
        end_col = 12,
        highlight = "@variable",
        priority = 200,
    }
end

local function publish(payload, marks)
    if payload.channel == "marks" then
        return store.set(payload.provider, buf, marks)
    elseif payload.channel == "spans" then
        return store.set_minimap_spans(payload.provider, buf, marks)
    end
    return store.set_window(payload.provider, winid, marks)
end

local results = {}
for _, payload in ipairs(payloads) do
    -- Warm the store with the baseline payload.
    publish(payload, payload.marks)

    -- no-op publication: identical payload exercises the deep_equal early exit
    local samples = {}
    for _ = 1, warmup_count do
        publish(payload, payload.marks)
    end
    collectgarbage("collect")
    for index = 1, iteration_count do
        local started = vim.uv.hrtime()
        publish(payload, payload.marks)
        samples[index] = (vim.uv.hrtime() - started) / 1000
    end
    results[#results + 1] = { payload = payload, op = "noop", stats = statistics(samples) }

    -- changed publication: one moved line forces validation + copy + notify
    local variant = vim.deepcopy(payload.marks)
    local samples_changed = {}
    for _ = 1, warmup_count do
        variant[1] = { line = math.random(0, line_count - 1), type = variant[1].type, text = variant[1].text }
        if payload.channel == "spans" then
            variant[1] = {
                line = variant[1].line,
                start_col = 0,
                end_col = 12,
                highlight = "@variable",
                priority = 200,
            }
        end
        publish(payload, variant)
    end
    collectgarbage("collect")
    for index = 1, iteration_count do
        variant[1] =
            { line = math.random(0, line_count - 1), type = payload.marks[1].type, text = payload.marks[1].text }
        if payload.channel == "spans" then
            variant[1] = {
                line = variant[1].line,
                start_col = 0,
                end_col = 12,
                highlight = "@variable",
                priority = 200,
            }
        end
        local started = vim.uv.hrtime()
        publish(payload, variant)
        samples_changed[index] = (vim.uv.hrtime() - started) / 1000
    end
    results[#results + 1] = { payload = payload, op = "changed", stats = statistics(samples_changed) }
end

io.write("## Provider publication cost (microseconds)\n\n")
io.write("| Provider | Channel | Op | Payload | p50 | p95 |\n")
io.write("| --- | --- | --- | --- | ---: | ---: |\n")
for _, result in ipairs(results) do
    io.write(
        string.format(
            "| %s | %s | %s | %d | %.2f | %.2f |\n",
            result.payload.provider,
            result.payload.channel,
            result.op,
            #result.payload.marks,
            result.stats.median,
            result.stats.p95
        )
    )
end

require("scrollbar.scheduler").dispose()
require("scrollbar.providers").dispose()
pcall(vim.api.nvim_win_close, winid, true)
pcall(vim.api.nvim_buf_delete, buf, { force = true })
vim.cmd("qa!")
