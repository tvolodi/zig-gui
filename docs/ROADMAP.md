# zig-gui Roadmap

> This document lists everything needed to turn the current architecture skeleton into a
> framework you would actually ship a product with. Items are grouped by theme, ordered
> roughly by dependency, and tagged with a milestone. Detailed requirements for each item
> live in (or will live in) `docs/requirements/`.
>
> **Status key:** `done` · `in-progress` · `planned` · `post-v2`

---

## Milestone 0 — Foundation (modules 01–09) `in-progress`

The architecture skeleton: platform, text, element store, layout, theme, markup, components,
schema forms, renderer. Modules are numbered in `docs/specs/`.

| # | Feature | Status |
|---|---|---|
| 01 | GLFW window + Vulkan swapchain | `done` |
| 02 | Glyph atlas, kerning, line breaking | `done` |
| 03 | Element store (generational handles, parallel arrays, arena) | `done` |
| 04 | Layout engine (flexbox + grid) | `done` |
| 05 | Four-layer token model, light/dark theme | `done` |
| 06 | `.ui` markup parser, Tailwind-subset resolver | `done` |
| 07 | Component instantiation, Scene, measure pass | `done` |
| 08 | Schema-driven forms, Value tree, validator | `done` |
| 09 | DrawCommand serializer, quad pipeline, atlas GPU upload | `planned` |

---

## Milestone 1 — It runs `done`

The framework produces pixels and responds to the user.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M1-01 | **App main loop** — single `App.run()` entry point that owns platform, backend, scene, font, and drives the frame lifecycle in the correct order | 09 | [R10](requirements/R10_app_main_loop.md) | `done` |
| M1-02 | **Event delivery** — expose mouse position, mouse buttons, scroll wheel, keyboard keys, and text-input characters from GLFW to app code | 01 | [R11](requirements/R11_event_delivery.md) | `done` |
| M1-03 | **Window resize handling** — propagate framebuffer resize to layout and renderer automatically | 01, 09 | [R12](requirements/R12_window_resize.md) | `done` |
| M1-04 | **Frame pacing** — vsync / present-mode selection; don't spin at 100% CPU when idle | 01 | [R13](requirements/R13_frame_pacing.md) | `done` |

---

## Milestone 2 — State and reactivity `done`

The UI reflects changing data without rebuilding everything from scratch every frame.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M2-01 | **Signal type** — `Signal(T)` with `get` / `set`; `set` marks affected elements dirty | M1 | [R20](requirements/R20_signal_type.md) | `done` |
| M2-02 | **Dirty bitset scan** — per-frame linear scan over dirty indices; re-layout and re-paint only dirty subtrees | M2-01 | [R21](requirements/R21_dirty_scan.md) | `done` |
| M2-03 | **Computed / derived signals** — a signal whose value is a pure function of other signals; invalidated automatically | M2-01 | [R22](requirements/R22_computed_signals.md) | `done` |
| M2-04 | **Static screen data binding** — comptime field-offset binding for static `.ui` screens (INV-4.1); typed, zero-runtime-path-resolution | M2-01 | [R23](requirements/R23_static_binding.md) | `done` |

---

## Milestone 3 — Interactive widgets `done`

Widgets respond to input. A form can actually be filled out.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M3-01 | **Focus model** — focused-element index, Tab/Shift-Tab navigation, visual focus ring | M1-02 | [R30](requirements/R30_focus_model.md) | `done` |
| M3-02 | **Button interaction** — hover, pressed, disabled visual states; `on_click` callback | M1-02, M3-01 | [R31](requirements/R31_button_interaction.md) | `done` |
| M3-03 | **Text input editing** — cursor, selection, insert/delete, clipboard paste; stores state in a parallel array in `Scene` | M1-02, M3-01 | [R32](requirements/R32_text_input_editing.md) | `done` |
| M3-04 | **Dropdown open/close** — overlay list, keyboard navigation, value selection | M1-02, M3-01, M4-02 | [R33](requirements/R33_dropdown_open_close.md) | `done` |
| M3-05 | **Checkbox widget** — boolean toggle; replaces the Dropdown workaround in schema forms | M1-02, M3-01 | [R34](requirements/R34_checkbox_widget.md) | `done` |
| M3-06 | **Scroll container** — per-element scroll offset stored in `Scene`; mouse wheel + drag scrollbar | M1-02 | [R35](requirements/R35_scroll_container.md) | `done` |
| M3-07 | **Clipboard** — read/write via `glfwGetClipboardString` / `glfwSetClipboardString` | M1-02 | [R36](requirements/R36_clipboard.md) | `done` |

