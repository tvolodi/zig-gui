# 00 — Constitution

> **Read this file in full at the start of every task, before reading any module spec.**
> These are invariants. No module, no task, and no agent session may violate them.
> If a task instruction appears to contradict this file, STOP and surface the conflict —
> do not resolve it by guessing. This file wins over any other document except a direct,
> explicit human override in the current task.

This project is a native GUI framework written in Zig. It renders to the GPU, is delivered
as a small binary, and is authored using web-familiar syntax (HTML-like markup + a Tailwind
subset). It is built by AI agents across many independent sessions that share no memory.
This file is the shared memory.

---

## 0. How to read these rules

Each rule has the form **RULE — rationale**. The rationale is not optional decoration:
it tells you *why* the rule exists so you do not "improve" the system by breaking it.
A rule with a rationale you disagree with is still binding. Raise it with the human; do
not act on the disagreement.

---

## 1. Scope invariants (what this is and is not)

- **INV-1.1 — Audience is the project owner only, not the public.**
  Rationale: No API-stability guarantees are owed. Prefer the simplest correct design over
  a configurable or future-proof one. Do NOT add extension points, plugin systems, or
  options "for flexibility." Hardcoding a single correct behavior is preferred over a
  configurable one unless a spec explicitly requires configuration.

- **INV-1.2 — Target platforms are Windows and Linux only.**
  Rationale: A single Vulkan backend covers both. Do NOT write platform-specific UI code
  paths beyond the windowing/surface layer. Do NOT add macOS, web, or mobile code.

- **INV-1.3 — No complex-script shaping; fallback glyph lookup for symbols and emoji is permitted.**
  Rationale: No bidirectional text, no Arabic/CJK shaping. Do NOT pull in HarfBuzz or any
  complex text-shaping dependency. A glyph atlas with kerning and basic line breaking is the
  entire text model. If a task seems to need complex shaping, it is out of scope — surface it.
  Fallback font lookup via `stbtt_FindGlyphIndex` (to render emoji, symbols, or extended
  Unicode codepoints from a secondary TTF) is explicitly permitted: it adds no shaping, only
  a glyph-index check. This was authorized by the project owner on 2026-06-03 when R64
  (font fallback) was approved.

---

## 2. Rendering invariants

- **INV-2.1 — One GPU backend: Vulkan, via SPIR-V shaders.**
  Rationale: Covers both target OSes with one code path. A seam (an interface other backends
  *could* implement later) is allowed and encouraged, but DO NOT implement DX12 or Metal.

- **INV-2.2 — Windowing, input, and the Vulkan surface come from GLFW.**
  Rationale: Solved, boring, cross-platform. Do NOT write a custom windowing or OS-event
  layer. Bind GLFW via `@cImport`.

- **INV-2.3 — The renderer consumes a flat draw-command list, nothing else.**
  Rationale: The renderer does not know about widgets, layout, or state. It receives a
  serialized list of draw commands once per frame and submits it. Keep this boundary clean.

---

## 3. Architecture invariants (the load-bearing decisions)

- **INV-3.1 — Memory is data-oriented. No per-widget heap objects.**
  Rationale: Widgets are NOT objects scattered on the heap. All widget data lives in
  contiguous, parallel arrays (struct-of-arrays). A widget IS an index shared across those
  arrays. Do NOT create a `Widget` struct that owns its own fields and is allocated
  individually. See `specs/03_element_store/` for the canonical `ElementStore`.

- **INV-3.2 — Widget identity is a generational handle, never a pointer.**
  Rationale: `ElementId = struct { index: u32, gen: u32 }`. Pointers into the arrays are
  forbidden in stored state because arrays may reallocate. Resolve handles to pointers only
  locally, within a single function call, never across frames.

- **INV-3.3 — All reactivity flows through signals → dirty bitset → linear scan.**
  Rationale: A signal write marks affected element indices dirty in a bitset. Each frame
  scans only set bits. Do NOT diff trees. Do NOT re-layout or re-paint anything whose dirty
  bit is clear. There is exactly one reactivity mechanism; do not introduce observers,
  event emitters, or callbacks as an alternative change-propagation path.

- **INV-3.4 — Three trees, three jobs. Do not merge them.**
  Rationale: Widget (immutable per-frame description) → Element (persistent state + identity)
  → RenderObject (cached layout + paint). State lives in Element. Layout caching lives in
  RenderObject. Per-frame descriptions are throwaway. Do NOT store state on a widget
  description; do NOT recompute layout for a RenderObject whose inputs are unchanged.

- **INV-3.5 — Per-screen arena allocation.**
  Rationale: Opening a screen bump-allocates its arrays in an arena. Closing it resets the
  arena. Do NOT free individual widgets. Do NOT use a general-purpose allocator for
  per-frame or per-screen widget data.

---

## 4. Authoring & styling invariants

