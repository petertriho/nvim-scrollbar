local presets = require("scrollbar.presets")
local utils = require("scrollbar.utils")

local DEFAULTS = {
    show = true,
    visibility = "all",
    set_highlights = true,
    max_lines = false,
    hide_if_all_visible = false,
    autohide = {
        enabled = false,
        delay_ms = 1000,
    },
    render = {
        interval_ms = 16,
        geometry = "line",
    },
    float = {
        zindex = 50,
        hide_on_cursor = true,
        placement = {
            relative = "window",
            anchor = "NE",
            row = 0,
            col = 0,
        },
    },
    layout = {
        direction = "auto",
        columns = {
            { "track", "thumb", "marks" },
        },
    },
    track = {
        highlight = "PmenuSbar",
    },
    mouse = {
        enabled = true,
    },
    thumb = {
        text = " ",
        blend = 30,
        highlight = "PmenuThumb",
        hide_if_all_visible = true,
    },
    marks = {
        Cursor = {
            text = { "•" },
            priority = 0,
            highlight = "Normal",
        },
        Mark = {
            text = {},
            priority = 1,
            highlight = "Special",
        },
        Search = {
            text = { "-", "=" },
            priority = 1,
            highlight = "Search",
        },
        Error = {
            text = { "-", "=" },
            priority = 2,
            highlight = "DiagnosticVirtualTextError",
        },
        Warn = {
            text = { "-", "=" },
            priority = 3,
            highlight = "DiagnosticVirtualTextWarn",
        },
        Info = {
            text = { "-", "=" },
            priority = 4,
            highlight = "DiagnosticVirtualTextInfo",
        },
        Hint = {
            text = { "-", "=" },
            priority = 5,
            highlight = "DiagnosticVirtualTextHint",
        },
        Misc = {
            text = { "-", "=" },
            priority = 6,
            highlight = "Normal",
        },
        GitAdd = {
            text = { "┃" },
            priority = 7,
            highlight = "GitSignsAdd",
        },
        GitChange = {
            text = { "┃" },
            priority = 7,
            highlight = "GitSignsChange",
        },
        GitDelete = {
            text = { "▁" },
            priority = 7,
            highlight = "GitSignsDelete",
        },
        MiniDiffAdd = {
            text = { "▒" },
            priority = 7,
            highlight = "MiniDiffSignAdd",
        },
        MiniDiffChange = {
            text = { "▒" },
            priority = 7,
            highlight = "MiniDiffSignChange",
        },
        MiniDiffDelete = {
            text = { "▒" },
            priority = 7,
            highlight = "MiniDiffSignDelete",
        },
        SignifyAdd = {
            text = { "┃" },
            priority = 7,
            highlight = "SignifySignAdd",
        },
        SignifyChange = {
            text = { "┃" },
            priority = 7,
            highlight = "SignifySignChange",
        },
        SignifyDelete = {
            text = { "▁" },
            priority = 7,
            highlight = "SignifySignDelete",
        },
        VGitAdd = {
            text = { "┃" },
            priority = 7,
            highlight = "GitSignsAdd",
        },
        VGitChange = {
            text = { "┃" },
            priority = 7,
            highlight = "GitSignsChange",
        },
        VGitDelete = {
            text = { "▁" },
            priority = 7,
            highlight = "GitSignsDelete",
        },
    },
    providers = {
        cursor = true,
        diagnostic = true,
        search = true,
        marks = true,
        gitsigns = false,
        mini_diff = false,
        signify = false,
        vgit = false,
        ale = false,
        coc = false,
    },
    excluded_buftypes = {
        "terminal",
    },
    excluded_filetypes = {
        "blink-cmp-menu",
        "dropbar_menu",
        "dropbar_menu_fzf",
        "DressingInput",
        "cmp_docs",
        "cmp_menu",
        "noice",
        "prompt",
        "TelescopePrompt",
    },
}

