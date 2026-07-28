--- Minimap subsystem configuration. Mirrors the strict-whitelist validation
--- pattern of `lua/scrollbar/config.lua` with a minimap-specific schema. Owns
--- its own active config and compiled profile variants so the minimap lifecycle
--- is independent of the scrollbar's. The top-level dispatcher
--- (`lua/scrollbar/config.lua`) delegates `minimap` slice handling here.

local minimap_presets = require("scrollbar.minimap.presets")
local provider_config = require("scrollbar.provider_config")

local DEFAULT_EVENTS = {
    "BufEnter",
    "BufWinEnter",
    "WinEnter",
    "WinScrolled",
    "WinResized",
    "VimResized",
    "CursorMoved",
    "CursorMovedI",
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "TextChangedT",
    "WinClosed",
    "BufDelete",
    "BufWipeout",
    "ColorScheme",
}

local ALLOWED_EVENTS = {}
do
    local all_events = {
        "BufEnter",
        "BufWinEnter",
        "WinEnter",
        "TabEnter",
        "TermEnter",
        "CmdwinLeave",
        "CursorMoved",
        "CursorMovedI",
        "TextChanged",
        "TextChangedI",
        "TextChangedP",
        "TextChangedT",
        "WinScrolled",
        "WinResized",
        "VimResized",
        "OptionSet",
        "ColorScheme",
        "WinClosed",
        "BufDelete",
        "BufWipeout",
        "TabClosed",
    }
    for _, event in ipairs(all_events) do
        ALLOWED_EVENTS[event] = true
    end
end

local DEFAULT_OVERLAY_TYPES = {
    Error = { priority = 2, highlight = "DiagnosticVirtualTextError" },
    GitAdd = { priority = 7, highlight = "GitSignsAdd" },
    GitChange = { priority = 7, highlight = "GitSignsChange" },
    GitDelete = { priority = 7, highlight = "GitSignsDelete" },
    Hint = { priority = 5, highlight = "DiagnosticVirtualTextHint" },
    Info = { priority = 4, highlight = "DiagnosticVirtualTextInfo" },
    Mark = { priority = 1, highlight = "Special" },
    MiniDiffAdd = { priority = 7, highlight = "MiniDiffSignAdd" },
    MiniDiffChange = { priority = 7, highlight = "MiniDiffSignChange" },
    MiniDiffDelete = { priority = 7, highlight = "MiniDiffSignDelete" },
    Misc = { priority = 6, highlight = "Normal" },
    Search = { priority = 1, highlight = "Search" },
    SignifyAdd = { priority = 7, highlight = "SignifySignAdd" },
    SignifyChange = { priority = 7, highlight = "SignifySignChange" },
    SignifyDelete = { priority = 7, highlight = "SignifySignDelete" },
    VGitAdd = { priority = 7, highlight = "GitSignsAdd" },
    VGitChange = { priority = 7, highlight = "GitSignsChange" },
    VGitDelete = { priority = 7, highlight = "GitSignsDelete" },
    Warn = { priority = 3, highlight = "DiagnosticVirtualTextWarn" },
}

local DEFAULTS = {
    enabled = false,
    visibility = "all",
    set_highlights = true,
    max_lines = false,
    autohide = {
        enabled = false,
        delay_ms = 1000,
    },
    background = {
        blend = false,
    },
    float = {
        zindex = 50,
        blend = 0,
        hide_on_cursor = true,
        placement = {
            relative = "window",
            anchor = "NE",
            row = 0,
            col = 0,
            gutter = "overlap",
            gutter_position = "inner",
        },
    },
    width = 16,
    height = false,
    mouse = {
        enabled = true,
    },
    backend = "worker",
    update = {
        events = vim.deepcopy(DEFAULT_EVENTS),
        interval_ms = 50,
    },
    excluded_buftypes = {},
    excluded_filetypes = {},
    overlays = {
        enabled = true,
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
        treesitter = false,
        lsp_semantic_tokens = false,
    },
    show_viewport = true,
    content_glyphs = { top = "▀", bottom = "▄", both = "█" },
}

local TOP_LEVEL_KEYS = {
    enabled = true,
    visibility = true,
    set_highlights = true,
    max_lines = true,
    autohide = true,
    background = true,
    float = true,
    width = true,
    height = true,
    mouse = true,
    backend = true,
    update = true,
    excluded_buftypes = true,
    excluded_filetypes = true,
    overlays = true,
    providers = true,
    show_viewport = true,
    content_glyphs = true,
}

