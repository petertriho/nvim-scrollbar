local M = {}

local store = require("scrollbar.store")
local search_compact = require("scrollbar.providers.search_compact")

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
-- Smallest line value whose display row is >= r under (extent, height);
-- math.huge when unreachable. Row bands are contiguous line ranges, so a
-- mark can only change rows when it lies in the symmetric difference of the
-- old and new band edges — narrow bands around moved boundaries.
local function row_threshold(r, extent, height)
    if extent <= 1 then
        return math.huge
    end
    local maximum = extent - 1
    if extent <= height then
        return r <= maximum and r or math.huge
    end
    local threshold = math.ceil(r * maximum / (height - 1))
    if threshold > maximum then
        return math.huge
    end
    return threshold
end

M.normalized_mark_rows = function(input)
    local total_extent = math.max(0, input.line_count)
    local marks = input.marks
    local count = #marks
    local height = input.height
    -- In-place fast path: when the caller still holds the rows array built for
    -- this exact marks table (identity) at the same height, row values only
    -- shift where a mark crosses a boundary after an extent change — a
    -- handful of entries at realistic densities. With provider segments
    -- (line-sorted index ranges) the shifted marks are located analytically:
    -- only marks inside the symmetric difference of the old and new band
    -- edges can change rows, so each band is binary-searched per segment
    -- instead of rescanning every mark. Without segments, recompute all rows
    -- but store only the diffs.
    local previous = input.previous
    if previous ~= nil and type(previous.rows) == "table" and #previous.rows == count then
        local mark_rows = previous.rows
        local changed = {}
        local segments = previous.segments
        local old_extent = previous.line_count
        if
            segments ~= nil
            and type(old_extent) == "number"
            and old_extent >= 0
            and old_extent ~= total_extent
            and height > 1
            and count > 0
            and (previous.height == nil or previous.height == height)
        then
            local bands = {}
            for r = 1, height - 1 do
                local old_edge = row_threshold(r, old_extent, height)
                local new_edge = row_threshold(r, total_extent, height)
                if old_edge ~= new_edge then
                    local lo = math.min(old_edge, new_edge)
                    local hi = math.max(old_edge, new_edge)
                    local merged = false
                    for _, band in ipairs(bands) do
                        if lo <= band[2] and band[1] <= hi then
                            band[1] = math.min(band[1], lo)
                            band[2] = math.max(band[2], hi)
                            merged = true
                            break
                        end
                    end
                    if not merged then
                        bands[#bands + 1] = { lo, hi }
                    end
                end
            end
            -- Merge to a fixpoint: extending a band can make it overlap a later one.
            local dirty = true
            while dirty and #bands > 1 do
                dirty = false
                local kept = { bands[1] }
                for index = 2, #bands do
                    local band = bands[index]
                    local target = kept[#kept]
                    if band[1] <= target[2] then
                        target[2] = math.max(target[2], band[2])
                        dirty = true
                    else
                        kept[#kept + 1] = band
                    end
                end
                bands = kept
            end
            for _, segment in ipairs(segments) do
                local lo_index, hi_index = segment[1], segment[2]
                for _, band in ipairs(bands) do
                    -- First index with line >= band[1].
                    local low, high = lo_index, hi_index + 1
                    while low < high do
                        local mid = math.floor((low + high) / 2)
                        if marks[mid].line < band[1] then
                            low = mid + 1
                        else
                            high = mid
                        end
                    end
                    local first = low
                    -- Last+1 index with line < band[2].
                    low, high = first, hi_index + 1
                    while low < high do
                        local mid = math.floor((low + high) / 2)
                        if marks[mid].line < band[2] then
                            low = mid + 1
                        else
                            high = mid
                        end
                    end
                    for index = first, low - 1 do
                        local row = M.map_position(marks[index].line, total_extent, height)
                        if mark_rows[index] ~= row then
                            changed[#changed + 1] = { index, mark_rows[index] }
                            mark_rows[index] = row
                        end
                    end
                end
            end
            return mark_rows, changed
        end
        for index = 1, count do
            local row = M.map_position(marks[index].line, total_extent, height)
            if mark_rows[index] ~= row then
                changed[#changed + 1] = { index, mark_rows[index] }
                mark_rows[index] = row
            end
        end
        return mark_rows, changed
    end
    local mark_rows = {}
    for index = 1, count do
        mark_rows[index] = M.map_position(marks[index].line, total_extent, height)
    end
    return mark_rows, nil
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

-- Options that can change the mapping from buffer lines to display rows
-- (wrapping, folds, width-affecting settings, diff folds). Horizontal-only
-- options (number, signcolumn, winbar, statusline, ...) are deliberately
-- excluded: they cannot change vertical extents or prefixes. The scheduler's
-- `OPTION_PATTERNS` remains a superset used for OptionSet autocmd patterns.
local EXTENT_OPTION_PATTERNS = {
    "ambiwidth",
    "breakindent",
    "conceallevel",
    "diff",
    "display",
    "foldenable",
    "foldexpr",
    "foldignore",
    "foldlevel",
    "foldmarker",
    "foldmethod",
    "foldminlines",
    "foldnestmax",
    "linebreak",
    "list",
    "listchars",
    "showbreak",
    "tabstop",
    "wrap",
}

-- Capture each option's scope at module load so the digest can fetch the
-- effective value for the correct scope (win/buf/global/tab).
local EXTENT_OPTION_SCOPES = {}
for _, name in ipairs(EXTENT_OPTION_PATTERNS) do
    local ok, info = pcall(vim.api.nvim_get_option_info2, name, {})
    if ok and info then
        EXTENT_OPTION_SCOPES[name] = info.scope
    end
end

local uv = vim.uv or vim.loop

-- Fold commands (za/zM/zR/...) fire no autocmd, so fold state can change
-- silently. Uniform extent layers are re-verified against the full buffer at
-- most this often; uniformity additionally lets text edits update the extent
-- by arithmetic (line_count) with no scan. Non-uniform windows verify on every
-- render. Exposed on the module so tests and users can tighten or disable the
-- window (0 verifies on every screen pass, matching the historical behavior).
local EXTENT_VERIFY_INTERVAL_MS = 250

-- Sorted anchor lines with known display prefixes. Prefix values are absolute
-- (rows before the line), and the array is retained with spread-preserving
-- halving, so dropping anchors keeps every remaining value sound and nearby.
local ANCHOR_LIMIT = 512

-- Per-source-window extent layer: everything that depends only on the buffer
-- text (changedtick), extent-affecting options, and the window width. Viewport
-- state (topline/topfill/skipcol) deliberately does NOT invalidate it, so
-- scrolling reuses prefixes. `generation` bumps whenever the prefix-visible
-- state changes, gating the mark-row cache in `M.screen`.
local screen_extent_cache = {}

-- Per-source-window cache of `M.screen` mark rows, keyed by mark revisions,
-- track height, and the extent layer generation.
local screen_marks_cache = {}

-- Option-digest cache: recomputing the digest reads ~20 options per render
-- (~7-8µs) just to prove nothing changed. Cached per window and refreshed at
-- most every DIGEST_INTERVAL_MS; wired setups clear it immediately on
-- OptionSet via `invalidate_screen_options`. Tests can tighten the interval
-- via `screen_extent_digest_interval_ms`.
local DIGEST_INTERVAL_MS = 50
local digest_cache = {}

local function extent_option_digest(source_win)
    local now = uv.now()
    local cached = digest_cache[source_win]
    if cached ~= nil and now - cached.at < (M.screen_extent_digest_interval_ms or DIGEST_INTERVAL_MS) then
        return cached.digest
    end
    local parts = {}
    for index, name in ipairs(EXTENT_OPTION_PATTERNS) do
        local scope = EXTENT_OPTION_SCOPES[name]
        local ok, value
        if scope == "win" then
            ok, value = pcall(vim.api.nvim_get_option_value, name, { win = source_win })
        elseif scope == "buf" then
            local source_buf = vim.api.nvim_win_get_buf(source_win)
            ok, value = pcall(vim.api.nvim_get_option_value, name, { buf = source_buf })
        else
            ok, value = pcall(vim.api.nvim_get_option_value, name, {})
        end
        if not ok then
            value = "<error>"
        end
        parts[index] = name .. "\0" .. tostring(value)
    end
    local digest = table.concat(parts, "\1")
    digest_cache[source_win] = { digest = digest, at = now }
    return digest
end

---Clear cached option digests (all windows, or one). Wired to OptionSet by
---the scheduler; safe to call at any time.
---@param source_win? integer
M.invalidate_screen_options = function(source_win)
    if source_win == nil then
        digest_cache = {}
    else
        digest_cache[source_win] = nil
    end
end

local function full_extent(source_win)
    return vim.api.nvim_win_text_height(source_win, {}).all
end

local function reset_prefixes(layer)
    layer.anchors = { 0 }
    layer.wrapped_memo = nil
    if layer.chunks ~= nil then
        for _, chunk in ipairs(layer.chunks) do
            chunk.memo = {}
        end
    end
    layer.prefix_count = 0
end

---@return table winsaveview for the source window
local function win_view(source_win)
    return vim.api.nvim_win_call(source_win, function()
        return vim.fn.winsaveview()
    end)
end

local function screen_range(source_win, start_line, end_line)
    return vim.api.nvim_win_text_height(source_win, {
        start_row = start_line,
        start_vcol = 0,
        end_row = end_line,
        end_vcol = 0,
    }).all
end

--- Display rows of the half-open range [start_line, end_line). Unlike
--- `screen_range`, `end_line` may equal `line_count`: nvim rejects end_row at
--- or beyond the buffer, so the final line is measured on its own.
local function rows_between(source_win, start_line, end_line, line_count)
    if end_line <= start_line or line_count <= start_line then
        return 0
    end
    local last = math.min(end_line, line_count)
    if last < line_count then
        return screen_range(source_win, start_line, last)
    end
    local rows = 0
    if line_count - 1 > start_line then
        rows = screen_range(source_win, start_line, line_count - 1)
    end
    return rows + vim.api.nvim_win_text_height(source_win, { start_row = line_count - 1, start_vcol = 0 }).all
end

-- Display rows before `line` (0-based). Uniform layers short-circuit to the
-- identity mapping. Otherwise the nearest cached anchor at or below the line
-- is extended with one bounded range measurement, and the new line becomes an
-- anchor itself so consecutive queries walk forward incrementally.
-- Memo entries live per chunk, keyed relative to the chunk start: shifting a
-- chunk (or re-basing everything after an edit) never rewrites entries, so
-- maintenance stays O(#chunks + #anchors) instead of O(#memo).
local PREFIX_MAP_LIMIT = 32768

---Binary search for the chunk containing `line` (last chunk with start <= line).
---@return integer index 0 when line precedes the first chunk
local function chunk_index_for(layer, line)
    local chunks = layer.chunks
    local low, high, index = 1, #chunks, 0
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if chunks[middle].start <= line then
            index = middle
            low = middle + 1
        else
            high = middle - 1
        end
    end
    return index
end

local function anchor_prefix(layer, anchor)
    if anchor == 0 then
        return 0
    end
    local chunks = layer.chunks
    local index = chunk_index_for(layer, anchor)
    local chunk = chunks[index]
    local relative = chunk.memo[anchor - chunk.start]
    if relative == nil then
        -- Anchors always carry a memo entry; rebuild conservatively when an
        -- invariant slip leaves one behind.
        return nil
    end
    return chunk.base + relative
end

local function halve_anchors(layer)
    local anchors = layer.anchors
    local compact = {}
    for index = 1, #anchors, 2 do
        compact[#compact + 1] = anchors[index]
    end
    layer.anchors = compact
end

---Bound total memo memory: clear every second chunk's memo (spread-preserving).
local function evict_memo(layer)
    local chunks = layer.chunks
    local kept_anchors = {}
    for index = 1, #chunks do
        local chunk = chunks[index]
        if index % 2 == 0 and next(chunk.memo) ~= nil then
            chunk.memo = {}
        end
    end
    for _, anchor in ipairs(layer.anchors) do
        local index = chunk_index_for(layer, anchor)
        if index == 0 or chunks[index].memo[anchor - chunks[index].start] ~= nil then
            kept_anchors[#kept_anchors + 1] = anchor
        end
    end
    layer.anchors = kept_anchors
    layer.prefix_count = 0
    for _, chunk in ipairs(chunks) do
        local count = 0
        for _ in pairs(chunk.memo) do
            count = count + 1
        end
        layer.prefix_count = layer.prefix_count + count
    end
end

local function prefix_for(source_win, line, layer)
    if layer.uniform then
        return line
    end
    local chunks = layer.chunks
    local index = chunk_index_for(layer, line)
    local chunk = chunks[index]
    if chunk == nil then
        return 0
    end
    local relative = line - chunk.start
    local cached = chunk.memo[relative]
    if cached ~= nil then
        return chunk.base + cached
    end

    local anchors = layer.anchors
    local low, high = 1, #anchors
    local position = 1
    local anchor = 0
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if anchors[middle] <= line then
            anchor = anchors[middle]
            position = middle + 1
            low = middle + 1
        else
            high = middle - 1
        end
    end

    local prefix = anchor_prefix(layer, anchor)
    if prefix == nil then
        prefix = 0
        anchor = 0
    end
    if anchor < line then
        prefix = prefix + screen_range(source_win, anchor, line)
    end
    chunk.memo[relative] = prefix - chunk.base
    layer.prefix_count = layer.prefix_count + 1
    table.insert(anchors, position, line)
    if #anchors > ANCHOR_LIMIT then
        -- Drop every second anchor instead of the oldest ones: keeping the
        -- spread preserves nearby anchors for every region of the buffer.
        halve_anchors(layer)
    end
    if layer.prefix_count > PREFIX_MAP_LIMIT then
        evict_memo(layer)
    end
    return prefix
end

local function wrapped_offset(source_win, line, skipcol, layer)
    if skipcol <= 0 then
        return 0
    end
    local memo = layer.wrapped_memo
    if memo ~= nil and memo.line == line and memo.skipcol == skipcol then
        return memo.offset
    end
    local offset = vim.api.nvim_win_text_height(source_win, {
        start_row = line,
        start_vcol = 0,
        end_row = line,
        end_vcol = skipcol,
    }).all
    layer.wrapped_memo = { line = line, skipcol = skipcol, offset = offset }
    return offset
end

-- Per-buffer record of recent text edits, captured through nvim_buf_attach
-- so extent maintenance can measure only the edited spans instead of the
-- whole buffer. Each edit is { first, last_old, updated, tick } in 0-based
-- rows. `overflow_tick` marks points where older edits were dropped; layers
-- whose changedtick predates it must fall back to a full verify.
local buffer_edits = {}

local BUFFER_EDIT_HISTORY = 8

local function attach_buffer_edits(source_buf)
    if buffer_edits[source_buf] ~= nil then
        return
    end
    local state = { edits = {}, overflow_tick = 0 }
    local ok = pcall(vim.api.nvim_buf_attach, source_buf, false, {
        on_lines = function(_, buf, tick, first, last, updated)
            local tracked = buffer_edits[buf]
            if tracked == nil then
                return true
            end
            if #tracked.edits >= BUFFER_EDIT_HISTORY then
                -- Roll the oldest edit out instead of clearing the history:
                -- overflow_tick becomes the tick of the newest DROPPED edit, so
                -- consumers asking for edits after any surviving tick still
                -- get a complete answer and never fall back to a full verify.
                local dropped = table.remove(tracked.edits, 1)
                tracked.overflow_tick = dropped[4]
            end
            local edits = tracked.edits
            edits[#edits + 1] = { first, last, updated, tick }
        end,
        on_detach = function(_, buf)
            buffer_edits[buf] = nil
        end,
    })
    if ok then
        buffer_edits[source_buf] = state
    end
end

local function edits_list_since(source_buf, since_tick)
    local state = buffer_edits[source_buf]
    if state == nil or (state.overflow_tick or 0) > since_tick then
        return nil
    end
    local list = {}
    for _, edit in ipairs(state.edits) do
        if edit[4] > since_tick then
            list[#list + 1] = edit
        end
    end
    if #list == 0 then
        return nil
    end
    return list
end

-- Union of the edits recorded after `since_tick`, as sorted disjoint
-- { first, updated } spans in current-buffer coordinates. Returns nil when
-- history for the range is unavailable.
local function edits_since(source_buf, since_tick)
    local state = buffer_edits[source_buf]
    if state == nil or (state.overflow_tick or 0) > since_tick then
        return nil
    end
    local spans = {}
    for _, edit in ipairs(state.edits) do
        if edit[4] > since_tick then
            spans[#spans + 1] = { edit[1], edit[3] }
        end
    end
    if #spans == 0 then
        return nil
    end
    table.sort(spans, function(left, right)
        return left[1] < right[1]
    end)
    local merged = { spans[1] }
    for index = 2, #spans do
        local span = spans[index]
        local previous = merged[#merged]
        if span[1] <= previous[2] then
            if span[2] > previous[2] then
                previous[2] = span[2]
            end
        else
            merged[#merged + 1] = span
        end
    end
    return merged
end

-- A uniform layer stays uniform through an edit set when every edited span
-- still renders to exactly one row per line (measured on the current text).
-- Manual folds cannot be created by text, so unedited lines keep their height;
-- wrap-affecting edits are confined to the edited spans.
local function uniform_after_edits(source_win, spans, line_count)
    for _, span in ipairs(spans) do
        local first = math.max(0, span[1])
        local updated = math.min(span[2], line_count)
        if updated > first and rows_between(source_win, first, updated, line_count) ~= (updated - first) then
            return false
        end
    end
    return true
end

--- Non-uniform extent maintenance through a chunk table. Chunks tile the
--- buffer as { start, height } entries; the total extent is their sum. Text
--- edits recorded through `nvim_buf_attach` re-measure only the chunks they
--- overlap (bounded by edit size), and silent fold changes are caught by
--- re-measuring a few chunks per render (round-robin) instead of rescanning
--- the whole buffer every pass.
local CHUNK_LINES = 512
-- Sub-span granularity for line-count-preserving edits: only the edited
-- 64-line span's height can change (per-line rendering is independent), so
-- a keystroke re-measures 64 lines instead of the whole 512-line chunk.
local CHUNK_SUB_LINES = 64
local CHUNK_SWEEP_PER_RENDER = 6
-- Minimum wall-clock spacing between chunk sweeps. Silent fold changes are
-- rare; re-measuring chunks on EVERY render (scroll bursts, steady
-- re-renders) spends the sweep budget on renders that cannot have observed a
-- change. Tests can tighten it via `screen_extent_sweep_interval_ms`.
local SWEEP_INTERVAL_MS = 50

--- Cost ceiling for one render's fold sweep. A 512-line chunk measurement is
--- ~45-60µs on this code path; exceeding the budget defers the remaining
--- chunks to the next render (the round-robin cursor already advances only
--- over measured chunks, so coverage continues where it left off).
local CHUNK_SWEEP_BUDGET_NS = 120 * 1000

-- Measure a chunk as fixed sub-spans: constructors capture PRE-edit
-- heights, and the edit fast path never builds them — it falls back to a
-- wholesale rebuild when subs are missing.
local function measure_chunk(source_win, at, stop, current_count, base)
    local subs = {}
    local height = 0
    local sub_at = at
    local index = 1
    while sub_at < stop do
        local sub_stop = math.min(sub_at + CHUNK_SUB_LINES, stop)
        local sub_height = rows_between(source_win, sub_at, sub_stop, current_count)
        subs[index] = sub_height
        height = height + sub_height
        sub_at = sub_stop
        index = index + 1
    end
    return { start = at, height = height, base = base, memo = {}, subs = subs }
end

local function build_chunks(source_win, layer)
    local chunks = {}
    local total = 0
    local at = 0
    local line_count = layer.line_count
    while at < line_count do
        local stop = math.min(at + CHUNK_LINES, line_count)
        local chunk = measure_chunk(source_win, at, stop, line_count, total)
        chunks[#chunks + 1] = chunk
        total = total + chunk.height
        at = stop
    end
    layer.chunks = chunks
    layer.chunk_cursor = 1
    layer.verified_at = uv.now()
    if total ~= layer.total_extent then
        layer.total_extent = total
        layer.generation = layer.generation + 1
        reset_prefixes(layer)
    end
end

local function verify_extent(source_win, layer)
    local extent = full_extent(source_win)
    layer.verified_at = uv.now()
    local uniform = extent == layer.line_count
    if extent ~= layer.total_extent or uniform ~= layer.uniform or (not uniform and layer.chunks == nil) then
        layer.total_extent = extent
        layer.uniform = uniform
        layer.generation = layer.generation + 1
        reset_prefixes(layer)
        if uniform then
            layer.chunks = nil
            layer.chunk_cursor = 1
        else
            -- Non-uniform layers get their chunk table immediately so later
            -- renders sweep a bounded number of chunks instead of rescanning.
            build_chunks(source_win, layer)
        end
    end
end

local function sweep_chunks(source_win, layer)
    local chunks = layer.chunks
    if chunks == nil or #chunks == 0 then
        return
    end
    if #chunks == 1 then
        -- One chunk: the whole-buffer call is the chunk measurement.
        local height = full_extent(source_win)
        local chunk = chunks[1]
        if height ~= chunk.height then
            layer.total_extent = height
            chunk.height = height
            chunk.memo = {}
            chunk.subs = nil
            layer.prefix_count = 0
            layer.anchors = { 0 }
        end
        layer.verified_at = uv.now()
        return
    end
    local count = math.min(CHUNK_SWEEP_PER_RENDER, #chunks)
    local total_delta = 0
    local lowest_changed_index = nil
    local started = uv.hrtime()
    for _ = 1, count do
        if uv.hrtime() - started > CHUNK_SWEEP_BUDGET_NS then
            break
        end
        local index = layer.chunk_cursor
        if index > #chunks then
            index = 1
        end
        layer.chunk_cursor = index + 1
        local chunk = chunks[index]
        local stop = index < #chunks and chunks[index + 1].start or layer.line_count
        if stop > chunk.start then
            local height = rows_between(source_win, chunk.start, stop, layer.line_count)
            if height ~= chunk.height then
                total_delta = total_delta + (height - chunk.height)
                chunk.height = height
                chunk.subs = nil
                if lowest_changed_index == nil or index < lowest_changed_index then
                    lowest_changed_index = index
                end
            end
        end
    end
    if lowest_changed_index ~= nil then
        layer.total_extent = layer.total_extent + total_delta
        local changed = chunks[lowest_changed_index]
        -- The changed chunk's internal layout moved; everything after it
        -- shifts wholesale through the chunk bases.
        changed.memo = {}
        for index = lowest_changed_index + 1, #chunks do
            chunks[index].base = chunks[index].base + total_delta
        end
        -- Drop anchors inside the changed chunk; later anchors resolve
        -- through their (shifted) chunk bases automatically.
        local anchors = layer.anchors
        local kept = {}
        for _, anchor in ipairs(anchors) do
            if anchor < changed.start then
                kept[#kept + 1] = anchor
            else
                local index = chunk_index_for(layer, anchor)
                if index ~= lowest_changed_index then
                    kept[#kept + 1] = anchor
                end
            end
        end
        layer.anchors = kept
        layer.prefix_count = math.max(0, layer.prefix_count - 0)
    end
    layer.verified_at = uv.now()
end

---Apply one recorded edit to the chunk table. Coordinates are in the buffer
---state before this edit; `current_count` is the line count in that state.
---@return boolean applied false when a full rebuild is the cheaper path
local function reindex_chunks_for_edit(source_win, layer, first, last, updated, current_count)
    local chunks = layer.chunks
    if chunks == nil or #chunks == 0 then
        return false
    end
    if updated - first > CHUNK_LINES * 8 then
        return false
    end

    -- Line-count-preserving edit: only the edited sub-spans' heights can
    -- change. Gated to manual folds — with expr/indent/syntax folds an edit
    -- can move other lines' fold boundaries, and the wholesale chunk rebuild
    -- keeps catching that immediately (the sweep covers silent changes).
    if updated == last and layer.foldmethod == "manual" then
        local i = chunk_index_for(layer, first)
        if i > 0 then
            local chunk = chunks[i]
            local chunk_end = i < #chunks and chunks[i + 1].start or current_count
            if first >= chunk.start and updated <= chunk_end and chunk.subs ~= nil then
                local subs = chunk.subs
                local s0 = math.floor((first - chunk.start) / CHUNK_SUB_LINES)
                local s1 = math.floor((updated - 1 - chunk.start) / CHUNK_SUB_LINES)
                local delta = 0
                for s = s0, s1 do
                    local sub_start = chunk.start + s * CHUNK_SUB_LINES
                    local sub_stop = math.min(sub_start + CHUNK_SUB_LINES, chunk_end)
                    local height = rows_between(source_win, sub_start, sub_stop, current_count)
                    delta = delta + (height - subs[s + 1])
                    subs[s + 1] = height
                end
                if delta ~= 0 then
                    chunk.height = chunk.height + delta
                    layer.total_extent = layer.total_extent + delta
                    for index = i + 1, #chunks do
                        chunks[index].base = chunks[index].base + delta
                    end
                end
                chunk.memo = {}
                if layer.wrapped_memo ~= nil and layer.wrapped_memo.line >= first then
                    layer.wrapped_memo = nil
                end
                return true
            end
        end
        -- Span crossing a chunk boundary: fall through to the wholesale rebuild.
    end

    local delta_lines = updated - last

    local i = chunk_index_for(layer, first)
    if i == 0 then
        return false
    end
    local j = i
    while j < #chunks and chunks[j + 1].start < last do
        j = j + 1
    end

    local removed_height = 0
    for index = i, j do
        removed_height = removed_height + chunks[index].height
    end
    local rebuild_start = chunks[i].start
    local rebuild_base = chunks[i].base
    local rebuild_end
    if j < #chunks then
        rebuild_end = chunks[j + 1].start + delta_lines
    else
        rebuild_end = current_count + delta_lines
    end

    local fresh = {}
    local added_height = 0
    local at = rebuild_start
    local running_base = rebuild_base
    local post_count = current_count + delta_lines
    while at < rebuild_end do
        local stop = math.min(at + CHUNK_LINES, rebuild_end)
        local rebuilt = measure_chunk(source_win, at, stop, post_count, running_base)
        fresh[#fresh + 1] = rebuilt
        running_base = running_base + rebuilt.height
        added_height = added_height + rebuilt.height
        at = stop
    end

    local height_delta = added_height - removed_height
    local spliced = {}
    for index = 1, i - 1 do
        spliced[#spliced + 1] = chunks[index]
    end
    for _, chunk in ipairs(fresh) do
        spliced[#spliced + 1] = chunk
    end
    for index = j + 1, #chunks do
        chunks[index].start = chunks[index].start + delta_lines
        chunks[index].base = chunks[index].base + height_delta
        spliced[#spliced + 1] = chunks[index]
    end
    layer.chunks = spliced
    layer.total_extent = layer.total_extent + height_delta

    -- Anchors inside the rebuilt region are gone with its chunks; anchors
    -- above it shift lines, and their prefixes follow the shifted bases.
    local anchors = layer.anchors
    local kept = {}
    for _, anchor in ipairs(anchors) do
        if anchor < rebuild_start then
            kept[#kept + 1] = anchor
        elseif anchor >= rebuild_end - delta_lines then
            kept[#kept + 1] = anchor + delta_lines
        end
    end
    layer.anchors = kept
    if layer.wrapped_memo ~= nil and layer.wrapped_memo.line >= first then
        layer.wrapped_memo = nil
    end
    return true
end

local function extent_layer_for(source_win)
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local changedtick = vim.api.nvim_buf_get_changedtick(source_buf)
    local line_count = vim.api.nvim_buf_line_count(source_buf)
    local win_width = vim.api.nvim_win_get_width(source_win)
    local digest = extent_option_digest(source_win)

    local layer = screen_extent_cache[source_win]
    if layer ~= nil and layer.source_buf == source_buf and layer.digest == digest then
        if layer.changedtick == changedtick and layer.line_count == line_count and layer.win_width == win_width then
            return layer
        end
        -- Text or window width changed while every extent-affecting option
        -- held. A uniform layer (no wraps, no closed folds, verified) can be
        -- carried forward by arithmetic when manual folds make text-created
        -- folds impossible: with 'wrap' off nothing can wrap, and with 'wrap'
        -- on only the edited spans can start wrapping, so measure those.
        if layer.uniform and layer.foldmethod == "manual" then
            local carried = false
            if not layer.wrap then
                -- 'wrap' off: no edit can change any line height, and
                -- window width cannot introduce wraps.
                carried = true
            else
                local spans = edits_since(source_buf, layer.changedtick)
                carried = spans ~= nil
                    and win_width == layer.win_width
                    and uniform_after_edits(source_win, spans, line_count)
            end
            if carried then
                layer.changedtick = changedtick
                layer.line_count = line_count
                layer.win_width = win_width
                layer.total_extent = line_count
                return layer
            end
        elseif layer.chunks ~= nil and win_width == layer.win_width then
            -- Non-uniform layer with a chunk table: apply the recorded edits
            -- to the chunks (measuring only the affected region) instead of
            -- rescanning the buffer.
            local edits = edits_list_since(source_buf, layer.changedtick)
            if edits ~= nil then
                local applied = true
                local prior_count = layer.line_count
                for _, edit in ipairs(edits) do
                    local first, last, updated = edit[1], edit[2], edit[3]
                    local current_count = prior_count
                    prior_count = prior_count + (updated - last)
                    if not reindex_chunks_for_edit(source_win, layer, first, last, updated, current_count) then
                        applied = false
                        break
                    end
                end
                if applied and prior_count == line_count then
                    layer.changedtick = changedtick
                    layer.line_count = line_count
                    layer.verified_at = uv.now()
                    return layer
                end
            end
        end
        layer.changedtick = changedtick
        layer.line_count = line_count
        layer.win_width = win_width
        layer.wrap = vim.api.nvim_get_option_value("wrap", { win = source_win }) == true
        layer.foldmethod = vim.api.nvim_get_option_value("foldmethod", { win = source_win })
        verify_extent(source_win, layer)
        return layer
    end

    layer = {
        source_buf = source_buf,
        changedtick = changedtick,
        line_count = line_count,
        win_width = win_width,
        digest = digest,
        wrap = vim.api.nvim_get_option_value("wrap", { win = source_win }) == true,
        foldmethod = vim.api.nvim_get_option_value("foldmethod", { win = source_win }),
        total_extent = 0,
        uniform = false,
        generation = (layer ~= nil and layer.generation or 0) + 1,
        prefix_count = 0,
        anchors = { 0 },
        verified_at = 0,
        chunks = nil,
        chunk_cursor = 1,
        uniform_cursor = 0,
    }
    attach_buffer_edits(source_buf)
    verify_extent(source_win, layer)
    screen_extent_cache[source_win] = layer
    return layer
end

--- Bounded probe standing in for the periodic full verify on uniform
--- layers: the viewport and one rotating slice below it must still render
--- 1:1 (one row per line). A mismatch drops the layer to the full verify.
--- Together with slice rotation this bounds silent-fold detection latency to
--- roughly the verify interval, at ~1% of the full scan's cost.
local UNIFORM_PROBE_SLICES = 4

local function uniform_probe(source_win, layer, height)
    local line_count = layer.line_count
    if line_count <= 1 then
        layer.verified_at = uv.now()
        return true
    end

    local view = win_view(source_win)
    local top = clamp(view.topline - 1, 0, line_count - 1)
    local view_end = math.min(top + math.max(1, height), line_count)
    if rows_between(source_win, top, view_end, line_count) ~= (view_end - top) then
        return false
    end

    local below = line_count - view_end
    if below > 0 then
        local slice = math.max(1, math.floor(below / UNIFORM_PROBE_SLICES))
        local cursor = layer.uniform_cursor or 0
        layer.uniform_cursor = (cursor % UNIFORM_PROBE_SLICES) + 1
        local start = view_end + cursor * slice
        local stop = math.min(start + slice, line_count)
        if stop > start and rows_between(source_win, start, stop, line_count) ~= (stop - start) then
            return false
        end
    end
    layer.verified_at = uv.now()
    return true
end

local function extent_layer_current(source_win, layer, height)
    if layer.uniform then
        if uv.now() - layer.verified_at >= (M.screen_extent_verify_interval_ms or EXTENT_VERIFY_INTERVAL_MS) then
            if not uniform_probe(source_win, layer, height) then
                verify_extent(source_win, layer)
            end
        end
    elseif uv.now() - layer.verified_at >= (M.screen_extent_sweep_interval_ms or SWEEP_INTERVAL_MS) then
        -- Silent fold changes are caught by re-measuring a few chunks per pass
        -- instead of rescanning the whole buffer, but no sooner than the sweep
        -- interval: renders between sweeps (scroll bursts, steady re-renders)
        -- cannot have observed a change. Windows with folding disabled cannot
        -- compress rows at all, so their sweep is a no-op stamp.
        if vim.wo[source_win].foldenable == false then
            layer.verified_at = uv.now()
        else
            sweep_chunks(source_win, layer)
        end
    end
end

---@param input ScrollbarScreenGeometryInput
---@return ScrollbarGeometry
M.screen = function(input)
    local source_win = input.source_win
    local height = input.height
    local layer = extent_layer_for(source_win)
    extent_layer_current(source_win, layer, height)

    local line_count = layer.line_count
    local maximum_line = math.max(0, line_count - 1)
    local total_extent = layer.total_extent
    local maximum_extent = math.max(0, total_extent - 1)

    local view = win_view(source_win)
    local top_line = clamp(view.topline - 1, 0, maximum_line)
    local viewport_start = clamp(
        prefix_for(source_win, top_line, layer)
            - view.topfill
            + wrapped_offset(source_win, top_line, view.skipcol, layer),
        0,
        maximum_extent
    )
    local viewport_end = clamp(viewport_start + height - 1, 0, maximum_extent)

    local buffer_revision = store._get_snapshot(layer.source_buf).revision
    local window_revision = store._get_window_snapshot(source_win).revision
    local compact_search = input.compact_search
    local cached = screen_marks_cache[source_win]
    if
        cached ~= nil
        and cached.buffer_revision == buffer_revision
        and cached.window_revision == window_revision
        and cached.height == height
        and cached.generation == layer.generation
        and cached.total_extent == total_extent
        and cached.marks == input.marks
        and cached.compact == compact_search
        and cached.viewport_start == viewport_start
    then
        return {
            total_extent = total_extent,
            viewport_start = viewport_start,
            viewport_end = viewport_end,
            mark_rows = cached.mark_rows,
            compact_mark_rows = cached.compact_mark_rows,
            handle = M.handle_geometry(viewport_start, viewport_end, total_extent, height),
        }
    end

    local unique_lines
    local prefixes = {}
    if input.marks_sorted == true then
        -- Renderer-flattened marks arrive in provider-major (line, text) runs;
        -- equal lines are adjacent, and prefix anchors make out-of-order runs
        -- cheap, so the dedup/sort pass is unnecessary.
        local previous = -1
        local marks_input = input.marks
        for index = 1, #marks_input do
            local line = marks_input[index].line
            if line < 0 then
                line = 0
            elseif line > maximum_line then
                line = maximum_line
            end
            if line ~= previous then
                prefixes[line] = line == 0 and 0 or prefix_for(source_win, line, layer)
                previous = line
            end
        end
        if compact_search ~= nil then
            search_compact.each(compact_search, function(line)
                local clamped = clamp(line, 0, maximum_line)
                if prefixes[clamped] == nil then
                    prefixes[clamped] = clamped == 0 and 0 or prefix_for(source_win, clamped, layer)
                end
            end)
        end
    else
        unique_lines = {}
        local seen_lines = {}
        for _, mark in ipairs(input.marks) do
            local line = clamp(mark.line, 0, maximum_line)
            if not seen_lines[line] then
                seen_lines[line] = true
                table.insert(unique_lines, line)
            end
        end
        if compact_search ~= nil then
            search_compact.each(compact_search, function(line)
                local clamped = clamp(line, 0, maximum_line)
                if not seen_lines[clamped] then
                    seen_lines[clamped] = true
                    table.insert(unique_lines, clamped)
                end
            end)
        end
        table.sort(unique_lines)
        for _, line in ipairs(unique_lines) do
            prefixes[line] = line == 0 and 0 or prefix_for(source_win, line, layer)
        end
    end

    local mark_rows = {}
    for index, mark in ipairs(input.marks) do
        local line = clamp(mark.line, 0, maximum_line)
        mark_rows[index] = M.map_position(prefixes[line], total_extent, height)
    end

    local compact_mark_rows
    if compact_search ~= nil then
        compact_mark_rows = {}
        search_compact.each(compact_search, function(line)
            local clamped = clamp(line, 0, maximum_line)
            compact_mark_rows[#compact_mark_rows + 1] = M.map_position(prefixes[clamped], total_extent, height)
        end)
    end

    screen_marks_cache[source_win] = {
        buffer_revision = buffer_revision,
        window_revision = window_revision,
        height = height,
        generation = layer.generation,
        total_extent = total_extent,
        marks = input.marks,
        compact = compact_search,
        viewport_start = viewport_start,
        mark_rows = mark_rows,
        compact_mark_rows = compact_mark_rows,
    }

    return {
        total_extent = total_extent,
        viewport_start = viewport_start,
        viewport_end = viewport_end,
        mark_rows = mark_rows,
        compact_mark_rows = compact_mark_rows,
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

    local layer = extent_layer_for(source_win)
    -- The caller passes the extent the scrollbar was rendered with; dragging
    -- should map rows against the geometry the user sees, not a fresher one.
    -- Prefix lookups measure live, so no canary sweep is needed here.
    local extent = math.max(1, total_extent or layer.total_extent)
    local target = extent <= height and math.min(clamped_row, extent - 1)
        or math.floor(clamped_row * (extent - 1) / (height - 1) + 0.5)
    if layer.uniform then
        -- Identity prefixes: the target display row is the target line.
        return clamp(target, 0, line_count - 1)
    end

    local low = 0
    local high = line_count - 1
    local result = 0
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if prefix_for(source_win, middle, layer) <= target then
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

-- Sort numerically only when the collected order is not already ascending;
-- provider-major mark streams leave single-provider groups presorted.
local function ensure_ascending(values)
    for index = 2, #values do
        if values[index - 1] > values[index] then
            table.sort(values)
            return
        end
    end
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
    -- When the caller guarantees `input.marks_sorted` (renderer-flattened
    -- marks are presorted per provider by line/text), group sources and lines
    -- are appended in `source_less` order and the per-group sorts disappear.
    local presorted = input.marks_sorted == true

    local function group_for(row, mark_type, mark_config, lane)
        local row_groups = by_row[row]
        if row_groups == nil then
            row_groups = {}
            by_row[row] = row_groups
        end
        local lane_groups = row_groups[lane.id]
        if lane_groups == nil then
            lane_groups = {}
            row_groups[lane.id] = lane_groups
        end
        local group = lane_groups[mark_type]
        if group == nil then
            -- `sources` is materialized only on the cold paths that need the
            -- full per-mark list (unsorted callers, compact-search merge).
            -- The presorted hot path tracks `source`, the first mark
            -- appended, which is exactly `sources[1]` there.
            local sources
            if presorted and input.compact_search == nil then
                sources = nil
            else
                sources = {}
            end
            group = {
                row = row,
                lane_id = lane.id,
                type = mark_type,
                column = translated_column(input.config, lane.first_column, column_offset),
                max_column = translated_column(input.config, lane.last_column, column_offset),
                priority = mark_config.priority,
                sources = sources,
                lines = {},
                count = 0,
                ordinary_count = 0,
            }
            lane_groups[mark_type] = group
            groups[#groups + 1] = group
        end
        return group
    end

    -- One mark-type lookup instead of a config walk per mark.
    local routes = {}
    local function route_for(mark_type)
        local route = routes[mark_type]
        if route == nil then
            local mark_config = input.config.marks[mark_type]
            local lane = mark_config and lane_for_type(input.config, mark_type) or nil
            route = (mark_config ~= nil and lane ~= nil) and { mark_config, lane } or false
            routes[mark_type] = route
        end
        return route
    end

    local height = input.height
    local mark_rows = input.geometry.mark_rows
    local marks = input.marks
    local count = #marks
    -- Provider segments (index ranges with one provider's marks, contiguous
    -- and line-sorted when the flatten emitted them). Rows are monotone in
    -- line within a segment, which lets incremental rebuilds binary-search
    -- the membership of any row.
    local segments = nil
    local segment_provider = nil
    local segment_start = 0
    -- Consecutive marks frequently share a type (provider runs) and a row
    -- (dense payloads); caching the last route and group skips the per-mark
    -- hash lookups that dominated large-payload grouping.
    local last_type, last_route
    local last_group_row, last_group_type, last_group
    for index = 1, count do
        local mark = marks[index]
        if presorted then
            local provider = mark.provider
            if provider ~= segment_provider then
                if segment_provider ~= nil then
                    segments = segments or {}
                    segments[#segments + 1] = { segment_start, index - 1 }
                end
                segment_start = index
                segment_provider = provider
            end
        end
        local row = mark_rows[index]
        if row and row >= 0 and row < height then
            local mark_type = mark.type
            if mark_type ~= last_type then
                last_type = mark_type
                last_route = route_for(mark_type)
            end
            local route = last_route
            if route ~= false then
                local lane = route[2]
                local expanded = lane.id == expanded_lane_id and mark.provider == "marks" and mark_type == "Mark"
                if not expanded then
                    local group
                    if row == last_group_row and mark_type == last_group_type and last_group ~= nil then
                        group = last_group
                    else
                        group = group_for(row, mark_type, route[1], lane)
                        last_group_row = row
                        last_group_type = mark_type
                        last_group = group
                    end
                    local n = group.count + 1
                    group.count = n
                    if group.sources ~= nil then
                        group.sources[n] = mark
                    elseif group.source == nil then
                        group.source = mark
                    end
                    group.lines[n] = mark.line
                    group.ordinary_count = group.ordinary_count + 1
                end
            end
        end
    end
    if presorted and segment_provider ~= nil then
        segments = segments or {}
        segments[#segments + 1] = { segment_start, count }
    end

    local compact = input.compact_search
    local search_config = input.config.marks.Search
    local search_lane = search_config and lane_for_type(input.config, "Search")
    if compact ~= nil and search_config ~= nil and search_lane ~= nil then
        local precomputed = input.geometry.compact_mark_rows
        local compact_groups = {}
        if precomputed ~= nil then
            search_compact.each(compact, function(line, index)
                local row = precomputed[index]
                local group = compact_groups[row]
                if group == nil then
                    group = group_for(row, "Search", search_config, search_lane)
                    group.compact_source = { provider = "search", line = line, type = "Search" }
                    compact_groups[row] = group
                end
                group.count = group.count + 1
                group.lines[#group.lines + 1] = line
            end)
        else
            local total_extent = math.max(0, input.line_count)
            local maximum_position = math.max(0, total_extent - 1)
            local maximum_row = math.max(0, input.height - 1)
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
    end

    for _, group in ipairs(groups) do
        local representative
        if group.compact_source ~= nil then
            if group.sources == nil then
                group.sources = { group.compact_source }
            else
                table.insert(group.sources, group.compact_source)
                table.sort(group.sources, source_less)
            end
            representative = group.sources[1]
        elseif group.sources ~= nil then
            if not presorted then
                table.sort(group.sources, source_less)
            end
            representative = group.sources[1]
        else
            representative = group.source
        end
        -- Group lines are a numeric-ascending contract (mouse navigation
        -- order), independent of the provider-major source order.
        ensure_ascending(group.lines)
        local variants = input.config.marks[group.type].text
        group.provider = representative.provider or ""
        group.line = representative.line
        group.text = resolved_text(group.type, variants, representative.text, group.count)
    end
    table.sort(groups, candidate_less)
    return groups, segments
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
        if input.marks_sorted ~= true then
            table.sort(sources, function(left, right)
                if left.line ~= right.line then
                    return left.line < right.line
                end
                return (left.text or "") < (right.text or "")
            end)
        end
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

-- Incremental layer rebuild: recompute only the rows whose membership
-- changed after an extent edit. A row's membership is derived by binary
-- search over each provider segment (rows are monotone in line within a
-- segment), so unchanged rows keep their exact placed objects and groups
-- are rebuilt from final membership — no in-place removal, no ambiguity.
local INCREMENTAL_CHANGE_LIMIT = 256

local function rebuild_row_groups(input, row, mark_rows, segments)
    local config = input.config
    local marks = input.marks
    local groups = {}
    local by_type = {}
    for _, segment in ipairs(segments) do
        local lo, hi = segment[1], segment[2]
        local low, high = lo, hi + 1
        while low < high do
            local mid = math.floor((low + high) / 2)
            if mark_rows[mid] < row then
                low = mid + 1
            else
                high = mid
            end
        end
        local first = low
        low, high = first, hi + 1
        while low < high do
            local mid = math.floor((low + high) / 2)
            if mark_rows[mid] > row then
                high = mid
            else
                low = mid + 1
            end
        end
        local last = low - 1
        for index = first, last do
            local mark = marks[index]
            local mark_type = mark.type
            local group = by_type[mark_type]
            if group == nil then
                local mark_config = config.marks[mark_type]
                local lane = mark_config and lane_for_type(config, mark_type) or nil
                if mark_config ~= nil and lane ~= nil then
                    group = {
                        row = row,
                        lane_id = lane.id,
                        type = mark_type,
                        column = translated_column(config, lane.first_column, 0),
                        max_column = translated_column(config, lane.last_column, 0),
                        priority = mark_config.priority,
                        source = mark,
                        lines = {},
                        count = 0,
                        ordinary_count = 0,
                    }
                    by_type[mark_type] = group
                    groups[#groups + 1] = group
                else
                    by_type[mark_type] = false
                end
            end
            if group ~= false and group ~= nil then
                local n = group.count + 1
                group.count = n
                group.lines[n] = mark.line
                group.ordinary_count = group.ordinary_count + 1
            end
        end
    end
    for _, group in ipairs(groups) do
        ensure_ascending(group.lines)
        local variants = config.marks[group.type].text
        group.provider = group.source.provider or ""
        group.line = group.source.line
        group.text = resolved_text(group.type, variants, group.source.text, group.count)
    end
    table.sort(groups, candidate_less)
    return groups
end

local function place_row(groups)
    local row_cells = {}
    for _, group in ipairs(groups) do
        local cells = row_cells[group.lane_id]
        if cells == nil then
            cells = {}
            row_cells[group.lane_id] = cells
        end
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
    return row_cells
end

local function resolve_mark_layer(input)
    local previous = input.previous
    if
        previous ~= nil
        and type(previous.layer) == "table"
        and type(previous.layer.segments) == "table"
        and previous.layer.expanded_lane_id == false
        and input.compact_search == nil
        and type(previous.changed) == "table"
        and #previous.changed <= INCREMENTAL_CHANGE_LIMIT
        and previous.layer.height == input.height
        and previous.layer.marks_identity == input.marks
    then
        local prev = previous.layer
        local mark_rows = input.geometry.mark_rows
        local changed_rows = {}
        for _, entry in ipairs(previous.changed) do
            -- entry = { index, old_row }; the new row is readable from the
            -- already-mutated rows array.
            changed_rows[entry[2]] = true
            changed_rows[mark_rows[entry[1]]] = true
        end
        local width, column_offset = layer_dimensions(input, {}, nil)
        local rows = {}
        for row = 0, input.height - 1 do
            rows[row] = prev.rows[row]
        end
        for row in pairs(changed_rows) do
            if row >= 0 and row < input.height then
                rows[row] = place_row(rebuild_row_groups(input, row, mark_rows, prev.segments))
            end
        end
        return {
            rows = rows,
            width = width,
            column_offset = column_offset,
            expanded_lane_id = false,
            marks_identity = input.marks,
            segments = prev.segments,
            height = input.height,
            mark_rows = mark_rows,
        }
    end
    local buckets, expanded_lane = expanded_buckets(input)
    local width, column_offset = layer_dimensions(input, buckets, expanded_lane)
    local candidates, segments = group_candidates(input, column_offset, expanded_lane and expanded_lane.id or nil)
    add_expanded_candidates(input, candidates, buckets, expanded_lane, width, column_offset)
    table.sort(candidates, candidate_less)
    return {
        rows = place_marks(input, candidates),
        width = width,
        column_offset = column_offset,
        expanded_lane_id = expanded_lane and expanded_lane.id or false,
        marks_identity = input.marks,
        segments = segments,
        height = input.height,
        mark_rows = input.geometry.mark_rows,
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

-- Composed-output cache keyed by resolved mark-layer identity, holding the
-- handle rows, height, and compiled layout cache that fully determine the
-- compose result. Each window rebuild produces a distinct layer table, so
-- windows sharing a variant keep separate entries instead of evicting each
-- other; entries die with their layer on the next rebuild or clear_cache.
local compose_cache = {}

-- Per-row reuse across layer rebuilds that share the flattened-marks table
-- identity. After an edit only a couple of row assignments shift, so most
-- composed rows are byte-identical; weak keys keep entries alive exactly as
-- long as their marks table (entries never reference their key).
local compose_reuse = setmetatable({}, { __mode = "k" })

-- Structural row equality. `lines` equality is checked as
-- count/first/last: with a stable marks table, row assignment is monotone in
-- line, so any membership change of a row's set alters its count or its
-- first/last element — the three-way check is exact under that invariant.
local function row_equivalent(a, b)
    if a == nil or b == nil then
        return a == nil and b == nil
    end
    local count_b = 0
    for _ in pairs(b) do
        count_b = count_b + 1
    end
    local count_a = 0
    for _ in pairs(a) do
        count_a = count_a + 1
    end
    if count_a ~= count_b then
        return false
    end
    for lane, cells_a in pairs(a) do
        local cells_b = b[lane]
        if cells_b == nil then
            return false
        end
        local cells = 0
        for _ in pairs(cells_a) do
            cells = cells + 1
        end
        for _ in pairs(cells_b) do
            cells = cells - 1
        end
        if cells ~= 0 then
            return false
        end
        for column, placed_a in pairs(cells_a) do
            local placed_b = cells_b[column]
            if placed_b == nil then
                return false
            end
            if
                placed_a.text ~= placed_b.text
                or placed_a.width ~= placed_b.width
                or placed_a.column ~= placed_b.column
                or placed_a.last_column ~= placed_b.last_column
                or placed_a.lane_id ~= placed_b.lane_id
                or placed_a.type ~= placed_b.type
                or placed_a.provider ~= placed_b.provider
                or placed_a.line ~= placed_b.line
            then
                return false
            end
            local lines_a = placed_a.lines
            local lines_b = placed_b.lines
            if #lines_a ~= #lines_b or lines_a[1] ~= lines_b[1] or lines_a[#lines_a] ~= lines_b[#lines_b] then
                return false
            end
        end
    end
    return true
end

---@param input ScrollbarLayoutInput
---@return ScrollbarLayoutOutput
M.compose = function(input)
    local mark_layer = input.mark_layer or resolve_mark_layer(input)
    local handle_geometry = input.geometry.handle
    local layout_cache = input.config.layout_cache
    local cached = compose_cache[mark_layer]
    if
        cached ~= nil
        and cached.handle_first == handle_geometry.first_row
        and cached.handle_last == handle_geometry.last_row
        and cached.height == input.height
        and (cached.layout_cache == layout_cache or vim.deep_equal(cached.layout_cache, layout_cache))
    then
        return cached.output
    end

    local rows = {}
    local highlights = {}
    local hitmap = {}
    -- Row-level reuse across rebuilds sharing the marks table identity: the
    -- reference entry must agree on every output-determining input (handle
    -- rows, height, layout cache, width, column offset, expansion lane).
    local reuse = nil
    local identity = mark_layer.marks_identity
    if identity ~= nil then
        local reference = compose_reuse[identity]
        if
            reference ~= nil
            and reference.handle_first == handle_geometry.first_row
            and reference.handle_last == handle_geometry.last_row
            and reference.height == input.height
            and (reference.layout_cache == layout_cache or vim.deep_equal(reference.layout_cache, layout_cache))
            and reference.width == mark_layer.width
            and reference.column_offset == mark_layer.column_offset
            and reference.expanded_lane_id == mark_layer.expanded_lane_id
        then
            reuse = reference
        end
    end
    for row = 0, input.height - 1 do
        local content = mark_layer.rows[row]
        if reuse ~= nil and row_equivalent(reuse.rows[row], content) then
            local reused = reuse.output
            rows[row + 1] = reused.rows[row + 1]
            highlights[row + 1] = reused.highlights[row + 1]
            hitmap[row + 1] = reused.hitmap[row + 1]
        else
            rows[row + 1], highlights[row + 1], hitmap[row + 1] =
                render_row(input, row, content, mark_layer.width, mark_layer.column_offset, mark_layer.expanded_lane_id)
        end
    end

    ---@type false|ScrollbarHandleGeometry
    local handle = false
    if input.config.layout.thumb ~= false then
        handle = {
            first_row = handle_geometry.first_row,
            last_row = handle_geometry.last_row,
            column = translated_column(input.config, input.config.layout.thumb.first_column, mark_layer.column_offset),
            width = input.config.layout.thumb.width,
        }
    end
    local output = {
        rows = rows,
        width = mark_layer.width,
        highlights = highlights,
        hitmap = hitmap,
        handle = handle,
    }
    compose_cache[mark_layer] = {
        handle_first = handle_geometry.first_row,
        handle_last = handle_geometry.last_row,
        height = input.height,
        layout_cache = layout_cache,
        output = output,
    }
    if identity ~= nil then
        compose_reuse[identity] = {
            rows = mark_layer.rows,
            output = output,
            handle_first = handle_geometry.first_row,
            handle_last = handle_geometry.last_row,
            height = input.height,
            layout_cache = layout_cache,
            width = mark_layer.width,
            column_offset = mark_layer.column_offset,
            expanded_lane_id = mark_layer.expanded_lane_id,
        }
    end
    return output
end

M.clear_cache = function()
    glyph_cache = {}
    compose_cache = {}
    compose_reuse = setmetatable({}, { __mode = "k" })
end

M.clear_screen_cache = function(source_win)
    screen_extent_cache[source_win] = nil
    screen_marks_cache[source_win] = nil
    digest_cache[source_win] = nil
end

M.clear_all_screen_caches = function()
    screen_extent_cache = {}
    screen_marks_cache = {}
    digest_cache = {}
end

return M
