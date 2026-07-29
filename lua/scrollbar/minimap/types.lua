---@meta

--- Minimap-specific type definitions. Mirrors the shape of
--- `lua/scrollbar/types.lua` but owned by the minimap subsystem so the schema
--- can evolve independently. Shared aliases (visibility, placement relative,
--- anchor, gutter modes) are reused from the scrollbar type surface since they
--- are identical enums; the minimap defines its own backend alias.

---@alias ScrollbarMinimapBackend "worker"|"sync"

---@class ScrollbarMinimapUserPlacement
---@field relative? ScrollbarPlacementRelative
---@field anchor? ScrollbarFloatAnchor
---@field row? integer
---@field col? integer
---@field gutter? ScrollbarGutterMode
---@field gutter_position? ScrollbarGutterPosition

---@class ScrollbarMinimapUserFloatConfig
---@field zindex? integer
---@field blend? integer
---@field hide_on_cursor? boolean
---@field placement? ScrollbarMinimapUserPlacement

---@class ScrollbarMinimapUserBackgroundConfig
---@field blend? false|integer

---@class ScrollbarMinimapUserPresetFloatConfig
---@field placement? ScrollbarMinimapUserPlacement

---@class ScrollbarMinimapUserAutohideConfig
---@field enabled? boolean
---@field delay_ms? integer

---@class ScrollbarMinimapUserUpdateConfig
---@field events? string[]
---@field interval_ms? integer

---@class ScrollbarMinimapUserMouseConfig
---@field enabled? boolean

---@class ScrollbarMinimapUserOverlaysConfig
---@field enabled? boolean
---@field types? table<string, false|ScrollbarMinimapUserOverlaySpec>

---@class ScrollbarMinimapUserOverlaySpec
---@field priority? integer Lower values win ordinary-overlay collisions
---@field highlight? ScrollbarHighlight Highlight source group or direct definition

---@class ScrollbarMinimapUserProvidersConfig
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
---@field treesitter? boolean
---@field lsp_semantic_tokens? boolean

---@class ScrollbarMinimapUserPreset
---@field extends? string
---@field width? false|integer
---@field height? false|integer
---@field float? ScrollbarMinimapUserPresetFloatConfig
---@field overlays? ScrollbarMinimapUserOverlaysConfig
---@field show_viewport? boolean
---@field autohide? ScrollbarMinimapUserAutohideConfig
---@field visibility? ScrollbarVisibility

---@class ScrollbarMinimapUserProfileMatcher
---@field filetypes? string[]
---@field buftypes? string[]
---@field when? fun(context: ScrollbarProfileContext): boolean

---@class ScrollbarMinimapUserProfileConfig
---@field width? false|integer
---@field height? false|integer
---@field float? ScrollbarMinimapUserFloatConfig
---@field overlays? ScrollbarMinimapUserOverlaysConfig
---@field show_viewport? boolean
---@field mouse? ScrollbarMinimapUserMouseConfig
---@field content_glyph? string Single-width glyph used for occupied cells

---@class ScrollbarMinimapUserProfile
---@field match ScrollbarMinimapUserProfileMatcher
---@field preset? string
---@field config? ScrollbarMinimapUserProfileConfig

---@class ScrollbarMinimapUserConfig
---@field enabled? boolean
---@field visibility? ScrollbarVisibility
---@field set_highlights? boolean
---@field max_lines? false|integer
---@field autohide? ScrollbarMinimapUserAutohideConfig
---@field background? ScrollbarMinimapUserBackgroundConfig Root-only base surface policy; profiles and presets cannot override it
---@field float? ScrollbarMinimapUserFloatConfig
---@field width? false|integer
---@field height? false|integer
---@field mouse? ScrollbarMinimapUserMouseConfig
---@field backend? ScrollbarMinimapBackend
---@field update? ScrollbarMinimapUserUpdateConfig
---@field excluded_buftypes? string[]
---@field excluded_filetypes? string[]
---@field preset? string
---@field presets? table<string, ScrollbarMinimapUserPreset>
---@field profiles? ScrollbarMinimapUserProfile[]
---@field overlays? ScrollbarMinimapUserOverlaysConfig
---@field providers? ScrollbarMinimapUserProvidersConfig Setup-level built-in provider demand; profiles and presets cannot override it
---@field show_viewport? boolean
---@field content_glyph? string Single-width glyph used for occupied cells

---@class ScrollbarMinimapPlacement
---@field relative ScrollbarPlacementRelative
---@field anchor ScrollbarFloatAnchor
---@field row integer
---@field col integer
---@field gutter ScrollbarGutterMode
---@field gutter_position ScrollbarGutterPosition

