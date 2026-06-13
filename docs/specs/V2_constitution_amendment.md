# V2 — Constitution Amendment (RATIFIED 2026-06-13)

> **Status: RATIFIED 2026-06-13.** The project owner ratified this amendment on 2026-06-13.
> The changes below are now recorded in `00_constitution.md` (see its "V2 RATIFICATION"
> header): INV-1.2, INV-1.3, INV-2.1, and INV-4.2 are replaced by their `-v2` successors;
> INV-5.6 is extended with the v2 dependency list; modules 10–13 are added to §7. Recorded
> dependency choices: **WebGPU = wgpu-native**, **bidi = pure-Zig UBA port**.
>
> v2 work (modules 10–13, RJ/RK/RL/RM) is now unblocked. This file is retained as the rationale
> of record; `00_constitution.md` is binding where the two differ.

---

## 0. Why an amendment is needed

Every v2 candidate in the ROADMAP is blocked by a v1 scope invariant. v1 invariants were
written to keep the framework small, single-path, and shippable by independent AI sessions.
v2 deliberately widens the scope, so the invariants that encode "single path" must be
**replaced with new invariants that encode the new, wider — but still bounded — path.**

The danger in v2 is not "too small" but "unbounded." Lifting an invariant without replacing
it would delete the guard rail that kept sessions from drifting. Therefore every lifted
invariant below is **replaced**, not deleted, by a successor invariant with the same
discipline applied to the larger scope.

---

## 1. Invariants lifted and replaced

### INV-1.2 — Target platforms are Windows and Linux only → **replaced by INV-1.2-v2**

- **INV-1.2-v2 — Target platforms are Windows, Linux, macOS, and Web (WebGPU). Mobile is
  out of scope.**
  Rationale: macOS and Web are added because they are reachable through the backend seam
  (INV-2.1-v2) and GLFW's existing Cocoa support, with no change to the framework's
  data-oriented core. Mobile (iOS/Android) remains out of scope: it requires a touch-first
  interaction model, a different windowing/lifecycle model, and app-store packaging that the
  current architecture does not address. Do NOT add iOS, Android, or any mobile code path.
  Per-OS code remains confined to the platform-surface layer and the backend layer
  (see INV-2.2-v2); no platform `#ifdef` may leak into layout, style, element store, or
  components.

### INV-1.3 — No complex-script shaping → **replaced by INV-1.3-v2**

- **INV-1.3-v2 — Complex-script shaping is permitted via HarfBuzz; the text model gains a
  shaping stage and a bidirectional stage, and nothing else.**
  Rationale: Arabic, Indic, and CJK demand contextual glyph selection, ligatures,
  mark positioning, and bidirectional reordering that a kerning-only model cannot express.
  HarfBuzz is the industry-standard shaper and is added as an approved dependency
  (see §2). Bidirectional reordering follows the Unicode Bidirectional Algorithm (UBA).
  The shaping stage sits between line breaking and glyph rasterization; it does NOT change
  the glyph atlas, the draw-command vocabulary, or the renderer. Do NOT invent a custom
  shaper, and do NOT add line-layout features beyond shaping + bidi (e.g. no vertical
  writing modes, no justification-by-kashida) without a further override.

### INV-2.1 — One GPU backend: Vulkan → **replaced by INV-2.1-v2**

- **INV-2.1-v2 — Multiple GPU backends behind one seam: Vulkan, Metal, DX12, WebGPU. The
  seam, not any single backend, is the contract.**
  Rationale: macOS has no first-class Vulkan; Web has no Vulkan; Windows benefits from a
  native DX12 path. The seam that INV-2.1 (v1) explicitly *permitted but deferred* is now
  *required and implemented*. All backends consume the identical `DrawCommand` list
  (INV-2.3 is unchanged and now load-bearing) and implement one Zig interface
  (`GpuBackend`, see RJ0). A backend may NOT add a draw-command variant for its own
  convenience; new visual primitives are added to the shared vocabulary or not at all.
  Exactly one backend is selected at build time per target; no runtime backend switching.

### INV-4.2 — Tailwind utility semantics, NOT the CSS cascade → **replaced by INV-4.2-v2**

