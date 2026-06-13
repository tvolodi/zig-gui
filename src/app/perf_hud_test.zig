//! R92 — PerfHud unit tests.
//! Tests FrameCounters storage, ring-buffer wrap-around, smoothFrameMs averaging,
//! and the disabled-path early return for buildHudDrawList.
//! No GPU required. Run via: zig build test-perf-hud

const std = @import("std");
const testing = std.testing;
const perf_mod = @import("perf_hud.zig");
const mod02 = @import("../02/types.zig");
const mod05 = @import("../05/types.zig");

const PerfHud = perf_mod.PerfHud;
const FrameCounters = perf_mod.FrameCounters;

// ---------------------------------------------------------------------------
// 1. init() — zero state
// ---------------------------------------------------------------------------

test "init: frame_ms_history all zero" {
    const hud = PerfHud.init();
    for (hud.frame_ms_history) |ms| {
        try testing.expectEqual(@as(f32, 0.0), ms);
    }
}

test "init: history_idx starts at zero" {
    const hud = PerfHud.init();
    try testing.expectEqual(@as(u8, 0), hud.history_idx);
}

test "init: counters all zero" {
    const hud = PerfHud.init();
    try testing.expectEqual(@as(f32, 0.0), hud.counters.frame_ms);
    try testing.expectEqual(@as(u32, 0), hud.counters.cmd_count);
    try testing.expectEqual(@as(u32, 0), hud.counters.dirty_count);
    try testing.expectEqual(@as(u32, 0), hud.counters.element_count);
}

// ---------------------------------------------------------------------------
// 2. record() — counter storage and ring-buffer advancement
// ---------------------------------------------------------------------------

test "record: stores counters" {
    var hud = PerfHud.init();
    hud.record(.{ .frame_ms = 16.0, .cmd_count = 200, .dirty_count = 5, .element_count = 42 });
    try testing.expectEqual(@as(f32, 16.0), hud.counters.frame_ms);
    try testing.expectEqual(@as(u32, 200), hud.counters.cmd_count);
    try testing.expectEqual(@as(u32, 5), hud.counters.dirty_count);
    try testing.expectEqual(@as(u32, 42), hud.counters.element_count);
}

test "record: writes frame_ms to first history slot" {
    var hud = PerfHud.init();
    hud.record(.{ .frame_ms = 8.0 });
    try testing.expectEqual(@as(f32, 8.0), hud.frame_ms_history[0]);
}

test "record: advances history_idx after one call" {
    var hud = PerfHud.init();
    hud.record(.{ .frame_ms = 1.0 });
    try testing.expectEqual(@as(u8, 1), hud.history_idx);
}

test "record: advances history_idx sequentially" {
    var hud = PerfHud.init();
    hud.record(.{ .frame_ms = 1.0 });
    hud.record(.{ .frame_ms = 2.0 });
    hud.record(.{ .frame_ms = 3.0 });
    try testing.expectEqual(@as(u8, 3), hud.history_idx);
    try testing.expectEqual(@as(f32, 1.0), hud.frame_ms_history[0]);
    try testing.expectEqual(@as(f32, 2.0), hud.frame_ms_history[1]);
    try testing.expectEqual(@as(f32, 3.0), hud.frame_ms_history[2]);
}

// ---------------------------------------------------------------------------
// 3. Ring-buffer wrap-around at 16 entries
// ---------------------------------------------------------------------------

test "ring buffer: wraps at 16 — history_idx returns to 0" {
    var hud = PerfHud.init();
    for (0..16) |_| {
        hud.record(.{ .frame_ms = 1.0 });
    }
    // After 16 records history_idx should wrap to 0.
    try testing.expectEqual(@as(u8, 0), hud.history_idx);
}

test "ring buffer: 17th record overwrites slot 0" {
    var hud = PerfHud.init();
    for (0..16) |_| {
        hud.record(.{ .frame_ms = 1.0 });
    }
    hud.record(.{ .frame_ms = 99.0 }); // 17th — overwrites slot 0
    try testing.expectEqual(@as(f32, 99.0), hud.frame_ms_history[0]);
    try testing.expectEqual(@as(u8, 1), hud.history_idx);
}

