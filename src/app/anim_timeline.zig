//! M14-01 — Animation timeline and easing functions (RD6).
//!
//! A minimal animation model: AnimTimeline drives a f32 value from 0→1 over a
//! duration (in frames) with an easing function. This is a pure scalar animator
//! with no dependency on the element store, preserving the data-orientation
//! boundary (INV-3.1).

const std = @import("std");

/// Easing function selector.
pub const Easing = enum {
    linear,
    ease_in,
    ease_out,
    ease_in_out,
};

/// A single animation timeline.
///
/// Call `tick()` once per frame to advance the animation. Read `value` to
/// get the current eased progress as a f32 in [0, 1].
///
/// The timeline does NOT hold a subscriber list or dirty-bitset reference.
/// The caller (typically `AppInner.tickAnimations`) is responsible for marking
/// subscribed elements dirty after `tick()` produces a new value.
pub const AnimTimeline = struct {
    /// Duration in frames (not milliseconds).
    duration: u32,
    /// Elapsed frames since this timeline started animating.
    elapsed: u32 = 0,
    /// Current normalized progress [0.0, 1.0]. Read by the animation consumer.
    value: f32 = 0,
    /// True while the timeline is actively animating.
    /// Set to false when value reaches 1.0 (non-repeating).
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

    /// Start the timeline from the beginning.
    /// Sets running = true, elapsed = 0, forward = true, value = 0.
    pub fn start(self: *AnimTimeline) void {
        self.running = true;
        self.elapsed = 0;
        self.forward = true;
        self.value = 0;
    }

    /// Advance the timeline by one frame.
    ///
    /// Must be called once per rendered frame for each active timeline.
    /// Updates `value` to the eased progress.
    ///
    /// When finished (value >= 1.0 and not repeating): sets running = false.
    /// When repeating with yoyo: reverses direction at each endpoint.
    /// When duration == 0: immediately sets value = 1.0, running = false.
    pub fn tick(self: *AnimTimeline) void {
        if (!self.running) return;

        // Duration-zero: instant completion.
        if (self.duration == 0) {
            self.value = 1.0;
            self.running = false;
            return;
        }

        self.elapsed += 1;

        const raw = self.rawProgress();

        if (self.yoyo and !self.forward) {
            // Playing reverse in yoyo mode.
            self.value = 1.0 - applyEasing(raw, self.easing);
        } else {
            self.value = applyEasing(raw, self.easing);
        }

        // Check for completion (raw progress >= 1.0).
        if (raw >= 1.0) {
            if (self.repeating) {
                if (self.yoyo) {
                    self.forward = !self.forward;
                }
                self.elapsed = 0;
            } else {
                self.running = false;
                self.value = 1.0;
            }
        }
    }

    /// Reset the timeline to its initial state.
    pub fn reset(self: *AnimTimeline) void {
        self.elapsed = 0;
        self.value = 0;
        self.running = false;
    }

    /// Return the raw (un-eased) progress t = elapsed / duration, clamped to [0, 1].
    fn rawProgress(self: *AnimTimeline) f32 {
        const t = @as(f32, @floatFromInt(self.elapsed)) / @as(f32, @floatFromInt(self.duration));
        return std.math.clamp(t, 0.0, 1.0);
    }
};

// ---------------------------------------------------------------------------
// Easing functions (all quadratic)
// ---------------------------------------------------------------------------

/// Linear: t unchanged.
pub fn easeLinear(t: f32) f32 {
    return t;
}

/// Ease-in (quadratic): t*t
pub fn easeIn(t: f32) f32 {
    return t * t;
}

/// Ease-out (quadratic): t*(2-t)  =  1 - (1-t)*(1-t)
pub fn easeOut(t: f32) f32 {
    return t * (2.0 - t);
}

/// Ease-in-out (quadratic):
///   t < 0.5: 2*t*t
///   t >= 0.5: -1 + (4-2*t)*t
pub fn easeInOut(t: f32) f32 {
    if (t < 0.5) {
        return 2.0 * t * t;
    } else {
        return -1.0 + (4.0 - 2.0 * t) * t;
    }
}

/// Apply the selected easing function to t.
pub fn applyEasing(t: f32, easing: Easing) f32 {
    return switch (easing) {
        .linear => easeLinear(t),
        .ease_in => easeIn(t),
        .ease_out => easeOut(t),
        .ease_in_out => easeInOut(t),
    };
}
