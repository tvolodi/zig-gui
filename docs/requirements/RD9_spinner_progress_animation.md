# RD9 — M14-04: Spinner and progress animation via AnimTimeline

> Roadmap item: M14-04
> Depends on: M14-01 (AnimTimeline), M7-04 (ProgressBar / Spinner)
> Read `00_constitution.md` before this file.

## Purpose

Currently, the spinner rotation and indeterminate progress bar fill motion are hardcoded
frame-counter calculations in `buildDrawList` (using `scene.frame_count` directly). This
requirement replaces those hardcoded animations with proper `AnimTimeline` instances so
they are consistent with the framework's animation model and can benefit from features like
easing, repeat, and yoyo.

## What to build

### Spinner animation via AnimTimeline

Replace the hardcoded `phase_idx = (frame_count / 10) % 8` in the spinner rendering path
with an `AnimTimeline` that cycles through the 8 positions.

Each spinner element gets an `AnimTimeline` that:
- Has `duration = 80` (one full rotation = 8 positions x 10 frames per position = 80 frames).
- Uses `linear` easing (uniform rotation).
- Has `repeating = true` so it loops forever.

### Indeterminate progress bar via AnimTimeline

Replace the hardcoded `phase = frame_count % 120 / 120.0` with an `AnimTimeline`:

```zig
// Timeline for indeterminate progress bar:
const tl_idx = self.anim_timelines.items.len;
try self.anim_timelines.append(self.gpa, .{
    .duration = 120,
    .repeating = true,
    .easing = .linear,
});
```

The rendering reads `timeline.value` (0→1 each 120 frames) and uses it to position the
indeterminate band.

### Frame loop integration

`AnimTimeline.tick()` is already called by `AppInner.tickAnimations()` each frame (M14-01).
No additional integration needed — the recurring timelines advance automatically.

The `ProgressState.anim_timeline_idx` links the widget to its timeline. During widget
instantiation in `Scene.instantiate`, if a spinner or indeterminate progress bar is created,
the app layer (or a callback) allocates the timeline and stores the index.

### Timeline allocation

The app layer needs to associate timelines with widgets. The simplest approach: after
`Scene.instantiate`, iterate the element tree and for each `.spinner` or `.progress_bar`
element, allocate a timeline and store the index in `ProgressState.anim_timeline_idx`.

The spinner currently advances one tick EVERY 10 frames (`scene.frame_count / 10`), so 8
positions x 10 = 80 frames per full rotation. The duration=80 timeline with linear easing
matches this, starting at value=0 and reaching 1.0 after 80 ticks.

The indeterminate progress bar currently advances through 120 frames. The duration=120
timeline with linear easing matches this exactly.

Both timelines have `repeating = true` so they loop forever and are auto-started after
creation (via `allocateTimeline` which calls `.start()`).

```zig
// In AppInner, after scene instantiation:
pub fn initAnimationTimelines(self: *AppInner) !void {
    for (0..self.scene._kind.items.len) |i| {
        const idx = @as(u32, @intCast(i));
        if (idx >= self.scene._progress_state.items.len) continue;
        switch (self.scene.kindOfIdx(idx)) {
            .spinner => {
                const tl_idx = try self.allocateTimeline(.{
                    .duration = 80,  // 80 frames = one full rotation
                    .repeating = true,
                    .easing = .linear,
                });
                self.scene.progressStateOf(idx).anim_timeline_idx = tl_idx;
            },
            .progress_bar => {
                const ps = self.scene.progressStateOf(idx);
                if (ps.indeterminate) {
                    const tl_idx = try self.allocateTimeline(.{
                        .duration = 120,  // 120 frames per cycle
                        .repeating = true,
                        .easing = .linear,
                    });
                    ps.anim_timeline_idx = tl_idx;
                }
            },
            else => {},
        }
    }
}
```

When `scene.reset()` is called (hot-reload, screen navigation), all timelines are re-created
by calling `initAnimationTimelines()` again. The old timelines remain in the array but are
no longer referenced.

### Sync animation state to rendering

Since `buildDrawList` runs in module 09 and `anim_timelines` lives on `AppInner` (module
app.zig), and module 09 cannot import from app.zig upward, we cannot pass the timelines
directly. Instead, we add a `syncAnimationState()` method to `AppInner` that copies the
timeline value into `ProgressState.anim_frame_value` each frame, after `tickAnimations()`
but before `buildDrawList()`:

```zig
fn syncAnimationState(self: *AppInner) void {
    for (0..self.scene._kind.items.len) |i| {
        const idx = @as(u32, @intCast(i));
        if (idx >= self.scene._progress_state.items.len) continue;
        const kind = self.scene.kindOfIdx(idx);
        if (kind != .spinner and kind != .progress_bar) continue;
        const ps = self.scene.progressStateOf(idx);
        if (ps.anim_timeline_idx == 0xFFFFFFFF) continue;
        if (ps.anim_timeline_idx >= self.anim_timelines.items.len) continue;
        const tl = self.anim_timelines.items[ps.anim_timeline_idx];
        ps.anim_frame_value = tl.value;
    }
}
```

`ProgressState` gains two new fields:

```zig
pub const ProgressState = struct {
    value: f32 = 0,
    indeterminate: bool = false,
    anim_frame_value: f32 = 0,
    anim_timeline_idx: u32 = 0xFFFFFFFF,
};
```

### HasAnimatedElements simplification

With `AnimTimeline` driving spinner and progress animations, `hasAnimatedElements` can simply
check if any timeline has `running = true`. The per-kind check for spinner/progress becomes
unnecessary — the timeline system naturally covers it.

```zig
fn hasAnimatedElements(self: *const AppInner) bool {
    for (self.anim_timelines.items) |tl| {
        if (tl.running) return true;
    }
    if (self.tooltip_manager.isPending()) return true;
    return false;
}
```

However, the existing `hasAnimatedElements` function takes only `Scene` + `TooltipManager`.
The signature changes to accept `*const AppInner` or the anim_timelines slice.

### Module location

```
src/07/types.zig                — ProgressState.anim_timeline_idx
src/09/types.zig                — read timeline value instead of frame_count for spinner/progress
src/app/app.zig                 — initAnimationTimelines, hasAnimatedElements update, timeline-based rendering
src/app/anim_timeline.zig      — no changes (timeline already supports repeating)
```

## Non-goals (DO NOT implement — INV-5.4)

- **No configurable spinner speed** — one speed (80 frames per full rotation) hardcoded in v1.
- **No easing on spinner** — linear only; a spinning indicator should be uniform.
- **No programmatic timeline control** — the developer does not create or manage timeline
  instances directly; allocation is automatic during instantiation.

## Acceptance criteria

1. Spinner rotation uses an `AnimTimeline` with `duration = 80, repeating = true, linear`.
2. Indeterminate progress bar uses an `AnimTimeline` with `duration = 120, repeating = true, linear`.
3. After `scene.reset()` + re-instantiation, timelines are correctly re-allocated.
4. `hasAnimatedElements` returns `true` when any timeline has `running = true`.
5. Visual behavior matches the current hardcoded implementation (identical before/after).
6. Unit tests verify that ProgressState.anim_timeline_idx is set correctly after instantiation.
