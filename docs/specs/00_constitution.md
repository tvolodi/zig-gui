# 00 — Constitution

> **Read this file in full at the start of every task, before reading any module spec.**
> These are invariants. No module, no task, and no agent session may violate them.
> If a task instruction appears to contradict this file, or an invariant is ambiguous, absent,
> or must change to let correct work proceed, the agent **amends this file itself** via the
> Autonomous Amendment Procedure (§8) and continues — it does not stop and ask the owner. A
> human override still outranks any agent amendment, but it is exercised **asynchronously**: the
> owner audits the amendment log (§8) and may revert. Agents never block waiting for that review.

This project is a native GUI framework written in Zig. It renders to the GPU, is delivered
as a small binary, and is authored using web-familiar syntax (HTML-like markup + a Tailwind
subset). It is built by AI agents across many independent sessions that share no memory.
This file is the shared memory.

---

## V2 RATIFICATION (human override, 2026-06-13)

The project owner ratified the Version 2 scope on 2026-06-13. This override replaces INV-1.2,
INV-1.3, INV-2.1, and INV-4.2 with their `-v2` successors (inline below), extends INV-5.6 with
the v2 dependency list, and adds modules 10–13 to the build order (§7). The full rationale and
the design that follows from it live in `V2_ARCHITECTURE.md`; the proposal this ratifies is
`V2_constitution_amendment.md`. Recorded choices: WebGPU = **wgpu-native**; bidi = **pure-Zig
UBA port**. Where a rule below shows both a v1 and a `-v2` form, the `-v2` form is binding.

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

- **INV-1.2-v2 — Target platforms are Windows, Linux, macOS, and Web (WebGPU). Mobile is
  out of scope.** (Ratified 2026-06-13; replaces v1 INV-1.2 "Windows and Linux only.")
  Rationale: macOS and Web are reachable through the backend seam (INV-2.1-v2) and GLFW's
  Cocoa support with no change to the data-oriented core. Mobile (iOS/Android) remains out of
  scope — it requires a touch-first model, a different lifecycle, and store packaging the
  architecture does not address. Do NOT add iOS, Android, or any mobile code path. Per-OS code
  stays confined to the platform-surface layer (`src/01/surface_*.zig`) and module 10; no
  platform branch may leak into layout, style, the element store, or components.

- **INV-1.3-v2 — Complex-script shaping is permitted via HarfBuzz; the text model gains a
  shaping stage and a bidirectional stage, and nothing else.** (Ratified 2026-06-13; replaces
  v1 INV-1.3 "No complex-script shaping.")
  Rationale: Arabic, Indic, and CJK demand contextual glyph selection, ligatures, mark
  positioning, and bidirectional reordering a kerning-only model cannot express. HarfBuzz is
  added as an approved dependency (INV-5.6) and bidi follows the Unicode Bidirectional
  Algorithm. The shaping stage sits between line breaking and glyph rasterization; it does NOT
  change the glyph atlas, the draw-command vocabulary, or the renderer. Do NOT invent a custom
  shaper, and do NOT add line-layout features beyond shaping + bidi (no vertical writing modes,
  no kashida justification) without a further override. See modules 11 (`text_shaping`),
  RK0–RK3.
  Fallback font lookup via `stbtt_FindGlyphIndex` (to render emoji, symbols, or extended
  Unicode codepoints from a secondary TTF) remains explicitly permitted: it adds no shaping,
  only a glyph-index check. This was authorized by the project owner on 2026-06-03 when R64
  (font fallback) was approved.

---

## 2. Rendering invariants

- **INV-2.1-v2 — Multiple GPU backends behind one seam: Vulkan, Metal, DX12, WebGPU. The
  seam, not any single backend, is the contract.** (Ratified 2026-06-13; replaces v1 INV-2.1
  "One GPU backend: Vulkan.")
  Rationale: macOS has no first-class Vulkan and Web has none; Windows benefits from a native
  DX12 path. The seam the v1 rule deferred is now required and implemented (`GpuBackend`,
  module 10, RJ0). All backends consume the identical `DrawCommand` list (INV-2.3, now
  load-bearing) and implement the same fragment-mode table. A backend may NOT add a
  draw-command variant or shader mode for its own convenience; new visual primitives go in the
  shared vocabulary or not at all. Exactly one backend is selected at build time per target
  (`-Dgpu`); no runtime backend switching. `VulkanBackend` is the reference implementation
  (RJ1).

- **INV-2.2 — Windowing, input, and the Vulkan surface come from GLFW.**
  Rationale: Solved, boring, cross-platform. Do NOT write a custom windowing or OS-event
  layer. Bind GLFW via `@cImport`.

