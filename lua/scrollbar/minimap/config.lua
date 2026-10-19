--- Minimap block of the configuration. The top-level dispatcher
--- (`lua/scrollbar/config.lua`) compiles it with the shared sections and
--- commits it together with the scrollbar block.

local schema = require("scrollbar.schema")
local shared_config = require("scrollbar.shared_config")

local invalid = schema.invalid

local DEFAULTS = {
    enabled = false,
    show = true,
    visibility = "all",
    autohide = false,
    max_lines = false,
    throttle_ms = 50,
    backend = "worker",
    background_blend = false,
    width = 16,
    height = false,
    placement = {
        relative = "window",
        anchor = "NE",
        row = 0,
        col = 0,
        zindex = 50,
        stack = "inner",
    },
    blend = 0,
    hide_on_cursor = true,
    mouse = true,
    viewport = true,
    glyph = "█",
    marks = {},
}

local AUTOHIDE_DEFAULTS = { delay_ms = 1000 }

local GLOBAL_KEYS = {
    enabled = true,
    show = true,
    visibility = true,
    autohide = { delay_ms = true },
    max_lines = true,
    throttle_ms = true,
    backend = true,
    background_blend = true,
}

local APPEARANCE_KEYS = {
    width = true,
    height = true,
    placement = {
        relative = true,
        anchor = true,
        row = true,
        col = true,
        zindex = true,
        stack = true,
    },
    blend = true,
    hide_on_cursor = true,
    mouse = true,
    viewport = true,
    glyph = true,
    marks = { ["*"] = { priority = true, highlight = true } },
}

local ROOT_KEYS = vim.tbl_extend("error", GLOBAL_KEYS, APPEARANCE_KEYS, { profiles = true })
local PROFILE_KEYS = vim.tbl_extend("error", APPEARANCE_KEYS, { match = true })

-- These names belong to the static ScrollbarMinimap<Name> groups.
local REJECTED_MARK_TYPES = {
    Cursor = "the minimap draws the cursor with ScrollbarMinimapCursor. "
        .. "To hide it, set providers.cursor = { minimap = false }",
    Base = "conflicts with the static ScrollbarMinimapBase group",
    Content = "conflicts with the static ScrollbarMinimapContent group",
    Viewport = "conflicts with the static ScrollbarMinimapViewport group",
}

---@type ScrollbarMinimapConfig?
local active
---@type ScrollbarMinimapCompiledVariant[]?
local variants
local selector = schema.selector("minimap")

---@param mark_type string
---@param variant_id integer
---@param automatic boolean
---@return string
local function mark_group_name(mark_type, variant_id, automatic)
    local prefix = "ScrollbarMinimap"
    if automatic and variant_id > 0 then
        prefix = prefix .. "Profile" .. variant_id .. "."
    end
    return prefix .. mark_type
end

-- Replacements for the v1 options, shown in the unknown-option error.
local REMOVED_KEYS = {
    presets = "the minimap has no presets",
    update = "use 'throttle_ms'. The update events are fixed",
    float = "use 'placement', 'placement.zindex', 'blend', and 'hide_on_cursor'",
    background = "use 'background_blend'",
    overlays = "use 'marks = false' to hide the overlays",
    show_viewport = "use 'viewport'",
    content_glyph = "use 'glyph'",
    excluded_buftypes = "use the top-level 'exclude' table",
    excluded_filetypes = "use the top-level 'exclude' table",
    providers = "use the top-level 'providers' table",
    set_highlights = "use the top-level 'set_highlights' option",
    ["autohide.enabled"] = "use 'autohide = true' or 'autohide = { delay_ms = n }'",
    ["placement.gutter"] = "the minimap always overlaps the gutter",
    ["placement.gutter_position"] = "the minimap always overlaps the gutter",
}

local describe_root_key = schema.hinter(REMOVED_KEYS, function(relative, path)
    if relative == "preset" then
        return path .. ": the minimap has no presets"
    end
end)

local describe_profile_key = schema.hinter(REMOVED_KEYS, function(relative, path)
    if GLOBAL_KEYS[relative] ~= nil or relative == "profiles" then
        return path .. " is a global option and cannot be set in a profile"
    end
    return describe_root_key(relative, path)
end)

---@param value any
---@return { matcher: ScrollbarCompiledMatcher, input: table, path: string }[]
local function compile_profiles(value)
    if value == nil then
        return {}
    end

    local count = schema.dense_count(value, "minimap.profiles")
    local result = {}
    for index = 1, count do
        local path = string.format("minimap.profiles[%d]", index)
        local profile = value[index]
        schema.table(profile, path)
        schema.check_keys(profile, PROFILE_KEYS, path, describe_profile_key)
        if profile.match == nil then
            invalid(path .. ".match is required")
        end
        result[index] = {
            matcher = schema.matcher(profile.match, path .. ".match"),
            input = profile,
            path = path,
        }
    end
    return result
end

