local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.minimap.projection"] = nil
            package.loaded["scrollbar.minimap.squash"] = nil
        end,
    },
})

local function projection()
    return require("scrollbar.minimap.projection")
end

local function new(options)
    return projection().new(vim.tbl_extend("force", {
        scale = "fixed",
        line_count = 400,
        rows = 20,
        width = 16,
        columns_per_dot = 4,
        top = 0,
        bottom = 39,
    }, options or {}))
end

T["the fixed scale shows four lines in each row"] = function()
    local p = new({ line_count = 40 })

    expect.equality(p.map_rows, 10)
    expect.equality(p.offset, 0)
    expect.equality(projection().float_row(p, 0), 1)
    expect.equality(projection().float_row(p, 3), 1)
    expect.equality(projection().float_row(p, 4), 2)
    expect.equality(projection().float_row(p, 39), 10)
    expect.equality(projection().float_row(p, 40), nil)
end

T["the fixed scale scrolls in proportion to the source window"] = function()
    expect.equality(new({ top = 0, bottom = 39 }).offset, 0)
    expect.equality(new({ top = 180, bottom = 219 }).offset, 40)
    expect.equality(new({ top = 360, bottom = 399 }).offset, 80)

    local p = new({ top = 180, bottom = 219 })
    expect.equality(projection().float_row(p, 0), nil)
    expect.equality(projection().float_row(p, 160), 1)
    expect.equality(projection().float_row(p, 239), 20)
    expect.equality(projection().float_row(p, 240), nil)
end

T["the end of the file shows the end of the map"] = function()
    local p = new({ top = 360, bottom = 399 })

    expect.equality(projection().float_row(p, 399), 20)
    expect.equality({ projection().band(p) }, { 11, 20 })
end

T["a numeric scale gives each dot row that number of lines"] = function()
    local p = new({ scale = 2 })

    expect.equality(p.scale_lines, 2)
    expect.equality(p.scale_dots, 1)
    expect.equality(p.map_rows, 50)
    expect.equality(projection().float_row(p, 7), 1)
    expect.equality(projection().float_row(p, 8), 2)
    expect.equality(projection().float_row(p, 159), 20)
    expect.equality(projection().float_row(p, 160), nil)
    expect.equality({ projection().band(p) }, { 1, 5 })
end

T["a numeric scale scrolls in proportion to the source window"] = function()
    expect.equality(new({ scale = 2, top = 0, bottom = 39 }).offset, 0)
    expect.equality(new({ scale = 2, top = 180, bottom = 219 }).offset, 15)
    expect.equality(new({ scale = 2, top = 360, bottom = 399 }).offset, 30)

    local last = new({ scale = 2, top = 360, bottom = 399 })
    expect.equality(projection().float_row(last, 399), 20)
end

T["scale 1 matches the fixed scale"] = function()
    local fixed = new({ top = 180, bottom = 219 })
    local one = new({ scale = 1, top = 180, bottom = 219 })

    expect.equality(one.offset, fixed.offset)
    expect.equality(one.map_rows, fixed.map_rows)
    for line = 0, 399 do
        expect.equality(projection().float_row(one, line), projection().float_row(fixed, line))
    end
end

T["the fit scale shows the whole buffer"] = function()
    local p = new({ scale = "fit" })

    expect.equality(p.offset, 0)
    expect.equality(p.map_rows, 20)
    expect.equality(projection().float_row(p, 0), 1)
    expect.equality(projection().float_row(p, 19), 1)
    expect.equality(projection().float_row(p, 20), 2)
    expect.equality(projection().float_row(p, 399), 20)
    expect.equality(new({ scale = "fit", top = 360, bottom = 399 }).offset, 0)
end

T["the fit scale matches the fixed scale when the buffer fits"] = function()
    local fixed = new({ line_count = 60, top = 10, bottom = 49 })
    local fit = new({ scale = "fit", line_count = 60, top = 10, bottom = 49 })

    expect.equality(fit.scale_lines, fixed.scale_lines)
    expect.equality(fit.scale_dots, fixed.scale_dots)
    for line = 0, 59 do
        expect.equality(projection().float_row(fit, line), projection().float_row(fixed, line))
    end
end

