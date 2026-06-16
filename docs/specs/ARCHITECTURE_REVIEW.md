# Architecture Review & Target State

> **Status:** Review (analysis + recommendation). Authored 2026-06-14.
> **Scope:** Assessment of the current zig-gui architecture as built through M17/M19 and the
> in-flight M20 (v2 backend seam), with a corrected target state and the invariant/process
> changes required to reach it.
> **Companion:** the remediation work this review motivates is specified as implementable
> requirements in `docs/requirements/M0_STABILIZATION.md` (Milestone S — Stabilization Gate).
> **Authority:** This is a design document. It does not override `00_constitution.md`. Agents
> enact the invariant/process changes it recommends themselves, via the Autonomous Amendment
> Procedure (constitution §8); the owner audits the amendment log asynchronously.

---

## 1. Executive summary

The core architecture is sound and unusually disciplined. The data-oriented element store, the
single flat draw-command boundary, the one-mechanism reactivity model, and the build-time
codegen rule are the right load-bearing decisions, and the v2 "widen at three seams plus one
leaf" strategy is the correct low-risk way to grow them.

The problems are not in the core design. They are in **source-of-truth organisation, build
infrastructure, contract governance, and status integrity** — and they have compounded into a
concrete failure: **the project does not currently compile** (`src/04/types.zig` still uses
`usingnamespace`, removed in Zig 0.16; module 09's acceptance test has signature errors), while
the roadmap marks modules through M17 as `done`. The single most important conclusion of this
review is that **"done" is no longer trustworthy**, because the executable definition of done
(INV-5.2: acceptance test passes) cannot currently be satisfied by a build that fails.

The recommendation is to stop adding v2 surface, run a short **Stabilization Gate** that
restores a green build, fixes the source-of-truth and build-system defects, repairs the
contract-governance contradiction, and re-audits the roadmap against an actually-passing test
suite — and only then resume the unimplemented milestones.

---

## 2. What the architecture gets right (keep, do not disturb)

These decisions are working and must be preserved through all remediation. Any fix that would
change a row here is a signal to stop and surface a conflict, exactly as `V2_ARCHITECTURE.md` §6
already states.

- **Data-oriented core (INV-3.1–3.5).** Struct-of-arrays element store, generational handles
  instead of stored pointers, per-screen arena allocation. This avoids per-widget heap churn
  and use-after-realloc, and is the correct foundation for a GPU UI.
- **Single flat draw-command boundary (INV-2.3).** The renderer consumes a serialized
  `DrawCommand` list and nothing else. This is the project's best decision: it is precisely what
  makes the v2 four-backend seam tractable, and it is now load-bearing rather than incidental.
- **One reactivity mechanism (INV-3.3).** Signal → dirty bitset → linear scan, with no tree
  diffing and no competing observer/callback path. Refusing a second change-propagation path is
  the discipline most UI frameworks lose.
- **Build-time codegen, no runtime parser in production (INV-4.4).** Good for binary size and
  attack surface; correctly extended to the v2 cascade resolver.
- **The v2 seam strategy.** Plugging WebGPU/Metal/DX12 into the existing backend seam, shaping
  into the existing text chokepoint, and the cascade into `resolveClasses` — "fill the seam,
  don't re-cut the core" — is architecturally correct and low-risk.
- **Constitution-as-shared-memory.** A single binding invariants file for memoryless sessions is
  a sound governance pattern; the failures below are about its *completeness*, not the idea.

---

## 3. Defects (current state)

### D1 — Source-of-truth inversion, applied inconsistently (severity: high)
Production code imports type definitions from the `docs/` tree, and only for some modules.
Modules **03, 04, 05, 06** keep their canonical implementation in `docs/specs/NN.types.zig`;
`src/NN/types.zig` is a thin re-export stub. Modules **01, 02, 07, 08, 09** keep full
implementations in `src/` (3488, 848, 2727, 872, 2053 lines respectively). There is therefore
no single rule for "where does a module live," and the build compiles source out of a directory
named `docs`. The stated reason (so the acceptance tests under `docs/specs/` can resolve their
imports) is a build-graph problem being solved in the wrong place.

**Root cause:** the acceptance test, the contract (`types.zig`), and the implementation were all
allowed to live in `docs/specs/`, so "spec" and "source" became the same files for some modules
but not others.

### D2 — Build is red; `usingnamespace` removal not fully migrated (severity: critical)
Zig 0.16 removed `usingnamespace`. Modules 03/05/06 were migrated to explicit re-export
(`const spec = @import(...); pub const X = spec.X;`), but **`src/04/types.zig:7` still uses
`pub usingnamespace`**, so the build fails at module 04. This is the top of the dependency chain
for everything above it.

### D3 — Frozen-contract governance contradiction, on a *phantom* invariant (severity: critical, process)
The "never modify `acceptance_test.zig`" rule (INV-5.3) forbids the only repair available when a
contract evolves. RJ1 legitimately extended the `buildDrawList` signature (added
`subpixel_atlas`, `subpixel_text`, `sdf_atlas`), so module 09's frozen acceptance test now
contains stray-argument syntax errors and **cannot be repaired without violating the rule**. v2
inherently evolves signatures; there is no ritual for "a frozen contract must change," so the
orchestrator is correctly deadlocked (`docs/.agent-context/20260614_phase4_blocker.md`) — the
rules as written have no legal move.

Two aggravating facts surfaced during this review:

- **INV-5.3 is not actually in the constitution.** `00_constitution.md` §5 defines INV-5.1, 5.2,
  5.4, 5.5, 5.6 — it skips 5.3 entirely. Yet INV-5.3 is treated as binding in `CLAUDE.md`
  ("never modify `acceptance_test.zig`") and is cited as a frozen-file rule in at least nine
  agent-context notes. The project's most disruptive rule exists only by convention; the
  shared-memory file that is supposed to be the single source of binding rules does not contain
  it. This is itself a governance defect: a phantom invariant cannot be amended, because there is
  nothing written to amend.
- **The same conflict has recurred at least four times** — the Zig-0.16 `fs.cwd` escalation
  (2026-06-02), R54 (module 06 signature), R60 (test-07/test-09), and now RJ1/M20 — each time
  resolved ad hoc as a "one-time exception." A rule that needs a one-time exception on every
  signature change is mis-specified, not occasionally inconvenient.

### D4 — `build.zig` is unmaintainable and has a name collision (severity: high)
`build.zig` is 1,746 lines of hand-written, copy-pasted module + test-step declarations. Module
names are often filenames (`addModule("events.zig")`, `addModule("window_state.zig")`), and
**`addModule("types.zig")` is declared twice** (modules 01 and 03) — the last two commits are
explicitly "partial resolution of module aliasing," i.e. the collision is still live. The build
graph is also coupled to source: `build.zig` imports `src/10/types.zig` at configuration time to
read the `BackendKind` enum for the `-Dgpu` option.

### D5 — Renderer seam signature is eroding (severity: medium, design drift)
The whole point of INV-2.3 is that the *flat command list* carries render data, not the builder
signature. `buildDrawList` instead grew three positional parameters. Each new backend feature
that widens this signature re-breaks every call site and the frozen test (this is the mechanism
behind D3). The seam should be stable; the data should move through the command list / a single
params struct.

### D6 — Status integrity: "done" diverges from the executable definition (severity: high)
The roadmap marks M11–M17 (input, layout extensions, rendering quality, animation, i18n,
platform integration, accessibility) as `done`, and even module 09 (the renderer they all sit
on) is listed `planned`, while the build does not compile. INV-5.2 defines done as "acceptance
test passes." A failing build means no downstream `done` flag can currently be substantiated.

### D7 — Repository hygiene / path-mangling artifacts (severity: low, signal: medium)
The tree contains files that are mangled Windows absolute paths used as filenames —
`C:Userstvolodevai-dalatest_type.zig`, `c:Userstvolodevai-dalatest_sb.zig`, a
`Userstvolodevai-dala.zig-cache/` directory — plus `docs/specs/04.types.zig.old` and
`docs/specs/03.mnt.user-data.outputs.requirements.specs.04_layout_engine.types.zig`. Harmless
individually, but they pollute the build inputs and indicate the agent file-path handling is
unreliable on Windows.

### D8 — Scope vs. INV-1.1 (severity: medium, strategic)
INV-1.1 declares an owner-only audience and "simplest correct design, no flexibility for its own
sake." The realised surface is four GPU backends, HarfBuzz plus a hand-ported Unicode bidi
algorithm, a CSS cascade, a charting vocabulary, AT-SPI *and* UIA accessibility bridges, and an
installer. Each is individually justified, but collectively this is multi-team scope sitting on
a foundation that currently cannot compile. This is a risk to call out, not a defect to fix by
deletion.

---

## 4. Target state

### 4.1 Single source of truth: `src/` is canonical
All module implementations and their `types.zig` contracts live under `src/NN/`. The `docs/`
tree describes and specifies; it is never a compilation input. Acceptance tests move to a
location that imports the module the normal way (e.g. `src/NN/NN_acceptance_test.zig`, or kept
under `docs/specs/` but importing the `src/` module through a named build module, never the
reverse). `docs/specs/NN.types.zig` either disappears or becomes a generated, clearly-marked
mirror — not a hand-edited source. Re-export stubs are deleted, not "fixed."

### 4.2 Stable renderer seam
The `GpuBackend` seam and the draw-list builder expose a **stable signature**. Backend- and
quality-specific inputs (subpixel atlas, SDF atlas, subpixel flag, future atlases) travel inside
a single `DrawListParams`/context struct or the command list itself, so adding a backend feature
does not re-break every call site or the frozen contract. This is the structural form of INV-2.3.

### 4.3 Data-driven build
`build.zig` is driven by a declarative module-descriptor table (id, root path, deps, test
files, GPU-dependence flag), with build modules and test steps generated by iterating that
table. Module names are unique logical names (`mod03_element_store`), never filenames. The
`-Dgpu` enum is defined in one place both `build.zig` and the source can read without `build.zig`
importing a source module for its configuration. Target: well under ~400 lines and zero name
collisions.

### 4.4 A defined contract-amendment procedure
The constitution gains an explicit, dated ritual for evolving a frozen contract
(`types.zig` signature and the matching `acceptance_test.zig` call sites): the signature and its
test change in the *same* change, never weakening an assertion, recorded as an amendment. This
replaces the current unresolvable INV-5.3 absolute. Combined with 4.2, signature churn becomes
rare *and* legal instead of frequent *and* forbidden.

### 4.5 Green-build gate and honest status
A single `zig build test` (or per-target `test-all -Dgpu=<t>`) must pass for every supported
backend before any module may carry `done`. The roadmap's status column is re-derived from that
suite, not asserted. No new milestone starts while the gate is red.

### 4.6 Clean tree
Path-mangled files, `.old` files, and stray caches are removed and `.gitignore`d so they cannot
re-enter.

---

## 5. The seam contract, restated (target diagram)

```
                 STABLE BOUNDARIES (the contract)
  app / screens
       |  builds Scene (widgets -> elements -> render objects)   -- INV-3.1..3.5 (unchanged)
       v
  buildDrawList(scene, params: DrawListParams) -> []DrawCommand   -- INV-2.3 (signature stable)
       |  flat, backend-agnostic command list
       v
  GpuBackend (one Zig interface)                                  -- INV-2.1-v2
       |-- VulkanBackend   (reference, RJ1)
       |-- MetalBackend    (RJ2)
       |-- DX12Backend     (RJ3)
       +-- WebGPUBackend   (RJ4)
            shaders differ; fragment-mode table identical         -- RJ0 shader-mode parity
```

The only data crossing the seam is the command list plus atlas handles. Everything
backend- or quality-specific is inside `DrawListParams`, so the seam signature does not move
when a backend or a rendering-quality feature is added.

---

## 6. Required invariant / process changes

> **Governance note (2026-06-14):** the constitution now carries an Autonomous Amendment
> Procedure (§8). Agents enact the changes below **themselves** — drafting the amendment,
> applying it to `00_constitution.md`, and logging it in `docs/specs/AMENDMENTS_LOG.md` — without
> owner ratification. The owner audits the log asynchronously and may revert. The items below are
> therefore the amendments agents should make as part of the Stabilization Gate, not requests
> awaiting sign-off.

1. **New INV (source of truth):** "`src/` is the sole compilation source. No production target
   imports from `docs/`. `docs/specs/*.types.zig` are non-compiled descriptions or generated
   mirrors." — addresses D1.
2. **Amend INV-2.3 / INV-2.1-v2:** "The draw-list builder and `GpuBackend` seam present a stable
   signature; backend- and quality-specific inputs are passed via a single params/context
   value, never by widening positional parameters." — addresses D5.
3. **Write INV-5.3 into the constitution as a contract-amendment procedure (it is currently a
   phantom).** First, the rule must actually exist in `00_constitution.md` §5. Second, it should
   be stated not as an absolute freeze but as a procedure: a frozen `acceptance_test.zig` may
   change only together with the `types.zig` signature it verifies, in one reviewed change,
   recorded in the amendment log, and never to weaken assertions. — addresses D3.
4. **New process rule (green-build gate):** "No module is `done`, and no new milestone starts,
   while `zig build test` fails for any supported `-Dgpu` target." — addresses D6.

---

## 7. Recommended sequence

Do these in order; each unblocks the next. They are specified as implementable requirements in
`docs/requirements/M0_STABILIZATION.md`.

1. **Restore a green build** (SR-01, SR-02) — the `usingnamespace` migration and the module 09
   acceptance-test signature. Nothing can be validated until this passes.
2. **Collapse the source-of-truth inversion** (SR-03) — make `src/` canonical, delete the
   re-export stubs, relocate tests.
3. **Stabilise the renderer seam** (SR-04) — `DrawListParams`, so D3-class churn cannot recur.
4. **Rewrite `build.zig` as a descriptor-driven table** (SR-05) — removes the boilerplate and
   the name collision.
5. **Enact the contract-amendment procedure and green-build gate** (SR-06).
6. **Clean the tree** (SR-07) and **re-audit roadmap `done` flags against the passing suite**
   (SR-08).

Only after SR-01…SR-08 are green should v2 resume (M20 backends RJ2–RJ4, M11 shaping, M12
cascade, M13 charts). Resuming earlier rebuilds on a base that cannot be validated.

---

## 8. Risk if not done

- Every new v2 module is written and "completed" against a suite that does not run, so defects
  accumulate invisibly (D2/D6).
- The next legitimate signature change re-deadlocks the orchestrator (D3) — until the AAP and a
  written INV-5.3 procedure are in place.
- `build.zig` grows another ~150 lines and another aliasing bug per module (D4).
- The `docs/`-as-source coupling makes the eventual migration larger the longer it waits (D1).

The stabilization milestone is small (the blocker itself estimates the build fixes at one
implementer cycle) relative to the cost of carrying these defects through four more modules.