local TOP_LEVEL_KEYS = {
    show = true,
    visibility = true,
    set_highlights = true,
    max_lines = true,
    hide_if_all_visible = true,
    autohide = true,
    render = true,
    float = true,
    layout = true,
    track = true,
    mouse = true,
    thumb = true,
    marks = true,
    providers = true,
    excluded_buftypes = true,
    excluded_filetypes = true,
}

local NESTED_KEYS = {
    autohide = { enabled = true, delay_ms = true },
    render = { interval_ms = true, geometry = true },
    float = { zindex = true, hide_on_cursor = true, placement = true },
    ["float.placement"] = { relative = true, anchor = true, row = true, col = true },
    layout = { direction = true, columns = true },
    track = { highlight = true },
    mouse = { enabled = true },
    thumb = { text = true, blend = true, highlight = true, hide_if_all_visible = true },
    mark = { text = true, priority = true, highlight = true },
    layer = { kind = true, types = true, max_width = true },
    providers = {
        cursor = true,
        diagnostic = true,
        search = true,
        marks = true,
        gitsigns = true,
        mini_diff = true,
        signify = true,
        vgit = true,
        ale = true,
        coc = true,
    },
    search = { incsearch = true, backend = true },
    ["providers.marks"] = { letters = true, numbers = true },
}

local PROFILE_KEYS = {
    match = true,
    preset = true,
    config = true,
}

local PROFILE_MATCH_KEYS = {
    filetypes = true,
    buftypes = true,
    when = true,
}

local PROFILE_CONFIG_KEYS = {
    hide_if_all_visible = true,
    render = true,
    float = true,
    layout = true,
    track = true,
    mouse = true,
    thumb = true,
    marks = true,
}

local PROFILE_NESTED_KEYS = {
    render = { geometry = true },
    float = NESTED_KEYS.float,
    ["float.placement"] = NESTED_KEYS["float.placement"],
    layout = NESTED_KEYS.layout,
    track = NESTED_KEYS.track,
    mouse = NESTED_KEYS.mouse,
    thumb = NESTED_KEYS.thumb,
    mark = NESTED_KEYS.mark,
}

local ENUMS = {
    visibility = { all = true, active = true },
    geometry = { line = true, screen = true },
    relative = { window = true, editor = true },
    anchor = { NW = true, NE = true, SW = true, SE = true },
    direction = { auto = true, ltr = true, rtl = true },
    search_backend = { sync = true, worker = true },
}

---@type ScrollbarConfig?
local active
---@type ScrollbarCompiledVariant[]?
local variants
local layout_generation = 0
local profile_error_notifications = {}

local function invalid(message)
    error("[scrollbar.nvim] " .. message, 3)
end

local function is_integer(value)
    return type(value) == "number" and value > -math.huge and value < math.huge and value == math.floor(value)
end

local function validate_unknown_keys(value, allowed, path)
    if type(value) ~= "table" then
        return
    end

    for key in pairs(value) do
        if not allowed[key] then
            invalid(string.format("unknown option '%s.%s'", path, tostring(key)))
        end
    end
end

local function validate_shape(overrides)
    for key in pairs(overrides) do
        if not TOP_LEVEL_KEYS[key] then
            invalid(string.format("unknown option '%s'", tostring(key)))
        end
    end

    validate_unknown_keys(overrides.render, NESTED_KEYS.render, "render")
    validate_unknown_keys(overrides.autohide, NESTED_KEYS.autohide, "autohide")
    validate_unknown_keys(overrides.float, NESTED_KEYS.float, "float")
    if type(overrides.float) == "table" then
        validate_unknown_keys(overrides.float.placement, NESTED_KEYS["float.placement"], "float.placement")
    end
    validate_unknown_keys(overrides.layout, NESTED_KEYS.layout, "layout")
    validate_unknown_keys(overrides.track, NESTED_KEYS.track, "track")
    validate_unknown_keys(overrides.mouse, NESTED_KEYS.mouse, "mouse")
    validate_unknown_keys(overrides.thumb, NESTED_KEYS.thumb, "thumb")
    validate_unknown_keys(overrides.providers, NESTED_KEYS.providers, "providers")

    if type(overrides.providers) == "table" and type(overrides.providers.search) == "table" then
        validate_unknown_keys(overrides.providers.search, NESTED_KEYS.search, "providers.search")
    end
    if type(overrides.providers) == "table" and type(overrides.providers.marks) == "table" then
        validate_unknown_keys(overrides.providers.marks, NESTED_KEYS["providers.marks"], "providers.marks")
    end

    if type(overrides.marks) == "table" then
        for mark_type, mark in pairs(overrides.marks) do
            validate_unknown_keys(mark, NESTED_KEYS.mark, "marks." .. tostring(mark_type))
        end
    end
