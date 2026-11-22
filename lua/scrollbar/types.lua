---@meta

---@alias ScrollbarVisibility "all"|"active"
---@alias ScrollbarUnit "line"|"screenline"
---@alias ScrollbarPlacementRelative "window"|"editor"
---@alias ScrollbarFloatAnchor "NW"|"NE"|"SW"|"SE"
---@alias ScrollbarGutter "inner"|"outer"|"overlap"
---@alias ScrollbarGutterPosition "inner"|"outer" Side of an avoided west gutter that the reservation takes
---@alias ScrollbarLayoutDirection "auto"|"ltr"|"rtl"
---@alias ScrollbarSearchBackend "sync"|"worker"
---@alias ScrollbarMarkTextFunction fun(context: ScrollbarMarkTextContext): string? Nil or "" hides the marks of the group
---@alias ScrollbarThumbTextFunction fun(context: ScrollbarThumbTextContext): string? Nil or "" leaves the thumb row blank
---@alias ScrollbarText string|string[]|ScrollbarMarkTextFunction
---@alias ScrollbarWhenFunction fun(context: ScrollbarProfileContext): boolean A predicate for a `when` option
---@alias ScrollbarHighlightDefinition table<string, any> A table accepted by nvim_set_hl()
---@alias ScrollbarHighlight string|ScrollbarHighlightDefinition
---@alias ScrollbarProviderOption boolean|ScrollbarSearchProviderConfig|ScrollbarMarksProviderConfig|ScrollbarListProviderConfig
---@alias ScrollbarFloatKind "snacks_list"|"snacks_preview"|"snacks_zen"|"telescope_results"|"telescope_preview"|"custom"
---@alias ScrollbarSourceKind "normal"|ScrollbarFloatKind A normal window, or the kind of a floating source window
---@alias ScrollbarFramePreset "scrollbar"|"cursor"|"center"
---@alias ScrollbarFrameFunction fun(ctx: ScrollbarFrameContext): ScrollbarFrameResult? Nil when the window has no room
---@alias ScrollbarFrameValue ScrollbarFramePreset|ScrollbarFrameFunction
---@alias ScrollbarGlanceEntries "line"|"mark"|"type"
---@alias ScrollbarUserKeys false|string|string[] `false` removes the keys

---@class ScrollbarUserWindowConfig
---@field border? string|(string|string[])[] `nvim_open_win` border. The default `"none"` keeps 'winborder' out
---@field title? string|string[][]
---@field title_pos? "left"|"center"|"right"
---@field footer? string|string[][]
---@field footer_pos? "left"|"center"|"right"
---@field wo? table<string, any> Window-local options, applied after the renderer defaults
---@field [string] any Other `nvim_open_win` keys that the renderer does not set

---@class ScrollbarWindowSides
---@field top integer Border rows above the content, 0 or 1
---@field right integer Border columns right of the content, 0 or 1
---@field bottom integer Border rows below the content, 0 or 1
---@field left integer Border columns left of the content, 0 or 1

---@class ScrollbarWindowHighlights
---@field value string The `wo.winhighlight` value
---@field groups table<string, true> Groups that the value maps

---@class ScrollbarWindowConfig
---@field open table<string, any> `nvim_open_win` keys. `border` is set, except in a block that keeps 'winborder'
---@field wo table<string, any> Window options by full name, without `winhighlight`
---@field winhighlight false|ScrollbarWindowHighlights
---@field sides ScrollbarWindowSides
---@field signature string Stable text of the keys and the options. A float with another signature opens again

---@class ScrollbarUserPlacement
---@field relative? ScrollbarPlacementRelative
---@field anchor? ScrollbarFloatAnchor
---@field row? integer
---@field col? integer
---@field gutter? ScrollbarGutter
---@field zindex? integer

---@class ScrollbarUserMarkLayer
---@field types string[] Mark types routed to this lane
---@field max_width? integer Total width of a lane that selects `Mark`, including declared columns

---@alias ScrollbarUserLayoutLayer "track"|"thumb"|"marks"|ScrollbarUserMarkLayer

---@class ScrollbarUserLayoutConfig
---@field direction? ScrollbarLayoutDirection
---@field columns? ScrollbarUserLayoutLayer[][] Logical columns whose layers are ordered bottom-to-top

---@class ScrollbarUserTrackConfig
---@field highlight? ScrollbarHighlight
---@field inactive_highlight? ScrollbarHighlight The track of a source window without focus

---@class ScrollbarUserAutohideConfig
---@field delay_ms? integer

---@class ScrollbarUserThumbConfig
---@field text? string|ScrollbarThumbTextFunction
---@field blend? integer
---@field highlight? ScrollbarHighlight
---@field inactive_highlight? ScrollbarHighlight The thumb of a source window without focus
---@field hide_if_all_visible? boolean

---@alias ScrollbarMarkStyle "glyph"|"tint" How a mark draws: its text, or a background in the color of the mark

---@alias ScrollbarReserve boolean|"virtual_text" `"virtual_text"` also pads the wrap points of a window with 'wrap'

---@class ScrollbarUserOverlapConfig
---@field reserve? ScrollbarReserve Keep the text away from an east scrollbar
---@field show_through? false|integer Blend from 1 to 100 that shows the text below the scrollbar
---@field marks? ScrollbarMarkStyle

---@alias ScrollbarHighlightChannel "fg"|"bg" The color of a highlight group that a mark takes

---@alias ScrollbarHighlightFrom "self"|"covered" The mark type whose highlight a scrollbar mark cell shows

---@class ScrollbarUserMarkTypeConfig
---@field text? ScrollbarText
---@field priority? integer
---@field highlight? ScrollbarHighlight
---@field highlight_channel? ScrollbarHighlightChannel Defaults to "fg". A table `highlight` ignores it
---@field inactive_highlight? ScrollbarHighlight The mark in a source window without focus
---@field inactive_highlight_channel? ScrollbarHighlightChannel Defaults to `highlight_channel`. A table `inactive_highlight` ignores it
---@field highlight_from? ScrollbarHighlightFrom Defaults to "self". "covered" shows a scrollbar mark cell in the highlight of the mark that it covers. The minimap ignores it

