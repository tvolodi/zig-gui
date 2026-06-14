# RJ4 — M23-01: WebGPU backend + Web target

> Roadmap item: M23-01
> Depends on: RJ0 (GpuBackend seam), RJ1, RJ5 (surface layer)
> Blocked by ratification of `V2_constitution_amendment.md` (INV-1.2-v2 adds Web; INV-2.1-v2
> adds WebGPU; §2 approves Dawn *or* wgpu-native — this requirement records the choice).
> Read `RJ0_gpu_backend_seam.md` before this file.

## Purpose

Implement a WebGPU `GpuBackend` so the framework can target the browser (WASM + `<canvas>`)
and, on desktop, run over a native WebGPU implementation. Same `DrawCommand` list, same
fragment modes, translated to WGSL.

## Decision recorded here

**WebGPU implementation: wgpu-native** (Rust→C ABI, MPL) is selected over Dawn (C++, BSD) for
the desktop/native path because its C ABI binds cleanly via `@cImport` with no C++ toolchain.
For the browser path, the browser's built-in WebGPU is used directly (no bundled
implementation). If wgpu-native proves unsuitable, the fallback is Dawn; the amendment §2 lists
both. **This choice requires owner sign-off as part of ratification.**

## What to build

### `WebGpuBackend` (module 10) implementing `GpuBackend`

- Adapter/device via `wgpuInstanceRequestAdapter` (native) or `navigator.gpu` (browser).
- Render pipelines mirroring quad + curve; bind groups for atlas textures.
- Atlas uploads via `wgpuQueueWriteTexture` (R8Unorm / RGBA8Unorm).
- `drawFrame` encodes one render pass from the shared `buildDrawList` output (INV-2.3).
- Present: surface configure + `wgpuSurfacePresent` (native); requestAnimationFrame-driven on
  the browser.

### Web surface + entry (RJ5 + this)

- Browser: WASM build target; the surface is a `<canvas>` whose `GPUCanvasContext` provides the
  drawable. A minimal JS shim forwards GLFW-equivalent input events (mouse, keyboard, resize)
  into the existing event model (R11). No GLFW in the browser build.
- Desktop native WebGPU: GLFW window + wgpu-native surface from the window handle.

### Shaders

WGSL `quad`/`curve` shaders; mode logic matches the RJ0 parity table.

### Build

`-Dgpu=webgpu`. Two sub-targets: `-Dtarget=wasm32-emscripten` (browser) and native.
Persistent settings (R82) and logging (RA2) degrade to in-memory / console on the browser
(no filesystem) — called out as the main platform-capability gap.

## Module location

```
src/10/webgpu_backend.zig   — WebGpuBackend : GpuBackend
src/10/shaders/quad.wgsl     — WGSL quad shader
src/10/shaders/curve.wgsl    — WGSL curve shader (RM0)
src/01/surface_web.zig       — <canvas> / GPUCanvasContext surface + input shim
src/01/surface_webgpu_native.zig — native wgpu surface
build.zig                    — -Dgpu=webgpu, wasm sub-target, wgpu-native linkage
docs/requirements/RJ4_webgpu_backend_web.md
```

## Public API changes

None beyond RJ0. Platform capability flags (filesystem availability) exposed via `Caps` /
platform query so R82/RA2 can branch without per-call OS checks upstream.

## Behavioral contract

| Situation | Behavior |
|---|---|
| `zig build -Dgpu=webgpu -Dtarget=wasm32-emscripten` | Produces a `.wasm` + `.js` loader; demo runs in a WebGPU browser |
| Browser without WebGPU | Startup message in-page (the web analogue of RA3); no crash |
| Persistent settings on browser | In-memory only (no disk); documented degradation |
| Resize / DPI on browser | Canvas size + `devicePixelRatio` drive resize + dpi_scale (RD5) |
| All fragment modes | Render through WGSL equivalents |

## Non-goals (DO NOT implement — INV-5.4)

- **No DOM-based rendering** — everything draws to the WebGPU canvas; no HTML widgets.
- **No WebGL fallback** — WebGPU only; unsupported browsers get a message.
- **No server, no networking** — the auto-update deferral stands; the web build is static.
- **No mobile-browser optimization** — desktop browsers only (INV-1.2-v2).
- **No WebGPU-only visual features** — shared modes only.

## Acceptance criteria

1. `zig build -Dgpu=webgpu` (native) and the wasm sub-target both succeed.
2. The demo app renders in a WebGPU-capable browser; every component category appears.
3. Shader-mode parity test passes for the WGSL shader set.
4. Input (click, type, scroll, resize) works in the browser via the event shim.
5. Browser-without-WebGPU shows the in-page unsupported message; no uncaught exception.
6. Persistent-settings and logging degradation on the browser is documented and does not crash.

## Deferred items from M20 (prerequisite check)

Before implementing RJ4, confirm that:

1. **RJ1** has completed the `drawFrame` AtlasHandles signature update and visual regression
   baseline (see `RJ1_vulkan_backend_conformance.md` deferred items section).
2. **RJ2** has completed the surface layer file extraction (see `RJ2_metal_backend_macos.md`
   deferred items section). `src/01/surface_web.zig` and `src/01/surface_webgpu_native.zig`
   (listed in the module location table above) must be created as part of RJ4.

No additional M20 deferrals apply to RJ4 specifically.