test "ring buffer: slots 1-15 unchanged after 17th record" {
    var hud = PerfHud.init();
    for (0..16) |_| {
        hud.record(.{ .frame_ms = 1.0 });
    }
    hud.record(.{ .frame_ms = 99.0 }); // overwrites slot 0 only
    for (1..16) |i| {
        try testing.expectEqual(@as(f32, 1.0), hud.frame_ms_history[i]);
    }
}

// ---------------------------------------------------------------------------
// 4. smoothFrameMs()
// ---------------------------------------------------------------------------

test "smoothFrameMs: returns 0 when all history slots are zero" {
    const hud = PerfHud.init();
    try testing.expectEqual(@as(f32, 0.0), hud.smoothFrameMs());
}

test "smoothFrameMs: single non-zero entry equals that entry" {
    var hud = PerfHud.init();
    hud.record(.{ .frame_ms = 20.0 });
    try testing.expectApproxEqAbs(@as(f32, 20.0), hud.smoothFrameMs(), 1e-4);
}

test "smoothFrameMs: averages only non-zero entries" {
    var hud = PerfHud.init();
    // Record 4 entries of 10 ms; remaining 12 slots are still zero.
    hud.record(.{ .frame_ms = 10.0 });
    hud.record(.{ .frame_ms = 10.0 });
    hud.record(.{ .frame_ms = 10.0 });
    hud.record(.{ .frame_ms = 10.0 });
    // Only 4 non-zero entries contribute: average = 40/4 = 10.
    try testing.expectApproxEqAbs(@as(f32, 10.0), hud.smoothFrameMs(), 1e-4);
}

test "smoothFrameMs: full buffer average" {
    var hud = PerfHud.init();
    for (0..16) |_| {
        hud.record(.{ .frame_ms = 8.0 });
    }
    // All 16 non-zero, average = 8.
    try testing.expectApproxEqAbs(@as(f32, 8.0), hud.smoothFrameMs(), 1e-4);
}

test "smoothFrameMs: after wrap-around overwrites one slot" {
    var hud = PerfHud.init();
    // Fill all 16 slots with 1.0.
    for (0..16) |_| {
        hud.record(.{ .frame_ms = 1.0 });
    }
    // Overwrite slot 0 with 17.0 — 15 slots of 1.0 + 1 slot of 17.0.
    hud.record(.{ .frame_ms = 17.0 });
    // Expected: (15*1 + 17) / 16 = 32/16 = 2.0
    try testing.expectApproxEqAbs(@as(f32, 2.0), hud.smoothFrameMs(), 1e-4);
}

// ---------------------------------------------------------------------------
// 5. buildHudDrawList — disabled early return (no GPU required).
//    Font and atlas are never accessed when enabled=false.
// ---------------------------------------------------------------------------

test "buildHudDrawList: returns empty slice when hud_enabled=false (default)" {
    const hud = PerfHud.init(); // hud_enabled defaults to false
    const tokens = mod05.Tokens.light(mod05.Palette.default());
    var font: mod02.Font = undefined;
    var atlas: mod02.GlyphAtlas = undefined;

    const cmds = try hud.buildHudDrawList(
        testing.allocator,
        1920.0,
        tokens,
        &font,
        &atlas,
    );
    try testing.expectEqual(@as(usize, 0), cmds.len);
}

test "buildHudDrawList: disabled with zero viewport returns empty" {
    const hud = PerfHud.init();
    const tokens = mod05.Tokens.dark(mod05.Palette.default());
    var font: mod02.Font = undefined;
    var atlas: mod02.GlyphAtlas = undefined;

    const cmds = try hud.buildHudDrawList(testing.allocator, 0.0, tokens, &font, &atlas);
    try testing.expectEqual(@as(usize, 0), cmds.len);
}

test "buildHudDrawList: repeated disabled calls do not leak memory" {
    const hud = PerfHud.init();
    const tokens = mod05.Tokens.light(mod05.Palette.default());
    var font: mod02.Font = undefined;
    var atlas: mod02.GlyphAtlas = undefined;

    for (0..8) |_| {
        const cmds = try hud.buildHudDrawList(testing.allocator, 800.0, tokens, &font, &atlas);
        try testing.expectEqual(@as(usize, 0), cmds.len);
    }
}
