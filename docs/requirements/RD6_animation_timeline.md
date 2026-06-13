# RD6 — M14-01: Animation timeline

> Roadmap item: M14-01
> Depends on: M2-01 (Signal type — for marking elements dirty via subscribers)
> Read `00_constitution.md` before this file.

## Purpose

A minimal, principled animation model for the framework. An `AnimTimeline` drives a `f32`
value from 0→1 over a duration with an easing function. When the timeline is active, it marks
subscribed element indices dirty each frame so the layout + paint pipeline processes the
animated element. This is the foundation for all animation features in M14.

## What to build

### `AnimTimeline` struct

A new file at `src/app/anim_timeline.zig` with:

```zig
pub const Easing = enum {
    linear,
    ease_in,
    ease_out,
    ease_in_out,
};

pub const AnimTimeline = struct {
    /// Duration in frames (not milliseconds — aligns with the existing frame_count system).
    duration: u32,
    /// Elapsed frames since this timeline started animating.
    elapsed: u32 = 0,
    /// Current normalized progress [0.0, 1.0]. Read by the animation consumer.
    value: f32 = 0,
    /// True while the timeline is actively animating.
    /// Set to false when value reaches 1.0.
    running: bool = false,
    /// Easing function applied to the raw t = elapsed/duration.
    easing: Easing = .ease_in_out,
    /// Whether the timeline should loop (restart from 0 when it reaches 1.0).
    repeating: bool = false,
    /// Whether the timeline should reverse direction each cycle (ping-pong).
    /// Only meaningful when repeating is true.
    yoyo: bool = false,
    /// Direction for yoyo mode. True = playing forward, False = playing reverse.
    forward: bool = true,

    /// Start the timeline from the beginning. Sets running = true, elapsed = 0, forward = true.
    pub fn start(self: *AnimTimeline) void;

    /// Advance the timeline by one frame. Must be called once per rendered frame
    /// for each active timeline. Updates value to the eased progress.
    /// When finished (value >= 1.0 and not repeating): sets running = false.
    /// When repeating with yoyo: reverses direction at each endpoint.
    pub fn tick(self: *AnimTimeline) void;

    /// Reset the timeline to its initial state (elapsed = 0, value = 0, running = false).
    pub fn reset(self: *AnimTimeline) void;

    /// Return the raw (un-eased) progress t = elapsed / duration, clamped to [0, 1].
    fn rawProgress(self: *AnimTimeline) f32;
};
```

### Easing functions

Pure helper functions in the same file:

```zig
/// Linear: t unchanged.
pub fn easeLinear(t: f32) f32;

/// Ease-in (quadratic): t*t
pub fn easeIn(t: f32) f32;

/// Ease-out (quadratic): t*(2-t)
pub fn easeOut(t: f32) f32;

/// Ease-in-out (quadratic): 2*t*t for t<0.5, -1+(4-2*t)*t for t>=0.5
pub fn easeInOut(t: f32) f32;

/// Apply the selected easing function to t.
pub fn applyEasing(t: f32, easing: Easing) f32;
```

### Dirty-marking integration

`AnimTimeline` itself does NOT hold a subscriber list or dirty-bitset reference. Instead,
the *caller* (the per-frame tick code in the App layer, or a `Computed` signal) is responsible
for marking subscribed elements dirty after `tick()` returns a new value.

This design keeps `AnimTimeline` as a pure scalar animator with no dependency on the
element store, maintaining the data-orientation boundary (INV-3.1).

### Integration with the frame loop

`AnimTimeline` instances are stored on `AppInner` in an `ArrayListUnmanaged(AnimTimeline)`
collection. `AppInner.run()` / `runWithNav()` calls `tickAnimations()` once per rendered frame,
after advancing `frame_count`, which calls `tick()` on every active timeline and marks the
corresponding element indices dirty.

```zig
// In AppInner:
anim_timelines: std.ArrayListUnmanaged(AnimTimeline) = .{},

pub fn tickAnimations(self: *AppInner) void;
```

`tickAnimations` iterates all active timelines, calls `tick()`, and if `value` changed
since the previous frame, marks the associated element index dirty.

### Integration with `hasAnimatedElements`

Active timelines must keep the frame loop running (poll mode instead of wait mode).
`hasAnimatedElements` is extended to check for active timelines:

```zig
if (self.anim_timelines.items.len > 0) {
    for (self.anim_timelines.items) |tl| {
        if (tl.running) return true;
    }
}
```

### Module location

```
src/app/anim_timeline.zig   — AnimTimeline, Easing, easing functions
src/app/app.zig             — anim_timelines list, tickAnimations, hasAnimatedElements check
src/app/app_test.zig        — unit tests for AnimTimeline
```

## Non-goals (DO NOT implement — INV-5.4)

- **No interpolation between `ComputedStyle` values.** The timeline only drives a `f32` value.
  Style interpolation is M14-02.
- **No animation event callbacks** (on_start, on_complete). The animation system does not
  push events; applications poll via `value` (INV-3.3).
- **No parallel / sequenced timelines.** Only individual independent timelines. Sequencing is
  post-v1.
- **No keyframe-based animation.** Only 0→1 with a single easing function. Keyframes are post-v1.
- **No cubic bezier or custom easing.** Only the three quadratic variants plus linear.
- **No async / coroutine-driven animation.** All animation advances synchronously
  via `tickAnimations` in the frame loop.

## Acceptance criteria

1. `AnimTimeline` ticks advance `elapsed` and update `value` according to the easing function.
2. `value` reaches exactly `1.0` when `elapsed >= duration` (non-repeating), then
   `running` becomes `false`.
3. `repeating = true` timelines wrap back to `elapsed = 0` at the end and continue.
4. `yoyo = true` timelines reverse direction (play forward, then backward, then forward).
5. `start()` resets elapsed and sets `running = true`.
6. `reset()` sets `elapsed = 0`, `value = 0`, `running = false`.
7. `easeIn(0.5)` ≈ `0.25`; `easeOut(0.5)` ≈ `0.75`; `easeInOut(0.25)` ≈ `0.125`.
8. `hasAnimatedElements` returns `true` when any anim_timeline has `running = true`.
9. Active timelines keep the frame loop in poll mode (detected via `hasAnimatedElements`).
10. Unit tests cover all easing functions, boundary conditions (duration=0, elapsed overflow).

## Open questions

None. The design is a direct implementation of the roadmap description combined with existing
patterns (`frame_count`, `hasAnimatedElements`).