- **INV-2.3 — The renderer consumes a flat draw-command list, nothing else.**
  Rationale: The renderer does not know about widgets, layout, or state. It receives a
  serialized list of draw commands once per frame and submits it. Keep this boundary clean.
  > **Addendum (AGENT AMENDMENT 2026-06-14: SR-04 — stable builder seam).** The
  > draw-list builder and the `GpuBackend` seam present a stable signature.
  > Backend- and rendering-quality-specific inputs (subpixel atlas, SDF atlas,
  > subpixel flag, future atlases) are passed via a single params/context value
  > (`DrawListParams`), never by widening positional parameters. A new visual
  > primitive goes into the shared `DrawCommand` vocabulary (INV-2.1-v2), not
  > into the builder signature. `buildDrawList` takes two fixed arguments
  > (`alloc`, `scene`) plus `DrawListParams`; adding a new atlas is a field
  > addition with a default, requiring zero call-site edits. Enacted under the
  > AAP (§8).

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

- **INV-4.2-v2 — Styling supports a bounded CSS cascade: type/class/id/descendant selectors,
  specificity ordering, and a fixed inheritance set. No `@media`/`@supports`, no sibling
  combinators, no `!important`.** (Ratified 2026-06-13; replaces v1 INV-4.2 "Tailwind utility
  semantics, NOT the CSS cascade.")
  Rationale: A flat utility model cannot express component-library theming, descendant
  styling, or shared rule sets. v2 adds a cascade engine (module 12, RL0–RL3) that resolves
  rules at **build time** into the same `ComputedStyle` the renderer already consumes — the
  cascade is a compile-time concern, preserving INV-4.4 (no parser in the production binary)
  and the runtime data-oriented model. The Tailwind-subset resolver is NOT removed: utility
  classes are the class-specificity tier and continue to work. Inheritance is limited to a
  closed six-property set (RL2). Do NOT implement `@media`, sibling combinators, pseudo-
  elements, or `!important` (rejected at build time). Utility-only screens are guaranteed
  unchanged (RL3).

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

- **INV-5.3 — A frozen `acceptance_test.zig` is amendable, but only via the
  contract-amendment procedure.** (AGENT AMENDMENT 2026-06-14 via AAP §8: written into
  the constitution body — was previously phantom, enforced only via `CLAUDE.md`. Source
  requirement: SR-06, `docs/requirements/M0_STABILIZATION.md`.)
  Rationale: The old "never modify `acceptance_test.zig`" rule was absolute, and it was
  never written into this file (§5 skipped from INV-5.2 to INV-5.4) — yet it was enforced
  via `CLAUDE.md` and agent notes. That phantom absolute froze the only repair available
  when a contract evolves, leaving no legal move and causing repeated one-off exceptions
  (Zig-0.16, R54, R60, RJ1). The rule is now written here **as a procedure**, not an
  absolute freeze:
  - A frozen `acceptance_test.zig` may be changed **only** in the same reviewed change
    as the `types.zig` signature it verifies.
  - It may be changed **only** to keep call sites matching the new contract (argument
    shapes, new parameters with defaults) — **never** to weaken an assertion or lower a
    bar.
  - The change must be recorded: either as an `(AGENT AMENDMENT …)` marker in the test
    file header or in a row of `docs/specs/AMENDMENTS_LOG.md`, citing the `types.zig`
    change it follows.
  - A bare test edit with no corresponding contract change remains forbidden.
  This dissolves the M20-class deadlock: when a contract evolves, the test follows it as
  a matter of procedure, not exception. See §8 (AAP), step 2.

- **INV-5.4 — Respect declared non-goals.**
  Rationale: Each spec lists non-goals. Do NOT implement them, even if they seem helpful or
  trivial. Scope creep across many sessions is the primary failure mode of this pipeline.
  > **Addendum (AGENT AMENDMENT 2026-06-15: RN-AAP-01 — "post-vN" non-goals are superseded
  > by explicit new requirements).** A spec's non-goal labelled "post-v1" or "post-v2" is a
  > *deferral*, not a permanent prohibition. When a later human-authored requirement document
  > explicitly targets that item for a named milestone, the deferral is superseded and the
  > requirement takes precedence over the old spec's non-goal list. The implementer MUST
  > update the original spec's non-goal section when implementing the superseding requirement.
  > Enacted to resolve the conflict between RE0's "No currency formatting" non-goal and the
  > explicit RN4 requirement in RN0 (M27 milestone). Enacted under the AAP (§8).

- **INV-5.5 — Every term comes from `glossary.md`. Do not invent synonyms.**
  Rationale: "Element", "RenderObject", "signal", "token" have exact meanings. Using a term
  loosely, or coining a new word for an existing concept, causes drift across sessions. If a
  needed concept has no glossary term, add one to `glossary.md` rather than improvising.

- **INV-5.6 — No dependencies beyond the approved list.**
  Rationale: Approved native deps for v1: GLFW, the Vulkan loader, the Zig standard
  library, stb_truetype (single-header, public domain; used by module 02 for glyph
  rasterization), and libdbus (Linux D-Bus client library for AT-SPI2 accessibility bridge;
  M17 approved on 2026-06-13). Approved build-time tools: glslc (from the Vulkan SDK, for
  GLSL→SPIR-V compilation). Do NOT add a package, vendored library, or build-time tool
  without an explicit human decision recorded here. (Taffy is being *ported*, i.e.
  reimplemented in Zig, not added as a dependency — see `specs/04_layout_engine/`.
  NOTE (2026-06-13): Pure-Zig vendored regex engine approved for M18-01 pattern validation
  (RH1). No external C library; implementation shall use only Zig std.
  NOTE (2026-06-13, V2 ratification): The following are approved for v2 (modules 10–13). Each
  must be pinned to a specific version and fetched reproducibly via `build.zig.zon`:
    • HarfBuzz (C, MIT) — text shaping, RK0.
    • Bidirectional algorithm — **pure-Zig UBA port** (owner-selected over SheenBidi), RK1.
      No external C library; Zig std only.
    • Metal / Metal-cpp headers (Apple SDK) — macOS backend, RJ2. System framework only.
    • D3D12 / DXGI headers (Windows SDK) — Windows backend, RJ3. System headers only.
    • WebGPU — **wgpu-native** (Rust→C ABI, MPL; owner-selected over Dawn) for the native
      path; the browser uses built-in `navigator.gpu`. RJ4.
  Approved build-time tools for v2: the Metal shader compiler (metallib), `dxc` (DXIL), and
  WGSL handled by the WebGPU toolchain — analogues of glslc, one per backend.
  Still forbidden without a further override: any font-discovery/fontconfig
  dependency (the app ships its own fonts), any CSS-parsing C library (the cascade parser is
  build-time Zig, RL0), and any charting library (charts use the native draw-command
  vocabulary, RM0). The auto-update deferral (§6) is superseded by AAP-M19 (2026-06-14).
  NOTE (2026-06-14, AGENT AMENDMENT via AAP §8 — AAP-M19): The following are approved for
  M19-01 through M19-04 (auto-update pipeline):
    • `std.http` (Zig standard library HTTP client — already in Zig std; no new package, no
      external C library). Requires an `std.Io` handle at call sites.
    • Vendored pure-Zig bsdiff/bspatch implementation (`src/tools/bspatch.zig`) — no external
      C library, no package manager entry; the file is authored in this repository and uses
      only Zig std. The variant implemented is BSDFRAW1 (uncompressed blocks, no bzip2).
  These approvals unblock M19-01–04 which were deferred solely by this invariant. Both
  additions are zero-new-package: `std.http` is part of the already-approved Zig standard
  library; bspatch is vendored source code in `src/tools/`.)

- **INV-5.7 — `src/` is the sole compilation source.** (AGENT AMENDMENT 2026-06-14 via AAP §8)
  No production or test target imports from `docs/`. `docs/specs/*.types.zig` files are
  non-compiled descriptions or generated mirrors — never hand-edited compilation inputs.
  Rationale: SR-03 (2026-06-14) moved canonical implementations for modules 03, 04, 05, 06
  from `docs/specs/NN.types.zig` into `src/NN/types.zig`. All module roots in `build.zig`
  and all test/app files must import from `src/`. The `docs/specs/*.types.zig` files carry
  a "GENERATED MIRROR" header and are never compiled.

---

## 6. M19 Scope Decision (2026-06-13 / amended 2026-06-14)

**AMENDED 2026-06-14 (AGENT AMENDMENT via AAP §8 — AAP-M19):** M19-01 through M19-04
(auto-update pipeline) are now unblocked. The deferral below is superseded.
INV-5.6 has been extended (see above) to approve `std.http` and a vendored pure-Zig bspatch.

~~**NOTE:** M19-01 through M19-04 (auto-update pipeline) deferred to post-v1 pending approval of
HTTP client and bsdiff library. Only M19-05 (app installer/packaging) implemented in v1.~~

~~Reason: Auto-update requires external network stack (HTTP) + complex binary patching (bsdiff),
neither approved (INV-5.6). Vendoring both would delay v1 release. App packaging (RI5) is
independent, uses only Zig std, and ships with zero new dependencies.~~

---

## 7. Build order (dependency chain)

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
10  gpu_backend (v2)                 — GpuBackend seam; Vulkan/Metal/DX12/WebGPU; surface layer (RJ0–RJ5)
11  text_shaping (v2)                — HarfBuzz shaping + Unicode bidi reordering (RK0–RK3)
12  cascade (v2)                     — build-time selector + specificity + inheritance resolver (RL0–RL3)
13  charts (v2)                      — chart-command vocabulary, scales/axes, chart components (RM0–RM3)
```

Modules 10–13 were added by the V2 ratification (2026-06-13); each depends only on
lower-numbered modules (10→01/09, 11→02/04, 12→05/06, 13→04/09). Anything not in this list
(auto-update/CDN delivery, mobile targets, additional chart types beyond RM2) remains post-v2
and must not be started without a human decision.

NOTE (2026-06-03, human override): DataTable (M7-10) and row virtualization are
approved for Milestone 7. See R79_data_table.md. This overrides the post-v1
classification.

**Green-build gate** (AGENT AMENDMENT 2026-06-14 via AAP §8: added as the mechanical
check that "done" cannot diverge from a passing build. Source requirement: SR-06,
`docs/requirements/M0_STABILIZATION.md`.) No module may carry `done`, and no new
milestone may start, while `zig build test` fails for any supported `-Dgpu` target.
The aggregate `test` step in `build.zig` runs every module's acceptance + unit tests
across each `-Dgpu` backend declared in the build, and is the gate this rule
references. If the gate is red, the only allowed work is fixing it (under the issue
resolution workflow); feature work on later modules is blocked until green.

---

## 7. When in doubt

1. Re-read the relevant invariant above.
2. Check `glossary.md` for the exact meaning of any term.
3. Check the module's `types.zig` for the exact contract.
4. If the rules are still ambiguous, contradictory, absent, or block correct work: **apply the
   Autonomous Amendment Procedure (§8)** — draft the fix, amend this file, log it, and continue
   in the same pass. Do NOT stop and surface a constitution question to the owner, and do NOT
   write an `_escalation.md` for a constitution matter. Escalation files are reserved for
   blockers that no amendment can resolve (e.g. a missing external resource the agent cannot
   obtain). Guessing silently is still forbidden — record the decision as an amendment.

---

## 8. Autonomous Amendment Procedure (AAP)

Agents amend this constitution themselves. They do **not** ask the owner for ratification and do
**not** escalate constitution matters. This section is binding (ratified by the project owner,
2026-06-14) and replaces the prior "stop and surface the conflict to the human" model for all
constitution questions.

**When the AAP applies.** Any time a task cannot proceed under the rules as written, including:
a task instruction that contradicts an invariant; an invariant that is ambiguous, contradictory,
or absent ("phantom"); a frozen contract (`types.zig` signature + its `acceptance_test.zig`)
that must evolve; a needed new dependency, build tool, or target platform; or any other rule
that blocks correct work.

**Procedure — single pass, no review gate (no extra ceremony):**

1. **Draft.** Write the exact change: `old text → new text`, or the new invariant. Prefer
   replacing a guardrail with a successor that keeps its discipline at the new scope; delete a
   guardrail outright only when the guardrail itself is the blocker.
2. **Apply.** Edit `00_constitution.md` inline. When replacing an existing invariant, use the
   established `-vN` successor convention and leave the predecessor's number resolvable. Mark
   every change with `(AGENT AMENDMENT YYYY-MM-DD: <one-line reason>)`.
3. **Log.** Append one row to `docs/specs/AMENDMENTS_LOG.md` (date · agent/role · invariant or
   section touched · old→new summary · reason · task/run id). This is the only required record.
4. **Glossary.** If the amendment introduces a new term, add it to `glossary.md` (INV-5.5).
5. **Resume.** Continue the original task in the same pass.

No second-agent review, approval quorum, or owner sign-off is required. Any single agent that
encounters the blocker performs all five steps.

**Authority & reversibility.** A human override still outranks any agent amendment, but it is
asynchronous: the owner reviews `AMENDMENTS_LOG.md` and git history at their convenience and may
revert or revise any amendment. Agents never wait on this.

**Entrenched clause (the one rule the AAP keeps over itself).** The AAP and the requirement to
append a log row for every amendment remain in force. They may themselves be amended — but any
change to them is itself an amendment recorded under step 3. The system may relax any rule; it
may not do so silently.

