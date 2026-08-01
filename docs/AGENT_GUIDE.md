# Agent Development Guide — zig-gui

> **Read `specs/00_constitution.md` in full before starting any task.**
> This guide is a map; the constitution is the law. If they conflict, the constitution wins.

---

## 1. What this project is

A native GPU-rendered GUI framework written in Zig. It targets Windows and Linux via Vulkan
(GLFW for windowing). Authors write HTML-like `.ui` markup with a Tailwind utility subset;
that compiles to a typed native tree. The design philosophy is: one binary, data-oriented
architecture, no external frameworks beyond GLFW + Vulkan + stb_truetype.

---

## 2. How this codebase is organized

### 2.1 The spec directory (`docs/specs/`)

Every module has four files:

| File | Purpose |
|---|---|
| `NN.spec.md` | Normative description — what to build, why, edge cases, non-goals |
| `NN.types.zig` | **The contract** — public API signatures that MUST be matched exactly |
| `NN.acceptance_test.zig` | The executable definition of "done" — NEVER modify |
| `NN.checklist.md` | Tick-box verification list — all boxes must be ticked before "done" |

`00_constitution.md` is the shared-memory file for all agents and all sessions. Read it
first on every task, every time.

### 2.2 Module build order (dependencies flow downward — no upward imports)

```
01  platform spike      — GLFW window, Vulkan surface, SPIR-V triangle proof
02  text                — glyph rasterization, kerning, atlas, word wrap
03  element store       — data-oriented parallel arrays, generational handles, arena
04  layout engine       — flexbox + grid solver over the element store
05  theme               — four-layer token model (palette → tokens → component styles)
06  markup + style      — .ui parser, Tailwind-subset class resolver
07  components          — NodeDesc → live element tree; text measurement; Scene
08  schema forms        — JSON Schema → runtime form, Value tree, validation
```

**The hard rule:** module `N` may only import modules numbered lower than `N`. Violating
this breaks the build-order contract (`INV-3.4`).

---

## 3. Architecture in one mental model

```
.ui markup  ──(build-time codegen)──►  NodeDesc tree
JSON Schema ──(runtime parser)───────►  FormModel

NodeDesc / FormModel
        │
        ▼
    module 07: Scene.instantiate()
        │  writes per-element kind/style/text arrays + LayoutNode into ElementStore
        ▼
    module 04: layout engine solve()
        │  writes computed Rect for every element
        ▼
    renderer: consumes flat draw-command list
        │  (one Color, one rect, one glyph atlas UV per command)
        ▼
    module 01: VulkanBackend.endFrame()  →  GPU  →  screen
```

State updates:
- A signal write marks affected element indices dirty in a bitset.
- Each frame, only dirty elements are re-laid-out and re-painted.
- "Widget" = an index. No per-widget heap object exists.

---

## 4. Architecture invariants — the non-negotiables

Read the full list in `00_constitution.md`. These are the most common agent mistakes:

### Data orientation (INV-3.1, INV-3.2)
- **No per-widget heap objects.** All widget data lives in parallel arrays. An element IS an
  index, not a struct.
- **Identity = generational handle** `ElementId { index: u32, gen: u32 }`. Never store a
  pointer across frames. Resolve a handle to a pointer only inside one function call.

### Reactivity (INV-3.3)
- One mechanism: signal → dirty bitset → linear scan. Do NOT introduce observers, event
  emitters, or callbacks as a parallel change-propagation path.

### Three-tree separation (INV-3.4)
- Widget description (throwaway, per-frame) → Element (persistent state) → RenderObject
  (cached layout/paint). Do not merge these. State lives in Element; layout caching in
  RenderObject.

### Memory (INV-3.5)
- Per-screen arena. Opening a screen bump-allocates; closing it resets the arena. Do NOT
  free individual elements.

### Styling (INV-4.2, INV-4.3)
- Tailwind-like utility classes: flat, atomic, order-independent. NO cascade, specificity,
  inheritance, or selectors.
- Style values go through the four-layer token model. A widget NEVER references a hex
  literal or a raw palette value — it references a `ComputedStyle`.

### Markup baking (INV-4.4)
- Production ships no markup parser. `.ui` files become typed struct trees via build-time
  codegen. A runtime parser lives only behind `-Dhot-reload`.

---

## 5. Process invariants — how to work

### INV-5.1 — Match `types.zig` exactly
The public API lives in `NN.types.zig`. Do NOT change signatures to make implementation
easier. If a signature genuinely must change, follow the contract-amendment procedure (INV-5.3):
change the signature and its `acceptance_test.zig` call sites together and record it as an
amendment (constitution §8). Never diverge silently, and never escalate it.

### INV-5.2 — "Done" is executable
A module is done when `acceptance_test.zig` passes via `zig test` AND every box in
`checklist.md` is ticked. "It looks right" is not done.

### INV-5.3 — Change `acceptance_test.zig` only via the contract-amendment procedure
A frozen test is the contract definition. Editing a test merely to make it pass defeats the
system. But when the `types.zig` signature it verifies legitimately changes, update the test's
call sites in the *same* pass (never weakening an assertion) and record it as an amendment
(constitution §8). A test edit without a matching contract change is still forbidden. Do NOT
escalate — amend and log.

**This invariant does NOT mean "don't create unit tests."** Agents regularly create new test
files like `src/NN/NN_test.zig` with unit-level coverage. Those are mutable (normal code review).
The invariant protects only the frozen acceptance test files in `docs/specs/`.

### INV-5.4 — Non-goals are binding
Each spec lists non-goals explicitly. Do NOT implement them, even if they look trivial.
Scope creep is the primary failure mode across multi-session pipelines.

### INV-5.5 — Use glossary terms
"Element", "RenderObject", "signal", "token" have exact meanings. Do not coin synonyms. If a
concept has no glossary term, add one to `glossary.md`.

### INV-5.6 — Approved dependencies only
Approved dependencies as of module 08: GLFW, Vulkan loader/SDK (`glslc` at build time),
stb_truetype, Zig std. Adding a new external dependency requires recording it in the
constitution and is a flag for human review.

---

## 6. Module-by-module quick reference

### Module 01 — Platform spike
- **Goal:** Prove the toolchain works: GLFW window + Vulkan + one SPIR-V triangle. No
  broader framework yet.
- **Key types:** `Platform`, `VulkanBackend`, `Extent2D`, `Color`
- **Seam rule:** `VulkanBackend` is a concrete struct. Its public method names are the seam.
  Do NOT build a `GpuBackend` vtable/function-pointer interface.
- **Done = automatable (smoke_test.zig) + manual visual check on both Windows and Linux.**

### Module 02 — Text
- **Goal:** UTF-8 string + font + pixel size → positioned glyphs + packed glyph atlas.
  Latin + Cyrillic only. No complex shaping.
- **Two layers:** pure layout (measureWidth, wrap, blockHeight) — fully testable without a
  font; font+atlas layer (stb_truetype backed).
- **Key types:** `Word`, `Line`, `TextExtent`, `FontMetrics`, `Font`, `GlyphAtlas`, `FontFamily`
- **Does NOT touch module 03.** Defines its own `TextExtent`. Handoff to layout happens via
  module 07.
- **R64 — `FontFamily` lives here:** `FontFamily` was moved from `src/app/font_family.zig`
  into `src/02/types.zig` so that `layoutParagraphEx` can reference it without an upward
  import (INV-3.4). `src/app/font_family.zig` is now a one-line re-export.
- **R64 — `layoutParagraphEx`:** 7-param variant of `layoutParagraph` that accepts
  `family: ?*FontFamily`. When non-null, each codepoint is resolved to the best font in the
  fallback chain. Unsupported codepoints use `REPLACEMENT_CODEPOINT` (U+FFFD); if that is
  also absent the glyph is skipped silently. `layoutParagraph` (6 params) remains unchanged
  and delegates to `layoutParagraphEx(…, null)`. GlyphKey gains `font_id: u8 = 0`.

