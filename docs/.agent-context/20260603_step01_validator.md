---
from_agent: validator
to_agent: implementer
step_number: 1
status: PASS
module: M5
timestamp: 2026-06-03T00:00:00Z
---

## Summary

All seven Milestone 5 R-files (R50–R56) were validated against the constitution, glossary,
existing source files, and each other. No constitution violations were found. Nine glossary
terms were missing and have been added in-place to `docs/specs/glossary.md`. No inter-
requirement conflicts were found. Several existing-code findings require implementer attention
(detailed below).

---

## Constitution check

### INV-3.1 — No per-widget heap objects
All new arrays (`_hidden`, `_saved_display` in R52; children re-instantiation in R53) use
`std.ArrayListUnmanaged` stored on `Scene`, which is the correct parallel-array pattern.
`ListBinding.refresh_fn` re-instantiates via `scene.removeChildren` + `scene.instantiateUnder`
— no per-widget heap objects. **PASS.**

### INV-3.3 — Signal → dirty → scan
R52's `setHidden` marks the element dirty (`self.elements.dirty.set(idx)`). R53's
`ListBinding.refresh` calls `scene.elements.dirty.set(b.container_idx)` after re-instantiation.
`CondBinding.bindCond` calls `sig.subscribe(element_idx)` so the signal's `set()` will mark
the element dirty. The correct reactivity path is used throughout. **PASS.**

### INV-3.4 — Build order (no upward imports)
- R50 adds helpers to module 06 and calls them from module 07. 06 < 07. **OK.**
- R51 modifies module 03 (`LayoutNode`, `Display`) and module 04 (layout engine). Both are
  lower-numbered than 06/07 where they are consumed. **OK.**
- R52/R53 modify `src/app/binding.zig` (app layer) and `src/07/types.zig`. The app layer is
  above module 07, so `binding.zig` importing module 07 is legal (app layer already does this
  for `TextBinding`). **OK.**
- R54 modifies only module 06. **OK.**
- R55 creates `src/tools/ui_codegen.zig` which imports module 06. The codegen tool is a
  standalone build-time executable, not a module in the numbered chain; this does not violate
  build order. **OK.**
- R56 creates `src/app/file_watcher.zig` which uses only `std` (for `std.fs.File.stat()`).
  The `reloadFile` function in `app.zig` imports module 06 (`parse`) behind the `hot_reload`
  comptime gate. Module 06 is lower-numbered than the app layer. **OK.**

### INV-4.1 — Two binding mechanisms
R52 and R53 extend `BindingSet` with `CondBinding` and `ListBinding`. These follow the same
comptime-field-offset pattern as `TextBinding` (comptime `StateType` + `field_name` →
zero runtime path resolution). This is the correct static-screen binding lane. The `for=`
`item_instantiate_fn` is a comptime-provided closure, not runtime path resolution. **PASS.**

### INV-4.4 — No runtime parser in production
R56 gates all `parse` calls on `comptime hot_reload` from `build_options`. R55 runs `parse`
in a standalone build-time codegen tool, not in the app binary. The R54 signature change
(`parse` gains `diag: ?*ParseDiagnostic`) does not change the fact that `parse` is dev/
codegen-only in production. **PASS.**

### INV-5.6 — No new dependencies
- R50/R51/R52/R53/R54: pure Zig std, no new deps.
- R55: the codegen tool uses `std.process.argsAlloc`, `std.fs.cwd()`, `std.io` — all Zig std.
  No new external dependency.
- R56: `FileWatcher.poll()` uses `std.fs.File.stat()` — Zig std. The background-thread option
  is explicitly deferred (non-goal in R56). Main-thread mtime polling uses only Zig std. The
  R56 non-goals explicitly exclude inotify / ReadDirectoryChangesW. **PASS.**

---

## Glossary check

Terms added to `docs/specs/glossary.md` (nine new entries):