- **INV-4.1 — Two binding mechanisms, each in its lane.**
  Rationale: STATIC screens (app chrome, fixed forms) bind via comptime-resolved field
  offsets — type-checked, zero runtime path resolution. DYNAMIC screens (JSON-schema-driven
  forms) bind via runtime string-path resolution into a dynamic `Value` tree. Do NOT use
  runtime path resolution for static screens. Do NOT attempt comptime binding for
  schema-driven forms (the shape is unknown at compile time — it is impossible, not just
  discouraged).

- **INV-4.2 — Styling mimics Tailwind utility semantics, NOT the CSS cascade.**
  Rationale: Classes are flat, atomic, order-independent. There is NO cascade, NO
  specificity, NO inheritance, NO selectors. A class maps to a fixed set of resolved
  properties. Do NOT implement descendant selectors, `!important`, or property inheritance.
  If a feature requires the cascade, it is out of scope.

- **INV-4.3 — Style values resolve through the four-layer token model.**
  Rationale: palette (raw values) → semantic tokens (roles) → component tokens (per-widget
  styles) → paint. A widget never references a raw palette value or a hex literal. It
  references a resolved `ComputedStyle`. Only layer 1 (palette) changes between themes.
  See `specs/06_theme/`.

- **INV-4.4 — Static markup is baked via a build-time codegen step; runtime parsing is
  dev-only.**
  Rationale: Production ships no markup parser — `.ui` markup is processed by a build-time
  codegen step that runs the same allocator-based `parse` function and emits generated `.zig`
  struct literals (baked tree). A runtime parser exists ONLY behind a `-Dhot-reload` dev
  flag. Do NOT make the runtime parser a production dependency. (Literal `comptime` parsing
  is not used because comptime has no general allocator; one parser function serves both
  build-time codegen and hot-reload — see module 06 spec refinement 1.)

---

## 5. Code & process invariants

- **INV-5.1 — A module's public API is defined by its `types.zig`. Match it exactly.**
  Rationale: Signatures in a module's `types.zig` are contracts. Do NOT change a public
  signature to make your implementation easier. If a signature is wrong, surface it; do not
  silently diverge.

- **INV-5.2 — A module is "done" only when its `acceptance_test.zig` passes and its
  `checklist.md` is fully ticked.**
  Rationale: "Done" is executable, not a judgment call. Run `zig test` against the
  acceptance test. Do NOT mark work complete on the basis of "it looks right."

- **INV-5.4 — Respect declared non-goals.**
  Rationale: Each spec lists non-goals. Do NOT implement them, even if they seem helpful or
  trivial. Scope creep across many sessions is the primary failure mode of this pipeline.

- **INV-5.5 — Every term comes from `glossary.md`. Do not invent synonyms.**
  Rationale: "Element", "RenderObject", "signal", "token" have exact meanings. Using a term
  loosely, or coining a new word for an existing concept, causes drift across sessions. If a
  needed concept has no glossary term, add one to `glossary.md` rather than improvising.

- **INV-5.6 — No dependencies beyond the approved list.**
  Rationale: Approved native deps for v1: GLFW, the Vulkan loader, the Zig standard
  library, and stb_truetype (single-header, public domain; used by module 02 for glyph
  rasterization). Approved build-time tools: glslc (from the Vulkan SDK, for GLSL→SPIR-V
  compilation). Do NOT add a package, vendored library, or build-time tool without an explicit
  human decision recorded here. (Taffy is being *ported*, i.e. reimplemented in Zig, not
  added as a dependency — see `specs/04_layout_engine/`.)

---

## 6. Build order (dependency chain)

Modules are numbered by build order. A module may depend only on lower-numbered modules.
Do NOT introduce a dependency from a lower number onto a higher one.

```
00  constitution (this file)        — shared/glossary.md, shared/interfaces.zig
01  platform spike                  — GLFW window + Vulkan swapchain + clear color + one SPIR-V triangle
02  text                            — glyph atlas, kerning, basic line breaking
03  element_store                   — data-oriented arrays, generational handles, arena
04  layout_engine                   — flexbox + grid (Taffy port), constraint protocol
05  theme                           — four-layer token model, light/dark
06  markup + style                  — comptime .ui parser, Tailwind-subset resolver
07  components                      — text, button, input, card, row/column, dropdown
08  schema_forms                    — Value tree, schema walker, widget registry, validator
09  renderer                        — DrawCommand list, Scene→GPU serializer, quad pipeline, atlas upload
```

Anything not in this list (DataTable, auto-update/CDN delivery, virtualization, charts)
is post-v1 and must not be started without a human decision.

NOTE (2026-06-03, human override): DataTable (M7-10) and row virtualization are
approved for Milestone 7. See R79_data_table.md. This overrides the post-v1
classification.

---

## 7. When in doubt

1. Re-read the relevant invariant above.
2. Check `glossary.md` for the exact meaning of any term.
3. Check the module's `types.zig` for the exact contract.
4. If still ambiguous: STOP and surface the ambiguity to the human. Do NOT guess and
   proceed. A blocked task is cheap; a confidently-wrong implementation merged across
   sessions is expensive.
