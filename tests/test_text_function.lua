local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.text_function"] = nil
        end,
    },
})

local function capture_notifications()
    local messages = {}
    local original = vim.notify
    vim.notify = function(message, level)
        messages[#messages + 1] = { message = message, level = level }
    end
    MiniTest.finally(function()
        vim.notify = original
    end)
    return messages
end

local function returning(value)
    return function()
        return value
    end
end

T["returns a valid text and passes the context"] = function()
    local messages = capture_notifications()
    local text_function = require("scrollbar.text_function")
    local seen
    local text = text_function.call(function(context)
        seen = context
        return tostring(context.line + 1)
    end, { line = 41 }, "the test function")

    expect.equality(text, "42")
    expect.equality(seen, { line = 41 })
    expect.equality(text_function.call(returning("├─"), {}, "the test function"), "├─")
    expect.equality(#messages, 0)
end

T["hides nil and the empty string without a notification"] = function()
    local messages = capture_notifications()
    local text_function = require("scrollbar.text_function")

    expect.equality(text_function.call(returning(nil), {}, "the test function"), nil)
    expect.equality(text_function.call(returning(""), {}, "the test function"), nil)
    expect.equality(#messages, 0)
end

T["hides an invalid result and notifies once for each message"] = function()
    local messages = capture_notifications()
    local text_function = require("scrollbar.text_function")

    expect.equality(text_function.call(returning(42), {}, "the test function"), nil)
    expect.equality(text_function.call(returning(42), {}, "the test function"), nil)
    expect.equality(text_function.call(returning("a\tb"), {}, "the test function"), nil)

    expect.equality(messages, {
        {
            message = "[nvim-scrollbar] the test function returned a number, not a string",
            level = vim.log.levels.ERROR,
        },
        {
            message = "[nvim-scrollbar] the test function returned text with control characters",
            level = vim.log.levels.ERROR,
        },
    })
end

T["hides an error and notifies once for each label and message"] = function()
    local messages = capture_notifications()
    local text_function = require("scrollbar.text_function")
    local failing = function()
        error("boom", 0)
    end

    expect.equality(text_function.call(failing, {}, "the first function"), nil)
    expect.equality(text_function.call(failing, {}, "the first function"), nil)
    expect.equality(text_function.call(failing, {}, "the second function"), nil)

    expect.equality(messages, {
        { message = "[nvim-scrollbar] the first function failed: boom", level = vim.log.levels.ERROR },
        { message = "[nvim-scrollbar] the second function failed: boom", level = vim.log.levels.ERROR },
    })

    text_function.reset()
    text_function.call(failing, {}, "the first function")
    expect.equality(#messages, 3)
end

T["measures the display width"] = function()
    local text_function = require("scrollbar.text_function")

    expect.equality(text_function.width("153"), 3)
    expect.equality(text_function.width("a:42"), 4)
    expect.equality(text_function.width("界1"), 3)
    expect.equality(text_function.width("e\204\129"), 1)
end

return T
