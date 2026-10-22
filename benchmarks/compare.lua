-- Compares two sets of benchmark results from benchmarks/run.lua and exits with 1 when the head regressed.
--
--   nvim --headless --clean -l benchmarks/compare.lua BASE HEAD [options]
--
-- BASE and HEAD are result files. To lower the noise, give the files of more than one run as a comma-separated list.
-- Each side then uses the lowest median of its runs.
--
-- Options:
--   --markdown FILE        Also append the report as a Markdown table to FILE, for example $GITHUB_STEP_SUMMARY.
--   --time-threshold R     A time regresses when it grows by more than this ratio (default 0.25).
--   --alloc-threshold R    An allocation regresses when it grows by more than this ratio (default 0.10).
--
-- A time must also grow by more than 0.5 us (sync cases) or 2 ms (async cases), and an allocation by more than
-- 0.5 KB, so that the noise of very small values does not count. Any increase of the process counts regresses.

-- `print` in `nvim -l` writes to stderr, and it ends a line only when the next message starts or Neovim exits
-- normally. `os.exit` skips that exit, so the lines go to stdout.
---@param line string
local function emit(line)
    io.write(line, "\n")
end

local TIME_FLOOR = { us = 0.5, ms = 2 }
local ALLOC_FLOOR_KB = 0.5

---@param argv string[]
local function parse_args(argv)
    local opts = { files = {}, time_threshold = 0.25, alloc_threshold = 0.10 }
    local i = 1
    while i <= #argv do
        local name = argv[i]
        local function value()
            i = i + 1
            return argv[i] or error("missing value for " .. name, 0)
        end

        if name == "--markdown" then
            opts.markdown = value()
        elseif name == "--time-threshold" then
            opts.time_threshold = assert(tonumber(value()), "--time-threshold needs a number")
        elseif name == "--alloc-threshold" then
            opts.alloc_threshold = assert(tonumber(value()), "--alloc-threshold needs a number")
        elseif name:sub(1, 2) == "--" then
            error("unknown option " .. name, 0)
        else
            table.insert(opts.files, name)
        end
        i = i + 1
    end
    if #opts.files ~= 2 then
        error("usage: compare.lua BASE HEAD [--markdown FILE] [--time-threshold R] [--alloc-threshold R]", 0)
    end
    return opts
end

---@class bench.Side
---@field order string[]
---@field results table<string, bench.Result>
---@field errors table<string, string>
---@field meta table

---Read the runs of one side and keep the best value of each metric.
---@param list string Comma-separated result files.
---@return bench.Side
local function load_side(list)
    local side = { order = {}, results = {}, errors = {}, meta = {} }
    for path in list:gmatch("[^,]+") do
        local file = assert(io.open(path, "r"), "cannot read " .. path)
        local data = vim.json.decode(file:read("*a"))
        file:close()

        side.meta = data.meta
        for _, name in ipairs(data.order) do
            if not vim.tbl_contains(side.order, name) then
                table.insert(side.order, name)
            end
        end
        for name, message in pairs(data.errors or {}) do
            side.errors[name] = message
        end
        for name, result in pairs(data.results) do
            local best = side.results[name]
            if not best then
                side.results[name] = result
            else
                best.median = math.min(best.median, result.median)
                best.min = math.min(best.min, result.min)
                if result.alloc_kb then
                    best.alloc_kb = math.min(best.alloc_kb, result.alloc_kb)
                end
                if result.main_ms then
                    best.main_ms = math.min(best.main_ms, result.main_ms)
                    best.block_ms = math.min(best.block_ms, result.block_ms)
                end
                -- Process counts do not depend on the machine, so a difference between runs is real
                best.spawns = math.max(best.spawns, result.spawns)
                best.blocking = math.max(best.blocking, result.blocking)
            end
        end
    end
    return side
end

---@param base number
---@param head number
---@param threshold number
---@param floor number
---@return "regressed" | "improved" | nil
local function classify(base, head, threshold, floor)
    if math.abs(head - base) <= floor then
        return nil
    end
    if head > base * (1 + threshold) then
        return "regressed"
    end
    if head < base / (1 + threshold) then
        return "improved"
    end
    return nil
end

---@param value number?
---@param unit "us" | "ms"
local function format_time(value, unit)
    if value == nil then
        return "-"
    end
    if unit == "ms" then
        return string.format("%.2f ms", value)
    end
    if value >= 1000 then
        return string.format("%.2f ms", value / 1000)
    end
    return string.format("%.2f us", value)
end

---@param base number?
---@param head number?
local function format_change(base, head)
    if not base or not head or base == 0 then
        return "-"
    end
    return string.format("%+.0f%%", (head / base - 1) * 100)
end