---@class ScrollbarMinimapFloatConfig
---@field zindex integer
---@field blend integer
---@field hide_on_cursor boolean
---@field placement ScrollbarMinimapPlacement

---@class ScrollbarMinimapBackgroundConfig
---@field blend false|integer

---@class ScrollbarMinimapAutohideConfig
---@field enabled boolean
---@field delay_ms integer

---@class ScrollbarMinimapUpdateConfig
---@field events string[]
---@field interval_ms integer

---@class ScrollbarMinimapMouseConfig
---@field enabled boolean

---@class ScrollbarMinimapOverlaysConfig
---@field enabled boolean
---@field types table<string, ScrollbarMinimapOverlaySpec>

---@class ScrollbarMinimapOverlaySpec
---@field priority integer Lower values win ordinary-overlay collisions
---@field highlight ScrollbarHighlight Highlight source used by automatic generation
---@field group string Compiled renderer-facing minimap highlight group

---@class ScrollbarMinimapProvidersConfig
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

---@class ScrollbarMinimapConfig
---@field enabled boolean
---@field visibility ScrollbarVisibility
---@field set_highlights boolean
---@field max_lines false|integer
---@field autohide ScrollbarMinimapAutohideConfig
---@field background ScrollbarMinimapBackgroundConfig
---@field float ScrollbarMinimapFloatConfig
---@field width false|integer
---@field height false|integer
---@field mouse ScrollbarMinimapMouseConfig
---@field backend ScrollbarMinimapBackend
---@field update ScrollbarMinimapUpdateConfig
---@field excluded_buftypes string[]
---@field excluded_filetypes string[]
---@field overlays ScrollbarMinimapOverlaysConfig
---@field providers ScrollbarMinimapProvidersConfig
---@field show_viewport boolean
---@field content_glyph string Single-width glyph used for occupied cells

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
---@field char " "|"█" Canonical empty or occupied value from squash output
---@field hl_group string|nil

---@class ScrollbarMinimapOverlay
---@field source_line integer Zero-based source buffer line
---@field minimap_row integer 1-based target row in the minimap grid
---@field mark_type string Mark type (e.g. "Error", "Search")
---@field priority integer Lower wins collisions using the selected minimap overlay spec
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
---@field render fun(source_win: integer)
---@field reveal? fun(source_win: integer): boolean
---@field conceal? fun(source_win: integer): boolean
---@field is_visible? fun(): boolean

---@class ScrollbarMinimapSchedulerOptions
---@field config? ScrollbarMinimapConfig
---@field renderer? ScrollbarMinimapSchedulerRenderer
---@field on_colorscheme? fun()

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
---@field unsubscribe_store fun()

---@class ScrollbarMinimapHighlightSpan
---@field start_col integer One-based minimap cell boundary, inclusive
---@field end_col integer One-based minimap cell boundary, exclusive
---@field highlight string
---@field priority integer

---@class ScrollbarMinimapCellCache
---@field signature string
---@field cells ScrollbarMinimapCell[][]
---@field revision integer
---@field changedtick integer
---@field semantic_revision integer
---@field filetype string
---@field source_line_count integer
---@field max_line_width integer Display width of the longest source line
---@field mirror_signature string

---@class ScrollbarMinimapPendingCells
---@field changedtick integer
---@field semantic_revision integer
---@field generation integer
---@field filetype string

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

---@class ScrollbarMinimapRendererWorker
---@field request fun(request: table): boolean

---@class ScrollbarMinimapRendererOverlays
---@field project_with fun(source_win: integer, minimap_height: integer, source_line_count: integer, presentation?: ScrollbarMinimapOverlaysConfig): ScrollbarMinimapOverlay[]

---@class ScrollbarMinimapRendererOptions
---@field config? ScrollbarMinimapConfig
---@field worker? ScrollbarMinimapRendererWorker
---@field overlays? ScrollbarMinimapRendererOverlays
---@field on_dirty? fun(source_win: integer)
---@field visible? boolean

---@class ScrollbarMinimapMouseRenderer
---@field get_state_by_float fun(float_win: integer): ScrollbarMinimapRendererState?
---@field is_owned_window fun(winid: integer): boolean
---@field set_state_callback fun(callback: fun(state: ScrollbarMinimapRendererState)?)

---@class ScrollbarMinimapMouseScheduler
---@field invalidate_window fun(winid: integer): boolean

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
---@field source_line_count integer
---@field v_ratio number
---@field pressed_row integer 0-based minimap row at press time
---@field dragging boolean

return {}
