---@meta

---@alias ScrollbarVisibility "all"|"active"
---@alias ScrollbarGeometryMode "line"|"screen"
---@alias ScrollbarPlacementRelative "window"|"editor"
---@alias ScrollbarFloatAnchor "NW"|"NE"|"SW"|"SE"
---@alias ScrollbarGutterMode "avoid"|"overlap"
---@alias ScrollbarGutterPosition "inner"|"outer"
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
---@field gutter? ScrollbarGutterMode
---@field gutter_position? ScrollbarGutterPosition

---@class ScrollbarUserFloatConfig
---@field zindex? integer
---@field hide_on_cursor? boolean
---@field placement? ScrollbarUserPlacement

---@class ScrollbarUserMarkLayer
---@field kind "marks"
---@field types? string[] Mark types routed to this lane; omitted means catch-all
---@field max_width? integer Total named-Mark lane width including declared columns

---@alias ScrollbarUserLayoutLayer "track"|"thumb"|"marks"|ScrollbarUserMarkLayer

---@class ScrollbarUserLayoutConfig
---@field direction? ScrollbarLayoutDirection
---@field columns? ScrollbarUserLayoutLayer[][] Logical columns whose layers are ordered bottom-to-top

---@class ScrollbarUserTrackConfig
---@field highlight? ScrollbarHighlight

---@class ScrollbarUserRenderConfig
---@field geometry? ScrollbarGeometryMode

---@class ScrollbarUserUpdateConfig
---@field events? string[]
---@field interval_ms? integer

---@class ScrollbarUserAutohideConfig
---@field enabled? boolean
---@field delay_ms? integer

---@class ScrollbarUserMouseConfig
---@field enabled? boolean

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

---@class ScrollbarUserSearchProviderConfig
---@field incsearch? boolean
---@field backend? ScrollbarSearchBackend

---@class ScrollbarMarksProviderConfig
---@field letters boolean
---@field numbers boolean

---@class ScrollbarUserMarksProviderConfig
---@field letters? boolean
---@field numbers? boolean

---@class ScrollbarUserPreset
---@field extends? string
---@field layout? ScrollbarUserLayoutConfig
---@field track? ScrollbarUserTrackConfig
---@field thumb? ScrollbarUserThumbConfig
---@field marks? table<string, ScrollbarUserMarkTypeConfig>
---@field float? { placement?: ScrollbarUserPlacement }

---@class ScrollbarUserProfileMatcher
---@field filetypes? string[]
---@field buftypes? string[]
---@field when? fun(context: ScrollbarProfileContext): boolean

---@class ScrollbarUserProfileConfig
---@field hide_if_all_visible? boolean
---@field render? { geometry?: ScrollbarGeometryMode }
---@field float? ScrollbarUserFloatConfig
---@field layout? ScrollbarUserLayoutConfig
---@field track? ScrollbarUserTrackConfig
---@field mouse? ScrollbarUserMouseConfig
---@field thumb? ScrollbarUserThumbConfig
---@field marks? table<string, ScrollbarUserMarkTypeConfig>

---@class ScrollbarUserProfile
---@field match ScrollbarUserProfileMatcher
---@field preset? string
---@field config? ScrollbarUserProfileConfig

---@class ScrollbarUserProvidersConfig
---@field cursor? boolean
---@field diagnostic? boolean
---@field search? boolean|ScrollbarUserSearchProviderConfig
---@field marks? boolean|ScrollbarUserMarksProviderConfig
---@field gitsigns? boolean
---@field mini_diff? boolean
---@field signify? boolean
---@field vgit? boolean
---@field ale? boolean
---@field coc? boolean

