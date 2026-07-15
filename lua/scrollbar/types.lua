---@meta

---@alias ScrollbarVisibility "all"|"active"
---@alias ScrollbarGeometryMode "line"|"screen"
---@alias ScrollbarPlacementRelative "window"|"editor"
---@alias ScrollbarFloatAnchor "NW"|"NE"|"SW"|"SE"
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

---@class ScrollbarUserFloatConfig
---@field width? integer
---@field zindex? integer
---@field hide_on_cursor? boolean
---@field placement? ScrollbarUserPlacement

---@class ScrollbarUserTrackConfig
---@field highlight? ScrollbarHighlight

---@class ScrollbarUserRenderConfig
---@field interval_ms? integer
---@field geometry? ScrollbarGeometryMode

---@class ScrollbarUserAutohideConfig
---@field enabled? boolean
---@field delay_ms? integer

---@class ScrollbarUserMouseConfig
---@field enabled? boolean

---@class ScrollbarUserHandleConfig
---@field text? string
---@field column? integer
---@field width? integer
---@field blend? integer
---@field highlight? ScrollbarHighlight
---@field hide_if_all_visible? boolean

---@class ScrollbarUserMarkTypeConfig
---@field text? ScrollbarText
---@field column? integer
---@field priority? integer
---@field highlight? ScrollbarHighlight

---@class ScrollbarSearchProviderConfig
---@field incsearch? boolean
---@field backend ScrollbarSearchBackend

---@class ScrollbarUserSearchProviderConfig
---@field incsearch? boolean
---@field backend? ScrollbarSearchBackend

---@class ScrollbarMarksProviderConfig
---@field max_width false|integer
---@field letters boolean
---@field numbers boolean

---@class ScrollbarUserMarksProviderConfig
---@field max_width? integer
---@field letters? boolean
---@field numbers? boolean

---@class ScrollbarUserProvidersConfig
---@field cursor? boolean
---@field diagnostic? boolean
---@field search? boolean|ScrollbarUserSearchProviderConfig
---@field marks? boolean|ScrollbarUserMarksProviderConfig
---@field gitsigns? boolean
---@field mini_diff? boolean
---@field ale? boolean
---@field coc? boolean

---@class ScrollbarUserConfig
---@field show? boolean
---@field visibility? ScrollbarVisibility
---@field set_highlights? boolean
---@field max_lines? false|integer
---@field hide_if_all_visible? boolean
---@field autohide? ScrollbarUserAutohideConfig
---@field render? ScrollbarUserRenderConfig
---@field float? ScrollbarUserFloatConfig
---@field track? ScrollbarUserTrackConfig
---@field mouse? ScrollbarUserMouseConfig
---@field handle? ScrollbarUserHandleConfig
---@field marks? table<string, ScrollbarUserMarkTypeConfig>
---@field providers? ScrollbarUserProvidersConfig
---@field excluded_buftypes? string[]
---@field excluded_filetypes? string[]

---@class ScrollbarPlacement
---@field relative ScrollbarPlacementRelative
---@field anchor ScrollbarFloatAnchor
---@field row integer
---@field col integer

---@class ScrollbarFloatConfig
---@field width integer
---@field zindex integer
---@field hide_on_cursor boolean
---@field placement ScrollbarPlacement

---@class ScrollbarTrackConfig
---@field highlight ScrollbarHighlight

---@class ScrollbarRenderConfig
---@field interval_ms integer
---@field geometry ScrollbarGeometryMode

---@class ScrollbarAutohideConfig
---@field enabled boolean
---@field delay_ms integer

---@class ScrollbarMouseConfig
---@field enabled boolean

---@class ScrollbarHandleConfig
---@field text string
---@field column integer
---@field width integer
---@field blend integer
---@field highlight ScrollbarHighlight
---@field hide_if_all_visible boolean

