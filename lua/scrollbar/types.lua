---@meta

---@alias ScrollbarVisibility "all"|"active"
---@alias ScrollbarUnit "line"|"screenline"
---@alias ScrollbarPlacementRelative "window"|"editor"
---@alias ScrollbarFloatAnchor "NW"|"NE"|"SW"|"SE"
---@alias ScrollbarGutter "inner"|"outer"|"overlap"
---@alias ScrollbarGutterPosition "inner"|"outer" Side of an avoided west gutter that the reservation takes
---@alias ScrollbarLayoutDirection "auto"|"ltr"|"rtl"
---@alias ScrollbarSearchBackend "sync"|"worker"
---@alias ScrollbarText string|string[]
---@alias ScrollbarHighlightDefinition table<string, any> A table accepted by nvim_set_hl()
---@alias ScrollbarHighlight string|ScrollbarHighlightDefinition
---@alias ScrollbarProviderOption boolean|ScrollbarSearchProviderConfig|ScrollbarMarksProviderConfig

---@class ScrollbarUserPlacement
---@field relative? ScrollbarPlacementRelative
---@field anchor? ScrollbarFloatAnchor
---@field row? integer
---@field col? integer
---@field gutter? ScrollbarGutter
---@field zindex? integer

---@class ScrollbarUserMarkLayer
---@field types string[] Mark types routed to this lane
---@field max_width? integer Total named-Mark lane width including declared columns

---@alias ScrollbarUserLayoutLayer "track"|"thumb"|"marks"|ScrollbarUserMarkLayer

---@class ScrollbarUserLayoutConfig
---@field direction? ScrollbarLayoutDirection
---@field columns? ScrollbarUserLayoutLayer[][] Logical columns whose layers are ordered bottom-to-top

---@class ScrollbarUserTrackConfig
---@field highlight? ScrollbarHighlight

---@class ScrollbarUserAutohideConfig
---@field delay_ms? integer

---@class ScrollbarUserThumbConfig
---@field text? string
---@field blend? integer
---@field highlight? ScrollbarHighlight
---@field hide_if_all_visible? boolean

---@class ScrollbarUserMarkTypeConfig
---@field text? ScrollbarText
---@field priority? integer
---@field highlight? ScrollbarHighlight

---@class ScrollbarSearchProviderConfig
---@field incsearch? boolean
---@field backend ScrollbarSearchBackend

---@class ScrollbarMarksProviderConfig
---@field letters boolean
---@field numbers boolean

---@class ScrollbarUserProviderTargets
---@field scrollbar? boolean Default true when the provider supports the scrollbar
---@field minimap? boolean Default true

---@class ScrollbarUserSearchProviderConfig: ScrollbarUserProviderTargets
---@field incsearch? boolean
---@field backend? ScrollbarSearchBackend

---@class ScrollbarUserMarksProviderConfig: ScrollbarUserProviderTargets
---@field letters? boolean
---@field numbers? boolean

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
---@field pattern false|string[] Autocmd patterns; false uses the default pattern of the event

---@class ScrollbarUserExcludeConfig
---@field buftypes? ScrollbarUserExcludeList A list replaces the defaults; a table keyed by name merges with them
---@field filetypes? ScrollbarUserExcludeList A list replaces the defaults; a table keyed by name merges with them

---@class ScrollbarUserProfileMatcher
---@field filetypes? string[]
---@field buftypes? string[]
---@field when? fun(context: ScrollbarProfileContext): boolean

---@class ScrollbarUserAppearance
---@field preset? string Built-in preset applied below the options at the same level
---@field unit? ScrollbarUnit
---@field placement? ScrollbarUserPlacement
---@field hide_on_cursor? boolean
---@field hide_if_all_visible? boolean
---@field mouse? boolean
---@field layout? ScrollbarUserLayoutConfig
---@field track? ScrollbarUserTrackConfig
---@field thumb? ScrollbarUserThumbConfig
---@field marks? false|table<string, false|ScrollbarUserMarkTypeConfig>