end

local function validate_boolean(value, path)
    if type(value) ~= "boolean" then
        invalid(path .. " must be a boolean")
    end
end

local function validate_integer(value, path, allow_zero)
    if not is_integer(value) or value < (allow_zero and 0 or 1) then
        invalid(path .. (allow_zero and " must be a non-negative integer" or " must be a positive integer"))
    end
end

local function validate_enum(value, path, values)
    if type(value) ~= "string" or not values[value] then
        local names = {}
        for name in pairs(values) do
            table.insert(names, name)
        end
        table.sort(names)
        invalid(string.format("%s must be one of: %s", path, table.concat(names, ", ")))
    end
end

local function dense_count(value, path)
    if type(value) ~= "table" then
        invalid(path .. " must be a dense list")
    end

    local count = 0
    local maximum = 0
    for key in pairs(value) do
        count = count + 1
        if not is_integer(key) or key < 1 then
            invalid(path .. " must be a dense list")
        end
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then
        invalid(path .. " must be a dense list")
    end
    return count
end

local function validate_text(value, path)
    if type(value) ~= "string" then
        invalid(path .. " must be a string")
    end
    if value:find("%c") then
        invalid(path .. " must not contain control characters")
    end

    local ok, width = pcall(vim.fn.strdisplaywidth, value)
    if not ok or width <= 0 then
        invalid(path .. " must have positive display width")
    end
end

local function normalize_highlight(value, path)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if type(value) == "table" then
        return vim.deepcopy(value)
    end
    invalid(path .. " must be a non-empty string or table")
end

local function normalize_text(value, path, allow_empty)
    if type(value) == "string" then
        value = { value }
    elseif type(value) ~= "table" then
        invalid(path .. " must be a string or dense list of strings")
    end

    local count = dense_count(value, path)
    if count == 0 and not allow_empty then
        invalid(path .. " must contain at least one variant")
    end
    for index = 1, count do
        validate_text(value[index], string.format("%s[%d]", path, index))
    end
    return vim.deepcopy(value)
end

local function validate_string_list(value, path)
    local count = dense_count(value, path)
    for index = 1, count do
        if type(value[index]) ~= "string" then
            invalid(string.format("%s[%d] must be a string", path, index))
        end
    end
end

local function normalize_matcher_list(value, path)
    local count = dense_count(value, path)
    if count == 0 then
        invalid(path .. " must contain at least one value")
    end

    local values = {}
    local lookup = {}
    for index = 1, count do
        local item = value[index]
        if type(item) ~= "string" then
            invalid(string.format("%s[%d] must be a string", path, index))
        end
        values[index] = item
        lookup[item] = true
    end
    return values, lookup
end

local function normalize_selector_types(value, path)
    local count = dense_count(value, path)
    if count == 0 then
        invalid(path .. " must contain at least one type")
    end

    local result = {}
    local seen = {}
    for index = 1, count do
        local name = value[index]
        if type(name) ~= "string" then
            invalid(string.format("%s[%d] must be a string", path, index))
        end
        if not name:match("^[%a_][%w_]*$") then
            invalid(string.format("%s[%d] must be a valid mark type", path, index))
        end
        if seen[name] then
            invalid(string.format("%s contains duplicate type '%s'", path, name))
        end
        seen[name] = true
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end

