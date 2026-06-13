# RD5 — M13-06: HiDPI / display-scale awareness

> Roadmap item: M13-06  
> Depends on: M1-01 (platform spike)  
> Read `00_constitution.md` before this file.

## Purpose

Read the monitor's content scale from GLFW and multiply all logical pixel values so the UI
renders at the correct physical pixel density. On HiDPI displays (Retina, 4K laptops, etc.),
GLFW reports a content scale of 2.0 or higher. Without scaling, a `w-100` element occupies
100 physical pixels on the screen — half the intended visual size on a 2× display, making
text tiny and hit targets too small for comfortable use.

This requirement ensures that all layout, text, spacing, and rendering values are multiplied
by the display scale factor so the UI appears at its intended physical size regardless of
the monitor's pixel density.

## What to build

### Read content scale from GLFW (module 01)

At platform initialization, after the window is created, query the monitor's content scale:

```zig
// In Platform.init() or a new method:
pub fn contentScale(self: *Platform) f32 {
    const impl: *PlatformImpl = @ptrCast(@alignCast(self._impl));
    const monitor = c.glfwGetPrimaryMonitor();
    // Fallback: if no monitor (headless), return 1.0.
    if (monitor == null) return 1.0;

    var scale_x: f32 = 1.0;
    var scale_y: f32 = 1.0;
    c.glfwGetMonitorContentScale(monitor, &scale_x, &scale_y);
    return @max(scale_x, scale_y);
}
```

Use `glfwGetPrimaryMonitor()` because the window may not be associated with a monitor
at startup time (GLFW assigns it later). The content scale of the primary monitor is
used for the entire application lifetime. Multi-monitor scale changes are a non-goal
for v1.

### Store `dpi_scale` in AppInner (src/app/app.zig)

```zig
// AppInner gains:
dpi_scale: f32 = 1.0,
```

This is read once at startup and stored. It is passed to the layout engine and renderer
each frame.

### Layout engine: multiply all `px` values (module 04)

The layout engine's `solve()` function receives `dpi_scale` as a parameter or reads it
from a context struct. Before computing the layout, every user-specified pixel value is
multiplied by `dpi_scale`:

- `Dimension.px(v)` → treated as `px(v * dpi_scale)` during layout.
- `font_size` → multiplied by `dpi_scale` (a `text-base` of 14 px becomes 28 physical px on 2×).
- `gap`, `padding`, `margin` → multiplied.
- `border_width` → multiplied.
- `rounded` corner radii → multiplied.

The multiplication happens **after** class resolution (which still stores logical pixel
values) and **before** layout computation. The layout engine operates entirely in
physical pixels.

Rounding rule: after multiplication, the value is rounded to the nearest integer pixel
using `@round(v * dpi_scale)`. All layout math uses `f32`, so this is just a precision
step before final pixel assignment.

The `dpi_scale` is NOT stored on individual `LayoutNode` objects — it is passed as a
parameter to `solve()` and applied uniformly.

### Renderer: apply `dpi_scale` to orthographic projection (module 09)

The orthographic projection matrix used by the quad pipeline is constructed from the
framebuffer size. With `dpi_scale`, the projection maps logical coordinates to physical
pixels:

```zig
// Before (current):
const ortho = orthographicProjection(0, fb_width, fb_height, 0);

// After RD5:
const ortho = orthographicProjection(0, fb_width, fb_height, 0);
// The ortho maps [0..fb_width] → [-1..+1] in clip space.
// Since layout values are already in physical pixels (multiplied by dpi_scale),
// and the framebuffer size is also in physical pixels, the ortho matrix is
// UNCHANGED. The scaling is already baked into the layout values.
```

Actually, the ortho matrix is unchanged because both the layout output and the framebuffer
size are in the same physical-pixel coordinate system. The `dpi_scale` is only applied to
logical pixel values — once layout is solved, all coordinates are in physical pixels and
the projection maps 1:1 to the framebuffer.

### Font rasterization (module 02)

Font sizes passed to `stbtt_GetCodepointBitmap` are already physical pixels because the
layout engine multiplies the font size by `dpi_scale`. No change to the glyph rasterization
code is needed — it already receives the final pixel size.

### Window-resize handling