---@class ScrollbarUserConfig
---@field preset? string Setup-local selected presentation preset
---@field presets? table<string, ScrollbarUserPreset> Setup-local preset definitions
---@field profiles? ScrollbarUserProfile[] Ordered setup-local contextual variants; first match wins
---@field show? boolean
---@field visibility? ScrollbarVisibility
---@field set_highlights? boolean
---@field max_lines? false|integer
---@field hide_if_all_visible? boolean
---@field autohide? ScrollbarUserAutohideConfig
---@field update? ScrollbarUserUpdateConfig
---@field render? ScrollbarUserRenderConfig
---@field float? ScrollbarUserFloatConfig
---@field layout? ScrollbarUserLayoutConfig
---@field track? ScrollbarUserTrackConfig
---@field mouse? ScrollbarUserMouseConfig
---@field thumb? ScrollbarUserThumbConfig
---@field marks? table<string, ScrollbarUserMarkTypeConfig>
---@field providers? ScrollbarUserProvidersConfig
---@field excluded_buftypes? string[]
---@field excluded_filetypes? string[]

---@class ScrollbarTopLevelConfig
---@field scrollbar? ScrollbarUserConfig
---@field minimap? ScrollbarMinimapUserConfig

---@class ScrollbarPlacement
---@field relative ScrollbarPlacementRelative
---@field anchor ScrollbarFloatAnchor
---@field row integer
---@field col integer
---@field gutter ScrollbarGutterMode
---@field gutter_position ScrollbarGutterPosition

---@class ScrollbarFloatConfig
---@field zindex integer
---@field hide_on_cursor boolean
---@field placement ScrollbarPlacement

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

---@class ScrollbarRenderConfig
---@field geometry ScrollbarGeometryMode

---@class ScrollbarUpdateConfig
---@field events string[]
---@field interval_ms integer

---@class ScrollbarAutohideConfig
---@field enabled boolean
---@field delay_ms integer

---@class ScrollbarMouseConfig
---@field enabled boolean

---@class ScrollbarThumbConfig
---@field text string
---@field blend integer
---@field highlight ScrollbarHighlight
---@field hide_if_all_visible boolean

---@class ScrollbarMarkTypeConfig
---@field text string[] Density variants ordered from least to most dense; an empty Mark list uses provider text
---@field priority integer
---@field highlight ScrollbarHighlight Source highlight group or direct definition

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
---@field show boolean
---@field visibility ScrollbarVisibility
---@field set_highlights boolean
---@field max_lines false|integer
---@field hide_if_all_visible boolean
---@field autohide ScrollbarAutohideConfig
---@field update ScrollbarUpdateConfig
---@field render ScrollbarRenderConfig
---@field float ScrollbarFloatConfig
---@field layout ScrollbarLayoutConfig
---@field track ScrollbarTrackConfig
---@field mouse ScrollbarMouseConfig
---@field thumb ScrollbarThumbConfig
---@field marks table<string, ScrollbarMarkTypeConfig>
---@field highlights ScrollbarHighlightGroups Compiled canonical or profile-internal group names
---@field layout_cache table Precompiled static line-layer cache inputs
---@field providers ScrollbarProvidersConfig
---@field excluded_buftypes string[]
---@field excluded_filetypes string[]

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
---@field mode ScrollbarGeometryMode
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

---@class ScrollbarSchedulerOptions
---@field config? ScrollbarConfig
---@field renderer? ScrollbarSchedulerRenderer
---@field on_colorscheme? fun()

---@class ScrollbarSchedulerRuntime
---@field config ScrollbarConfig
---@field renderer ScrollbarSchedulerRenderer
---@field on_colorscheme fun()
---@field timer any
---@field timer_armed boolean
---@field dirty table<integer, true>
---@field flushing boolean
---@field augroup integer
---@field uv any
---@field text_events table<string, boolean> Text-change autocmd events registered for subscriber dispatch
---@field cursor_events table<string, boolean> Cursor-activity autocmd events registered for subscriber dispatch
---@field hide_timers table<integer, any>
---@field hide_generations table<integer, integer>
---@field held table<integer, true>
---@field unsubscribe_store fun()

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
---@field is_owned_window fun(winid: integer): boolean
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
