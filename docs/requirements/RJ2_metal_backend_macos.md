# RJ2 — M21-01: Metal backend (macOS)

> Roadmap item: M21-01
> Depends on: RJ0 (GpuBackend seam), RJ1 (Vulkan conformance baseline), RJ5 (surface layer)
> Blocked by ratification of `V2_constitution_amendment.md` (INV-1.2-v2 adds macOS;
> INV-2.1-v2 adds Metal; §2 approves Metal-cpp headers).
> Read `RJ0_gpu_backend_seam.md` before this file.

## Purpose

Implement a Metal `GpuBackend` so the framework runs natively on macOS, where Vulkan is not a
first-class API. Metal renders the identical `DrawCommand` list through the same fragment
modes (RJ0 parity table), translated to Metal Shading Language.

## What to build

### `MetalBackend` (module 10) implementing `GpuBackend`

- Device/queue from `MTLCreateSystemDefaultDevice`; one `CAMetalLayer` drawable per frame,
  obtained from the surface RJ5 provides for macOS.
- One render pipeline state per shader stage, mirroring the Vulkan quad + curve pipelines.
- Atlas uploads create `MTLTexture` (R8Unorm for glyph/SDF, RGBA8 for image) — same formats
  the Vulkan path uses; `AtlasHandle.backend_obj` wraps the `MTLTexture`.
- `drawFrame` encodes one render pass: vertex buffer of quads (built from `DrawCommand` exactly
  as the Vulkan path builds it — the CPU-side `buildDrawList` output is shared, INV-2.3), one
  draw call per batch, fragment shader branches on the mode constant.
- Present modes: map R13 frame pacing (vsync on/off) to `CAMetalLayer.displaySyncEnabled`.

### Shaders

Translate `quad.vert` / `quad.frag` and the curve shader (RM0) to MSL. Mode logic must match
the RJ0 table case-for-case (parity test, RJ0 AC3 generalized to all backends). HiDPI (RD5)
uses the layer `contentsScale`.

### Build

`-Dgpu=metal` (default when target OS is macOS). MSL compiled to a `.metallib` at build time
(the Metal analogue of glslc); recorded as a build-time tool in the amendment if not already.

## Module location

```
src/10/metal_backend.zig    — MetalBackend : GpuBackend
src/10/shaders/quad.metal    — MSL quad shader (mode parity with quad.frag)
src/10/shaders/curve.metal   — MSL curve shader (RM0)
src/01/surface_macos.zig     — CAMetalLayer surface (see RJ5)
build.zig                    — -Dgpu=metal path, metallib compilation
docs/requirements/RJ2_metal_backend_macos.md
```

## Public API changes

None beyond RJ0 — `MetalBackend` conforms to the existing `GpuBackend` contract. No upstream
module changes.

## Behavioral contract

| Situation | Behavior |
|---|---|
| `zig build -Dgpu=metal` on macOS | Produces a native macOS app; demo screens render |
| Same demo screen, Metal vs Vulkan | Visually equivalent (within AA tolerance; not bit-exact across GPUs) |
| HiDPI Retina display | `dpi_scale` from `contentsScale`; all px values multiplied (RD5) |
| Metal device unavailable | Graceful startup failure dialog (RA3), not a crash |
| All fragment modes (rect…curve) | Render through MSL equivalents |

## Non-goals (DO NOT implement — INV-5.4)

- **No macOS-specific UI behavior** — menus, dock, traffic-light theming beyond what GLFW/the
  surface layer already provide. Per-OS code stays in module 10 + surface layer (INV-1.2-v2).
- **No Metal-only visual features** — modes are shared; no private mode (INV-2.1-v2).
- **No MoltenVK shim** — this is a native Metal backend, not Vulkan-over-Metal.
- **No iOS** — macOS desktop only (INV-1.2-v2 keeps mobile out of scope).

## Acceptance criteria

1. `zig build -Dgpu=metal` succeeds on a macOS target; `.metallib` is produced.
2. The demo app launches on macOS and renders every component category at least once.
3. Shader-mode parity test passes for the MSL shader set (same mode count as Vulkan).
4. A side-by-side visual comparison of the demo screens (Metal vs Vulkan reference) shows no
   structural differences (text legible, colors correct, shapes positioned identically).
5. Missing-device path shows the RA3 startup-failure dialog.
