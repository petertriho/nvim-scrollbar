--- Ready-made text functions for the marks and the thumb, and predicates for
--- the `when` options. Each recipe is a factory: call it, with its options,
--- to get the function.
---
--- ```lua
--- local recipes = require("scrollbar.recipes")
--- marks = { GitAdd = { text = recipes.marks.line_number({ width = 4 }) } }
--- profiles = { { match = { when = recipes.when.searching() }, ... } }
--- ```
---
--- A recipe reads only the context fields that its text needs. A mark text
--- that reads `cursor_line` makes the scrollbar build the marks again on each
--- cursor line change, so only `relative_number` reads it.

local text_function = require("scrollbar.text_function")

local M = {}

---@param name string Recipe path, for example `"marks.line_number"`
---@param message string
local function fail(name, message)
    error(string.format("[nvim-scrollbar] recipes.%s: %s", name, message), 0)
end

---@param value any
---@return boolean
local function positive_integer(value)
    return type(value) == "number" and value >= 1 and value < math.huge and value == math.floor(value)
end

---Every context has `winid`, and no argument of a factory has it. The plugin
---calls a factory with a context when the user forgets the call, as in
---`text = recipes.marks.line_number`.
---@param name string
---@param value any
local function check_call(name, value)
    if type(value) == "table" and rawget(value, "winid") ~= nil then
        fail(name, string.format("call the recipe to get its function, for example recipes.%s()", name))
    end
end

---@param name string
---@param options any
---@param allowed table<string, true>
local function check_keys(name, options, allowed)
    if type(options) ~= "table" then
        fail(name, "options must be a table")
    end
    check_call(name, options)
    for key in pairs(options) do
        if not allowed[key] then
            fail(name, string.format("unknown option '%s'", tostring(key)))
        end
    end
end

local TEXT_OPTIONS = { width = true, align = true }

---Checks and copies the options of a text recipe, so that a later change to
---the table of the user changes nothing.
---@param name string
---@param options? ScrollbarRecipeOptions
---@param default_width? integer
---@return integer? width
---@return "left"|"right" align
local function text_options(name, options, default_width)
    if options == nil then
        return default_width, "right"
    end
    check_keys(name, options, TEXT_OPTIONS)
    local width = options.width
    if width == nil then
        width = default_width
    elseif not positive_integer(width) then
        fail(name, "width must be a positive integer")
    end
    local align = options.align
    if align == nil then
        align = "right"
    elseif align ~= "left" and align ~= "right" then
        fail(name, 'align must be "left" or "right"')
    end
    return width, align
end

---Pads a text with spaces to `width` cells. A text that is as wide as
---`width`, or wider, does not change.
---@param text string
---@param width? integer
---@param align "left"|"right"
---@return string
local function pad(text, width, align)
    if width == nil then
        return text
    end
    local missing = width - text_function.width(text)
    if missing <= 0 then
        return text
    end
    if align == "left" then
        return text .. string.rep(" ", missing)
    end
    return string.rep(" ", missing) .. text
end

---Vim's 'ruler' position of the view: `All`, `Top`, `Bot`, or the percentage
---of the lines above the view, as `get_rel_pos()` and `calc_perc()` of Neovim
---compute it. Lines are zero-based.
---@param top_line integer
---@param bottom_line integer
---@param line_count integer
---@return string
local function ruler_position(top_line, bottom_line, line_count)
    local above = top_line
    local below = line_count - bottom_line - 1
    if below <= 0 then
        return above <= 0 and "All" or "Bot"
    end
    if above <= 0 then
        return "Top"
    end
    local whole = above + below
    local percent
    -- Neovim divides first for large counts, which rounds a little
    -- differently. Keep the same result.
    if above > 1000000 then
        percent = math.floor(above / math.floor(whole / 100))
    else
        percent = math.floor(above * 100 / whole)
    end
    return percent .. "%"
end

M.marks = {}

---The line of the mark, one-based. A click on the mark goes to this line.
---@param options? ScrollbarRecipeOptions
---@return ScrollbarMarkTextFunction
M.marks.line_number = function(options)
    local width, align = text_options("marks.line_number", options)
    return function(context)
        return pad(tostring(context.line + 1), width, align)
    end
end

