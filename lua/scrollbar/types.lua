---@meta

---@alias ScrollbarVisibility "all"|"active"
---@alias ScrollbarGeometryMode "line"|"screen"
---@alias ScrollbarPlacementRelative "window"|"editor"
---@alias ScrollbarFloatAnchor "NW"|"NE"|"SW"|"SE"
---@alias ScrollbarText string|string[]
---@alias ScrollbarHighlightDefinition table<string, any> A table accepted by nvim_set_hl()
---@alias ScrollbarHighlight string|ScrollbarHighlightDefinition
---@alias ScrollbarProviderOption boolean|ScrollbarSearchProviderConfig

---@class ScrollbarUserPlacement
---@field relative? ScrollbarPlacementRelative
---@field anchor? ScrollbarFloatAnchor
---@field row? integer
---@field col? integer

---@class ScrollbarUserFloatConfig
---@field width? integer
---@field zindex? integer
---@field placement? ScrollbarUserPlacement

---@class ScrollbarUserRenderConfig
---@field interval_ms? integer
---@field geometry? ScrollbarGeometryMode

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
---@field live boolean

---@class ScrollbarUserSearchProviderConfig
---@field live? boolean

---@class ScrollbarUserProvidersConfig
---@field cursor? boolean
---@field diagnostic? boolean
---@field search? boolean|ScrollbarUserSearchProviderConfig
---@field gitsigns? boolean
---@field ale? boolean
---@field coc? boolean

---@class ScrollbarUserConfig
---@field show? boolean
---@field visibility? ScrollbarVisibility
---@field set_highlights? boolean
---@field max_lines? false|integer
---@field hide_if_all_visible? boolean
---@field render? ScrollbarUserRenderConfig
---@field float? ScrollbarUserFloatConfig
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
---@field placement ScrollbarPlacement

---@class ScrollbarRenderConfig
---@field interval_ms integer
---@field geometry ScrollbarGeometryMode

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
---@field text string[] Density variants ordered from least to most dense
---@field column integer One-based display column
---@field priority integer
---@field highlight ScrollbarHighlight Source highlight group or direct definition

---@class ScrollbarProvidersConfig
---@field cursor boolean
---@field diagnostic boolean
---@field search false|ScrollbarSearchProviderConfig
---@field gitsigns boolean
---@field ale boolean
---@field coc boolean

---@class ScrollbarConfig
---@field show boolean
---@field visibility ScrollbarVisibility
---@field set_highlights boolean
---@field max_lines false|integer
---@field hide_if_all_visible boolean
---@field render ScrollbarRenderConfig
---@field float ScrollbarFloatConfig
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

---@class ScrollbarLayoutMark: ScrollbarMark
---@field provider string Owning provider name used for deterministic ties and hit metadata

---@class ScrollbarProviderContext
---@field config ScrollbarConfig Provider-local snapshot; mutations cannot change root configuration
---@field set_marks fun(bufnr: integer, marks: ScrollbarMark[]): boolean
---@field clear_marks fun(bufnr?: integer): boolean
---@field create_augroup fun(name: string): integer
---@field add_cleanup fun(cleanup: fun())
---@field source_windows fun(bufnr?: integer): integer[]
---@field invalidate_buffer fun(bufnr: integer)
---@field invalidate_window fun(winid: integer)

---@class ScrollbarProvider
---@field name string
---@field setup? fun(context: ScrollbarProviderContext)
---@field refresh? fun(bufnr: integer, context: ScrollbarProviderContext): ScrollbarMark[]?
---@field dispose? fun(context: ScrollbarProviderContext)

---@alias ScrollbarStoreSnapshot table<string, ScrollbarMark[]>
---@alias ScrollbarChangedBuffers table<integer, true>

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
---@field geometry ScrollbarGeometry
---@field marks ScrollbarLayoutMark[] Marks aligned with geometry.mark_rows

---@class ScrollbarLayoutOutput
---@field rows string[]
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
---@field width integer Float width used for the row cache
---@field height integer Float height used for the row cache
---@field rows string[]
---@field highlights ScrollbarHighlightSpan[][]
---@field hitmap ScrollbarHitCell[][]
---@field handle ScrollbarHandleGeometry
---@field geometry ScrollbarRendererGeometry

---@class ScrollbarSchedulerRenderer
---@field render fun(source_win: integer): ScrollbarWindowState?
---@field source_windows fun(bufnr?: integer): integer[]
---@field is_owned_window? fun(winid: integer): boolean

---@class ScrollbarSchedulerOptions
---@field config? ScrollbarConfig
---@field renderer? ScrollbarSchedulerRenderer
---@field on_colorscheme? fun()

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
---@field pressed_hit ScrollbarHitCell
---@field handle ScrollbarHandleGeometry
---@field handle_grab_offset? integer
---@field last_row integer
---@field last_col integer
---@field dragging boolean

---@class ScrollbarMouseRenderer
---@field get_state_by_float fun(float_win: integer): ScrollbarWindowState?
---@field is_owned_window fun(winid: integer): boolean
---@field set_state_callback fun(callback: fun(state: ScrollbarWindowState)?)

---@class ScrollbarMouseScheduler
---@field invalidate_window fun(winid: integer): boolean

---@class ScrollbarMouseOptions
---@field config? ScrollbarConfig
---@field renderer? ScrollbarMouseRenderer
---@field scheduler? ScrollbarMouseScheduler

return {}