### Module 03 — Element store
- **Goal:** The data-oriented foundation. Parallel arrays, generational handles, parent/child
  tree as index links, dirty bitset, per-screen arena.
- **This module defines the shared geometry types** used across the project: `ElementId`,
  `Rect`, `Size`, `Constraints`, `Insets`, `Dimension`, `TrackSize`, `Display`,
  `FlexDirection`, `JustifyContent`, `AlignItems`, `LayoutNode`.
- **Key rule:** `get(id)` returns `*LayoutNode` for LOCAL use only — never stored across
  frames.
- Module 04 imports types from here; it does NOT redefine them.

### Module 04 — Layout engine
- **Goal:** Compute exact pixel rectangles for every element. Flexbox + grid (ported from
  Taffy algorithm).
- **Single entry point:** `solve(store, root, available)` — deterministic, fills
  `computed: Rect` for every reachable node.
- **Does NOT read/write** styles, signals, or the dirty bitset. Only reads `LayoutNode` data
  and writes `computed`.
- **Supported models:** flex (with grow/shrink/basis), grid (fixed track lists only), block.

### Module 05 — Theme
- **Goal:** Four-layer token model. Only layer 1 (palette) changes between themes.
- **Layers:** `Palette` → `Tokens` (via `Tokens.light(p)` / `Tokens.dark(p)`) →
  component-style builders (`buttonPrimary`, `inputDefault`, etc.) → `ComputedStyle`.
- **Key rule (INV-4.3):** A component style references tokens, NEVER raw palette values or
  hex literals. The acceptance test verifies this directly.
- `ComputedStyle` is defined here (lowest module that needs it) and shared upward.
- **M9 — `Tokens.scaled(factor)`:** Pure function that multiplies all five text-size fields (`text_xs`…`text_xl`) by `factor` and clamps each to `[6, 96]`. Call with `factor = 1.0` for an unscaled copy.
- **M9 — `Palette.highContrast()` / `highContrastDark()`:** Built-in high-contrast palettes (WCAG AA). Available as `Theme.hc_light` / `Theme.hc_dark` convenience constants on the `Theme` struct.

### Module 06 — Markup + style
- **Goal:** `.ui` parser → `NodeDesc` tree; Tailwind-subset class resolver → `ComputedStyle`
  + `LayoutNode`.
- **Parser grammar:** XML-like, attribute-based, no mixed-content text nodes. Text is an
  attribute (`text="hello"`).
- **Resolver rule:** spacing/gap/sizing → fixed px scale (n×4); colors/radius/font-size →
  theme tokens.
- **Production binary ships no parser** — a build-step codegen tool runs `parse` over `.ui`
  files and emits generated `.zig` struct literals.

### Module 07 — Components
- **Goal:** Turn `NodeDesc` tree into a live element tree. Map tags to widget kinds, resolve
  classes, write arrays, build elements.
- **Twenty-seven widget kinds (M27):** `text`, `button`, `input`, `card`, `row`, `column`, `dropdown`,
  `checkbox`, `scrollview`, `image`, `icon`, `textarea`, `separator`, `radio`, `slider`,
  `progress_bar`, `spinner`, `tabs`, `tab_item`, `accordion`, `date_picker`, `avatar`, `badge`, `data_table`,
  `date_range_picker`, `maskable_value`, `trend_badge`.
- **`NONE` constant:** `pub const NONE: u32 = std.math.maxInt(u32)` — sentinel for "no element" used in `focused_idx` and similar u32 index fields. Do NOT redeclare a local `const NONE` inside functions; use the module-level constant.
- **`Scene`** owns the `ElementStore` AND all parallel arrays: `kind[]`, `style[]`, `text[]`,
  `_button_state[]`, `_input_state[]`, `_dropdown_state[]`, `_checkbox_state[]`,
  `_scroll_state[]`, `_queued_callbacks`, `_pseudo[]`, `_image_state[]`, `_selection[]`, `_textarea_state[]`, `_radio_state[]`, `_slider_state[]`, `_progress_state[]`, `_tabs_state[]`, `_accordion_state[]`, `_date_range_picker_state[]`, `_maskable_value_state[]`, `_trend_badge_state[]` (INV-3.1: no per-widget heap objects).
- **`Scene.frame_count: u64`** — animation frame counter, set by the app layer each frame.
  `buildDrawList` reads this for `progress_bar` indeterminate animation and `spinner` rotation.
- **Focus state:** `focused_idx: u32` (NONE = no focus) + `focusable_indices: []u32`
  rebuilt by `instantiate()`. Focusable kinds: button, input, dropdown, checkbox, textarea, radio, slider, accordion (M7 Phase 2 adds accordion), date_range_picker (M27).
- **Two passes:** `instantiate` (no font, fully testable), then `measurePass` (font-dependent,
  fills `LayoutNode.measured`). **R60:** `measurePass` takes `*FontFamily` instead of `*Font`;
  uses `family.face(style.font_bold, style.font_italic)` per element.
- All element creation/removal goes through `Scene`, never the store directly.
- **Callback firing:** `Scene.fireQueuedCallbacks()` called ONCE per frame by the app layer,
  after layout solve, before `buildDrawList` (INV-3.3).