---@class ScrollbarUserProfile: ScrollbarUserAppearance
---@field match ScrollbarUserProfileMatcher

---@class ScrollbarUserScrollbarConfig: ScrollbarUserAppearance
---@field enabled? boolean
---@field show? boolean
---@field visibility? ScrollbarVisibility
---@field autohide? boolean|ScrollbarUserAutohideConfig
---@field max_lines? false|integer
---@field throttle_ms? integer
---@field events? ScrollbarUserEventList Autocmd events that update the scrollbar. A list replaces the defaults; a table keyed by event name merges with them
---@field profiles? ScrollbarUserProfile[] Ordered contextual variants; first match wins

---@class ScrollbarUserConfig
---@field set_highlights? boolean
---@field exclude? ScrollbarUserExcludeConfig
---@field providers? ScrollbarUserProvidersConfig
---@field marks? table<string, false|ScrollbarUserMarkTypeConfig> Mark-type registry shared by both renderers
---@field scrollbar? ScrollbarUserScrollbarConfig
---@field minimap? ScrollbarMinimapUserConfig

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
---@field max_width false|integer Total lane width including declared columns

---@class ScrollbarNormalizedThumbSpan
---@field first_column integer
---@field last_column integer
---@field width integer

---@class ScrollbarLayoutConfig
---@field direction ScrollbarLayoutDirection
---@field width integer Derived declared width
---@field inward "left"|"right" Dynamic named-mark growth side
---@field columns ScrollbarNormalizedLayoutLayer[][] Physical columns with bottom-to-top layers
---@field lanes ScrollbarNormalizedMarkLane[]
---@field routes table<string, integer> Explicit type-to-lane routing
---@field catchall_lane false|integer
---@field thumb false|ScrollbarNormalizedThumbSpan
---@field cache table Cache-relevant normalized layout snapshot

---@class ScrollbarTrackConfig
---@field highlight ScrollbarHighlight

---@class ScrollbarAutohideConfig
---@field delay_ms integer

---@class ScrollbarThumbConfig
---@field text string
---@field blend integer
---@field highlight ScrollbarHighlight
---@field hide_if_all_visible boolean

---@class ScrollbarMarkTypeConfig
---@field text string[] Density variants ordered from least to most dense; an empty Mark list uses provider text
---@field priority integer
---@field highlight ScrollbarHighlight Source highlight group or direct definition

---@class ScrollbarMarkRegistry
---@field specs table<string, ScrollbarMarkTypeConfig> Every registered mark type
---@field hidden table<string, true> Types hidden in both renderers unless an override shows them

---@class ScrollbarExcludeConfig
---@field buftypes table<string, true>
---@field filetypes table<string, true>

---@class ScrollbarSharedConfig
---@field set_highlights boolean
---@field marks ScrollbarMarkRegistry
---@field exclude table<"scrollbar"|"minimap", ScrollbarExcludeConfig>

---@class ScrollbarMarkHighlightGroups
---@field mark string
---@field thumb string
---@field thumb_pressed string

---@class ScrollbarHighlightGroups
---@field base string
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
---@field consumers ScrollbarProviderConsumers Consumers whose enabled config requests this provider
---@field options ScrollbarProviderOption One normalized option set, or false when inactive
---@field targets ScrollbarProviderTargets Built-in capabilities independent of current demand
---@field execution ScrollbarProviderExecutionMode

---@alias ScrollbarEffectiveProviderPlan table<string, ScrollbarEffectiveProvider>