---@param value any
---@param path string
---@return false|integer
local function blend_or_false(value, path)
    if value == false then
        return false
    end
    if not schema.is_integer(value) or value < 0 or value > 100 then
        invalid(path .. " must be false or an integer between 0 and 100")
    end
    return value
end

---@param value table Layered options merged onto the defaults
---@param shared ScrollbarSharedConfig
---@param path string Prefix for error paths
---@return ScrollbarMinimapConfig
local function normalize(value, shared, path)
    local function at(name)
        return path .. "." .. name
    end

    local autohide = schema.feature(value.autohide, at("autohide"), AUTOHIDE_DEFAULTS)
    if autohide then
        schema.integer(autohide.delay_ms, at("autohide.delay_ms"), 1)
    end

    local placement = schema.table(value.placement, at("placement"))
    if type(value.glyph) ~= "string" or value.glyph == "" then
        invalid(at("glyph") .. " must be a non-empty string")
    elseif vim.fn.strdisplaywidth(value.glyph) ~= 1 then
        invalid(at("glyph") .. " must be a single-width glyph")
    end

    ---@type ScrollbarMinimapConfig
    local result = {
        enabled = schema.boolean(value.enabled, at("enabled")),
        show = schema.boolean(value.show, at("show")),
        visibility = schema.enum(value.visibility, at("visibility"), { "all", "active" }),
        autohide = autohide,
        max_lines = schema.positive_or_false(value.max_lines, at("max_lines")),
        throttle_ms = schema.integer(value.throttle_ms, at("throttle_ms"), 0),
        backend = schema.enum(value.backend, at("backend"), { "worker", "sync" }),
        background_blend = blend_or_false(value.background_blend, at("background_blend")),
        set_highlights = shared.set_highlights,
        exclude = shared.exclude.minimap,
        width = schema.integer(value.width, at("width"), 1),
        height = schema.positive_or_false(value.height, at("height")),
        placement = {
            relative = schema.enum(placement.relative, at("placement.relative"), { "window", "editor" }),
            anchor = schema.enum(placement.anchor, at("placement.anchor"), { "NW", "NE", "SW", "SE" }),
            row = schema.integer(placement.row, at("placement.row")),
            col = schema.integer(placement.col, at("placement.col")),
            zindex = schema.integer(placement.zindex, at("placement.zindex"), 1),
            stack = schema.enum(placement.stack, at("placement.stack"), { "inner", "outer", "above", "below" }),
        },
        blend = schema.integer(value.blend, at("blend"), 0, 100),
        hide_on_cursor = schema.boolean(value.hide_on_cursor, at("hide_on_cursor")),
        mouse = schema.boolean(value.mouse, at("mouse")),
        viewport = schema.boolean(value.viewport, at("viewport")),
        glyph = value.glyph,
        marks = shared_config.resolve_marks(shared.marks, value.marks, at("marks"), {
            fields = { "priority", "highlight" },
            reject = REJECTED_MARK_TYPES,
        }),
    }
    return result
end

---@param overrides any
---@param shared ScrollbarSharedConfig
---@return ScrollbarMinimapConfig, ScrollbarMinimapCompiledVariant[]
local function compile(overrides, shared)
    if overrides == nil then
        overrides = {}
    end
    schema.table(overrides, "minimap")
    schema.check_keys(overrides, ROOT_KEYS, "minimap", describe_root_key)

    local profiles = compile_profiles(overrides.profiles)
    local root_options = schema.without(overrides, { "profiles" })
    local root = normalize(schema.merge(DEFAULTS, root_options), shared, "minimap")
    local compiled = {
        { id = 0, matcher = false, config = root },
    }
    for index, profile in ipairs(profiles) do
        local options = schema.merge(root_options, schema.without(profile.input, { "match" }))
        compiled[#compiled + 1] = {
            id = index,
            matcher = profile.matcher,
            config = normalize(schema.merge(DEFAULTS, options), shared, profile.path),
        }
    end
    for _, variant in ipairs(compiled) do
        for mark_type, spec in pairs(variant.config.marks) do
            spec.group = mark_group_name(mark_type, variant.id, shared.set_highlights)
        end
    end
    return root, compiled
end

local M = {}

---@param overrides? ScrollbarMinimapUserConfig
---@param shared ScrollbarSharedConfig
---@return ScrollbarMinimapConfig, ScrollbarMinimapCompiledVariant[]
M._compile = function(overrides, shared)
    return compile(overrides, shared)
end

---@param root ScrollbarMinimapConfig
---@param compiled ScrollbarMinimapCompiledVariant[]
M._commit = function(root, compiled)
    active = root
    variants = compiled
    selector = schema.selector("minimap")
end

--- Compile and commit only the minimap block, with default shared sections.
--- `require("scrollbar").setup()` uses the top-level dispatcher instead.
---@param overrides? ScrollbarMinimapUserConfig
---@return ScrollbarMinimapConfig
M.set = function(overrides)
    local root, compiled = M._compile(overrides, shared_config.normalize({}))
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
    M.get()
    return schema.select(selector, assert(variants, "compiled minimap variants unavailable"), source_win)
end

return M