- **R40 — Pseudo-state:** `PseudoState` parallel array `_pseudo[]`; `setPseudo(idx, state)` marks dirty.
- **R43 — Image state:** `ImageState` parallel array `_image_state[]`; `setImage(idx, id)` / `setImageTint(idx, color)`.
- **Style fields (M4):** `ComputedStyle` gains `truncate: bool`, `opacity: f32`, `shadow_blur: f32`, `shadow_offset_x/y: f32`, `shadow_color: Color`; resolved by `resolveClasses` from Tailwind `truncate`/`opacity-*`/`shadow-*` classes.
- **R71 — Radio state:** `RadioState` parallel array `_radio_state[]`. `group_id: u16` computed via `hashGroupName` from the `group=` attribute. `selectRadio(idx)` deselects all others in the same group. `selectNextInGroup`/`selectPrevInGroup` cycle selection.
- **R72 — Slider state:** `SliderState` parallel array `_slider_state[]`. `min`/`max`/`step`/`value` parsed from attributes at instantiation. `setSliderValue` applies step-snapping via `snapToStep`.
- **R73 — Progress bar / spinner:** `ProgressState` parallel array `_progress_state[]`. `setProgress(idx, value)` updates `value` (0.0–1.0); `setIndeterminate(idx, bool)` enables the moving animation band. `spinner` kinds have no extra state — they animate purely from `scene.frame_count`.
- **R76 — Tabs:** `TabsState` parallel array `_tabs_state[]`. `selectTab(idx, tab_i)` sets `active_idx`; all tab panels' `_hidden` bits are updated accordingly. `tab_count` is set at instantiation by counting `tab_item` children.
- **R77 — Accordion:** `AccordionState` parallel array `_accordion_state[]`. `toggleAccordion(idx)` flips `open`; the body child's `_hidden` bit follows. `isAccordionOpen(idx)` for read access.
- **R78 — Date Picker (M7 Phase 3):** `DatePickerState` parallel array `_date_picker_state[]`. `datePickerStateOf(idx)` → `*DatePickerState`. `setDateValue(idx, v)` / `getDateValue(idx)` for programmatic get/set. `openCalendar(idx)` / `closeCalendar(idx)` toggle the popup. `disabled=` attribute sets initial state; `value="YYYY-MM-DD"` sets initial date. Helper `parseDateStr` parses ISO dates.
- **R7B — Avatar + Badge (M7 Phase 3):** `AvatarState` parallel array `_avatar_state[]`. `avatarStateOf(idx)` → `*AvatarState`. `setAvatarImage(idx, image_id)` / `setAvatarInitials(idx, initials)`. `BadgeState` parallel array `_badge_state[]`. `badgeStateOf(idx)` → `*BadgeState`. `BadgeState` fields: `text: [8]u8` (NUL-terminated display text) and `color: BadgeColor` (`.default`/`.success`/`.warning`/`.error_c`). Avatar background color is deterministic from first initial — uses 4 semantic tokens (accent/ok/warn/err), NOT hex literals (INV-4.3). `size=` attribute sets pixel size of avatar.
- **R7C — Tooltip (M7 Phase 3):** `_tooltip[]` is `[]?[]const u8` — `null` means no tooltip. `tooltipOf(idx)` → `?[]const u8`. `setTooltip(idx, text)` assigns text. `tooltip=` attribute on any element sets it at instantiation. `TooltipManager` in `src/app/tooltip.zig` handles hover-delay logic (500 ms) and overlay rendering.
- **R7D — Context Menu (M7 Phase 3):** `_context_menu_idx[]` is `[]u8` — `0xFF` means no menu. `contextMenuIdxOf(idx)` → `u8`. `setContextMenuIdx(idx, menu_idx)` assigns a registered menu. `ContextMenuManager` in `src/app/context_menu.zig` handles registration, right-click popup, and overlay rendering.
- **R79 — Data Table (M7 Phase 3):** `DataTableState` parallel array `_table_state[]`. `tableStateOf(idx)` → `*DataTableState`. `setTableData(idx, rows)` sets the data source (`DataTableRows` with `row_ptr: *anyopaque`, `row_size: usize`, `row_count: u32`, and `cell_fn: CellTextFn`). `CellTextFn = *const fn(row_ptr: *anyopaque, col: u8, buf: []u8) u8` — receives pointer to the specific row, writes text into `buf`, returns byte count. Compute row N's pointer via `@ptrCast(@as([*]u8, @ptrCast(rows.row_ptr)) + N * rows.row_size)`. `setTableColumns(idx, columns)` defines column headers/widths. `sortTable(idx, col)` toggles sort direction and rebuilds `sorted_indices` using `std.ArrayListUnmanaged(u32)`. Virtualized rendering: only visible rows emitted by `buildDrawList`.
- **RN3 — Date Range Picker (M27):** `DateRangePickerState` parallel array `_date_range_picker_state[]`. `setDateRange(idx, start, end)` sets both ends; rejects end < start (no-op). `getDateRange(idx)` → `DateRangeValue`. `setDateRangePreset(idx, preset)` atomically sets both ends from `DateRangePreset` enum (`.today/.last_7/.last_30/.this_month/.custom`). Focusable kind; added to `focusable_indices` in `instantiate()`.
- **RN5 — Maskable Value (M27):** `MaskableValueState` parallel array `_maskable_value_state[]`. `setMaskableValue(idx, text)` stores value text and sets `display_len` on first call (fixed-width — never changes). `setMaskableVisible(idx, visible)` toggles masking and marks dirty (INV-3.3). When hidden, renderer shows `masked_char` × `display_len`; when visible, shows actual `value_text`. Default `masked_char = '*'`.
- **RN6 — Trend Badge (M27):** `TrendBadgeState` parallel array `_trend_badge_state[]`. `setTrendValue(idx, value: f32)` sets value and computes `direction` from sign (`.up`/`.down`/`.neutral`). Renderer colors from tokens only (INV-4.3): `tokens.ok` (up), `tokens.err` (down), `tokens.text_muted` (neutral). **Layout gotcha:** `TrendBadge` has `display: block, flex_shrink: 0` but no default size — the layout engine gives it zero width/height unless explicit `w-N h-N` classes are added (e.g. `"text-xs w-14 h-4"`). Alternatively, use a `Text` element with post-instantiation text/color injection for pixel-exact trend strings like "+11.01%".
- **RN4 — Currency formatting (M27):** `formatCurrency(buf, amount, currency, locale)` in `src/app/locale.zig`. `Currency` enum: `.usd`, `.sgd`, `.eur`. EUR always uses EU grouping conventions regardless of locale arg. Renders exactly 2 decimal places.

### Module 08 — Schema forms
- **Goal:** JSON Schema (runtime) → working form. Walk schema → `FormModel`, map fields to
  widgets, build elements, bind inputs to `Value` tree, validate.
- **Four pure pieces:** `Value`, widget registry, walker (`buildForm`), validator (`validate`).
- **`Form`** ties them to module 07: `mount` builds elements and records `path → ElementId`.
- **v1 keyword subset:** type, format (date/email/uri), enum, required, properties, items,
  minLength/maxLength, minimum/maximum, title, x-widget. Pattern, if/then/else, $ref,
  combinators are deferred.

### Module 09 — Renderer
- **R40 — `resolveStyle(base, overrides, state)`:** Layers `PseudoStyleSet` onto `ComputedStyle` in priority order (focus < hover < active < disabled). Called per-element during `buildDrawList`.
- **R42 — `intersectScissor(a, b)`:** Computes intersection of two `ScissorRect`s; used to nest scissor regions for scrollviews.
- **R43 — `GpuImageAtlas`:** Stub GPU atlas for RGBA image tiles; mirrors `GpuAtlas.upload` pattern; real Vulkan upload deferred to GPU integration step.
- **R44 — Text truncation:** `buildDrawList` checks `style.truncate`; clips glyph commands and appends ellipsis glyph sequence when text overflows element width.
- **R45 — `applyOpacity(col, factor)`:** Multiplies `col.a` by `factor`; called for every color emitted when `effective_alpha < 1.0`.
- **R46 — `emitShadow(...)`:** Emits 5 concentric `filled_rect` commands before the element background; skipped when `style.shadow_blur == 0`.
- **R60 — Font variants (bold/italic):** `buildDrawList` now receives `family: *FontFamily` instead of `font: *Font`. Call `family.face(style.font_bold, style.font_italic)` per element before `emitGlyphs`. `computeTextX` has no style context — uses `.variant = .regular`.
- **R62 — Text selection:** `TextSelection { anchor: u32, active: u32 }` stored in `Scene._selection[]`. `selectionOf(idx)` returns `*TextSelection`. Selection highlight rendered between border (step 2) and text glyphs (step 3) in `buildDrawList` as a `filled_rect` using `tokens.accent` with `a = 80`. Glyph matching uses `g.byte_offset` from `PositionedGlyph`. `hitTestText` maps mouse_x → byte offset by finding the glyph whose midpoint is closest. `handleTextKey` handles keyboard navigation for read-only `.text` elements.
- **R63 — Textarea:** Adds `.textarea` WidgetKind (12th kind). `TextareaState` parallel array `_textarea_state[]`; `textareaStateOf(idx)` returns `*TextareaState`. Content is stored in `InputState.text`; `TextareaState.line_starts` is a `[]u32` of byte offsets of each line's first character (rebuilt by `rebuildLineStarts` in app.zig after every mutation). `buildDrawList` emits background/border, `set_scissor`, per-line glyphs + selection highlights, cursor rect, `restore_scissor`; does NOT push children. App layer adds `handleTextareaKey` (handles Enter, Up/Down; delegates other keys to `handleInputKey`) and standalone helpers `rebuildLineStarts`, `taLineOfByte`, `scrollToCursor`. Focusable kinds updated to include `.textarea`. `setFocus` activates/deactivates `InputState.active` for `.textarea` the same as `.input`.
- **R64 — Font fallback:** `buildDrawList` calls to `layoutParagraph` updated to
  `layoutParagraphEx(…, scene.font_family)`. Fallback glyphs are stored in atlas under
  `font_id = 1+idx` — `emitGlyphs` looks up with the primary font's key only (font_id=0);
  full fallback rendering in emitGlyphs is a post-v1 enhancement.
