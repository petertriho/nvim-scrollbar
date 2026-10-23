--- Compile steps that the scrollbar block and the minimap block share: the key
--- checks and their hints, the profile list, the global options, and the loop
--- that compiles the root and each profile into variants.

local floats_config = require("scrollbar.config.floats")
local presets = require("scrollbar.config.presets")
local schema = require("scrollbar.config.schema")
local shared_config = require("scrollbar.config.shared")

local M = {}

local AUTOHIDE_DEFAULTS = { delay_ms = 1000 }

--- Global options of both blocks. A profile cannot set them.
M.GLOBAL_KEYS = {
    enabled = true,
    show = true,
    visibility = true,
    autohide = { delay_ms = true },
    max_lines = true,
    throttle_ms = true,
    events = true,
    -- `scrollbar.config.floats` validates the keys of `floats`.
    floats = true,
}

---@class ScrollbarBlockSpec
---@field name "scrollbar"|"minimap" Block key, also the prefix of its error paths
---@field defaults table
---@field global_keys table Keys that only the root of the block accepts
---@field appearance_keys table Keys that the root and the profiles accept
---@field removed_keys table<string, string> Replacements for the v1 options
---@field profile_hints? table<string, string> Extra replacement hints for the keys of a profile
---@field normalize fun(value: table, shared: ScrollbarSharedConfig, path: string, variant_id: integer): table

---@class ScrollbarBlock
---@field name "scrollbar"|"minimap"
---@field defaults table
---@field root_keys table
---@field profile_keys table
---@field describe_root fun(relative: string, path: string): string?
---@field describe_profile fun(relative: string, path: string): string?
---@field normalize fun(value: table, shared: ScrollbarSharedConfig, path: string, variant_id: integer): table

---@param spec ScrollbarBlockSpec
---@return ScrollbarBlock
M.block = function(spec)
    local global_keys = spec.global_keys
    return {
        name = spec.name,
        defaults = spec.defaults,
        root_keys = vim.tbl_extend("error", global_keys, spec.appearance_keys, { profiles = true }),
        profile_keys = vim.tbl_extend("error", spec.appearance_keys, { match = true }),
        describe_root = schema.hinter(spec.removed_keys),
        describe_profile = schema.hinter(
            vim.tbl_extend("force", spec.removed_keys, spec.profile_hints or {}),
            function(relative, path)
                if global_keys[relative] ~= nil or relative == "profiles" then
                    return path .. " is a global option and cannot be set in a profile"
                end
            end
        ),
        normalize = spec.normalize,
    }
end

---@param block ScrollbarBlock
---@param value any
---@return { matcher: ScrollbarCompiledMatcher, input: table, path: string }[]
local function compile_profiles(block, value)
    if value == nil then
        return {}
    end

    local list_path = block.name .. ".profiles"
    local count = schema.dense_count(value, list_path)
    local float_kinds = floats_config.match_kinds(block.name)
    local result = {}
    for index = 1, count do
        local path = string.format("%s[%d]", list_path, index)
        local profile = value[index]
        schema.table(profile, path)
        schema.check_keys(profile, block.profile_keys, path, block.describe_profile)
        if profile.match == nil then
            schema.invalid(path .. ".match is required")
        end
        result[index] = {
            matcher = schema.matcher(profile.match, path .. ".match", float_kinds),
            input = profile,
            path = path,
        }
    end
    return result
end

--- Compile the options of one block. The root configuration is variant 0, and
--- each profile is a variant with its 1-based index.
---@param block ScrollbarBlock
---@param overrides any
---@param shared ScrollbarSharedConfig
---@return table root
---@return { id: integer, matcher: false|ScrollbarCompiledMatcher, config: table }[] compiled
M.compile = function(block, overrides, shared)
    if overrides == nil then
        overrides = {}
    end
    schema.table(overrides, block.name)
    schema.check_keys(overrides, block.root_keys, block.name, block.describe_root)

    local profiles = compile_profiles(block, overrides.profiles)
    local root = block.normalize(presets.layered(block.name, block.defaults, overrides), shared, block.name, 0)
    local compiled = {
        { id = 0, matcher = false, config = root },
    }
    for index, profile in ipairs(profiles) do
        local layered = presets.layered(block.name, block.defaults, overrides, profile)
        compiled[#compiled + 1] = {
            id = index,
            matcher = profile.matcher,
            config = block.normalize(layered, shared, profile.path, index),
        }
    end
    return root, compiled
end

---@param value any
---@param path string
---@return false|ScrollbarAutohideConfig
M.autohide = function(value, path)
    local autohide = schema.feature(value, path, AUTOHIDE_DEFAULTS)
    if autohide then
        schema.integer(autohide.delay_ms, path .. ".delay_ms", 1)
    end
    return autohide
end

--- Validate the global options of a block in a fixed order. The caller
--- validates `autohide` with `M.autohide` and its own early tables first. Then
--- it calls this function. Validation stops at the first invalid value. Thus a
--- configuration with more than one invalid option always reports the same
--- error.
---@param value table Layered options merged onto the defaults
---@param path string Prefix for error paths
---@param autohide false|ScrollbarAutohideConfig
---@param default_events string[]
---@param block "scrollbar"|"minimap"
---@return table
M.globals = function(value, path, autohide, default_events, block)
    return {
        enabled = schema.boolean(value.enabled, path .. ".enabled"),
        show = schema.boolean(value.show, path .. ".show"),
        visibility = schema.enum(value.visibility, path .. ".visibility", { "all", "active" }),
        autohide = autohide,
        max_lines = schema.positive_or_false(value.max_lines, path .. ".max_lines"),
        throttle_ms = schema.integer(value.throttle_ms, path .. ".throttle_ms", 0),
        events = shared_config.resolve_events(value.events, default_events, path .. ".events"),
        floats = floats_config.normalize(value.floats, path .. ".floats", block),
    }
end

return M
