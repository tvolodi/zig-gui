# RJ3 — M22-01: DX12 backend (Windows)

> Roadmap item: M22-01
> Depends on: RJ0 (GpuBackend seam), RJ1 (Vulkan conformance baseline), RJ5 (surface layer)
> Blocked by ratification of `V2_constitution_amendment.md` (INV-2.1-v2 adds DX12; §2 approves
> D3D12/DXGI system headers).
> Read `RJ0_gpu_backend_seam.md` before this file.

## Purpose

Implement a Direct3D 12 `GpuBackend` as a native Windows rendering path, alongside the Vulkan
path that already covers Windows. DX12 is added for parity with platform expectations and to
exercise the seam with a third API; Vulkan remains the Windows default. Same `DrawCommand`
list, same fragment modes, translated to HLSL→DXIL.

## What to build

### `Dx12Backend` (module 10) implementing `GpuBackend`

- `ID3D12Device` + command queue; `IDXGISwapChain3` for the `HWND` surface (RJ5 provides the
  `HWND`, already available from GLFW on Windows).
- Root signature + PSOs mirroring the quad + curve pipelines; one descriptor heap for the
  glyph/SDF/image atlas SRVs.
- Atlas uploads create committed `ID3D12Resource` textures (R8_UNORM / RGBA8_UNORM) via an
  upload heap + copy command list; `AtlasHandle` wraps the resource + SRV handle.
- `drawFrame` records one command list: a vertex buffer of quads built from the shared
  `buildDrawList` output (INV-2.3), one draw per batch, pixel shader branches on mode.
- Present modes: map R13 frame pacing to `IDXGISwapChain::Present(syncInterval)`.

### Shaders

HLSL `quad.vert`/`quad.frag` equivalents + curve shader, compiled to DXIL via `dxc` at build
time. Mode logic matches the RJ0 parity table.

### Build

`-Dgpu=dx12` (opt-in on Windows; Vulkan stays default). `dxc` recorded as a build-time tool.

## Module location

```
src/10/dx12_backend.zig     — Dx12Backend : GpuBackend
src/10/shaders/quad.hlsl     — HLSL quad shader
src/10/shaders/curve.hlsl    — HLSL curve shader (RM0)
src/01/surface_win32.zig     — HWND/DXGI swapchain surface (see RJ5)
build.zig                    — -Dgpu=dx12 path, dxc compilation
docs/requirements/RJ3_dx12_backend_windows.md
```

## Public API changes

None beyond RJ0. `Dx12Backend` conforms to `GpuBackend`.

## Behavioral contract

| Situation | Behavior |
|---|---|
| `zig build -Dgpu=dx12` on Windows | Native DX12 app; demo screens render |
| Same demo screen, DX12 vs Vulkan | Visually equivalent (within AA tolerance) |
| HiDPI / per-monitor DPI | `dpi_scale` from monitor content scale (RD5) |
| DX12 unavailable (old GPU) | Graceful startup failure dialog (RA3) |
| All fragment modes | Render through HLSL equivalents |

## Non-goals (DO NOT implement — INV-5.4)

- **No DX11 / DX9 fallback** — DX12 only; if unavailable, fail gracefully (RA3) or use Vulkan.
- **No DX12-only visual features** — shared modes only (INV-2.1-v2).
- **No making DX12 the Windows default** — Vulkan stays default; DX12 is `-Dgpu=dx12` opt-in.

## Acceptance criteria

1. `zig build -Dgpu=dx12` succeeds on a Windows target; DXIL is produced.
2. The demo app launches under DX12 and renders every component category at least once.
3. Shader-mode parity test passes for the HLSL shader set.
4. Side-by-side visual comparison (DX12 vs Vulkan reference) shows no structural differences.
5. Missing-device path shows the RA3 startup-failure dialog.