- **R70 — Polished checkbox (M7 Phase 1):** Box size = `style.font_size`. Box background = `tokens.accent` when checked, `tokens.bg_surface` otherwise. Border = `tokens.border_strong` on hover, `tokens.border_default` otherwise. Checkmark rendered as two `filled_rect` tick strokes (horizontal + vertical) in `tokens.accent_text`.
- **R7A — Separator (M7 Phase 1):** No special rendering case needed. `defaultStyleFor(.separator)` sets `background = tokens.border_default`, and the existing "emit background if a > 0" path in `buildDrawList` handles it automatically.
- **R71 — Radio (M7 Phase 1):** Three-layer rendering: outer ring (`tokens.border_default` filled circle), inner fill (`tokens.bg_surface` inset by 2 px to create ring appearance), accent dot (`tokens.accent`) when `rs.selected`. All with `effective_alpha`.
- **R72 — Slider (M7 Phase 1):** Three-layer rendering: 4 px tall track (`tokens.border_default`), filled portion (`tokens.accent`, width = `track_w * t`), circular thumb (`tokens.accent`, radius = `font_size * 0.5`; `tokens.accent_hover` when dragging). Edge case: `range = max - min`; if `range <= 0` then `t = 0`.

- **R73 — Progress bar / spinner (M7 Phase 2):** `progress_bar` renders a track + fill; when `indeterminate`, a moving 40% band animates using `scene.frame_count % 120`. `spinner` renders 8 tick marks at angles 0–315°; visible mark rotates using `scene.frame_count % 8`. Animation reads from `Scene.frame_count` (NOT a buildDrawList parameter — the app sets `scene.frame_count` before each call).
- **R74 — Toast (M7 Phase 2):** `ToastManager` in `src/app/toast.zig`. `init(overlay)` allocates an overlay slot. `show(message, kind, duration_ms, now_ms)` enqueues a toast. `tick(now_ms, w, h, tokens, font, atlas, overlay, alloc)` expires old toasts, builds draw commands, writes to the overlay slot. Max 4 simultaneous toasts. Memory: `current_cmds: ?[]DrawCommand` freed at start of each `tick`.
- **R75 — Modal dialog (M7 Phase 2):** `DialogManager` in `src/app/dialog.zig`. `init(overlay)` allocates an overlay slot. `open(content_idx, scene)` shows backdrop + focus trap. `close(scene)` restores focus. `buildOverlay(w, h, tokens, overlay, alloc)` emits semi-transparent backdrop + panel background.
- **R76 — Tabs (M7 Phase 2):** `tabs` renders a tab bar along the top from `tab_item` children's `_text` labels. Active panel is shown; others have their hidden bit set. Clicking a tab bar button calls `scene.selectTab`. Tabs click handling is NOT in `focusable_indices` — it is handled in `app.zig`'s mouse press path.
- **R77 — Accordion (M7 Phase 2):** `accordion` renders its header child (first child) with a chevron (▶/▼) prepended. Clicking the header toggles the body child (second child) visibility via `scene.toggleAccordion`. The accordion header is in `focusable_indices`.
- **R78 — Date Picker (M7 Phase 3):** Styled input rect + border + date string text. Popup calendar rendering deferred to later milestone.
- **R7B — Avatar (M7 Phase 3):** Image mode: `ImageCmd` with `dst`/`uv`/`tint` fields. Initials mode: circle background (`initialsColor` from char modulo 8-color palette) + initials text + border.
- **R79 — Badge (M7 Phase 3):** Pill `filled_rect` + count text. Background uses `tokens.err` when no explicit color set. Zero count renders as empty string.
- **R79 — Data Table (M7 Phase 3):** `set_scissor` + header row (column headers, dividers) + virtualized data rows + `restore_scissor`. Only `visible_count = ceil(view_h / row_height) + 1` rows emitted per frame.
- **M9 — `_classes` parallel array (R90/R93/R95):** `_classes: ArrayListUnmanaged([]const u8)` stores the raw CSS class string for each element at instantiation. Used by `rebuildStyles` in the app layer to re-resolve element styles when the active theme changes at runtime. Populated in `instantiateNode` from `desc.classes`; cleared in `reset()`.
- **M9 — `debugPrint` / `debugPrintStats` forwarding methods (R91):** Scene exposes two forwarding methods that delegate to free functions in `src/07/debug.zig`. The free functions own the DFS traversal and stderr formatting; Scene never touches stderr directly.

### Module 13 — Charts (M26 / M27 RN1 RN2 RN7 RN9 RN10)
- **Goal:** Chart-command vocabulary, scales/axes, five chart mark kinds, hit-test interactivity, M27 dashboard extensions (donut, callouts, crosshair), gauge arc meter, world map.
- **Files:** `scale.zig`, `axes.zig`, `marks.zig`, `chart.zig`, `interaction.zig`, `tessellate.zig`, `legend.zig`.
- **Seven chart kinds:** `line`, `bar`, `area`, `scatter`, `pie`, `gauge`, `map`. A `Chart` struct holds `kind`, `series`, `x`, and option fields; `.render(frame, draw_list, allocator)` dispatches to `marks.renderChart`.
- **RN9 — Gauge chart:** `chart.kind = .gauge`. Set `gauge_value: f64` (0–1), `gauge_bg_token`, `gauge_fill_token`. Pass `series = &.{}` (no data series). Arc sweeps −π (left) → 0 (right) through the TOP. `renderGauge` uses `ArcCmd` for fill + background arc, `aa_filled_circle` for end-cap dots. End-caps at arc center radius (±arc_r from center). `cy = plot_rect.y + h * 0.72` positions gauge center in lower portion.
- **RN10 — World map:** `chart.kind = .map`. Set `map_markers: []const MapMarker` (each with `norm_x`, `norm_y`, `radius`, `color_token`), `map_ocean_token`, `map_land_token`. Pass `series = &.{}`. Continent shapes are rendered as `aa_filled_rect` bounding boxes (the Vulkan backend treats `filled_path`/`polyline`/`arc` as no-ops — only `filled_rect`, `aa_filled_rect`, `aa_filled_circle`, and `glyph` produce pixels). Dot markers use `aa_filled_circle`. `renderWorldMap` previously used `tess.triangulateConvex` + `filled_path`; those were replaced with bounding-box rects.
- **RN11 — chart_cmds injection slot:** `AppInner.chart_cmds: ?[]DrawCommand = null`. Set by `per_frame_app_fn` before the frame renders; consumed and freed by the frame loop. Commands appear between main and overlay draw passes. Use `cmds.toOwnedSlice(alloc)` to transfer ownership; `errdefer cmds.deinit(alloc)` for safety. Pattern in demo: `ecommerce_screen.renderCharts(ai) catch {}` called from `toastAppTick`. **Sub-allocation ownership:** The frame loop frees `polyline.points` and `filled_path.vertices`/`.indices` sub-slices before freeing the outer slice — allocate all of these from `ai.gpa`.
- **Demo module 13 import:** `mod13_charts` is a named module in `build.zig` (root = `src/13/chart.zig`, dep = `mod01_platform`). Added to `demo_mod` as `"../../13/chart.zig"`. `chart.zig` re-exports `Rect09`, `AxisOptions`, `makeFrame`, `drawAxes`, `DrawCmd` from `axes.zig` so demo screens need only one import.
- **RN1 — Donut ring pattern:** `Chart.inner_radius: f32 = 0.0`. When > 0, `renderPie` emits `ArcCmd` with `width > 0`:
  - `arc_radius = outer * (1 + inner_radius) / 2` (center of ring stroke)
  - `arc_width  = outer * (1 - inner_radius)` (ring thickness)
  - This places the inner edge at `outer × inner_radius` and outer edge at `outer`. Setting `radius = outer` directly is wrong — it would shift the ring outward.
