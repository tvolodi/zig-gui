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
easier. If a signature seems wrong, surface it to the human; do not silently diverge.

### INV-5.2 — "Done" is executable
A module is done when `acceptance_test.zig` passes via `zig test` AND every box in
`checklist.md` is ticked. "It looks right" is not done.

### INV-5.3 — Never edit `acceptance_test.zig`
It is the human's specification — the contract definition. Editing a test to make it pass
defeats the system. If a test looks wrong, STOP and surface it.

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
- **Key types:** `Word`, `Line`, `TextExtent`, `FontMetrics`, `Font`, `GlyphAtlas`
- **Does NOT touch module 03.** Defines its own `TextExtent`. Handoff to layout happens via
  module 07.

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
- **Eleven widget kinds (M4):** `text`, `button`, `input`, `card`, `row`, `column`, `dropdown`,
  `checkbox`, `scrollview`, `image`, `icon`.
- **`Scene`** owns the `ElementStore` AND all parallel arrays: `kind[]`, `style[]`, `text[]`,
  `_button_state[]`, `_input_state[]`, `_dropdown_state[]`, `_checkbox_state[]`,
  `_scroll_state[]`, `_queued_callbacks`, `_pseudo[]`, `_image_state[]` (INV-3.1: no per-widget heap objects).
- **Focus state:** `focused_idx: u32` (maxInt(u32) = no focus) + `focusable_indices: []u32`
  rebuilt by `instantiate()`. Focusable kinds: button, input, dropdown, checkbox (B2).
- **Two passes:** `instantiate` (no font, fully testable), then `measurePass` (font-dependent,
  fills `LayoutNode.measured`).
- All element creation/removal goes through `Scene`, never the store directly.
- **Callback firing:** `Scene.fireQueuedCallbacks()` called ONCE per frame by the app layer,
  after layout solve, before `buildDrawList` (INV-3.3).
- **R40 — Pseudo-state:** `PseudoState` parallel array `_pseudo[]`; `setPseudo(idx, state)` marks dirty.
- **R43 — Image state:** `ImageState` parallel array `_image_state[]`; `setImage(idx, id)` / `setImageTint(idx, color)`.
- **Style fields (M4):** `ComputedStyle` gains `truncate: bool`, `opacity: f32`, `shadow_blur: f32`, `shadow_offset_x/y: f32`, `shadow_color: Color`; resolved by `resolveClasses` from Tailwind `truncate`/`opacity-*`/`shadow-*` classes.

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

### App layer — Milestone 1 (src/app/)
- **Goal:** Single `App.run()` entry point that owns and drives all modules. Wires together
  modules 01-09 into a runnable application.
- **Key types:** `App`, `AppOptions`, `EventQueue`, `Event`, `Key`, `MouseButton`, `Action`,
  `Modifiers` — all in `src/app/types.zig`.
- **Init order (must be exact):** Platform → VulkanBackend → initQuadPipeline → Font →
  GlyphAtlas → GpuAtlas → Scene. Deinit is exact reverse.
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

## 9. Stopping conditions — when to pause and surface to the human

Stop and report to the human (do not guess or work around) when:

1. A task instruction appears to contradict `00_constitution.md`.
2. A `types.zig` signature appears wrong and you cannot implement the spec without changing it.
3. An `acceptance_test.zig` test appears to encode incorrect behavior.
4. A task requires an unapproved dependency (see INV-5.6).
5. A concept you need has no glossary term and you're unsure of the right name.
6. The spec's non-goals list would need to be violated to complete the task.

---

## 10. Approved dependencies (INV-5.6)

| Dependency | Role | How included |
|---|---|---|
| Zig std | Everything std gives us | `@import("std")` |
| GLFW | Windowing, input, Vulkan surface | `@cImport` |
| Vulkan loader | GPU API | `@cImport` |
| `glslc` (Vulkan SDK) | GLSL → SPIR-V at build time | Invoked from `build.zig` |
| stb_truetype | Glyph rasterization + metrics | `@cImport` (single-header) |

Do NOT add new entries to this table without recording them in `00_constitution.md` and
surfacing the change to the human.

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
- Module 01 additionally requires a manual visual confirmation on both Windows and Linux.

### 11.1 Frozen acceptance tests vs. agent-written unit tests

| File | Owner | Status | What it does |
|---|---|---|---|
| `docs/specs/NN.acceptance_test.zig` | **Human (spec author)** | **FROZEN** (INV-5.3) | Defines the contract. The executable spec. Agents implement code to pass it. Never modify. |
| `src/NN/NN_test.zig` | **Agent (test-designer)** | **MUTABLE** | Unit tests covering edge cases, error paths, boundary conditions. Created alongside implementation. Updated when code changes (normal code review). |

The key distinction: **INV-5.3 protects the acceptance test file itself, not the testing infrastructure.**
A test-designer agent creates new test files. If those tests become obsolete (code changes), they're updated via
normal code maintenance, not preserved forever.

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