local NESTED_KEYS = {
    autohide = { enabled = true, delay_ms = true },
    background = { blend = true },
    update = { events = true, interval_ms = true },
    float = { zindex = true, blend = true, hide_on_cursor = true, placement = true },
    ["float.placement"] = {
        relative = true,
        anchor = true,
        row = true,
        col = true,
        gutter = true,
        gutter_position = true,
    },
    mouse = { enabled = true },
    overlays = { enabled = true, types = true },
}

local OVERLAY_SPEC_KEYS = {
    priority = true,
    highlight = true,
}

local STATIC_HIGHLIGHT_TYPES = {
    Base = true,
    Content = true,
    Viewport = true,
    Cursor = true,
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
    width = true,
    height = true,
    float = true,
    overlays = true,
    show_viewport = true,
    mouse = true,
    content_glyphs = true,
}

local PROFILE_NESTED_KEYS = {
    float = NESTED_KEYS.float,
    ["float.placement"] = NESTED_KEYS["float.placement"],
    overlays = NESTED_KEYS.overlays,
    mouse = NESTED_KEYS.mouse,
}

local ENUMS = {
    visibility = { all = true, active = true },
    relative = { window = true, editor = true },
    anchor = { NW = true, NE = true, SW = true, SE = true },
    gutter = { avoid = true, overlap = true },
    gutter_position = { inner = true, outer = true },
    backend = { worker = true, sync = true },
}

---@type ScrollbarMinimapConfig?
local active
---@type ScrollbarMinimapCompiledVariant[]?
local variants
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
            invalid(string.format("unknown option 'minimap.%s'", tostring(key)))
        end
    end

    validate_unknown_keys(overrides.update, NESTED_KEYS.update, "minimap.update")
    validate_unknown_keys(overrides.autohide, NESTED_KEYS.autohide, "minimap.autohide")
    validate_unknown_keys(overrides.background, NESTED_KEYS.background, "minimap.background")
    validate_unknown_keys(overrides.float, NESTED_KEYS.float, "minimap.float")
    if type(overrides.float) == "table" then
        validate_unknown_keys(overrides.float.placement, NESTED_KEYS["float.placement"], "minimap.float.placement")
    end
    validate_unknown_keys(overrides.mouse, NESTED_KEYS.mouse, "minimap.mouse")
    validate_unknown_keys(overrides.overlays, NESTED_KEYS.overlays, "minimap.overlays")
    provider_config.validate_shape(overrides.providers, provider_config.MINIMAP_NAMES, "minimap.providers")
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

local function normalize_highlight(value, path)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if type(value) == "table" then
        return vim.deepcopy(value)
    end
    invalid(path .. " must be a non-empty string or table")
end

local function validate_overlay_types(value, path)
    if type(value) ~= "table" then
        invalid(path .. " must be a table")
    end
    for mark_type, spec in pairs(value) do
        if type(mark_type) ~= "string" or not mark_type:match("^[%a_][%w_]*$") then
            invalid(path .. " keys must be valid mark types")
        end
        local spec_path = path .. "." .. mark_type
        if spec ~= false then
            if type(spec) ~= "table" then
                invalid(spec_path .. " must be false or a table")
            end
            validate_unknown_keys(spec, OVERLAY_SPEC_KEYS, spec_path)
            if spec.priority ~= nil then
                validate_integer(spec.priority, spec_path .. ".priority", true)
            end
            if spec.highlight ~= nil then
                normalize_highlight(spec.highlight, spec_path .. ".highlight")
            end
        end
    end
end

local function normalize_overlay_types(value, defaults, path)
    validate_overlay_types(value, path)
    local merged = minimap_presets.merge(defaults, value)
    local result = {}
    for mark_type, spec in pairs(merged) do
        if spec ~= false then
            local spec_path = path .. "." .. mark_type
            if STATIC_HIGHLIGHT_TYPES[mark_type] then
                invalid(spec_path .. " conflicts with the static ScrollbarMinimap" .. mark_type .. " group")
            end
            if type(spec) ~= "table" then
                invalid(spec_path .. " must be false or a table")
            end
            validate_unknown_keys(spec, OVERLAY_SPEC_KEYS, spec_path)
            if spec.priority == nil then
                invalid(spec_path .. ".priority is required")
            end
            validate_integer(spec.priority, spec_path .. ".priority", true)
            if spec.highlight == nil then
                invalid(spec_path .. ".highlight is required")
            end
            result[mark_type] = {
                priority = spec.priority,
                highlight = normalize_highlight(spec.highlight, spec_path .. ".highlight"),
            }
        end
    end
    return result
end

local function overlay_group_name(mark_type, variant_id, automatic)
    local prefix = "ScrollbarMinimap"
    if automatic and variant_id > 0 then
        prefix = prefix .. "Profile" .. variant_id .. "."
    end
    return prefix .. mark_type
end

