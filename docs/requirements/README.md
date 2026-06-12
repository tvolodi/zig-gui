# Requirements index

Each file in this directory is a behavioral specification for one roadmap item.
Files are named `R<id>_<slug>.md` where `<id>` matches the milestone table numbering.

## Milestone 1 — It runs

| File | Roadmap item | Status |
|---|---|---|
| [R10_app_main_loop.md](R10_app_main_loop.md) | M1-01 — App main loop | `done` |
| [R11_event_delivery.md](R11_event_delivery.md) | M1-02 — Event delivery | `done` |
| [R12_window_resize.md](R12_window_resize.md) | M1-03 — Window resize handling | `done` |
| [R13_frame_pacing.md](R13_frame_pacing.md) | M1-04 — Frame pacing | `done` |

Implementation order: R10 first (establishes `App`), then R11/R13 in parallel (they touch
different parts of the frame loop), then R12 (depends on both Platform callbacks and the
resize path that R10 sketches).

## Milestone 2 — State and reactivity

| File | Roadmap item | Status |
|---|---|---|
| [R20_signal_type.md](R20_signal_type.md) | M2-01 — Signal type | `planned` |
| [R21_dirty_scan.md](R21_dirty_scan.md) | M2-02 — Dirty bitset scan | `planned` |
| [R22_computed_signals.md](R22_computed_signals.md) | M2-03 — Computed / derived signals | `planned` |
| [R23_static_binding.md](R23_static_binding.md) | M2-04 — Static screen data binding | `planned` |

Implementation order: R20 first (`Signal(T)` is the foundation), then R21 (dirty scan
modifies the frame loop and adds `ElementStore` helpers), then R22 (extends `signal.zig`
with `Computed(T)`, depends on `StaleFn` from R20), then R23 (binding layer, depends on
R20 for `Signal.subscribe` and R21 for the `refreshBindings` stub in `App.run()`).

## Milestone 3 — Interactive widgets

| File | Roadmap item | Status |
|---|---|---|
| [R30_focus_model.md](R30_focus_model.md) | M3-01 — Focus model | `done` |
| [R31_button_interaction.md](R31_button_interaction.md) | M3-02 — Button interaction | `done` |
| [R32_text_input_editing.md](R32_text_input_editing.md) | M3-03 — Text input editing | `done` |
| [R33_dropdown_open_close.md](R33_dropdown_open_close.md) | M3-04 — Dropdown open/close | `done` |
| [R34_checkbox_widget.md](R34_checkbox_widget.md) | M3-05 — Checkbox widget | `done` |
| [R35_scroll_container.md](R35_scroll_container.md) | M3-06 — Scroll container | `done` |
| [R36_clipboard.md](R36_clipboard.md) | M3-07 — Clipboard | `done` |

Implementation order:
1. **R36 first** (Clipboard is a platform-level utility; needed by text input)
2. **R30 second** (Focus model is foundational; needed by all interactive widgets)
3. **R31, R32, R33, R34 in parallel** (Button, text input, dropdown, checkbox all depend on focus but not on each other)
4. **R35 last** (Scroll container depends on layout integration and renderer clipping; post-widget-core)

## Milestone 4 — Rendering completeness

| File | Roadmap item | Status |
|---|---|---|
| [R40_pseudo_state_styling.md](R40_pseudo_state_styling.md) | M4-01 — Pseudo-state styling | `planned` |
| [R41_overlay_z_layer.md](R41_overlay_z_layer.md) | M4-02 — Overlay / z-layer | `planned` |
| [R42_clipping_overflow_hidden.md](R42_clipping_overflow_hidden.md) | M4-03 — Clipping / overflow-hidden | `planned` |
| [R43_image_icon_rendering.md](R43_image_icon_rendering.md) | M4-04 — Image / icon rendering | `planned` |
| [R44_text_truncation_ellipsis.md](R44_text_truncation_ellipsis.md) | M4-05 — Text truncation with ellipsis | `planned` |
| [R45_opacity.md](R45_opacity.md) | M4-06 — Opacity | `planned` |
| [R46_box_shadow.md](R46_box_shadow.md) | M4-07 — Box shadow | `planned` |