local function normalized_layer(value, path)
    if type(value) == "string" then
        if value == "track" or value == "thumb" then
            return { kind = value }
        end
        if value == "marks" then
            return { kind = "marks", catch_all = true, types = false, max_width = false }
        end
        invalid(path .. " must be 'track', 'thumb', 'marks', or a mark descriptor")
    end
    if type(value) ~= "table" then
        invalid(path .. " must be 'track', 'thumb', 'marks', or a mark descriptor")
    end

    validate_unknown_keys(value, NESTED_KEYS.layer, path)
    if value.kind ~= "marks" then
        invalid(path .. ".kind must be 'marks'")
    end

    ---@type false|string[]
    local types = false
    local catch_all = value.types == nil
    if value.types ~= nil then
        types = normalize_selector_types(value.types, path .. ".types")
    end

    local max_width = false
    if value.max_width ~= nil then
        validate_integer(value.max_width, path .. ".max_width", false)
        local selects_mark = false
        for _, name in ipairs(types or {}) do
            selects_mark = selects_mark or name == "Mark"
        end
        if not selects_mark then
            invalid(path .. ".max_width is valid only for a lane explicitly selecting Mark")
        end
        max_width = value.max_width
    end

    return { kind = "marks", catch_all = catch_all, types = types, max_width = max_width }
end

local function layer_signature(layer)
    if layer.catch_all then
        return "*"
    end
    return table.concat(layer.types, "\0")
end

local function compile_layout(layout, anchor)
    if type(layout) ~= "table" then
        invalid("layout must be a table")
    end
    validate_enum(layout.direction, "layout.direction", ENUMS.direction)
    local width = dense_count(layout.columns, "layout.columns")
    if width == 0 then
        invalid("layout.columns must contain at least one column")
    end

    local logical = {}
    local lanes = {}
    local lane_by_signature = {}
    local type_owner = {}
    local previous_signatures = {}
    local thumb_columns = {}

    for column_index = 1, width do
        local column_path = string.format("layout.columns[%d]", column_index)
        local layer_count = dense_count(layout.columns[column_index], column_path)
        if layer_count == 0 then
            invalid(column_path .. " must contain at least one layer")
        end

        local column = {}
        local current_signatures = {}
        local seen_layers = {}
        for stack_index = 1, layer_count do
            local path = string.format("%s[%d]", column_path, stack_index)
            local layer = normalized_layer(layout.columns[column_index][stack_index], path)
            if layer.kind ~= "marks" then
                if seen_layers[layer.kind] then
                    invalid(path .. " duplicates the " .. layer.kind .. " layer in one column")
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
                    invalid(path .. " duplicates the same mark selector in one column")
                end
                seen_layers[duplicate_key] = true

                local lane_id = previous_signatures[signature]
                if lane_id == nil then
                    if lane_by_signature[signature] ~= nil then
                        local label = layer.catch_all and "catch-all marks" or "mark type '" .. layer.types[1] .. "'"
                        invalid(label .. " must occupy one contiguous lane")
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
                                invalid("mark type '" .. mark_type .. "' must occupy one contiguous lane")
                            end
                            type_owner[mark_type] = lane_id
                        end
                    end
                end

                local lane = lanes[lane_id]
                if layer.max_width ~= false then
                    if lane.max_width ~= false and lane.max_width ~= layer.max_width then
                        invalid(path .. ".max_width conflicts with another value in the same lane")
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
            invalid("thumb must occupy one contiguous span")
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
            invalid("layout mark lane max_width must be greater than or equal to its base lane width")
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