| Term | R-file | Status |
|---|---|---|
| `parseHexColor` | R50 | ADDED |
| `parseFloat` | R50 | ADDED |
| `AlignSelf` | R51 | ADDED |
| `MarginValue` | R51 | ADDED |
| `Margin` | R51 | ADDED |
| `CondBinding` | R52 | ADDED |
| `ListBinding` | R53 | ADDED |
| `SourceLoc` | R54 | ADDED |
| `ParseDiagnostic` | R54 | ADDED |
| `FileWatcher` | R56 | ADDED |
| `WatchEntry` | R56 | ADDED |

Terms confirmed already present:
- `BindingSet`, `TextBinding`, `Signal(T)`, `Computed(T)`, `dirty bitset scan`, `NodeDesc`,
  `Scene`, `ElementId`, `LayoutNode`, `ComputedStyle`, `PseudoState`, `CallbackFn` — all
  present.

---

## Dependency check

| R-file | Touches | Status |
|---|---|---|
| R50 | src/06/types.zig (parseHexColor, parseFloat), src/07/types.zig (applyInlineStyle), docs/specs/06.types.zig | OK — modules 06 and 07 only |
| R51 | src/03/types.zig (Display.none, AlignSelf, Margin/MarginValue), src/04/types.zig (solveBlock, solveFlex), src/06/types.zig (applyClass), docs/specs/03.types.zig | OK — modules 03, 04, 06 |
| R52 | src/07/types.zig (_hidden, _saved_display, setHidden, isHidden), src/app/binding.zig (CondBinding, bindCond), docs/specs/07.types.zig | OK — module 07 + app layer |
| R53 | src/07/types.zig (removeChildren, instantiateUnder), src/app/binding.zig (ListBinding, bindList), docs/specs/07.types.zig | OK — module 07 + app layer |
| R54 | src/06/types.zig (SourceLoc, ParseDiagnostic, parse signature), docs/specs/06.types.zig | OK — module 06 only |
| R55 | src/tools/ui_codegen.zig (NEW), build.zig (codegen step) | OK — build-time tool only; imports module 06 from the build side, not from app binary |
| R56 | src/app/file_watcher.zig (NEW), src/app/app.zig (watcher field + poll call), build.zig (hot_reload option, run-dev step) | OK — app layer + build; no new deps |

---

## Inter-requirement conflict check

### R54 changes `parse` signature — does R55 and R56 reference the new signature?

R54 changes `parse` from:
```zig
pub fn parse(allocator: Allocator, source: []const u8) ParseError!NodeDesc
```
to:
```zig
pub fn parse(allocator: Allocator, source: []const u8, diag: ?*ParseDiagnostic) error{ParseFailed,OutOfMemory}!NodeDesc
```

R55 (`ui_codegen.zig`) calls `parse(arena.allocator(), source, &diag)` — uses the new signature correctly.

R56 (`reloadFile`) calls `parse(arena.allocator(), source, &diag_val)` — uses the new signature correctly.

The existing `docs/specs/06.acceptance_test.zig` calls the old signature. R54 explicitly notes this file must be updated to pass `diag=null`. However, per INV-5.3, the acceptance test file is **frozen** (agents must not modify it). **This is a potential conflict**: R54 requires updating `06.acceptance_test.zig` but INV-5.3 forbids it.

**Resolution:** R54 says "All existing unit tests in `docs/specs/06.acceptance_test.zig`" need updating. This is a spec update (the test encodes the old signature as the contract). The implementer must surface this to the human before touching that file. The `src/06/06_test.zig` unit test file is mutable and should be updated normally. **This is a WARNING, not a blocker** — the human must decide whether to update the frozen acceptance test.

### R52 and R53 both extend `BindingSet.refresh()`

R52 extends `refresh(self, scene)` to also iterate `self.cond.items`.
R53 extends `refresh(self, scene, tokens)` — **gains a `tokens: Tokens` parameter**.

