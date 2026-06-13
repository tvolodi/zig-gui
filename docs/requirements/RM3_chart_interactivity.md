# RM3 — M26-04: Chart interactivity (hover, tooltip, legend, selection)

> Roadmap item: M26-04
> Depends on: RM1 (scales/invert), RM2 (marks), R7C (tooltip), R41 (overlay), M1-02 (events)
> Read `RM2_chart_marks.md` before this file.

## Purpose

Make charts interactive using only the framework's existing interaction machinery — events
(M1-02), overlays (R41), tooltips (R7C), and signals (INV-3.3). No new interaction mechanism
is introduced (INV-3.3 forbids an alternative change-propagation path). This is the final
chart requirement; with it, charts are usable in a real app.

## What to build

### Hit-testing (module 13)

Use `Scale.invert` (RM1) to map a mouse position in the plot rect back to data space, then
find the nearest datum/series:

```zig
pub const HitResult = struct { series_idx: u32, datum_idx: u32, value: f64, pixel: Vec2 };
pub fn hitTest(chart: *const Chart, frame: *const ChartFrame, mouse: Vec2) ?HitResult;
```

### Hover + tooltip

On mouse move within a chart element (existing event delivery), run `hitTest`; if a datum is
hit, set a hover `Signal` (datum index) and show an existing R7C tooltip in the R41 overlay
layer with the formatted value (RE0/RE1). Moving off clears the hover signal. The hovered mark
is emphasized (e.g. a larger AA circle / highlighted bar) by RM2 reading the hover signal —
flowing through the normal dirty scan.

### Legend

A legend is a normal layout row of swatch + series-name pairs (existing components). Clicking a
legend entry toggles a per-series `Signal(bool)` visibility flag; RM2's `render` skips hidden
series. This reuses button interaction (R31) and signals — no chart-specific event path.

### Selection (optional, bounded)

Click on a datum sets a selected-datum `Signal`; the app can bind to it. No box/lasso
selection in v2.

## Module location

```
src/13/interaction.zig    — hitTest, HitResult; hover/select signal wiring
src/13/legend.zig          — legend row built from existing components
docs/requirements/RM3_chart_interactivity.md
```

## Public API changes

```zig
// Module 13: HitResult, hitTest(); hover/visibility/selection exposed as Signals the app binds to.
```

## Behavioral contract

| Situation | Behavior |
|---|---|
| Mouse over a line near a point | Nearest datum hit-tested; tooltip shows formatted value |
| Mouse leaves plot area | Hover signal cleared; tooltip hidden; emphasis removed |
| Click legend entry | Series visibility signal toggles; chart re-renders without that series |
| Hovered bar/point | Emphasized via hover signal read in RM2 render (dirty-scan path) |
| Click a datum | Selected-datum signal set; app may bind to it |
| Tooltip value formatting | Uses RE0/RE1 per locale |

## Non-goals (DO NOT implement — INV-5.4)

- **No new interaction/event system** — all hover/click flows through M1-02 events + signals
  (INV-3.3).
- **No zoom/pan** of the plot area in v2.
- **No box/lasso/brush selection** — single-datum selection only.
- **No crosshair cursor mode** beyond a hovered-point emphasis.
- **No tooltip styling system** beyond the existing R7C tooltip.

## Acceptance criteria

1. Module 13 acceptance test: `hitTest` returns the correct nearest datum for known mouse
   positions (using `Scale.invert`).
2. Hover sets/clears the hover signal; the tooltip appears in the overlay layer with a
   correctly formatted value.
3. Legend click toggles series visibility through a signal; the hidden series disappears via
   the dirty scan (no tree rebuild).
4. Hovered-mark emphasis updates through the signal/dirty path only.
5. Visual + interaction: a demo chart shows working hover tooltips and a clickable legend.