---The number of lines between the cursor line and the line of the mark. A
---closed fold counts by its lines.
---@param options? ScrollbarRecipeOptions
---@return ScrollbarMarkTextFunction
M.marks.relative_number = function(options)
    local width, align = text_options("marks.relative_number", options)
    return function(context)
        local cursor_line = context.cursor_line
        if cursor_line == nil then
            return nil
        end
        local distance = context.line - cursor_line
        if distance < 0 then
            distance = -distance
        end
        return pad(tostring(distance), width, align)
    end
end

---The number of marks of the group. A count with more digits than `width`
---(default 1) shows `+`.
---@param options? ScrollbarRecipeOptions
---@return ScrollbarMarkTextFunction
M.marks.count = function(options)
    local width, align = text_options("marks.count", options, 1)
    ---@cast width integer
    return function(context)
        local text = tostring(context.count)
        if #text > width then
            text = "+"
        end
        return pad(text, width, align)
    end
end

---The text of the mark from its provider and the line, for example `a:42`
---for the named mark `a`. Without provider text, only the line.
---@param options? ScrollbarRecipeOptions
---@return ScrollbarMarkTextFunction
M.marks.label = function(options)
    local width, align = text_options("marks.label", options)
    return function(context)
        local text = tostring(context.line + 1)
        local label = context.text
        if label ~= nil and label ~= "" then
            text = label .. ":" .. text
        end
        return pad(text, width, align)
    end
end

M.thumb = {}

---The first visible line, one-based, on the first thumb row.
---@param options? ScrollbarRecipeOptions
---@return ScrollbarThumbTextFunction
M.thumb.top_line = function(options)
    local width, align = text_options("thumb.top_line", options)
    return function(context)
        if context.index ~= 0 then
            return nil
        end
        return pad(tostring(context.top_line + 1), width, align)
    end
end

---The first visible line on the first thumb row, and the last visible line on
---the last thumb row. A thumb of one row shows only the first line.
---@param options? ScrollbarRecipeOptions
---@return ScrollbarThumbTextFunction
M.thumb.range = function(options)
    local width, align = text_options("thumb.range", options)
    return function(context)
        local index = context.index
        if index == 0 then
            return pad(tostring(context.top_line + 1), width, align)
        end
        if index == context.last_row - context.first_row then
            return pad(tostring(context.bottom_line + 1), width, align)
        end
        return nil
    end
end

---The position of the view as Vim's 'ruler' shows it, on the first thumb row:
---`All`, `Top`, `Bot`, or a percentage such as `45%`.
---@param options? ScrollbarRecipeOptions
---@return ScrollbarThumbTextFunction
M.thumb.percent = function(options)
    local width, align = text_options("thumb.percent", options)
    return function(context)
        if context.index ~= 0 then
            return nil
        end
        return pad(ruler_position(context.top_line, context.bottom_line, context.line_count), width, align)
    end
end

M.when = {}

---@param name string
---@param ... any
local function no_options(name, ...)
    if select("#", ...) == 0 or (...) == nil then
        return
    end
    check_call(name, (...))
    fail(name, "takes no options")
end

---@param name string
---@param ... any
---@return function[] predicates
---@return integer count
local function predicate_list(name, ...)
    local count = select("#", ...)
    if count == 0 then
        fail(name, "needs at least one predicate")
    end
    local list = { ... }
    for index = 1, count do
        local value = list[index]
        check_call(name, value)
        if type(value) ~= "function" then
            fail(name, string.format("argument %d must be a function", index))
        end
    end
    return list, count
end

local SEARCHING_OPTIONS = { cmdline = true }

---Matches while a search is visible, by the rule of the search provider:
---'hlsearch' is on, `v:hlsearch` is set, and the search register is not
---empty. With `cmdline` (default true), an open `/` or `?` command line also
---matches, so that incremental previews use the same profile.
---@param options? { cmdline?: boolean }
---@return ScrollbarWhenFunction
M.when.searching = function(options)
    local cmdline = true
    if options ~= nil then
        check_keys("when.searching", options, SEARCHING_OPTIONS)
        if options.cmdline ~= nil then
            if type(options.cmdline) ~= "boolean" then
                fail("when.searching", "cmdline must be a boolean")
            end
            cmdline = options.cmdline
        end
    end
    return function()
        if cmdline then
            local cmdtype = vim.fn.getcmdtype()
            if cmdtype == "/" or cmdtype == "?" then
                return true
            end
        end
        return vim.o.hlsearch and vim.v.hlsearch ~= 0 and vim.fn.getreg("/") ~= ""
    end