local function normalize_providers(providers)
    for _, name in ipairs({ "cursor", "diagnostic", "gitsigns", "mini_diff", "signify", "vgit", "ale", "coc" }) do
        validate_boolean(providers[name], "providers." .. name)
    end

    local search = providers.search
    if search == true then
        providers.search = { backend = "worker" }
    elseif type(search) == "table" then
        if search.backend == nil then
            search.backend = "worker"
        end
        if search.incsearch ~= nil then
            validate_boolean(search.incsearch, "providers.search.incsearch")
        end
        validate_enum(search.backend, "providers.search.backend", ENUMS.search_backend)
    elseif search ~= false then
        invalid("providers.search must be a boolean or table")
    end

    local marks = providers.marks
    if marks == true then
        providers.marks = { letters = true, numbers = false }
    elseif type(marks) == "table" then
        if marks.letters == nil then
            marks.letters = true
        end
        if marks.numbers == nil then
            marks.numbers = false
        end
        validate_boolean(marks.letters, "providers.marks.letters")
        validate_boolean(marks.numbers, "providers.marks.numbers")
    elseif marks ~= false then
        invalid("providers.marks must be a boolean or table")
    end
end

local function layout_config(value)
    local marks = {}
    for mark_type, mark in pairs(value.marks) do
        marks[mark_type] = {
            text = mark.text,
            priority = mark.priority,
        }
    end
    return { geometry = value.render.geometry, layout = value.layout.cache, marks = marks }
end

local function variants_layout_config(compiled)
    local result = {}
    for index, variant in ipairs(compiled) do
        result[index] = variant.config.layout_cache
    end
    return result
end

local function validate_profile_config(value, path)
    if type(value) ~= "table" then
        invalid(path .. " must be a table")
    end
    validate_unknown_keys(value, PROFILE_CONFIG_KEYS, path)
    validate_unknown_keys(value.render, PROFILE_NESTED_KEYS.render, path .. ".render")
    validate_unknown_keys(value.float, PROFILE_NESTED_KEYS.float, path .. ".float")
    if type(value.float) == "table" then
        validate_unknown_keys(value.float.placement, PROFILE_NESTED_KEYS["float.placement"], path .. ".float.placement")
    end
    validate_unknown_keys(value.layout, PROFILE_NESTED_KEYS.layout, path .. ".layout")
    validate_unknown_keys(value.track, PROFILE_NESTED_KEYS.track, path .. ".track")
    validate_unknown_keys(value.mouse, PROFILE_NESTED_KEYS.mouse, path .. ".mouse")
    validate_unknown_keys(value.thumb, PROFILE_NESTED_KEYS.thumb, path .. ".thumb")
    if type(value.marks) == "table" then
        for mark_type, mark in pairs(value.marks) do
            validate_unknown_keys(mark, PROFILE_NESTED_KEYS.mark, path .. ".marks." .. tostring(mark_type))
        end
    end
end

local function compile_profiles(value)
    if value == nil then
        return {}
    end

    local count = dense_count(value, "profiles")
    local result = {}
    for index = 1, count do
        local path = string.format("profiles[%d]", index)
        local profile = value[index]
        if type(profile) ~= "table" then
            invalid(path .. " must be a table")
        end
        validate_unknown_keys(profile, PROFILE_KEYS, path)
        if type(profile.match) ~= "table" then
            invalid(path .. ".match must be a table")
        end
        validate_unknown_keys(profile.match, PROFILE_MATCH_KEYS, path .. ".match")
        if profile.match.filetypes == nil and profile.match.buftypes == nil and profile.match.when == nil then
            invalid(path .. ".match must contain at least one matcher")
        end

        ---@type ScrollbarCompiledMatcher
        local matcher = {
            filetypes = false,
            filetype_lookup = false,
            buftypes = false,
            buftype_lookup = false,
            when = false,
        }
        if profile.match.filetypes ~= nil then
            matcher.filetypes, matcher.filetype_lookup =
                normalize_matcher_list(profile.match.filetypes, path .. ".match.filetypes")
        end
        if profile.match.buftypes ~= nil then
            matcher.buftypes, matcher.buftype_lookup =
                normalize_matcher_list(profile.match.buftypes, path .. ".match.buftypes")
        end
        if profile.match.when ~= nil then
            if type(profile.match.when) ~= "function" then
                invalid(path .. ".match.when must be a function")
            end
            matcher.when = profile.match.when
        end
        if profile.preset ~= nil and type(profile.preset) ~= "string" then
            invalid(path .. ".preset must be a string")
        end
        if profile.config ~= nil then
            validate_profile_config(profile.config, path .. ".config")
        end

        result[index] = {
            matcher = matcher,
            preset = profile.preset,
            overrides = vim.deepcopy(profile.config or {}),
        }
    end
    return result
