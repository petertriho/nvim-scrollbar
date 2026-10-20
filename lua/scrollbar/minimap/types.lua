---@meta

--- Minimap-specific type definitions. Shared aliases (visibility, placement
--- relative, anchor) come from `lua/scrollbar/types.lua`.

---@alias ScrollbarMinimapBackend "worker"|"sync"

--- A positive integer maps that number of source lines to each dot row and
--- scrolls the map with the source window. `fixed` is the same as `1`. `fit`
--- shrinks the whole buffer into the float height.
---@alias ScrollbarMinimapScale "fixed"|"fit"|integer

--- Both encodings use cells of 2 by 4 dots. `braille` draws each dot, and
--- `block` draws `█` for a cell with any dot.
---@alias ScrollbarMinimapEncoding "braille"|"block"

--- Arrangement with a scrollbar on the same side of the source window.
--- `inner` and `outer` place the floats side by side, with the minimap beside
--- the text or at the window edge. `above` and `below` overlap them.
---@alias ScrollbarMinimapStack "inner"|"outer"|"above"|"below"

---@class ScrollbarMinimapUserPlacement
---@field relative? ScrollbarPlacementRelative
---@field anchor? ScrollbarFloatAnchor
---@field row? integer
---@field col? integer
---@field zindex? integer
---@field stack? ScrollbarMinimapStack

---@class ScrollbarMinimapUserMarkTypeConfig
---@field priority? integer Lower values win overlay collisions
---@field highlight? ScrollbarHighlight Highlight source group or direct definition

---@class ScrollbarMinimapUserAppearance
---@field preset? string Built-in minimap preset name
---@field width? integer
---@field height? false|integer
---@field scale? ScrollbarMinimapScale
---@field encoding? ScrollbarMinimapEncoding
---@field columns_per_dot? integer Source display columns for each dot column
---@field placement? ScrollbarMinimapUserPlacement
---@field blend? integer Blend of the full float, 0-100
---@field hide_on_cursor? boolean
---@field mouse? boolean
---@field viewport? boolean
---@field marks? false|table<string, false|ScrollbarMinimapUserMarkTypeConfig>

---@class ScrollbarMinimapUserProfile: ScrollbarMinimapUserAppearance
---@field match ScrollbarUserProfileMatcher

---@class ScrollbarMinimapUserConfig: ScrollbarMinimapUserAppearance
---@field enabled? boolean
---@field show? boolean
---@field visibility? ScrollbarVisibility
---@field autohide? boolean|ScrollbarUserAutohideConfig
---@field max_lines? false|integer
---@field throttle_ms? integer
---@field events? ScrollbarUserEventList Autocmd events that update the minimap. A list replaces the defaults; a table keyed by event name merges with them
---@field backend? ScrollbarMinimapBackend
---@field background_blend? false|integer Root-only blend of the base surface
---@field profiles? ScrollbarMinimapUserProfile[]

---@class ScrollbarMinimapPlacement
---@field relative ScrollbarPlacementRelative
---@field anchor ScrollbarFloatAnchor
---@field row integer
---@field col integer
---@field zindex integer
---@field stack ScrollbarMinimapStack

---@class ScrollbarMinimapMarkSpec
---@field priority integer Lower values win overlay collisions
---@field highlight ScrollbarHighlight Highlight source used by automatic generation
---@field group string Compiled renderer-facing minimap highlight group

---@class ScrollbarMinimapConfig
---@field enabled boolean
---@field show boolean
---@field visibility ScrollbarVisibility
---@field autohide false|ScrollbarAutohideConfig
---@field max_lines false|integer
---@field throttle_ms integer
---@field events ScrollbarEventConfig[] Autocmd events that update the minimap: the handled events first, then the others sorted
---@field backend ScrollbarMinimapBackend
---@field background_blend false|integer
---@field set_highlights boolean Copied from the top-level option
---@field exclude ScrollbarExcludeConfig
---@field width integer
---@field height false|integer
---@field scale ScrollbarMinimapScale
---@field encoding ScrollbarMinimapEncoding
---@field columns_per_dot integer
---@field placement ScrollbarMinimapPlacement
---@field blend integer
---@field hide_on_cursor boolean
---@field mouse boolean
---@field viewport boolean
---@field marks table<string, ScrollbarMinimapMarkSpec> Shown mark types