---

## Milestone 4 — Rendering completeness `done`

The renderer draws everything a real UI needs.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M4-01 | **Pseudo-state styling** — hover / focus / active / disabled style variants stored as token overrides; applied by the renderer based on widget state | 09, M3-01 | [R40](requirements/R40_pseudo_state_styling.md) | `done` |
| M4-02 | **Overlay / z-layer** — a second draw pass for popups, dropdowns, and tooltips rendered above the main layer | 09 | [R41](requirements/R41_overlay_z_layer.md) | `done` |
| M4-03 | **Clipping / overflow-hidden** — scissor rect per scroll container; clip children to parent bounds | 09 | [R42](requirements/R42_clipping_overflow_hidden.md) | `done` |
| M4-04 | **Image / icon rendering** — RGBA texture tiles in the draw command list; `GlyphAtlas` or a separate `ImageAtlas` | 09 | [R43](requirements/R43_image_icon_rendering.md) | `done` |
| M4-05 | **Text truncation with ellipsis** — `text-overflow: ellipsis` when text exceeds container width | 02, 09 | [R44](requirements/R44_text_truncation_ellipsis.md) | `done` |
| M4-06 | **Opacity** — per-element alpha multiplier applied at paint time | 09 | [R45](requirements/R45_opacity.md) | `done` |
| M4-07 | **Box shadow** — single-level drop shadow as a blurred rect drawn behind the element | 09 | [R46](requirements/R46_box_shadow.md) | `done` |

---

## Milestone 5 — Markup and styling completeness `done`

The authoring surface covers the common cases without forcing escape to raw Zig.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M5-01 | **Inline style attributes** — `style:background`, `style:color`, etc. on any markup node; overrides token-derived defaults for dynamic content | 06 | [R50](requirements/R50_inline_style_attributes.md) | `done` |
| M5-02 | **Missing Tailwind classes** — `hidden`, `overflow-hidden`, `min-w-*`, `max-w-*`, `w-{n}`, `h-{n}`, `mx-auto`, `shrink-0`, `grow-0`, `self-*`, `col-span-*`, `row-span-*`, `opacity-*` | 06 | [R51](requirements/R51_missing_tailwind_classes.md) | `done` |
| M5-03 | **Conditional rendering** — `if="{bind condition}"` attribute hides/shows a subtree | M2-04 | [R52](requirements/R52_conditional_rendering.md) | `done` |
| M5-04 | **List rendering** — `for="{bind items}"` repeats a child template over a collection | M2-04 | [R53](requirements/R53_list_rendering.md) | `done` |
| M5-05 | **Markup error reporting** — parse errors include line number and column, not just an enum variant | 06 | [R54](requirements/R54_markup_error_reporting.md) | `done` |
| M5-06 | **Build-time markup codegen tool** — `build.zig` step that runs `parse` over `.ui` files and emits `.zig` struct literals; no parser in the production binary (INV-4.4) | 06 | [R55](requirements/R55_build_time_markup_codegen.md) | `done` |
| M5-07 | **Hot-reload** — file watcher behind `-Dhot-reload` that re-parses changed `.ui` files and calls `scene.reset()` + `instantiate` without recompiling | 06, M1-01 | [R56](requirements/R56_hot_reload.md) | `done` |

---

## Milestone 6 — Text completeness `done`

Text rendering covers what a desktop app actually needs.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M6-01 | **Bold and italic variants** — load regular + bold (+ optional italic) faces from the same font family; `font-bold` / `font-italic` classes | 02 | [R60](requirements/R60_bold_italic_variants.md) | `done` |
| M6-02 | **Mixed font sizes in one scene** — `text-sm` / `text-base` / `text-lg` per element, already in the class resolver but needs measurement + atlas keying per size | 02, 07 | [R61](requirements/R61_mixed_font_sizes.md) | `done` |
| M6-03 | **Text selection** — mouse drag selects a range; keyboard extend-selection; visual highlight rect behind selected glyphs | M1-02, 09 | [R62](requirements/R62_text_selection.md) | `done` |
| M6-04 | **Multi-line text input** — `<Textarea>` widget; newline handling, vertical scroll within the widget | M3-03 | [R63](requirements/R63_textarea.md) | `done` |
| M6-05 | **Font fallback** — if a codepoint is absent from the primary font, try a fallback font before rendering a replacement glyph | 02 | [R64](requirements/R64_font_fallback.md) | `done` |