These are sequential extensions to the same function. The final signature must be:
```zig
pub fn refresh(self: *const BindingSet, scene: *Scene, tokens: Tokens) void
```

R52 shows `refresh(self, scene)` (no tokens). R53 then adds `tokens`. The implementer must apply R52's cond-binding extension AND R53's tokens parameter change together; the intermediate `refresh(self, scene)` signature from R52 is immediately superseded by R53. **No conflict if implemented in R52→R53 order** (or together). The implementer must not leave `refresh` with the R52 signature and forget R53's parameter addition.

Additionally, `src/app/app.zig` currently calls `self.bindings.refresh(&self.scene)` (line 402, `refreshBindings` function). After R53, this call site must become `self.bindings.refresh(&self.scene, self.tokens)`. The `tokens` field already exists on `AppInner`. **No blocker; just a required call-site update.**

### R51 changes `margin: Insets` → `margin: Margin` — does R52 use `LayoutNode.margin`?

R52's `setHidden` accesses `self.elements.layout.items[idx].display` only — not `.margin`. R52 does not touch `margin`. **No conflict.**

R51's `LayoutNode` change from `margin: Insets` to `margin: Margin` does require updating any existing code that accesses `node.margin.top` as a bare `f32`. The current `src/07/types.zig` and `src/03/types.zig` do not read `margin` fields directly (module 04 is where margin arithmetic lives). The implementer must survey `src/04/` for `margin.top/right/bottom/left` accesses and update them to use `MarginValue`.

### No other inter-requirement conflicts found.

---

## Existing code findings

### `src/06/types.zig` (via `docs/specs/06.types.zig`)
- `parseHexColor`: **NOT PRESENT** — must be added (R50).
- `parseFloat`: **NOT PRESENT** — must be added (R50).
- `ParseDiagnostic`: **NOT PRESENT** — must be added (R54).
- `SourceLoc`: **NOT PRESENT** — must be added (R54).
- `parse` signature: currently `pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParseError!NodeDesc` — must be updated to the new R54 signature.
- `Parser` struct: currently has no `line`/`column` fields — must be added (R54).
- `applyClass` in `resolveClasses`: `hidden` → `display = .none` is **NOT PRESENT** (the `Display` enum currently lacks `.none`). All Group A–G classes from R51 are **NOT PRESENT** in the current resolver.
- Note: `src/06/types.zig` is just a `pub usingnamespace` re-export of `docs/specs/06.types.zig`. All changes go in `docs/specs/06.types.zig`.

### `src/03/types.zig` (via `docs/specs/03.types.zig`)
- `Display` enum: currently `enum { block, flex, grid }` — `none` is **NOT PRESENT** (R51 needs it).
- `AlignSelf` enum: **NOT PRESENT** — must be added (R51).
- `MarginValue` union: **NOT PRESENT** — must be added (R51).
- `Margin` struct: **NOT PRESENT** — must be added (R51).
- `LayoutNode.align_self` field: **NOT PRESENT** — must be added (R51).
- `LayoutNode.margin` field: currently `margin: Insets` — must be changed to `margin: Margin` (R51).

### `src/04/types.zig` (via `docs/specs/04.types.zig`)
- Layout engine changes for `display = .none`, `mx-auto`, `align_self`, and `MarginValue.px` margins: **NOT PRESENT** — all must be added per R51.
- Note: `src/04/types.zig` is a re-export of `docs/specs/04.types.zig`.

### `src/07/types.zig`
- `_hidden` array: **NOT PRESENT** — must be added (R52).
- `_saved_display` array: **NOT PRESENT** — must be added (R52).
- `isHidden` method: **NOT PRESENT** — must be added (R52).
- `setHidden` method: **NOT PRESENT** — must be added (R52).
- `removeChildren` method: **NOT PRESENT** — must be added (R53).
- `instantiateUnder` method: **NOT PRESENT** — must be added (R53).
- Note: The **implementation** (`src/07/types.zig` as the real code) already has all prior R3x methods implemented. The **spec contract** (`docs/specs/07.types.zig`) has stubs. Both files need the new R52/R53 additions.