---@class ScrollbarSearchProviderConfig
---@field incsearch? boolean
---@field backend ScrollbarSearchBackend

---@class ScrollbarMarksProviderConfig
---@field letters boolean
---@field numbers boolean

---@class ScrollbarListProviderConfig
---@field types table<string, string|false> The mark type for each entry type letter, or false to drop the entries

---@class ScrollbarUserProviderTargets
---@field scrollbar? boolean Defaults to true when the provider supports the scrollbar
---@field minimap? boolean Defaults to true

---@class ScrollbarUserSearchProviderConfig: ScrollbarUserProviderTargets
---@field incsearch? boolean
---@field backend? ScrollbarSearchBackend

---@class ScrollbarUserMarksProviderConfig: ScrollbarUserProviderTargets
---@field letters? boolean
---@field numbers? boolean

---@class ScrollbarUserListProviderConfig: ScrollbarUserProviderTargets
---@field types? table<"E"|"W"|"I"|"N", string|false> The mark type for each entry type letter, or false to drop the entries

---@alias ScrollbarUserProvider boolean|ScrollbarUserProviderTargets

---@class ScrollbarUserProvidersConfig
---@field cursor? ScrollbarUserProvider
---@field diagnostic? ScrollbarUserProvider
---@field search? boolean|ScrollbarUserSearchProviderConfig
---@field marks? boolean|ScrollbarUserMarksProviderConfig
---@field gitsigns? ScrollbarUserProvider
---@field mini_diff? ScrollbarUserProvider
---@field signify? ScrollbarUserProvider
---@field vgit? ScrollbarUserProvider
---@field ale? ScrollbarUserProvider
---@field coc? ScrollbarUserProvider
---@field qflist? boolean|ScrollbarUserListProviderConfig
---@field loclist? boolean|ScrollbarUserListProviderConfig
---@field treesitter? ScrollbarUserProvider
---@field lsp_semantic_tokens? ScrollbarUserProvider

---@alias ScrollbarUserExcludeEntry boolean|ScrollbarUserProviderTargets
---@alias ScrollbarUserExcludeList string[]|table<string, ScrollbarUserExcludeEntry>
---@class ScrollbarUserEventEntry
---@field pattern? string|string[] Autocmd patterns that replace the default pattern of the event

---@class ScrollbarUserEventListEntry: ScrollbarUserEventEntry
---@field event string

---@alias ScrollbarUserEventList (string|ScrollbarUserEventListEntry)[]|table<string, boolean|ScrollbarUserEventEntry>

---@class ScrollbarEventConfig
---@field event string Canonical autocmd event name
---@field pattern false|string[] Autocmd patterns, or false for the default pattern of the event

---@class ScrollbarUserExcludeConfig
---@field buftypes? ScrollbarUserExcludeList A list replaces the defaults. A table keyed by name merges with them
---@field filetypes? ScrollbarUserExcludeList A list replaces the defaults. A table keyed by name merges with them
---@field unfocusable? ScrollbarUserExcludeEntry Exclude normal windows that are not focusable. Defaults to true
---@field when? false|fun(context: ScrollbarExcludeContext): boolean Excludes each source window for which it returns a truthy value

---@class ScrollbarUserProfileMatcher
---@field filetypes? string[]
---@field buftypes? string[]
---@field when? fun(context: ScrollbarProfileContext): boolean
---@field floats? true|ScrollbarFloatKind[] Match only floating source windows: every kind, or the listed kinds

---@class ScrollbarUserSnacksFloats
---@field list? boolean The picker list. The scrollbar only
---@field preview? boolean The picker preview
---@field zen? boolean The window of `Snacks.zen()` and `Snacks.zen.zoom()`

---@class ScrollbarUserTelescopeFloats
---@field results? boolean The picker results
---@field preview? boolean The picker preview

---@class ScrollbarUserFloatsTable
---@field snacks? boolean|ScrollbarUserSnacksFloats `true` turns on every snacks.nvim window that the block supports
---@field telescope? boolean|ScrollbarUserTelescopeFloats `true` turns on every window of the Telescope picker
---@field when? fun(context: ScrollbarFloatContext): boolean Admits other floats with the kind `"custom"`

---@alias ScrollbarUserFloats boolean|ScrollbarUserFloatsTable `true` turns on every built-in window that the block supports

---@class ScrollbarUserAppearance
---@field preset? string Built-in preset. The options at the same level win over it
---@field unit? ScrollbarUnit
---@field placement? ScrollbarUserPlacement
---@field hide_on_cursor? boolean|"row"
---@field hide_if_all_visible? boolean
---@field mouse? boolean
---@field layout? ScrollbarUserLayoutConfig
---@field track? ScrollbarUserTrackConfig
---@field thumb? ScrollbarUserThumbConfig
---@field overlap? ScrollbarUserOverlapConfig
---@field marks? false|table<string, false|ScrollbarUserMarkTypeConfig>
---@field window? ScrollbarUserWindowConfig

---@class ScrollbarUserProfile: ScrollbarUserAppearance
---@field match ScrollbarUserProfileMatcher

---@class ScrollbarUserScrollbarConfig: ScrollbarUserAppearance
---@field enabled? boolean
---@field show? boolean
---@field visibility? ScrollbarVisibility
---@field floats? ScrollbarUserFloats Floating windows that get a scrollbar. Off by default
---@field autohide? boolean|ScrollbarUserAutohideConfig
---@field max_lines? false|integer
---@field throttle_ms? integer
---@field events? ScrollbarUserEventList Autocmd events that update the scrollbar. A list replaces the defaults. A table keyed by event name merges with them
---@field profiles? ScrollbarUserProfile[] Ordered contextual variants. The first match wins
---@field jump? ScrollbarUserLabelModeConfig Label mode of `require("scrollbar").jump()`
---@field peek? ScrollbarUserLabelModeConfig Label mode of `require("scrollbar").peek()`. The top-level `peek` configures the peek float
---@field hover? boolean|ScrollbarUserHoverConfig Peek at the mark under the mouse pointer. Off by default