- **RN1 — Center-label slot pattern:** `Chart.center_label: ?[]const u8 = null`. The chart module has no glyph atlas; it emits an `aa_filled_circle` background as a slot, and the caller renders the actual text glyphs. This is the same deferral pattern used by `drawLegend()` (swatches only, no text). Always follow this pattern for modules that lack glyph access.
- **RN2 — Callout rendering:** `Chart.callouts: []const Callout = &.{}`. For pie charts, `renderCallouts` computes each segment's mid-angle by replaying the renderPie angle traversal, then emits one 2-point `PolylineCmd` (leader line) + one `filled_rect` (label background) per callout. The public `computeCalloutPos` helper returns geometry without side effects — useful when the caller needs to position glyph commands.
- **Area chart rendering (Vulkan-safe pattern):** `renderArea` emits `aa_filled_rect` column segments between adjacent data points — one rect per pair spanning `x[i]→x[i+1]` from `min(py[i],py[i+1])` to baseline, plus a 2 px top-edge rect. Do NOT use `filled_path`/`polyline` — the Vulkan backend treats those as no-ops.
- **Scale tick ownership:** All three numeric tick generators (`linearTicks`, `logTicks`, `timeTicks`) and `bandTicks` allocate both the `[]Tick` array AND the `label` string via the passed allocator. The caller (`drawAxes`) must free every tick's label then the array: `for (ticks) |t| alloc.free(t.label); alloc.free(ticks);`. This is now done with `defer` in `drawAxes` for both x and y tick slices.
- **RN7 — Dashed line pattern:** Crosshair is "dashed" by emitting multiple short 2-point `PolylineCmd` segments (alternating dash/gap), NOT by adding a dash-pattern field to `PolylineCmd`. This preserves the draw-command vocabulary (INV-2.1-v2) and avoids a renderer change. Use this pattern wherever dashed lines are needed in chart components.
- **RN7 — Decoupled state / render:** `CrosshairState` in `interaction.zig` is pure data (the snapped pixel x); the visual render in `marks.renderCrosshair` is driven by `Series.hovered_datum` (the signal-based hover state). These are independent — `CrosshairState.x` is a caller-side cache; the render path reads the series state. Do not couple them.
- **ArrayListUnmanaged.append in Zig 0.16:** The signature is `append(self, gpa: Allocator, item: T)`. All `out.append` calls in chart marks MUST pass the allocator as the first argument. Omitting it compiles only because the function is lazily analyzed — if `chart.render()` is called from tests, the missing allocator will cause a compile error.
- **Test arena pattern:** Tests that call `chart.render()` must use an `ArenaAllocator` (not bare `std.testing.allocator`) because the draw list holds slices allocated during rendering. The arena frees everything on `deinit`, avoiding leak detection failures.

### App layer — Milestone 1 (src/app/)
- **Goal:** Single `App.run()` entry point that owns and drives all modules. Wires together
  modules 01-09 into a runnable application.
- **Key types:** `App`, `AppOptions`, `EventQueue`, `Event`, `Key`, `MouseButton`, `Action`,
  `Modifiers` — all in `src/app/types.zig`.
- **Init order (must be exact):** Platform → VulkanBackend → initQuadPipeline → FontFamily →
  GlyphAtlas → GpuAtlas → Scene. Deinit is exact reverse.
- **R60:** `AppOptions` gains `bold_font_path` / `italic_font_path` (both optional). `AppInner`
  holds `font_family: FontFamily` instead of `font: Font`. **R64:** `FontFamily` is now
  defined in `src/02/types.zig` (moved from `src/app/font_family.zig` to avoid upward
  import); `src/app/font_family.zig` re-exports it. `FontFamily.face(bold, italic)` returns
  `*Font` with fallback to regular. `FontFamily.addFallback(ttf)` registers a fallback font.
- **Frame loop order:** poll events → drain EventQueue → apply pending resize → beginFrame →
  measurePass → re-upload GPU atlas if generation changed → layout solve → buildDrawList →
  clear → drawFrame → endFrame.
- **Present mode:** always `VK_PRESENT_MODE_FIFO_KHR`. No mailbox, no immediate. Changed in
  `src/01/types.zig:chooseSwapPresentMode`.
- **GLFW user pointer:** `glfwSetWindowUserPointer` is called exactly once per window and
  always points to `PlatformImpl.callback_ctx` (a `GlfwCallbackContext` struct). Both the
  event queue and the resize callback share this single pointer. Never add a second call.
- **Event types live in module 01** (`src/01/types.zig`) to avoid an upward import from the
  app layer into itself. `src/app/types.zig` re-exports them under the R11 names.
- **`dispatchEvents` is implemented (M3)** — handles Tab/Shift+Tab focus cycling,
  click-based focus/button/checkbox/dropdown interaction, character input, clipboard
  (Ctrl+C/V/X), scroll wheel. The `left_mouse_down: bool` and `last_cursor_x/y: f32`
  fields track interaction state.
- **R41 — `OverlayLayer` (`src/app/overlay.zig`):** Ordered list of named `DrawCommand` slices rendered after the main pass. `allocId` → `setSlot` → `flatten` → submit. `removeSlot` clears on dismiss.
- **Frame loop order (updated M3):** poll events → drain EventQueue → dispatchEvents →
  apply pending resize → beginFrame → measurePass → re-upload GPU atlas if generation changed
  → layout solve → **`scene.fireQueuedCallbacks()`** → buildDrawList → clear → drawFrame →
  endFrame → clear dirty bits.
- **R73–R77 — Animated elements (M7 Phase 2):** `AppInner` increments `self.scene.frame_count` (wrapping `+%=`) and sets `self.scene.frame_time_ms` each frame before calling `buildDrawList`. `hasAnimatedElements(scene, tooltip)` scans `_kind[]` and `_progress_state[]` to detect spinner or indeterminate progress bars AND checks `tooltip.isPending()` (tooltip hover delay); when found, the idle check calls `pollEvents()` (non-blocking) instead of `waitEvents()` so the display refreshes each frame.
- **R74 — `ToastManager` (`src/app/toast.zig`):** Wire into app: `var toasts = ToastManager.init(&overlay); defer toasts.deinit(alloc);`. Call `toasts.tick(now_ms, w, h, tokens, font, &atlas, &overlay, alloc)` once per frame after `buildDrawList`. Internally frees its own draw-command slice at start of each tick.
- **R75 — `DialogManager` (`src/app/dialog.zig`):** Wire into app: `var dialog = DialogManager.init(&overlay); defer dialog.deinit(alloc);`. Call `dialog.buildOverlay(w, h, tokens, &overlay, alloc)` each frame when open. `dialog.open(content_idx, &scene)` hides the rest of the scene and traps focus; `dialog.close(&scene)` restores it.
- **R7C — `TooltipManager` (`src/app/tooltip.zig`):** Fields in `AppInner`: `tooltip_manager: TooltipManager = .{}`. `deinit` called in `AppInner.deinit`. Mouse move handler calls `onHover(idx, text, now_ms)` / `onLeave(idx)` based on hit-testing `_tooltip[]`. `isPending()` checked in `hasAnimatedElements`. `tick` called once per frame to build overlay.
- **R7D — `ContextMenuManager` (`src/app/context_menu.zig`):** Fields in `AppInner`: `context_menu_manager: ContextMenuManager = .{}`. `deinit` called in `AppInner.deinit`. Right-click (`mb.button == .right`) opens menu via `openAt(menu_idx, x, y, &overlay, tokens, &font_family.regular, &atlas_cpu, gpa)` when `contextMenuIdxOf(hit) != 0xFF`.
- **M9 — `DebugOverlay` (`src/app/debug_overlay.zig`):** Toggled by F1 in `handleKey`. `updateHover` iterates elements in REVERSE order, skips hidden+zero-size. `buildDebugDrawList` emits `border_rect` for every live element + an info panel for the hovered element. Border color encodes role: hovered=accent, focusable=info, container=ok, other=warn.
- **M9 — `PerfHud` (`src/app/perf_hud.zig`):** Maintains a 16-entry ring buffer of frame times. `record(FrameCounters)` pushes to the ring; `smoothFrameMs()` averages non-zero entries. `buildHudDrawList(alloc, enabled, viewport_w, tokens, font, atlas)` returns nil-length slice (fast path) when `!enabled`.
- **M9 — Theme live-swap pattern:** `setTheme(theme)` → scale tokens → `rebuildStyles()` → `markAllDirty()`. `rebuildStyles` calls `defaultStyleFor(kind, tokens)` + `resolveStyleForIdx(idx, base)` (which calls `markup_mod.resolveClasses(classes, tokens)`) for every live element. `toggleTheme` flips `_current_mode` and calls `setTheme(Theme.build(_current_palette, mode))`.
- **M9 — Font scale pattern:** `setFontScale(factor)` clamps to `[0.5, 4.0]`, stores in `_font_scale`, rebuilds tokens via `Theme.build(_current_palette, _current_mode).tokens.scaled(factor)`, calls `rebuildStyles()` + `markAllDirty()`.
- **M9 — Frame loop additions:** After `buildDrawList`, append debug/HUD draw lists before `drawFrame`. Record `_frame_start_ns = std.time.nanoTimestamp()` at `beginFrame`; compute `elapsed_ms` after `endFrame`; call `perf_hud.record(FrameCounters{…})`.
- **Viewport constraints:** stored as `AppInner.viewport_constraints: Constraints` and updated
  on every resize. Passed to `layout.solve` each frame. No `LayoutEngine.setViewport` method
  exists in module 04 — the App layer owns this state.

