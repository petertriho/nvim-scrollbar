--- Top-level configuration. Normalizes the shared sections, compiles the
--- scrollbar block and its profiles, delegates the minimap block to
--- `scrollbar.minimap.config`, and builds the provider plan. Setup either
--- commits every part or fails without changing the active configuration.

local block_config = require("scrollbar.config.block")
local const = require("scrollbar.config.const")
local highlights = require("scrollbar.highlights")
local minimap_config = require("scrollbar.minimap.config")
local provider_config = require("scrollbar.config.providers")
local schema = require("scrollbar.config.schema")
local shared_config = require("scrollbar.config.shared")
local window_config = require("scrollbar.config.window")

local invalid = schema.invalid

local DEFAULTS = {
    enabled = true,
    show = true,
    visibility = "all",
    autohide = false,
    max_lines = false,
    throttle_ms = 16,
    unit = "line",
    placement = {
        relative = "window",
        anchor = "NE",
        row = 0,
        col = 0,
        gutter = "inner",
        zindex = 50,
    },
    hide_on_cursor = true,
    hide_if_all_visible = false,
    mouse = true,
    layout = {
        direction = "auto",
        columns = {
            { "track", "thumb", "marks" },
        },
    },
    track = {
        highlight = "PmenuSbar",
    },
    thumb = {
        text = " ",
        blend = 30,
        highlight = "PmenuThumb",
        hide_if_all_visible = true,
    },
    marks = {},
    window = {
        border = "none",
        wo = {},
    },
}

-- The scrollbar listens to every supported event by default. If the list is in
-- DEFAULTS, a keyed `events` override merges into it. Thus the list is not in
-- DEFAULTS.
local DEFAULT_EVENTS = shared_config.EVENTS

local APPEARANCE_KEYS = {
    preset = true,
    unit = true,
    placement = {
        relative = true,
        anchor = true,
        row = true,
        col = true,
        gutter = true,
        zindex = true,
    },
    hide_on_cursor = true,
    hide_if_all_visible = true,
    mouse = true,
    layout = { direction = true, columns = true },
    track = { highlight = true },
    thumb = { text = true, blend = true, highlight = true, hide_if_all_visible = true },
    marks = { ["*"] = { text = true, priority = true, highlight = true } },
    -- `scrollbar.config.window` validates the keys of `window`.
    window = { ["*"] = true },
}

local WINDOW_SPEC = {
    owned_keys = {
        width = "the layout sets the width",
        height = "the text area sets the height",
    },
}

local LAYER_KEYS = { types = true, max_width = true }

-- Replacements for the v1 options, shown in the unknown-option error.
local REMOVED_KEYS = {
    update = "use 'throttle_ms' and 'events'",
    render = "use 'unit'",
    float = "use 'placement', 'placement.zindex', and 'hide_on_cursor'",
    presets = "custom presets are removed. Set the options in the block or in a profile",
    extends = "custom presets are removed. Set the options in the block or in a profile",
    excluded_buftypes = "use the top-level 'exclude' table",
    excluded_filetypes = "use the top-level 'exclude' table",
    providers = "use the top-level 'providers' table",
    set_highlights = "use the top-level 'set_highlights' option",
    ["autohide.enabled"] = "use 'autohide = true' or 'autohide = { delay_ms = n }'",
    ["placement.gutter_position"] = "use 'placement.gutter' with 'inner', 'outer', or 'overlap'",
}

-- Replacements for the top-level v1 options. A v1 configuration fails setup,
-- so the error also names the migration guide and the v1 branch.
local V1_TOP_LEVEL_KEYS = {
    show = "use 'scrollbar.show'",
    show_in_active_only = "use 'scrollbar.visibility'",
    folds = "use 'scrollbar.unit'",
    max_lines = "use 'scrollbar.max_lines'",
    hide_if_all_visible = "use 'scrollbar.hide_if_all_visible'",
    throttle_ms = "use 'scrollbar.throttle_ms'",
    handle = "use 'scrollbar.thumb'",
    excluded_buftypes = "use 'exclude.buftypes'",
    excluded_filetypes = "use 'exclude.filetypes'",
    autocmd = "use 'scrollbar.events' and 'minimap.events'",
    handlers = "use 'providers'",
}