---

## Milestone 7 — Component library `done`

Widgets beyond the seven core kinds.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M7-01 | **Checkbox** — polished, with label slot | M3-05 | [R70](requirements/R70_checkbox_polished.md) | `done` |
| M7-02 | **Radio group** | M3-01 | [R71](requirements/R71_radio_group.md) | `done` |
| M7-03 | **Slider** | M1-02 | [R72](requirements/R72_slider.md) | `done` |
| M7-04 | **Progress bar / spinner** | M4 | [R73](requirements/R73_progress_spinner.md) | `done` |
| M7-05 | **Toast / notification** — timed overlay in a corner | M4-02 | [R74](requirements/R74_toast_notification.md) | `done` |
| M7-06 | **Modal dialog** — blocking overlay with content slot | M4-02 | [R75](requirements/R75_modal_dialog.md) | `done` |
| M7-07 | **Tabs** | M2-01 | [R76](requirements/R76_tabs.md) | `done` |
| M7-08 | **Accordion / collapsible** | M2-01 | [R77](requirements/R77_accordion.md) | `done` |
| M7-09 | **Date picker** | M3-03, M7-06 | [R78](requirements/R78_date_picker.md) | `done` |
| M7-10 | **Data table** — virtualized rows, sortable columns | M3-06 | [R79](requirements/R79_data_table.md) | `done` |
| M7-11 | **Separator / divider** — trivial 1px line | 09 | [R7A](requirements/R7A_separator.md) | `done` |
| M7-12 | **Avatar / badge** | M4-04 | [R7B](requirements/R7B_avatar_badge.md) | `done` |
| M7-13 | **Tooltip** | M4-02 | [R7C](requirements/R7C_tooltip.md) | `done` |
| M7-14 | **Context menu** | M4-02, M1-02 | [R7D](requirements/R7D_context_menu.md) | `done` |

---

## Milestone 8 — App-level concerns `done`

Structure for building a real multi-screen application.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M8-01 | **Screen / navigation model** — named screens, push/pop history stack, deferred screen transitions | M1-01 | [R80](requirements/R80_screen_navigation.md) | `done` |
| M8-02 | **Application state store** — a top-level signal tree accessible from any screen | M2-01 | [R81](requirements/R81_app_state_store.md) | `done` |
| M8-03 | **Persistent settings** — read/write a small key-value store to disk (window size, theme preference) | M1-01 | [R82](requirements/R82_persistent_settings.md) | `done` |
| M8-04 | **Multi-window** — open a second `Platform` + `Scene` pair; share font and GPU device | M1-01 | [R83](requirements/R83_multi_window.md) | `done` |

---

## Milestone 9 — Developer experience `done`

Makes building with the framework fast and observable.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M9-01 | **Debug overlay** — toggle with F1; draws element bounds, shows computed rect and applied style on hover | M1-02, 09 | [R90](requirements/R90_debug_overlay.md) | `done` |
| M9-02 | **Scene dump** — `Scene.debugPrint()` writes the element tree with kinds, rects, and styles to stderr | 07 | [R91](requirements/R91_scene_dump.md) | `done` |
| M9-03 | **Performance counters** — frame time, draw command count, dirty element count displayed in debug overlay | M1-01, M9-01 | [R92](requirements/R92_performance_counters.md) | `done` |
| M9-04 | **Theme live-swap** — change light/dark or swap a palette at runtime without restart | M2-01, 05 | [R93](requirements/R93_theme_live_swap.md) | `done` |
| M9-05 | **Accessibility: font scaling** — a global font-size multiplier applied to the type scale tokens | 05, 06 | [R94](requirements/R94_font_scaling.md) | `done` |
| M9-06 | **Accessibility: high-contrast mode** — a high-contrast palette variant | 05 | [R95](requirements/R95_high_contrast.md) | `done` |

---

## Milestone 10 — Production hardening `done`