---

## 7. Common patterns and idioms

### Reading a module for the first time
1. Read `00_constitution.md` (always first).
2. Read `NN.spec.md` for the module you're implementing.
3. Read `NN.types.zig` — that is what you're implementing against.
4. Read `NN.acceptance_test.zig` to understand the exact behavioral expectations.
5. Read `NN.checklist.md` to understand the verification criteria.

### Implementing a module
1. Implement the bodies of the stubs in `types.zig`. Do NOT change signatures.
2. Run `zig test NN.acceptance_test.zig` as your feedback loop.
3. Do NOT implement anything listed under "Non-goals" in the spec.
4. Go through `NN.checklist.md` line by line. Tick boxes only when you can verify them.
5. Update `docs/requirements/DEMO_APP.md` to include the new feature in the appropriate
   Showcase screen (or add a new screen if the feature is too large to fit an existing one).
   A feature with no demo coverage is invisible to the next agent and will break silently.

### Merge rule for style layering (module 07)
```
base     = defaultStyleFor(kind, tokens)
resolved = resolveClasses(node.classes, tokens)
empty    = resolveClasses("", tokens)
final.field = if (resolved.field != empty.field) resolved.field else base.field
```

### Insertion order in the element store
`childrenOf(id)` MUST yield children in the order they were added via `addChild`. Module
04's tests assert left-to-right placement that depends on this.

### Dirty elements
Newly added elements are always marked dirty. `markDirty` → bitset → `dirtyIndices` iterator
→ per-frame scan. Never scan the full element list; always use the dirty iterator.

### Index reuse
`addRoot`/`addChild` pop from the `free` list when available. A reused index has its
generation bumped, so all previously issued handles for that index become stale and
`isValid` returns false.

### Atlas generation tracking (App layer pattern)
`GlyphAtlas.generation: u32` is bumped every time a new glyph is rasterized into the CPU
atlas (i.e. after `scene.measurePass`). The App layer caches `atlas_generation_seen: u32`
and re-uploads the GPU atlas with `GpuAtlas.upload` only when the generation changes. This
avoids an expensive GPU upload every frame when the glyph set is stable.

### GLFW single user-pointer rule
GLFW allows exactly one `glfwSetWindowUserPointer` per window. All GLFW callbacks that need
application state must share a single context struct (`GlfwCallbackContext` in `PlatformImpl`)
pointed to by that one pointer. Never call `glfwSetWindowUserPointer` a second time — it
silently overwrites the first, breaking all callbacks registered before it.