local TOP_LEVEL_KEYS = {
    set_highlights = true,
    exclude = true,
    providers = true,
    marks = true,
    scrollbar = true,
    minimap = true,
}

---@type ScrollbarConfig?
local active
---@type ScrollbarCompiledVariant[]?
local variants
---@type ScrollbarEffectiveProviderPlan?
local provider_plan
---@type table<string, true>?
local mark_types
local selector = schema.selector("scrollbar")

---@param value any
---@param path string
---@return ScrollbarNormalizedLayoutLayerInput
local function normalized_layer(value, path)
    if type(value) == "string" then
        if value == "track" or value == "thumb" then
            return { kind = value }
        end
        if value == "marks" then
            return { kind = "marks", catch_all = true, types = false, max_width = false }
        end
    end
    if type(value) ~= "table" then
        invalid(path .. " must be 'track', 'thumb', 'marks', or a mark descriptor")
    end

    schema.check_keys(value, LAYER_KEYS, path)
    if value.types == nil then
        invalid(path .. ".types is required in a mark descriptor. Use 'marks' for the catch-all lane")
    end

    local types_path = path .. ".types"
    local count = schema.dense_count(value.types, types_path)
    if count == 0 then
        invalid(types_path .. " must contain at least one type")
    end
    local types = {}
    local seen = {}
    for index = 1, count do
        local name = value.types[index]
        if type(name) ~= "string" then
            invalid(string.format("%s[%d] must be a string", types_path, index))
        end
        if not name:match(schema.TYPE_NAME_PATTERN) then
            invalid(string.format("%s[%d] must be a valid mark type", types_path, index))
        end
        if seen[name] then
            invalid(string.format("%s contains duplicate type '%s'", types_path, name))
        end
        seen[name] = true
        types[#types + 1] = name
    end
    table.sort(types)

    local max_width = false
    if value.max_width ~= nil then
        schema.integer(value.max_width, path .. ".max_width", 1)
        if not seen.Mark then
            invalid(path .. ".max_width is valid only for a lane explicitly selecting Mark")
        end
        max_width = value.max_width
    end

    return { kind = "marks", catch_all = false, types = types, max_width = max_width }
end

local function layer_signature(layer)
    if layer.catch_all then
        return "*"
    end
    return table.concat(layer.types, "\0")
end

---@param layout any
---@param anchor ScrollbarFloatAnchor
---@param path string
---@return ScrollbarLayoutConfig
local function compile_layout(layout, anchor, path)
    schema.table(layout, path)
    schema.enum(layout.direction, path .. ".direction", { "auto", "ltr", "rtl" })
    local columns_path = path .. ".columns"
    local width = schema.dense_count(layout.columns, columns_path)
    if width == 0 then
        invalid(columns_path .. " must contain at least one column")
    end

    local logical = {}
    local lanes = {}
    local lane_by_signature = {}
    local type_owner = {}
    local previous_signatures = {}
    local thumb_columns = {}

    for column_index = 1, width do
        local column_path = string.format("%s[%d]", columns_path, column_index)
        local layer_count = schema.dense_count(layout.columns[column_index], column_path)
        if layer_count == 0 then
            invalid(column_path .. " must contain at least one layer")
        end

        local column = {}
        local current_signatures = {}
        local seen_layers = {}
        for stack_index = 1, layer_count do
            local layer_path = string.format("%s[%d]", column_path, stack_index)
            local layer = normalized_layer(layout.columns[column_index][stack_index], layer_path)
            if layer.kind ~= "marks" then
                if seen_layers[layer.kind] then
                    invalid(layer_path .. " duplicates the " .. layer.kind .. " layer in one column")
                end
                seen_layers[layer.kind] = true
                if layer.kind == "thumb" then
                    thumb_columns[#thumb_columns + 1] = column_index
                end
                column[#column + 1] = { kind = layer.kind, priority = stack_index }
            else
                local signature = layer_signature(layer)
                local duplicate_key = "marks:" .. signature
                if seen_layers[duplicate_key] then
                    invalid(layer_path .. " duplicates the same mark selector in one column")
                end
                seen_layers[duplicate_key] = true

                local lane_id = previous_signatures[signature]
                if lane_id == nil then
                    if lane_by_signature[signature] ~= nil then
                        local label = layer.catch_all and "catch-all marks" or "mark type '" .. layer.types[1] .. "'"
                        invalid(path .. ": " .. label .. " must occupy one contiguous lane")
                    end
                    lane_id = #lanes + 1
                    lanes[lane_id] = {
                        id = lane_id,
                        catch_all = layer.catch_all,
                        types = layer.types,
                        columns = {},
                        max_width = false,
                    }
                    lane_by_signature[signature] = lane_id
                    if not layer.catch_all then
                        for _, mark_type in ipairs(layer.types) do
                            if type_owner[mark_type] ~= nil then
                                invalid(path .. ": mark type '" .. mark_type .. "' must occupy one contiguous lane")
                            end
                            type_owner[mark_type] = lane_id
                        end
                    end
                end

                local lane = lanes[lane_id]
                if layer.max_width ~= false then
                    if lane.max_width ~= false and lane.max_width ~= layer.max_width then
                        invalid(layer_path .. ".max_width conflicts with another value in the same lane")
                    end
                    lane.max_width = layer.max_width
                end
                lane.columns[#lane.columns + 1] = column_index
                current_signatures[signature] = lane_id
                column[#column + 1] = { kind = "marks", lane_id = lane_id, priority = stack_index }
            end
        end
        logical[column_index] = column
        previous_signatures = current_signatures
    end

    for index = 2, #thumb_columns do
        if thumb_columns[index] ~= thumb_columns[index - 1] + 1 then
            invalid(path .. ": thumb must occupy one contiguous span")
        end
    end

    local east = anchor:sub(2, 2) == "E"
    local reverse = layout.direction == "rtl" or (layout.direction == "auto" and not east)
    local physical = {}
    for logical_column, column in ipairs(logical) do
        local physical_column = reverse and width - logical_column + 1 or logical_column
        physical[physical_column] = column
    end

    local routes = {}
    local catchall_lane = false
    for _, lane in ipairs(lanes) do
        local physical_columns = {}
        for _, logical_column in ipairs(lane.columns) do
            physical_columns[#physical_columns + 1] = reverse and width - logical_column + 1 or logical_column
        end
        table.sort(physical_columns)
        lane.columns = physical_columns
        lane.first_column = physical_columns[1]
        lane.last_column = physical_columns[#physical_columns]
        if lane.max_width ~= false and lane.max_width < #physical_columns then
            invalid(path .. ": mark lane max_width must be greater than or equal to its base lane width")
        end
        if lane.catch_all then
            catchall_lane = lane.id
        else
            for _, mark_type in ipairs(lane.types) do
                routes[mark_type] = lane.id
            end
        end
    end

    ---@type false|ScrollbarNormalizedThumbSpan
    local thumb = false
    if #thumb_columns > 0 then
        local first = reverse and width - thumb_columns[#thumb_columns] + 1 or thumb_columns[1]
        local last = reverse and width - thumb_columns[1] + 1 or thumb_columns[#thumb_columns]
        thumb = { first_column = first, last_column = last, width = last - first + 1 }
    end

    local result = {
        direction = layout.direction,
        width = width,
        inward = east and "left" or "right",
        columns = physical,
        lanes = lanes,
        routes = routes,
        catchall_lane = catchall_lane,
        thumb = thumb,
    }
    result.cache = vim.deepcopy(result)
    return result
end

---@param value ScrollbarConfig
local function layout_config(value)
    local marks = {}
    for mark_type, mark in pairs(value.marks) do
        marks[mark_type] = {
            text = mark.text,
            priority = mark.priority,
        }
    end
    return { unit = value.unit, layout = value.layout.cache, marks = marks }
end

---@param value table Layered options merged onto the defaults
---@param shared ScrollbarSharedConfig
---@param path string Prefix for error paths
---@param variant_id integer 0 for the root, or the profile index
---@return ScrollbarConfig
local function normalize(value, shared, path, variant_id)
    local function at(name)
        return path .. "." .. name
    end

    local autohide = block_config.autohide(value.autohide, at("autohide"))

    local placement = schema.table(value.placement, at("placement"))
    local normalized_placement = {
        relative = schema.enum(placement.relative, at("placement.relative"), { "window", "editor" }),
        anchor = schema.enum(placement.anchor, at("placement.anchor"), { "NW", "NE", "SW", "SE" }),
        row = schema.integer(placement.row, at("placement.row")),
        col = schema.integer(placement.col, at("placement.col")),
        gutter = schema.enum(placement.gutter, at("placement.gutter"), { "inner", "outer", "overlap" }),
        zindex = schema.integer(placement.zindex, at("placement.zindex"), 1),
    }

    local track = schema.table(value.track, at("track"))
    local thumb = schema.table(value.thumb, at("thumb"))

    local globals = block_config.globals(value, path, autohide, DEFAULT_EVENTS)
    local result = vim.tbl_extend("error", globals, {
        set_highlights = shared.set_highlights,
        exclude = shared.exclude.scrollbar,
        unit = schema.enum(value.unit, at("unit"), { "line", "screenline" }),
        placement = normalized_placement,
        hide_on_cursor = schema.boolean(value.hide_on_cursor, at("hide_on_cursor")),
        hide_if_all_visible = schema.boolean(value.hide_if_all_visible, at("hide_if_all_visible")),
        mouse = schema.boolean(value.mouse, at("mouse")),
        layout = compile_layout(value.layout, normalized_placement.anchor, at("layout")),
        track = { highlight = schema.highlight(track.highlight, at("track.highlight")) },
        thumb = {
            text = schema.text(thumb.text, at("thumb.text")),
            blend = schema.integer(thumb.blend, at("thumb.blend"), 0, 100),
            highlight = schema.highlight(thumb.highlight, at("thumb.highlight")),
            hide_if_all_visible = schema.boolean(thumb.hide_if_all_visible, at("thumb.hide_if_all_visible")),
        },
        marks = shared_config.resolve_marks(shared.marks, value.marks, at("marks"), {
            fields = { "text", "priority", "highlight" },
        }),
        window = window_config.normalize(value.window, at("window"), WINDOW_SPEC),
    })
    result.highlights = highlights.get_highlight_groups(result, variant_id, shared.set_highlights)
    result.layout_cache = layout_config(result)
    ---@cast result ScrollbarConfig
    return result
end

local BLOCK = block_config.block({
    name = "scrollbar",
    defaults = DEFAULTS,
    global_keys = block_config.GLOBAL_KEYS,
    appearance_keys = APPEARANCE_KEYS,
    removed_keys = REMOVED_KEYS,
    profile_hints = { config = "set the options directly in the profile" },
    normalize = normalize,
})

---@param overrides any
---@param shared ScrollbarSharedConfig
---@return ScrollbarConfig, ScrollbarCompiledVariant[]
local function compile(overrides, shared)
    local root, compiled = block_config.compile(BLOCK, overrides, shared)
    ---@cast root ScrollbarConfig
    ---@cast compiled ScrollbarCompiledVariant[]
    return root, compiled
end

---@param scrollbar_variants ScrollbarCompiledVariant[]
---@param minimap_variants ScrollbarMinimapCompiledVariant[]
local function validate_public_highlight_groups(scrollbar_variants, minimap_variants)
    local owners = {
        ScrollbarBase = "the scrollbar base",
        ScrollbarTrack = "the scrollbar track",
        ScrollbarThumb = "the scrollbar thumb",
        ScrollbarThumbPressed = "the pressed scrollbar thumb",
        ScrollbarHandle = "the legacy scrollbar handle",
        ScrollbarHandlePressed = "the pressed legacy scrollbar handle",
        ScrollbarFloatBorder = "the scrollbar border",
        ScrollbarFloatTitle = "the scrollbar title",
        ScrollbarFloatFooter = "the scrollbar footer",
        ScrollbarMinimapBase = "the static minimap base",
        ScrollbarMinimapContent = "the static minimap content",
        ScrollbarMinimapViewport = "the static minimap viewport",
        ScrollbarMinimapCursor = "the static minimap cursor",
        ScrollbarMinimapFloatBorder = "the minimap border",
        ScrollbarMinimapFloatTitle = "the minimap title",
        ScrollbarMinimapFloatFooter = "the minimap footer",
    }
    local function claim(group, owner)
        local existing = owners[group]
        if existing ~= nil and existing ~= owner then
            invalid(string.format("highlight group '%s' is claimed by %s and %s", group, existing, owner))
        end
        owners[group] = owner
    end

    for _, variant in ipairs(scrollbar_variants) do
        for mark_type in pairs(variant.config.marks) do
            local owner = "scrollbar mark type '" .. mark_type .. "'"
            claim("Scrollbar" .. mark_type, owner)
            claim("Scrollbar" .. mark_type .. "Thumb", owner .. " thumb overlap")
            claim("Scrollbar" .. mark_type .. "ThumbPressed", owner .. " pressed thumb overlap")
            claim("Scrollbar" .. mark_type .. "Handle", owner .. " legacy handle overlap")
            claim("Scrollbar" .. mark_type .. "HandlePressed", owner .. " pressed legacy handle overlap")
        end
    end
    for _, variant in ipairs(minimap_variants) do
        for mark_type in pairs(variant.config.marks) do
            claim("ScrollbarMinimap" .. mark_type, "minimap mark type '" .. mark_type .. "'")
        end
    end
end

local M = {}

---@param overrides? ScrollbarUserConfig
---@return ScrollbarConfig
M.set = function(overrides)
    if overrides == nil then
        overrides = {}
    elseif type(overrides) ~= "table" then
        invalid("configuration must be a table")
    end

    for key in pairs(overrides) do
        if not TOP_LEVEL_KEYS[key] then
            local hint = ""
            if V1_TOP_LEVEL_KEYS[key] ~= nil then
                hint = string.format(" (v1 option: %s. %s)", V1_TOP_LEVEL_KEYS[key], const.V1_MIGRATION)
            elseif BLOCK.root_keys[key] ~= nil then
                hint = " (scrollbar options go in the 'scrollbar' block)"
            end
            invalid(string.format("unknown option '%s'%s", tostring(key), hint))
        end
    end

    local shared = shared_config.normalize(overrides)
    local provider_requests = provider_config.normalize(overrides.providers)
    local normalized, compiled = compile(overrides.scrollbar, shared)
    local normalized_minimap, compiled_minimap = minimap_config._compile(overrides.minimap, shared)
    -- A disabled minimap defines no groups, so it claims none.
    validate_public_highlight_groups(compiled, normalized_minimap.enabled and compiled_minimap or {})
    local compiled_provider_plan =
        provider_config.compile_plan(provider_requests, normalized.enabled, normalized_minimap.enabled)

    local registered = {}
    for mark_type in pairs(shared.marks.specs) do
        registered[mark_type] = true
    end

    active = normalized
    variants = compiled
    provider_plan = compiled_provider_plan
    mark_types = registered
    minimap_config._commit(normalized_minimap, compiled_minimap)
    selector = schema.selector("scrollbar")
    return active
end

---@return ScrollbarConfig
M.get = function()
    if active == nil then
        M.set()
    end
    return assert(active, "active scrollbar config unavailable")
end

---@return ScrollbarMinimapConfig
M.get_minimap = function()
    return minimap_config.get()
end

---@return ScrollbarEffectiveProviderPlan
M.get_provider_plan = function()
    M.get()
    return assert(provider_plan, "effective provider plan unavailable")
end

---@return ScrollbarCompiledVariant[]
M.get_variants = function()
    M.get()
    return assert(variants, "compiled scrollbar variants unavailable")
end

--- Registered mark types. Providers can publish any registered type, even
--- when a renderer hides it.
---@return table<string, true>
M.get_mark_types = function()
    M.get()
    return assert(mark_types, "registered mark types unavailable")
end

---@param source_win integer
---@return ScrollbarConfigSelection
M.select = function(source_win)
    M.get()
    return schema.select(selector, assert(variants, "compiled scrollbar variants unavailable"), source_win)
end

return M
