--- Inline virtual-text padding for `overlap.reserve = "virtual_text"`. In a
--- window with 'wrap', a pad at each wrap point fills the rest of the screen
--- row. Each row then ends before the columns that an east scrollbar covers,
--- and the next character starts the next row.
---
--- Neovim wraps the text around persistent inline marks only. Ephemeral marks
--- of a decoration provider do not change the wrapping. Thus the module sets
--- persistent marks, and only on the lines that the window can show, because
--- marks for a whole buffer cost too much.
---
--- The pad positions depend on the width of the window, so each window has its
--- own namespace, and `nvim__ns_set` shows the marks of that namespace only in
--- the window. Without that API, a buffer gets pads only while one window
--- shows it.
---
--- The renderer runs after the redraw. Thus the autocmds of this module update
--- the pads before the redraw: after a scroll, a resize, a text change, a
--- buffer change, and a change of an option that changes the wrapping. A
--- decoration provider pads the lines that a fold command shows, because no
--- autocmd reports a fold command.

local M = {}

local api = vim.api

local AUGROUP = "ScrollbarWrapPadding"

-- Options that change the pad positions or the width of the text area.
local OPTION_PATTERN = {
    "ambiwidth",
    "breakat",
    "breakindent",
    "breakindentopt",
    "emoji",
    "foldcolumn",
    "linebreak",
    "list",
    "listchars",
    "number",
    "numberwidth",
    "relativenumber",
    "showbreak",
    "signcolumn",
    "statuscolumn",
    "tabstop",
    "vartabstop",
    "wrap",
}

-- Neovim cannot delete a namespace, so a released window returns its
-- namespace to this pool.
---@type integer[]
local free_namespaces = {}
local namespace_count = 0

-- `nvim__ns_set` is experimental. The first window reads whether it exists,
-- and a failed call turns the scope off for the windows after it.
---@type boolean?
local scope_supported = nil

-- The pad cache of a window drops all entries at this size.
local PAD_CACHE_LIMIT = 1024

-- The width table of a window drops the entries of deleted marks at this size.
local WIDTH_LIMIT = 2048

---@class ScrollbarWrapPaddingState
---@field ns integer
---@field scoped boolean Whether only the window shows the marks of `ns`
---@field buf integer The buffer that has the marks, or 0
---@field covered integer Text columns that the scrollbar covers
---@field text_width integer Columns of the text area, without the gutter
---@field options_key string? The options that `pads` depends on
---@field wrap boolean
---@field tabstop integer
---@field vartabs integer[]? The 'vartabstop' columns, or nil without them
---@field tab_cells integer? The cells of a tab that 'list' shows as `^I`
---@field blank_space boolean Whether a space shows as a blank cell
---@field showbreak integer Cells of 'showbreak'
---@field breakindent boolean
---@field bri_shift integer
---@field bri_min integer
---@field bri_sbr boolean
---@field linebreak boolean
---@field breakat table<integer, true> Bytes of 'breakat'
---@field pads table<string, integer[]> Pad columns and widths of each line text
---@field pad_count integer
---@field widths table<integer, integer> The pad width of each mark
---@field width_count integer
---@field first integer The first line with pads, or 0 without pads
---@field last integer The last line with pads
---@field bottom integer The last line that the window showed at the last render
---@field shared boolean Whether the buffer has no pads, because another window shows it without a scope

---@type table<integer, ScrollbarWrapPaddingState>
local states = {}

M.states = states

local WINDOW_OPTIONS = { win = 0 }
local BUFFER_OPTIONS = { buf = 0 }
local GET_EXTMARKS = {}

-- `nvim_buf_set_extmark` copies the options, so the calls reuse this table.
local EXTMARK = { virt_text = nil, virt_text_pos = "inline", right_gravity = false }

---@type integer[]
local NO_PADS = {}

-- Neovim 0.13 counts the inline virtual text in a word for 'linebreak'. A pad
-- at the first character of a word then moves with the word, so the pad goes
-- before the 'breakat' character in front of the word.
local PAD_BEFORE_BREAK = vim.fn.has("nvim-0.13") == 1

---@type table<integer, table>
local pad_texts = {}

---@param cells integer
---@return table
local function pad_text(cells)
    local text = pad_texts[cells]
    if text == nil then
        text = { { string.rep(" ", cells) } }
        pad_texts[cells] = text
    end
    return text