Makes the framework safe and observable when shipped as a real binary.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M10-01 | **Error boundary / recovery** — catch panics or errors from `ScreenFn` / callbacks; display a fallback screen instead of crashing | M8-01 | [RA0](requirements/RA0_error_boundary.md) | `done` |
| M10-02 | **Memory budget enforcement** — configurable arena size ceiling; graceful `OutOfMemory` surface (log + fallback screen) instead of undefined behavior | M0 | [RA1](requirements/RA1_memory_budget.md) | `done` |
| M10-03 | **Release logging** — structured `std.log` wrapper writing to a rolling file on disk; `App.init` accepts an optional log path | M1-01 | [RA2](requirements/RA2_release_logging.md) | `done` |
| M10-04 | **Graceful startup failure** — if Vulkan is unavailable, display a native OS error dialog instead of crashing to stderr | M1-01 | [RA3](requirements/RA3_graceful_startup.md) | `done` |
| M10-05 | **Window state persistence** — auto save/restore window position, size, and maximised state via `PersistentSettings` | M8-03 | [RA4](requirements/RA4_window_state_persistence.md) | `done` |

---

## Milestone 11 — Input completeness `done`

Fills the gaps in the current event model.

| ID | Feature | Depends on | Requirements |
|---|---|---|---|
| M11-01 | **Mouse cursor shapes** — change the OS cursor (arrow, text-beam, resize, hand, crosshair) based on hovered element; uses `glfwSetCursor` | M1-02 | [RB0](requirements/RB0_mouse_cursor_shapes.md) |
| M11-02 | **Drag-and-drop (intra-window)** — register elements as drag sources or drop targets; deliver `drag_start`, `drag_move`, `drag_end`, `drop` events | M1-02 | [RB1](requirements/RB1_drag_drop_intrawindow.md) |
| M11-03 | **Right-click event routing** — expose a generic `on_right_click: CallbackFn` on any element, independent of the context-menu registry | M7-14 | [RB2](requirements/RB2_right_click_routing.md) |
| M11-04 | **Double-click detection** — `mouse_button_double` event variant with configurable timing threshold (default 250 ms) | M1-02 | [RB3](requirements/RB3_double_click_detection.md) |
| M11-05 | **Keyboard shortcuts / accelerators** — register global key combinations (`Ctrl+S`, `Ctrl+Z`) that fire a `CallbackFn` regardless of focused element | M1-02 | [RB4](requirements/RB4_keyboard_shortcuts.md) |
| M11-06 | **Touch / trackpad gesture support** — swipe-to-scroll and pinch-to-zoom gesture events from GLFW touch callbacks | M1-02 | [RB5](requirements/RB5_touch_trackpad_gestures.md) |

---

## Milestone 12 — Layout engine extensions `done`

Unlocks common layout patterns that are awkward or impossible today.

| ID | Feature | Depends on | Requirements |
|---|---|---|---|
| M12-01 | **Absolute positioning** — `position: absolute` removes an element from flow and places it at `(x, y)` relative to its nearest positioned ancestor | 04 | [RC0](requirements/RC0_absolute_positioning.md) |
| M12-02 | **Sticky positioning** — `position: sticky` keeps an element at a fixed offset from its scroll container when scrolled past | M3-06, M12-01 | [RC1](requirements/RC1_sticky_positioning.md) |
| M12-03 | **Wrapping flex rows** — `flex-wrap` support in the layout engine; currently flex containers are non-wrapping only | 04 | [RC2](requirements/RC2_flex_wrap.md) |
| M12-04 | **Aspect-ratio constraint** — `aspect-square` / `aspect-video` locks width-to-height ratio during layout | 04 | [RC3](requirements/RC3_aspect_ratio.md) |
| M12-05 | **Z-index on normal elements** — `z-N` class reorders overlapping siblings within the same layer, without the overlay system | 04, 09 | [RC4](requirements/RC4_z_index.md) |

---

## Milestone 13 — Rendering quality `done`

Closes the gap between functional and polished.

| ID | Feature | Depends on | Requirements |
|---|---|---|---|---|
| M13-01 | **Gradient fills** — `bg-gradient-to-{r,b,br}` with two token-sourced stop colors; emitted as a texture tile | 09, 05 | [RD0](requirements/RD0_gradient_fills.md) |
| M13-02 | **Rounded content clipping** — clip element content (images, children) to the rounded-corner boundary of its container | 09 | [RD1](requirements/RD1_rounded_content_clipping.md) |
| M13-03 | **Subpixel glyph rendering** — RGB-subpixel atlas channels + ClearType-style fragment shader for crisp text at 12–14 px | 02, 09 | [RD2](requirements/RD2_subpixel_glyph_rendering.md) |
| M13-04 | **Vector icons via SDF** — `SdfAtlas` for single-color SVG-path icons that scale without re-rasterization | 09 | [RD3](requirements/RD3_vector_icons_sdf.md) |
| M13-05 | **Anti-aliased filled shapes** — 1 px feather at rect and circle edges via coverage mask in the fragment shader | 09 | [RD4](requirements/RD4_antialiased_filled_shapes.md) |
| M13-06 | **HiDPI / display-scale awareness** — read monitor content scale from `glfwGetMonitorContentScale` and multiply all px values; expose `dpi_scale` on `AppInner` | M1-01 | [RD5](requirements/RD5_hidpi_display_scale.md) |

