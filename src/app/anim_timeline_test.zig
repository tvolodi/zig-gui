//! M14-01 — AnimTimeline and easing functions unit tests (RD6).
//!
//! Covers all easing functions, timeline state machine states (start, tick, reset),
//! boundary conditions (duration=0, repeating, yoyo), and the applyEasing dispatch.
//! Run via: zig test src/app/anim_timeline_test.zig
//! All tests are deterministic: no random, no wall-clock time, no GPU.

const std = @import("std");
const testing = std.testing;
const anim = @import("anim_timeline.zig");

// ===========================================================================
// Easing function unit tests
// ===========================================================================

test "easeLinear returns t unchanged" {
    try testing.expectEqual(@as(f32, 0.0), anim.easeLinear(0.0));
    try testing.expectEqual(@as(f32, 0.25), anim.easeLinear(0.25));
    try testing.expectEqual(@as(f32, 0.5), anim.easeLinear(0.5));
    try testing.expectEqual(@as(f32, 0.75), anim.easeLinear(0.75));
    try testing.expectEqual(@as(f32, 1.0), anim.easeLinear(1.0));
}

test "easeIn quadratic" {
    try testing.expectEqual(@as(f32, 0.0), anim.easeIn(0.0));
    try testing.expectEqual(@as(f32, 1.0), anim.easeIn(1.0));
    // easeIn(0.5) = 0.5 * 0.5 = 0.25
    try testing.expectApproxEqAbs(@as(f32, 0.25), anim.easeIn(0.5), 0.001);
    // easeIn(0.25) = 0.25 * 0.25 = 0.0625
    try testing.expectApproxEqAbs(@as(f32, 0.0625), anim.easeIn(0.25), 0.001);
}

test "easeOut quadratic" {
    try testing.expectEqual(@as(f32, 0.0), anim.easeOut(0.0));
    try testing.expectEqual(@as(f32, 1.0), anim.easeOut(1.0));
    // easeOut(0.5) = 0.5 * (2.0 - 0.5) = 0.75
    try testing.expectApproxEqAbs(@as(f32, 0.75), anim.easeOut(0.5), 0.001);
    // easeOut(0.25) = 0.25 * (2.0 - 0.25) = 0.4375
    try testing.expectApproxEqAbs(@as(f32, 0.4375), anim.easeOut(0.25), 0.001);
}

test "easeInOut symmetric" {
    try testing.expectEqual(@as(f32, 0.0), anim.easeInOut(0.0));
    try testing.expectEqual(@as(f32, 1.0), anim.easeInOut(1.0));
    // easeInOut(0.5) = 2*0.5*0.5 = 0.5
    try testing.expectApproxEqAbs(@as(f32, 0.5), anim.easeInOut(0.5), 0.001);
    // easeInOut(0.25) = 2*0.25*0.25 = 0.125
    try testing.expectApproxEqAbs(@as(f32, 0.125), anim.easeInOut(0.25), 0.001);
    // easeInOut(0.75) = -1 + (4 - 2*0.75)*0.75 = -1 + (4 - 1.5)*0.75 = -1 + 2.5*0.75 = -1 + 1.875 = 0.875
    try testing.expectApproxEqAbs(@as(f32, 0.875), anim.easeInOut(0.75), 0.001);
    // Symmetry check
    try testing.expectApproxEqAbs(
        anim.easeInOut(0.3),
        1.0 - anim.easeInOut(0.7),
        0.001,
    );
}

// ===========================================================================
// applyEasing dispatch
// ===========================================================================

test "applyEasing dispatches correctly" {
    const t: f32 = 0.5;
    try testing.expectApproxEqAbs(anim.easeLinear(t), anim.applyEasing(t, .linear), 0.001);
    try testing.expectApproxEqAbs(anim.easeIn(t), anim.applyEasing(t, .ease_in), 0.001);
    try testing.expectApproxEqAbs(anim.easeOut(t), anim.applyEasing(t, .ease_out), 0.001);
    try testing.expectApproxEqAbs(anim.easeInOut(t), anim.applyEasing(t, .ease_in_out), 0.001);
}

// ===========================================================================
// AnimTimeline: basic tick and value
// ===========================================================================

test "AnimTimeline tick advances elapsed and value" {
    var tl = anim.AnimTimeline{
        .duration = 60,
        .easing = .linear,
    };
    tl.start();

    try testing.expect(tl.running);
    try testing.expectEqual(@as(u32, 0), tl.elapsed);
    try testing.expectEqual(@as(f32, 0.0), tl.value);

    tl.tick();
    try testing.expectEqual(@as(u32, 1), tl.elapsed);
    // linear: value = 1/60
    try testing.expectApproxEqAbs(@as(f32, 1.0 / 60.0), tl.value, 0.001);
}

