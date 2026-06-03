# R73 — M7-04: Progress bar / spinner

> Roadmap item: M7-04  
> Depends on: M4 (renderer complete — `buildDrawList`), M1-04 (frame pacing — for spinner animation)  
> Read `00_constitution.md` before this file.

## Purpose

Two display-only widgets: a `<ProgressBar>` shows a filled track from 0–100 %, and a
`<Spinner>` shows a rotating arc that indicates indeterminate loading. Neither has
interaction. The progress bar is purely data-driven (value from state). The spinner animates
via a `frame_time_ms: u64` counter incremented each frame.

## What to build

### `ProgressBar` widget kind and state

```zig
pub const WidgetKind = enum { /* ...existing... */ progress_bar, spinner };

// tagToKind: "ProgressBar" → .progress_bar, "Spinner" → .spinner
// defaultLayoutFor: .progress_bar → { .display = .block, .height = .{ .px = 8 } }
// defaultLayoutFor: .spinner → { .display = .block, .width = .{ .px = 24 }, .height = .{ .px = 24 } }

pub const ProgressState = struct {
    value:         f32  = 0,   // 0.0–1.0 (not 0–100; normalized)
    indeterminate: bool = false,
};

pub const Scene = struct {
    _progress_state: std.ArrayListUnmanaged(ProgressState) = .empty,

    pub fn progressStateOf(self: *Scene, idx: u32) *ProgressState

    /// Set progress value (clamped to [0, 1]) and mark dirty.
    pub fn setProgress(self: *Scene, idx: u32, value: f32) void
};
```

Markup:

```html
<ProgressBar value="0.7" class="w-full" />
<ProgressBar indeterminate="true" class="w-full" />
<Spinner class="w-6 h-6" />
```

The `value` and `indeterminate` literal attrs are parsed in `instantiate`.

### `ProgressBar` rendering

```zig
// Track:
try cmds.append(.{ .filled_rect = .{
    .rect = layout_rect, .color = tokens.bg_surface, .radius = layout_rect.h / 2 } });
// Fill:
if (!state.indeterminate) {
    const fill = Rect{ .x = layout_rect.x, .y = layout_rect.y,
                       .w = layout_rect.w * std.math.clamp(state.value, 0, 1),
                       .h = layout_rect.h };
    try cmds.append(.{ .filled_rect = .{
        .rect = fill, .color = tokens.accent, .radius = layout_rect.h / 2 } });
} else {
    // Indeterminate: animated sliding fill.
    // Phase derived from App.frame_count (passed via tokens or a new buildDrawList param).
    const phase: f32 = @as(f32, @floatFromInt(frame_count % 120)) / 120.0;
    const fill_w = layout_rect.w * 0.4;
    const fill_x = layout_rect.x - fill_w + (layout_rect.w + fill_w) * phase;
    const fill = Rect{ .x = fill_x, .y = layout_rect.y,
                       .w = fill_w,  .h = layout_rect.h };
    try cmds.append(.{ .filled_rect = .{
        .rect = fill, .color = tokens.accent, .radius = layout_rect.h / 2 } });
}
```

`frame_count` is a `u64` on `App` incremented each frame. `buildDrawList` receives it as a
parameter:

```zig
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    glyph_atlas: *GlyphAtlas,
    image_atlas: *const ImageAtlas,
    family: *const FontFamily,
    tokens: Tokens,
    frame_count: u64,  // NEW — for indeterminate / spinner animation
) error{OutOfMemory}![]DrawCommand
```

For deterministic (non-animated) elements, `frame_count` has no effect.

**Frame pacing for animations:** indeterminate progress and spinner animations require the
frame loop to run continuously rather than waiting for input. When any `progress_bar` with
`indeterminate = true` or any `spinner` exists in the scene, `App.run()` uses
`platform.pollEvents()` (non-blocking) rather than `platform.waitEvents()` (blocking). This
is implemented by adding a `has_animated_elements(scene)` check before the
`waitEvents`/`pollEvents` branch.

### `Spinner` rendering

The spinner is a partial arc drawn as `N=8` thin `filled_rect` "tick marks" arranged in a
circle, with brightness fading from the "head" of the arc. Each tick is a short rect rotated
at `i * (360°/N)`:

```zig
const N = 8;
const cx = layout_rect.x + layout_rect.w / 2;
const cy = layout_rect.y + layout_rect.h / 2;
const r  = layout_rect.w * 0.35;    // radius to tick centers
const tw = layout_rect.w * 0.08;    // tick width
const th = layout_rect.w * 0.22;    // tick height

const phase_idx: u32 = @intCast(frame_count % N);

var i: u32 = 0;
while (i < N) : (i += 1) {
    const angle = @as(f32, @floatFromInt(i)) * (std.math.tau / N);
    const age   = @intCast(u32, (i + N - phase_idx) % N);  // 0 = newest tick
    const alpha = @as(u8, @intFromFloat(255.0 * @as(f32, @floatFromInt(N - age)) / N));

    // Position: tick center is (cx + r*cos, cy + r*sin)
    // For simplicity in the absence of rotation transforms, approximate each tick
    // as a small square at the tick position (rotation ignored — acceptable for v1).
    const tx = cx + r * @cos(angle) - tw / 2;
    const ty = cy + r * @sin(angle) - th / 2;
    try cmds.append(.{ .filled_rect = .{
        .rect   = .{ .x = tx, .y = ty, .w = tw, .h = th },
        .color  = .{ .r = tokens.accent.r, .g = tokens.accent.g,
                     .b = tokens.accent.b, .a = alpha },
        .radius = tw / 2,
    }});
}
```

The spinner must be continuously dirty (mark itself dirty at frame end) so the frame loop
doesn't idle while it is visible. `has_animated_elements` detects this.

### `has_animated_elements`

```zig
fn has_animated_elements(scene: *const Scene) bool {
    var i: u32 = 0;
    while (i < scene.elements.layout.items.len) : (i += 1) {
        if (scene._hidden.items[i]) continue;
        switch (scene._kind.items[i]) {
            .spinner => return true,
            .progress_bar => {
                if (scene.progressStateOf(i).indeterminate) return true;
            },
            else => {},
        }
    }
    return false;
}
```

### Module location

```
src/07/types.zig   — WidgetKind.progress_bar/.spinner, ProgressState, setProgress, progressStateOf
src/09/types.zig   — buildDrawList frame_count param, ProgressBar/Spinner rendering
src/app/app.zig    — frame_count increment, has_animated_elements check in event loop
docs/requirements/R73_progress_spinner.md
```

## Non-goals (DO NOT implement — INV-5.4)

- **No circular progress bar** — arc rendering via SDF or GPU clipping is post-v1.
- **No animated transitions** for determinate bar fill — instantaneous value updates only.
- **No label inside bar** — plain track only.
- **No custom spinner shape** — 8-tick approximation is the v1 design.
- **No progress-change callbacks** — display-only; INV-3.3.

## Acceptance criteria

1. `zig build test-07` passes. `setProgress` clamps to [0,1] and marks dirty. `<Spinner/>`
   and `<ProgressBar value="0.5"/>` instantiate without error.
2. `zig build test-09-unit` passes. `buildDrawList` for a 50 % progress bar emits a fill
   rect of width = 50 % of track width. Frame 0 spinner emits 8 rects with decreasing alpha.
3. Integration: indeterminate bar and spinner animate continuously. Setting progress to 0.8
   renders an 80 % fill. Checklist ticked.
