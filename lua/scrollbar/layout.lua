local M = {}

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

---@param position integer
---@param total_extent integer
---@param height integer
---@return integer
M.map_position = function(position, total_extent, height)
    if total_extent <= 1 or height <= 1 then
        return 0
    end

    local maximum_position = total_extent - 1
    local clamped_position = clamp(position, 0, maximum_position)
    if total_extent <= height then
        return clamped_position
    end
    return math.floor(clamped_position * (height - 1) / maximum_position)
end

---@param viewport_start integer
---@param viewport_end integer
---@param total_extent integer
---@param height integer
---@return ScrollbarVerticalHandleGeometry
M.handle_geometry = function(viewport_start, viewport_end, total_extent, height)
    if total_extent <= 1 or (viewport_start <= 0 and viewport_end >= total_extent - 1) then
        return { first_row = 0, last_row = math.max(0, height - 1) }
    end

    local first_row = M.map_position(viewport_start, total_extent, height)
    local last_row = M.map_position(math.max(viewport_start, viewport_end), total_extent, height)
    return { first_row = first_row, last_row = math.max(first_row, last_row) }
end

---@param input ScrollbarNormalizedMarkGeometryInput
---@return integer[]
M.normalized_mark_rows = function(input)
    local total_extent = math.max(0, input.line_count)
    local mark_rows = {}
    for index, mark in ipairs(input.marks) do
        mark_rows[index] = M.map_position(mark.line, total_extent, input.height)
    end
    return mark_rows
end

---@param input ScrollbarNormalizedGeometryInput
---@return ScrollbarGeometry
M.normalized = function(input)
    local total_extent = math.max(0, input.line_count)
    local maximum_position = math.max(0, total_extent - 1)
    local viewport_start = clamp(input.top_line, 0, maximum_position)
    local viewport_end = clamp(math.max(input.top_line, input.bottom_line), 0, maximum_position)
    local mark_rows = input.mark_rows
        or M.normalized_mark_rows({
            height = input.height,
            line_count = input.line_count,
            marks = input.marks,
        })

    return {
        total_extent = total_extent,
        viewport_start = viewport_start,
        viewport_end = viewport_end,
        mark_rows = mark_rows,
        handle = M.handle_geometry(viewport_start, viewport_end, total_extent, input.height),
    }
end

local function screen_prefix(source_win, line)
    return vim.api.nvim_win_text_height(source_win, { end_row = line, end_vcol = 0 }).all
end

local function wrapped_offset(source_win, line, skipcol)
    if skipcol <= 0 then
        return 0
    end

    return vim.api.nvim_win_text_height(source_win, {
        start_row = line,
        start_vcol = 0,
        end_row = line,
        end_vcol = skipcol,
    }).all
end

---@param input ScrollbarScreenGeometryInput
---@return ScrollbarGeometry
M.screen = function(input)
    local source_win = input.source_win
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local height = input.height
    local line_count = vim.api.nvim_buf_line_count(source_buf)
    local maximum_line = math.max(0, line_count - 1)
    local total_extent = vim.api.nvim_win_text_height(source_win, {}).all
    local view = vim.api.nvim_win_call(source_win, function()
        return vim.fn.winsaveview()
    end)
    local top_line = clamp(view.topline - 1, 0, maximum_line)
    local viewport_start = screen_prefix(source_win, top_line)
        - view.topfill
        + wrapped_offset(source_win, top_line, view.skipcol)
    viewport_start = clamp(viewport_start, 0, math.max(0, total_extent - 1))
    local viewport_end = clamp(viewport_start + height - 1, 0, math.max(0, total_extent - 1))

    local unique_lines = {}
    local seen_lines = {}
    for _, mark in ipairs(input.marks) do
        local line = clamp(mark.line, 0, maximum_line)
        if not seen_lines[line] then
            seen_lines[line] = true
            table.insert(unique_lines, line)
        end
    end
    table.sort(unique_lines)

    local prefixes = {}
    local previous_line = 0
    local prefix = 0
    for _, line in ipairs(unique_lines) do
        if line > previous_line then
            prefix = prefix
                + vim.api.nvim_win_text_height(source_win, {
                    start_row = previous_line,
                    start_vcol = 0,
                    end_row = line,
                    end_vcol = 0,
                }).all
        end
        prefixes[line] = prefix
        previous_line = line
    end

    local mark_rows = {}
    for index, mark in ipairs(input.marks) do
        local line = clamp(mark.line, 0, maximum_line)
        mark_rows[index] = M.map_position(prefixes[line], total_extent, height)
    end

    return {
        total_extent = total_extent,
        viewport_start = viewport_start,
        viewport_end = viewport_end,
        mark_rows = mark_rows,
        handle = M.handle_geometry(viewport_start, viewport_end, total_extent, height),
    }
