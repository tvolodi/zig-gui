# RM1 — M26-02: Scales, axes, and chart frame

> Roadmap item: M26-02
> Depends on: RM0 (curve primitives), 04 (layout — chart occupies a layout rect), 02 (text — labels)
> Read `RM0_chart_command_vocabulary.md` and `V2_ARCHITECTURE.md` §5 before this file.

## Purpose

Provide the coordinate machinery every chart type shares: scales that map data values to pixel
positions, axes with ticks and labels, and gridlines, laid out within a chart frame that
occupies a normal layout rect. RM2 builds marks on top of this; RM1 owns nothing visual beyond
axes/grid.

## What to build

### Scales (module 13)

```zig
pub const Scale = union(enum) {
    linear: struct { domain_min: f64, domain_max: f64, range_min: f32, range_max: f32 },
    log:    struct { domain_min: f64, domain_max: f64, range_min: f32, range_max: f32 },
    band:   struct { categories: []const []const u8, range_min: f32, range_max: f32, padding: f32 },
    time:   struct { t_min: i64, t_max: i64, range_min: f32, range_max: f32 },

    pub fn map(self: Scale, value: f64) f32;       // data → pixel
    pub fn invert(self: Scale, pixel: f32) f64;    // pixel → data (for hit-testing, RM3)
    pub fn ticks(self: Scale, target_count: u32, gpa) ![]Tick;  // "nice" tick values
};
```

`ticks` produces human-friendly intervals (1/2/5×10ⁿ for linear; calendar steps for time;
each category for band). Number/date labels format through M15 (RE0/RE1) for locale support.

### Axes + frame (module 13)

```zig
pub const ChartFrame = struct {
    plot_rect: Rect09,      // inner area for marks (frame minus axis gutters)
    x: Scale, y: Scale,
};

/// Emit axis lines, ticks, tick labels (glyph cmds), and gridlines (polyline cmds) for a frame.
pub fn drawAxes(frame: *const ChartFrame, opts: AxisOptions, out: *DrawList) void;
```

Axis gutters are computed from measured label widths (module 02 measurement) so labels never
clip. Gridlines use `PolylineCmd` (RM0); axis labels use existing `GlyphCmd`.

## Module location

```
src/13/scale.zig          — Scale union, map/invert/ticks
src/13/axes.zig            — ChartFrame, drawAxes, AxisOptions
docs/requirements/RM1_scales_axes.md
```

## Public API changes

```zig
// Module 13: Scale, Tick, ChartFrame, AxisOptions, drawAxes()
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Linear scale domain 0–100 → range 0–200px | `map(50) == 100` |
| `ticks(5)` on 0–97 | "Nice" ticks (0,20,40,60,80,100) not raw divisions |
| Band scale, 4 categories | Evenly spaced bands with padding; `map` returns band centers |
| Time scale spanning months | Calendar-aware ticks (month starts), labels via RE1 |
| Long y labels | Axis gutter widens to fit measured label width; no clipping |
| Locale set to a thousands-separator locale | Tick labels formatted via RE0 |

## Non-goals (DO NOT implement — INV-5.4)

- **No secondary/dual axes**, no broken axes in v2.
- **No polar/radial coordinate system** (pie in RM2 is drawn directly with arcs, not a polar scale).
- **No automatic data-driven domain padding heuristics** beyond simple min/max + nice ticks.
- **No animation of axis transitions** (M14 animation is not wired into charts in v2).

## Acceptance criteria

1. Module 13 acceptance test: `map`/`invert` round-trip for linear, log, time; band centers
   correct; `ticks` produces nice values for several ranges.
2. `drawAxes` emits axis lines, ticks, gridlines, and labels positioned within the frame; axis
   gutters fit measured labels.
3. Tick labels format through RE0/RE1 under a non-default locale.
4. Visual: a chart frame with x and y axes renders cleanly with no label clipping.