local function normalize_placement(value)
    return {
        relative = value.relative,
        anchor = value.anchor,
        row = value.row,
        col = value.col,
        gutter = value.gutter,
        gutter_position = value.gutter_position,
    }
end

local function validate_profile_config(value, path)
    if type(value) ~= "table" then
        invalid(path .. " must be a table")
    end
    validate_unknown_keys(value, PROFILE_CONFIG_KEYS, path)
    validate_unknown_keys(value.float, PROFILE_NESTED_KEYS.float, path .. ".float")
    if type(value.float) == "table" then
        validate_unknown_keys(value.float.placement, PROFILE_NESTED_KEYS["float.placement"], path .. ".float.placement")
    end
    validate_unknown_keys(value.overlays, PROFILE_NESTED_KEYS.overlays, path .. ".overlays")
    validate_unknown_keys(value.mouse, PROFILE_NESTED_KEYS.mouse, path .. ".mouse")
end

local function compile_profiles(value)
    if value == nil then
        return {}
    end

    local count = dense_count(value, "minimap.profiles")
    local result = {}
    for index = 1, count do
        local path = string.format("minimap.profiles[%d]", index)
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

local function validate_dimension(value, path)
    if value == false then
        return false
    end
    if not is_integer(value) or value < 1 then
        invalid(path .. " must be false or a positive integer")
    end
    return value
end

local function normalize(overrides, default_overlay_types)
    local resolved = minimap_presets.resolve(overrides)
    validate_shape(resolved)
    local result = minimap_presets.merge(DEFAULTS, resolved)

    validate_boolean(result.enabled, "minimap.enabled")
    validate_enum(result.visibility, "minimap.visibility", ENUMS.visibility)
    validate_boolean(result.set_highlights, "minimap.set_highlights")
    if result.max_lines ~= false and (not is_integer(result.max_lines) or result.max_lines < 1) then
        invalid("minimap.max_lines must be false or a positive integer")
    end
    result.width = validate_dimension(result.width, "minimap.width")
    result.height = validate_dimension(result.height, "minimap.height")

    if type(result.autohide) ~= "table" then
        invalid("minimap.autohide must be a table")
    end
    validate_boolean(result.autohide.enabled, "minimap.autohide.enabled")
    validate_integer(result.autohide.delay_ms, "minimap.autohide.delay_ms", false)

    if type(result.background) ~= "table" then
        invalid("minimap.background must be a table")
    end
    if
        result.background.blend ~= false
        and (not is_integer(result.background.blend) or result.background.blend < 0)
    then
        invalid("minimap.background.blend must be false or an integer in 0..100")
    end
    if result.background.blend ~= false and result.background.blend > 100 then
        invalid("minimap.background.blend must be at most 100")
    end

    if type(result.update) ~= "table" then
        invalid("minimap.update must be a table")
    end
    validate_integer(result.update.interval_ms, "minimap.update.interval_ms", true)
    local event_count = dense_count(result.update.events, "minimap.update.events")
    if event_count == 0 then
        invalid("minimap.update.events must contain at least one event")
    end
    local seen_events = {}
    for index = 1, event_count do
        local event = result.update.events[index]
        if type(event) ~= "string" then
            invalid(string.format("minimap.update.events[%d] must be a string", index))
        end
        if not ALLOWED_EVENTS[event] then
            invalid(string.format("minimap.update.events[%d] unknown event '%s'", index, event))
        end
        if seen_events[event] then
            invalid(string.format("minimap.update.events[%d] duplicate event '%s'", index, event))
        end
        seen_events[event] = true
    end

    if type(result.float) ~= "table" then
        invalid("minimap.float must be a table")
    end
    validate_integer(result.float.zindex, "minimap.float.zindex", false)
    validate_integer(result.float.blend, "minimap.float.blend", true)
    if result.float.blend > 100 then
        invalid("minimap.float.blend must be at most 100")
    end
    validate_boolean(result.float.hide_on_cursor, "minimap.float.hide_on_cursor")
    if type(result.float.placement) ~= "table" then
        invalid("minimap.float.placement must be a table")
    end
    validate_enum(result.float.placement.relative, "minimap.float.placement.relative", ENUMS.relative)
    validate_enum(result.float.placement.anchor, "minimap.float.placement.anchor", ENUMS.anchor)
    validate_enum(result.float.placement.gutter, "minimap.float.placement.gutter", ENUMS.gutter)
    validate_enum(
        result.float.placement.gutter_position,
        "minimap.float.placement.gutter_position",
        ENUMS.gutter_position
    )
    if not is_integer(result.float.placement.row) then
        invalid("minimap.float.placement.row must be an integer")
    end
    if not is_integer(result.float.placement.col) then
        invalid("minimap.float.placement.col must be an integer")
    end
    result.float.placement = normalize_placement(result.float.placement)

    if type(result.mouse) ~= "table" then
        invalid("minimap.mouse must be a table")
    end
    validate_boolean(result.mouse.enabled, "minimap.mouse.enabled")

    validate_enum(result.backend, "minimap.backend", ENUMS.backend)

    if type(result.overlays) ~= "table" then
        invalid("minimap.overlays must be a table")
    end
    validate_boolean(result.overlays.enabled, "minimap.overlays.enabled")
    result.overlays.types =
        normalize_overlay_types(result.overlays.types or {}, default_overlay_types, "minimap.overlays.types")

    local provider_requests
    result.providers, provider_requests =
        provider_config.normalize(result.providers, provider_config.MINIMAP_NAMES, "minimap.providers")

    validate_boolean(result.show_viewport, "minimap.show_viewport")

    if type(result.content_glyphs) ~= "table" then
        invalid("minimap.content_glyphs must be a table")
    end
    for _, key in ipairs({ "top", "bottom", "both" }) do
        local glyph = result.content_glyphs[key]
        if type(glyph) ~= "string" or glyph == "" then
            invalid(string.format("minimap.content_glyphs.%s must be a non-empty string", key))
        elseif vim.fn.strdisplaywidth(glyph) ~= 1 then
            invalid(string.format("minimap.content_glyphs.%s must be a single-width glyph", key))
        end
    end
    for key in pairs(result.content_glyphs) do
        if key ~= "top" and key ~= "bottom" and key ~= "both" then
            invalid(string.format("unknown option 'minimap.content_glyphs.%s'", tostring(key)))
        end
    end

    validate_string_list(result.excluded_buftypes, "minimap.excluded_buftypes")
    validate_string_list(result.excluded_filetypes, "minimap.excluded_filetypes")
    return result, provider_requests