---@class ScrollbarConfig
---@field enabled boolean
---@field show boolean
---@field visibility ScrollbarVisibility
---@field autohide false|ScrollbarAutohideConfig
---@field max_lines false|integer
---@field throttle_ms integer
---@field events ScrollbarEventConfig[] Autocmd events that update the scrollbar: the handled events first, then the others sorted
---@field set_highlights boolean Copied from the top-level option
---@field exclude ScrollbarExcludeConfig
---@field unit ScrollbarUnit
---@field placement ScrollbarPlacement
---@field hide_on_cursor boolean
---@field hide_if_all_visible boolean
---@field mouse boolean
---@field layout ScrollbarLayoutConfig
---@field track ScrollbarTrackConfig
---@field thumb ScrollbarThumbConfig
---@field marks table<string, ScrollbarMarkTypeConfig> Shown mark types
---@field highlights ScrollbarHighlightGroups Compiled canonical or profile-internal group names
---@field layout_cache table Precompiled static line-layer cache inputs
---@field providers? ScrollbarProvidersConfig Present only in provider context snapshots

---@class ScrollbarProfileContext
---@field winid integer
---@field bufnr integer
---@field filetype string
---@field buftype string
---@field bufname string

---@class ScrollbarCompiledMatcher
---@field filetypes false|string[]
---@field filetype_lookup false|table<string, true>
---@field buftypes false|string[]
---@field buftype_lookup false|table<string, true>
---@field when false|fun(context: ScrollbarProfileContext): boolean

---@class ScrollbarCompiledVariant
---@field id integer Root is 0; profile variants use their one-based declaration index
---@field matcher false|ScrollbarCompiledMatcher
---@field config ScrollbarConfig

---@class ScrollbarConfigSelection
---@field config ScrollbarConfig
---@field variant_id integer

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
---@field count integer Exact match count
---@field partial? boolean True when any sync-budget bound fired during the scan

---@class ScrollbarLayoutMark: ScrollbarMark
---@field provider string Owning provider name used for deterministic ties and hit metadata

---@class ScrollbarProviderContext
---@field config ScrollbarConfig Provider-local snapshot; mutations cannot change root configuration
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
---@field on_text_change? fun(fn: fun(args: table), events?: string[]) Shared TextChanged dispatch hosted by the scheduler; absent in standalone provider setups
---@field on_cursor_activity? fun(fn: fun(args: table), events?: string[]): boolean Shared cursor-activity dispatch hosted by the scheduler; absent in standalone provider setups
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
---@field targets? { scrollbar?: boolean, minimap?: boolean } Omitted defaults to scrollbar-only
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
---@field marks ScrollbarStoreSnapshot Immutable by convention; internal callers must not mutate it
---@field revision integer Monotonic revision for this buffer's mark collection
---@field compact_search? ScrollbarCompactSearch Private built-in search representation
---@field minimap_spans ScrollbarMinimapSpanStoreSnapshot Immutable by convention; internal callers must not mutate it
---@field minimap_span_revision integer Monotonic revision for this buffer's minimap spans

---@class ScrollbarWindowStoreTrustedSnapshot
---@field marks ScrollbarWindowStoreSnapshot Immutable by convention; internal callers must not mutate it
---@field revision integer Monotonic revision for this window's mark collection
---@field minimap_points ScrollbarMinimapPointStoreSnapshot Immutable by convention; internal callers must not mutate it
---@field minimap_point_revision integer Monotonic revision for this window's minimap points

---@alias ScrollbarChangedBuffers table<integer, true>
---@alias ScrollbarChangedWindows table<integer, true>

---@class ScrollbarHighlightSpan
---@field start_col integer Zero-based byte column
---@field end_col integer Exclusive zero-based byte column
---@field highlight string
---@field priority integer Stable compositor stack priority

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
---@field line_count integer Logical source-buffer line count
---@field top_line integer Zero-based first visible logical line
---@field bottom_line integer Zero-based last visible logical line
---@field marks ScrollbarMark[]
---@field mark_rows? integer[] Precomputed mark rows aligned with marks

---@class ScrollbarNormalizedMarkGeometryInput
---@field height integer Track height in rows
---@field line_count integer Logical source-buffer line count
---@field marks ScrollbarMark[]
---@field previous? { rows: integer[], line_count: number, height?: integer, segments?: integer[][] } Prior rows plus the context needed to recompute only shifted entries

