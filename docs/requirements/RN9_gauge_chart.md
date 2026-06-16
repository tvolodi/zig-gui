# RN9 — Gauge / radial-arc chart

> Status: `planned` — Milestone 27 extension.
> Blocking: TailAdmin Ecommerce demo screen (Screen 12, "Monthly Target" widget).
> Read `docs/specs/00_constitution.md` before this file.
> Use project-relative paths only. Never use absolute Windows paths starting with `c:\`.

## 1. What to build

Add a **gauge chart** rendering function to `src/13/marks.zig`. A gauge displays a single
value (0–1) as a filled semi-circle arc (upper-half dome, like a speedometer or progress
meter). The gauge is composed of two `ArcCmd` draw commands:

1. **Background arc** — full 180° sweep, light-gray color, centered horizontally in the
   chart frame, ring-style (width > 0).
2. **Fill arc** — from the left endpoint to the point at `value * 180°`, accent color, same
   ring geometry as the background.

Both arcs sweep through the **top** of the circle (counterclockwise on screen since Y is
down). The arc angle mapping:
- Start: `start_rad = -π` (left endpoint, equal to the 9 o'clock position)
- End (background): `end_rad = 0` (right endpoint, 3 o'clock position)
- End (fill): `end_rad = -π + value * π`

Ring geometry:
```
outer_r   = min(plot_rect.w, plot_rect.h) * 0.46
inner_r   = outer_r * 0.72   (ring inner radius)
arc_r     = (outer_r + inner_r) / 2   (arc center radius)
arc_width = outer_r - inner_r          (ring thickness)
cy_offset = outer_r * 0.9             (center slightly above plot_rect bottom)
cx        = plot_rect.x + plot_rect.w / 2
cy        = plot_rect.y + plot_rect.h - outer_r * 0.15
```

## 2. Public API

In `src/13/marks.zig`, add:

```zig
/// RN9 — Render a gauge (semi-circle arc meter) into `out`.
/// `value`: clamped to [0, 1]. 0 = empty arc; 1 = full semi-circle.
/// `bg_token`: semantic color token for background arc (e.g. "axis").
/// `fill_token`: semantic color token for fill arc (e.g. "accent").
/// Frame: plot_rect is the available drawing area; center is computed from it.
pub fn renderGauge(
    value: f64,
    bg_token: []const u8,
    fill_token: []const u8,
    frame: *const ChartFrame,
    out: *std.ArrayListUnmanaged(DrawCmd),
    allocator: std.mem.Allocator,
) !void
```

Also expose in `src/13/chart.zig` by adding `gauge` to `ChartKind`:
```zig
pub const ChartKind = enum { line, bar, area, scatter, pie, gauge };
```

Add gauge-specific fields to `Chart`:
```zig
/// RN9 — Gauge fill value [0, 1].  Ignored for non-gauge kinds.
gauge_value: f64 = 0.0,
/// RN9 — Background arc color token.
gauge_bg_token: []const u8 = "axis",
/// RN9 — Fill arc color token.
gauge_fill_token: []const u8 = "accent",
```

In `renderChart` (marks.zig), add the gauge case:
```zig
.gauge => try renderGauge(chart.gauge_value, chart.gauge_bg_token, chart.gauge_fill_token, frame, out, allocator),
```

Note: the gauge kind does NOT iterate over `chart.series`; it uses the gauge-specific fields
directly.

## 3. Acceptance criteria

- `zig build` exits 0.
- `Chart{ .kind = .gauge, .gauge_value = 0.7555, ... }.render(frame, &cmds, alloc)` emits
  exactly 2 `DrawCommand.arc` entries.
- The first arc spans the full 180° (`start_rad = -π`, `end_rad = 0`).
- The second arc ends at approximately `(-π + 0.7555 * π)` radians.
- No existing tests are broken.

## 4. Non-goals

- No text label rendering (center percentage text is placed separately as a NodeDesc Text
  element by the caller).
- No animation (the value is static per frame; animation goes through AnimTimeline if needed).
- No tick marks or labels on the arc itself.