end

local function compile(overrides, scrollbar_mark_types)
    if overrides == nil then
        overrides = {}
    elseif type(overrides) ~= "table" then
        invalid("minimap must be a table")
    end

    local default_overlay_types = vim.deepcopy(scrollbar_mark_types or DEFAULT_OVERLAY_TYPES)

    local setup = vim.deepcopy(overrides)
    local compiled_profiles = compile_profiles(setup.profiles)
    setup.profiles = nil
    local root, provider_requests = normalize(setup, default_overlay_types)
    local compiled = {
        { id = 0, matcher = false, config = root },
    }

    for index, profile in ipairs(compiled_profiles) do
        local variant_options = vim.deepcopy(setup)
        variant_options.preset = profile.preset or setup.preset
        variant_options = minimap_presets.merge(variant_options, profile.overrides)
        local variant_config = normalize(variant_options, default_overlay_types)
        compiled[#compiled + 1] = {
            id = index,
            matcher = profile.matcher,
            config = variant_config,
        }
    end
    for _, variant in ipairs(compiled) do
        for mark_type, spec in pairs(variant.config.overlays.types) do
            spec.group = overlay_group_name(mark_type, variant.id, root.set_highlights)
        end
    end
    return root, compiled, provider_requests
end

local M = {}

---@param overrides? ScrollbarMinimapUserConfig
---@param scrollbar_mark_types? table<string, ScrollbarMinimapOverlaySpec>
---@return ScrollbarMinimapConfig, ScrollbarMinimapCompiledVariant[], table<string, "boolean"|"table">
M._compile = function(overrides, scrollbar_mark_types)
    return compile(overrides, scrollbar_mark_types)
end

---@param root ScrollbarMinimapConfig
---@param compiled ScrollbarMinimapCompiledVariant[]
M._commit = function(root, compiled)
    active = root
    variants = compiled
    profile_error_notifications = {}
end

---@param overrides? ScrollbarMinimapUserConfig
---@return ScrollbarMinimapConfig
M.set = function(overrides)
    local root, compiled = M._compile(overrides)
    M._commit(root, compiled)
    return root
end

---@return ScrollbarMinimapConfig
M.get = function()
    if active == nil then
        M.set()
    end
    return assert(active, "active minimap config unavailable")
end

---@return ScrollbarMinimapCompiledVariant[]
M.get_variants = function()
    M.get()
    return assert(variants, "compiled minimap variants unavailable")
end

---@param source_win integer
---@return ScrollbarMinimapConfigSelection
M.select = function(source_win)
    local root = M.get()
    local compiled = assert(variants, "compiled minimap variants unavailable")
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
        assert(matcher ~= false, "compiled minimap profile matcher unavailable")
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
                            string.format("[scrollbar.nvim] minimap profile %d matcher failed: %s", variant.id, message),
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

return M
