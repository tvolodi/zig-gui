# RM0 — M26-01: Chart command vocabulary + GPU curve primitives

> Roadmap item: M26-01
> Depends on: 09 (DrawCommand, renderer), RJ0 (shader-mode parity across backends)
> Read `00_constitution.md` and `V2_ARCHITECTURE.md` §5 before this file.

## Purpose

Add the small set of general GPU drawing primitives that data visualization needs — stroked
polylines, filled paths, and arcs — to the shared `DrawCommand` vocabulary (INV-2.3). These
are **not** chart-specific; they are general primitives that every backend renders identically
via one new shader mode. Charts (RM1–RM3) are built entirely on top of these plus existing
commands. This is the only place charts touch the renderer.

## What to build

### New draw commands (module 01)

```zig
pub const PolylineCmd = struct {
    points: []const Vec2,   // screen-space, pre-tessellated (see decision below)
    width: f32,
    color: Color09,
    closed: bool,           // closed = polygon outline
    join: enum { miter, bevel, round },
};

pub const FilledPathCmd = struct {
    /// Triangulated fan/strip of the filled region (areas, pie wedges). CPU-tessellated.
    vertices: []const Vec2,
    indices: []const u16,
    color: Color09,
};

pub const ArcCmd = struct {
    center: Vec2, radius: f32, start_rad: f32, end_rad: f32,
    width: f32,             // 0 = filled wedge, >0 = stroked arc
    color: Color09,
};

// DrawCommand union gains: polyline, filled_path, arc
```

### Decision recorded here

**CPU pre-tessellation** is chosen over GPU tessellation. Polylines are expanded to triangle
strips and paths triangulated on the CPU (in module 13, before emitting commands), so the
shader stays a single simple "mode 8: solid-with-coverage" path. Rationale: keeps all four
backends' shaders trivially in parity (RJ0), avoids per-backend tessellation-shader
divergence, and chart vertex counts are small. Anti-aliasing reuses the RD4 coverage-feather
approach at stroke edges.

### Shader mode 8 (all backends)

One new fragment mode rendering tessellated geometry with a solid color and a 1px coverage
feather at edges (consistent with RD4). Added to the RJ0 parity table; each backend
(Vulkan/Metal/DX12/WebGPU) implements it in its shader language. No backend-private behavior.

## Module location

```
src/01/types.zig          — PolylineCmd, FilledPathCmd, ArcCmd; DrawCommand variants
src/10/shaders/*           — mode 8 added to quad.frag / .metal / .hlsl / .wgsl (parity)
src/13/tessellate.zig      — CPU polyline expansion + path triangulation (chart module owns it)
docs/specs/13.types.zig    — spec mirror
docs/requirements/RM0_chart_command_vocabulary.md
```

## Public API changes

```zig
// Module 01: PolylineCmd, FilledPathCmd, ArcCmd; DrawCommand gains polyline/filled_path/arc.
// Module 10: shader-mode table gains mode 8 (curve/tessellated geometry).
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| `polyline` with 3 points, width 2 | Stroked path with the chosen join, 1px AA feather |
| `filled_path` (area under a line) | Filled region rendered from CPU triangulation |
| `arc` width 0 | Filled pie wedge |
| `arc` width > 0 | Stroked arc / donut segment |
| Same primitive across Vulkan/Metal/DX12/WebGPU | Visually equivalent (mode-8 parity) |
| Primitive overlapping existing rects/glyphs | Composites correctly in draw order (no z fighting) |

## Non-goals (DO NOT implement — INV-5.4)

- **No Bézier/curve draw command** — paths are pre-tessellated polylines; smoothing is a
  chart-layer concern (RM2 may sample a curve into points).
- **No GPU tessellation shaders** (decision above).
- **No general 2D vector graphics API** — primitives exist to serve charts (RM1–RM3), not as a
  public canvas.
- **No backend-private modes** (INV-2.1-v2).
- **No stroke dashing / gradients on strokes** in v2.

## Acceptance criteria

1. Module 01 + 13 acceptance test: `PolylineCmd`, `FilledPathCmd`, `ArcCmd` construct and the
   tessellator produces valid triangle data for representative inputs.
2. RJ0 shader-mode parity test passes with mode 8 present in all backend shader sets.
3. Visual: a demo screen draws a stroked polyline, a filled area, a stroked arc, and a filled
   wedge; edges are anti-aliased (RD4-consistent).
4. The same screen renders equivalently under at least Vulkan and one other backend.
5. No regression: existing modes 0–7 unchanged.