### Upward-import avoidance via function-pointer indirection
When a lower-numbered module needs to call into a type defined in a higher-numbered module
(e.g. module 01's GLFW callbacks need to push into `EventQueue` defined in the app layer),
define the type in the lower module and pass a function pointer (`PushEventFn`) instead of a
direct reference. The higher module provides the thunk (`EventQueue.pushThunk`). This
preserves the build-order invariant (INV-3.4) without duplicating type definitions.

---

## 8. Boundaries that bite (things that are NOT allowed even if they seem fine)

| Temptation | Why it is wrong |
|---|---|
| Edit `acceptance_test.zig` to fix a failing test | INV-5.3 — tests are the spec |
| Add a `GpuBackend` interface for "future DX12" | INV-1.1 — no speculative extension points |
| Pull in FreeType or HarfBuzz for text | INV-1.3, INV-5.6 — stb_truetype only |
| Store `*LayoutNode` across frames | INV-3.2 — arrays may reallocate |
| Implement a non-goal from any spec | INV-5.4 — scope creep is the failure mode |
| Use cascade/specificity/selectors in styling | INV-4.2 — Tailwind flat utilities only |
| Reference a hex literal in a component style | INV-4.3 — tokens only |
| Import a higher-numbered module | INV-3.4 — build order is enforced |
| Runtime path binding for static screens | INV-4.1 — comptime only for static |
| Add macOS, web, or mobile code | INV-1.2 — Windows + Linux only |
| Add complex-script shaping or bidi text | INV-1.3 — Latin + Cyrillic only |
| Per-widget heap allocations | INV-3.1 — parallel arrays, no widget objects |

---

## 9. Blocked by the rules — amend, don't pause

When the rules as written block correct work, you resolve it yourself under the Autonomous
Amendment Procedure (constitution §8 / Workflow 5): draft the change, amend `00_constitution.md`
with an `(AGENT AMENDMENT …)` marker, append a row to `docs/specs/AMENDMENTS_LOG.md`, add any new
glossary term, then continue. Do NOT pause or surface these to the human. This covers:

1. A task instruction that contradicts `00_constitution.md`.
2. A `types.zig` signature that must change to implement the spec (use the contract-amendment
   procedure, INV-5.3).
3. An `acceptance_test.zig` that must change because the contract it verifies changed.
4. A task that needs a dependency not in INV-5.6 (add it, pinned).
5. A concept with no glossary term (add the term).
6. A spec non-goal that conflicts with a genuine requirement (amend the non-goal).

**Escalate (write an `_escalation.md` and stop) ONLY** for a hard blocker no amendment can
resolve — a missing external resource you cannot obtain, or repeated unrecoverable failure after
the 3-attempt redo cap. The owner audits `AMENDMENTS_LOG.md` asynchronously and may revert.

---

## 10. Approved dependencies (INV-5.6)

| Dependency | Role | How included |
|---|---|---|
| Zig std | Everything std gives us | `@import("std")` |
| GLFW | Windowing, input, Vulkan surface | `@cImport` |
| Vulkan loader | GPU API | `@cImport` |
| `glslc` (Vulkan SDK) | GLSL → SPIR-V at build time | Invoked from `build.zig` |
| stb_truetype | Glyph rasterization + metrics | `@cImport` (single-header) |

To add a new entry: amend INV-5.6 under the Autonomous Amendment Procedure (constitution §8 /
Workflow 5) — pin the version, record it with an `(AGENT AMENDMENT …)` marker, and log it in
`docs/specs/AMENDMENTS_LOG.md`. No human approval; never a silent addition.

---

## 11. Testing workflow

```powershell
# Run acceptance test for module N
zig test docs/specs/0N.acceptance_test.zig

# For module 01 (smoke test — needs real GPU)
zig test docs/specs/01.smoke_test.zig

# Run unit tests written by test-designer agent
zig test src/NN/NN_test.zig
```

A module is done when:
- `zig test` against its `acceptance_test.zig` passes with zero failures.
- `zig test` against any unit test file (`src/NN/NN_test.zig`) passes with zero failures.
- Every checkbox in its `checklist.md` is ticked.
- `docs/requirements/DEMO_APP.md` has been updated to cover the new feature.
- **`zig build visual-check` passes** (required for any change touching rendering, layout, or styling).
- Module 01 additionally requires a manual visual confirmation on both Windows and Linux.

### 11.1 Frozen acceptance tests vs. agent-written unit tests

| File | Owner | Status | What it does |
|---|---|---|---|
| `docs/specs/NN.acceptance_test.zig` | **Human (spec author)** | **FROZEN** (INV-5.3) | Defines the contract. The executable spec. Agents implement code to pass it. Never modify. |
| `src/NN/NN_test.zig` | **Agent (test-designer)** | **MUTABLE** | Unit tests covering edge cases, error paths, boundary conditions. Created alongside implementation. Updated when code changes (normal code review). |

The key distinction: **INV-5.3 protects the acceptance test file itself, not the testing infrastructure.**
A test-designer agent creates new test files. If those tests become obsolete (code changes), they're updated via
normal code maintenance, not preserved forever.

### 11.2 Visual verification — required for any rendering change

Unit tests and acceptance tests verify data structures and logic paths. They cannot catch:
- text rendered transparent (wrong default color)
- layout that computes non-zero rects but emits invisible draw commands
- a widget kind that falls through to a no-op rendering branch
- theme tokens that produce unreadable contrast

**Rule: if a task touches `buildDrawList`, `defaultStyleFor`, any `*State` render path, or any
`ComputedStyle` field — run `zig build visual-check` and confirm it passes before declaring done.**

#### The automated visual check

```powershell
zig build visual-check
```

This single command:
1. Builds the demo binary (`zig build`)
2. Runs it for 3 frames with a real Vulkan swapchain (`--screenshot-frames 3`)
3. Reads the rendered frame back from GPU memory to CPU
4. Writes a PNG to `testdata/screenshot_actual.png`
5. Runs `src/tools/visual_check.zig` — fails (exit 1) if the PNG is all-black

A passing run looks like:
```
PASS: screenshot 'testdata/screenshot_actual.png' — 42.3% non-zero IDAT bytes
```

A failing run (blank frame) looks like:
```
FAIL: screenshot appears blank — 0.1% non-zero IDAT bytes (threshold 5.0%)
```

The check requires a display (GLFW opens a real window briefly). It does **not** require
manual intervention — it is fully automated and returns exit code 0/1.

#### How it works

`AppOptions.screenshot_frames` (> 0) triggers the readback path in `AppInner.runWithNav`:
after the Nth frame, `VulkanBackend.readbackFrameRgba` blits the swapchain image to a
host-visible buffer, swaps BGRA→RGBA, and returns the pixel data. `src/app/png_writer.zig`
encodes it to an uncompressed PNG (zlib store blocks, no external deps).
`src/tools/visual_check.zig` checks that the IDAT payload has > 5% non-zero bytes —
a blank (all-black) frame compresses to near-zero entropy.

#### What "obviously wrong" looks like

| Symptom | Likely cause |
|---|---|
| `visual-check` fails: 0% non-zero bytes | `buildDrawList` returns empty or all elements zero-size |
| `visual-check` passes but image shows no text | `text_color.a == 0` — check `defaultStyleFor(.text)` |
| Layout correct, glyphs invisible | `font_size = 0` in `ComputedStyle` default |
| Widgets present but wrong color | Token reference resolves to wrong palette entry |
| Content clipped at viewport edge | `h-full`/`w-full` not resolving in layout |

#### Attaching the screenshot for human review

After `zig build visual-check` passes the automated check, attach the PNG for human review:

```powershell
# Screenshot is at testdata/screenshot_actual.png — attach it to the conversation
```

The agent reads the file with the `Read` tool (it supports PNG) and describes what it sees.

---

## 12. Quick terminology reference

| Term | Meaning |
|---|---|
| `ElementId` | `{ index: u32, gen: u32 }` — generational handle, never a pointer |
| `LayoutNode` | Per-element layout data (display, direction, flex props, computed rect) |
| `ComputedStyle` | Fully resolved drawable style (color, font, border, radius, padding) |
| `Tokens` | Semantic design roles (bg_canvas, text_body, accent, …) |
| `Palette` | Raw named values — the only layer that changes between themes |
| `NodeDesc` | Markup parser output — tag + attrs + classes + children, throwaway |
| `Scene` | Module 07 struct — owns `ElementStore` + parallel kind/style/text arrays |
| `FormModel` | `[]FieldSpec` — flat field list produced from a JSON Schema |
| `Value` | Dynamic JSON-like union: null/bool/int/float/string/array/object |
| dirty bitset | Per-element bit; set on signal write; cleared after layout/paint scan |
| arena | Per-screen `ArenaAllocator` backing element arrays; reset on screen close |
| seam | Documented concrete method set that a future backend would match |

Full glossary lives in `docs/specs/glossary.md` (if it does not exist yet, do not invent
terms — surface the gap).

---

## 13. RN12/RN13 patterns (added 2026-06-15)

### Default palette is now zinc-based (RN12)

`Palette.default()` returns shadcn/ui-equivalent zinc values. The teal-accent palette
(`0x1D9E75`) is gone. When updating tests that check exact palette hex values, update
`src/05/05_test.zig` (not the frozen `docs/specs/05.acceptance_test.zig`).

### Radio/Checkbox fixed-size (RN12)

Both are now 16px fixed regardless of `font_size * dpi_scale`. When adding new widget
renderers, prefer explicit pixel sizes over font-size-relative sizes for icon/control elements.

### TrendBadge layout gotcha

`TrendBadge` nodes must have explicit width/height classes (e.g. `w-14 h-4`). Without them
the layout engine assigns zero size and the renderer produces no visible output.

### `src/app/ui/` component library (RN13)

`src/app/ui/mod.zig` exports class string namespaces (`Badge`, `Button`, `Card`, `Input`,
`Separator`). These are NOT components — they are design-token class strings. The caller
builds `NodeDesc` with their own stack-allocated `[N]Attr` arrays. The ui/ files contain
zero runtime code (just constants).

### Adding a new sidebar screen (RN13 pattern)

1. Add `<name>_ctx: ?*anyopaque = null` to `GlobalState` in `shared/types.zig`
2. Add `<name>: SidebarCb` to `SidebarCbs`
3. Add `ctxForScreen` entry for the name
4. Expand the `pairs` array in `wireSidebarCallbacks` to `[N+1]`, increment active guard
5. Expand `_btn_attrs` and `_btns` in `sidebar.zig` from `[N]` to `[N+1]`
6. Add import, ctx, global wire, `nav.register`, and initial-screen handler in `main.zig`

### `DropdownOption` requires `*anyopaque` value

`setDropdownOptions` takes `[]const DropdownOption` where each entry has a `.value: *anyopaque`.
Use module-level `var _values: [N]u8` + `var _opts: [N]DropdownOption` for stable storage
(same pattern as `forms.zig` / `dashboard.zig`).

---

## 14. RN14/RN15 patterns (added 2026-08-01) — component-library visual fidelity + renderer fixes

Session goal: make `src/app/ui/` (`Button`, `Card`, `Input`, `Badge`) visually reproduce a
real external design system's tokens (AI-Qadam), bottom-up (components first, page assembly
second). Along the way this uncovered and fixed four renderer-level bugs that were silently
breaking rendering fidelity for the whole app, not just this feature. See
`docs/specs/AMENDMENTS_LOG.md` (2026-08-01 RN14/RN15 entries) for the exact palette/token
values changed. Patterns below are for the NEXT agent touching the renderer or component
library — read this before assuming `filled_rect`/`border_rect`/`gradient_rect` behave the
way their names suggest.

