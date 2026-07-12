local script_path = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(script_path, ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.lines = 48
vim.o.columns = 120
vim.o.swapfile = false

local line_count = 50000
local mark_count = 10000
local warmup_count = 5
local iteration_count = 30

local lines = {}
for index = 1, line_count do
    lines[index] = "benchmark line " .. index
end
vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
local source_buf = vim.api.nvim_get_current_buf()

local marks = {}
for index = 1, mark_count do
    marks[index] = {
        line = math.floor((index - 1) * (line_count - 1) / (mark_count - 1)),
        text = "-",
        type = "Misc",
    }
end
assert(require("scrollbar.store").set("benchmark", source_buf, marks))

local function percentile(sorted, fraction)
    return sorted[math.max(1, math.ceil(#sorted * fraction))]
end

local function measure(geometry, name, windows)
    require("scrollbar.config").set({
        set_highlights = false,
        render = { interval_ms = 0, geometry = geometry },
        excluded_buftypes = {},
        excluded_filetypes = {},
        handle = { text = "H", hide_if_all_visible = false },
        providers = {
            cursor = false,
            diagnostic = false,
            gitsigns = false,
            search = false,
            ale = false,
            coc = false,
        },
    })
    require("scrollbar.renderer").setup()

    local function render_pass()
        for _, winid in ipairs(windows) do
            require("scrollbar.renderer").render(winid)
        end
    end

    for _ = 1, warmup_count do
        render_pass()
    end

    collectgarbage("collect")
    local samples = {}
    for index = 1, iteration_count do
        local started = vim.uv.hrtime()
        render_pass()
        samples[index] = (vim.uv.hrtime() - started) / 1000000
    end
    table.sort(samples)

    io.write(
        string.format(
            "| %s | %s | %.3f | %.3f | %.3f |\n",
            geometry,
            name,
            percentile(samples, 0.5),
            percentile(samples, 0.95),
            samples[#samples]
        )
    )
end

local first_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(first_win, { 1, 0 })
vim.cmd("normal! zt")
measure("line", "1 window", { first_win })
measure("screen", "1 window", { first_win })

vim.cmd("vsplit")
local second_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(second_win, { math.floor(line_count / 2), 0 })
vim.cmd("normal! zt")
vim.cmd("split")
local third_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(third_win, { line_count - 100, 0 })
vim.cmd("normal! zt")
measure("line", "3 windows", { first_win, second_win, third_win })
measure("screen", "3 windows", { first_win, second_win, third_win })

require("scrollbar.renderer").dispose()
vim.cmd("qa!")