- **INV-4.2-v2 — Styling supports a bounded CSS cascade: type/class/id/descendant selectors,
  specificity ordering, and a fixed inheritance set. No `@media`/`@supports`, no
  pseudo-class combinatorics beyond the existing pseudo-states, no `!important` chains.**
  Rationale: A flat utility model cannot express component-library theming, descendant
  styling, or shared rule sets, which real applications need. v2 adds a cascade engine
  (RL0–RL3) that resolves rules at **build time** into the same `ComputedStyle` the renderer
  already consumes — the cascade is a *compile-time* concern, preserving INV-4.4 (no parser
  in the production binary) and the runtime data-oriented model. The Tailwind-subset
  resolver is NOT removed; utility classes become the highest-but-one specificity tier and
  continue to work. This is the one change that can break existing markup; RL3 defines the
  migration and a compatibility guarantee for utility-only screens.

---

## 2. Dependency additions (extends INV-5.6)

The following are approved for v2 **only upon ratification**. Each must be pinned to a
specific version and vendored or fetched reproducibly through `build.zig.zon`.

| Dependency | Used by | Why no alternative | License note |
|---|---|---|---|
| **HarfBuzz** (C library) | RK0 shaping | The de-facto text shaper; reimplementing shaping is infeasible and explicitly out of scope | MIT |
| **SheenBidi** *or* a vendored UBA implementation | RK1 bidi | Unicode Bidirectional Algorithm; SheenBidi is small, dependency-free C. A pure-Zig UBA port is acceptable if preferred | Apache-2.0 / port |
| **Metal / Metal-cpp headers** | RJ2 macOS backend | Apple's only modern GPU API; system framework, no third-party code | Apple SDK |
| **D3D12 / DXGI headers** | RJ3 Windows backend | System headers from the Windows SDK; no third-party code | Windows SDK |
| **Dawn** *or* **wgpu-native** (WebGPU) | RJ4 web/native-WebGPU backend | WebGPU implementation; Dawn (C++) or wgpu-native (Rust→C ABI). Choice recorded in RJ4 | BSD / MPL |

Items explicitly **still forbidden** without a further override: any HTTP client, any
font-discovery/fontconfig dependency (the app ships its own fonts), any CSS-parsing C
library (the cascade parser is build-time Zig, RL0), and any charting library (charts are
built on the native draw-command vocabulary, RM0). The auto-update deferral
(`00_constitution.md` §6) is unchanged.

---

## 3. Invariants that DO NOT change (and become more load-bearing)

These v1 invariants are reaffirmed for v2 and several carry more weight now:

- **INV-1.1 (owner-only audience, simplest correct design)** — unchanged. v2 adds scope, not
  configurability. Still no plugin systems or "for flexibility" options.
- **INV-2.3 (renderer consumes a flat draw-command list, nothing else)** — now the *single
  contract* every backend implements. Critical: it is what makes four backends tractable.
- **INV-3.1–INV-3.5 (data-oriented, generational handles, signal→dirty→scan, three trees,
  per-screen arena)** — unchanged and untouched by all v2 work. No v2 feature may introduce
  per-widget heap objects, pointer identity, or an alternative change-propagation path.
- **INV-4.1 (two binding mechanisms)** — unchanged.
- **INV-4.3 (four-layer token model)** — unchanged; the cascade (RL) resolves *into* the
  token model, it does not replace it.
- **INV-4.4 (static markup baked at build time; runtime parser dev-only)** — unchanged and
  extended to the cascade: the selector/cascade resolver runs at build-time codegen, never
  in the production binary.
- **INV-5.1, INV-5.2, INV-5.4, INV-5.5 (typed contracts, executable "done", non-goals,
  glossary)** — unchanged. Every new term in v2 must be added to `glossary.md`.

---

## 4. Ratification checklist (for the project owner)

To start v2, the owner copies the following into `00_constitution.md` with a dated override
line, choosing the dependency variants in §2:

1. Replace INV-1.2 text with INV-1.2-v2.
2. Replace INV-1.3 text with INV-1.3-v2 (keep the existing fallback-glyph paragraph).
3. Replace INV-2.1 text with INV-2.1-v2.
4. Replace INV-4.2 text with INV-4.2-v2.
5. Append the approved-dependency rows from §2 to INV-5.6, pinning versions and recording
   the Web (Dawn vs wgpu-native) and bidi (SheenBidi vs Zig port) choices.
6. Add the new build-order entries (modules 10–13, see `V2_ARCHITECTURE.md` §1) to §7.

Until all six are recorded, agents must treat v2 requirements as **blocked** and surface the
block rather than guess (per `00_constitution.md` §7 "When in doubt").