end

---@param source_win integer
---@param row integer
---@param height integer
---@param mode ScrollbarGeometryMode
---@param total_extent integer
---@return integer
M.track_row_to_line = function(source_win, row, height, mode, total_extent)
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local line_count = vim.api.nvim_buf_line_count(source_buf)
    if line_count <= 1 or height <= 1 then
        return 0
    end

    local clamped_row = clamp(row, 0, height - 1)
    if mode == "line" then
        if line_count <= height then
            return math.min(clamped_row, line_count - 1)
        end
        return math.floor(clamped_row * (line_count - 1) / (height - 1) + 0.5)
    end

    local extent = math.max(1, total_extent)
    local target = extent <= height and math.min(clamped_row, extent - 1)
        or math.floor(clamped_row * (extent - 1) / (height - 1) + 0.5)
    local low = 0
    local high = line_count - 1
    local result = 0
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if screen_prefix(source_win, middle) <= target then
            result = middle
            low = middle + 1
        else
            high = middle - 1
        end
    end
    return result
end

local glyph_cache = {}

local function display_glyphs(text)
    local cached = glyph_cache[text]
    if cached ~= nil then
        return cached
    end

    local glyphs = {}
    local join_next = false
    local character_count = vim.fn.strchars(text)

    for index = 0, character_count - 1 do
        local character = vim.fn.strcharpart(text, index, 1)
        local width = vim.fn.strdisplaywidth(character)
        local codepoint = vim.fn.char2nr(character)
        local previous = glyphs[#glyphs]

        if previous and (width == 0 or join_next) then
            previous.text = previous.text .. character
            previous.width = vim.fn.strdisplaywidth(previous.text)
        else
            table.insert(glyphs, { text = character, width = width })
        end
        join_next = codepoint == 0x200D
    end

    glyph_cache[text] = glyphs
    return glyphs
end

local function source_less(left, right)
    local left_provider = left.provider or ""
    local right_provider = right.provider or ""
    if left_provider ~= right_provider then
        return left_provider < right_provider
    end
    if left.line ~= right.line then
        return left.line < right.line
    end
    return (left.text or "") < (right.text or "")
end

local function candidate_less(left, right)
    if left.priority ~= right.priority then
        return left.priority < right.priority
    end
    if left.type ~= right.type then
        return left.type < right.type
    end
    if left.provider ~= right.provider then
        return left.provider < right.provider
    end
    if left.line ~= right.line then
        return left.line < right.line
    end
    return left.column < right.column
end

local function resolved_text(mark_type, variants, source_text, count)
    if mark_type == "Mark" then
        if #variants == 0 then
            return source_text or ""
        end
        return variants[math.min(count, #variants)]
    end
    return source_text or variants[math.min(count, #variants)]
end

local function group_candidates(input, column_offset, expand_marks)
    local groups = {}
    local by_row = {}

    local function group_for(row, mark_type, mark_config)
        local column = mark_config.column + column_offset
        by_row[row] = by_row[row] or {}
        local by_type = by_row[row]
        by_type[mark_type] = by_type[mark_type] or {}
        local by_column = by_type[mark_type]
        local group = by_column[column]
        if not group then
            group = {
                row = row,
                type = mark_type,
                column = column,
                max_column = input.config.float.width + column_offset,
                priority = mark_config.priority,
                sources = {},
                lines = {},
                count = 0,
                ordinary_count = 0,
            }
            by_column[column] = group
            table.insert(groups, group)
        end
        return group
    end

    for index, mark in ipairs(input.marks) do
        local row = input.geometry.mark_rows[index]
        local mark_config = input.config.marks[mark.type]
        local expanded = expand_marks and mark.provider == "marks" and mark.type == "Mark"
        if not expanded and row and row >= 0 and row < input.height and mark_config then
            local group = group_for(row, mark.type, mark_config)
            table.insert(group.sources, mark)
            table.insert(group.lines, mark.line)
            group.count = group.count + 1
            group.ordinary_count = group.ordinary_count + 1
        end
    end

    local compact = input.compact_search
    local search_config = input.config.marks.Search
    if compact ~= nil and search_config ~= nil then
        local total_extent = math.max(0, input.line_count)
        local maximum_position = math.max(0, total_extent - 1)
        local maximum_row = math.max(0, input.height - 1)
        local compact_groups = {}
        for offset = 1, #compact.data, 4 do
            local first, second, third, fourth = compact.data:byte(offset, offset + 3)
            local line = first * 0x1000000 + second * 0x10000 + third * 0x100 + fourth
            local row
            if total_extent <= 1 or input.height <= 1 then
                row = 0
            elseif total_extent <= input.height then
                row = math.min(line, maximum_position)
            else
                row = math.floor(math.min(line, maximum_position) * maximum_row / maximum_position)
            end
            local group = compact_groups[row]
            if group == nil then
                group = group_for(row, "Search", search_config)
                group.compact_source = { provider = "search", line = line, type = "Search" }
                compact_groups[row] = group
            end
            group.count = group.count + 1
            group.lines[#group.lines + 1] = line
        end
    end

    for _, group in ipairs(groups) do
        if group.compact_source ~= nil then
            table.insert(group.sources, group.compact_source)
        end
        table.sort(group.sources, source_less)
        local variants = input.config.marks[group.type].text
        local representative = group.sources[1]
        group.provider = representative.provider or ""
        group.line = representative.line
        if group.ordinary_count > 0 or group.compact_source == nil then
            table.sort(group.lines)
        end
        group.text = resolved_text(group.type, variants, representative.text, group.count)
    end

    table.sort(groups, candidate_less)

    return groups
end

local function expanded_buckets(input, expand_marks)
    if not expand_marks then
        return {}
    end

    local buckets = {}
    for index, mark in ipairs(input.marks) do
        local row = input.geometry.mark_rows[index]
        if
            mark.provider == "marks"
            and mark.type == "Mark"
            and row
            and row >= 0
            and row < input.height
            and input.config.marks.Mark
        then
            buckets[row] = buckets[row] or {}
            table.insert(buckets[row], mark)
        end
    end

    for _, sources in pairs(buckets) do
        table.sort(sources, function(left, right)
            if left.line ~= right.line then
                return left.line < right.line
            end
            return (left.text or "") < (right.text or "")
        end)
    end
    return buckets
end

local function layer_dimensions(input, buckets, expand_marks)
    local base_width = input.config.float.width
    if not expand_marks then
        return base_width, 0
    end

    local mark_column = input.config.marks.Mark.column
    local east = input.config.float.placement.anchor:sub(2, 2) == "E"
    local demand = base_width
    for _, sources in pairs(buckets) do
        if east then
            demand = math.max(demand, base_width + math.max(0, #sources - mark_column))
        else
            demand = math.max(demand, mark_column + #sources - 1)
        end
    end

    local container_width = math.max(base_width, input.container_width or base_width)
    local maximum_width = math.max(base_width, math.min(input.config.providers.marks.max_width, container_width))
    local width = math.min(demand, maximum_width)
    return width, east and width - base_width or 0
end

local function add_expanded_candidates(input, candidates, buckets, width, column_offset)
    local mark_config = input.config.marks.Mark
    local east = input.config.float.placement.anchor:sub(2, 2) == "E"

    for row, sources in pairs(buckets) do
        local last_column = mark_config.column + column_offset
        local capacity = east and last_column or width - mark_config.column + 1
        local visible_count = math.min(#sources, math.max(0, capacity))
        local first_column = east and last_column - visible_count + 1 or mark_config.column

        for index = 1, visible_count do
            local source = sources[index]
            table.insert(candidates, {
                row = row,
                type = "Mark",
                column = first_column + index - 1,
                max_column = width,
                priority = mark_config.priority,
                provider = source.provider,
                line = source.line,
                lines = { source.line },
                text = resolved_text("Mark", mark_config.text, source.text, 1),
            })
        end
    end
end

local function place_marks(input, groups)
    local rows = {}
    for row = 0, input.height - 1 do
        rows[row] = {}
    end

    for _, group in ipairs(groups) do
        local column = group.column
        for _, glyph in ipairs(display_glyphs(group.text)) do
            local last_column = column + glyph.width - 1
            if glyph.width > 0 and last_column <= group.max_column then
                local available = true
                for cell = column, last_column do
                    if rows[group.row][cell] then
                        available = false
                        break
                    end
                end

                if available then
                    local placed = {
                        text = glyph.text,
                        width = glyph.width,
                        column = column,
                        last_column = last_column,
                        type = group.type,
                        provider = group.provider,
                        line = group.line,
                        lines = group.lines,
                    }
                    for cell = column, last_column do
                        rows[group.row][cell] = placed
                    end
                end
            elseif last_column > group.max_column then
                break
            end
            column = column + glyph.width
        end
    end

    return rows
end

local function resolve_mark_layer(input)
    local marks_config = input.config.providers.marks
    local expand_marks = marks_config ~= false and type(marks_config.max_width) == "number"
    local buckets = expanded_buckets(input, expand_marks)
    local width, column_offset = layer_dimensions(input, buckets, expand_marks)
    local candidates = group_candidates(input, column_offset, expand_marks)
    add_expanded_candidates(input, candidates, buckets, width, column_offset)
    table.sort(candidates, candidate_less)

    return {
        rows = place_marks(input, candidates),
        width = width,
        column_offset = column_offset,
    }
end

---@param input ScrollbarMarkLayerInput
---@return ScrollbarResolvedMarkLayer
M.mark_layer = function(input)
    return resolve_mark_layer(input)
end

local function handle_glyphs(config, column_offset)
    local glyphs = display_glyphs(config.handle.text)
    local placed = {}
    local column = config.handle.column + column_offset
    local last_column = column + config.handle.width - 1
    local index = 1

    while column <= last_column do
        local glyph = glyphs[index]
        local glyph_last_column = column + glyph.width - 1
        if glyph.width <= 0 or glyph_last_column > last_column then
            break
        end
        table.insert(placed, {
            text = glyph.text,
            width = glyph.width,
            column = column,
            last_column = glyph_last_column,
        })
        column = glyph_last_column + 1
        index = index % #glyphs + 1
    end

    return placed
end

local function add_span(spans, start_col, end_col, highlight)
    if not highlight then
        return
    end

    local previous = spans[#spans]
    if previous and previous.end_col == start_col and previous.highlight == highlight then
        previous.end_col = end_col
    else
        table.insert(spans, { start_col = start_col, end_col = end_col, highlight = highlight })
    end
end

local function render_row(input, row, marks, base_handle_glyphs, width, column_offset)
    local handle = input.geometry.handle
    local handle_first_column = input.config.handle.column + column_offset
    local handle_last_column = handle_first_column + input.config.handle.width - 1
    local in_handle_row = row >= handle.first_row and row <= handle.last_row
    local handle_starts = {}
    if in_handle_row then
        for _, glyph in ipairs(base_handle_glyphs) do
            local covered = false
            for column = glyph.column, glyph.last_column do
                if marks[column] then
                    covered = true
                    break
                end
            end
            if not covered then
                handle_starts[glyph.column] = glyph
            end
        end
    end

    local parts = {}
    local spans = {}
    local hit_cells = {}
    local byte_column = 0
    local column = 1

    while column <= width do
        local mark = marks[column]
        local handle_glyph = handle_starts[column]
        local text = " "
        local cell_width = 1
        local highlight

        if mark and mark.column == column then
            text = mark.text
            cell_width = mark.width
            local overlaps_handle = in_handle_row
                and mark.last_column >= handle_first_column
                and mark.column <= handle_last_column
            highlight = "Scrollbar" .. mark.type .. (overlaps_handle and "Handle" or "")
        elseif handle_glyph then
            text = handle_glyph.text
            cell_width = handle_glyph.width
            highlight = "ScrollbarHandle"
        elseif in_handle_row and column >= handle_first_column and column <= handle_last_column then
            highlight = "ScrollbarHandle"
        end

        table.insert(parts, text)
        local next_byte_column = byte_column + #text
        add_span(spans, byte_column, next_byte_column, highlight)

        for cell = column, column + cell_width - 1 do
            local owner = marks[cell]
            local is_handle = in_handle_row and cell >= handle_first_column and cell <= handle_last_column
            if owner then
                hit_cells[cell] = {
                    handle = is_handle,
                    provider = owner.provider,
                    type = owner.type,
                    line = owner.line,
                    lines = owner.lines,
                    start_col = owner.column,
                    end_col = owner.last_column,
                }
            else
                hit_cells[cell] = { handle = is_handle }
            end
        end

        byte_column = next_byte_column
        column = column + cell_width
    end

    return table.concat(parts), spans, hit_cells
end

---@param input ScrollbarLayoutInput
---@return ScrollbarLayoutOutput
M.compose = function(input)
    local mark_layer = input.mark_layer or resolve_mark_layer(input)
    local placed_marks = mark_layer.rows
    local width = mark_layer.width
    local column_offset = mark_layer.column_offset
    local base_handle_glyphs = handle_glyphs(input.config, column_offset)
    local rows = {}
    local highlights = {}
    local hitmap = {}

    for row = 0, input.height - 1 do
        rows[row + 1], highlights[row + 1], hitmap[row + 1] =
            render_row(input, row, placed_marks[row], base_handle_glyphs, width, column_offset)
    end

    return {
        rows = rows,
        width = width,
        highlights = highlights,
        hitmap = hitmap,
        handle = {
            first_row = input.geometry.handle.first_row,
            last_row = input.geometry.handle.last_row,
            column = input.config.handle.column + column_offset,
            width = input.config.handle.width,
        },
    }
end

M.clear_cache = function()
    glyph_cache = {}
end

return M
