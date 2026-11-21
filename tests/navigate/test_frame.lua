local MiniTest = MiniTest
local expect = MiniTest.expect

local frame = require("scrollbar.navigate.frame")

local messages
local original_notify = vim.notify

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            messages = {}
            vim.notify = function(message)
                messages[#messages + 1] = message
            end
            frame.reset()
        end,
        post_case = function()
            vim.notify = original_notify
        end,
    },
})

---@param fields? table
---@return ScrollbarFrameContext
local function context(fields)
    return vim.tbl_deep_extend("force", {
        kind = "glance",
        winid = 1000,
        bufnr = 1,
        win = { width = 80, height = 22, textoff = 0 },
        editor = { width = 120, height = 40 },
        sides = { top = 0, right = 0, bottom = 0, left = 0 },
        cursor_row = 0,
        anchor_row = 0,
        free = { side = "E", first_col = 0, last_col = 80 },
    }, fields or {})
end

---@param result any
---@param ctx? ScrollbarFrameContext
---@param top? integer
local function run(result, ctx, top)
    return frame.run("glance.frame", function()
        return result
    end, ctx or context(), top or 0)
end

T["run"] = MiniTest.new_set()

T["run"]["rounds the result down"] = function()
    expect.equality(
        run({ row = 2.7, col = 3.2, width = 30.9, height = 7.5 }),
        { relative = "win", row = 2, col = 3, width = 30, height = 7 }
    )
end

T["run"]["clamps the result into the window"] = function()
    -- A function can cover the gutter.
    expect.equality(
        run({ row = 100, col = -5, width = 500, height = 3 }, context({ win = { textoff = 4 } })),
        { relative = "win", row = 19, col = 0, width = 80, height = 3 }
    )
end

T["run"]["clamps an editor result into the editor area below the tabline"] = function()
    expect.equality(
        run({ relative = "editor", row = 50, col = 110, width = 20, height = 10 }, nil, 1),
        { relative = "editor", row = 30 + 1, col = 100, width = 20, height = 10 }
    )
end

T["run"]["nil and an empty area mean no room, without a notification"] = function()
    expect.equality({ run(nil) }, { nil, "no_room" })
    expect.equality({ run({ row = 0, col = 0, width = 5, height = 5 }, context({ win = { height = 0 } })) }, {
        nil,
        "no_room",
    })
    expect.equality(messages, {})
end

T["run"]["an invalid result notifies once for each message"] = function()
    local cases = {
        { "x", "[nvim-scrollbar] glance.frame returned a string, not a table" },
        { { col = 0, width = 1, height = 1 }, "[nvim-scrollbar] glance.frame returned no 'row'" },
        {
            { row = "1", col = 0, width = 1, height = 1 },
            "[nvim-scrollbar] glance.frame returned an invalid 'row': it must be a finite number",
        },
        {
            { row = 0, col = 0 / 0, width = 1, height = 1 },
            "[nvim-scrollbar] glance.frame returned an invalid 'col': it must be a finite number",
        },
        { { row = 0, col = 0, width = 0.5, height = 1 }, "[nvim-scrollbar] glance.frame returned a 'width' below 1" },
        {
            { relative = "cursor", row = 0, col = 0, width = 1, height = 1 },
            '[nvim-scrollbar] glance.frame returned an invalid \'relative\': it must be "win" or "editor"',
        },
    }
    local expected = {}
    for _, case in ipairs(cases) do
        expect.equality({ run(case[1]) }, { nil, "failed" })
        expect.equality({ run(case[1]) }, { nil, "failed" })
        expected[#expected + 1] = case[2]
    end
    expect.equality(messages, expected)
end

T["run"]["an error notifies once until reset"] = function()
    local function broken()
        error("boom", 0)
    end
    expect.equality({ frame.run("peek.frame", broken, context(), 0) }, { nil, "failed" })
    expect.equality({ frame.run("peek.frame", broken, context(), 0) }, { nil, "failed" })
    expect.equality(messages, { "[nvim-scrollbar] peek.frame failed: boom" })
    frame.reset()
    frame.run("peek.frame", broken, context(), 0)
    expect.equality(#messages, 2)
end

T["run"]["passes the context to the function"] = function()
    local seen
    local ctx = context({ kind = "peek", anchor_row = 7 })
    frame.run("peek.frame", function(given)
        seen = given
        return { row = 0, col = 0, width = 1, height = 1 }
    end, ctx, 0)
    expect.equality(seen, ctx)
end

return T