---@class ScrollbarMarkTypeConfig
---@field text string[] Density variants ordered from least to most dense; an empty Mark list uses provider text
---@field column integer One-based display column
---@field priority integer
---@field highlight ScrollbarHighlight Source highlight group or direct definition

---@class ScrollbarProvidersConfig
---@field cursor boolean
---@field diagnostic boolean
---@field search false|ScrollbarSearchProviderConfig
---@field marks false|ScrollbarMarksProviderConfig
---@field gitsigns boolean
---@field mini_diff boolean
---@field ale boolean
---@field coc boolean

---@class ScrollbarConfig
---@field show boolean
---@field visibility ScrollbarVisibility
---@field set_highlights boolean
---@field max_lines false|integer
---@field hide_if_all_visible boolean
---@field autohide ScrollbarAutohideConfig
---@field render ScrollbarRenderConfig
---@field float ScrollbarFloatConfig
---@field track ScrollbarTrackConfig
---@field mouse ScrollbarMouseConfig
---@field handle ScrollbarHandleConfig
---@field marks table<string, ScrollbarMarkTypeConfig>
---@field providers ScrollbarProvidersConfig
---@field excluded_buftypes string[]
---@field excluded_filetypes string[]

---@class ScrollbarMark
---@field line integer Zero-based source buffer line
---@field type string Configured mark type
---@field text? string Per-mark text override

---@class ScrollbarCompactSearch
---@field data string Big-endian zero-based line numbers, four bytes per exact match
---@field count integer Exact match count

---@class ScrollbarLayoutMark: ScrollbarMark
---@field provider string Owning provider name used for deterministic ties and hit metadata

---@class ScrollbarProviderContext
---@field config ScrollbarConfig Provider-local snapshot; mutations cannot change root configuration
---@field set_marks fun(bufnr: integer, marks: ScrollbarMark[]): boolean
---@field clear_marks fun(bufnr?: integer): boolean
---@field set_window_marks fun(winid: integer, marks: ScrollbarMark[]): boolean
---@field clear_window_marks fun(winid?: integer): boolean
---@field create_augroup fun(name: string): integer
---@field add_cleanup fun(cleanup: fun())
---@field source_windows fun(bufnr?: integer): integer[]
---@field invalidate_buffer fun(bufnr: integer)
---@field invalidate_window fun(winid: integer)

