---Buffers, windows, and marks for the cases in `benchmarks/cases/`. The cases call the module functions of the plugin,
---not internal upvalues, so that `scripts/bench-compare.sh` can run them on the code of an older revision.
local M = {}

---The line count of the buffers. The reports in `benchmarks/reports/` measure larger buffers.
M.LINE_COUNT = 10000

---The time limit for a worker child to start.
M.READY_TIMEOUT_MS = 10000

function M.isolate_environment()
    -- Keep the default screen of 24 lines. In `nvim -l` with 48 lines, the redraw that places a float crashes Neovim
    -- 0.12.6 in grid_clear_line when three windows show the buffer.
    vim.o.swapfile = false
    vim.o.undofile = false
    vim.o.hlsearch = false
end

---@param count integer
---@param line? fun(index: integer): string
---@return string[]
function M.lines(count, line)
    local lines = {}
    for index = 1, count do
        lines[index] = line and line(index) or string.format("local value_%d = %d", index, index * 2)
    end
    return lines
end

---@param lines string[]
---@return integer bufnr
function M.buffer(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr
end

---Shows the buffer in the first window of the editor. The renderers skip floating windows, so the cases use normal
---windows.
---@param bufnr integer
---@return integer winid
function M.source_window(bufnr)
    local winid = vim.api.nvim_list_wins()[1]
    vim.api.nvim_set_current_win(winid)
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.api.nvim_win_set_cursor(winid, { 1, 0 })
    return winid
end

---Opens a split that shows the buffer.
---@param bufnr integer
---@param command? string The split command (default: `vsplit`).
---@return integer winid
function M.split(bufnr, command)
    vim.cmd(command or "vsplit")
    local winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    return winid
end

---Marks spread evenly over the buffer.
---@param count integer
---@param line_count integer
---@param mark_type string
---@param text? string
---@return table[]
function M.spread(count, line_count, mark_type, text)
    local marks = {}
    for index = 1, count do
        marks[index] = {
            line = math.floor((index - 1) * (line_count - 1) / math.max(1, count - 1)),
            type = mark_type,
            text = text,
        }
    end
    return marks
end

---Calls `done` once, when the store publishes the result of the provider for the buffer.
---@param provider string
---@param bufnr integer
---@return fun(done: fun(err?: string)) wait Sets the callback for the next publication.
---@return fun() unsubscribe
function M.on_publication(provider, bufnr)
    local pending = nil ---@type fun(err?: string)?
    local unsubscribe = require("scrollbar.shared.store").subscribe(function(event)
        if pending ~= nil and event.provider == provider and event.target == bufnr then
            local done = pending
            pending = nil
            done()
        end
    end)
    return function(done)
        pending = done
    end, unsubscribe
end

---Waits until the status of a worker module reports `ready`.
---@param worker { status: (fun(): { state: string }) }
function M.wait_until_ready(worker)
    if not vim.wait(M.READY_TIMEOUT_MS, function()
        return worker.status().state == "ready"
    end, 1) then
        error("the worker did not start: " .. worker.status().state, 0)
    end
end

---Stops a worker module and waits until its child exits.
---@param worker { status: (fun(): { job_id?: integer }), dispose: fun() }
function M.dispose_worker(worker)
    local job_id = worker.status().job_id
    worker.dispose()
    if job_id ~= nil then
        vim.fn.jobwait({ job_id }, 1000)
    end
end

---`setup` replaces the previous runtime, but no public function removes it, so this disposes the loaded modules in
---the order that setup uses. A module that an older revision lacks is skipped.
local function dispose_plugin()
    local stack = package.loaded["scrollbar.shared.stack"]
    if stack ~= nil and type(stack.reset) == "function" then
        pcall(stack.reset)
    end
    for _, name in ipairs({
        "scrollbar.minimap",
        "scrollbar.mouse",
        "scrollbar.scheduler",
        "scrollbar.minimap.scheduler",
        "scrollbar.providers",
        "scrollbar.renderer",
        "scrollbar.minimap.renderer",
        "scrollbar.minimap.overlays",
    }) do
        local module = package.loaded[name]
        if module ~= nil and type(module.dispose) == "function" then
            pcall(module.dispose)
        end
    end
    for _, name in ipairs({ "scrollbar.minimap.worker", "scrollbar.providers.search.worker" }) do
        local worker = package.loaded[name]
        if worker ~= nil and type(worker.dispose) == "function" then
            pcall(M.dispose_worker, worker)
        end
    end
end

---Removes the plugin state, the windows, and the buffers of a case, so that the next case starts clean.
function M.reset()
    dispose_plugin()
    local first = vim.api.nvim_list_wins()[1]
    vim.api.nvim_set_current_win(first)
    vim.cmd("silent! only!")
    vim.cmd("enew!")
    local current = vim.api.nvim_get_current_buf()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if bufnr ~= current then
            pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
        end
    end
    vim.fn.setreg("/", "")
    vim.o.hlsearch = false
    vim.cmd("nohlsearch")
end

M.cleanup = M.reset

return M
