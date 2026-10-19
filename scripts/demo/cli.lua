-- Build the demo images and the bodies of the two GitHub issues.
--
--   nvim -l scripts/demo/cli.lua build [id ...]  Render images into scripts/demo/out/
--   nvim -l scripts/demo/cli.lua manifest <issue>  Match the attachments of <issue> to the images
--   nvim -l scripts/demo/cli.lua issues [showcase]  Write out/.work/assets.md and out/.work/showcase.md
--
-- `build` runs the VHS command from `$VHS` (default `vhs`), for example
-- `VHS="nix shell nixpkgs#vhs -c vhs"`.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
local demo_dir = root .. "/scripts/demo"
local out_dir = demo_dir .. "/out"
-- Hidden, so that a file picker on out/ shows only the images.
local work_dir = out_dir .. "/.work"
local manifest_path = demo_dir .. "/manifest.json"

local catalog = dofile(demo_dir .. "/entries.lua")

local REPO_URL = "https://github.com/petertriho/nvim-scrollbar"
local BRANCH = "main"
-- GitHub rejects larger image attachments.
local MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024
local MAX_ISSUE_BODY = 65536
local PARALLEL_JOBS = 4

local function fail(message)
    error(message, 0)
end

---@param path string
---@param content string
local function write_file(path, content)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local file = assert(io.open(path, "wb"))
    file:write(content)
    file:close()
end

---@param path string
---@return string?
local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

---@param command string[]
---@return string
local function run(command)
    local result = vim.system(command, { cwd = root, text = true }):wait()
    if result.code ~= 0 then
        fail(table.concat(command, " ") .. ": " .. vim.trim(result.stderr or ""))
    end
    return result.stdout or ""
end

---@param path string
---@return string
local function sha256(path)
    return (run({ "sha256sum", path }):match("^(%x+)"))
end

---@return table<string, { sha256: string, url: string }>
local function read_manifest()
    local content = read_file(manifest_path)
    if content == nil then
        return {}
    end
    return vim.json.decode(content)
end