---@class ScrollbarUserLabelModeConfig
---@field labels? string Unique lowercase ASCII letters. The uppercase letter of a label is also a key: it peeks in `jump()` and jumps in `peek()`
---@field offset? integer Columns from the mark cell to its label. A negative offset is to the left. 0 puts the label on the mark cell

---@class ScrollbarUserHoverConfig
---@field delay_ms? integer Rest time of the pointer on a mark before the peek opens

---@class ScrollbarFrameContext
---@field kind "peek"|"glance"
---@field winid integer Source window
---@field bufnr integer Source buffer
---@field win { width: integer, height: integer, textoff: integer } Columns of the window, text rows without the winbar, and columns of the gutter
---@field editor { width: integer, height: integer } The area between the tabline and the command line
---@field sides ScrollbarWindowSides Border cells of one pane
---@field cursor_row integer Zero-based row of the cursor line in the text area
---@field anchor_row integer Peek: the row of the mark (the label row or the pointer row). Glance: `cursor_row`
---@field free ScrollbarFrameFree

---@class ScrollbarFrameFree
---@field side "E"|"W" Side of the scrollbar and the minimap floats. "E" without a float
---@field first_col integer Zero-based column of the window
---@field last_col integer Zero-based column of the window, exclusive

---@class ScrollbarFrameResult
---@field relative? "win"|"editor" Default "win"
---@field row number Zero-based. Relative to the text area of the source window, or to the editor area. Fractions round down
---@field col number Zero-based. Fractions round down
---@field width number Outer columns, border included. At least 1 after rounding
---@field height number Outer rows, border included. At least 1 after rounding

---@class ScrollbarFrameRecipeOptions
---@field width? number Outer width. A number up to 1 is a part of the text area, and a whole number above 1 is cells
---@field height? number Outer height, with the same rule as `width`
---@field relative? "win"|"editor" Only for `recipes.frame.center`. Default "win"

---@class ScrollbarUserPeekConfig
---@field frame? ScrollbarFrameValue Place and size of the float. Default "scrollbar"
---@field window? ScrollbarUserWindowConfig Without `border`, the float uses 'winborder'

---@class ScrollbarUserGlanceListKeys
---@field jump? ScrollbarUserKeys Jump to the selected entry
---@field jump_split? ScrollbarUserKeys Jump to the selected entry in a new split
---@field jump_vsplit? ScrollbarUserKeys Jump to the selected entry in a new vertical split
---@field next? ScrollbarUserKeys Select the next entry. Skips headers and wraps around
---@field previous? ScrollbarUserKeys Select the previous entry. Skips headers and wraps around
---@field focus_preview? ScrollbarUserKeys Put the focus in the preview pane
---@field quickfix? ScrollbarUserKeys Put the entries in the quickfix list, close the frame, and open the quickfix window
---@field close? ScrollbarUserKeys Close the frame

---@class ScrollbarUserGlancePreviewKeys
---@field jump_split? ScrollbarUserKeys Jump to the selected entry in a new split
---@field jump_vsplit? ScrollbarUserKeys Jump to the selected entry in a new vertical split
---@field next? ScrollbarUserKeys Select and show the next entry. Skips headers and wraps around
---@field previous? ScrollbarUserKeys Select and show the previous entry. Skips headers and wraps around
---@field focus_list? ScrollbarUserKeys Put the focus in the list
---@field close? ScrollbarUserKeys Close the frame

---@class ScrollbarUserGlanceKeys
---@field list? ScrollbarUserGlanceListKeys Buffer-local keys of the list
---@field preview? ScrollbarUserGlancePreviewKeys Keys of the preview pane. They are buffer-local on the source buffer while the pane has focus

---@class ScrollbarUserGlanceListConfig
---@field width? number Outer width of the list pane: a part (less than 1) of the frame width, or a whole number of cells above 1. Default 0.4
---@field side? "right"|"left" Side of the list. The preview takes the other side. Default "right"

---@class ScrollbarUserGlanceBuiltinConfig
---@field frame? ScrollbarFrameValue Place and size of the frame of both panes. Default "cursor"
---@field list? ScrollbarUserGlanceListConfig
---@field keys? ScrollbarUserGlanceKeys Keys of the list and of the preview pane
---@field window? ScrollbarUserWindowConfig Applies to both panes. Without `border`, the panes use 'winborder'

---@class ScrollbarUserGlanceConfig
---@field picker? ScrollbarGlancePicker Picker of `glance()`. Default "builtin"
---@field entries? ScrollbarGlanceEntries Entries of the list. Default "line"
---@field builtin? ScrollbarUserGlanceBuiltinConfig Options of the builtin frame

---@class ScrollbarUserConfig
---@field set_highlights? boolean
---@field exclude? ScrollbarUserExcludeConfig
---@field providers? ScrollbarUserProvidersConfig
---@field marks? table<string, false|ScrollbarUserMarkTypeConfig> Mark-type registry shared by both renderers
---@field scrollbar? ScrollbarUserScrollbarConfig
---@field minimap? ScrollbarMinimapUserConfig
---@field peek? ScrollbarUserPeekConfig
---@field glance? ScrollbarUserGlanceConfig

---@class ScrollbarLabelModeConfig
---@field labels string
---@field offset integer

---@class ScrollbarHoverConfig
---@field delay_ms integer

---@class ScrollbarPeekConfig
---@field frame ScrollbarFrameValue
---@field window ScrollbarWindowConfig `open.border` is nil when the float uses 'winborder'

---@class ScrollbarGlanceListKeys
---@field jump string[]
---@field jump_split string[]
---@field jump_vsplit string[]
---@field next string[]
---@field previous string[]
---@field focus_preview string[]
---@field quickfix string[]
---@field close string[]

---@class ScrollbarGlancePreviewKeys
---@field jump_split string[]
---@field jump_vsplit string[]
---@field next string[]
---@field previous string[]
---@field focus_list string[]
---@field close string[]

