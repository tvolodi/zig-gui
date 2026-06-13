# RJ5 — M20-03: Platform surface abstraction

> Roadmap item: M20-03
> Depends on: 01 (Platform), RJ0 (BackendKind)
> Blocked by ratification of `V2_constitution_amendment.md` (INV-1.2-v2, INV-2.2 extended to
> a web surface).
> Read `RJ0_gpu_backend_seam.md` and `V2_ARCHITECTURE.md` §2 before this file.

## Purpose

Generalize the v1 single `Platform.createSurface` (which returns a Vulkan surface) into a thin
per-target surface layer that hands each backend the drawable handle it needs, while keeping
the rest of `Platform` (windowing, input, frame pacing) unchanged. This is the only place,
besides module 10, where per-OS code is permitted (INV-1.2-v2).

## What to build

A `Surface` abstraction in module 01 that, given a `BackendKind`, produces:

| Backend | Surface handle | Window source |
|---|---|---|
| Vulkan | `VkSurfaceKHR` | GLFW (Win/Linux), GLFW-Cocoa (macOS) |
| Metal | `CAMetalLayer` | GLFW-Cocoa window's `NSView` |
| DX12 | `HWND` + `IDXGISwapChain3` | GLFW Win32 window |
| WebGPU (native) | `WGPUSurface` from window handle | GLFW |
| WebGPU (browser) | `GPUCanvasContext` | `<canvas>`, no GLFW |

```zig
pub const Surface = union(BackendKind) {
    vulkan: *anyopaque,   // VkSurfaceKHR
    metal: *anyopaque,    // CAMetalLayer
    dx12: Win32Surface,   // HWND + swapchain
    webgpu: *anyopaque,   // WGPUSurface or canvas context
};

pub fn createSurface(self: *Platform, backend: BackendKind, instance: ?*anyopaque) PlatformError!Surface;
```

For the browser (RJ4), a separate `Platform` implementation backed by a `<canvas>` and a JS
input shim provides the same public API (`pollEvents`, `framebufferSize`, mouse/keyboard
state, R11/R12) without GLFW. Selection is compile-time by target (`wasm32` → web platform).

## Module location

```
src/01/surface.zig         — Surface union, createSurface dispatch
src/01/surface_win32.zig    — HWND + DXGI (DX12)
src/01/surface_macos.zig    — CAMetalLayer from NSView (Metal)
src/01/surface_web.zig      — canvas context + input shim (browser, no GLFW)
src/01/platform_web.zig     — web Platform implementation mirroring Platform's API
docs/requirements/RJ5_platform_surface_layer.md
```

## Public API changes

```zig
// Module 01
pub const Surface = union(BackendKind) { ... };
pub fn createSurface(self: *Platform, backend: BackendKind, instance: ?*anyopaque) PlatformError!Surface;
// Web target provides a Platform with the identical public surface to the GLFW one.
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Native target, any backend | `createSurface` returns the matching handle; GLFW windowing unchanged |
| Browser target | `Platform` resolves to the canvas-backed implementation; same public API |
| Input on browser | mouse/keyboard/scroll/resize forwarded into the existing event model (R11/R12) |
| Frame pacing (R13) | Native: present-mode selection; browser: requestAnimationFrame |

## Non-goals (DO NOT implement — INV-5.4)

- **No custom windowing on native** — GLFW stays the windowing layer (INV-2.2). Only the
  surface handle extraction is added per OS.
- **No per-OS code outside module 01 surface files and module 10** (INV-1.2-v2).
- **No mobile windowing/lifecycle** (INV-1.2-v2).
- **No multiple simultaneous backends** — one `BackendKind` per build.

## Acceptance criteria

1. `createSurface` returns the correct handle type for each `-Dgpu` selection.
2. The Vulkan path is unchanged (RJ1 visual diff = 0).
3. The browser `Platform` passes the existing event-model tests (R11/R12) against simulated
   canvas events.
4. A grep gate confirms no OS-specific symbols (`HWND`, `NSView`, `CAMetalLayer`, `canvas`)
   appear outside `src/01/surface_*.zig`, `src/01/platform_web.zig`, and module 10.
