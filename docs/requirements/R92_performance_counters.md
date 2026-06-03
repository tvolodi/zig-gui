# R92 — M9-03: Performance counters

> Roadmap item: M9-03  
> Depends on: M1-01 (App main loop), M9-01 (Debug overlay)  
> Read `00_constitution.md` before this file.

## Purpose

Measure and display three per-frame counters — frame time, draw command count, and dirty
element count — inside the debug overlay so the developer can see rendering cost at a glance.

After this item ships, pressing F1 shows not only element bounds but also a HUD panel in
the top-right corner with:

```
frame  4.2 ms   (237 fps)
cmds   312
dirty  7 / 1024
```

---

## Motivation

`buildDrawList` produces up to thousands of commands per frame; there is currently no way to
know how many. A slider being dragged might mark 3 elements dirty — or 300 if something is
wrong. The counters expose this at zero developer effort.

---

## What to build

### 1. `FrameCounters` struct

```zig
pub const FrameCounters = struct {
    /// Frame time in milliseconds (wall-clock from previous beginFrame to current endFrame).
    frame_ms: f32 = 0,
    /// Number of DrawCommand entries submitted to the last drawFrame call (main + overlay combined).
    cmd_count: u32 = 0,
    /// Number of set bits in ElementStore.dirty at the START of the last frame
    /// (before the dirty clear at frame end).
    dirty_count: u32 = 0,
    /// Total live element count (elements with a valid generation).
    element_count: u32 = 0,
};
```

`FrameCounters` is a plain data struct — no methods, no allocation.

### 2. `PerfHud` struct

```zig
pub const PerfHud = struct {
    counters: FrameCounters = .{},
    /// Ring buffer of the last N frame times for smoothing.
    frame_ms_history: [16]f32 = [_]f32{0} ** 16,
    history_idx: u8 = 0,

    pub fn init() PerfHud;

    /// Record one frame's worth of counters. Updates the ring buffer.
    pub fn record(self: *PerfHud, c: FrameCounters) void;

    /// Smoothed frame time: average of the ring buffer.
    pub fn smoothFrameMs(self: *const PerfHud) f32;

    /// Produce the HUD draw list.  Returned slice is owned by `alloc`; caller frees it.
    /// Returns empty slice when debug overlay is disabled.
    pub fn buildHudDrawList(
        self: *const PerfHud,
        alloc: std.mem.Allocator,
        enabled: bool,
        viewport_w: f32,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
    ) ![]DrawCommand;
};
```

`record` is called once per frame after `endFrame`. It stores the new `FrameCounters` into
`self.counters` and pushes `c.frame_ms` into the ring buffer.

`smoothFrameMs` returns the arithmetic mean of the non-zero entries in the ring buffer.
If all entries are zero (first frame), returns `0`.

### 3. HUD panel layout

The HUD is drawn in the **top-right corner** of the viewport, 12 px from each edge:

```
┌─────────────────────────────┐
│ frame  4.2 ms   (237 fps)   │
│ cmds   312                  │
│ dirty  7 / 1024             │
└─────────────────────────────┘
```

Draw commands emitted by `buildHudDrawList`:

1. `filled_rect` background: `tokens.bg_raised` with `a = 210`, radius 4.
2. `border_rect` outline: `tokens.border_default`, width 1 px, radius 4.
3. Glyph commands for three text lines, font size 11 px, color `tokens.text_body`.

Line contents:

| Line | Content |
|---|---|
| 1 | `frame  <smoothed_ms> ms   (<fps> fps)` where fps = `round(1000 / smoothed_ms)` when `smoothed_ms > 0`, else `--- fps` |
| 2 | `cmds   <cmd_count>` |
| 3 | `dirty  <dirty_count> / <element_count>` |

Number formatting:
- Frame ms: one decimal place (e.g. `4.2`)
- FPS: integer (e.g. `237`)
- Counts: plain integer

The panel width is fixed at 200 px. Height is `3 * line_height + 2 * padding` where
`line_height = font.metrics(11).ascent + font.metrics(11).descent + font.metrics(11).line_gap`
and `padding = 8 px` top and bottom.

The panel's top-right corner is placed 12 px from the top and 12 px from the right of the
viewport:

```
panel_x = viewport_w - panel_w - 12
panel_y = 12
```

### 4. Frame timing

