local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

-- The pinned plugins of `make test-deps`. Only the child of this file adds
-- them to its runtimepath, so the other tests never load them.
local DEPS = { "deps/snacks.nvim", "deps/telescope.nvim", "deps/plenary.nvim" }

local FILE_COUNT = 120

local T = MiniTest.new_set()

-- Installs `require("scrollbar.test.integration")` in the child. Its
-- `fixture` is a directory of FILE_COUNT files with 100 lines each.
local function install(deps, file_count)
    for _, path in ipairs(deps) do
        vim.opt.runtimepath:prepend(vim.fn.fnamemodify(path, ":p"))
    end
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local lines = {}
    for index = 1, 100 do
        lines[index] = "line " .. index
    end
    for index = 1, file_count do
        vim.fn.writefile(lines, string.format("%s/file_%03d.txt", dir, index))
    end
    local M = { fixture = dir }
    package.loaded["scrollbar.test.integration"] = M

    require("scrollbar").setup({
        set_highlights = false,
        providers = { cursor = false, diagnostic = false, search = false },
        scrollbar = { floats = true, throttle_ms = 0 },
        minimap = { enabled = true, backend = "sync", floats = true, throttle_ms = 0 },
    })

    local RENDERERS = { scrollbar = "scrollbar.renderer", minimap = "scrollbar.minimap.renderer" }

    ---@param winid integer
    ---@return table
    M.bars = function(winid)
        ---@type table<string, any>
        local result = { source_zindex = vim.api.nvim_win_get_config(winid).zindex }
        for name, module in pairs(RENDERERS) do
            local state = require(module).get_state(winid)
            if state == nil then
                result[name] = false
            else
                local config = vim.api.nvim_win_get_config(state.float_win)
                result[name] = { win = config.win == winid, zindex = config.zindex }
                if name == "scrollbar" then
                    result.handle = { state.handle.first_row, state.handle.last_row }
                    result.total_extent = state.geometry.total_extent
                end
            end
        end
        return result
    end

    ---@param config table Result of nvim_win_get_config()
    ---@return integer top, integer right, integer bottom, integer left
    local function border_sides(config)
        local border = config.border
        if type(border) ~= "table" then
            return 0, 0, 0, 0
        end
        local function side(index)
            local item = border[index]
            local text = type(item) == "table" and item[1] or item
            return text ~= nil and text ~= "" and 1 or 0
        end
        return side(2), side(4), side(6), side(8)
    end

    ---@param winid integer
    ---@return { top: integer, left: integer, bottom: integer, right: integer }
    local function frame(winid)
        local config = vim.api.nvim_win_get_config(winid)
        local position = vim.api.nvim_win_get_position(winid)
        local top, right, bottom, left = border_sides(config)
        return {
            top = position[1],
            left = position[2],
            bottom = position[1] + config.height + top + bottom - 1,
            right = position[2] + config.width + left + right - 1,
        }
    end

    -- Headless Neovim does not apply the anchor in nvim_win_get_position().
    ---@param float_win integer
    local function bar_frame(float_win)
        local config = vim.api.nvim_win_get_config(float_win)
        local result = frame(float_win)
        if config.anchor == "NE" or config.anchor == "SE" then
            result.left = result.left - config.width
            result.right = result.right - config.width
        end
        if config.anchor == "SW" or config.anchor == "SE" then
            result.top = result.top - config.height
            result.bottom = result.bottom - config.height
        end
        return result
    end

    local function owned(winid)
        return vim.w[winid].scrollbar_owned == true or vim.w[winid].scrollbar_minimap_owned == true
    end

    --- The other windows with the same or a higher z-index that overlap a
    --- bar of `winid`.
    ---@param winid integer
    ---@return integer[]
    M.covering = function(winid)
        local result = {}
        for _, module in pairs(RENDERERS) do
            local state = require(module).get_state(winid)
            if state ~= nil then
                local bar = bar_frame(state.float_win)
                local zindex = vim.api.nvim_win_get_config(state.float_win).zindex
                for _, other in ipairs(vim.api.nvim_list_wins()) do
                    local config = vim.api.nvim_win_get_config(other)
                    if other ~= winid and config.relative ~= "" and not owned(other) and config.zindex >= zindex then
                        local area = frame(other)
                        if
                            area.left <= bar.right
                            and bar.left <= area.right
                            and area.top <= bar.bottom
                            and bar.top <= area.bottom
                        then
                            result[#result + 1] = other
                        end
                    end
                end
            end
        end
        return result
    end

    --- The bars whose source is a float.
    ---@return integer
    M.float_bars = function()
        local count = 0
        for _, winid in ipairs(vim.api.nvim_list_wins()) do
            if owned(winid) then
                local parent = vim.api.nvim_win_get_config(winid).win
                if parent == nil or vim.api.nvim_win_get_config(parent).relative ~= "" then
                    count = count + 1
                end
            end
        end
        return count
    end
end

local function new_child()
    for _, path in ipairs(DEPS) do
        if vim.fn.isdirectory(path) == 0 then
            MiniTest.skip(path .. " is missing. Run `make test-deps`.")
        end
    end
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    child.o.lines = 40
    child.o.columns = 120
    child.lua_func(install, DEPS, FILE_COUNT)
    return child
end

---@param child table
---@param expression string Lua expression that the child evaluates
---@return boolean
local function wait_for(child, expression)
    local deadline = vim.uv.hrtime() + 5e9
    repeat
        if child.lua_get(expression) == true then
            return true
        end
        vim.uv.sleep(20)
    until vim.uv.hrtime() > deadline
    return false
end

local FLOAT_BARS_CLOSED = 'require("scrollbar.test.integration").float_bars() == 0'

local SNACKS_READY = [[(function()
    local picker = Snacks.picker.get()[1]
    if picker == nil or picker.list:count() ~= ]] .. FILE_COUNT .. [[ then
        return false
    end
    local bars = require("scrollbar.test.integration").bars(picker.list.win.win)
    return bars.scrollbar ~= false and bars.total_extent == ]] .. FILE_COUNT .. [[
        and require("scrollbar.test.integration").bars(picker.preview.win.win).scrollbar ~= false
end)()]]

T["a snacks picker gets bars on the list and the preview"] = function()
    local child = new_child()
    child.lua([[
        require("snacks").setup({ picker = { enabled = true } })
        Snacks.picker.files({ cwd = require("scrollbar.test.integration").fixture })
    ]])
    expect.equality(wait_for(child, SNACKS_READY), true)

    local windows = child.lua_get([[(function()
        local picker = Snacks.picker.get()[1]
        return { list = picker.list.win.win, preview = picker.preview.win.win, input = picker.input.win.win }
    end)()]])
    local list = child.lua_func(function(winid)
        return require("scrollbar.test.integration").bars(winid)
    end, windows.list)
    local preview = child.lua_func(function(winid)
        return require("scrollbar.test.integration").bars(winid)
    end, windows.preview)
    local input = child.lua_func(function(winid)
        return require("scrollbar.test.integration").bars(winid)
    end, windows.input)

    expect.equality(list.scrollbar, { win = true, zindex = list.source_zindex + 1 })
    -- The minimap cannot draw the snacks list.
    expect.equality(list.minimap, false)
    expect.equality(preview.scrollbar, { win = true, zindex = preview.source_zindex + 1 })
    expect.equality(preview.minimap, { win = true, zindex = preview.source_zindex + 1 })
    expect.equality({ input.scrollbar, input.minimap }, { false, false })
    expect.equality(
        child.lua_func(function(list_win, preview_win)
            return {
                list = require("scrollbar.test.integration").covering(list_win),
                preview = require("scrollbar.test.integration").covering(preview_win),
            }
        end, windows.list, windows.preview),
        { list = {}, preview = {} }
    )

    child.lua("Snacks.picker.get()[1].list:scroll(30)")
    expect.equality(
        wait_for(
            child,
            string.format('require("scrollbar.test.integration").bars(%d).handle[1] > %d', windows.list, list.handle[1])
        ),
        true
    )

    child.lua("Snacks.picker.get()[1]:close()")
    expect.equality(wait_for(child, FLOAT_BARS_CLOSED), true)
end

local TELESCOPE_PICKER = [[(function()
    local state = require("telescope.state")
    local prompt = state.get_existing_prompt_bufnrs()[1]
    return prompt and state.get_status(prompt).picker or nil
end)()]]

T["a Telescope picker gets bars on the results and the preview"] = function()
    local child = new_child()
    child.lua([[
        require("telescope").setup({})
        require("telescope.builtin").find_files({ cwd = require("scrollbar.test.integration").fixture })
    ]])
    expect.equality(
        wait_for(
            child,
            string.format(
                [[(function()
                    local picker = %s
                    if picker == nil or picker.preview_win == nil then
                        return false
                    end
                    return require("scrollbar.test.integration").bars(picker.results_win).scrollbar ~= false
                        and require("scrollbar.test.integration").bars(picker.preview_win).scrollbar ~= false
                end)()]],
                TELESCOPE_PICKER
            )
        ),
        true
    )

    local windows = child.lua_get(string.format(
        [[(function()
            local picker = %s
            return { results = picker.results_win, preview = picker.preview_win, prompt = picker.prompt_win }
        end)()]],
        TELESCOPE_PICKER
    ))
    local results = child.lua_func(function(winid)
        return require("scrollbar.test.integration").bars(winid)
    end, windows.results)
    local preview = child.lua_func(function(winid)
        return require("scrollbar.test.integration").bars(winid)
    end, windows.preview)
    local prompt = child.lua_func(function(winid)
        return require("scrollbar.test.integration").bars(winid)
    end, windows.prompt)

    expect.equality(results.scrollbar, { win = true, zindex = results.source_zindex + 1 })
    expect.equality(results.minimap, { win = true, zindex = results.source_zindex + 1 })
    expect.equality(preview.scrollbar, { win = true, zindex = preview.source_zindex + 1 })
    expect.equality(preview.minimap, { win = true, zindex = preview.source_zindex + 1 })
    expect.equality({ prompt.scrollbar, prompt.minimap }, { false, false })
    expect.equality(
        child.lua_func(function(results_win, preview_win)
            return {
                results = require("scrollbar.test.integration").covering(results_win),
                preview = require("scrollbar.test.integration").covering(preview_win),
            }
        end, windows.results, windows.preview),
        { results = {}, preview = {} }
    )

    child.lua([[
        local state = require("telescope.state")
        require("telescope.actions").close(state.get_existing_prompt_bufnrs()[1])
    ]])
    expect.equality(wait_for(child, FLOAT_BARS_CLOSED), true)
end

return T
