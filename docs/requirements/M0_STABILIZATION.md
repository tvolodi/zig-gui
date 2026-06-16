# Milestone S — Stabilization Gate (blocking, pre-v2)

> **Status:** `planned` — blocking gate. No unimplemented milestone (M20 backends RJ2–RJ4, M11
> shaping, M12 cascade, M13 charts) may start until SR-01…SR-08 are green.
> **Motivation:** `docs/specs/ARCHITECTURE_REVIEW.md` (defects D1–D8).
> **Read `00_constitution.md` before this file.** Three requirements here (SR-03, SR-04, SR-06)
> change invariants/process. Under the Autonomous Amendment Procedure (constitution §8) agents
> enact these themselves — amend `00_constitution.md`, log in `docs/specs/AMENDMENTS_LOG.md` —
> with no owner sign-off. The "Amends constitution" column flags which ones.
> **Authored:** 2026-06-14.

## How to use this milestone

Each requirement below is self-contained and follows the house format (Purpose / What to build /
Non-goals / Acceptance criteria / Dependencies). Implement them in ID order; the dependency
lines make the ordering explicit. The gate is complete when a single command —
`zig build test` — passes for every supported `-Dgpu` target and SR-08's audit is recorded.

| ID | Title | Severity | Depends on | Amends constitution |
|---|---|---|---|---|
| SR-01 | Finish the `usingnamespace` → explicit re-export migration | critical | — | no |
| SR-02 | Repair module 09 acceptance-test signature | critical | SR-01 | no |
| SR-03 | Make `src/` the single source of truth | high | SR-01, SR-02 | yes — add INV-5.7 (via AAP) |
| SR-04 | Stabilise the renderer/seam signature (`DrawListParams`) | high | SR-02 | yes — amend INV-2.3 (via AAP) |
| SR-05 | Rewrite `build.zig` as a descriptor-driven table | high | SR-03 | no |
| SR-06 | Contract-amendment procedure + green-build gate | critical | — | yes — write INV-5.3 + gate (via AAP) |
| SR-07 | Repository hygiene: remove path-mangled & stale files | low | — | no |
| SR-08 | Re-audit roadmap `done` flags against the passing suite | high | SR-01…SR-05 | no |

---

## SR-01 — Finish the `usingnamespace` → explicit re-export migration

**Severity:** critical (build is red). **Depends on:** none.

### Purpose
Zig 0.16 removed `usingnamespace`. Modules 03/05/06 were already migrated to explicit
re-export; **`src/04/types.zig:7` still uses `pub usingnamespace`**, so the build fails at
module 04 — the top of the layout dependency chain. Restore compilation.

### What to build
- In `src/04/types.zig`, replace the `usingnamespace` re-export with explicit re-exports of
  every public symbol from the canonical implementation, matching the already-migrated pattern
  in `src/03/types.zig`, `src/05/types.zig`, `src/06/types.zig`:
  ```zig
  const spec = @import("../../docs/specs/04.types.zig");
  pub const LayoutEngine = spec.LayoutEngine;
  pub const Style = spec.Style;
  // …one line per public symbol the module 04 contract exposes…
  ```
  (This is the minimal fix that unblocks the build. SR-03 then removes this stub entirely by
  making `src/` canonical — SR-01 is the fast green-build step, SR-03 is the structural fix.)
- Grep the whole tree for any remaining `usingnamespace` and confirm `src/04/types.zig` is the
  last occurrence in compiled source.

### Non-goals (INV-5.4)
- Do NOT relocate the implementation in this requirement — that is SR-03.
- Do NOT change any public signature — re-export the existing contract verbatim.

### Acceptance criteria
1. `grep -rn "usingnamespace" src` returns nothing.
2. `zig build -Dgpu=vulkan` proceeds past module 04 (it may still fail later on SR-02 errors —
   that is expected and handled by SR-02).
3. The re-exported symbol set of `src/04/types.zig` is identical to before the migration
   (no symbol added or dropped).

---

## SR-02 — Repair the module 09 acceptance-test signature

**Severity:** critical. **Depends on:** SR-01.

### Purpose
`docs/specs/09.acceptance_test.zig` calls `buildDrawList` with the old 6-argument shape followed
by stray `, null, false;` text (lines ~70, 94, 117, 158, 186, 283, 319), because RJ1 extended
the signature to 9 parameters (`subpixel_atlas`, `subpixel_text`, `sdf_atlas`). The test no
longer parses. Make the test compile and pass against the current contract.

> **Governance note:** updating these call sites is a contract-amendment action. It is permitted
> because the `types.zig` signature changed first (RJ1 AC1) and the test must follow the contract
> it verifies. It is enacted under the contract-amendment procedure (INV-5.3, formalised in
> SR-06) and recorded in `AMENDMENTS_LOG.md` — not escalated. If SR-04 lands first (recommended),
> update the test to the *stable* `DrawListParams` form instead of the 9-positional form, so this
> edit is done once.

