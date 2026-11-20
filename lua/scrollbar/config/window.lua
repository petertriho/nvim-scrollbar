--- The `window` option of the scrollbar and minimap blocks. Its keys go to
--- `nvim_open_win`, except the keys that a renderer sets itself, and `wo` holds
--- window-local options. A hidden probe float lets Neovim validate the values,
--- so this module has no copy of the Neovim border rules. The probe also
--- reports the normalized border, which gives the size of each side.

local schema = require("scrollbar.config.schema")

local invalid = schema.invalid

local M = {}

-- `nvim_open_win` keys that both renderers set, with the option that controls
-- each key. A block adds the hints for `width` and `height`.
local OWNED_KEYS = {
    relative = "use 'placement.relative'",
    win = "use 'placement.relative'",
    bufpos = "use 'placement'",
    anchor = "use 'placement.anchor'",
    row = "use 'placement.row'",
    col = "use 'placement.col'",
    zindex = "use 'placement.zindex'",
    mouse = "use 'mouse'",
    focusable = "use 'mouse'",
    hide = "use 'hide_on_cursor', 'autohide', or 'show'",
    style = "the renderer owns this key",
    external = "the renderer owns this key",
    split = "the renderer owns this key",
    vertical = "the renderer owns this key",
    noautocmd = "the renderer owns this key",
    fixed = "the renderer owns this key",
}

-- Window options that change the text area of a float. The renderers size a
-- float from its content, so these options would break the geometry.
local GEOMETRY_OPTIONS = {
    number = true,
    relativenumber = true,
    signcolumn = true,
    foldcolumn = true,
    statuscolumn = true,
    wrap = true,
}

local NO_SIDES = { top = 0, right = 0, bottom = 0, left = 0 }

local PROBE_CONFIG = {
    relative = "editor",
    row = 0,
    col = 0,
    width = 1,
    height = 1,
    focusable = false,
    hide = true,
    style = "minimal",
    noautocmd = true,
}

-- Sides of each validated signature. Profiles usually inherit the window of
-- the root, so one probe serves all of them.
---@type table<string, ScrollbarWindowSides>
local probed = {}

---@class ScrollbarWindowSpec
---@field owned_keys table<string, string|true> Hints for the `nvim_open_win` keys that only this block owns. `true` gives no hint
---@field owner? string What sets the owned keys, in the errors. Default "the renderer"
---@field owned_options? table<string, string> Window options that this block sets on each render, with their hints
---@field renderer_keys? boolean Whether the keys that both renderers set are also owned. Default true
---@field keep_winborder? boolean Without a `border` key, leave the key out, so that each float applies 'winborder' when it opens. Its sides then come from the open float
---@field text_area_options? boolean Accept the window options that change the text area, for a float that shows a source buffer