---@class ScrollbarMinimapCompiledVariant
---@field id integer Root is 0; profile variants use their one-based declaration index
---@field matcher false|ScrollbarCompiledMatcher
---@field config ScrollbarMinimapConfig

---@class ScrollbarMinimapConfigSelection
---@field config ScrollbarMinimapConfig
---@field variant_id integer

---@class ScrollbarMinimapSquashHighlight
---@field hl_group string
---@field col_start integer 1-indexed display column, inclusive
---@field col_end integer 1-indexed display column, inclusive
---@field order? integer Lower values win semantic composition; omitted preserves legacy tuple order

---@class ScrollbarMinimapCell
---@field char string A space, a Braille character, or `█`
---@field hl_group string|nil

--- Rows of the minimap grid that one squash request produces. One dot row
--- covers `scale_lines / scale_dots` source lines.
---@class ScrollbarMinimapGrid
---@field width integer Cells per row
---@field first_row integer Zero-based map row of the first produced row
---@field row_count integer
---@field scale_lines integer
---@field scale_dots integer
---@field columns_per_dot integer
---@field encoding ScrollbarMinimapEncoding

---@class ScrollbarMinimapProjection
---@field scale ScrollbarMinimapScale
---@field line_count integer
---@field rows integer Float rows
---@field width integer Float columns
---@field columns_per_dot integer
---@field scale_lines integer
---@field scale_dots integer
---@field map_rows integer Rows of the whole map
---@field offset integer Zero-based map row at the top of the float
---@field top integer Zero-based first visible source line
---@field bottom integer Zero-based last visible source line
---@field max_topline integer Largest zero-based topline for a drag
---@field scroll_rate number Source lines for each float row of band movement

---@class ScrollbarMinimapOverlay
---@field source_line integer Zero-based source buffer line
---@field minimap_row integer 1-based target row in the minimap grid
---@field mark_type string Mark type (e.g. "Error", "Search")
---@field priority integer Lower wins collisions using the selected minimap mark spec
---@field highlight string Compiled minimap highlight group (e.g. "ScrollbarMinimapError")
---@field provider string Publishing provider name; used for deterministic tiebreaks

---@class ScrollbarMinimapOverlaysOptions
---@field config ScrollbarMinimapConfig Active minimap config slice

---@class ScrollbarMinimapSchedulerRenderer
---@field source_windows fun(bufnr?: integer): integer[]
---@field is_source_window fun(winid: integer): boolean
---@field is_buffer_eligible fun(bufnr: integer): boolean
---@field is_owned_buffer? fun(bufnr: integer): boolean
---@field is_owned_window? fun(winid: integer): boolean
---@field is_owned_float_buffer? fun(bufnr: integer): boolean
---@field is_owned_float_window? fun(winid: integer): boolean
---@field windows_showing_buffer? fun(bufnr: integer): integer[]
---@field render fun(source_win: integer)
---@field reveal? fun(source_win: integer): boolean
---@field conceal? fun(source_win: integer): boolean
---@field is_visible? fun(): boolean

---@class ScrollbarMinimapSchedulerOptions
---@field config? ScrollbarMinimapConfig
---@field renderer? ScrollbarMinimapSchedulerRenderer
---@field on_colorscheme? fun()
---@field on_text_change? fun(fn: fun(args: table), events?: string[]): boolean Shared TextChanged dispatch hosted by the scrollbar scheduler; returns false when the hub is inactive so the caller keeps its own registration

