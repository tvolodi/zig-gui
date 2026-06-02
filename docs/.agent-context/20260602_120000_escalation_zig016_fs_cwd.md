# Escalation — Orchestrator — 2026-06-02

## Workflow
Workflow 1 — Module 07 implementation, Step 5 (Run tests)

## Blocker
`docs/specs/07.acceptance_test.zig` (line 166) uses `std.fs.cwd()` which was removed in
Zig 0.16. The project is running Zig 0.16.0. The same issue affects
`docs/specs/02.acceptance_test.zig` (line 157).

In Zig 0.16, the API moved to `std.Io.Dir.cwd()` with a different signature — `openFile`
now requires an `io: Io` parameter. The old API is completely gone (not deprecated, removed).

The module 07 implementation (`src/07/types.zig`) itself compiles without errors. The
blocker is exclusively in the acceptance test file, which is frozen (INV-5.3).

## What was tried
1. Fixed the `ArrayListUnmanaged` init syntax (`.{}` → `.empty`, a different Zig 0.16 break)
   in `src/07/types.zig` — this resolved the implementation compile error.
2. Confirmed the remaining error is only `std.fs.cwd()` in the frozen acceptance test.
3. Confirmed the same issue pre-exists in module 02's acceptance test (not introduced by
   module 07 work).

## Decision needed from human
**Choose one:**

A. **Downgrade Zig** — install Zig 0.13.0 or 0.14.x (the version the specs were written
   against) and re-run. The acceptance tests were written for an earlier Zig release.

B. **Update the acceptance test files** — treat the `std.fs.cwd()` → `std.Io.Dir.cwd()` fix
   as a non-behavioral correction to keep the tests compilable on Zig 0.16. This would mean
   making a one-time exception to INV-5.3 for this mechanical API-compatibility update only.
   Behavioral assertions remain identical.

C. **Run tests via `zig test` directly** — bypass build.zig and run the pure (non-font) tests
   only by compiling with explicit path overrides. The font-dependent test (FONT: measurePass)
   would be skipped as designed, but the `std.fs.cwd()` call still compiles even if it doesn't
   run, so this doesn't resolve the compilation failure.

Option B is the minimal correct fix: only the file-open call in one test changes; all
behavioral assertions in the spec remain unchanged.

## Relevant files
- `docs/specs/07.acceptance_test.zig` (line 166) — `std.fs.cwd()` call
- `docs/specs/02.acceptance_test.zig` (line 157) — same issue, pre-existing
- `src/07/types.zig` — implementation, compiles cleanly