test "AnimTimeline reaches value 1.0 at end of duration" {
    var tl = anim.AnimTimeline{
        .duration = 10,
        .easing = .linear,
    };
    tl.start();

    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        tl.tick();
    }
    try testing.expectApproxEqAbs(@as(f32, 1.0), tl.value, 0.001);
    try testing.expectEqual(@as(u32, 10), tl.elapsed);
    // After exactly duration ticks, the timeline is NOT yet stopped:
    // rawProgress = 10/10 = 1.0, which triggers the check — running should become false.
    try testing.expect(!tl.running);
}

test "AnimTimeline stops when value reaches 1.0 (non-repeating)" {
    var tl = anim.AnimTimeline{
        .duration = 5,
        .easing = .linear,
    };
    tl.start();

    // Tick past duration.
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        tl.tick();
    }
    try testing.expect(!tl.running);
    try testing.expectEqual(@as(f32, 1.0), tl.value);
}

test "AnimTimeline tick is no-op when not running" {
    var tl = anim.AnimTimeline{
        .duration = 10,
        .easing = .linear,
    };
    // Not started — running=false.
    tl.tick();
    try testing.expectEqual(@as(u32, 0), tl.elapsed);
    try testing.expectEqual(@as(f32, 0.0), tl.value);
}

// ===========================================================================
// AnimTimeline: repeating
// ===========================================================================

test "AnimTimeline repeating loops back to 0" {
    var tl = anim.AnimTimeline{
        .duration = 5,
        .repeating = true,
        .easing = .linear,
    };
    tl.start();

    // Tick through one full cycle.
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        tl.tick();
    }
    // At the tick that pushes elapsed past duration, elapsed resets to 0.
    // The value was computed at easing(1.0) = 1.0 before the reset.
    try testing.expect(tl.running); // still running after loop
    try testing.expectEqual(@as(u32, 0), tl.elapsed); // reset
    // After the wrap, value = 1.0 (the eased result at the endpoint).
    // The next tick will start computing from elapsed=0+1=1.
    try testing.expectApproxEqAbs(@as(f32, 1.0), tl.value, 0.001);
}

test "AnimTimeline repeating continues after multiple cycles" {
    var tl = anim.AnimTimeline{
        .duration = 3,
        .repeating = true,
        .easing = .linear,
    };
    tl.start();

    // Three full cycles = 9 ticks.
    var i: u32 = 0;
    while (i < 9) : (i += 1) {
        tl.tick();
    }
    try testing.expect(tl.running);
    // 9 % 3 = 0, so elapsed should be 0.
    try testing.expectEqual(@as(u32, 0), tl.elapsed);
    // value = 1.0 (eased result at the endpoint, then elapsed resets).
    try testing.expectApproxEqAbs(@as(f32, 1.0), tl.value, 0.001);
}

// ===========================================================================
// AnimTimeline: yoyo (ping-pong)
// ===========================================================================

test "AnimTimeline yoyo reverses direction" {
    var tl = anim.AnimTimeline{
        .duration = 4,
        .repeating = true,
        .yoyo = true,
        .easing = .linear,
    };
    tl.start();
    try testing.expect(tl.forward);

    // Tick through first 4 ticks — forward direction for ticks 1-3,
    // on tick 4 (elapsed reaches 4, raw=1.0) the direction flips.
    tl.tick(); // elapsed=1, forward=true
    try testing.expect(tl.forward);
    tl.tick(); // elapsed=2, forward=true
    try testing.expect(tl.forward);
    tl.tick(); // elapsed=3, forward=true
    try testing.expect(tl.forward);
    tl.tick(); // elapsed=4, raw=1.0, value=1.0, forward flips to false, elapsed=0
    try testing.expect(!tl.forward);
    try testing.expectEqual(@as(u32, 0), tl.elapsed);

    // Tick through reverse: elapsed 1, 2, 3, then at 4 direction flips back.
    tl.tick(); // elapsed=1, forward=false
    try testing.expect(!tl.forward);
    tl.tick(); // elapsed=2, forward=false
    try testing.expect(!tl.forward);
    tl.tick(); // elapsed=3, forward=false
    try testing.expect(!tl.forward);
    tl.tick(); // elapsed=4, raw=1.0, direction flips back to forward
    try testing.expect(tl.forward);
    try testing.expectEqual(@as(u32, 0), tl.elapsed);
}

test "AnimTimeline yoyo value goes to 1.0 then back to 0.0" {
    var tl = anim.AnimTimeline{
        .duration = 4,
        .repeating = true,
        .yoyo = true,
        .easing = .linear,
    };
    tl.start();

    // Tick to nearly the end.
    var i: u32 = 0;
    while (i < 4) : (i += 1) {
        tl.tick();
    }
    // After completing forward: value should be near 1.0, then direction flips and
    // elapsed resets. The tick that flips sets value = 1.0 - easing(0) = 1.0.
    try testing.expectApproxEqAbs(@as(f32, 1.0), tl.value, 0.001);

    // Tick once in reverse.
    tl.tick(); // elapsed=1, rawProgress=0.25, easing linear=0.25, value=1-0.25=0.75
    try testing.expectApproxEqAbs(@as(f32, 0.75), tl.value, 0.001);
}