---

## Milestone 14 — Animation `done`

A minimal, principled animation model that fits the architecture. Requires: RD6, RD7, RD8, RD9, RDA.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M14-01 | **Animation timeline** — `AnimTimeline` drives a `f32` value from 0→1 over a duration with an easing function; ticks mark subscribed elements dirty | M2-01 | [RD6](requirements/RD6_animation_timeline.md) | `done` |
| M14-02 | **Style transitions** — `transition-{opacity,background}` Tailwind class triggers an `AnimTimeline` when the value changes; blends old and new `ComputedStyle` fields over the duration | M14-01, 09 | [RD7](requirements/RD7_style_transitions.md) | `done` |
| M14-03 | **Enter / exit animations** — `animate-in` / `animate-out` classes play a fade when an element's `isHidden` state changes | M14-01, M5-03 | [RD8](requirements/RD8_enter_exit_animations.md) | `done` |
| M14-04 | **Spinner and progress animation** — `ProgressBar` indeterminate mode and `Spinner` use a proper `AnimTimeline` instead of `frame_count` arithmetic | M14-01, M7-04 | [RD9](requirements/RD9_spinner_progress_animation.md) | `done` |
| M14-05 | **Reduced-motion respect** — `prefer_reduced_motion: bool` on `AppInner` disables all `AnimTimeline` playback | M14-01 | [RDA](requirements/RDA_reduced_motion.md) | `done` |

---

## Milestone 15 — Internationalisation `done`

Extends the text model within the Latin + Cyrillic scope. Requires: RE0, RE1, RE2, RE3.

| ID | Feature | Depends on | Requirements | Status |
|---|---|---|---|---|
| M15-01 | **Number formatting** — `formatInt(n, locale)` and `formatFloat(n, locale)` helpers applying thousands separators and decimal symbols per a locale config | — | [RE0](requirements/RE0_number_formatting.md) | `done` |
| M15-02 | **Date / time formatting** — `formatDate(DateValue, locale)` with day/month/year order and separator per locale; `formatDateLong`/`formatDateShort` with full/abbreviated month names | M7-09 | [RE1](requirements/RE1_date_time_formatting.md) | `done` |
| M15-03 | **String table** — build-time tool reads `strings.en.txt` and emits a Zig `const`-table; `t("key")` resolves at comptime; `formatString` for `{key}` substitution | 05 | [RE2](requirements/RE2_string_table.md) | `done` |
| M15-04 | **RTL layout direction** — `direction: rtl` flag on `LayoutNode` reverses the main flex axis and mirrors text layout coordinates; prerequisite for Hebrew if scope expands | 04 | [RE3](requirements/RE3_rtl_layout_direction.md) | `done` |

---

## Milestone 16 — Platform integrations `planned`

Connects the framework to the OS in ways users expect from a desktop app.

| ID | Feature | Depends on |
|---|---|---|
| M16-01 | **System tray** — `Tray` struct adds an icon to the OS notification area with a popup menu; Win32 + libnotify (Linux) | M8-04 |
| M16-02 | **Native file-open dialog** — `Platform.showOpenDialog(filters) ?[]const u8` wraps Win32 `GetOpenFileName` / GTK `GtkFileChooserDialog` | M1-01 |
| M16-03 | **Native file-save dialog** — `Platform.showSaveDialog(default_name) ?[]const u8` | M16-02 |
| M16-04 | **OS native color-scheme detection** — read the OS light/dark preference at startup and apply it as the initial theme mode | M9-04 |
| M16-05 | **MIME clipboard** — extend `Platform.setClipboard` / `getClipboard` to carry a MIME type alongside text; enables copying images and rich text | M3-07 |

---

## Milestone 17 — Accessibility `planned`

Promotes the framework items that were previously deferred from the post-v1 list.

