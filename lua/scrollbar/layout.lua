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
    if left.lane_id ~= right.lane_id then
        return left.lane_id < right.lane_id
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

local function lane_for_type(config, mark_type)
    local lane_id = config.layout.routes[mark_type] or config.layout.catchall_lane
    if lane_id == false or lane_id == nil then
        return nil
    end
    return config.layout.lanes[lane_id]
end

local function translated_column(config, column, column_offset)
    return config.layout.inward == "left" and column + column_offset or column
end

local function group_candidates(input, column_offset, expanded_lane_id)
    local groups = {}
    local by_row = {}

    local function group_for(row, mark_type, mark_config, lane)
        by_row[row] = by_row[row] or {}
        local key = string.format("%d\0%s", lane.id, mark_type)
        local group = by_row[row][key]
        if group == nil then
            group = {
                row = row,
                lane_id = lane.id,
                type = mark_type,
                column = translated_column(input.config, lane.first_column, column_offset),
                max_column = translated_column(input.config, lane.last_column, column_offset),
                priority = mark_config.priority,
                sources = {},
                lines = {},
                count = 0,
                ordinary_count = 0,
            }
            by_row[row][key] = group
            table.insert(groups, group)
        end
        return group
    end

    for index, mark in ipairs(input.marks) do
        local row = input.geometry.mark_rows[index]
        local mark_config = input.config.marks[mark.type]
        local lane = mark_config and lane_for_type(input.config, mark.type)
        local expanded = lane ~= nil
            and lane.id == expanded_lane_id
            and mark.provider == "marks"
            and mark.type == "Mark"
        if not expanded and row and row >= 0 and row < input.height and mark_config and lane then
            local group = group_for(row, mark.type, mark_config, lane)
            table.insert(group.sources, mark)
            table.insert(group.lines, mark.line)
            group.count = group.count + 1
            group.ordinary_count = group.ordinary_count + 1
        end
    end

    local compact = input.compact_search
    local search_config = input.config.marks.Search
    local search_lane = search_config and lane_for_type(input.config, "Search")
    if compact ~= nil and search_config ~= nil and search_lane ~= nil then
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
                group = group_for(row, "Search", search_config, search_lane)
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

local function expanded_buckets(input)
    local lane = lane_for_type(input.config, "Mark")
    if lane == nil or type(lane.max_width) ~= "number" then
        return {}, nil
    end

    local buckets = {}
    for index, mark in ipairs(input.marks) do
        local row = input.geometry.mark_rows[index]
        if mark.provider == "marks" and mark.type == "Mark" and row and row >= 0 and row < input.height then
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
    return buckets, lane
end