T["row_line inverts float_row in both scales"] = function()
    for _, options in ipairs({
        { top = 180, bottom = 219 },
        { scale = "fit", line_count = 100 },
        { scale = "fit", line_count = 997, top = 500, bottom = 539 },
    }) do
        local p = new(options)
        for row = 0, p.rows - 1 do
            local line = projection().row_line(p, row)
            expect.equality(projection().float_row(p, line), row + 1)
        end
        for line = 0, p.line_count - 1 do
            local row = projection().float_row(p, line)
            if row ~= nil then
                expect.equality(projection().row_line(p, row - 1) <= line, true)
            end
        end
    end
end

T["the band rounds outward to every row with a visible line"] = function()
    expect.equality({ projection().band(new({ line_count = 40, top = 5, bottom = 10 })) }, { 2, 3 })
    expect.equality({ projection().band(new({ line_count = 40, top = 4, bottom = 7 })) }, { 2, 2 })
    expect.equality({ projection().band(new({ scale = "fit", top = 30, bottom = 69 })) }, { 2, 4 })
end

T["cell maps display columns through columns_per_dot"] = function()
    local p = new({ width = 2 })

    expect.equality(projection().cell(p, 0), 1)
    expect.equality(projection().cell(p, 7), 1)
    expect.equality(projection().cell(p, 8), 2)
    expect.equality(projection().cell(p, 200), 2)
end

T["the slice keeps one float height of rows on each side"] = function()
    expect.equality({ projection().slice(new({ top = 180, bottom = 219 })) }, { 20, 60 })
    expect.equality({ projection().slice(new({ top = 0, bottom = 39 })) }, { 0, 40 })
    expect.equality({ projection().slice(new({ top = 360, bottom = 399 })) }, { 60, 40 })
    expect.equality({ projection().slice(new({ line_count = 40 })) }, { 0, 10 })
end

T["covers needs half a float height of margin away from the file ends"] = function()
    local p = new({ top = 180, bottom = 219 })

    expect.equality(projection().covers(p, 20, 60, true), true)
    expect.equality(projection().covers(p, 31, 60, true), false)
    expect.equality(projection().covers(p, 31, 60, false), true)
    expect.equality(projection().covers(p, 20, 49, true), false)
    expect.equality(projection().covers(p, 20, 40, false), true)

    local last = new({ top = 360, bottom = 399 })
    expect.equality(projection().covers(last, 60, 40, true), true)
    local first = new({ top = 0, bottom = 39 })
    expect.equality(projection().covers(first, 0, 30, true), true)
end

T["a drag moves the band with the pointer"] = function()
    for _, options in ipairs({
        { top = 100, bottom = 139 },
        { scale = 3, line_count = 2000, top = 600, bottom = 639 },
        { scale = "fit", line_count = 2000, top = 600, bottom = 639 },
        { line_count = 1000, top = 300, bottom = 339 },
    }) do
        local pressed = new(options)
        local pressed_band = projection().band(pressed)
        for _, delta in ipairs({ -3, -1, 1, 2, 5 }) do
            local topline = projection().drag_topline(pressed, pressed.top, delta)
            local dragged = new(vim.tbl_extend("force", options, {
                top = topline,
                bottom = topline + options.bottom - options.top,
            }))
            local band = projection().band(dragged)
            expect.equality(math.abs(band - (pressed_band + delta)) <= 1, true)
        end
    end
end

T["one drag can reach both ends of the buffer"] = function()
    for _, options in ipairs({
        { top = 100, bottom = 139 },
        { scale = 3, line_count = 2000, top = 600, bottom = 639 },
        { scale = "fit", line_count = 2000, top = 600, bottom = 639 },
    }) do
        local p = new(options)
        expect.equality(projection().drag_topline(p, p.top, p.rows), p.max_topline)
        expect.equality(projection().drag_topline(p, p.top, -p.rows), 0)
    end
end

T["a buffer shorter than the window has no scroll"] = function()
    local p = new({ line_count = 10, top = 0, bottom = 9 })

    expect.equality(p.offset, 0)
    expect.equality(p.max_topline, 0)
    expect.equality(projection().drag_topline(p, 0, 5), 0)
    expect.equality({ projection().band(p) }, { 1, 3 })
end

return T
