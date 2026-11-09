local MiniTest = MiniTest
local expect = MiniTest.expect

local T = MiniTest.new_set({
    hooks = {
        pre_case = function()
            package.loaded["scrollbar.config"] = nil
            package.loaded["scrollbar.minimap.config"] = nil
        end,
    },
})

local function config()
    return require("scrollbar.config")
end

local function minimap()
    return require("scrollbar.minimap.config")
end

local function expect_error(fn, overrides, pattern)
    local ok, err = pcall(fn, overrides)
    expect.equality(ok, false)
    expect.no_equality(tostring(err):match(pattern), nil)
end

local function expect_invalid(overrides, pattern)
    expect_error(config().set, { scrollbar = overrides }, pattern)
end

local function expect_minimap_invalid(overrides, pattern)
    expect_error(minimap().set, overrides, pattern)
end

---@param overrides? table<string, boolean>
---@return table<string, boolean>
local function kinds(overrides)
    return vim.tbl_extend("force", {
        snacks_list = false,
        snacks_preview = false,
        telescope_results = false,
        telescope_preview = false,
    }, overrides or {})
end

local ALL = kinds({
    snacks_list = true,
    snacks_preview = true,
    telescope_results = true,
    telescope_preview = true,
})

local function floats(value)
    return config().set({ scrollbar = { floats = value } }).floats
end

T["normalizes the floats forms of the scrollbar"] = function()
    local off = { enabled = false, kinds = kinds(), when = false }
    expect.equality(config().set({}).floats, off)
    expect.equality(floats(false), off)
    expect.equality(floats(true), { enabled = true, kinds = ALL, when = false })
    expect.equality(floats({ snacks = false, telescope = false }), off)
    expect.equality(
        floats({ snacks = true }),
        { enabled = true, kinds = kinds({ snacks_list = true, snacks_preview = true }), when = false }
    )
    expect.equality(
        floats({ snacks = { list = true }, telescope = { preview = true, results = false } }),
        { enabled = true, kinds = kinds({ snacks_list = true, telescope_preview = true }), when = false }
    )

    local when = function()
        return true
    end
    expect.equality(floats({ when = when }), { enabled = true, kinds = kinds(), when = when })
end

T["rejects invalid floats values"] = function()
    expect_invalid({ floats = "yes" }, "scrollbar%.floats must be a boolean or table")
    expect_invalid({ floats = { extra = true } }, "unknown option 'scrollbar%.floats%.extra'")
    expect_invalid({ floats = { snacks = "list" } }, "scrollbar%.floats%.snacks must be a boolean or table")
    expect_invalid({ floats = { telescope = 1 } }, "scrollbar%.floats%.telescope must be a boolean or table")
    expect_invalid({ floats = { snacks = { input = true } } }, "unknown option 'scrollbar%.floats%.snacks%.input'")
    expect_invalid({ floats = { telescope = { list = true } } }, "unknown option 'scrollbar%.floats%.telescope%.list'")
    expect_invalid({ floats = { snacks = { list = 1 } } }, "scrollbar%.floats%.snacks%.list must be a boolean")
    expect_invalid({ floats = { when = true } }, "scrollbar%.floats%.when must be a function")
    expect_invalid(
        { profiles = { { match = { filetypes = { "lua" } }, floats = true } } },
        "scrollbar%.profiles%[1%]%.floats is a global option"
    )
end

T["the minimap turns on every kind except the snacks list"] = function()
    expect.equality(minimap().set({}).floats, { enabled = false, kinds = kinds(), when = false })
    expect.equality(
        minimap().set({ floats = true }).floats.kinds,
        kinds({
            snacks_preview = true,
            telescope_results = true,
            telescope_preview = true,
        })
    )
    expect.equality(minimap().set({ floats = { snacks = true } }).floats.kinds, kinds({ snacks_preview = true }))

    local message = "minimap%.floats%.snacks%.list is not supported%. The minimap cannot draw the snacks list, "
        .. "because its buffer holds only the visible rows"
    expect_minimap_invalid({ floats = { snacks = { list = true } } }, message)
    expect_minimap_invalid({ floats = { snacks = { list = false, preview = true } } }, message)
    expect_minimap_invalid(
        { profiles = { { match = { floats = { "snacks_list" } } } } },
        "minimap%.profiles%[1%]%.match%.floats%[1%] 'snacks_list' is not supported"
    )
    expect_minimap_invalid(
        { profiles = { { match = { filetypes = { "lua" } }, floats = true } } },
        "minimap%.profiles%[1%]%.floats is a global option"
    )
end

T["validates match.floats"] = function()
    local function profile(match)
        return { profiles = { { match = match } } }
    end
    expect_invalid(
        profile({ floats = false }),
        "scrollbar%.profiles%[1%]%.match%.floats must be true or a dense list of float kinds"
    )
    expect_invalid(profile({ floats = "custom" }), "match%.floats must be true or a dense list of float kinds")
    expect_invalid(profile({ floats = {} }), "match%.floats must contain at least one kind")
    expect_invalid(profile({ floats = { 1 } }), "match%.floats%[1%] must be a string")
    expect_invalid(
        profile({ floats = { "custom", "fzf" } }),
        "match%.floats%[2%] must be one of: custom, snacks_list, snacks_preview, telescope_preview, telescope_results"
    )

    expect.no_error(config().set, { scrollbar = profile({ floats = { "snacks_preview", "custom" } }) })
    expect.no_error(config().set, { scrollbar = profile({ floats = true }) })
end

T["match.floats separates float profiles from normal profiles"] = function()
    local winid = vim.api.nvim_get_current_win()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(winid, bufnr)
    vim.bo[bufnr].filetype = "lua"

    config().set({
        scrollbar = {
            floats = true,
            profiles = {
                { match = { floats = { "snacks_list", "custom" } }, thumb = { text = "L" } },
                { match = { floats = true, filetypes = { "lua" } }, thumb = { text = "F" } },
                { match = { floats = true }, thumb = { text = "A" } },
                { match = { filetypes = { "lua" } }, thumb = { text = "N" } },
            },
        },
    })
    local function variant(kind)
        return config().select(winid, kind).variant_id
    end

    expect.equality(variant("snacks_list"), 1)
    expect.equality(variant("custom"), 1)
    expect.equality(variant("snacks_preview"), 2)
    expect.equality(variant("normal"), 4)
    expect.equality(variant(nil), 4)

    vim.bo[bufnr].filetype = "text"
    expect.equality(variant("telescope_results"), 3)
    expect.equality(variant("normal"), 0)

    -- A float never gets a profile without `floats`.
    config().set({ scrollbar = { profiles = { { match = { filetypes = { "text" } }, thumb = { text = "N" } } } } })
    expect.equality(variant("custom"), 0)
    expect.equality(variant("normal"), 1)

    vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