---@class ScrollbarProvider
---@field name string
---@field setup? fun(context: ScrollbarProviderContext)
---@field refresh? fun(bufnr: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field refresh_window? fun(winid: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field dispose? fun(context: ScrollbarProviderContext)

---@alias ScrollbarStoreSnapshot table<string, ScrollbarMark[]>
---@alias ScrollbarWindowStoreSnapshot table<string, ScrollbarMark[]>

---@class ScrollbarStoreTrustedSnapshot
---@field marks ScrollbarStoreSnapshot Immutable by convention; internal callers must not mutate it
---@field revision integer Monotonic revision for this buffer's mark collection
---@field compact_search? ScrollbarCompactSearch Private built-in search representation

---@class ScrollbarWindowStoreTrustedSnapshot
---@field marks ScrollbarWindowStoreSnapshot Immutable by convention; internal callers must not mutate it
---@field revision integer Monotonic revision for this window's mark collection

---@alias ScrollbarChangedBuffers table<integer, true>
---@alias ScrollbarChangedWindows table<integer, true>

---@class ScrollbarHighlightSpan
---@field start_col integer Zero-based byte column
---@field end_col integer Exclusive zero-based byte column
---@field highlight string

---@class ScrollbarHitCell
---@field handle boolean Whether this display cell is inside the handle range
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

---@class ScrollbarScreenGeometryInput
---@field source_win integer
---@field height integer Track height in rows
---@field marks ScrollbarMark[]

---@class ScrollbarGeometry
---@field total_extent integer Logical lines or rendered screen rows
---@field viewport_start integer Zero-based document coordinate
---@field viewport_end integer Zero-based inclusive document coordinate
---@field mark_rows integer[] Track rows aligned with the input marks
---@field handle ScrollbarVerticalHandleGeometry

---@class ScrollbarLayoutInput
---@field config ScrollbarConfig
---@field height integer
---@field line_count? integer Logical line count required by compact line-mode search
---@field container_width? integer Placement container width; defaults to the configured base width
---@field geometry ScrollbarGeometry
---@field marks ScrollbarLayoutMark[] Marks aligned with geometry.mark_rows
---@field mark_layer? ScrollbarResolvedMarkLayer Precomputed static placed mark cells and resolved width
---@field compact_search? ScrollbarCompactSearch Private built-in search matches

---@class ScrollbarMarkLayerInput
---@field config ScrollbarConfig
---@field height integer
---@field line_count? integer Logical line count required by compact line-mode search
---@field container_width? integer Placement container width; defaults to the configured base width
---@field geometry { mark_rows: integer[] }
---@field marks ScrollbarLayoutMark[]
---@field compact_search? ScrollbarCompactSearch Private built-in search matches

---@class ScrollbarPlacedMark
---@field text string
---@field width integer
---@field column integer
---@field last_column integer
---@field type string
---@field provider string
---@field line integer
---@field lines integer[]

---@class ScrollbarResolvedMarkLayer
---@field rows ScrollbarPlacedMark[][] Placed mark cells by zero-based row
---@field width integer Effective total layout width
---@field column_offset integer East-anchor translation applied to base content

---@class ScrollbarLayoutOutput
---@field rows string[]
---@field width integer Effective total layout width
---@field highlights ScrollbarHighlightSpan[][]
---@field hitmap ScrollbarHitCell[][]
---@field handle ScrollbarHandleGeometry

---@class ScrollbarRendererGeometry
---@field mode ScrollbarGeometryMode
---@field total_extent integer
---@field viewport_start integer
---@field viewport_end integer

---@class ScrollbarWindowState
---@field source_win integer
---@field source_buf integer
---@field float_win integer
---@field float_buf integer
---@field float_config table<string, any> Last applied floating-window configuration
---@field width integer Float width used for the row cache
---@field height integer Float height used for the row cache
---@field rows string[]
---@field highlights ScrollbarHighlightSpan[][]
---@field rendered_highlights ScrollbarHighlightSpan[][]
---@field hitmap ScrollbarHitCell[][]
---@field handle ScrollbarHandleGeometry
---@field handle_pressed boolean
---@field hidden_by_cursor boolean
---@field geometry ScrollbarRendererGeometry

---@class ScrollbarFlattenedMarksCache
---@field source_buf integer
---@field buffer_revision integer
---@field window_revision integer
---@field marks ScrollbarLayoutMark[]
---@field compact_search? ScrollbarCompactSearch
---@field expanded_marks? ScrollbarLayoutMark[] Exact screen-mode expansion, intentionally expensive

---@class ScrollbarLineMarkLayerCache
---@field source_buf integer
---@field buffer_revision integer
---@field window_revision integer
---@field line_count integer
---@field container_width integer
---@field height integer
---@field config_generation integer
---@field mark_rows integer[]
---@field layer ScrollbarResolvedMarkLayer

---@class ScrollbarSchedulerRenderer
---@field render fun(source_win: integer): ScrollbarWindowState?
---@field reveal? fun(source_win: integer): boolean
---@field conceal? fun(source_win: integer): boolean
---@field source_windows fun(bufnr?: integer): integer[]
---@field is_visible? fun(): boolean
---@field is_owned_window? fun(winid: integer): boolean

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
---@field hide_timers table<integer, any>
---@field hide_generations table<integer, integer>
---@field held table<integer, true>

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
---@field handle ScrollbarHandleGeometry
---@field handle_grab_offset? integer
---@field last_row integer
---@field last_col integer
---@field dragging boolean

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