// ===========================================================================
// AnimTimeline: start and reset
// ===========================================================================

test "AnimTimeline start resets state" {
    var tl = anim.AnimTimeline{
        .duration = 10,
        .easing = .linear,
    };
    tl.start();

    tl.tick();
    tl.tick();
    tl.tick();
    try testing.expect(tl.running);
    try testing.expect(tl.elapsed > 0);
    try testing.expect(tl.value > 0);

    tl.start();
    try testing.expectEqual(@as(u32, 0), tl.elapsed);
    try testing.expectEqual(@as(f32, 0.0), tl.value);
    try testing.expect(tl.forward);
    try testing.expect(tl.running);
}

test "AnimTimeline reset clears state" {
    var tl = anim.AnimTimeline{
        .duration = 10,
        .easing = .linear,
    };
    tl.start();
    tl.tick();
    tl.tick();

    tl.reset();
    try testing.expectEqual(@as(u32, 0), tl.elapsed);
    try testing.expectEqual(@as(f32, 0.0), tl.value);
    try testing.expect(!tl.running);
}

// ===========================================================================
// AnimTimeline: boundary conditions
// ===========================================================================

test "AnimTimeline duration=0 completes instantly" {
    var tl = anim.AnimTimeline{
        .duration = 0,
        .easing = .linear,
    };
    tl.start();
    try testing.expect(tl.running);

    tl.tick();
    try testing.expectEqual(@as(f32, 1.0), tl.value);
    try testing.expect(!tl.running);
}

test "AnimTimeline respects easing setting" {
    var tl = anim.AnimTimeline{
        .duration = 10,
        .easing = .ease_in,
    };
    tl.start();

    // Tick 5 out of 10 frames: raw = 0.5, easeIn = 0.25
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        tl.tick();
    }
    try testing.expectApproxEqAbs(@as(f32, 0.25), tl.value, 0.001);

    // Finish the timeline.
    while (i < 10) : (i += 1) {
        tl.tick();
    }
    try testing.expectEqual(@as(f32, 1.0), tl.value);
    try testing.expect(!tl.running);
}

test "AnimTimeline default easing is ease_in_out" {
    const tl = anim.AnimTimeline{
        .duration = 10,
    };
    try testing.expectEqual(anim.Easing.ease_in_out, tl.easing);
}

test "AnimTimeline start after reset re-enables running" {
    var tl = anim.AnimTimeline{
        .duration = 10,
        .easing = .linear,
    };
    tl.start();
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        tl.tick();
    }
    try testing.expect(!tl.running);

    // Start again
    tl.start();
    try testing.expect(tl.running);
    try testing.expectEqual(@as(u32, 0), tl.elapsed);

    tl.tick();
    try testing.expect(tl.running);
    try testing.expect(tl.elapsed > 0);
}

test "AnimTimeline value monotonic in forward non-repeating" {
    var tl = anim.AnimTimeline{
        .duration = 10,
        .easing = .linear,
    };
    tl.start();
    var prev: f32 = 0.0;
    var i: u32 = 0;
    while (i < 10) : (i += 1) {
        tl.tick();
        try testing.expect(tl.value >= prev);
        prev = tl.value;
    }
}

test "AnimTimeline yoyo value dips after midpoint" {
    var tl = anim.AnimTimeline{
        .duration = 5,
        .repeating = true,
        .yoyo = true,
        .easing = .linear,
    };
    tl.start();

    // Tick through forward: elapsed 1,2,3,4,5 → direction flips at 5.
    var i: u32 = 0;
    while (i < 5) : (i += 1) {
        tl.tick();
    }
    const peak_value = tl.value;
    try testing.expectApproxEqAbs(@as(f32, 1.0), peak_value, 0.001);

    // Tick in reverse once.
    tl.tick(); // elapsed=1, raw=0.2, reversed = 1-0.2 = 0.8
    try testing.expect(tl.value < peak_value);
}

test "AnimTimeline repeating with yoyo forward flag toggles correctly through multiple cycles" {
    var tl = anim.AnimTimeline{
        .duration = 3,
        .repeating = true,
        .yoyo = true,
        .easing = .linear,
    };
    tl.start();
    try testing.expect(tl.forward);

    // Cycle 1 forward (3 ticks) exits at elapsed=3, forward flips to false.
    var i: u32 = 0;
    while (i < 3) : (i += 1) tl.tick();
    try testing.expect(!tl.forward);

    // Cycle 1 reverse (3 ticks) exits at elapsed=3, forward flips to true.
    i = 0;
    while (i < 3) : (i += 1) tl.tick();
    try testing.expect(tl.forward);

    // Cycle 2 forward.
    i = 0;
    while (i < 3) : (i += 1) tl.tick();
    try testing.expect(!tl.forward);
}
