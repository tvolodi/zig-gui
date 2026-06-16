# RN11 — Chart injection slot (chart_cmds) in AppInner

> Status: `planned` — Milestone 27 extension.
> Blocking: TailAdmin Ecommerce demo screen (Screen 12) — charts must render BETWEEN the main
> scene pass and the overlay layer to achieve correct Z-order (above card backgrounds but below
> tooltips and dropdowns).
> Read `docs/specs/00_constitution.md` before this file.
> Use project-relative paths only. Never use absolute Windows paths starting with `c:\`.

## 1. Problem

`Chart.render()` (module 13) produces `DrawCommand` slices. These must be submitted to the GPU
in a specific Z-order:
1. Main scene elements (card backgrounds, text labels, separators)
2. **Chart visuals** (bars, area fills, gauge arcs, map polygons)
3. Overlay (tooltips, dropdowns, toasts)

Currently there is no hook between (1) and (3). Charts cannot be rendered in module 09
(`buildDrawList`) because that would create an upward import from module 09 to module 13,
violating INV-3.4. Using the existing `overlay` layer puts charts ABOVE tooltips (wrong Z-order)
and on top of text elements that should appear above chart fills (wrong).

## 2. What to build

Add a **chart_cmds** injection field to `AppInner` in `src/app/app.zig`. The chart_cmds slice
is populated by `per_frame_app_fn` and consumed (concatenated into the main command stream)
by the frame render loop — between main draw list and overlay flattening.

### 2a. AppInner field

```zig
/// RN11 — Per-frame chart draw commands injected between main and overlay passes.
/// Allocated and populated by per_frame_app_fn (e.g., the screen's renderCharts fn).
/// Freed by AppInner at the end of each frame; must not be retained across frames.
chart_cmds: ?[]DrawCommand = null,
```

### 2b. Render loop change

In `src/app/app.zig`, in BOTH `run()` and `runWithNav()`, after `per_frame_app_fn` runs and
before the final `all_cmds2` concatenation, add the chart_cmds concatenation step.

Current concatenation (simplified):
```
all_cmds = main_cmds + overlay_cmds
all_cmds2 = all_cmds + debug_cmds + hud_cmds
```

New concatenation:
```
all_cmds = main_cmds + chart_cmds + overlay_cmds
all_cmds2 = all_cmds + debug_cmds + hud_cmds
```

Where `chart_cmds` is `self.chart_cmds orelse &[_]DrawCommand{}`.

Deallocation: after consuming `chart_cmds`, free and clear it:
```zig
if (self.chart_cmds) |cc| { self.gpa.free(cc); self.chart_cmds = null; }
```

This must happen even if `chart_cmds.len == 0` (i.e., if `per_frame_app_fn` set it to an
empty slice) to avoid double-free.

Use `defer { ... }` or explicit free AFTER the GPU submission but BEFORE end of frame scope.

### 2c. Screen usage pattern

A screen wishing to render charts:
1. In `build()`: creates placeholder `Column`/`Card` NodeDescs with a distinct text attribute
   (e.g., `text = "CHART:BAR"`) to occupy layout space. The placeholder is just an empty
   rect — no visible rendering.
2. In a per-frame function registered via `app._inner.per_frame_app_fn`: scans
   `ai.scene.elements.layout.items[idx].computed` for the placeholder's rect, builds a
   `ChartFrame` from it, calls `chart.render(frame, &cmds, alloc)`, then sets:
   `ai.chart_cmds = cmds.toOwnedSlice(alloc) catch null;`
3. If multiple charts: accumulate all commands into a single list before assigning to
   `ai.chart_cmds`.

## 3. Acceptance criteria

- `zig build` exits 0.
- When `per_frame_app_fn` sets `ai.chart_cmds` to a non-empty slice, those commands appear
  between the main and overlay draw commands in the submitted frame.
- At end of each frame, `ai.chart_cmds` is `null` (freed).
- No existing screen is affected (default `chart_cmds = null` means no change).

## 4. Non-goals

- No new widget kind in module 07 (that remains an optional follow-on: RN_CHART_WIDGET).
- No automatic chart positioning — the screen code is responsible for computing ChartFrame
  from the placeholder element's `computed` rect.
- No multiple chart_cmds slots — all charts for a frame go into the same slice.
