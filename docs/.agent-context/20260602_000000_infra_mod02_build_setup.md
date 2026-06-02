# Infra change summary — Module 02 build infrastructure
**Date:** 2026-06-02
**Agent:** Infra

## What was done

Set up all build infrastructure for module 02 (Text / stb_truetype).  No module
logic code was modified.

### Files created

| Path | Description |
|---|---|
| `deps/stb_truetype.h` | Declarations-only stub header — provides `stbtt_fontinfo` and all function prototypes needed for `@cImport` to parse cleanly.  **Must be replaced** with the real header from https://github.com/nothings/stb before implementing Font methods. |
| `deps/stb_impl.c` | Single-header implementation translation unit: `#define STB_TRUETYPE_IMPLEMENTATION` then `#include "stb_truetype.h"`.  Compiles cleanly against the stub; produces the real implementations once the real header is in place. |
| `deps/README.md` | Developer instructions for replacing the stub with the real stb_truetype.h. |
| `src/02/types.zig` | Verbatim copy of `docs/specs/02.types.zig` (the contract).  Contains `@compileError` stubs — the implementer replaces these per spec.md. |
| `src/02/testdata/README.md` | Instructions for placing `DejaVuSans.ttf` to enable font-dependent acceptance tests. |

### Files modified

| Path | Change |
|---|---|
| `build.zig` | Added module 02 block (see below). |

### build.zig additions (module 02 block)

```zig
const mod02 = b.addModule("text", .{
    .root_source_file = b.path("src/02/types.zig"),
    .target = target,
    .optimize = optimize,
});
mod02.addIncludePath(b.path("deps"));
mod02.addCSourceFile(.{ .file = b.path("deps/stb_impl.c"), .flags = &.{} });
mod02.link_libc = true;

const accept02_mod = b.createModule(.{ .root_source_file = b.path("docs/specs/02.acceptance_test.zig"), ... });
accept02_mod.addImport("types.zig", mod02);
const accept02 = b.addTest(.{ .name = "02-acceptance-test", .root_module = accept02_mod });
const run_accept02 = b.addRunArtifact(accept02);
const accept02_step = b.step("test-02", "Run module 02 acceptance tests");
accept02_step.dependOn(&run_accept02.step);
```

### Key deviation from task template

The task template included `b.default_step.dependOn(&accept02.step)`.  This line was
**intentionally omitted** because `src/02/types.zig` currently contains `@compileError`
stubs (the contract, not the implementation).  Adding the acceptance test to the default
step would make `zig build` fail for everyone until the implementer fills in all stubs —
breaking module 01's CI guarantees.

**After the implementer replaces the stubs**, the following line should be added to
`build.zig` (in the module 02 block, after `const accept02 = ...`):

```zig
b.default_step.dependOn(&accept02.step);
```

## Validation

- `zig build` (default step) → **succeeds** with no output after these changes.
- Module 01 smoke + unit test compile steps are unaffected.
- Named step `zig build test-02` is available but will fail to compile until the
  implementer replaces the `@compileError` stubs in `src/02/types.zig`.

## Manual steps for the implementer

1. Replace `deps/stb_truetype.h` with the real header:
   ```powershell
   curl -L -o deps\stb_truetype.h https://raw.githubusercontent.com/nothings/stb/master/stb_truetype.h
   ```
2. Place `DejaVuSans.ttf` (or equivalent TTF with Cyrillic + kern table) at
   `src/02/testdata/DejaVuSans.ttf`.
3. Implement `src/02/types.zig` (replace `@compileError` stubs per `docs/specs/02.spec.md`).
4. Add `b.default_step.dependOn(&accept02.step);` to `build.zig` once the stubs are filled.
5. Run `zig build test-02` — all pure tests must pass; font tests must pass with the TTF.
6. Tick `docs/specs/02.checklist.md` when done.

## Approved dependencies

No new dependencies were added beyond the approved list in INV-5.6.
stb_truetype was already approved by the spec.