---@class ScrollbarGlanceKeys
---@field list ScrollbarGlanceListKeys
---@field preview ScrollbarGlancePreviewKeys

---@class ScrollbarGlanceListConfig
---@field width number
---@field side "right"|"left"

---@class ScrollbarGlanceBuiltinConfig
---@field frame ScrollbarFrameValue
---@field list ScrollbarGlanceListConfig
---@field keys ScrollbarGlanceKeys
---@field window ScrollbarWindowConfig `open.border` is nil when the panes use 'winborder'

---@class ScrollbarGlanceConfig
---@field picker ScrollbarGlancePicker
---@field entries ScrollbarGlanceEntries
---@field builtin ScrollbarGlanceBuiltinConfig

---@alias ScrollbarGlancePicker "builtin"|"snacks"|"telescope"|fun(ctx: ScrollbarGlanceContext)

---@alias ScrollbarGlanceChunk { [1]: string, [2]: string? } Text and an optional highlight group

---@class ScrollbarGlanceItemMark
---@field type string
---@field provider string
---@field text? string Text of the provider
---@field priority integer
---@field glyph string
---@field hl string Highlight group of the glyph

---@class ScrollbarGlanceItem
---@field lnum integer One-based line
---@field text string The source line without its indent. Tabs are spaces
---@field glyph string Glyph of the first mark
---@field hl string Highlight group of the glyph
---@field type string Mark type of the first mark
---@field types string[] Mark types of the item, in priority order, each once
---@field marks ScrollbarGlanceItemMark[] Marks of the item, in priority order
---@field group? string Mark type of the group. Only in "type" mode

---@class ScrollbarGlanceFormatOptions
---@field group? boolean `false` leaves out the group column of "type" mode

---@class ScrollbarGlanceJumpOptions
---@field split? "split"|"vsplit" Open a split of the source window first, and move in it

---@class ScrollbarGlanceContext
---@field source_win integer Window of `glance()`
---@field source_buf integer Buffer of the source window
---@field mode ScrollbarGlanceEntries Value of `glance.entries`
---@field items ScrollbarGlanceItem[] Entries of the list, in list order. Never empty when the picker starts
---@field selected integer Index of the first item at or after the cursor line, else of the last item. 0 without items
---@field format fun(item: ScrollbarGlanceItem, opts?: ScrollbarGlanceFormatOptions): ScrollbarGlanceChunk[] Columns of the row of `item`
---@field jump fun(item: ScrollbarGlanceItem, opts?: ScrollbarGlanceJumpOptions): boolean Move the cursor of the source window to `item`. Returns whether it moved
---@field quickfix fun(items?: ScrollbarGlanceItem[]) Put one quickfix item for each line of `items` (default `ctx.items`) in a new quickfix list, and open the quickfix window
---@field refresh fun(): ScrollbarGlanceItem[] Read the marks again. Replaces `items`, `selected`, and the column widths of `format`

---@class ScrollbarPlacement
---@field relative ScrollbarPlacementRelative
---@field anchor ScrollbarFloatAnchor
---@field row integer
---@field col integer
---@field gutter ScrollbarGutter
---@field zindex integer

---@class ScrollbarNormalizedLayoutLayerInput
---@field kind "track"|"thumb"|"marks"
---@field catch_all? boolean
---@field types? false|string[]
---@field max_width? false|integer

---@class ScrollbarNormalizedLayoutLayer
---@field kind "track"|"thumb"|"marks"
---@field priority integer Stable bottom-to-top stack position within one column
---@field lane_id? integer

---@class ScrollbarNormalizedMarkLane
---@field id integer
---@field catch_all boolean
---@field types false|string[]
---@field columns integer[] Physical base columns
---@field first_column integer
---@field last_column integer
---@field max_width false|integer Total width of the lane, including declared columns

---@class ScrollbarNormalizedThumbSpan
---@field first_column integer
---@field last_column integer
---@field width integer

---@class ScrollbarLayoutConfig
---@field direction ScrollbarLayoutDirection
---@field width integer Derived declared width
---@field inward "left"|"right" Side to which named marks grow dynamically
---@field columns ScrollbarNormalizedLayoutLayer[][] Physical columns with bottom-to-top layers
---@field lanes ScrollbarNormalizedMarkLane[]
---@field routes table<string, integer> Explicit type-to-lane routing
---@field catchall_lane false|integer
---@field thumb false|ScrollbarNormalizedThumbSpan
---@field cache table Cache-relevant snapshot of the normalized layout

---@class ScrollbarTrackConfig
---@field highlight ScrollbarHighlight
---@field inactive_highlight? ScrollbarHighlight

---@class ScrollbarAutohideConfig
---@field delay_ms integer

---@class ScrollbarThumbConfig
---@field text string|ScrollbarThumbTextFunction A string repeats across the thumb. A function result shows once on its row
---@field blend integer
---@field highlight ScrollbarHighlight
---@field inactive_highlight? ScrollbarHighlight
---@field hide_if_all_visible boolean

---@class ScrollbarOverlapConfig
---@field reserve ScrollbarReserve
---@field show_through false|integer
---@field marks ScrollbarMarkStyle

---@class ScrollbarMarkTypeConfig
---@field text string[]|ScrollbarMarkTextFunction Density variants from least to most dense, or a function. An empty list for `Mark` uses the provider text
---@field priority integer
---@field highlight ScrollbarHighlight Source highlight group or direct definition
---@field highlight_channel? ScrollbarHighlightChannel Nil means "fg"
---@field inactive_highlight? ScrollbarHighlight Source group or direct definition for a source window without focus
---@field inactive_highlight_channel? ScrollbarHighlightChannel Nil means `highlight_channel`
---@field highlight_from? "covered" Nil means "self"

---@class ScrollbarMarkRegistry
---@field specs table<string, ScrollbarMarkTypeConfig> Every registered mark type
---@field hidden table<string, true> Types hidden in both renderers unless an override shows them

---@class ScrollbarExcludeConfig
---@field buftypes table<string, true>
---@field filetypes table<string, true>
---@field unfocusable boolean Whether normal windows that are not focusable are excluded
---@field when false|fun(context: ScrollbarExcludeContext): boolean