On window resize (`glfwSetFramebufferSizeCallback`), the framebuffer size changes but the
`dpi_scale` does not (it's per-monitor, not per-framebuffer). The layout engine re-solves
with the same `dpi_scale` and the new framebuffer size.

### Window move to a different monitor

Detection of monitor change and re-querying the content scale is a non-goal for v1. The
app uses the primary monitor's scale at startup and keeps it for the session lifetime. If
the user moves the window to a different monitor, the scale remains at the startup value.

## Module location

```
src/01/types.zig         — Platform.contentScale() method
src/app/app.zig          — dpi_scale field on AppInner, read at startup, pass to layout + renderer
src/04/types.zig         — solve() accepts dpi_scale, multiplies all px values and font sizes
src/09/types.zig         — no ortho change; renderer receives already-scaled physical coordinates
docs/specs/04.types.zig  — updated solve() signature
docs/requirements/RD5_hidpi_display_scale.md
```

## Public API changes

```zig
// Module 01 — Platform gains:
pub fn contentScale(self: *Platform) f32 { ... }

// Module 04 — solve() signature:
pub fn solve(
    nodes: []LayoutNode,         // existing
    allocator: std.mem.Allocator, // existing
    dpi_scale: f32,              // NEW — logical-to-physical pixel scale factor
) !void { ... }

// AppInner gains:
dpi_scale: f32 = 1.0,
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Standard DPI display (scale = 1.0) | All layout values unchanged from current behavior |
| 2× HiDPI display (scale = 2.0) | All px values doubled: `w-100` = 200 physical px, `text-base` = 28 physical px |
| 1.25× display (scale = 1.25, 125% Windows scaling) | `w-100` → 125 physical px; `gap-2` (8 px) → 10 physical px |
| `dpi_scale = 2.0`, `rounded-lg` (8 px radius) | Corner radius → 16 physical px |
| Non-integer scaling result (e.g., `8 * 1.25 = 10.0`, exact) | Rounded to nearest integer: `@round(8.0 * 1.25) = 10` |
| Non-integer scaling result (e.g., `14 * 1.5 = 21.0`, exact) | `@round(14.0 * 1.5) = 21` |
| `glfwGetPrimaryMonitor()` returns null (headless) | `dpi_scale` defaults to 1.0 |
| Framebuffer resize (window dragged to larger size) | `dpi_scale` unchanged; layout re-solves with new framebuffer size |
| Window moved to different monitor | `dpi_scale` NOT updated — uses startup value for session lifetime |

## Non-goals (DO NOT implement — INV-5.4)

- **No per-window DPI scale** — single-window app only for v1.
- **No per-monitor DPI detection in multi-monitor setups** — primary monitor only.
- **No monitor change detection** — if the user moves the window to a different monitor,
  the scale does NOT update. Re-querying on monitor change requires GLFW monitor callbacks
  and a full re-layout, which is deferred.
- **No fractional scale override** — the OS-reported scale is used as-is. No
  `--dpi-scale=1.5` CLI flag to override.
- **No DPI-aware cursor sizes** — cursor bitmaps are not scaled.
- **No DPI-aware image loading** — images and icons are loaded at their native resolution.
  Image scaling is a separate concern.
- **No `rem`/`em` scaling beyond the existing font-size base** — the `dpi_scale` multiplies
  all values uniformly; there is no separate root-em scaling factor.
- **No `devicePixelRatio` web-compatibility** — `dpi_scale` is an internal detail, not an
  API exposed to markup or class resolution.

## Acceptance criteria

1. `zig build` passes after all changes.

2. Unit tests in `src/04/04_test.zig` cover:
   - `dpi_scale = 1.0`: layout values unchanged (regression check).
   - `dpi_scale = 2.0`: a node with `width = .px(100)` resolves to `computed.w = 200`.
   - `dpi_scale = 2.0`: `font_size = 14` → layout uses 28 px for text measurement.
   - `dpi_scale = 1.5`: `inset = .px(8)` → 12 px after rounding (`@round(8 * 1.5) = 12`).

3. Unit tests in `src/01/01_test.zig` cover:
   - `Platform.contentScale()` returns 1.0 on a headless config where `glfwGetPrimaryMonitor()` returns null.
   - (Stub for monitor-dependent tests — actual monitor scale requires hardware.)

4. Visual: run the demo app on a HiDPI display (or with simulated 2× scaling). The UI
   elements are the same physical size as the same app running with `dpi_scale = 1.0`
   on a standard DPI display.

5. No regression: on a standard DPI display (`dpi_scale = 1.0`), the UI renders
   identically to before.