---@param value table
---@param path string
---@return string[]
local function sorted_keys(value, path)
    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" then
            invalid(path .. " must be a table keyed by name")
        end
        keys[#keys + 1] = key
    end
    table.sort(keys)
    return keys
end

---@param border any Border that `nvim_win_get_config` reports
---@return ScrollbarWindowSides
local function border_sides(border)
    if type(border) ~= "table" then
        return NO_SIDES
    end
    -- Neovim draws a side only when its edge item is not empty. The edge items
    -- are the 2nd (top), 4th (right), 6th (bottom), and 8th (left) items of
    -- the normalized list. An item is a string or a [char, highlight] pair.
    local function side(index)
        local item = border[index]
        if type(item) == "table" then
            item = item[1]
        end
        return (type(item) == "string" and item ~= "") and 1 or 0
    end
    return { top = side(2), right = side(4), bottom = side(6), left = side(8) }
end

---Run `callback` with all autocmds off. The floats of an earlier setup are
---still live, and their schedulers would treat a probe float as a source
---window. `vim._with` restores 'eventignore' without an `OptionSet` event.
---The fallback for a build without it restores the option with that event.
---@generic R
---@param callback fun(): R
---@return R
local function without_autocmds(callback)
    if type(vim._with) == "function" then
        return vim._with({ noautocmd = true }, callback)
    end
    local eventignore = vim.o.eventignore
    vim.o.eventignore = "all"
    local ok, result = pcall(callback)
    vim.o.eventignore = eventignore
    if not ok then
        error(result, 0)
    end
    return result
end

---Open a hidden float with the keys and the options, so that Neovim reports
---the first invalid value.
---@param open table<string, any>
---@param options table<string, any>
---@param path string
---@return { border?: any, message?: string }
local function probe_float(open, options, path)
    local float_buf = vim.api.nvim_create_buf(false, true)
    local float_win
    local ok, result = pcall(function()
        local opened, win = pcall(vim.api.nvim_open_win, float_buf, false, vim.tbl_extend("force", open, PROBE_CONFIG))
        if not opened then
            return { message = string.format("%s: %s", path, win) }
        end
        float_win = win
        local names = vim.tbl_keys(options)
        table.sort(names)
        for _, name in ipairs(names) do
            local set, message = pcall(vim.api.nvim_set_option_value, name, options[name], { win = float_win })
            if not set then
                return { message = string.format("%s.wo.%s: %s", path, name, message) }
            end
        end
        return { border = vim.api.nvim_win_get_config(float_win).border }
    end)
    if float_win ~= nil and vim.api.nvim_win_is_valid(float_win) then
        pcall(vim.api.nvim_win_close, float_win, true)
    end
    if vim.api.nvim_buf_is_valid(float_buf) then
        pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
    end
    if not ok then
        error(result, 0)
    end
    return result
end

---@param open table<string, any>
---@param options table<string, any>
---@param path string
---@return any border Normalized border of the probe float
local function probe(open, options, path)
    local result = without_autocmds(function()
        return probe_float(open, options, path)
    end)
    if result.message ~= nil then
        invalid(result.message)
    end
    return result.border
end

---@param value string
---@return ScrollbarWindowHighlights
local function parse_winhighlight(value)
    local groups = {}
    for entry in value:gmatch("[^,]+") do
        local group = entry:match("^([^:]+):")
        if group ~= nil then
            groups[group] = true
        end
    end
    return { value = value, groups = groups }
end

--- Validate and compile the layered `window` table of one variant.
---@param value any
---@param path string
---@param spec ScrollbarWindowSpec
---@return ScrollbarWindowConfig
M.normalize = function(value, path, spec)
    schema.table(value, path)

    local open = {}
    for _, key in ipairs(sorted_keys(value, path)) do
        if key ~= "wo" then
            local hint = spec.owned_keys[key]
            if hint == nil and spec.renderer_keys ~= false then
                hint = OWNED_KEYS[key]
            end
            if hint ~= nil then
                local owner = spec.owner or "the renderer"
                if hint == true then
                    invalid(string.format("%s.%s: %s sets this key", path, key, owner))
                end
                invalid(string.format("%s.%s: %s sets this key (%s)", path, key, owner, hint))
            end
            open[key] = value[key]
        end
    end
    -- Without a `border` key, `nvim_open_win` applies 'winborder'.
    if open.border == nil and not spec.keep_winborder then
        open.border = "none"
    end

    local wo_path = path .. ".wo"
    local wo = value.wo == nil and {} or schema.table(value.wo, wo_path)
    local options = {}
    local probed_options = {}
    local winhighlight = false
    local seen = {}
    for _, key in ipairs(sorted_keys(wo, wo_path)) do
        local option_path = wo_path .. "." .. key
        local found, info = pcall(vim.api.nvim_get_option_info2, key, {})
        if not found or info.scope ~= "win" then
            invalid(option_path .. " is not a window option")
        end
        -- Check the full name, so that a short name such as `nu` gets the same
        -- result.
        local name = info.name
        local owned = spec.owned_options and spec.owned_options[name]
        if owned ~= nil then
            invalid(string.format("%s: the renderer sets this option (%s)", option_path, owned))
        end
        if GEOMETRY_OPTIONS[name] and not spec.text_area_options then
            invalid(option_path .. ": the renderer sets this option, because it changes the text area of the float")
        end
        if seen[name] then
            invalid(string.format("%s duplicates option '%s'", option_path, name))
        end
        seen[name] = true
        probed_options[name] = wo[key]
        if name == "winhighlight" then
            winhighlight = wo[key]
        else
            options[name] = wo[key]
        end
    end

    local signature = vim.inspect({ open = open, wo = probed_options }, { newline = "", indent = "" })
    -- The sides of a float that applies 'winborder' depend on the option when
    -- the float opens. For such a float, the probe only validates the values,
    -- and the float reads its sides when it opens.
    local follows_winborder = open.border == nil
    local sides = probed[signature]
    if sides == nil then
        local key_count = vim.tbl_count(open)
        local plain = next(probed_options) == nil and (key_count == 0 or (key_count == 1 and open.border == "none"))
        if plain then
            -- The default window needs no probe, so a default setup opens no float.
            sides = NO_SIDES
        else
            sides = border_sides(probe(open, probed_options, path))
        end
        if not follows_winborder then
            probed[signature] = sides
        end
    end
    if follows_winborder then
        sides = NO_SIDES
    end

    return {
        open = open,
        wo = options,
        winhighlight = winhighlight and winhighlight ~= "" and parse_winhighlight(winhighlight) or false,
        sides = sides,
        signature = signature,
    }
end

--- The size of each side of the border of an open float.
---@param winid integer
---@return ScrollbarWindowSides
M.sides = function(winid)
    local ok, current = pcall(vim.api.nvim_win_get_config, winid)
    return ok and border_sides(current.border) or NO_SIDES
end

--- The `winhighlight` value of a float: the base entries of the renderer, then
--- the entries of `wo.winhighlight`. A user entry replaces the base entry of
--- the same group.
---@param base string Comma-separated `Group:Target` entries of the renderer
---@param window ScrollbarWindowConfig
---@return string
M.winhighlight = function(base, window)
    local user = window.winhighlight
    if not user then
        return base
    end
    local entries = {}
    for entry in base:gmatch("[^,]+") do
        if not user.groups[entry:match("^([^:]+):")] then
            entries[#entries + 1] = entry
        end
    end
    entries[#entries + 1] = user.value
    return table.concat(entries, ",")
end

return M