end

---Matches a window with 'diff' set.
---@return ScrollbarWhenFunction
M.when.diff = function(...)
    no_options("when.diff", ...)
    return function(context)
        return vim.api.nvim_get_option_value("diff", { win = context.winid }) == true
    end
end

local LINE_COUNT_OPTIONS = { min = true, max = true }

---Matches a buffer with at least `min` lines, at most `max` lines, or both.
---@param options { min?: integer, max?: integer }
---@return ScrollbarWhenFunction
M.when.line_count = function(options)
    local name = "when.line_count"
    if options == nil then
        fail(name, "needs min or max")
    end
    check_keys(name, options, LINE_COUNT_OPTIONS)
    ---@cast options -nil
    local min, max = options.min, options.max
    if min == nil and max == nil then
        fail(name, "needs min or max")
    end
    if min ~= nil and not positive_integer(min) then
        fail(name, "min must be a positive integer")
    end
    if max ~= nil and not positive_integer(max) then
        fail(name, "max must be a positive integer")
    end
    if min ~= nil and max ~= nil and min > max then
        fail(name, "min must not be more than max")
    end
    return function(context)
        local count = vim.api.nvim_buf_line_count(context.bufnr)
        return (min == nil or count >= min) and (max == nil or count <= max)
    end
end

local RENDERER_MODULES = {
    scrollbar = "scrollbar.renderer",
    minimap = "scrollbar.minimap.renderer",
}

-- The active rule checks the float eligibility, which calls `floats.when`. A
-- call of `active()` inside that check returns false instead of a loop.
local active_depth = 0

---Matches the windows that the renderer of `context.renderer` counts as
---active, by the rule of `visibility = "active"`: the current window, the
---source window of a focused scrollbar or minimap, and the windows of a
---focused picker.
---@return ScrollbarWhenFunction
M.when.active = function(...)
    no_options("when.active", ...)
    return function(context)
        local module = RENDERER_MODULES[context.renderer]
        local renderer = module and package.loaded[module]
        if renderer == nil or active_depth > 0 then
            return false
        end
        active_depth = active_depth + 1
        local ok, active = pcall(renderer._is_active, context.winid)
        active_depth = active_depth - 1
        if not ok then
            error(active, 0)
        end
        return active
    end
end

---Matches the windows of a buffer with one of the filetypes.
---@param filetypes string[]
---@return ScrollbarWhenFunction
M.when.filetypes = function(filetypes)
    local name = "when.filetypes"
    check_call(name, filetypes)
    if type(filetypes) ~= "table" then
        fail(name, "needs a non-empty list of filetypes")
    end
    local lookup = {}
    local count = 0
    for key, value in pairs(filetypes) do
        if type(key) ~= "number" or type(value) ~= "string" then
            fail(name, "needs a non-empty list of filetypes")
        end
        count = count + 1
        lookup[value] = true
    end
    if count == 0 or count ~= #filetypes then
        fail(name, "needs a non-empty list of filetypes")
    end
    return function(context)
        return lookup[context.filetype] == true
    end
end

---Matches when one of the predicates matches.
---@param ... ScrollbarWhenFunction
---@return ScrollbarWhenFunction
M.when.any = function(...)
    local list, count = predicate_list("when.any", ...)
    return function(context)
        for index = 1, count do
            if list[index](context) then
                return true
            end
        end
        return false
    end
end

---Matches when each predicate matches.
---@param ... ScrollbarWhenFunction
---@return ScrollbarWhenFunction
M.when.all = function(...)
    local list, count = predicate_list("when.all", ...)
    return function(context)
        for index = 1, count do
            if not list[index](context) then
                return false
            end
        end
        return true
    end
end

---Matches when the predicate does not match.
---@param predicate ScrollbarWhenFunction
---@return ScrollbarWhenFunction
M.when.negate = function(predicate, ...)
    if select("#", ...) > 0 then
        fail("when.negate", "takes one predicate")
    end
    local list = predicate_list("when.negate", predicate)
    local only = list[1]
    return function(context)
        return not only(context)
    end
end

return M