| ID | Feature | Depends on |
|---|---|---|
| M17-01 | **Accessibility tree** — a parallel `AccessNode` tree mirroring the element tree; one node per live element with role, name, and state properties | 07 |
| M17-02 | **AT-SPI bridge (Linux)** — expose the `AccessNode` tree over D-Bus AT-SPI2 so screen readers (Orca) can narrate widgets | M17-01 |
| M17-03 | **UIA bridge (Windows)** — expose the `AccessNode` tree over the Windows UI Automation COM interface so Narrator and NVDA can narrate widgets | M17-01 |
| M17-04 | **ARIA-like roles in markup** — `role="button"`, `role="list"`, `aria-label="..."` attributes on any markup node populate the `AccessNode` | M17-01, 06 |
| M17-05 | **Screen-reader-only text** — `sr-only` Tailwind class renders an element invisible but present in the accessibility tree | M17-01 |

---

## Milestone 18 — JSON Schema completeness `planned`

Lifts the remaining deferred keywords from module 08.

| ID | Feature | Depends on |
|---|---|---|
| M18-01 | **`pattern` validation** — regex validation in schema forms using a vendored regex engine (human decision required per INV-5.6 before implementing) | 08 |
| M18-02 | **`$ref` resolution** — resolve `$ref` URIs within the same schema document; enables shared sub-schema definitions | 08 |
| M18-03 | **`allOf` / `anyOf` / `oneOf` combinators** — validate a value against multiple sub-schemas with and/or/exactly-one semantics | 08 |
| M18-04 | **`dependentRequired`** — conditionally require fields based on the presence of other fields | 08 |
| M18-05 | **`if` / `then` / `else` conditional schemas** — apply a sub-schema based on whether the value validates against a condition | 08 |
| M18-06 | **Array add / remove UI** — `+` / `−` controls for array-type fields in a mounted `Form`; currently v1 renders existing items only | 08, M7-06 |

---

## Milestone 19 — Auto-update / delivery `planned`

Ships the binary to end users.

| ID | Feature | Depends on |
|---|---|---|
| M19-01 | **Update manifest check** — on startup, fetch a JSON manifest from a configured URL and compare the bundled version string; notify the user if a newer version exists | M10-03 |
| M19-02 | **Delta download** — download only a binary diff (bsdiff format) between the current and next version; apply in-process | M19-01 |
| M19-03 | **Staged update** — write the new binary to a temp path, verify its checksum, then rename atomically on next launch (same pattern as `PersistentSettings.flush`) | M19-02 |
| M19-04 | **Update UI** — toast notification with "Update available — restart to apply" action; progress bar during download | M19-02, M7-05 |
| M19-05 | **App installer / packaging** — `zig build package` step that bundles the binary, font assets, and a version manifest into a zip (Windows) or tar.gz (Linux) | M19-03 |

---

## Version 2 (post-v1 — requires explicit decision in `00_constitution.md`)

These require architectural decisions that go beyond the current scope invariants.
A human override recorded in `00_constitution.md` is required before any work begins.

| Feature | Blocking invariant | What must change |
|---|---|---|
| **macOS / web / mobile** | INV-1.2 — Windows + Linux only | Lift INV-1.2; add a Metal backend (macOS) or WebGPU backend (web); new windowing surface layer per platform |
| **Complex-script shaping (Arabic, CJK)** | INV-1.3 — Latin + Cyrillic only | Lift INV-1.3; add HarfBuzz as an approved dependency (INV-5.6); add bidirectional text model |
| **DX12 / Metal backend** | INV-2.1 — Vulkan only | Lift INV-2.1; implement the backend seam that INV-2.1 explicitly permits but defers |
| **CSS cascade / specificity** | INV-4.2 — flat utility classes only | Lift INV-4.2; replace the flat resolver with a cascade engine; breaking change to all existing markup |
| **Charts / data visualization** | Separate concern | Define a chart-command vocabulary alongside `DrawCommand`; needs GPU curve primitives (M13) as foundation |

---

## Reading this document

- Each milestone builds on the previous; start at the top.
- Items within a milestone can be parallelized unless one lists another as a dependency.
- When an item is ready to implement, write a `docs/requirements/RXX_name.md` file with
  the full behavioral specification before starting any code.
- When an item is done: tick it, update `docs/HOW_TO_USE.md`, and update
  `docs/requirements/DEMO_APP.md` to cover the new feature in the Showcase application.
  All three updates are required — a milestone is not done until all three are complete.