---@class ScrollbarSharedConfig
---@field set_highlights boolean
---@field marks ScrollbarMarkRegistry
---@field exclude table<"scrollbar"|"minimap", ScrollbarExcludeConfig>

---@class ScrollbarMarkHighlightGroups
---@field mark string
---@field thumb string
---@field thumb_pressed string
---@field tint string Background in the color of the mark, for `overlap.marks = "tint"`

---@class ScrollbarHighlightGroups
---@field base string
---@field surface? string Blend-only group under a glyph mark without a track or thumb, with `show_through`
---@field track string
---@field thumb string
---@field thumb_pressed string
---@field marks table<string, ScrollbarMarkHighlightGroups>

---@class ScrollbarProvidersConfig
---@field cursor boolean
---@field diagnostic boolean
---@field search false|ScrollbarSearchProviderConfig
---@field marks false|ScrollbarMarksProviderConfig
---@field gitsigns boolean
---@field mini_diff boolean
---@field signify boolean
---@field vgit boolean
---@field ale boolean
---@field coc boolean
---@field qflist false|ScrollbarListProviderConfig
---@field loclist false|ScrollbarListProviderConfig
---@field treesitter boolean
---@field lsp_semantic_tokens boolean

---@class ScrollbarProviderRequest
---@field options false|ScrollbarProviderOption Normalized options, or false when no renderer requests the provider
---@field scrollbar boolean
---@field minimap boolean

---@alias ScrollbarProviderExecutionMode "parent"|"worker"

---@class ScrollbarProviderConsumers
---@field scrollbar boolean
---@field minimap boolean

---@class ScrollbarProviderTargets
---@field scrollbar boolean
---@field minimap boolean

---@class ScrollbarEffectiveProvider
---@field consumers ScrollbarProviderConsumers Consumers whose enabled configuration requests this provider
---@field options ScrollbarProviderOption One normalized option set, or false when inactive
---@field targets ScrollbarProviderTargets Built-in capabilities independent of current demand
---@field execution ScrollbarProviderExecutionMode

---@alias ScrollbarEffectiveProviderPlan table<string, ScrollbarEffectiveProvider>

---@class ScrollbarFloatsConfig
---@field enabled boolean Whether any kind or `when` is on
---@field kinds table<ScrollbarFloatKind, boolean> Toggles of the built-in kinds. `custom` is not a key
---@field when false|fun(context: ScrollbarFloatContext): boolean

---@class ScrollbarConfig
---@field enabled boolean
---@field show boolean
---@field visibility ScrollbarVisibility
---@field floats ScrollbarFloatsConfig
---@field autohide false|ScrollbarAutohideConfig
---@field max_lines false|integer
---@field throttle_ms integer
---@field events ScrollbarEventConfig[] Autocmd events that update the scrollbar: the handled events first, then the others sorted
---@field set_highlights boolean Copied from the top-level option
---@field exclude ScrollbarExcludeConfig
---@field unit ScrollbarUnit
---@field placement ScrollbarPlacement
---@field hide_on_cursor boolean|"row"
---@field hide_if_all_visible boolean
---@field mouse boolean
---@field layout ScrollbarLayoutConfig
---@field track ScrollbarTrackConfig
---@field thumb ScrollbarThumbConfig
---@field overlap ScrollbarOverlapConfig
---@field marks table<string, ScrollbarMarkTypeConfig> Shown mark types
---@field window ScrollbarWindowConfig
---@field jump ScrollbarLabelModeConfig Global. Every variant has the value of the root
---@field peek ScrollbarLabelModeConfig Global. Every variant has the value of the root
---@field hover false|ScrollbarHoverConfig Global. Every variant has the value of the root
---@field highlights ScrollbarHighlightGroups Compiled canonical or profile-internal group names
---@field layout_cache table Precompiled static inputs for the line-layer cache
---@field providers? ScrollbarProvidersConfig Present only in provider context snapshots

---@class ScrollbarMarkTextContext
---@field winid integer Source window
---@field bufnr integer Source buffer
---@field type string Mark type
---@field line integer Zero-based line that a click on the mark goes to
---@field lines integer[] Zero-based lines of the marks of the group, ascending. A copy
---@field count integer Number of marks of the group
---@field text? string Text of the mark from its provider
---@field row integer Zero-based scrollbar row
---@field line_count integer Lines of the source buffer. Read on demand
---@field cursor_line integer Zero-based cursor line of the source window. Read on demand

---@class ScrollbarRecipeOptions
---@field width? integer Pads the text with spaces to this many cells. A wider text does not change
---@field align? "left"|"right" Side of the text when `width` pads it (default "right")

---@class ScrollbarThumbTextContext
---@field winid integer Source window
---@field bufnr integer Source buffer
---@field index integer Zero-based row in the thumb
---@field row integer Zero-based scrollbar row
---@field first_row integer Zero-based first thumb row
---@field last_row integer Zero-based last thumb row
---@field height integer Scrollbar rows
---@field top_line integer Zero-based first visible line
---@field bottom_line integer Zero-based last visible line
---@field line_count integer Lines of the source buffer
---@field cursor_line? integer Zero-based cursor line of the source window. Nil on a snacks list

---@class ScrollbarProfileContext
---@field winid integer
---@field bufnr integer
---@field filetype string
---@field buftype string
---@field bufname string
---@field renderer "scrollbar"|"minimap" The renderer that asks

---@class ScrollbarFloatContext: ScrollbarProfileContext
---@field config vim.api.keyset.win_config The `nvim_win_get_config` result of the float

---@class ScrollbarExcludeContext: ScrollbarProfileContext

---@class ScrollbarCompiledMatcher
---@field filetypes false|string[]
---@field filetype_lookup false|table<string, true>
---@field buftypes false|string[]
---@field buftype_lookup false|table<string, true>
---@field when false|fun(context: ScrollbarProfileContext): boolean
---@field floats false|true|table<string, true> `false` matches only normal windows. `true` or a kind lookup matches only floats

