# RDA — M14-05: Reduced-motion respect

> Roadmap item: M14-05
> Depends on: M14-01 (AnimTimeline)
> Read `00_constitution.md` before this file.

## Purpose

Users with vestibular disorders or motion sensitivity can experience discomfort from UI
animations. This requirement adds a `prefer_reduced_motion: bool` flag on `AppInner` that
disables all `AnimTimeline` playback. When set, all timeline-based animations jump to their
end state instantly.

## What to build

### Flag on `AppInner`

```zig
pub const AppInner = struct {
    // ...existing fields...

    /// When true, all animation timelines are disabled.
    /// AnimTimeline.tick() is a no-op, and enter/exit animations complete instantly.
    prefer_reduced_motion: bool = false,
};
```

### Integration with `AnimTimeline.tick()`

`AnimTimeline.tick()` remains a pure function (no dependency on AppInner). Instead, the
integration layer (`tickAnimations` in AppInner) checks the flag:

```zig
pub fn tickAnimations(self: *AppInner) void {
    if (self.prefer_reduced_motion) {
        // When reduced motion is preferred, complete all active timelines instantly
        // and stop them.
        for (&self.anim_timelines.items) |*tl| {
            if (tl.running) {
                tl.elapsed = tl.duration;
                tl.value = 1.0;
                tl.running = false;
            }
        }
        return;
    }
    for (&self.anim_timelines.items) |*tl| {
        if (tl.running) tl.tick();
    }
}
```

This ensures that when reduced motion is enabled:
- Transitions jump to their final value (M14-02).
- Enter animations jump to "fully visible" (M14-03).
- Exit animations jump to "fully hidden" (M14-03).
- Spinner/progress animations stop at their current position (M14-04).

### Enter/exit interaction

For exit animations with `prefer_reduced_motion`, the pending_hidden element is set to hidden
immediately (no animation delay). Similarly, enter animations snap the element visible
instantly.

### Setter

```zig
pub fn setReducedMotion(self: *AppInner, enabled: bool) void {
    self.prefer_reduced_motion = enabled;
}
```

### Integration with enter/exit (M14-03)

In the M14-03 visibility change interception path, when `prefer_reduced_motion` is true,
the enter/exit handler skips creating timelines and immediately shows/hides the element:

```zig
fn setHiddenWithAnimation(self: *AppInner, idx: u32, hidden: bool) void {
    const style = self.scene.styleOf(idx);
    if (self.prefer_reduced_motion or !style.enter_exit.animate_in or !style.enter_exit.animate_out) {
        self.scene.setHidden(idx, hidden);
        return;
    }
    // ...start animation timeline, defer actual setHidden...
}
```

### Future integration with OS settings

In v2, `prefer_reduced_motion` could be read from the OS accessibility settings at startup.
This is NOT implemented in v1 — the flag is set programmatically via `setReducedMotion`.

### Demo / integration

The demo app adds a keyboard shortcut (Ctrl+Shift+M or F3) to toggle reduced motion, so the
feature can be demonstrated and tested.

### Module location

```
src/app/app.zig           — prefer_reduced_motion flag, tickAnimations reduced-motion path,
                            setReducedMotion, setHiddenWithAnimation integration
src/app/anim_timeline.zig — no changes needed (timeline is pure; the check is in tickAnimations)
```

## Non-goals (DO NOT implement — INV-5.4)

- **No OS-level reduced-motion detection** — reading the OS accessibility setting is
  M16-04 (OS native color-scheme detection) territory and is post-v1.
- **No per-element override** — reduced motion is an app-wide setting.
- **No animation-frame elimination** — the frame loop continues to run normally; only
  the timeline values jump to end state. This avoids complexity with the poll/wait decision.
- **No "reduce transparency" or other accessibility preferences** — only motion.

## Acceptance criteria

1. Setting `prefer_reduced_motion = true` causes all active timelines to complete instantly.
2. After setting reduced motion, no new timeline animations produce visible intermediate frames.
3. Enter animations snap the element visible immediately when reduced motion is on.
4. Exit animations snap the element hidden immediately when reduced motion is on.
5. Setting `prefer_reduced_motion = false` restores normal animation behavior.
6. Unit tests verify `tickAnimations` with `prefer_reduced_motion = true` sets all timelines
   to `value = 1.0, running = false`.
7. Existing animation behavior is unchanged when `prefer_reduced_motion = false` (the default).