---@class ScrollbarScreenGeometryInput
---@field source_win integer
---@field height integer Track height in rows
---@field marks ScrollbarMark[]
---@field marks_sorted? boolean Marks already ordered per provider by (line, text); skips the dedup/sort pass
---@field compact_search? ScrollbarCompactSearch Private built-in search matches projected into compact_mark_rows

---@class ScrollbarGeometry
---@field total_extent integer Logical lines or rendered screen rows
---@field viewport_start integer Zero-based document coordinate
---@field viewport_end integer Zero-based inclusive document coordinate
---@field mark_rows integer[] Track rows aligned with the input marks
---@field compact_mark_rows? integer[] Track rows aligned with compact_search entries; only produced by M.screen
---@field handle ScrollbarVerticalHandleGeometry

---@class ScrollbarLayoutInput
---@field config ScrollbarConfig
---@field height integer
---@field line_count? integer Logical line count required by compact line-mode search
---@field container_width? integer Placement container width; defaults to normalized layout width
---@field geometry ScrollbarGeometry
---@field marks ScrollbarLayoutMark[] Marks aligned with geometry.mark_rows
---@field mark_layer? ScrollbarResolvedMarkLayer Precomputed static placed mark cells and resolved width
---@field compact_search? ScrollbarCompactSearch Private built-in search matches

---@class ScrollbarMarkLayerInput
---@field config ScrollbarConfig
---@field height integer
---@field line_count? integer Logical line count required by compact line-mode search
---@field container_width? integer Placement container width; defaults to normalized layout width
---@field geometry { mark_rows: integer[], compact_mark_rows?: integer[] }
---@field marks ScrollbarLayoutMark[]
---@field marks_sorted? boolean Marks already ordered per provider by (line, text); skips grouping sorts
---@field compact_search? ScrollbarCompactSearch Private built-in search matches
---@field previous? { layer: table, changed: table[] } Previous layer plus the {index, old_row} shift list for incremental row rebuilds

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

---@class ScrollbarResolvedMarkLayer
---@field rows table<integer, table<integer, table<integer, ScrollbarPlacedMark>>> Placed cells by row, lane, and display column
---@field width integer Effective total layout width
---@field column_offset integer East-anchor translation applied to base content
---@field expanded_lane_id false|integer
---@field marks_identity ScrollbarLayoutMark[] Identity of the marks list the layer was built from
---@field segments? integer[][] Provider segments as [first, last] index ranges over line-sorted marks; nil when unavailable
---@field height integer Track height the layer was built for
---@field mark_rows integer[] Track rows aligned with marks_identity

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
---@field config ScrollbarConfig Effective config that produced this rendered state
---@field variant_id integer Stable selected variant ID; root is 0
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
---@field hidden_by_cursor boolean
---@field geometry ScrollbarRendererGeometry
---@field footprint? ScrollbarStackFootprint Own stacking footprint from the last render

---@class ScrollbarFlattenedMarksCache
---@field source_buf integer
---@field buffer_revision integer
---@field window_revision integer
---@field marks ScrollbarLayoutMark[]
---@field compact_search? ScrollbarCompactSearch

---@class ScrollbarLineMarkLayerCache
---@field source_buf integer
---@field buffer_revision integer
---@field window_revision integer
---@field line_count integer
---@field container_width integer
---@field height integer
---@field config table Precompiled cache-relevant inputs for the selected variant
---@field marks ScrollbarLayoutMark[] Identity of the flattened marks the rows and layer were built from
---@field mark_rows integer[]
---@field layer ScrollbarResolvedMarkLayer

---@class ScrollbarRendererPolicy
---@field is_buffer_eligible fun(bufnr: integer): boolean
---@field is_source_window fun(winid: integer): boolean
---@field source_windows fun(bufnr?: integer): integer[]

---@class ScrollbarSchedulerRenderer: ScrollbarRendererPolicy
---@field render fun(source_win: integer): ScrollbarWindowState?
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
---@field float_win integer
---@field float_buf integer
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