---@param manifest table<string, { sha256: string, url: string }>
local function write_manifest(manifest)
    local files = vim.tbl_keys(manifest)
    table.sort(files)
    local lines = { "{" }
    for index, file in ipairs(files) do
        local item = manifest[file]
        table.insert(lines, string.format("  %s: {", vim.json.encode(file)))
        table.insert(lines, string.format("    %q: %s,", "sha256", vim.json.encode(item.sha256)))
        table.insert(lines, string.format("    %q: %s", "url", vim.json.encode(item.url)))
        table.insert(lines, index < #files and "  }," or "  }")
    end
    table.insert(lines, "}")
    write_file(manifest_path, table.concat(lines, "\n") .. "\n")
end

-- Build

---@param text string
---@return string
local function regex_escape(text)
    return (text:gsub("[%^%$%(%)%.%[%]%*%+%?%{%}%|\\]", "\\%0"))
end

---@param entry DemoEntry
---@return string
local function png_tape(entry)
    assert(not entry.label:find("/"), "labels must not contain '/': " .. entry.id)
    return table.concat({
        'Source "scripts/demo/settings.tape"',
        string.format('Output "scripts/demo/out/.work/%s.gif"', entry.id),
        "Hide",
        string.format('Type `DEMO_ENTRY=%s "$DEMO_NVIM" --clean -u scripts/demo/init.lua %s`', entry.id, catalog.file),
        "Enter",
        -- The statusline shows the label at its right edge once the demo is ready.
        string.format("Wait+Screen@30s /(?m)%s$/", regex_escape(entry.label)),
        "Show",
        "Sleep 200ms",
        string.format('Screenshot "scripts/demo/out/%s"', entry.file),
        "Sleep 200ms",
        "",
    }, "\n")
end

---@param ids string[]
local function build(ids)
    local selected = {}
    if #ids == 0 then
        selected = catalog.entries
    else
        for _, id in ipairs(ids) do
            table.insert(selected, catalog.find(id))
        end
    end

    local vhs = vim.split(os.getenv("VHS") or "vhs", "%s+", { trimempty = true })
    -- Check before any image is replaced, so a missing VHS keeps the old images.
    if vhs[1] == nil or vim.fn.executable(vhs[1]) == 0 then
        fail(
            string.format(
                "'%s' is not executable. Set VHS, for example VHS=\"nix shell nixpkgs#vhs -c vhs\".",
                vhs[1] or ""
            )
        )
    end
    vim.fn.mkdir(work_dir, "p")

    local jobs = {}
    for _, entry in ipairs(selected) do
        local tape
        if entry.kind == "gif" then
            tape = demo_dir .. "/" .. entry.id .. ".tape"
        else
            tape = work_dir .. "/" .. entry.id .. ".tape"
            write_file(tape, png_tape(entry))
        end
        table.insert(jobs, { entry = entry, command = vim.list_extend(vim.deepcopy(vhs), { "--quiet", tape }) })
    end

    local next_job, running, finished = 0, 0, 0
    local function start_jobs()
        while running < PARALLEL_JOBS and next_job < #jobs do
            next_job = next_job + 1
            local job = jobs[next_job]
            running = running + 1
            -- A failed run must not leave the previous image in place.
            os.remove(out_dir .. "/" .. job.entry.file)
            vim.system(job.command, {
                cwd = root,
                text = true,
                env = { DEMO_NVIM = vim.v.progpath },
            }, function(result)
                job.result = result
                running = running - 1
                finished = finished + 1
                vim.schedule(start_jobs)
            end)
        end
    end
    start_jobs()
    vim.wait(60 * 60 * 1000, function()
        return finished == #jobs
    end, 100)

    local failed = false
    for _, job in ipairs(jobs) do
        local path = out_dir .. "/" .. job.entry.file
        local size = vim.fn.getfsize(path)
        local status
        if job.result.code ~= 0 or size <= 0 then
            failed = true
            status = "FAILED " .. vim.trim((job.result.stderr or "") .. " " .. (job.result.stdout or ""))
        elseif size > MAX_ATTACHMENT_BYTES then
            failed = true
            status = string.format("TOO LARGE (%.1f MB)", size / 1024 / 1024)
        else
            status = string.format("%.0f KB", size / 1024)
        end
        io.write(string.format("%-24s %s\n", job.entry.file, status))
    end
    if failed then
        fail("some images failed")
    end
end

-- Manifest

---@param issue string
local function manifest(issue)
    local data = vim.json.decode(run({ "gh", "issue", "view", issue, "--json", "body,comments" }))
    local texts = { data.body }
    for _, comment in ipairs(data.comments) do
        table.insert(texts, comment.body)
    end

    local urls, seen = {}, {}
    for _, text in ipairs(texts) do
        for url in text:gmatch("https://github%.com/user%-attachments/assets/[%w%-]+") do
            if not seen[url] then
                seen[url] = true
                table.insert(urls, url)
            end
        end
    end

    local by_hash = {}
    local download = vim.fn.tempname()
    for _, url in ipairs(urls) do
        run({ "curl", "--fail", "--silent", "--show-error", "--location", "--output", download, url })
        by_hash[sha256(download)] = url
    end
    os.remove(download)

    local result, matched, missing = {}, {}, {}
    for _, entry in ipairs(catalog.entries) do
        local path = out_dir .. "/" .. entry.file
        if vim.fn.filereadable(path) == 0 then
            table.insert(missing, entry.file .. " (not built)")
        else
            local hash = sha256(path)
            local url = by_hash[hash]
            if url == nil then
                table.insert(missing, entry.file)
            else
                matched[url] = true
                result[entry.file] = { sha256 = hash, url = url }
            end
        end
    end

    for _, url in ipairs(urls) do
        if not matched[url] then
            io.write("unused attachment: ", url, "\n")
        end
    end
    if #missing > 0 then
        fail("no attachment matches: " .. table.concat(missing, ", "))
    end
    write_manifest(result)
    io.write(string.format("matched %d images, wrote %s\n", vim.tbl_count(result), manifest_path))
end

-- Issue bodies

---@param text string
---@return string
local function slug(text)
    return (text:lower():gsub("[^%w%s%-_]", ""):gsub("%s", "-"))
end

---@param entry DemoEntry
---@return string
local function heading(entry)
    if entry.section == "scrollbar" then
        return "Scrollbar: " .. entry.title
    elseif entry.section == "minimap" then
        return "Minimap: " .. entry.title
    end
    return entry.title
end

---@param entry DemoEntry
---@param manifest_data table<string, { url: string }>
---@param width? integer
---@return string
local function image(entry, manifest_data, width)
    local item = manifest_data[entry.file]
    if item == nil then
        return string.format("_`%s` is not uploaded yet._", entry.file)
    end
    if width then
        return string.format('<img src="%s" alt="%s" width="%d">', item.url, entry.title, width)
    end
    return string.format("![%s](%s)", entry.title, item.url)
end

local COMMON_SETUP = [[
```lua
{
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
        require("tokyonight").setup({
            style = "night",
            on_highlights = function(highlights, colors)
                highlights.ScrollbarSearch = { fg = colors.orange }
                highlights.ScrollbarMinimapSearch = { fg = colors.orange }
                highlights.ScrollbarMinimapCursor = { fg = colors.fg, bg = colors.fg }
            end,
        })
        vim.cmd.colorscheme("tokyonight")
    end,
},
{
    "nvim-mini/mini.diff",
    version = false,
    opts = {},
},
{
    "petertriho/nvim-scrollbar",
    config = function()
        -- Paste the setup of an entry here.
    end,
},
```]]

---@param manifest_data table<string, { url: string }>
---@return string
local function showcase_body(manifest_data)
    local lines = {
        string.format(
            "Each image shows one preset or configuration, and its snippet is the exact setup that produced it. [`scripts/demo/`](%s/tree/%s/scripts/demo) generates the images with `make demo`.",
            REPO_URL,
            BRANCH
        ),
        "",
        "Share your own configuration in a comment.",
        "",
        "## Contents",
        "",
        "- [Common setup](#common-setup)",
    }
    for _, section in ipairs(catalog.sections) do
        table.insert(lines, string.format("- [%s](#%s)", section.title, slug(section.title)))
        for _, entry in ipairs(catalog.entries) do
            if entry.section == section.id and section.id ~= "author" then
                table.insert(lines, string.format("  - [%s](#%s)", heading(entry), slug(heading(entry))))
            end
        end
    end
    vim.list_extend(lines, {
        "",
        "## Common setup",
        "",
        "Every image uses this lazy.nvim setup: the tokyonight `night` style with three scrollbar highlight overrides, mini.diff for the Git hunks, and nvim-scrollbar.",
        "",
        COMMON_SETUP,
        "",
        string.format(
            'The editor options are `number`, `relativenumber`, `cursorline`, `signcolumn = "no"`, `cmdheight = 0`, and `laststatus = 3`. The demo sets fixed diagnostics, Git hunks, the named marks `a` to `e`, and a search for `%s` in [`%s`](%s/blob/%s/%s).',
            catalog.search_pattern,
            catalog.file,
            REPO_URL,
            BRANCH,
            catalog.file
        ),
    })

    for _, section in ipairs(catalog.sections) do
        vim.list_extend(lines, { "", "## " .. section.title })
        for _, entry in ipairs(catalog.entries) do
            if entry.section == section.id then
                if section.id ~= "author" then
                    vim.list_extend(lines, { "", "### " .. heading(entry) })
                end
                vim.list_extend(lines, {
                    "",
                    entry.description,
                    "",
                    image(entry, manifest_data),
                    "",
                    "```lua",
                    vim.trim(entry.setup),
                    "```",
                })
            end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end

---@param manifest_data table<string, { url: string }>
---@param showcase_issue? string
---@return string
local function assets_body(manifest_data, showcase_issue)
    local showcase = showcase_issue and ("the showcase (#" .. showcase_issue .. ")") or "the showcase issue"
    local lines = {
        string.format(
            "This issue stores the images of the README, the docs, and %s as attachments. The docs and the showcase embed the attachment URLs.",
            showcase
        ),
        "",
        "> [!WARNING]",
        "> Do not delete a comment with attachments. That breaks the images that use them.",
        "",
        string.format(
            "[`scripts/demo/`](%s/tree/%s/scripts/demo) generates the images. To replace them:",
            REPO_URL,
            BRANCH
        ),
        "",
        "1. Run `make demo`.",
        "2. Drag the new files from `scripts/demo/out/` into a new comment on this issue.",
        "3. Run `make demo-manifest ISSUE=<this issue>` to match the attachments to the files by SHA-256.",
        "4. Run `make demo-issues`, then update the docs and the showcase with the new URLs.",
        "",
        "| File | Used in | Image |",
        "| --- | --- | --- |",
    }
    for _, entry in ipairs(catalog.entries) do
        local used = {}
        if entry.docs then
            table.insert(used, "`" .. entry.docs .. "`")
        end
        if entry.section then
            table.insert(used, "showcase")
        end
        table.insert(
            lines,
            string.format("| `%s` | %s | %s |", entry.file, table.concat(used, ", "), image(entry, manifest_data, 200))
        )
    end
    return table.concat(lines, "\n") .. "\n"
end

---@param showcase_issue? string
local function issues(showcase_issue)
    local manifest_data = read_manifest()
    local showcase = showcase_body(manifest_data)
    if #showcase > MAX_ISSUE_BODY then
        fail(string.format("the showcase body has %d characters, more than %d", #showcase, MAX_ISSUE_BODY))
    end
    write_file(out_dir .. "/.work/showcase.md", showcase)
    write_file(out_dir .. "/.work/assets.md", assets_body(manifest_data, showcase_issue))
    io.write(
        string.format(
            "wrote %s/.work/showcase.md (%d characters) and %s/.work/assets.md\n",
            out_dir,
            #showcase,
            out_dir
        )
    )
end

local command = arg[1]
local args = vim.list_slice(arg, 2)
if command == "build" then
    build(args)
elseif command == "manifest" then
    if args[1] == nil then
        fail("usage: cli.lua manifest <issue>")
    end
    manifest(args[1])
elseif command == "issues" then
    issues(args[1])
else
    fail("usage: cli.lua build [id ...] | manifest <issue> | issues [showcase issue]")
end
