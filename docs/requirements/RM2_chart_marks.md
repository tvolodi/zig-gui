# RM2 — M26-03: Chart marks (line, bar, area, scatter, pie)

> Roadmap item: M26-03
> Depends on: RM0 (primitives), RM1 (scales/axes), 05 (theme palette for series colors)
> Read `RM1_scales_axes.md` before this file.

## Purpose

Provide the actual chart types as components that, given data and a `ChartFrame` (RM1), emit
the RM0 primitives for their marks. This is the visible chart library: line, bar, area,
scatter, and pie. Series colors come from the theme palette (INV-4.3); charts re-render on
data change through the normal signal/dirty path (INV-3.3).

## What to build

### Chart spec + marks (module 13)

```zig
pub const Series = struct {
    name: []const u8,
    values: []const f64,           // y values; x is index, category, or paired x (scatter)
    color_token: []const u8,       // semantic palette token, not a raw color (INV-4.3)
};

pub const ChartKind = enum { line, bar, area, scatter, pie };

pub const Chart = struct {
    kind: ChartKind,
    series: []const Series,
    x: XData,                      // categories | numeric | time
    // resolved at build of the chart into a ChartFrame + emitted marks
    pub fn render(self: *const Chart, frame: *const ChartFrame, out: *DrawList) void;
};
```

Mark emission per kind:

- **line:** one `PolylineCmd` per series across mapped points.
- **area:** `FilledPathCmd` (region between line and baseline) + optional line on top.
- **bar:** one rect per datum (existing rect command), positioned via band/linear scales;
  grouped or stacked per option.
- **scatter:** one `aa_filled_circle` (RD4) per point.
- **pie:** one `ArcCmd` wedge per datum, angles from value proportions.

Multi-series colors cycle through a palette token sequence (theme layer 2). A legend mapping
series name→color is produced for RM3.

### Chart as a component

`Chart` is a widget kind occupying a layout rect (module 04). It owns a `ChartFrame` built
from its rect and data domains (RM1). When a bound `Signal`/`Value` holding the data changes,
the element is marked dirty and `render` re-emits marks — no special path (INV-3.3).

## Module location

```
src/13/chart.zig          — Chart, Series, ChartKind, render() dispatch per kind
src/13/marks.zig           — per-kind mark emission (line/bar/area/scatter/pie)
src/07/ or src/13/         — Chart widget kind wiring into the component/scene model
docs/requirements/RM2_chart_marks.md
```

## Public API changes

```zig
// Module 13: Series, ChartKind, Chart, XData, render()
// Chart registered as a widget kind that occupies a layout rect.
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Line chart, one series, 10 points | One polyline across 10 mapped points |
| Area chart | Filled region to baseline + optional top line |
| Bar chart, 2 series, grouped | Bars grouped per category via band scale |
| Bar chart, stacked option | Bars stacked, cumulative per category |
| Scatter | One AA circle per (x,y) point |
| Pie, values [30,20,50] | Wedges of 108°, 72°, 180° |
| Data signal changes | Element dirtied; marks re-emitted next frame (no full rebuild) |
| Series colors | Pulled from theme palette tokens; theme swap (R93) recolors |

## Non-goals (DO NOT implement — INV-5.4)

- **No stacked area, no candlestick, no heatmap, no treemap** in v2 (line/bar/area/scatter/pie only).
- **No 3D charts.**
- **No data aggregation / statistics** (binning, regression) — caller supplies final values.
- **No animated transitions between datasets** (M14 not wired to charts in v2).
- **No raw color literals for series** — palette tokens only (INV-4.3).

## Acceptance criteria

1. Module 13 acceptance test: each kind emits the expected primitive counts for a known
   dataset (e.g. pie wedge angles sum to 2π; line emits N−1 segments).
2. Grouped and stacked bar layouts position correctly via RM1 scales.
3. A data-signal change marks the chart element dirty and re-emits marks (verified via the
   dirty bitset, not a tree diff).
4. Series colors resolve from theme palette tokens; a theme swap recolors the chart.
5. Visual: a demo screen shows all five chart kinds rendering correctly with axes (RM1).
