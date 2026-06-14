# RJ1 — M20-02: Vulkan backend conformance to the seam

> Roadmap item: M20-02
> Depends on: RJ0 (GpuBackend seam), 01 (VulkanBackend), 09 (renderer)
> Read `RJ0_gpu_backend_seam.md` before this file.

## Purpose

Refactor the existing `VulkanBackend` to *be* the reference implementation of the `GpuBackend`
contract (RJ0), with **zero observable behavior change**. This is a pure refactor: it proves
the seam is the contract, not Vulkan's incidental shape, and de-risks every other backend by
establishing a known-good conformance baseline. No new rendering features.

## What to build

1. Move `VulkanBackend` to satisfy each `GpuBackend` signature exactly:
   - `drawFrame(commands, atlas)` → `drawFrame(commands, handles: AtlasHandles)`. The single
     glyph atlas becomes one entry in `AtlasHandles`; SDF and image atlases (already present
     in v1 as `GpuSdfAtlas` / image tiles) become the other entries.
   - `initQuadPipeline` / `deinitQuadPipeline` fold into `initPipelines` / `deinit`.
   - `createSurface` calls route through `Platform.createSurface(.vulkan, instance)`.
2. Extract the shader fragment-mode `switch` to align 1:1 with the RJ0 mode table; no mode
   logic changes, only the source is reorganized so the parity test (RJ0 AC3) can read it.
3. Expose `capabilities()` reporting the real device limits already queried at init
   (`max_texture_dim`, subpixel support = true, present modes from R13 frame pacing).

## Module location

```
src/01/types.zig         — VulkanBackend reshaped to GpuBackend signatures
src/09/shaders/quad.frag — mode switch reorganized to match RJ0 table (no logic change)
src/10/backend.zig       — VulkanBackend registered as the .vulkan active backend
docs/requirements/RJ1_vulkan_backend_conformance.md
```

## Public API changes

```zig
// VulkanBackend signatures now match GpuBackend exactly (see RJ0).
// drawFrame signature changes:
//   v1:  drawFrame(commands: []const DrawCommand, atlas: *const anyopaque) void
//   v2:  drawFrame(commands: []const DrawCommand, handles: AtlasHandles) void
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Any v1 demo screen rendered under refactored backend | Pixel-identical to pre-refactor (visual suite) |
| Existing `09.acceptance_test.zig` | Passes unchanged except for the `drawFrame` signature update |
| Subpixel text, SDF icons, gradients, AA circles, shadows | All render as before — modes unchanged |

## Non-goals (DO NOT implement — INV-5.4)

- **No new visual features** — this is a refactor; behavior must not change.
- **No performance "improvements"** that alter output.
- **No removal of the v1 atlas types** beyond renaming/wrapping them as `AtlasHandle`.

## Acceptance criteria

1. `zig build -Dgpu=vulkan` passes; all existing module 01 and 09 acceptance tests pass after
   the mechanical signature updates.
2. The full v1 visual-regression suite (the demo app screens) renders pixel-identical to the
   pre-refactor baseline (diff = 0).
3. RJ0 AC3 (shader-mode parity test) passes against the reorganized `quad.frag`.
4. RJ0 AC5 (no `Vulkan*` symbol in modules 04–08) passes.

## Deferred items from M20 (must be completed as part of this requirement)

The following items were deferred from M20 (RJ0 implementation) because they require the
Vulkan conformance refactor to land first. They are **not optional** — they are part of
RJ1's definition of done.

### AC2 — Visual regression baseline

M20 shipped without a pre-refactor screenshot baseline. RJ1 is the refactor; the baseline
must be established **before** the refactor code lands:

1. Run `zig build visual-check` on the `main` branch (pre-refactor) and save the output
   screenshots to `testdata/visual-baseline/` (one PNG per demo screen).
2. After the refactor lands, run `zig build visual-check` again and diff against the baseline.
3. AC2 is satisfied when the diff shows 0 structural differences (pixel-identical or within
   the documented AA tolerance).

The baseline directory does not exist yet — the implementer must create it and the `zig build
visual-baseline` capture step as part of this requirement.

### `drawFrame` AtlasHandles signature

M20 kept `drawFrame(commands, atlas: *const anyopaque)` because `09.acceptance_test.zig`
(frozen, INV-5.3) calls `drawFrame(&.{}, &gpu_atlas)` with a raw pointer. RJ1 (this
requirement) changes the `VulkanBackend.drawFrame` signature to `AtlasHandles` as specified
in the RJ0 public API table. This requires a contract amendment (INV-5.3 / AAP):

1. Update `src/01/types.zig` `drawFrame` to accept `handles: AtlasHandles`.
2. Update the corresponding call sites in `docs/specs/09.acceptance_test.zig` in the same
   pass (never weaken an assertion).
3. Record the amendment in `docs/specs/AMENDMENTS_LOG.md`.