### `src/app/binding.zig`
- `CondBinding` struct: **NOT PRESENT** — must be added (R52).
- `BindingSet.cond` field: **NOT PRESENT** — must be added (R52).
- `BindingSet.bindCond` method: **NOT PRESENT** — must be added (R52).
- `ListBinding` struct: **NOT PRESENT** — must be added (R53).
- `BindingSet.list` field: **NOT PRESENT** — must be added (R53).
- `BindingSet.bindList` method: **NOT PRESENT** — must be added (R53).
- `BindingSet.refresh` signature: currently `refresh(self, scene)` — must gain `tokens: Tokens` parameter (R53) and apply both cond and list bindings.
- `BindingSet.deinit`: must be updated to also deinit `cond` and `list` arrays.

### `src/app/app.zig`
- No `watcher` field or `reloadFile` function: **NOT PRESENT** — must be added behind comptime `hot_reload` gate (R56).
- `refreshBindings` call site: `self.bindings.refresh(&self.scene)` → must become `self.bindings.refresh(&self.scene, self.tokens)` after R53 changes `refresh` signature.
- No `hot_reload` build option in `build.zig`: **NOT PRESENT** — must be added (R56).

### `build.zig`
- No `codegen` step: **NOT PRESENT** — must be added (R55).
- No `hot_reload` option: **NOT PRESENT** — must be added (R56).
- No `run-dev` step: **NOT PRESENT** — must be added (R56).
- `src/tools/` directory: likely does not exist — must be created for `ui_codegen.zig` (R55).
- `src/app/file_watcher.zig`: does not exist — must be created (R56).

---

## For next agent

Organized by R-file, in dependency order:

### R54 (do first — changes `parse` signature that R55 and R56 depend on)
- Modify `docs/specs/06.types.zig`: add `SourceLoc`, `ParseDiagnostic`; update `parse` signature; add `line`/`column` to `Parser`; update `consume()`, `expect()`, `readName()`, `skipWs()` to go through `consume()`; add `makeDiag` helper; update all `return ParseError.*` sites.
- Update `docs/specs/06.acceptance_test.zig`: **surface to human first** (INV-5.3 — frozen file). Human must authorize the signature update before implementer touches it.
- Update `src/06/06_test.zig` unit tests to pass `diag=null` where not testing diagnostics.

### R51 (do second — adds `Display.none` that R52 depends on)
- Modify `docs/specs/03.types.zig`: add `.none` to `Display`; add `AlignSelf`, `MarginValue`, `Margin`; add `align_self` field to `LayoutNode`; change `margin: Insets` to `margin: Margin`.
- Modify `docs/specs/04.types.zig`: add `display = .none` early-out in `solveNode`; add `mx-auto` logic in `solveBlock`; add `align_self` logic in `solveFlex`; handle `MarginValue.px` in margin arithmetic.
- Modify `docs/specs/06.types.zig`: add all Group A–G `applyClass` entries (hidden, overflow-hidden, min/max-w/h, w/h numeric, mx-auto, m/mx/my/mt/mr/mb/ml, shrink-0/grow-0/grow/shrink, self-*, col-span/row-span, and M4 classes if not already present).
- Survey `src/04/` for existing `margin.top/right/bottom/left` float accesses; update to `MarginValue`.

### R50 (after R51 — uses `ComputedStyle` which is unchanged, but good order)
- Modify `docs/specs/06.types.zig`: add `parseHexColor` and `parseFloat` public functions.
- Modify `src/07/types.zig` (implementation): add `applyInlineStyle` helper; call it in `instantiateNode` after class resolution.
- Add unit tests in `src/06/06_test.zig` for `parseHexColor` and `parseFloat`.
- Add scene instantiation tests in `src/07/07_test.zig` for inline style overrides.

