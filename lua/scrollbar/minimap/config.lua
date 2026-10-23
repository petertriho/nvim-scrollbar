--- Minimap block of the configuration. The top-level dispatcher
--- (`lua/scrollbar/config/init.lua`) compiles it with the shared sections and
--- commits it together with the scrollbar block.

local block_config = require("scrollbar.config.block")
local schema = require("scrollbar.config.schema")
local shared_config = require("scrollbar.config.shared")
local window_config = require("scrollbar.config.window")

local invalid = schema.invalid

local DEFAULTS = {
    enabled = false,
    show = true,
    visibility = "all",
    autohide = false,
    max_lines = false,
    floats = false,
    throttle_ms = 50,
    backend = "worker",
    background_blend = false,
    width = 16,
    height = false,
    scale = "fixed",
    encoding = "braille",
    columns_per_dot = 4,
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
    marks = {},
    window = {
        border = "none",
        wo = {},
    },
}

-- Autocmd events that can change minimap content, the viewport, or the window
-- and buffer lifecycle. If the list is in DEFAULTS, a keyed `events` override
-- merges into it. Thus the list is not in DEFAULTS.
local DEFAULT_EVENTS = {
    "BufEnter",
    "BufWinEnter",
    "WinEnter",
    "CursorMoved",
    "CursorMovedI",
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
    "TextChangedT",
    "WinScrolled",
    "WinResized",
    "VimResized",
    "ColorScheme",
    "WinClosed",
    "BufDelete",
    "BufWipeout",
}

local GLOBAL_KEYS = vim.tbl_extend("error", block_config.GLOBAL_KEYS, {
    backend = true,
    background_blend = true,
})

local APPEARANCE_KEYS = {
    preset = true,
    width = true,
    height = true,
    scale = true,
    encoding = true,
    columns_per_dot = true,
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
    marks = { ["*"] = { priority = true, highlight = true } },
    -- `scrollbar.config.window` validates the keys of `window`.
    window = { ["*"] = true },
}

local WINDOW_SPEC = {
    owned_keys = {
        width = "use 'width'",
        height = "use 'height'",
    },
    -- The minimap sets the blend again on each render.
    owned_options = { winblend = "use 'blend'" },
}

-- These names belong to the static ScrollbarMinimap<Name> groups.
local REJECTED_MARK_TYPES = {
    Cursor = "the minimap draws the cursor with ScrollbarMinimapCursor. "
        .. "To hide it, set providers.cursor = { minimap = false }",
    Base = "conflicts with the static ScrollbarMinimapBase group",
    Content = "conflicts with the static ScrollbarMinimapContent group",
    Viewport = "conflicts with the static ScrollbarMinimapViewport group",
    FloatBorder = "conflicts with the static ScrollbarMinimapFloatBorder group",
    FloatTitle = "conflicts with the static ScrollbarMinimapFloatTitle group",
    FloatFooter = "conflicts with the static ScrollbarMinimapFloatFooter group",
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
    presets = "custom presets are removed. Set the options in the block or in a profile",
    glyph = "use 'encoding'. The block encoding always draws █",
    update = "use 'throttle_ms' and 'events'",
    float = "use 'placement', 'placement.zindex', 'blend', and 'hide_on_cursor'",
    background = "use 'background_blend'",
    overlays = "use 'marks = false' to hide the overlays",
    show_viewport = "use 'viewport'",
    content_glyph = "use 'encoding'",
    excluded_buftypes = "use the top-level 'exclude' table",
    excluded_filetypes = "use the top-level 'exclude' table",
    providers = "use the top-level 'providers' table",
    set_highlights = "use the top-level 'set_highlights' option",
    ["autohide.enabled"] = "use 'autohide = true' or 'autohide = { delay_ms = n }'",
    ["placement.gutter"] = "the minimap always overlaps the gutter",
    ["placement.gutter_position"] = "the minimap always overlaps the gutter",
}

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

---@param value any
---@param path string
---@return ScrollbarMinimapScale
local function scale_option(value, path)
    if value == "fixed" or value == "fit" or (schema.is_integer(value) and value >= 1) then
        return value
    end
    invalid(path .. " must be 'fixed', 'fit', or a positive integer")
    return value
end

---@param value table Layered options merged onto the defaults
---@param shared ScrollbarSharedConfig
---@param path string Prefix for error paths
---@param variant_id integer 0 for the root, or the profile index
---@return ScrollbarMinimapConfig
local function normalize(value, shared, path, variant_id)
    local function at(name)
        return path .. "." .. name
    end

    local autohide = block_config.autohide(value.autohide, at("autohide"))
    local placement = schema.table(value.placement, at("placement"))

    local globals = block_config.globals(value, path, autohide, DEFAULT_EVENTS, "minimap")
    local result = vim.tbl_extend("error", globals, {
        backend = schema.enum(value.backend, at("backend"), { "worker", "sync" }),
        background_blend = blend_or_false(value.background_blend, at("background_blend")),
        set_highlights = shared.set_highlights,
        exclude = shared.exclude.minimap,
        width = schema.integer(value.width, at("width"), 1),
        height = schema.positive_or_false(value.height, at("height")),
        scale = scale_option(value.scale, at("scale")),
        encoding = schema.enum(value.encoding, at("encoding"), { "braille", "block" }),
        columns_per_dot = schema.integer(value.columns_per_dot, at("columns_per_dot"), 1),
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
        marks = shared_config.resolve_marks(shared.marks, value.marks, at("marks"), {
            fields = { "priority", "highlight" },
            reject = REJECTED_MARK_TYPES,
        }),
        window = window_config.normalize(value.window, at("window"), WINDOW_SPEC),
    })
    for mark_type, spec in pairs(result.marks) do
        spec.group = mark_group_name(mark_type, variant_id, shared.set_highlights)
    end
    ---@cast result ScrollbarMinimapConfig
    return result
end

local BLOCK = block_config.block({
    name = "minimap",
    defaults = DEFAULTS,
    global_keys = GLOBAL_KEYS,
    appearance_keys = APPEARANCE_KEYS,
    removed_keys = REMOVED_KEYS,
    normalize = normalize,
})

---@param overrides any
---@param shared ScrollbarSharedConfig
---@return ScrollbarMinimapConfig, ScrollbarMinimapCompiledVariant[]
local function compile(overrides, shared)
    local root, compiled = block_config.compile(BLOCK, overrides, shared)
    ---@cast root ScrollbarMinimapConfig
    ---@cast compiled ScrollbarMinimapCompiledVariant[]
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
---@param kind? ScrollbarSourceKind Kind of the source window. Nil is a normal window
---@return ScrollbarMinimapConfigSelection
M.select = function(source_win, kind)
    M.get()
    return schema.select(selector, assert(variants, "compiled minimap variants unavailable"), source_win, kind)
end

return M
