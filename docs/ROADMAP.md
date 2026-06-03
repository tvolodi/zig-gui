# zig-gui Roadmap

> This document lists everything needed to turn the current architecture skeleton into a
> framework you would actually ship a product with. Items are grouped by theme, ordered
> roughly by dependency, and tagged with a milestone. Detailed requirements for each item
> live in (or will live in) `docs/requirements/`.
>
> **Status key:** `done` · `in-progress` · `planned` · `post-v1`

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

## Milestone 5 — Markup and styling completeness `planned`

The authoring surface covers the common cases without forcing escape to raw Zig.

| ID | Feature | Depends on |
|---|---|---|
| M5-01 | **Inline style attributes** — `style:background`, `style:color`, etc. on any markup node; overrides token-derived defaults for dynamic content | 06 |
| M5-02 | **Missing Tailwind classes** — `hidden`, `overflow-hidden`, `min-w-*`, `max-w-*`, `w-{n}`, `h-{n}`, `mx-auto`, `shrink-0`, `grow-0`, `self-*`, `col-span-*`, `row-span-*`, `opacity-*` | 06 |
| M5-03 | **Conditional rendering** — `if="{bind condition}"` attribute hides/shows a subtree | M2-04 |
| M5-04 | **List rendering** — `for="{bind items}"` repeats a child template over a collection | M2-04 |
| M5-05 | **Markup error reporting** — parse errors include line number and column, not just an enum variant | 06 |
| M5-06 | **Build-time markup codegen tool** — `build.zig` step that runs `parse` over `.ui` files and emits `.zig` struct literals; no parser in the production binary (INV-4.4) | 06 |
| M5-07 | **Hot-reload** — file watcher behind `-Dhot-reload` that re-parses changed `.ui` files and calls `scene.reset()` + `instantiate` without recompiling | 06, M1-01 |

---

## Milestone 6 — Text completeness `planned`

Text rendering covers what a desktop app actually needs.

| ID | Feature | Depends on |
|---|---|---|
| M6-01 | **Bold and italic variants** — load regular + bold (+ optional italic) faces from the same font family; `font-bold` / `font-italic` classes | 02 |
| M6-02 | **Mixed font sizes in one scene** — `text-sm` / `text-base` / `text-lg` per element, already in the class resolver but needs measurement + atlas keying per size | 02, 07 |
| M6-03 | **Text selection** — mouse drag selects a range; keyboard extend-selection; visual highlight rect behind selected glyphs | M1-02, 09 |
| M6-04 | **Multi-line text input** — `<Textarea>` widget; newline handling, vertical scroll within the widget | M3-03 |
| M6-05 | **Font fallback** — if a codepoint is absent from the primary font, try a fallback font before rendering a replacement glyph | 02 |

---

## Milestone 7 — Component library `planned`

Widgets beyond the seven core kinds.

| ID | Feature | Depends on |
|---|---|---|
| M7-01 | **Checkbox** — spec'd in M3-05; library-level polished version with label slot | M3-05 |
| M7-02 | **Radio group** | M3-01 |
| M7-03 | **Slider** | M1-02 |
| M7-04 | **Progress bar / spinner** | M4 |
| M7-05 | **Toast / notification** — timed overlay in a corner | M4-02 |
| M7-06 | **Modal dialog** — blocking overlay with content slot | M4-02 |
| M7-07 | **Tabs** | M2-01 |
| M7-08 | **Accordion / collapsible** | M2-01 |
| M7-09 | **Date picker** | M3-03, M7-06 |
| M7-10 | **Data table** — virtualized rows, sortable columns | M3-06 |
| M7-11 | **Separator / divider** — trivial 1px line | 09 |
| M7-12 | **Avatar / badge** | M4-04 |
| M7-13 | **Tooltip** | M4-02 |
| M7-14 | **Context menu** | M4-02, M1-02 |

---

## Milestone 8 — App-level concerns `planned`

Structure for building a real multi-screen application.

| ID | Feature | Depends on |
|---|---|---|
| M8-01 | **Screen / navigation model** — named screens, push/pop history stack, screen transition | M1-01 |
| M8-02 | **Application state store** — a top-level signal tree accessible from any screen | M2-01 |
| M8-03 | **Persistent settings** — read/write a small key-value store to disk (window size, theme preference) | M1-01 |
| M8-04 | **Multi-window** — open a second `Platform` + `Scene` pair; share font and GPU device | M1-01 |

---

## Milestone 9 — Developer experience `planned`

Makes building with the framework fast and observable.

| ID | Feature | Depends on |
|---|---|---|
| M9-01 | **Debug overlay** — toggle with a hotkey; draws element bounds, shows computed rect and applied style on hover | M1-02, 09 |
| M9-02 | **Scene dump** — `Scene.debugPrint()` writes the element tree with kinds, rects, and styles to stderr | 07 |
| M9-03 | **Performance counters** — frame time, draw command count, dirty element count displayed in debug overlay | M1-01, M9-01 |
| M9-04 | **Theme live-swap** — change light/dark or swap a palette at runtime without restart | M2-01, 05 |
| M9-05 | **Accessibility: font scaling** — a global font-size multiplier applied to the type scale tokens | 05, 06 |
| M9-06 | **Accessibility: high-contrast mode** — a high-contrast palette variant | 05 |

---

## Post-v1 (explicit non-goals until decided otherwise)

These are out of scope until a human decision records them in `00_constitution.md`.

| Feature | Reason deferred |
|---|---|
| macOS / web / mobile | INV-1.2 — Windows + Linux only |
| Complex-script shaping (Arabic, CJK) | INV-1.3 — Latin + Cyrillic only |
| Accessibility tree / screen reader | INV-1.4 |
| DX12 / Metal backend | INV-2.1 |
| CSS cascade / specificity | INV-4.2 |
| `pattern` / `$ref` / combinators in JSON Schema | Explicit non-goal in module 08 spec |
| Animations / transitions | No timeline model exists yet |
| Charts / data visualization | Separate concern |
| Auto-update / CDN delivery | Separate concern |
| Plugin / extension system | INV-1.1 — no speculative extension points |

---

## Reading this document

- Each milestone builds on the previous; start at the top.
- Items within a milestone can be parallelized unless one lists another as a dependency.
- When an item is ready to implement, write a `docs/requirements/RXX_name.md` file with
  the full behavioral specification before starting any code.
- When an item is done, tick it and update `docs/HOW_TO_USE.md` accordingly.