### R52 (after R51 — depends on `Display.none`)
- Modify `docs/specs/07.types.zig`: add `_hidden`, `_saved_display` arrays; add `isHidden`, `setHidden` method signatures.
- Modify `src/07/types.zig`: add `_hidden`, `_saved_display` arrays; implement `isHidden`, `setHidden`; initialize/clear both arrays in `init`, `deinit`, `reset`; add `if=` attribute handling in `instantiateNode`.
- Modify `src/app/binding.zig`: add `CondBinding` struct; add `cond` field to `BindingSet`; implement `bindCond`; extend `refresh` to iterate `self.cond.items` (note: final `refresh` signature must include `tokens` per R53 — implement R52 and R53 together or leave a TODO).
- Update `BindingSet.deinit` to free `cond` array.
- Add tests in `src/app/binding_test.zig`.

### R53 (after R52 — extends R52's `BindingSet`)
- Modify `docs/specs/07.types.zig`: add `removeChildren`, `instantiateUnder` method signatures.
- Modify `src/07/types.zig`: implement `removeChildren` and `instantiateUnder`.
- Modify `src/app/binding.zig`: add `ListBinding` struct; add `list` field to `BindingSet`; implement `bindList`; change `refresh` signature to `refresh(self, scene, tokens: Tokens)`; extend `refresh` to handle list bindings.
- Update `BindingSet.deinit` to free `list` array.
- Modify `src/app/app.zig`: update `refreshBindings` to call `self.bindings.refresh(&self.scene, self.tokens)`.
- Add tests in `src/app/binding_test.zig`.

### R55 (after R54 — uses new `parse` signature)
- Create `src/tools/ui_codegen.zig` (standalone executable).
- Modify `build.zig`: add `codegen_exe`, enumerate `.ui` files, add `codegen` step.
- Create any `.ui` files needed for the round-trip acceptance test, or use existing ones.

### R56 (after R54 — uses new `parse` signature)
- Modify `build.zig`: add `hot_reload` option, `build_options` module, `run-dev` step.
- Create `src/app/file_watcher.zig` with `WatchEntry` and `FileWatcher`.
- Modify `src/app/app.zig`: add `watcher` field behind comptime gate; add `reloadFile` function; add `poll` call in `run()` loop; import `file_watcher.zig` conditionally.

---

## Issues

### WARNING (non-blocking) — R54 requests update to frozen acceptance test
R54 states: "All existing unit tests in `docs/specs/06.acceptance_test.zig`" must be updated to
pass `diag=null`. However, INV-5.3 forbids modifying `acceptance_test.zig` files. The human
must decide whether to authorize this change. Options:
1. Authorize the update (treat R54 as a spec revision that supersedes the old `parse` signature).
2. Keep the old `parse` signature internally and add a `parseWithDiag` wrapper instead.

**Recommended action:** Surface to human before implementing R54. Do not touch `docs/specs/06.acceptance_test.zig` without explicit human authorization.

### WARNING (non-blocking) — R53 `refresh` signature change requires `app.zig` update
`src/app/app.zig` line 402 calls `self.bindings.refresh(&self.scene)`. After R53, this must be
`self.bindings.refresh(&self.scene, self.tokens)`. The `tokens` field is already present on
`AppInner`. This is a mechanical one-line update but must not be forgotten.

### NOTE — R56 open question about `rebind_fn` hook
R56 explicitly asks: "Confirm this design with the human before implementing — the alternative
(no hook, documented as a known limitation) is simpler but less ergonomic." The implementer
must pause and confirm this design choice before implementing the App-level `rebind_fn` field.

### NOTE — R55 has no existing `.ui` files in `src/`
R55 references `src/screens/login.ui` and `src/screens/main.ui` as example paths. The
`src/screens/` directory does not currently exist. The implementer must either create stub `.ui`
files for the codegen round-trip test or clarify with the human what UI files exist.