Implementation order:
1. **R40 first** (Pseudo-state styling wires M3-01/M3-02 widget states to the renderer; needed by every interactive widget's visual feedback; also removes the R30 hardcoded focus ring)
2. **R42 second** (Clipping is needed by M3-06 scroll container and must land before scroll container ships)
3. **R41, R44, R45, R46 in parallel** (Overlay, truncation, opacity, box shadow are independent renderer features with no inter-dependencies)
4. **R43 last** (Image/icon rendering adds a second GPU atlas and a shader mode; requires the most GPU-side work and can land after the pure-CPU features)

## Milestone 5 — Markup and styling completeness

| File | Roadmap item | Status |
|---|---|---|
| [R50_inline_style_attributes.md](R50_inline_style_attributes.md) | M5-01 — Inline style attributes | `planned` |
| [R51_missing_tailwind_classes.md](R51_missing_tailwind_classes.md) | M5-02 — Missing Tailwind classes | `planned` |
| [R52_conditional_rendering.md](R52_conditional_rendering.md) | M5-03 — Conditional rendering | `planned` |
| [R53_list_rendering.md](R53_list_rendering.md) | M5-04 — List rendering | `planned` |
| [R54_markup_error_reporting.md](R54_markup_error_reporting.md) | M5-05 — Markup error reporting | `planned` |
| [R55_build_time_markup_codegen.md](R55_build_time_markup_codegen.md) | M5-06 — Build-time markup codegen tool | `planned` |
| [R56_hot_reload.md](R56_hot_reload.md) | M5-07 — Hot-reload | `planned` |

Implementation order:
1. **R54 first** (Error reporting changes `parse`'s signature — must land before anything else calls `parse`)
2. **R55 second** (Build-time codegen uses the updated `parse`; establishes the baked-file pattern before conditional/list rendering add complexity)
3. **R50 and R51 in parallel** (Inline styles and missing Tailwind classes are both pure additions to the resolver/instantiator; no inter-dependency)
4. **R52, R53 in parallel** (Conditional and list rendering both extend `BindingSet`; they touch different fields and can be developed concurrently, but both depend on R50/R51 being stable)
5. **R56 last** (Hot-reload depends on R54 for diagnostics, R55 for the baked-file understanding, and a stable scene/binding model from R52/R53)

## Milestone 6 — Text completeness

| File | Roadmap item | Status |
|---|---|---|
| [R60_bold_italic_variants.md](R60_bold_italic_variants.md) | M6-01 — Bold and italic variants | `planned` |
| [R61_mixed_font_sizes.md](R61_mixed_font_sizes.md) | M6-02 — Mixed font sizes in one scene | `planned` |
| [R62_text_selection.md](R62_text_selection.md) | M6-03 — Text selection | `planned` |
| [R63_textarea.md](R63_textarea.md) | M6-04 — Multi-line text input (Textarea) | `planned` |
| [R64_font_fallback.md](R64_font_fallback.md) | M6-05 — Font fallback | `planned` |

Implementation order:
1. **R61 first** (Mixed font sizes is the simplest and most self-contained; confirms the `GlyphKey.px` path works end-to-end before adding more complexity)
2. **R60 second** (Bold/italic builds on the confirmed atlas path from R61; introduces `FontFamily` and `FontVariant` which R64 extends)
3. **R64 third** (Font fallback extends `FontFamily` from R60; must ship before R62/R63 so that text layout is complete)
4. **R62 fourth** (Text selection depends on stable `layoutParagraph` + `PositionedGlyph.byte_offset`; extends `InputState` in a breaking way)
5. **R63 last** (Textarea is the most complex; depends on R62 for selection, R60 for font-family measurement, and M4-03 for scroll clipping)

## Milestone 7 — Component library

| File | Roadmap item | Status |
|---|---|---|
| [R70_checkbox_polished.md](R70_checkbox_polished.md) | M7-01 — Checkbox (polished, with label slot) | `planned` |
| [R71_radio_group.md](R71_radio_group.md) | M7-02 — Radio group | `planned` |
| [R72_slider.md](R72_slider.md) | M7-03 — Slider | `planned` |
| [R73_progress_spinner.md](R73_progress_spinner.md) | M7-04 — Progress bar / spinner | `planned` |
| [R74_toast_notification.md](R74_toast_notification.md) | M7-05 — Toast / notification | `planned` |
| [R75_modal_dialog.md](R75_modal_dialog.md) | M7-06 — Modal dialog | `planned` |
| [R76_tabs.md](R76_tabs.md) | M7-07 — Tabs | `planned` |
| [R77_accordion.md](R77_accordion.md) | M7-08 — Accordion / collapsible | `planned` |
| [R78_date_picker.md](R78_date_picker.md) | M7-09 — Date picker | `planned` |
| [R79_data_table.md](R79_data_table.md) | M7-10 — Data table | `planned` |
| [R7A_separator.md](R7A_separator.md) | M7-11 — Separator / divider | `planned` |
| [R7B_avatar_badge.md](R7B_avatar_badge.md) | M7-12 — Avatar / badge | `planned` |
| [R7C_tooltip.md](R7C_tooltip.md) | M7-13 — Tooltip | `planned` |
| [R7D_context_menu.md](R7D_context_menu.md) | M7-14 — Context menu | `planned` |

Implementation order:
1. **R7A first** (Separator — zero state, zero interaction; confirms the rendering path without new machinery)
2. **R70, R71, R72, R73 in parallel** (Checkbox polish, Radio, Slider, Progress/Spinner are independent stateful widgets with no overlay dependencies)
3. **R76, R77 in parallel** (Tabs and Accordion use `setHidden` from M5-03 but have no overlay dependency; can ship after the basic stateful widgets are stable)
4. **R74, R7B, R7C, R7D in parallel** (Toast, Avatar/Badge, Tooltip, Context Menu all use the overlay layer and `OverlayLayer`; they are independent of each other)
5. **R75 fifth** (Modal dialog requires the overlay layer and focus trapping; depends on the overlay work from step 4 being settled)
6. **R78 sixth** (Date picker requires the modal dialog from R75 and text input from M3-03)
7. **R79 last** (Data table is the most complex; requires scroll container from M3-06 and all rendering features from M4)

## Milestone 10 — Production hardening

| File | Roadmap item | Status |
|---|---|---|
| [RA0_error_boundary.md](RA0_error_boundary.md) | M10-01 — Error boundary / recovery | `done` |
| [RA1_memory_budget.md](RA1_memory_budget.md) | M10-02 — Memory budget enforcement | `done` |
| [RA2_release_logging.md](RA2_release_logging.md) | M10-03 — Release logging | `done` |
| [RA3_graceful_startup.md](RA3_graceful_startup.md) | M10-04 — Graceful startup failure | `done` |
| [RA4_window_state_persistence.md](RA4_window_state_persistence.md) | M10-05 — Window state persistence | `done` |

Implementation order:
1. **RA2 first** (FileLogger is standalone; no dependencies on other M10 items; needed by RA0 for logging captured errors)
2. **RA1 second** (BudgetedArena wraps the existing arena; standalone; needed by RA0 which may produce OOM)
3. **RA3 third** (showErrorDialog is standalone platform code; no M10 inter-dependencies)
4. **RA4 fourth** (WindowStateManager builds on PersistentSettings from M8-03; standalone)
5. **RA0 last** (ErrorBoundary depends on Navigator from M8-01; wires together the above logging/memory pieces)