### 14.1 Swapchain format: UNORM, not SRGB, when the shader already writes encoded bytes

`VulkanBackend`'s swapchain surface-format selection (`src/01/types.zig`, surface-format
selection near the swapchain-creation path) now prefers `VK_FORMAT_B8G8R8A8_UNORM` with
`VK_COLOR_SPACE_SRGB_NONLINEAR_KHR`, NOT `VK_FORMAT_B8G8R8A8_SRGB`. Root cause: CPU-side
color prep (`Color09`/`Color.hex`) already stores sRGB-encoded byte values, and the vertex
color attribute format is `VK_FORMAT_R8G8B8A8_UNORM` (linear passthrough). Pairing that with
an `_SRGB` swapchain format made the GPU apply a SECOND linear→sRGB re-encode on store,
double-encoding already-encoded values (measured pixel ≈ intended^(1/2.2)) — this washed out
every color in the entire app, not just AI-Qadam colors. **Lesson: when your CPU-side color
prep already produces final encoded bytes, the swapchain/target format must be UNORM. Only
use an `_SRGB` format if you are deliberately feeding it linear values and want the GPU to do
the encode.** Keep the color SPACE as SRGB_NONLINEAR regardless — that's about how the
display interprets the bytes, not whether the GPU re-encodes them.

### 14.2 Per-quad rounded-clip technique for `radius > 0` on ordinary fills

`filled_rect` and `aa_filled_rect` DrawCommands carry a `radius` field that was previously
declared on the contract but silently dropped by the Vulkan consumer (corners always
rendered square regardless of `ComputedStyle.radius`). Fixed by reusing the EXISTING
`clipRadii`/`clipEnabled` push-constant discard mechanism that scrollview clipping already
used (previously scrollview-only) — no shader change needed. Pattern, in
`VulkanBackend.drawFrame`'s command-walk loop:

```zig
if (r.radius > 0 and scissor_range_count + 2 <= scissor_ranges.len) {
    const saved_clip = current_clip;
    current_clip = .{ .rect = r.rect, .radius_tl = r.radius, .radius_tr = r.radius,
                       .radius_br = r.radius, .radius_bl = r.radius };
    scissor_ranges[scissor_range_count] = .{ .scissor = current_scissor, .first_vert = vert_count, .clip_rounded = current_clip };
    scissor_range_count += 1;
    emitQuad(...);                    // the actual quad, now clipped to rounded corners
    current_clip = saved_clip;        // restore whatever clip state was active before
    scissor_ranges[scissor_range_count] = .{ .scissor = current_scissor, .first_vert = vert_count, .clip_rounded = current_clip };
    scissor_range_count += 1;
} else {
    emitQuad(...);                    // radius == 0: no bracketing needed
}
```

Each radius'd quad opens and closes its own scissor-range boundary, bracketing exactly that
one quad. Because every rounded quad now consumes 2 extra range slots, **`scissor_ranges`
was bumped from `[64]` to `[512]`** — a busy screen with many rounded cards/buttons/badges
can exceed a 64-range budget fast. If you add a new draw-command kind with a `radius` field,
follow this exact bracketing pattern rather than inventing a new clip mechanism.

### 14.3 Border-stroke-via-4-quads technique

`border_rect` previously emitted ONE opaque quad covering the entire element rect — meaning
"a bordered element" rendered as a solid fill in the border color, not a stroke. Fixed by
expanding to 4 edge quads (top/bottom/left/right), clamping width to `min(w,h)/2`:

```zig
const max_w = @min(br.rect.w, br.rect.h) / 2.0;
const bw = if (br.width <= max_w) br.width else max_w;
// top:    { x, y,          w,      h = bw }
// bottom: { x, y+h-bw,     w,      h = bw }
// left:   { x, y+bw,       w = bw, h-2*bw }
// right:  { x+w-bw, y+bw,  w = bw, h-2*bw }
```

This reimplements (does not import) the same geometry `src/09`'s tested
`expandBorderToQuads`/`clampBorderWidth` helpers use — `src/01` is lower-numbered than
`src/09` and INV-3.4 forbids an upward import, so the two copies must be kept in sync by
hand if the stroke geometry ever changes. The `.border_rect` DrawCommand itself is unchanged
(frozen acceptance-test contract, `docs/specs/09.acceptance_test.zig`); only this consumer's
interpretation of the command changed.

### 14.4 CPU/shader draw-mode-number table (keep this in sync — it drifted once already)

The `emitQuad(..., mode)` last argument is a raw integer that must agree with the `switch` in
`quad.frag` (and its HLSL/WGSL equivalents). There is no enum shared between CPU and shader —
just an integer convention. It had already drifted once (`gradient_rect` was using the
unimplemented mode `2` instead of the real gradient mode `5`, so gradients rendered as a flat
wrong color; `aa_filled_rect` was colliding with `gradient_rect` on mode `5`, so an AA rect
rendered as a color blend toward black instead of a solid fill). Current, corrected mapping:

| Mode | Meaning | CPU emitters |
|---|---|---|
| 0 | Solid rect | `filled_rect`, `aa_filled_rect`, `border_rect` edges, `image_rect` (tint-less path) |
| 1 | Glyph (grayscale atlas alpha mask) | `.glyph` (non-subpixel) |
| 2 | **Reserved** — unimplemented "bordered rect" stub in `quad.frag` | none — do not target this |
| 3 | Image rect (RGBA atlas sample × tint) | `image_rect` |
| 4 | SDF icon | `sdf_icon` |
| 5 | Gradient (two-stop lerp driven by UV) | `gradient_rect` |
| 6 | AA filled circle (per-pixel distance feather) | `aa_filled_circle` |
| 7 | Subpixel glyph (RGB coverage atlas) | `.glyph` (subpixel) |

If you add a new DrawCommand variant that needs a distinct shader path, claim mode `2` (the
only reserved/unused slot) or add a new case to all three shaders (`quad.frag`, `quad.hlsl`,
`quad.wgsl`) simultaneously and extend this table in the same change — do not reuse an
already-claimed mode number.

### 14.5 Screenshot workflow: invoke the binary directly, not `zig build run-demo --`

`zig build run-demo -- --screenshot-frames N ...` was observed to hang in this session
instead of running the N frames and exiting. For screenshot/visual-check work, prefer
invoking the built binary directly:

```powershell
zig build
zig-out\bin\showcase.exe --screenshot-frames 3 --screenshot-out testdata\screenshot_actual.png --initial-screen components
```

This bypasses whatever `zig build run-demo --` argument-forwarding or process-lifecycle issue
caused the hang. `zig build visual-check` (which does not go through `run-demo`) is unaffected
and remains the required automated gate — this note is only about ad hoc manual screenshots
during a Visual Validation Loop.

### 14.6 Open gap: badge corner radius does not render (flagged, not fixed)

`ui.Badge.*` class strings include `rounded-sm`, and it was traced and confirmed in code that
this correctly resolves to a non-zero `ComputedStyle.radius` at the badge element. Despite
that, 3 independent pixel-level visual checks found badges render with perfectly square
corners and zero anti-aliased curvature — while buttons and cards (which go through the same
`filled_rect`/`aa_filled_rect` radius path documented in §14.2) DO show genuine rounded-corner
AA in the same screenshots. The root cause was NOT found this session. Leading hypothesis,
NOT confirmed: `BadgeState`/`_badge_state`'s draw-command construction (module 07/09, see §6
module 07 R7B/R79 history) may have a badge-specific rect-emission path that doesn't forward
`style.radius` into the `filled_rect`/`aa_filled_rect` command the same way the generic
element-paint path does. Next agent: instrument or read the badge-specific render branch in
`buildDrawList` (search for where `.badge` kind is special-cased) before assuming the fix is
in `src/01/types.zig` — the radius plumbing there is already confirmed correct for the
commands it receives; the bug is upstream of that, in what command badges actually emit.