---@class ScrollbarMinimapSchedulerRuntime
---@field config ScrollbarMinimapConfig
---@field renderer ScrollbarMinimapSchedulerRenderer
---@field on_colorscheme fun()
---@field timer any
---@field timer_armed boolean
---@field dirty table<integer, true>
---@field flushing boolean
---@field augroup integer
---@field uv any
---@field hide_timers table<integer, any>
---@field hide_generations table<integer, integer>
---@field held table<integer, true>
---@field shows_marks boolean Whether any compiled variant shows mark types
---@field unsubscribe_store fun()

---@class ScrollbarMinimapHighlightSpan
---@field start_col integer One-based minimap cell boundary, inclusive
---@field end_col integer One-based minimap cell boundary, exclusive
---@field highlight string
---@field priority integer

---@class ScrollbarMinimapCellCache
---@field signature string
---@field cells ScrollbarMinimapCell[][] Rows of the cached slice
---@field first_row integer Zero-based map row of `cells[1]`
---@field row_count integer
---@field scale_lines integer
---@field scale_dots integer
---@field revision integer
---@field changedtick integer
---@field semantic_revision integer
---@field filetype string
---@field source_line_count integer
---@field mirror_signature string

---@class ScrollbarMinimapPendingCells
---@field changedtick integer
---@field semantic_revision integer
---@field generation integer
---@field filetype string
---@field grid ScrollbarMinimapGrid

---@class ScrollbarMinimapSemanticInput
---@field revision integer
---@field store_revision integer
---@field signature string
---@field spans ScrollbarMinimapSpanStoreSnapshot

---@class ScrollbarMinimapRendererState
---@field source_win integer
---@field source_buf integer
---@field config ScrollbarMinimapConfig
---@field variant_id integer
---@field float_win integer
---@field float_buf integer
---@field float_config table<string, any>
---@field width integer
---@field height integer
---@field projection ScrollbarMinimapProjection
---@field rows string[]
---@field highlights ScrollbarMinimapHighlightSpan[][]
---@field rendered_signature string
---@field viewport_top integer
---@field viewport_bottom integer
---@field cursor_row? integer
---@field cursor_col? integer 1-based projected minimap cursor column
---@field overlay_signature string
---@field cells_signature string
---@field hidden_by_cursor boolean
---@field winblend integer
---@field winhighlight string
---@field footprint ScrollbarStackFootprint Own stacking footprint from the last render

---@class ScrollbarMinimapRendererWorker
---@field request fun(request: table): boolean

---@class ScrollbarMinimapRendererOverlays
---@field project_with fun(source_win: integer, projection: ScrollbarMinimapProjection, marks?: table<string, ScrollbarMinimapMarkSpec>): ScrollbarMinimapOverlay[]

---@class ScrollbarMinimapRendererOptions
---@field config? ScrollbarMinimapConfig
---@field worker? ScrollbarMinimapRendererWorker
---@field overlays? ScrollbarMinimapRendererOverlays
---@field on_dirty? fun(source_win: integer)
---@field visible? boolean

---@class ScrollbarMinimapMouseRenderer
---@field get_state_by_float fun(float_win: integer): ScrollbarMinimapRendererState?
---@field set_state_callback fun(callback: fun(state: ScrollbarMinimapRendererState)?)

---@class ScrollbarMinimapMouseScheduler
---@field invalidate_window fun(winid: integer): boolean
---@field hold_window? fun(winid: integer): boolean
---@field resume_window? fun(winid: integer): boolean

---@class ScrollbarMinimapMouseOptions
---@field renderer? ScrollbarMinimapMouseRenderer
---@field scheduler? ScrollbarMinimapMouseScheduler

---@class ScrollbarMinimapMouseInteraction
---@field source_win integer
---@field source_buf integer
---@field float_win integer
---@field float_buf integer
---@field height integer
---@field width integer
---@field projection ScrollbarMinimapProjection Projection of the render before the press
---@field pressed_row integer 0-based minimap row at press time
---@field pressed_topline integer 0-based source topline after the press jump
---@field dragging boolean
---@field held boolean Whether the scheduler deadline was paused; always true because every press navigates

return {}