`AppInner` gains two new fields:

```zig
perf_hud: PerfHud = PerfHud.init(),
_frame_start_ns: i128 = 0,
```

In `App.run` / `App.runWithNav`:

- At the top of the frame loop, immediately after the dirty check passes (GPU work is about
  to happen), record the timestamp: `self._frame_start_ns = std.time.nanoTimestamp()`.
- After `backend.endFrame()`, compute the elapsed time:
  ```zig
  const elapsed_ns = std.time.nanoTimestamp() - self._frame_start_ns;
  const elapsed_ms: f32 = @as(f32, @floatFromInt(elapsed_ns)) / 1_000_000.0;
  ```
- Count dirty elements before the `dirty.unsetAll()` call:
  ```zig
  const dirty_count = self.scene.elements.dirty.count();
  ```
- Count live elements (elements with valid generation):
  ```zig
  var live: u32 = 0;
  for (self.scene.elements.gen.items) |g| if (g != 0) { live += 1; };
  ```
- Count total draw commands: `all_cmds.len`.
- Call `self.perf_hud.record(.{ .frame_ms = elapsed_ms, .cmd_count = ..., .dirty_count = ..., .element_count = ... })`.

The `dirty_count` is captured after `syncPseudoStates` and before `dirty.unsetAll()`.

### 5. Integration into `AppInner.run`

The HUD draw list is built after the debug overlay draw list and concatenated in this order:

```
all_cmds = main_cmds + overlay_cmds + debug_bounds_cmds + hud_cmds
```

`buildHudDrawList` receives `app.debug_overlay.enabled` — the HUD is only shown when the
debug overlay is active. It shares the same F1 toggle.

---

## Module location

```
src/app/perf_hud.zig           — FrameCounters, PerfHud
src/app/perf_hud_test.zig      — acceptance tests (headless)
docs/requirements/R92_performance_counters.md
```

`src/app/types.zig` re-exports `FrameCounters` and `PerfHud`.

---

## Invariant interactions

- **INV-2.3**: `PerfHud` emits `DrawCommand` values only. No GPU state.
- **INV-4.3**: All colors sourced from `Tokens`. No hex literals.
- **INV-3.3**: The HUD does NOT mark any element dirty. It reads counters; it does not
  drive the dirty mechanism.

---

## Non-goals (DO NOT implement — INV-5.4)

- NO per-element timing (how long did layouting element N take).
- NO GPU timing queries (Vulkan timestamp queries are a separate concern).
- NO history graph / sparkline — three numbers only.
- NO logging to file — the HUD is display-only; `stderr` is the dev's responsibility.
- NO separate FPS cap or frame limiter — that remains `M1-04` (vsync).

---

## Acceptance criteria

The module is done when:

1. `zig build test-perf-hud` passes all tests in `src/app/perf_hud_test.zig`.
2. `PerfHud.init()` returns a struct with all-zero history.
3. `record` with `frame_ms = 8.0` repeated 16 times → `smoothFrameMs()` returns `8.0`.
4. `smoothFrameMs()` returns `0` when the history buffer is all-zero.
5. FPS is `round(1000 / 8.0) = 125` when smooth frame ms is 8.0.
6. `buildHudDrawList` with `enabled = false` returns an empty slice.
7. `buildHudDrawList` with `enabled = true` returns a non-empty slice (at least one
   `filled_rect` + one `border_rect` + three glyph groups).
8. Panel x/y positions are correct for a 1280×800 viewport: `x = 1280 - 200 - 12 = 1068`,
   `y = 12`.
9. Frame timing is recorded in the live run (verified by checking `perf_hud.counters.frame_ms
   > 0` after one frame in the integration smoke test).
10. The checklist for this item is fully ticked.

---

## Edge cases (each has a test)

- First frame (all history zero) — `smoothFrameMs()` returns `0`; line shows `--- fps`.
- `dirty_count = 0` (idle frame, skipped GPU work) — counters retain previous frame's values;
  `record` is NOT called on skipped frames (no GPU work means no timing to report).
- `cmd_count` exceeds 65536 (theoretical max) — displayed as plain integer, no truncation.
- Very fast frame (< 0.1 ms) — `fps` is computed and displayed without division by zero
  (guarded: if `smoothed_ms < 0.001`, display `--- fps`).