local function layer_dimensions(input, buckets, lane)
    local base_width = input.config.layout.width
    if lane == nil then
        return base_width, 0
    end

    local demand = #lane.columns
    for _, sources in pairs(buckets) do
        demand = math.max(demand, #sources)
    end
    local lane_growth = math.min(demand, lane.max_width) - #lane.columns
    local container_width = math.max(base_width, input.container_width or base_width)
    local growth = math.max(0, math.min(lane_growth, container_width - base_width))
    local width = base_width + growth
    local column_offset = input.config.layout.inward == "left" and growth or 0
    return width, column_offset
end

local function add_expanded_candidates(input, candidates, buckets, lane, width, column_offset)
    if lane == nil then
        return
    end

    local available = {}
    local growth = width - input.config.layout.width
    if input.config.layout.inward == "left" then
        for column = 1, growth do
            available[#available + 1] = column
        end
    end
    for _, column in ipairs(lane.columns) do
        available[#available + 1] = translated_column(input.config, column, column_offset)
    end
    if input.config.layout.inward == "right" then
        for column = input.config.layout.width + 1, width do
            available[#available + 1] = column
        end
    end
    table.sort(available)

    local mark_config = input.config.marks.Mark
    for row, sources in pairs(buckets) do
        local visible_count = math.min(#sources, #available)
        for index = 1, visible_count do
            local source = sources[index]
            candidates[#candidates + 1] = {
                row = row,
                lane_id = lane.id,
                type = "Mark",
                column = available[index],
                max_column = width,
                priority = mark_config.priority,
                provider = source.provider,
                line = source.line,
                lines = { source.line },
                text = resolved_text("Mark", mark_config.text, source.text, 1),
            }
        end
    end
end

local function place_marks(input, groups)
    local rows = {}
    for row = 0, input.height - 1 do
        rows[row] = {}
    end

    for _, group in ipairs(groups) do
        rows[group.row][group.lane_id] = rows[group.row][group.lane_id] or {}
        local cells = rows[group.row][group.lane_id]
        local column = group.column
        for _, glyph in ipairs(display_glyphs(group.text)) do
            local last_column = column + glyph.width - 1
            if glyph.width > 0 and last_column <= group.max_column then
                local available = true
                for cell = column, last_column do
                    if cells[cell] then
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
                        lane_id = group.lane_id,
                        type = group.type,
                        provider = group.provider,
                        line = group.line,
                        lines = group.lines,
                    }
                    for cell = column, last_column do
                        cells[cell] = placed
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
    local buckets, expanded_lane = expanded_buckets(input)
    local width, column_offset = layer_dimensions(input, buckets, expanded_lane)
    local candidates = group_candidates(input, column_offset, expanded_lane and expanded_lane.id or nil)
    add_expanded_candidates(input, candidates, buckets, expanded_lane, width, column_offset)
    table.sort(candidates, candidate_less)
    return {
        rows = place_marks(input, candidates),
        width = width,
        column_offset = column_offset,
        expanded_lane_id = expanded_lane and expanded_lane.id or false,
    }
end

---@param input ScrollbarMarkLayerInput
---@return ScrollbarResolvedMarkLayer
M.mark_layer = function(input)
    return resolve_mark_layer(input)
end

local function base_column_at(config, column, column_offset)
    if config.layout.inward == "left" then
        local base_column = column - column_offset
        return base_column >= 1 and base_column <= config.layout.width and base_column or nil
    end
    return column <= config.layout.width and column or nil
end

local function layers_at(config, column, column_offset, expanded_lane_id)
    local base_column = base_column_at(config, column, column_offset)
    if base_column ~= nil then
        return config.layout.columns[base_column]
    end
    if expanded_lane_id ~= false then
        return { { kind = "marks", lane_id = expanded_lane_id, priority = 1 } }
    end
    return {}
end

local function layer_priority(config, column, column_offset, expanded_lane_id, kind, lane_id)
    for _, layer in ipairs(layers_at(config, column, column_offset, expanded_lane_id)) do
        if layer.kind == kind and (kind ~= "marks" or layer.lane_id == lane_id) then
            return layer.priority
        end
    end
    return nil
end

local function visual_layer_signature(config, column, column_offset, expanded_lane_id, in_thumb_row, lane_id)
    local parts = {}
    for _, layer in ipairs(layers_at(config, column, column_offset, expanded_lane_id)) do
        if layer.kind == "track" then
            parts[#parts + 1] = "track:" .. layer.priority
        elseif layer.kind == "thumb" and in_thumb_row then
            parts[#parts + 1] = "thumb:" .. layer.priority
        elseif layer.kind == "marks" and lane_id ~= nil and layer.lane_id == lane_id then
            parts[#parts + 1] = "marks:" .. layer.priority
        end
    end
    return table.concat(parts, "|")
end

local function collect_row_marks(config, marks, width, column_offset, expanded_lane_id, in_thumb_row)
    local placed = {}
    for _, cells in pairs(marks) do
        for column, mark in pairs(cells) do
            if mark.column == column then
                local minimum_priority = math.huge
                for cell = mark.column, mark.last_column do
                    local priority =
                        layer_priority(config, cell, column_offset, expanded_lane_id, "marks", mark.lane_id)
                    minimum_priority = math.min(minimum_priority, priority or -math.huge)
                end
                mark.stack_priority = minimum_priority
                placed[#placed + 1] = mark
            end
        end
    end
    table.sort(placed, function(left, right)
        if left.stack_priority ~= right.stack_priority then
            return left.stack_priority > right.stack_priority
        end
        if left.lane_id ~= right.lane_id then
            return left.lane_id > right.lane_id
        end
        return candidate_less(left, right)
    end)

    local reservations = {}
    if in_thumb_row then
        for column = 1, width do
            local priority = layer_priority(config, column, column_offset, expanded_lane_id, "thumb")
            if priority ~= nil then
                reservations[column] = priority
            end
        end
    end

    local winners = {}
    for _, mark in ipairs(placed) do
        local visible = true
        local signature =
            visual_layer_signature(config, mark.column, column_offset, expanded_lane_id, in_thumb_row, mark.lane_id)
        for cell = mark.column, mark.last_column do
            local priority = layer_priority(config, cell, column_offset, expanded_lane_id, "marks", mark.lane_id)
            if
                priority == nil
                or visual_layer_signature(config, cell, column_offset, expanded_lane_id, in_thumb_row, mark.lane_id) ~= signature
                or (reservations[cell] ~= nil and reservations[cell] >= priority)
            then
                visible = false
                break
            end
        end
        if visible then
            for cell = mark.column, mark.last_column do
                winners[cell] = mark
                reservations[cell] =
                    layer_priority(config, cell, column_offset, expanded_lane_id, "marks", mark.lane_id)
            end
        end
    end
    return winners
end

local function thumb_glyphs(config, column_offset, winners, in_thumb_row)
    local span = config.layout.thumb
    if not in_thumb_row or span == false then
        return {}
    end

    local glyphs = display_glyphs(config.thumb.text)
    local first_column = translated_column(config, span.first_column, column_offset)
    local last_column = translated_column(config, span.last_column, column_offset)
    local placed = {}
    local column = first_column
    local index = 1
    while column <= last_column do
        local glyph = glyphs[index]
        local glyph_last_column = column + glyph.width - 1
        if glyph.width <= 0 or glyph_last_column > last_column then
            break
        end
        local covered = false
        local signature = visual_layer_signature(config, column, column_offset, false, true, nil)
        for cell = column, glyph_last_column do
            covered = covered
                or winners[cell] ~= nil
                or visual_layer_signature(config, cell, column_offset, false, true, nil) ~= signature
        end
        if not covered then
            placed[column] = {
                text = glyph.text,
                width = glyph.width,
                column = column,
                last_column = glyph_last_column,
            }
        end
        column = glyph_last_column + 1
        index = index % #glyphs + 1
    end
    return placed
end

local function add_span(spans, start_col, end_col, highlight, priority)
    local previous = spans[#spans]
    if
        previous
        and previous.end_col == start_col
        and previous.highlight == highlight
        and previous.priority == priority
    then
        previous.end_col = end_col
    else
        spans[#spans + 1] = {
            start_col = start_col,
            end_col = end_col,
            highlight = highlight,
            priority = priority,
        }
    end
end

local function mark_highlight(config, column, column_offset, expanded_lane_id, mark, in_thumb_row)
    local groups = config.highlights.marks[mark.type]
    if not in_thumb_row then
        return groups.mark
    end

    local mark_priority = layer_priority(config, column, column_offset, expanded_lane_id, "marks", mark.lane_id)
    local background_kind
    local background_priority = -math.huge
    for _, layer in ipairs(layers_at(config, column, column_offset, expanded_lane_id)) do
        if layer.priority < mark_priority and (layer.kind == "track" or layer.kind == "thumb") then
            if layer.priority > background_priority then
                background_kind = layer.kind
                background_priority = layer.priority
            end
        end
    end
    return background_kind == "thumb" and groups.thumb or groups.mark
end

local function render_row(input, row, marks, width, column_offset, expanded_lane_id)
    local in_thumb_row = input.config.layout.thumb ~= false
        and row >= input.geometry.handle.first_row
        and row <= input.geometry.handle.last_row
    local winners = collect_row_marks(input.config, marks, width, column_offset, expanded_lane_id, in_thumb_row)
    local thumb_starts = thumb_glyphs(input.config, column_offset, winners, in_thumb_row)
    local parts = {}
    local spans = {}
    local hit_cells = {}
    local byte_column = 0
    local column = 1

    while column <= width do
        local mark = winners[column]
        local thumb = thumb_starts[column]
        local text = " "
        local cell_width = 1
        if mark and mark.column == column then
            text = mark.text
            cell_width = mark.width
        elseif thumb then
            text = thumb.text
            cell_width = thumb.width
        end

        parts[#parts + 1] = text
        local next_byte_column = byte_column + #text
        local layers = layers_at(input.config, column, column_offset, expanded_lane_id)
        for _, layer in ipairs(layers) do
            if layer.kind == "track" then
                add_span(spans, byte_column, next_byte_column, input.config.highlights.track, layer.priority)
            elseif layer.kind == "thumb" and in_thumb_row then
                add_span(spans, byte_column, next_byte_column, input.config.highlights.thumb, layer.priority)
            elseif
                layer.kind == "marks"
                and mark ~= nil
                and mark.column == column
                and layer.lane_id == mark.lane_id
            then
                add_span(
                    spans,
                    byte_column,
                    next_byte_column,
                    mark_highlight(input.config, column, column_offset, expanded_lane_id, mark, in_thumb_row),
                    layer.priority
                )
            end
        end

        for cell = column, column + cell_width - 1 do
            local owner = winners[cell]
            local track = layer_priority(input.config, cell, column_offset, expanded_lane_id, "track") ~= nil
            local thumb_member = in_thumb_row
                and layer_priority(input.config, cell, column_offset, expanded_lane_id, "thumb") ~= nil
            if owner then
                hit_cells[cell] = {
                    track = track,
                    thumb = thumb_member,
                    provider = owner.provider,
                    type = owner.type,
                    line = owner.line,
                    lines = owner.lines,
                    start_col = owner.column,
                    end_col = owner.last_column,
                }
            else
                hit_cells[cell] = { track = track, thumb = thumb_member }
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
    local rows = {}
    local highlights = {}
    local hitmap = {}
    for row = 0, input.height - 1 do
        rows[row + 1], highlights[row + 1], hitmap[row + 1] = render_row(
            input,
            row,
            mark_layer.rows[row],
            mark_layer.width,
            mark_layer.column_offset,
            mark_layer.expanded_lane_id
        )
    end

    ---@type false|ScrollbarHandleGeometry
    local handle = false
    if input.config.layout.thumb ~= false then
        handle = {
            first_row = input.geometry.handle.first_row,
            last_row = input.geometry.handle.last_row,
            column = translated_column(input.config, input.config.layout.thumb.first_column, mark_layer.column_offset),
            width = input.config.layout.thumb.width,
        }
    end
    return {
        rows = rows,
        width = mark_layer.width,
        highlights = highlights,
        hitmap = hitmap,
        handle = handle,
    }
end

M.clear_cache = function()
    glyph_cache = {}
end

return M