### What to build
- Update every `buildDrawList` call in `docs/specs/09.acceptance_test.zig` to the current
  signature. If SR-04 is already merged, use `buildDrawList(alloc, &scene, params)` with a
  `DrawListParams` literal; otherwise pass the 9 positional arguments with
  `subpixel_atlas = null`, `subpixel_text = false`, `sdf_atlas = null` for the basic cases.
- Verify there are no other frozen tests calling the changed signature; if there are, update
  them in the same change.

### Non-goals
- Do NOT change `buildDrawList`'s behaviour or signature here (signature work is SR-04).
- Do NOT weaken any assertion to make the test pass.

### Acceptance criteria
1. `zig test docs/specs/09.acceptance_test.zig -Dgpu=vulkan` compiles and passes (GPU-only
   cases may skip when no GPU is present, per existing convention).
2. `zig build -Dgpu=vulkan` completes a clean build.
3. The change touches only call sites / argument values, not assertions, and is recorded in
   `AMENDMENTS_LOG.md`.

---

## SR-03 — Make `src/` the single source of truth

**Severity:** high. **Depends on:** SR-01, SR-02. **Amends constitution:** yes — adds INV-5.7, enacted via the AAP (§8).

### Purpose
Production targets currently import type definitions from the `docs/` tree, inconsistently:
modules 03/04/05/06 keep their canonical implementation in `docs/specs/NN.types.zig` with a
`src/NN/types.zig` re-export stub, while 01/02/07/08/09 are full implementations in `src/`.
Remove the inversion so the build never compiles out of `docs/`, and there is one rule for where
a module lives.

### New invariant (agent enacts via AAP — no owner sign-off)
> **INV-5.7:** `src/` is the sole compilation source. No production or test target
> imports from `docs/`. `docs/specs/*.types.zig` are non-compiled descriptions, or generated,
> clearly-marked mirrors — never hand-edited compilation inputs.

### What to build
For each of modules 03, 04, 05, 06:
1. Move the canonical implementation from `docs/specs/NN.types.zig` into `src/NN/types.zig`
   (replacing the re-export stub).
2. Relocate the acceptance test so it imports the module the normal way. Either move it to
   `src/NN/NN_acceptance_test.zig`, or keep it under `docs/specs/` but have it `@import` the
   `src/` module through a named build module — never the reverse.
3. Delete the now-empty `docs/specs/NN.types.zig`, or convert it to a generated mirror with a
   header comment stating it is generated and must not be hand-edited.
4. Update `build.zig` module roots to point at `src/NN/types.zig` for all modules uniformly.

### Non-goals
- Do NOT change any public signature during the move — this is a relocation, not a redesign.
- Do NOT introduce a codegen step for the mirrors unless trivial; a deletion is preferred.

### Acceptance criteria
1. `grep -rn "docs/specs" build.zig src` shows no compiled target importing `docs/`.
2. Every module's canonical `types.zig` lives under `src/NN/`.
3. `zig build test` passes for all supported `-Dgpu` targets after the move.
4. INV-5.7 (or equivalent) is recorded in `00_constitution.md` with an `(AGENT AMENDMENT …)`
   marker and a matching row in `docs/specs/AMENDMENTS_LOG.md`.

---

## SR-04 — Stabilise the renderer/seam signature (`DrawListParams`)

**Severity:** high. **Depends on:** SR-02. **Amends constitution:** yes — amends INV-2.3, enacted via the AAP (§8).

### Purpose
INV-2.3's intent is that the flat command list carries render data, not an ever-widening builder
signature. `buildDrawList` instead grew three positional parameters; each future backend or
quality feature re-breaks every call site and the frozen test (the mechanism behind the M20
blocker). Make the seam signature stable.

### Invariant amendment (agent enacts via AAP — no owner sign-off)
> **INV-2.3 (addendum):** The draw-list builder and the `GpuBackend` seam present a
> stable signature. Backend- and rendering-quality-specific inputs (subpixel atlas, SDF atlas,
> subpixel flag, future atlases) are passed via a single params/context value, never by widening
> positional parameters. A new visual primitive goes into the shared `DrawCommand` vocabulary
> (INV-2.1-v2), not into the builder signature.