end

---@param vcol integer
---@param tabstop integer
---@param vartabs integer[]?
---@return integer
local function tab_width(vcol, tabstop, vartabs)
    if vartabs == nil then
        return tabstop - vcol % tabstop
    end
    local tabcol = 0
    for index = 1, #vartabs do
        tabcol = tabcol + vartabs[index]
        if tabcol > vcol then
            return tabcol - vcol
        end
    end
    local last = vartabs[#vartabs]
    return last - (vcol - tabcol) % last
end

---The cells of the leading white space of a line.
---@param line string
---@param state ScrollbarWrapPaddingState
---@return integer
local function indent_cells(line, state)
    local vcol = 0
    for index = 1, #line do
        local byte = line:byte(index)
        if byte == 32 then
            vcol = vcol + 1
        elseif byte == 9 then
            vcol = vcol + (state.tab_cells or tab_width(vcol, state.tabstop, state.vartabs))
        else
            break
        end
    end
    return vcol
end

---The cells before the text of a continuation row: 'showbreak' and the
---'breakindent' indent, as Neovim computes them.
---@param line string
---@param state ScrollbarWrapPaddingState
---@return integer
local function continuation_cells(line, state)
    if not state.breakindent then
        return state.showbreak
    end
    local indent = indent_cells(line, state) + state.bri_shift
    if state.bri_sbr then
        indent = indent - state.showbreak
    end
    local limit = state.text_width - state.bri_min
    if indent < 0 then
        indent = 0
    elseif indent > limit then
        indent = limit < 0 and 0 or limit
    end
    return state.showbreak + indent
end

-- Bytes that are not one cell of printable ASCII.
local NOT_PLAIN = "[%c\128-\255]"

-- The caches of the code points and the characters drop all entries at this
-- size.
local CHARACTER_CACHE_LIMIT = 4096

-- How a code point joins its neighbors: `false` starts a character, `true`
-- joins the character before it, such as a combining mark, and `"context"`
-- joins depending on its neighbors.
---@type table<string, boolean|"context">
local joins = {}
local join_count = 0

-- The cells of each multibyte character. 'ambiwidth' and 'emoji' change them.
---@type table<string, integer>
local character_widths = {}
local width_entry_count = 0
local width_options = ""

-- The code points with `InCB=Linker`. A virama between two consonants makes
-- one cluster.
local INDIC_VIRAMAS =
    { [0x094D] = true, [0x09CD] = true, [0x0ACD] = true, [0x0B4D] = true, [0x0C4D] = true, [0x0D4D] = true }

---@param character string
---@return integer
local function codepoint(character)
    local b1, b2, b3, b4 = character:byte(1, 4)
    if #character == 2 then
        return (b1 % 32) * 64 + b2 % 64
    elseif #character == 3 then
        return ((b1 % 16) * 64 + b2 % 64) * 64 + b3 % 64
    end
    return (((b1 % 8) * 64 + b2 % 64) * 64 + b3 % 64) * 64 + (b4 or 0) % 64
end

---Whether a code point joins its neighbors. One probe with `split()` for each
---code point is cheaper than `split()` on each line. The zero width joiner,
---the regional indicators, the Hangul jamo, and an Indic virama, which joins
---two consonants, join depending on their neighbors, which a probe cannot
---find.
---@param point string A multibyte code point
---@return boolean|"context"
local function join_kind(point)
    local kind = joins[point]
    if kind ~= nil then
        return kind
    end
    local value = #point > 1 and codepoint(point) or 0
    if
        value == 0x200D
        or (value >= 0x1F1E6 and value <= 0x1F1FF)
        or (value >= 0x1100 and value <= 0x11FF)
        or (value >= 0xA960 and value <= 0xA97F)
        or (value >= 0xD7B0 and value <= 0xD7FF)
        or INDIC_VIRAMAS[value]
        -- A prepended mark joins the character after it.
        or #vim.fn.split(point .. "a", [[\zs]]) == 1
    then
        kind = "context"
    else
        kind = #vim.fn.split("a" .. point, [[\zs]]) == 1
    end
    if join_count >= CHARACTER_CACHE_LIMIT then
        joins = {}
        join_count = 0
    end
    joins[point] = kind
    join_count = join_count + 1
    return kind
end

---The characters of a line. Neovim draws a cluster of code points, such as a
---letter and its combining marks, as one character.
---@param line string
---@return string[]? characters Nil for a line of ASCII, which has one character in each byte
local function characters(line)
    if not line:find("[\128-\255]") then
        return nil
    end
    local chars = {}
    local length = #line
    local index = 1
    while index <= length do
        local stop = index + vim.str_utf_end(line, index) + 1
        if line:byte(index) >= 0x80 and join_kind(line:sub(index, stop - 1)) == "context" then
            return vim.fn.split(line, [[\zs]])
        end
        -- Only a code point from U+0300 joins the character before it.
        while stop <= length and line:byte(stop) >= 0xCC do
            local next_stop = stop + vim.str_utf_end(line, stop) + 1
            local kind = join_kind(line:sub(stop, next_stop - 1))
            if kind == "context" then
                return vim.fn.split(line, [[\zs]])
            elseif not kind then
                break
            end
            stop = next_stop
        end
        chars[#chars + 1] = line:sub(index, stop - 1)
        index = stop
    end
    return chars
end

---The cells of a character at `vcol`.
---@param character string?
---@param byte integer The first byte of the character
---@param vcol integer
---@param state ScrollbarWrapPaddingState
---@return integer
local function character_cells(character, byte, vcol, state)
    if byte == 9 then
        return state.tab_cells or tab_width(vcol, state.tabstop, state.vartabs)
    end
    if character == nil or #character == 1 then
        if byte < 32 or byte == 127 then
            -- Neovim shows a control character as `^X`.
            return 2
        end
        if byte < 128 then
            return 1
        end
    end
    character = character or string.char(byte)
    local cells = character_widths[character]
    if cells == nil then
        if width_entry_count >= CHARACTER_CACHE_LIMIT then
            character_widths = {}
            width_entry_count = 0
        end
        cells = api.nvim_strwidth(character)
        character_widths[character] = cells
        width_entry_count = width_entry_count + 1
    end
    return cells
end

---The cells of the word after a 'breakat' character, as Neovim measures it
---for 'linebreak': the characters up to the next word, with the 'breakat'
---characters after the word.
---@param line string
---@param chars string[]?
---@param count integer
---@param start integer The index of the first character after the 'breakat' character
---@param vcol integer The virtual column of the 'breakat' character
---@param after integer The virtual column after the 'breakat' character
---@param limit integer Cells after which the count can stop
---@param state ScrollbarWrapPaddingState
---@return integer cells The cells with the 'breakat' characters after the word
---@return integer text The cells without them
---@return integer shown The cells without the blank spaces at the end, at the columns where Neovim shows them
local function word_cells(line, chars, count, start, vcol, after, limit, state)
    local breakat = state.breakat
    local blank_space = state.blank_space
    local cells, text, shown, real = 0, 0, 0, 0
    local previous_break = true
    for index = start, count do
        local character = chars and chars[index] or nil
        local byte = character and character:byte(1) or line:byte(index)
        local is_break = breakat[byte] == true
        if index > start and previous_break and not is_break then
            break
        end
        -- Neovim measures each character from the column of the 'breakat'
        -- character. Only a tab gets other cells at the column where it shows.
        local size = character_cells(character, byte, vcol + cells, state)
        cells = cells + size
        if byte == 9 then
            size = character_cells(character, byte, after + real, state)
        end
        real = real + size
        if not is_break then
            text = cells
        end
        if byte ~= 32 or not blank_space then
            shown = real
        end
        if cells > limit then
            break
        end
        previous_break = is_break
    end
    return cells, text, shown
end

---The pad before a 'breakat' character that makes Neovim move the word after
---the character to the next row.
---@param character string?
---@param byte integer The first byte of the 'breakat' character
---@param col integer The cells of the row before the character
---@param vcol integer The virtual column of the character
---@param cells integer The cells of the character
---@param word integer The cells of the word, from `word_cells`
---@param width integer
---@param state ScrollbarWrapPaddingState
---@return integer pad
---@return integer cells The cells of the character after the pad
local function break_pad(character, byte, col, vcol, cells, word, width, state)
    local pad = width + 1 - col - cells - word
    cells = character_cells(character, byte, vcol + pad, state)
    -- A pad before a tab makes the tab narrower until the tab passes a tab
    -- stop.
    while col + pad + cells + word <= width do
        pad = pad + 1
        cells = character_cells(character, byte, vcol + pad, state)
    end
    return pad, cells
end

---Add a pad. A pad at the column of the last pad joins it.
---@param pads integer[]
---@param byte_col integer
---@param cells integer
local function add_pad(pads, byte_col, cells)
    local count = #pads
    if count > 0 and pads[count - 1] == byte_col then
        pads[count] = pads[count] + cells
    else
        pads[count + 1] = byte_col
        pads[count + 2] = cells
    end
end

---The pads of a line of printable ASCII, which has one cell for each byte.
---@param line string
---@param state ScrollbarWrapPaddingState
---@param usable integer
---@param continuation integer
---@return integer[]? pads Nil when a blank space is at a wrap point. The general path keeps it in the covered columns
local function plain_pads(line, state, usable, continuation)
    local pads = {}
    local pad = state.text_width - usable
    local col = usable
    while col < #line do
        if state.blank_space and line:byte(col + 1) == 32 then
            return nil
        end
        pads[#pads + 1] = col
        pads[#pads + 1] = pad
        col = col + usable - continuation
    end
    return pads
end

---The pads of one line: the byte column (0-based) and the width of each pad,
---in pairs. Each pad fills the rest of a screen row whose next character
---does not fit before the covered columns. With 'linebreak', a pad also
---moves a word that does not fit to the next row, where Neovim would move it
---for the full width. Before Neovim 0.13, that pad is at the first character
---of the word. From Neovim 0.13, it is before the 'breakat' character in
---front of the word, and Neovim fills the rest of the row after that
---character.
---@param line string
---@param state ScrollbarWrapPaddingState
---@return integer[]
local function line_pads(line, state)
    local width = state.text_width
    local usable = width - state.covered
    local length = #line
    local plain = not line:find(NOT_PLAIN)
    if plain and length <= usable then
        return NO_PADS
    end
    local continuation = continuation_cells(line, state)
    if usable - continuation < 1 then
        return NO_PADS
    end
    if plain and not state.linebreak then
        local pads = plain_pads(line, state, usable, continuation)
        if pads ~= nil then
            return pads
        end
    end
    local pads = {}

    local chars = characters(line)
    local count = chars and #chars or length
    local breakat = state.linebreak and state.breakat or nil
    -- `col` counts the cells of the current screen row. `vcol` is the
    -- virtual column, which also counts the pads and the cells before the
    -- text of a continuation row. Both move the tab stops.
    local col, vcol, byte_col = 0, 0, 0
    local filled = false
    local leading = true
    local pad_next = false
    -- Whether the current word follows its 'breakat' character on the same
    -- row. From Neovim 0.13, a pad in such a word, or at the 'breakat'
    -- character after it, makes Neovim move the word to the next row.
    local follows_break = false
    for index = 1, count do
        local character = chars and chars[index] or nil
        local byte = character and character:byte(1) or line:byte(index)
        local cells = character_cells(character, byte, vcol, state)
        -- The word after a 'breakat' character, which 'linebreak' can move.
        -- From Neovim 0.13, the 'breakat' characters after the word also
        -- decide whether it fits, because a pad there moves the word.
        local word, text, shown
        if breakat ~= nil then
            local is_break = breakat[byte] == true
            leading = leading and is_break
            if not leading and is_break and index < count then
                local next_character = chars and chars[index + 1] or nil
                local next_byte = next_character and next_character:byte(1) or line:byte(index + 1)
                if not breakat[next_byte] then
                    word, text, shown = word_cells(line, chars, count, index + 1, vcol, vcol + cells, width, state)
                    if PAD_BEFORE_BREAK then
                        text = shown
                    end
                end
            end
        end
        -- A blank space in the covered columns hides no text.
        local blank = byte == 32 and state.blank_space
        local wrap = filled and (pad_next or (col + cells > usable and not (blank and col + cells <= width)))
        if
            PAD_BEFORE_BREAK
            and word ~= nil
            and filled
            and not wrap
            and not follows_break
            and not blank
            and col + cells + word <= width
            and col + cells + text > usable
        then
            -- When the pad that moves the word would also move this character
            -- into the covered columns, this character starts the next row.
            -- After a word that follows its 'breakat' character, that pad
            -- would also move the word, so the character stays.
            local pad, padded = break_pad(character, byte, col, vcol, cells, word, width, state)
            wrap = col + pad + padded > usable
        end
        if wrap then
            local pad = width - col
            if pad > 0 then
                pads[#pads + 1] = byte_col
                pads[#pads + 1] = pad
            end
            vcol = vcol + math.max(pad, 0) + continuation
            col = continuation
            if byte == 9 then
                cells = character_cells(character, byte, vcol, state)
            end
            if word ~= nil then
                word, text, shown = word_cells(line, chars, count, index + 1, vcol, vcol + cells, width, state)
                if PAD_BEFORE_BREAK then
                    text = shown
                end
            end
        end
        pad_next = false
        if word ~= nil then
            follows_break = false
            if col + cells + word > width then
                -- Neovim fills the rest of the row after this character, and
                -- the word starts the next row.
                cells = math.max(cells, width - col)
            elseif col + cells + text > usable then
                if PAD_BEFORE_BREAK then
                    local pad, padded = break_pad(character, byte, col, vcol, cells, word, width, state)
                    add_pad(pads, byte_col, pad)
                    col = col + pad
                    vcol = vcol + pad
                    cells = math.max(padded, width - col)
                else
                    pad_next = true
                end
            else
                follows_break = true
            end
        end
        col = col + cells
        vcol = vcol + cells
        byte_col = byte_col + (character and #character or 1)
        filled = true
        -- A full row continues on the next row without a pad. A character
        -- wider than the rest of the row, such as a long tab, continues there.
        while col >= width do
            col = continuation + col - width
            vcol = vcol + continuation
            filled = col > continuation
        end
    end
    if #pads == 0 then
        return NO_PADS
    end
    return pads
end

---@param state ScrollbarWrapPaddingState
---@param line string
---@return integer[]
local function cached_pads(state, line)
    local pads = state.pads[line]
    if pads == nil then
        if state.pad_count >= PAD_CACHE_LIMIT then
            state.pads = {}
            state.pad_count = 0
        end
        pads = line_pads(line, state)
        state.pads[line] = pads
        state.pad_count = state.pad_count + 1
    end
    return pads
end

---@param state ScrollbarWrapPaddingState
local function forget_pads(state)
    state.pads = {}
    state.pad_count = 0
end

---Remove all marks of the window.
---@param state ScrollbarWrapPaddingState
---@return boolean removed Whether the window had marks
local function clear_marks(state)
    local removed = state.width_count > 0
    if state.buf ~= 0 and api.nvim_buf_is_valid(state.buf) then
        api.nvim_buf_clear_namespace(state.buf, state.ns, 0, -1)
    end
    state.widths = {}
    state.width_count = 0
    return removed
end

---Keep the widths of the marks that still exist.
---@param state ScrollbarWrapPaddingState
local function prune_widths(state)
    local widths = {}
    local count = 0
    for _, mark in ipairs(api.nvim_buf_get_extmarks(state.buf, state.ns, 0, -1, GET_EXTMARKS)) do
        local id = mark[1]
        widths[id] = state.widths[id]
        count = count + 1
    end
    state.widths = widths
    state.width_count = count
end

---Set the pads of the lines `first` to `last` (1-based). A line keeps its
---marks when they have the wanted columns and widths.
---@param state ScrollbarWrapPaddingState
---@param first integer
---@param last integer
---@return boolean changed
local function pad_lines(state, first, last)
    local buf, ns = state.buf, state.ns
    local lines = api.nvim_buf_get_lines(buf, first - 1, last, false)
    local marks = api.nvim_buf_get_extmarks(buf, ns, { first - 1, 0 }, { last - 1, -1 }, GET_EXTMARKS)
    local widths = state.widths
    local changed = false
    local next_mark = 1
    for index = 1, #lines do
        local row = first + index - 2
        local pads = cached_pads(state, lines[index])
        local start = next_mark
        while marks[next_mark] ~= nil and marks[next_mark][2] == row do
            next_mark = next_mark + 1
        end
        local count = next_mark - start
        local same = count * 2 == #pads
        if same then
            for offset = 0, count - 1 do
                local mark = marks[start + offset]
                if mark[3] ~= pads[offset * 2 + 1] or widths[mark[1]] ~= pads[offset * 2 + 2] then
                    same = false
                    break
                end
            end
        end
        if not same then
            changed = true
            if count > 0 then
                api.nvim_buf_clear_namespace(buf, ns, row, row + 1)
            end
            for position = start, next_mark - 1 do
                local id = marks[position][1]
                if widths[id] ~= nil then
                    widths[id] = nil
                    state.width_count = state.width_count - 1
                end
            end
            for position = 1, #pads, 2 do
                local cells = pads[position + 1]
                EXTMARK.virt_text = pad_text(cells)
                local id = api.nvim_buf_set_extmark(buf, ns, row, pads[position], EXTMARK)
                widths[id] = cells
                state.width_count = state.width_count + 1
            end
        end
    end
    EXTMARK.virt_text = nil
    return changed
end

---@param value string
---@return integer[]?
local function parse_vartabs(value)
    if value == "" then
        return nil
    end
    local columns = {}
    for item in value:gmatch("[^,]+") do
        local column = tonumber(item)
        if column ~= nil and column > 0 then
            columns[#columns + 1] = column
        end
    end
    return #columns > 0 and columns or nil
end

---@param state ScrollbarWrapPaddingState
---@param briopt string
local function parse_breakindentopt(state, briopt)
    state.bri_shift = 0
    state.bri_min = 20
    state.bri_sbr = false
    for item in briopt:gmatch("[^,]+") do
        local name, number = item:match("^(%a+):(-?%d+)$")
        if name == "shift" then
            state.bri_shift = tonumber(number) or 0
        elseif name == "min" then
            state.bri_min = tonumber(number) or 20
        elseif item == "sbr" then
            state.bri_sbr = true
        end
    end
end

---@param value string
---@return table<integer, true>
local function parse_breakat(value)
    local bytes = {}
    for index = 1, #value do
        bytes[value:byte(index)] = true
    end
    return bytes
end

---Read the options that the pads depend on.
---@param state ScrollbarWrapPaddingState
---@param win integer
---@return boolean changed Whether an option changed
local function read_options(state, win)
    local get = api.nvim_get_option_value
    WINDOW_OPTIONS.win = win
    BUFFER_OPTIONS.buf = state.buf
    local wrap = get("wrap", WINDOW_OPTIONS)
    local tabstop = get("tabstop", BUFFER_OPTIONS)
    local vartabstop = get("vartabstop", BUFFER_OPTIONS)
    local list = get("list", WINDOW_OPTIONS)
    local listchars = list and get("listchars", WINDOW_OPTIONS) or ""
    local showbreak = get("showbreak", WINDOW_OPTIONS)
    local breakindent = get("breakindent", WINDOW_OPTIONS)
    local briopt = breakindent and get("breakindentopt", WINDOW_OPTIONS) or ""
    local linebreak = get("linebreak", WINDOW_OPTIONS)
    local breakat = linebreak and vim.o.breakat or ""
    local widths = vim.o.ambiwidth .. tostring(vim.o.emoji)
    if widths ~= width_options then
        width_options = widths
        character_widths = {}
        width_entry_count = 0
    end
    local key = table.concat({
        tostring(wrap),
        tabstop,
        vartabstop,
        tostring(list),
        listchars,
        showbreak,
        tostring(breakindent),
        briopt,
        tostring(linebreak),
        breakat,
        widths,
    }, "\0")
    if key == state.options_key then
        return false
    end
    state.options_key = key
    state.wrap = wrap
    state.tabstop = tabstop > 0 and tabstop or 8
    state.vartabs = parse_vartabs(vartabstop)
    -- Without a `tab:` item, 'list' shows a tab as `^I`.
    state.tab_cells = (list and not listchars:find("tab:", 1, true)) and 2 or nil
    -- 'list' can show a space as a character: `space:`, `multispace:`,
    -- `lead:`, `leadmultispace:`, or `trail:`.
    state.blank_space = not (
        list
        and (listchars:find("space:", 1, true) or listchars:find("lead:", 1, true) or listchars:find("trail:", 1, true))
    )
    state.showbreak = (showbreak == "" or showbreak == "NONE") and 0 or api.nvim_strwidth(showbreak)
    state.breakindent = breakindent
    parse_breakindentopt(state, briopt)
    state.linebreak = linebreak
    state.breakat = parse_breakat(breakat)
    forget_pads(state)
    return true
end

---@param buf integer
---@return integer windows
local function window_count(buf)
    return #vim.fn.win_findbuf(buf)
end

---Update the pads of the lines that the window can show.
---
---After a text change or a scroll, Neovim must measure the screen lines of
---the window again to find its last line (`line("w$")`), and this costs more
---than the pads. Each line takes at least one row, so the lines from the top
---line to the window height fill the window. Only a closed fold shows more
---lines, and the last line of the last render covers them.
---@param win integer
---@param state ScrollbarWrapPaddingState
---@param text_width integer
---@param top? integer The top line, when the caller knows it
---@return boolean changed
local function refresh(win, state, text_width, top)
    local buf = api.nvim_win_get_buf(win)
    local changed = false
    if buf ~= state.buf then
        changed = clear_marks(state)
        state.buf = buf
        state.options_key = nil
    end
    read_options(state, win)
    if text_width ~= state.text_width then
        state.text_width = text_width
        forget_pads(state)
    end
    state.shared = not state.scoped and window_count(buf) > 1
    if not state.wrap or text_width - state.covered < 1 or state.shared then
        state.first, state.last = 0, 0
        return clear_marks(state) or changed
    end

    local first = top or vim.fn.line("w0", win)
    local line_count = api.nvim_buf_line_count(buf)
    local last = math.min(line_count, math.max(first + api.nvim_win_get_height(win) - 1, state.bottom))
    if pad_lines(state, first, last) then
        changed = true
    end
    -- A scroll or an edit moves marks out of the range.
    if first > 1 then
        api.nvim_buf_clear_namespace(buf, state.ns, 0, first - 1)
    end
    if last < line_count then
        api.nvim_buf_clear_namespace(buf, state.ns, last, -1)
    end
    if state.width_count > WIDTH_LIMIT then
        prune_widths(state)
    end
    state.first, state.last = first, last
    return changed
end

---@param win integer
---@return integer
local function window_text_width(win)
    local info = vim.fn.getwininfo(win)[1]
    return info.width - info.textoff
end

-- Whether an autocmd reported a failed update. The report shows once.
local warned = false

---@param win integer
---@param measure boolean Whether to read the text width again. Without a resize or an option change, the text width stays
local function refresh_window(win, measure)
    local state = states[win]
    if state == nil or not api.nvim_win_is_valid(win) then
        return
    end
    local ok, err = pcall(refresh, win, state, measure and window_text_width(win) or state.text_width)
    if not ok then
        -- An error in an autocmd repeats on each keystroke, so the window
        -- loses its pads until the next render.
        M.release(win)
        if not warned then
            warned = true
            vim.notify("[nvim-scrollbar] wrap padding failed: " .. tostring(err), vim.log.levels.WARN)
        end
    end
end

local function refresh_all()
    for win in pairs(states) do
        refresh_window(win, true)
    end
end

---@type integer?
local augroup = nil

local PROVIDER_NAMESPACE = api.nvim_create_namespace("scrollbar.wrap_padding")

-- A fold command fires no autocmd, but it can show lines after the padded
-- lines. Neovim calls `on_win` before it draws the lines of a window, and the
-- callback pads the lines that the window shows without pads. The cursor
-- position is from before the callback, so the autocmds stay the main path.
local DECORATION_PROVIDER = {
    on_win = function(_, win, _, toprow, botrow)
        local state = states[win]
        if state ~= nil and state.first ~= 0 and (toprow + 1 ~= state.first or botrow + 1 > state.last) then
            state.bottom = botrow + 1
            local ok, err = pcall(refresh, win, state, state.text_width, toprow + 1)
            if not ok then
                vim.schedule(function()
                    vim.notify("[nvim-scrollbar] wrap padding failed: " .. tostring(err), vim.log.levels.WARN)
                end)
            end
        end
        return false
    end,
}

local function create_autocmds()
    if augroup ~= nil then
        return
    end
    api.nvim_set_decoration_provider(PROVIDER_NAMESPACE, DECORATION_PROVIDER)
    augroup = api.nvim_create_augroup(AUGROUP, { clear = true })
    -- WinScrolled also covers a change of the width or the height. Its event
    -- has the change of each window.
    api.nvim_create_autocmd("WinScrolled", {
        group = augroup,
        callback = function()
            for key, change in pairs(vim.v.event) do
                local win = tonumber(key)
                if win ~= nil and states[win] ~= nil then
                    refresh_window(win, type(change) == "table" and change.width ~= 0)
                end
            end
        end,
    })
    -- A text change can change the width of the number column, but the next
    -- render reads the text width.
    api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "TextChangedP" }, {
        group = augroup,
        callback = function(args)
            for win, state in pairs(states) do
                if state.buf == args.buf then
                    refresh_window(win, false)
                end
            end
        end,
    })
    api.nvim_create_autocmd("OptionSet", {
        group = augroup,
        pattern = OPTION_PATTERN,
        callback = refresh_all,
    })
    -- A buffer in a window changed. Without a scope, a second window can also
    -- show a padded buffer.
    api.nvim_create_autocmd({ "BufWinEnter", "WinNew" }, {
        group = augroup,
        callback = refresh_all,
    })
end

local function delete_autocmds()
    if augroup ~= nil then
        pcall(api.nvim_del_augroup_by_id, augroup)
        augroup = nil
        api.nvim_set_decoration_provider(PROVIDER_NAMESPACE, {})
    end
end

---@param win integer
---@return integer ns
---@return boolean scoped
local function window_namespace(win)
    local ns = table.remove(free_namespaces)
    if ns == nil then
        namespace_count = namespace_count + 1
        ns = api.nvim_create_namespace("scrollbar.wrap_padding." .. namespace_count)
    end
    if scope_supported == nil then
        scope_supported = type(api.nvim__ns_set) == "function"
    end
    if scope_supported then
        local ok = pcall(api.nvim__ns_set, ns, { wins = { win } })
        if ok then
            return ns, true
        end
        scope_supported = false
    end
    return ns, false
end

---Pad the wrap points of a window with 'wrap', so that the text ends
---`covered` columns before the right edge of the text area. The autocmds
---keep the pads current between the calls.
---
---The result reports only the changes that move the pads of many lines. A
---scroll moves only the pads of the lines that enter the view, and a report
---would make the caller measure the screen lines of the whole buffer again.
---@param win integer
---@param covered integer Text columns that the scrollbar covers at the right edge
---@param text_width integer Columns of the text area, without the gutter
---@return boolean changed Whether a new width, buffer, or option changed the marks
M.apply = function(win, covered, text_width)
    local state = states[win]
    if state == nil then
        local ns, scoped = window_namespace(win)
        state = {
            ns = ns,
            scoped = scoped,
            buf = 0,
            covered = covered,
            text_width = text_width,
            wrap = false,
            tabstop = 8,
            blank_space = true,
            showbreak = 0,
            breakindent = false,
            bri_shift = 0,
            bri_min = 20,
            bri_sbr = false,
            linebreak = false,
            breakat = {},
            pads = {},
            pad_count = 0,
            widths = {},
            width_count = 0,
            first = 0,
            last = 0,
            bottom = vim.fn.line("w$", win),
            shared = false,
        }
        states[win] = state
        create_autocmds()
        return refresh(win, state, text_width)
    end
    -- The render runs after the redraw, so the last line is known.
    state.bottom = vim.fn.line("w$", win)
    if state.covered ~= covered then
        state.covered = covered
        forget_pads(state)
        return refresh(win, state, text_width)
    end
    local buf = api.nvim_win_get_buf(win)
    if buf ~= state.buf or text_width ~= state.text_width then
        return refresh(win, state, text_width)
    end
    -- No autocmd reports an option change from `:noautocmd`.
    if read_options(state, win) then
        return refresh(win, state, text_width)
    end
    -- No autocmd reports a fold command or a closed window that shared the
    -- buffer.
    if state.shared or vim.fn.line("w0", win) ~= state.first or state.bottom > state.last then
        refresh(win, state, text_width)
    end
    return false
end

---Remove the pads of a window.
---@param win integer
M.release = function(win)
    local state = states[win]
    if state == nil then
        return
    end
    states[win] = nil
    clear_marks(state)
    if state.scoped then
        pcall(api.nvim__ns_set, state.ns, { wins = {} })
    end
    free_namespaces[#free_namespaces + 1] = state.ns
    if next(states) == nil then
        delete_autocmds()
    end
end

return M