---@class ScrollbarCompiledVariant
---@field id integer The root variant has ID 0. A profile variant uses its one-based declaration index
---@field matcher false|ScrollbarCompiledMatcher
---@field config ScrollbarConfig

---@class ScrollbarConfigSelection
---@field config ScrollbarConfig
---@field variant_id integer
---@field kind? ScrollbarSourceKind Set by the source policy
---@field inactive? boolean Set by the renderer when the variant has inactive groups and the source window is not active

---@class ScrollbarMark
---@field line integer Zero-based source buffer line
---@field type string Configured mark type
---@field text? string Per-mark text override

---@class ScrollbarMinimapSourceSpan
---@field line integer Zero-based source buffer line
---@field start_col integer Zero-based byte column, inclusive
---@field end_col integer Zero-based byte column, exclusive
---@field highlight string Non-empty highlight group name
---@field priority integer Higher values win semantic composition

---@class ScrollbarMinimapSourcePoint
---@field line integer Zero-based source buffer line
---@field col integer Zero-based byte column
---@field highlight string Non-empty highlight group name
---@field priority integer Higher values win point composition

---@class ScrollbarCompactSearch
---@field data string Big-endian zero-based line numbers, four bytes per exact match
---@field count integer Number of exact matches
---@field partial? boolean True when any sync-budget bound fired during the scan

---@class ScrollbarLayoutMark: ScrollbarMark
---@field provider string Name of the owning provider, used for deterministic tie-breaks and for hit metadata

---@class ScrollbarProviderContext
---@field config ScrollbarConfig Provider-local snapshot. Mutations of it cannot change the root configuration
---@field set_marks fun(bufnr: integer, marks: ScrollbarMark[]): boolean Whether publication was accepted
---@field clear_marks fun(bufnr?: integer): boolean
---@field set_minimap_spans fun(bufnr: integer, spans: ScrollbarMinimapSourceSpan[]): boolean Whether publication was accepted
---@field clear_minimap_spans fun(bufnr?: integer): boolean
---@field set_window_marks fun(winid: integer, marks: ScrollbarMark[]): boolean Whether publication was accepted
---@field clear_window_marks fun(winid?: integer): boolean
---@field set_minimap_points fun(winid: integer, points: ScrollbarMinimapSourcePoint[]): boolean Whether publication was accepted
---@field clear_minimap_points fun(winid?: integer): boolean
---@field create_augroup fun(name: string): integer
---@field add_cleanup fun(cleanup: fun())
---@field on_text_change? fun(fn: fun(args: table), events?: string[]) Shared TextChanged dispatch hosted by the scheduler. Absent in standalone provider setups
---@field on_cursor_activity? fun(fn: fun(args: table), events?: string[]): boolean Shared cursor-activity dispatch hosted by the scheduler. Absent in standalone provider setups
---@field is_buffer_eligible fun(bufnr: integer): boolean
---@field is_source_window fun(winid: integer): boolean
---@field source_windows fun(bufnr?: integer): integer[]
---@field invalidate_buffer fun(bufnr: integer)
---@field invalidate_window fun(winid: integer)

---@alias ScrollbarProviderRefreshOwner "manager"|"provider"

---@class ScrollbarProviderRefreshOptions
---@field consumer? "scrollbar"|"minimap"
---@field channel? ScrollbarStoreChannel

---@class ScrollbarProviderRefreshOwnership
---@field buffer? ScrollbarProviderRefreshOwner
---@field window? ScrollbarProviderRefreshOwner
---@field minimap_buffer? ScrollbarProviderRefreshOwner
---@field minimap_window? ScrollbarProviderRefreshOwner