### What to build
- Define `DrawListParams` (in module 09's `types.zig`) carrying the inputs `buildDrawList`
  currently takes positionally plus the three RJ1 additions:
  ```zig
  pub const DrawListParams = struct {
      atlas: *GlyphAtlas,
      image_atlas: *const ImageAtlas,
      font: *Font,
      tokens: Tokens,
      subpixel_atlas: ?*SubpixelAtlas = null,
      subpixel_text: bool = false,
      sdf_atlas: ?*const anyopaque = null,
  };
  pub fn buildDrawList(alloc: std.mem.Allocator, scene: *Scene, params: DrawListParams)
      error{OutOfMemory}![]DrawCommand
  ```
- Update all call sites (`src/app/app.zig`, demo, tests) to pass a `DrawListParams` literal.
- Confirm the `GpuBackend` interface methods (RJ0) likewise take struct/context inputs where a
  future backend feature would otherwise widen a signature.

### Non-goals
- Do NOT change draw-list *output* or `DrawCommand` shapes — output stays identical (INV-2.3).
- Do NOT add a backend-private parameter; shared vocabulary only.

### Acceptance criteria
1. `buildDrawList` has the stable two-fixed-args + `DrawListParams` shape; no positional
   render-input arguments remain.
2. Adding a hypothetical new atlas is a field addition with a default, requiring zero call-site
   edits — demonstrate with a no-op default field.
3. `zig build test` passes for all `-Dgpu` targets; draw-list output is byte-identical to
   pre-change for the demo screens (visual-regression suite green).
4. The INV-2.3 addendum is recorded in `00_constitution.md` with an `(AGENT AMENDMENT …)` marker
   and a matching row in `docs/specs/AMENDMENTS_LOG.md`.

---

## SR-05 — Rewrite `build.zig` as a descriptor-driven table

**Severity:** high. **Depends on:** SR-03.

### Purpose
`build.zig` is 1,746 lines of copy-pasted module/test declarations with filename-based module
names and a live name collision (`addModule("types.zig")` declared for both module 01 and 03).
Replace it with a declarative module table and a generation loop.

### What to build
- Define a `ModuleDesc` table, one entry per module/component:
  ```zig
  const ModuleDesc = struct {
      name: []const u8,        // unique logical name, e.g. "mod03_element_store" — never a filename
      root: []const u8,        // src path
      deps: []const []const u8,
      accept_test: ?[]const u8 = null,
      unit_test: ?[]const u8 = null,
      needs_gpu: bool = false,
  };
  const modules = [_]ModuleDesc{ … };
  ```
- Iterate the table to create each `b.addModule`, wire `deps` by name, and generate the
  per-module `test-NN` / `test-NN-unit` steps and an aggregate `test` step.
- Give every module a unique logical name; remove all `addModule("<file>.zig")` filename names.
- Define the `-Dgpu` `BackendKind` enum in a single location that both `build.zig` and source
  can reference without `build.zig` importing a `src/` module purely for its build configuration
  (e.g. a small `build_options.zig` or an enum duplicated with a compile-time assert of parity).

### Non-goals
- Do NOT change what gets built or any test's behaviour — this is a refactor of the build graph
  description only.
- Do NOT add new build options or targets.

### Acceptance criteria
1. `build.zig` is well under ~400 lines and contains no duplicated module/test boilerplate.
2. `grep -oE 'addModule\("[^"]+"' build.zig | sort | uniq -d` returns nothing (no collisions);
   no module name is a filename.
3. Every `test-NN`, `test-NN-unit`, and the aggregate `test` step that existed before still
   exists and passes for all `-Dgpu` targets.

---

## SR-06 — Contract-amendment procedure + green-build gate

**Severity:** critical (process). **Depends on:** none. **Amends constitution:** yes — writes INV-5.3 + green-build gate, enacted via the AAP (§8).

### Purpose
The "never modify `acceptance_test.zig`" rule (INV-5.3) forbade the only repair available when a
contract evolves, leaving the orchestrator with no legal move (the M20 deadlock) — and the same
conflict had been waved through as a "one-time exception" at least four times (Zig-0.16
escalation, R54, R60, RJ1/M20). Worse, **INV-5.3 was never written in `00_constitution.md`** (§5
defines 5.1, 5.2, 5.4, 5.5, 5.6 and skips 5.3), yet it was enforced via `CLAUDE.md` and
agent-context notes — a phantom rule.

The 2026-06-14 governance change already added the Autonomous Amendment Procedure (constitution
§8), which structurally dissolves the deadlock: a frozen contract is now changed by amending the
constitution, not by escalating. This requirement finishes the job: give INV-5.3 a real, written
home **as a procedure** (not an absolute freeze), and add the green-build gate so `done` cannot
diverge from a passing build.

### Process changes (agent enacts via AAP — no owner sign-off)
> **INV-5.3 (write it into the constitution, as a procedure — currently phantom):** A frozen
> `acceptance_test.zig` may be changed *only* in the same reviewed change as the `types.zig`
> signature it verifies, *only* to keep call sites matching the new contract (never to weaken
> assertions), and the change is recorded in `00_constitution.md` or an agent-context note. A
> bare test edit without a corresponding contract change remains forbidden. (This rule is cited
> throughout `CLAUDE.md` and agent notes but is absent from `00_constitution.md` §5 — it must be
> added there to be binding and amendable.)
>
> **Green-build gate (new process rule):** No module may carry `done`, and no new milestone may
> start, while `zig build test` fails for any supported `-Dgpu` target.

### What to build
- Add INV-5.3 (the contract-amendment procedure above) to `00_constitution.md` §5 — it is
  currently missing from the body — and record the green-build gate in §7, both with an
  `(AGENT AMENDMENT …)` marker and matching rows in `docs/specs/AMENDMENTS_LOG.md`.
- Add a CI/`build.zig` aggregate `test` step (if not produced by SR-05) that runs every
  module's tests across each `-Dgpu` target, so the gate is mechanically checkable.
- Update the agent workflow docs (`docs/agents/AGENT_WORKFLOWS.md`, `CLAUDE.md`) so the
  orchestrator's "never modify acceptance_test.zig" rule references the new procedure.

### Non-goals
- Do NOT loosen the contract beyond the stated procedure (no free-form test edits).

### Acceptance criteria
1. INV-5.3 (contract-amendment procedure) and the green-build gate both appear in
   `00_constitution.md` with an `(AGENT AMENDMENT …)` marker and matching `AMENDMENTS_LOG.md`
   rows; `grep -n "INV-5.3" docs/specs/00_constitution.md` now returns a hit in the body, not
   just in references.
2. `docs/agents/AGENT_WORKFLOWS.md` and `CLAUDE.md` reference the contract-amendment procedure
   instead of an absolute prohibition.
3. A documented, runnable command (`zig build test`) exercises every module across every
   `-Dgpu` target and is the gate referenced by the rule.

---

## SR-07 — Repository hygiene: remove path-mangled & stale files

**Severity:** low. **Depends on:** none.

### Purpose
Remove mangled-absolute-path files and stale artifacts that pollute build inputs and signal
unreliable path handling.

### What to build
- Delete the path-mangled files/dirs at the repo root:
  `C:Userstvolodevai-dalatest_type.zig`, `c:Userstvolodevai-dalatest_sb.zig`, and the
  `Userstvolodevai-dala.zig-cache/` directory.
- Delete stale spec artifacts: `docs/specs/04.types.zig.old` and
  `docs/specs/03.mnt.user-data.outputs.requirements.specs.04_layout_engine.types.zig`.
- Add `.gitignore` rules so mangled `C:*`/`c:*` filenames and stray `*.zig-cache` dirs cannot
  re-enter, and confirm `zig-cache`/`zig-out`/`.zig-cache` are ignored.

### Non-goals
- Do NOT delete any file that is referenced by `build.zig` or imported by source — verify with a
  grep before each deletion.

### Acceptance criteria
1. None of the listed files/dirs exist in the tree.
2. `git status` is clean of mangled-path entries and they are `.gitignore`d.
3. `zig build test` still passes after the deletions (nothing was load-bearing).

---

## SR-08 — Re-audit roadmap `done` flags against the passing suite

**Severity:** high. **Depends on:** SR-01…SR-05.

### Purpose
The roadmap marks M11–M17 `done` and module 09 `planned` while the build does not compile.
Re-derive status from the now-passing suite so `done` means what INV-5.2 says it means.

### What to build
- With a green `zig build test`, for every milestone/module currently flagged `done`, confirm
  its acceptance test and checklist actually pass; downgrade any that do not to `in-progress`
  with a one-line note of what fails.
- Correct module 09's status (it underpins everything marked done and must not be `planned` if
  its acceptance test passes).
- Record the audit result as an agent-context note (e.g.
  `docs/.agent-context/<date>_stabilization_audit.md`) and update `docs/ROADMAP.md`.

### Non-goals
- Do NOT implement missing features here — only correct the status and record gaps.

### Acceptance criteria
1. Every `done` flag in `docs/ROADMAP.md` corresponds to a passing acceptance test + ticked
   checklist; mismatches are downgraded and noted.
2. Module 09's status reflects reality.
3. The audit note exists and lists any milestone downgraded and why.

---

## Exit criteria for Milestone S (the gate)

The gate is passed — and v2 work may resume — only when **all** hold:

1. `zig build test` passes for every supported `-Dgpu` target.
2. No compiled target imports from `docs/` (SR-03).
3. `build.zig` has no name collisions and no filename module names (SR-05).
4. The contract-amendment procedure (INV-5.3) and green-build gate are recorded in
   `00_constitution.md` and `AMENDMENTS_LOG.md` (SR-06).
5. The roadmap `done` flags match the passing suite (SR-08).