end

local function normalize(overrides)
    local resolved = presets.resolve(overrides)
    validate_shape(resolved)
    local result = presets.merge(DEFAULTS, resolved)

    validate_boolean(result.show, "show")
    validate_boolean(result.set_highlights, "set_highlights")
    validate_boolean(result.hide_if_all_visible, "hide_if_all_visible")
    validate_enum(result.visibility, "visibility", ENUMS.visibility)
    if result.max_lines ~= false and (not is_integer(result.max_lines) or result.max_lines < 1) then
        invalid("max_lines must be false or a positive integer")
    end

    if type(result.autohide) ~= "table" then
        invalid("autohide must be a table")
    end
    validate_boolean(result.autohide.enabled, "autohide.enabled")
    validate_integer(result.autohide.delay_ms, "autohide.delay_ms", false)

    if type(result.render) ~= "table" then
        invalid("render must be a table")
    end
    validate_integer(result.render.interval_ms, "render.interval_ms", true)
    validate_enum(result.render.geometry, "render.geometry", ENUMS.geometry)

    if type(result.float) ~= "table" then
        invalid("float must be a table")
    end
    validate_integer(result.float.zindex, "float.zindex", false)
    validate_boolean(result.float.hide_on_cursor, "float.hide_on_cursor")
    if type(result.float.placement) ~= "table" then
        invalid("float.placement must be a table")
    end
    validate_enum(result.float.placement.relative, "float.placement.relative", ENUMS.relative)
    validate_enum(result.float.placement.anchor, "float.placement.anchor", ENUMS.anchor)
    if not is_integer(result.float.placement.row) then
        invalid("float.placement.row must be an integer")
    end
    if not is_integer(result.float.placement.col) then
        invalid("float.placement.col must be an integer")
    end

    result.layout = compile_layout(result.layout, result.float.placement.anchor)

    if type(result.track) ~= "table" then
        invalid("track must be a table")
    end
    result.track.highlight = normalize_highlight(result.track.highlight, "track.highlight")

    if type(result.mouse) ~= "table" then
        invalid("mouse must be a table")
    end
    validate_boolean(result.mouse.enabled, "mouse.enabled")

    if type(result.thumb) ~= "table" then
        invalid("thumb must be a table")
    end
    validate_text(result.thumb.text, "thumb.text")
    validate_integer(result.thumb.blend, "thumb.blend", true)
    if result.thumb.blend > 100 then
        invalid("thumb.blend must be between 0 and 100")
    end
    result.thumb.highlight = normalize_highlight(result.thumb.highlight, "thumb.highlight")
    validate_boolean(result.thumb.hide_if_all_visible, "thumb.hide_if_all_visible")

    if type(result.marks) ~= "table" then
        invalid("marks must be a table")
    end
    for mark_type, mark in pairs(result.marks) do
        if type(mark_type) ~= "string" or not mark_type:match("^[%a_][%w_]*$") then
            invalid(string.format("invalid mark type %s", vim.inspect(mark_type)))
        end
        if type(mark) ~= "table" then
            invalid("marks." .. mark_type .. " must be a table")
        end

        local path = "marks." .. mark_type
        mark.text = normalize_text(mark.text, path .. ".text", mark_type == "Mark")
        validate_integer(mark.priority, path .. ".priority", true)
        mark.highlight = normalize_highlight(mark.highlight, path .. ".highlight")
    end

    if type(result.providers) ~= "table" then
        invalid("providers must be a table")
    end
    normalize_providers(result.providers)
    validate_string_list(result.excluded_buftypes, "excluded_buftypes")
    validate_string_list(result.excluded_filetypes, "excluded_filetypes")
    return result