local function main()
    -- `nvim -l` gives the script arguments in the global `arg`
    -- selene: allow(global_usage)
    local opts = parse_args(_G.arg)
    local base = load_side(opts.files[1])
    local head = load_side(opts.files[2])

    local names = vim.list_extend({}, head.order)
    for _, name in ipairs(base.order) do
        if not vim.tbl_contains(names, name) then
            table.insert(names, name)
        end
    end

    local rows = {}
    local regressions = 0
    for _, name in ipairs(names) do
        local b, h = base.results[name], head.results[name]
        local notes = {}
        local status = "ok"

        if head.errors[name] then
            status = base.errors[name] and "error in both" or "error"
            if not base.errors[name] then
                regressions = regressions + 1
            end
        elseif not h then
            status = "removed"
        elseif not b then
            status = base.errors[name] and "base error" or "new"
        else
            local unit = h.unit
            local changes = {
                { "time", classify(b.median, h.median, opts.time_threshold, TIME_FLOOR[unit]) },
            }
            if h.main_ms and b.main_ms then
                table.insert(changes, {
                    "main thread",
                    classify(b.main_ms, h.main_ms, opts.time_threshold, TIME_FLOOR.ms),
                })
            end
            if h.alloc_kb and b.alloc_kb then
                table.insert(changes, {
                    "alloc",
                    classify(b.alloc_kb, h.alloc_kb, opts.alloc_threshold, ALLOC_FLOOR_KB),
                })
            end
            if h.spawns > b.spawns + 0.01 then
                table.insert(changes, { "spawns", "regressed" })
            elseif h.spawns < b.spawns - 0.01 then
                table.insert(changes, { "spawns", "improved" })
            end
            if h.blocking > b.blocking + 0.01 then
                table.insert(changes, { "blocking calls", "regressed" })
            elseif h.blocking < b.blocking - 0.01 then
                table.insert(changes, { "blocking calls", "improved" })
            end

            local regressed, improved = {}, {}
            for _, change in ipairs(changes) do
                if change[2] == "regressed" then
                    table.insert(regressed, change[1])
                elseif change[2] == "improved" then
                    table.insert(improved, change[1])
                end
            end
            if #regressed > 0 then
                status = "REGRESSED"
                regressions = regressions + 1
                table.insert(notes, "worse: " .. table.concat(regressed, ", "))
            end
            if #improved > 0 then
                if status == "ok" then
                    status = "improved"
                end
                table.insert(notes, "better: " .. table.concat(improved, ", "))
            end
        end

        local unit = (h or b or { unit = "us" }).unit
        table.insert(rows, {
            name = name,
            base = format_time(b and b.median, unit),
            head = format_time(h and h.median, unit),
            change = format_change(b and b.median, h and h.median),
            alloc = (b and b.alloc_kb and h and h.alloc_kb)
                    and string.format("%.1f -> %.1f KB", b.alloc_kb, h.alloc_kb)
                or "-",
            spawns = (b and h) and string.format("%g -> %g", b.spawns, h.spawns) or "-",
            status = status .. (#notes > 0 and " (" .. table.concat(notes, "; ") .. ")" or ""),
        })
    end

    local header = string.format(
        "base %s (%s), head %s (%s), Neovim %s",
        tostring(base.meta.revision),
        tostring(base.meta.date),
        tostring(head.meta.revision),
        tostring(head.meta.date),
        tostring(head.meta.nvim)
    )
    emit(header)
    emit(
        string.format(
            "%-52s %12s %12s %7s %22s %12s  %s",
            "case",
            "base",
            "head",
            "change",
            "alloc/op",
            "spawns/op",
            "status"
        )
    )
    for _, row in ipairs(rows) do
        emit(
            string.format(
                "%-52s %12s %12s %7s %22s %12s  %s",
                row.name,
                row.base,
                row.head,
                row.change,
                row.alloc,
                row.spawns,
                row.status
            )
        )
    end
    emit(string.format("%d regression(s)", regressions))

    if opts.markdown then
        local lines = {
            "## Benchmarks",
            "",
            header,
            "",
            "| Case | Base | Head | Change | Alloc/op | Spawns/op | Status |",
            "| --- | ---: | ---: | ---: | ---: | ---: | --- |",
        }
        for _, row in ipairs(rows) do
            table.insert(
                lines,
                string.format(
                    "| `%s` | %s | %s | %s | %s | %s | %s |",
                    row.name,
                    row.base,
                    row.head,
                    row.change,
                    row.alloc,
                    row.spawns,
                    row.status
                )
            )
        end
        table.insert(lines, "")
        table.insert(lines, string.format("%d regression(s)", regressions))
        table.insert(lines, "")
        local file = assert(io.open(opts.markdown, "a"))
        file:write(table.concat(lines, "\n"))
        file:close()
    end

    return regressions == 0 and 0 or 1
end

local ok, code = xpcall(main, debug.traceback)
if not ok then
    -- selene: allow(incorrect_standard_library_use)
    io.stderr:write(tostring(code) .. "\n")
    os.exit(2)
end
os.exit(code)
