-- Runs the benchmarks and prints one line for each case.
--
--   nvim --headless --clean -l benchmarks/run.lua [options]
--
-- Options:
--   --root DIR            Measure the nvim-scrollbar code in DIR (default: this repository). The cases always come
--                         from this repository, so that two revisions run the same cases.
--   --json FILE           Write the results to FILE for benchmarks/compare.lua.
--   --filter PATTERN      Run only the cases whose names match the Lua pattern.
--   --samples N           Samples for each sync case (default 15).
--   --async-samples N     Samples for each async case (default 10).
--   --revision REV        The revision to record in the results (default: `git rev-parse --short HEAD` in the root).
--   --allow-errors        Exit with 0 when a case fails. Use it for an older revision that lacks an API that a case
--                         needs.

local bench_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = string.format("%s/?.lua;%s", bench_root, package.path)

-- `print` in `nvim -l` writes to stderr, and it ends a line only when the next message starts or Neovim exits
-- normally. `os.exit` skips that exit, so the lines go to stdout.
---@param line string
local function emit(line)
    io.write(line, "\n")
end

local CASE_MODULES = {
    "benchmarks.cases.render",
    "benchmarks.cases.typing",
    "benchmarks.cases.providers",
    "benchmarks.cases.marks",
    "benchmarks.cases.search",
    "benchmarks.cases.minimap",
    "benchmarks.cases.worker",
}

---@param argv string[]
---@return { root: string, json?: string, filter?: string, revision?: string, samples: integer, async_samples: integer, allow_errors: boolean }
local function parse_args(argv)
    local opts = { root = bench_root, samples = 15, async_samples = 10, allow_errors = false }
    local i = 1
    while i <= #argv do
        local name = argv[i]
        local function value()
            i = i + 1
            return argv[i] or error("missing value for " .. name, 0)
        end

        if name == "--root" then
            opts.root = value()
        elseif name == "--json" then
            opts.json = value()
        elseif name == "--filter" then
            opts.filter = value()
        elseif name == "--revision" then
            opts.revision = value()
        elseif name == "--samples" then
            opts.samples = assert(tonumber(value()), "--samples needs a number")
        elseif name == "--async-samples" then
            opts.async_samples = assert(tonumber(value()), "--async-samples needs a number")
        elseif name == "--allow-errors" then
            opts.allow_errors = true
        else
            error("unknown option " .. name, 0)
        end
        i = i + 1
    end
    opts.root = vim.fs.normalize(vim.fn.fnamemodify(opts.root, ":p"))
    return opts
end

---@param root string
---@return string?
local function revision(root)
    local result = vim.system({ "git", "-C", root, "rev-parse", "--short", "HEAD" }, { text = true }):wait()
    if result.code ~= 0 then
        return nil
    end
    return vim.trim(result.stdout)
end

local function main()
    -- `nvim -l` gives the script arguments in the global `arg`
    -- selene: allow(global_usage)
    local opts = parse_args(_G.arg)

    vim.opt.runtimepath:prepend(opts.root)
    -- The worker children get their code from the same runtime path, so they also run the code of the root
    local init_path = vim.api.nvim_get_runtime_file("lua/scrollbar/init.lua", false)[1]
    if not init_path or vim.fs.normalize(init_path) ~= opts.root .. "/lua/scrollbar/init.lua" then
        error(string.format("nvim-scrollbar does not load from %s (found %s)", opts.root, tostring(init_path)), 0)
    end

    local harness = require("benchmarks.harness")
    local fixtures = require("benchmarks.fixtures")
    fixtures.isolate_environment()

    ---@type bench.Options
    local measure_opts = {
        samples = opts.samples,
        async_samples = opts.async_samples,
        min_sample_ns = 5e6,
        alloc_ops = 32,
        timeout_ms = 10000,
    }

    local order = {}
    local results = {} ---@type table<string, bench.Result>
    local errors = {} ---@type table<string, string>

    for _, module in ipairs(CASE_MODULES) do
        for _, case in ipairs(require(module)) do
            if not opts.filter or case.name:find(opts.filter) then
                table.insert(order, case.name)
                local ok, result = pcall(harness.measure, case, measure_opts)
                if ok then
                    results[case.name] = result
                    emit(harness.format_result(case.name, result))
                else
                    errors[case.name] = tostring(result)
                    emit(string.format("%-52s  ERROR %s", case.name, tostring(result)))
                end
            end
        end
    end

    if opts.json then
        local version = vim.version()
        local uname = vim.uv.os_uname()
        local file = assert(io.open(opts.json, "w"))
        file:write(vim.json.encode({
            version = 1,
            meta = {
                date = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                nvim = string.format("%d.%d.%d", version.major, version.minor, version.patch),
                luajit = package.loaded.jit and package.loaded.jit.version or _VERSION,
                os = string.format("%s %s", uname.sysname, uname.machine),
                root = opts.root,
                revision = opts.revision or revision(opts.root),
            },
            order = order,
            -- An empty table encodes as a JSON array
            results = next(results) and results or vim.empty_dict(),
            errors = next(errors) and errors or vim.empty_dict(),
        }))
        file:close()
    end

    fixtures.cleanup()
    return (next(errors) == nil or opts.allow_errors) and 0 or 1
end

local ok, code = xpcall(main, debug.traceback)
if not ok then
    -- selene: allow(incorrect_standard_library_use)
    io.stderr:write(tostring(code) .. "\n")
    require("benchmarks.fixtures").cleanup()
    os.exit(2)
end
os.exit(code)
