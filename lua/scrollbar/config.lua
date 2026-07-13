local DEFAULTS = {
    show = true,
    visibility = "all",
    set_highlights = true,
    max_lines = false,
    hide_if_all_visible = false,
    render = {
        interval_ms = 16,
        geometry = "line",
    },
    float = {
        width = 1,
        zindex = 50,
        placement = {
            relative = "window",
            anchor = "NE",
            row = 0,
            col = 0,
        },
    },
    mouse = {
        enabled = true,
    },
    handle = {
        text = " ",
        column = 1,
        width = 1,
        blend = 30,
        highlight = "PmenuThumb",
        hide_if_all_visible = true,
    },
    marks = {
        Cursor = {
            text = { "•" },
            column = 1,
            priority = 0,
            highlight = "Normal",
        },
        Search = {
            text = { "-", "=" },
            column = 1,
            priority = 1,
            highlight = "Search",
        },
        Error = {
            text = { "-", "=" },
            column = 1,
            priority = 2,
            highlight = "DiagnosticVirtualTextError",
        },
        Warn = {
            text = { "-", "=" },
            column = 1,
            priority = 3,
            highlight = "DiagnosticVirtualTextWarn",
        },
        Info = {
            text = { "-", "=" },
            column = 1,
            priority = 4,
            highlight = "DiagnosticVirtualTextInfo",
        },
        Hint = {
            text = { "-", "=" },
            column = 1,
            priority = 5,
            highlight = "DiagnosticVirtualTextHint",
        },
        Misc = {
            text = { "-", "=" },
            column = 1,
            priority = 6,
            highlight = "Normal",
        },
        GitAdd = {
            text = { "┆" },
            column = 1,
            priority = 7,
            highlight = "GitSignsAdd",
        },
        GitChange = {
            text = { "┆" },
            column = 1,
            priority = 7,
            highlight = "GitSignsChange",
        },
        GitDelete = {
            text = { "▁" },
            column = 1,
            priority = 7,
            highlight = "GitSignsDelete",
        },
    },
    providers = {
        cursor = true,
        diagnostic = true,
        search = true,
        gitsigns = false,
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
    render = true,
    float = true,
    mouse = true,
    handle = true,
    marks = true,
    providers = true,
    excluded_buftypes = true,
    excluded_filetypes = true,
}

local NESTED_KEYS = {
    render = { interval_ms = true, geometry = true },
    float = { width = true, zindex = true, placement = true },
    ["float.placement"] = { relative = true, anchor = true, row = true, col = true },
    mouse = { enabled = true },
    handle = {
        text = true,
        column = true,
        width = true,
        blend = true,
        highlight = true,
        hide_if_all_visible = true,
    },
    mark = { text = true, column = true, priority = true, highlight = true },
    providers = { cursor = true, diagnostic = true, search = true, gitsigns = true, ale = true, coc = true },
    search = { live = true, backend = true },
}

local ENUMS = {
    visibility = { all = true, active = true },
    geometry = { line = true, screen = true },
    relative = { window = true, editor = true },
    anchor = { NW = true, NE = true, SW = true, SE = true },
    search_backend = { sync = true, worker = true },
}

local active = vim.deepcopy(DEFAULTS)
local layout_generation = 0

---@param value ScrollbarConfig
---@return table
local function layout_config(value)
    local marks = {}
    for mark_type, mark in pairs(value.marks) do
        marks[mark_type] = {
            text = mark.text,
            column = mark.column,
            priority = mark.priority,
        }
    end
    return { width = value.float.width, marks = marks }
end

local function invalid(message)
    error("[scrollbar.nvim] " .. message, 3)
end

local function is_integer(value)
    return type(value) == "number" and value == math.floor(value)
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
    if overrides == nil then
        return
    end
    if type(overrides) ~= "table" then
        invalid("configuration must be a table")
    end

    for key in pairs(overrides) do
        if not TOP_LEVEL_KEYS[key] then
            invalid(string.format("unknown option '%s'", tostring(key)))
        end
    end

    validate_unknown_keys(overrides.render, NESTED_KEYS.render, "render")
    validate_unknown_keys(overrides.float, NESTED_KEYS.float, "float")
    if type(overrides.float) == "table" then
        validate_unknown_keys(overrides.float.placement, NESTED_KEYS["float.placement"], "float.placement")
    end
    validate_unknown_keys(overrides.mouse, NESTED_KEYS.mouse, "mouse")
    validate_unknown_keys(overrides.handle, NESTED_KEYS.handle, "handle")
    validate_unknown_keys(overrides.providers, NESTED_KEYS.providers, "providers")

    if type(overrides.providers) == "table" and type(overrides.providers.search) == "table" then
        validate_unknown_keys(overrides.providers.search, NESTED_KEYS.search, "providers.search")
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

local function normalize_text(value, path)
    if type(value) == "string" then
        value = { value }
    elseif type(value) ~= "table" then
        invalid(path .. " must be a string or dense list of strings")
    end

    if #value == 0 then
        invalid(path .. " must contain at least one variant")
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

    for index = 1, count do
        validate_text(value[index], string.format("%s[%d]", path, index))
    end
    return vim.deepcopy(value)
end

local function validate_string_list(value, path)
    if type(value) ~= "table" then
        invalid(path .. " must be a dense list of strings")
    end

    local count = 0
    local maximum = 0
    for key in pairs(value) do
        count = count + 1
        if not is_integer(key) or key < 1 then
            invalid(path .. " must be a dense list of strings")
        end
        maximum = math.max(maximum, key)
    end
    if count ~= maximum then
        invalid(path .. " must be a dense list of strings")
    end

    for index = 1, count do
        local item = value[index]
        if type(item) ~= "string" then
            invalid(string.format("%s[%d] must be a string", path, index))
        end
    end
end

local function normalize_providers(providers)
    for _, name in ipairs({ "cursor", "diagnostic", "gitsigns", "ale", "coc" }) do
        validate_boolean(providers[name], "providers." .. name)
    end

    local search = providers.search
    if search == true then
        providers.search = { live = false, backend = "worker" }
    elseif search == false then
        return
    elseif type(search) == "table" then
        if search.live == nil then
            search.live = false
        end
        if search.backend == nil then
            search.backend = "worker"
        end
        validate_boolean(search.live, "providers.search.live")
        validate_enum(search.backend, "providers.search.backend", ENUMS.search_backend)
    else
        invalid("providers.search must be a boolean or table")
    end
end

local function normalize(overrides)
    validate_shape(overrides)
    local result = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULTS), overrides or {})

    validate_boolean(result.show, "show")
    validate_boolean(result.set_highlights, "set_highlights")
    validate_boolean(result.hide_if_all_visible, "hide_if_all_visible")
    validate_enum(result.visibility, "visibility", ENUMS.visibility)
    if result.max_lines ~= false then
        if not is_integer(result.max_lines) or result.max_lines < 1 then
            invalid("max_lines must be false or a positive integer")
        end
    end

    if type(result.render) ~= "table" then
        invalid("render must be a table")
    end
    validate_integer(result.render.interval_ms, "render.interval_ms", true)
    validate_enum(result.render.geometry, "render.geometry", ENUMS.geometry)

    if type(result.float) ~= "table" then
        invalid("float must be a table")
    end
    validate_integer(result.float.width, "float.width", false)
    validate_integer(result.float.zindex, "float.zindex", false)
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

    if type(result.mouse) ~= "table" then
        invalid("mouse must be a table")
    end
    validate_boolean(result.mouse.enabled, "mouse.enabled")

    if type(result.handle) ~= "table" then
        invalid("handle must be a table")
    end
    validate_text(result.handle.text, "handle.text")
    validate_integer(result.handle.column, "handle.column", false)
    validate_integer(result.handle.width, "handle.width", false)
    validate_integer(result.handle.blend, "handle.blend", true)
    if result.handle.blend > 100 then
        invalid("handle.blend must be between 0 and 100")
    end
    result.handle.highlight = normalize_highlight(result.handle.highlight, "handle.highlight")
    validate_boolean(result.handle.hide_if_all_visible, "handle.hide_if_all_visible")
    if result.handle.column + result.handle.width - 1 > result.float.width then
        invalid("handle.column + handle.width - 1 must not exceed float.width")
    end

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
        mark.text = normalize_text(mark.text, path .. ".text")
        validate_integer(mark.column, path .. ".column", false)
        if mark.column > result.float.width then
            invalid(path .. ".column must fit within float.width")
        end
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

local M = {}

---@param overrides? ScrollbarUserConfig
---@return ScrollbarConfig
M.set = function(overrides)
    local normalized = normalize(overrides)
    if not vim.deep_equal(layout_config(active), layout_config(normalized)) then
        layout_generation = layout_generation + 1
    end
    active = normalized
    return active
end

---@return ScrollbarConfig
M.get = function()
    return active
end

---@return integer
M.get_layout_generation = function()
    return layout_generation
end

return M