end

local function compile(overrides)
    if overrides == nil then
        overrides = {}
    elseif type(overrides) ~= "table" then
        invalid("configuration must be a table")
    end

    local setup = vim.deepcopy(overrides)
    local compiled_profiles = compile_profiles(setup.profiles)
    setup.profiles = nil
    local root = normalize(setup)
    local compiled = {
        { id = 0, matcher = false, config = root },
    }

    for index, profile in ipairs(compiled_profiles) do
        local variant_options = vim.deepcopy(setup)
        variant_options.preset = profile.preset or setup.preset
        variant_options = presets.merge(variant_options, profile.overrides)
        compiled[#compiled + 1] = {
            id = index,
            matcher = profile.matcher,
            config = normalize(variant_options),
        }
    end
    for _, variant in ipairs(compiled) do
        variant.config.highlights = utils.get_highlight_groups(variant.config, variant.id, root.set_highlights)
        variant.config.layout_cache = layout_config(variant.config)
    end
    return root, compiled
end

local M = {}

---@param overrides? ScrollbarUserConfig
---@return ScrollbarConfig
M.set = function(overrides)
    local normalized, compiled = compile(overrides)
    if variants ~= nil and not vim.deep_equal(variants_layout_config(variants), variants_layout_config(compiled)) then
        layout_generation = layout_generation + 1
    end
    active = normalized
    variants = compiled
    profile_error_notifications = {}
    return active
end

---@return ScrollbarConfig
M.get = function()
    if active == nil then
        M.set()
    end
    return assert(active, "active scrollbar config unavailable")
end

---@return ScrollbarCompiledVariant[]
M.get_variants = function()
    M.get()
    return assert(variants, "compiled scrollbar variants unavailable")
end

---@param source_win integer
---@return ScrollbarConfigSelection
M.select = function(source_win)
    local root = M.get()
    local compiled = assert(variants, "compiled scrollbar variants unavailable")
    local source_buf = vim.api.nvim_win_get_buf(source_win)
    local context = {
        winid = source_win,
        bufnr = source_buf,
        filetype = vim.bo[source_buf].filetype,
        buftype = vim.bo[source_buf].buftype,
        bufname = vim.api.nvim_buf_get_name(source_buf),
    }

    for index = 2, #compiled do
        local variant = compiled[index]
        local matcher = variant.matcher
        assert(matcher ~= false, "compiled scrollbar profile matcher unavailable")
        ---@cast matcher ScrollbarCompiledMatcher
        local filetype_lookup = matcher.filetype_lookup
        local buftype_lookup = matcher.buftype_lookup
        local when = matcher.when
        if
            (filetype_lookup == false or filetype_lookup[context.filetype])
            and (buftype_lookup == false or buftype_lookup[context.buftype])
        then
            if when ~= false then
                local ok, matched = pcall(when, context)
                if not ok then
                    local message = tostring(matched)
                    local notification_key = variant.id .. "\0" .. message
                    if not profile_error_notifications[notification_key] then
                        profile_error_notifications[notification_key] = true
                        vim.notify(
                            string.format("[scrollbar.nvim] profile %d matcher failed: %s", variant.id, message),
                            vim.log.levels.ERROR
                        )
                    end
                    return { config = root, variant_id = 0 }
                end
                if matched then
                    return { config = variant.config, variant_id = variant.id }
                end
            else
                return { config = variant.config, variant_id = variant.id }
            end
        end
    end
    return { config = root, variant_id = 0 }
end

---@return integer
M.get_layout_generation = function()
    return layout_generation
end

return M
