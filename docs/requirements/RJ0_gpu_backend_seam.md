# RJ0 — M20-01: GPU backend seam (`GpuBackend` interface)

> Roadmap item: M20-01
> Depends on: 01 (Platform, VulkanBackend), 09 (DrawCommand, GpuAtlas)
> Blocked by ratification of `V2_constitution_amendment.md` (replaces INV-2.1 with INV-2.1-v2).
> Read `00_constitution.md` and `V2_ARCHITECTURE.md` §2 before this file.

## Purpose

Define the single interface every GPU backend implements, so that Vulkan, Metal, DX12, and
WebGPU are interchangeable peers selected at build time. This requirement defines **only the
seam** — no second backend is written here. The deliverable is the interface plus the proof
(RJ1) that the existing Vulkan code fits behind it with zero behavior change.

This makes INV-2.3 (renderer consumes a flat draw-command list) structural: the draw-command
list and the atlas handles are the *only* data crossing the seam.

## What to build

### `GpuBackend` interface (module 10)

Dispatch mechanism is a decision of this requirement: **comptime tagged union** is preferred
over a runtime vtable, because exactly one backend is selected per build (INV-1.1, no runtime
switching) and comptime dispatch costs nothing at the frame hot path. The selected backend is
chosen by a build option `-Dgpu=vulkan|metal|dx12|webgpu` defaulting per target OS.

```zig
pub const BackendKind = enum { vulkan, metal, dx12, webgpu };

pub const Caps = struct {
    max_texture_dim: u32,
    subpixel_text: bool,        // RD2 supported on this backend
    present_modes: PresentModeSet,
};

/// The contract. Each concrete backend is a struct exposing these exact signatures.
pub const GpuBackend = struct {
    pub fn init(gpa: std.mem.Allocator, platform: *Platform) BackendError!GpuBackend;
    pub fn deinit(self: *GpuBackend) void;
    pub fn initPipelines(self: *GpuBackend) BackendError!void;   // quad + curve (RM0)
    pub fn resize(self: *GpuBackend, w: u32, h: u32, dpi_scale: f32) void;
    pub fn uploadAtlas(self: *GpuBackend, atlas: *const GlyphAtlas) BackendError!AtlasHandle;
    pub fn uploadSdfAtlas(self: *GpuBackend, atlas: *const SdfAtlas) BackendError!AtlasHandle;
    pub fn uploadImage(self: *GpuBackend, pixels: []const u8, w: u32, h: u32) BackendError!AtlasHandle;
    pub fn drawFrame(self: *GpuBackend, commands: []const DrawCommand, handles: AtlasHandles) void;
    pub fn capabilities(self: *const GpuBackend) Caps;
};
```

### Shader mode parity table (module 10)

Every backend translates the *same* fragment modes. The canonical list lives in module 10 as
a comment-documented enum; each backend's shader source must implement exactly these and no
others (INV-2.1-v2 forbids private modes):

```
mode 0: solid rect            mode 4: SDF icon (RD3)
mode 1: bordered rect         mode 5: gradient (RD0)
mode 2: glyph (atlas-sampled) mode 6: AA filled circle (RD4)
mode 3: image rect (RGBA)     mode 7: subpixel glyph (RD2)
                              mode 8: curve/polyline (RM0, added by charts)
```

A CI check (RJ0 acceptance) asserts each backend's shader set declares the same mode count.

### Platform decoupling

`Platform.createSurface` (v1 returns a Vulkan surface) generalizes to return a
backend-appropriate surface handle, dispatched on `BackendKind`. See RJ5 for the surface
layer; this requirement only declares the call shape the seam depends on.

## Module location

```
src/10/types.zig          — BackendKind, Caps, GpuBackend contract, AtlasHandle, shader-mode enum
src/10/backend.zig        — comptime selection of the active backend struct
build.zig                 — -Dgpu build option; selects backend + shader compilation per target
docs/specs/10.types.zig   — spec mirror
docs/requirements/RJ0_gpu_backend_seam.md
```

## Public API changes

```zig
// Module 10 (new)
pub const BackendKind = enum { vulkan, metal, dx12, webgpu };
pub const GpuBackend = ...; // see above
pub const AtlasHandle = struct { backend_obj: *anyopaque };

// Module 01: Platform.createSurface generalized
pub fn createSurface(self: *Platform, backend: BackendKind, instance: ?*anyopaque) PlatformError!*anyopaque;
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `-Dgpu=vulkan` (default on Win/Linux) | `GpuBackend` resolves to `VulkanBackend`; behavior identical to v1 |
| `-Dgpu` value unsupported on target | `build.zig` errors at configure time with a clear message |
| `drawFrame` called with a command whose mode the backend lacks | Compile-time impossible — all backends implement all modes |
| Atlas uploaded once, reused across frames | `AtlasHandle` is stable until `deinit`; re-upload only on atlas change |
| Window resized | `resize` reconfigures swapchain/drawable; next `drawFrame` targets new size |

## Non-goals (DO NOT implement — INV-5.4)

- **No runtime backend switching** — the backend is fixed at build time (INV-1.1).
- **No second backend in this requirement** — Metal/DX12/WebGPU are RJ2/RJ3/RJ4.
- **No new draw-command variants** — curve mode (8) is added by RM0, not here.
- **No backend-private capabilities leaking upstream** — `Caps` is read-only metadata for the
  app (e.g. to disable subpixel text); it must not branch layout or element-store logic.
- **No abstraction over the atlas pixel format** beyond the existing R8/RGBA the renderer uses.

## Acceptance criteria

1. `zig build -Dgpu=vulkan` produces a binary byte-for-byte equivalent in *behavior* to the
   pre-refactor build (RJ1 proves this with the existing acceptance + visual suites).
2. The `GpuBackend` contract compiles with `VulkanBackend` substituted as the active backend.
3. A build-time test asserts the shader-mode enum and the Vulkan shader's mode `switch` have
   identical case counts.
4. `build.zig` rejects an unsupported `-Dgpu` for the target with a configure-time error.
5. No symbol named `Vulkan*` appears in modules 04–08 (grep gate): the seam fully hides the
   backend from layout/style/components.