---@class ScrollbarProvider
---@field name string
---@field targets? { scrollbar?: boolean, minimap?: boolean } If omitted, defaults to scrollbar-only
---@field refresh_owner? ScrollbarProviderRefreshOwnership
---@field setup? fun(context: ScrollbarProviderContext)
---@field refresh? fun(bufnr: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field refresh_window? fun(winid: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field refresh_minimap? fun(bufnr: integer, context: ScrollbarProviderContext): ScrollbarMinimapSourceSpan[]?
---@field refresh_minimap_window? fun(winid: integer, context: ScrollbarProviderContext): ScrollbarMinimapSourcePoint[]?
---@field dispose? fun(context: ScrollbarProviderContext)

---@alias ScrollbarStoreSnapshot table<string, ScrollbarMark[]>
---@alias ScrollbarWindowStoreSnapshot table<string, ScrollbarMark[]>
---@alias ScrollbarMinimapSpanStoreSnapshot table<string, ScrollbarMinimapSourceSpan[]>
---@alias ScrollbarMinimapPointStoreSnapshot table<string, ScrollbarMinimapSourcePoint[]>

---@alias ScrollbarStoreScope "buffer"|"window"
---@alias ScrollbarStoreChannel "marks"|"minimap_spans"|"minimap_points"

---@class ScrollbarStoreEvent
---@field scope ScrollbarStoreScope
---@field channel ScrollbarStoreChannel
---@field target integer
---@field provider string

---@class ScrollbarStoreTrustedSnapshot
---@field marks ScrollbarStoreSnapshot Immutable by convention. Internal callers must not mutate it
---@field revision integer Monotonic revision for the mark collection of this buffer
---@field compact_search? ScrollbarCompactSearch Private built-in search representation
---@field minimap_spans ScrollbarMinimapSpanStoreSnapshot Immutable by convention. Internal callers must not mutate it
---@field minimap_span_revision integer Monotonic revision for the minimap spans of this buffer

---@class ScrollbarWindowStoreTrustedSnapshot
---@field marks ScrollbarWindowStoreSnapshot Immutable by convention. Internal callers must not mutate it
---@field revision integer Monotonic revision for the mark collection of this window
---@field minimap_points ScrollbarMinimapPointStoreSnapshot Immutable by convention. Internal callers must not mutate it
---@field minimap_point_revision integer Monotonic revision for the minimap points of this window

---@alias ScrollbarChangedBuffers table<integer, true>
---@alias ScrollbarChangedWindows table<integer, true>

---@class ScrollbarHighlightSpan
---@field start_col integer Zero-based byte column
---@field end_col integer Exclusive zero-based byte column
---@field highlight string
---@field priority integer Stable stack priority in the compositor

---@class ScrollbarHitCell
---@field track boolean Whether this display cell declares a track layer
---@field thumb boolean Whether this display cell is inside an active thumb layer
---@field provider? string
---@field type? string
---@field line? integer Exact zero-based source line
---@field lines? integer[] Exact source lines compressed into this rendered mark
---@field start_col? integer One-based first display column of the owning glyph
---@field end_col? integer One-based last display column of the owning glyph

---@class ScrollbarVerticalHandleGeometry
---@field first_row integer Zero-based inclusive row
---@field last_row integer Zero-based inclusive row

---@class ScrollbarHandleGeometry: ScrollbarVerticalHandleGeometry
---@field column integer One-based display column
---@field width integer

---@class ScrollbarNormalizedGeometryInput
---@field height integer Track height in rows
---@field line_count integer Logical line count of the source buffer
---@field top_line integer Zero-based first visible logical line
---@field bottom_line integer Zero-based last visible logical line
---@field marks ScrollbarMark[]
---@field mark_rows? integer[] Precomputed mark rows aligned with marks

---@class ScrollbarNormalizedMarkGeometryInput
---@field height integer Track height in rows
---@field line_count integer Logical line count of the source buffer
---@field marks ScrollbarMark[]
---@field previous? { rows: integer[], line_count: number, height?: integer, segments?: integer[][] } Prior rows plus the context needed to recompute only shifted entries
---@field changed? integer[] Indexes of marks that changed in place since `previous.rows`. The result lists them also when their row stays the same

---@class ScrollbarScreenGeometryInput
---@field source_win integer
---@field height integer Track height in rows
---@field viewport_height? integer Text rows of the source window. Defaults to `height`
---@field marks ScrollbarMark[]
---@field marks_sorted? boolean Marks already ordered per provider by (line, text). Skips the dedup/sort pass
---@field compact_search? ScrollbarCompactSearch Private built-in search matches projected into compact_mark_rows

---@class ScrollbarGeometry
---@field total_extent integer Logical lines or rendered screen rows
---@field viewport_start integer Zero-based document coordinate
---@field viewport_end integer Zero-based inclusive document coordinate
---@field mark_rows integer[] Track rows aligned with the input marks
---@field compact_mark_rows? integer[] Track rows aligned with compact_search entries. Only M.screen produces them
---@field handle ScrollbarVerticalHandleGeometry

---@class ScrollbarLayoutInput
---@field config ScrollbarConfig
---@field height integer
---@field line_count? integer Logical line count required by compact line-mode search
---@field container_width? integer Width of the placement container. Defaults to the normalized layout width
---@field geometry ScrollbarGeometry
---@field marks ScrollbarLayoutMark[] Marks aligned with geometry.mark_rows
---@field mark_layer? ScrollbarResolvedMarkLayer Precomputed static placed mark cells and resolved width
---@field compact_search? ScrollbarCompactSearch Private built-in search matches
---@field source_win? integer Source window for the context of the text functions
---@field source_buf? integer Source buffer for the context of the text functions
---@field thumb_context? ScrollbarThumbTextSource Window values for the context of a thumb text function

---@class ScrollbarThumbTextSource
---@field winid integer
---@field bufnr integer
---@field top_line integer
---@field bottom_line integer
---@field line_count integer
---@field cursor_line? integer Nil on a snacks list

---@class ScrollbarMarkLayerInput
---@field config ScrollbarConfig
---@field height integer
---@field line_count? integer Logical line count required by compact line-mode search
---@field container_width? integer Width of the placement container. Defaults to the normalized layout width
---@field geometry { mark_rows: integer[], compact_mark_rows?: integer[] }
---@field marks ScrollbarLayoutMark[]
---@field marks_sorted? boolean Marks already ordered per provider by (line, text). Skips the grouping sorts
---@field compact_search? ScrollbarCompactSearch Private built-in search matches
---@field previous? { layer: table, changed: table[] } Previous layer plus the {index, old_row} shift list for incremental row rebuilds
---@field source_win? integer Source window for the context of the text functions
---@field source_buf? integer Source buffer for the context of the text functions

---@class ScrollbarPlacedMark
---@field text string
---@field width integer
---@field column integer
---@field last_column integer
---@field lane_id integer
---@field type string
---@field provider string
---@field line integer
---@field lines integer[]
---@field inherits? true The type has `highlight_from = "covered"`
---@field covered_type? string The first mark type that this inheriting glyph drops in its lane and that does not inherit

---@class ScrollbarResolvedMarkLayer
---@field rows table<integer, table<integer, table<integer, ScrollbarPlacedMark>>> Placed cells by row, lane, and display column
---@field width integer Effective total layout width
---@field column_offset integer East-anchor translation applied to base content
---@field expanded_lane_id false|integer
---@field marks_identity ScrollbarLayoutMark[] Identity of the marks list that the layer was built from
---@field segments? integer[][] Provider segments as [first, last] index ranges over line-sorted marks. Nil when unavailable
---@field height integer Track height that the layer was built for
---@field mark_rows integer[] Track rows aligned with marks_identity
---@field text_reads? table<string, integer> Lazy context fields that the text functions read, with their values. Nil without text functions
---@field compact? ScrollbarCompactSearch The compact search matches that the layer was built from
---@field line_count? integer The line count that the layer was built for
---@field compact_ranges? table<integer, integer[]> The [first, last] compact entries of each row in line math. Nil when the entries of a row are not contiguous

---@class ScrollbarLayoutOutput
---@field rows string[]
---@field width integer Effective total layout width
---@field highlights ScrollbarHighlightSpan[][]
---@field hitmap ScrollbarHitCell[][]
---@field handle false|ScrollbarHandleGeometry

---@class ScrollbarRendererGeometry
---@field unit ScrollbarUnit
---@field total_extent integer
---@field viewport_start integer
---@field viewport_end integer

---@class ScrollbarWindowState
---@field source_win integer
---@field source_buf integer
---@field config ScrollbarConfig Effective configuration that produced this rendered state
---@field variant_id integer Stable ID of the selected variant. The root variant has ID 0
---@field float_win integer
---@field float_buf integer
---@field float_config table<string, any> Last applied floating-window configuration
---@field width integer Float width used for the row cache
---@field height integer Float height used for the row cache
---@field rows string[]
---@field highlights ScrollbarHighlightSpan[][]
---@field rendered_highlights ScrollbarHighlightSpan[][]
---@field hitmap ScrollbarHitCell[][]
---@field handle false|ScrollbarHandleGeometry
---@field handle_pressed boolean
---@field inactive boolean Whether the source window is not active, so the float uses the inactive groups
---@field hidden_by_cursor boolean
---@field cleared_row? integer One-based content row that `hide_on_cursor = "row"` clears
---@field written_rows string[] Rows of the last write, with the cleared row
---@field winblend integer `winblend` of the float
---@field winhighlight string `winhighlight` of the float
---@field geometry ScrollbarRendererGeometry
---@field footprint? ScrollbarStackFootprint Own stacking footprint from the last render
---@field sides ScrollbarWindowSides Border size of each side of the float
---@field window_signature string Signature of the `window` configuration that opened the float
---@field source_kind? ScrollbarSourceKind Kind of the source window at the last render
---@field source_position? integer[] Screen position of a floating source window at the last render

---@class ScrollbarFlattenedMarksCache
---@field source_buf integer
---@field buffer_revision integer
---@field window_revision integer
---@field marks ScrollbarLayoutMark[]
---@field compact_search? ScrollbarCompactSearch
---@field provider_names string[] The providers of `marks`, in name order
---@field regions table<string, ScrollbarFlattenedRegion> The sorted marks of each provider
---@field generation integer Changes each time the content of `marks` changes
---@field patch? ScrollbarFlattenedPatch The in-place change that made this generation

---The sorted layout marks of one provider, and the store arrays they come from.
---@class ScrollbarFlattenedRegion
---@field buffer_marks? ScrollbarMark[]
---@field window_marks? ScrollbarMark[]
---@field marks ScrollbarLayoutMark[]

---The indexes of a flattened marks table that changed in place.
---@class ScrollbarFlattenedPatch
---@field from integer The generation before the change
---@field indexes integer[]

---@class ScrollbarLineMarkLayerCache
---@field source_buf integer
---@field buffer_revision integer
---@field window_revision integer
---@field line_count integer
---@field container_width integer
---@field height integer
---@field config table Precompiled cache-relevant inputs for the selected variant
---@field marks ScrollbarLayoutMark[] Identity of the flattened marks that the rows and the layer were built from
---@field marks_generation integer The generation of `marks` that the rows and the layer were built from
---@field compact_search? ScrollbarCompactSearch
---@field mark_rows integer[]
---@field layer ScrollbarResolvedMarkLayer

---@class ScrollbarRendererPolicy
---@field is_buffer_eligible fun(bufnr: integer): boolean
---@field is_source_window fun(winid: integer): boolean
---@field source_windows fun(bufnr?: integer): integer[]

---@class ScrollbarSchedulerRenderer: ScrollbarRendererPolicy
---@field render fun(source_win: integer): ScrollbarWindowState?
---@field reconcile_source_windows? fun(): integer[] The flush lists the source windows with it. Without it, the flush uses `source_windows`
---@field reveal? fun(source_win: integer): boolean
---@field conceal? fun(source_win: integer): boolean
---@field is_visible? fun(): boolean
---@field is_owned_buffer? fun(bufnr: integer): boolean
---@field is_owned_window? fun(winid: integer): boolean
---@field is_owned_float_buffer? fun(bufnr: integer): boolean
---@field is_owned_float_window? fun(winid: integer): boolean
---@field windows_showing_buffer? fun(bufnr: integer): integer[]
---@field invalidate_source_selection? fun(source_win?: integer)

---@class ScrollbarSchedulerOptions
---@field config? ScrollbarConfig
---@field renderer? ScrollbarSchedulerRenderer
---@field on_colorscheme? fun()
---@field peers? ScrollbarSchedulerPeer[] Renderers whose floats the scheduler ignores

---@class ScrollbarSchedulerStatus
---@field setup boolean
---@field timer_active boolean
---@field timer_closed boolean
---@field flushing boolean
---@field dirty_windows integer[]
---@field augroup_id? integer
---@field interval_ms? integer

---@class ScrollbarInteractionState
---@field source_win integer
---@field source_buf integer
---@field source_kind? ScrollbarSourceKind Kind of the source window at press time
---@field float_win integer
---@field float_buf integer
---@field sides ScrollbarWindowSides Border size of each side of the float at press time
---@field pressed_row integer
---@field pressed_col integer
---@field pressed_screen_row integer
---@field pressed_screen_col integer
---@field pressed_hit ScrollbarHitCell
---@field handle false|ScrollbarHandleGeometry
---@field width integer Rendered width captured at press time
---@field height integer Rendered height captured at press time
---@field geometry ScrollbarRendererGeometry Geometry captured at press time
---@field handle_grab_offset? integer
---@field last_row integer
---@field last_col integer
---@field dragging boolean
---@field held boolean Whether the scheduler deadline was paused for an interactive layer

---@class ScrollbarMouseRenderer
---@field get_state_by_float fun(float_win: integer): ScrollbarWindowState?
---@field set_handle_pressed fun(float_win: integer, pressed: boolean): boolean
---@field set_state_callback fun(callback: fun(state: ScrollbarWindowState)?)

---@class ScrollbarMouseScheduler
---@field invalidate_window fun(winid: integer): boolean
---@field hold_window fun(winid: integer): boolean
---@field resume_window fun(winid: integer): boolean

---@class ScrollbarMouseOptions
---@field config? ScrollbarConfig
---@field renderer? ScrollbarMouseRenderer
---@field scheduler? ScrollbarMouseScheduler

return {}
