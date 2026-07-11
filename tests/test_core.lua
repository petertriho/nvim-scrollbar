local MiniTest = MiniTest
local helpers = require("tests.helpers")
local expect = MiniTest.expect

local T = MiniTest.new_set()

local function new_child()
    local child = helpers.new_child()
    MiniTest.finally(function()
        helpers.stop_child(child)
    end)
    return child
end

local function setup_render_case(child, exclusions)
    child.lua_func(function(config)
        require("scrollbar").setup({
            set_highlights = false,
            throttle_ms = 0,
            autocmd = { render = {} },
            excluded_buftypes = config.excluded_buftypes or {},
            excluded_filetypes = config.excluded_filetypes or {},
            handle = { text = "H", hide_if_all_visible = false },
            handlers = {
                cursor = false,
                diagnostic = false,
                gitsigns = false,
                search = false,
                ale = false,
            },
        })
        require("scrollbar.handlers").register("test", function()
            return { { line = 90, text = "!", type = "Misc", level = 1 } }
        end)
    end, exclusions or {})

    local lines = {}
    for index = 1, 100 do
        lines[index] = "line " .. index
    end
    helpers.set_lines(child, lines)
end

local function render_extmarks(child)
    return child.lua_get([[(function()
        require("scrollbar.handlers").show()
        require("scrollbar").render()
        local namespace = vim.api.nvim_get_namespaces().Scrollbar
        return vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })
    end)()]])
end

T["default setup succeeds in a clean child process"] = function()
    local child = new_child()
    expect.no_error(function()
        child.lua([[require("scrollbar").setup()]])
    end)
end

T["renders handler marks as right-aligned extmarks"] = function()
    local child = new_child()
    setup_render_case(child)
    local extmarks = render_extmarks(child)
    local rendered_mark

    for _, extmark in ipairs(extmarks) do
        local details = extmark[4]
        if details.virt_text and details.virt_text[1][1] == "!" then
            rendered_mark = details
            break
        end
    end

    expect.no_equality(rendered_mark, nil)
    expect.equality(rendered_mark.virt_text_pos, "right_align")
end

T["does not render in an excluded filetype"] = function()
    local child = new_child()
    setup_render_case(child, { excluded_filetypes = { "scrollbar-test" } })
    child.bo.filetype = "scrollbar-test"
    expect.equality(#render_extmarks(child), 0)
end

T["does not render in an excluded buftype"] = function()
    local child = new_child()
    setup_render_case(child, { excluded_buftypes = { "nofile" } })
    child.bo.buftype = "nofile"
    expect.equality(#render_extmarks(child), 0)
end

return T
