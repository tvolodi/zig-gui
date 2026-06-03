//! R7C — Tooltip manager unit tests.
//! Tests TooltipManager state transitions without GPU, GLFW, or rendering.
//! tick() requires Font + GlyphAtlas; we test pure state paths instead.

const std = @import("std");
const testing = std.testing;
const tooltip_mod = @import("tooltip.zig");
const overlay_mod = @import("overlay.zig");

pub const TooltipManager = tooltip_mod.TooltipManager;
pub const OverlayLayer = overlay_mod.OverlayLayer;

const NONE: u32 = std.math.maxInt(u32);
const HOVER_DELAY_MS: u64 = 500;

fn newTooltip() TooltipManager {
    return TooltipManager{};
}

// ---------------------------------------------------------------------------
// onHover
// ---------------------------------------------------------------------------

test "onHover: sets hover_idx and start time" {
    var t = newTooltip();
    t.onHover(5, "Hello", 1000);
    try testing.expectEqual(@as(u32, 5), t.hover_idx);
    try testing.expectEqual(@as(u64, 1000), t.hover_start_ms);
}

test "onHover: stores tooltip text" {
    var t = newTooltip();
    t.onHover(3, "Tooltip text", 0);
    try testing.expectEqualSlices(u8, "Tooltip text", t.text);
}

test "onHover: clears visible flag when new hover starts" {
    var t = newTooltip();
    // Simulate that tooltip was already visible from a previous hover
    t.visible = true;
    t.onHover(7, "New", 0);
    try testing.expect(!t.visible);
}

// ---------------------------------------------------------------------------
// onHover — hovering same element twice does not reset the timer
// ---------------------------------------------------------------------------

test "onHover: same idx twice does not reset hover_start_ms" {
    var t = newTooltip();
    t.onHover(10, "Label", 1000);
    const original_start = t.hover_start_ms;

    // Second call with same idx must be ignored (no reset)
    t.onHover(10, "Label", 9999);
    try testing.expectEqual(original_start, t.hover_start_ms);
}

// ---------------------------------------------------------------------------
// isPending
// ---------------------------------------------------------------------------

test "isPending: true immediately after onHover (visible=false)" {
    var t = newTooltip();
    t.onHover(1, "tip", 0);
    try testing.expect(t.isPending());
}

test "isPending: false when hover_idx is NONE (no hover)" {
    const t = newTooltip();
    try testing.expect(!t.isPending());
}

test "isPending: false once visible=true (delay elapsed)" {
    var t = newTooltip();
    t.onHover(2, "tip", 0);
    // Simulate tick making tooltip visible
    t.visible = true;
    try testing.expect(!t.isPending());
}

// isPending reflects the 500 ms window:
// - At t=0 hover starts; at t=499 still pending; at t=500 no longer pending (visible).

test "isPending: true while under 500 ms threshold (visible=false)" {
    var t = newTooltip();
    t.onHover(1, "tip", 1000); // started at ms=1000
    // At ms=1499 (499 ms elapsed) — still pending, not yet visible
    try testing.expect(t.hover_idx != NONE and !t.visible);
    try testing.expect(t.isPending());
}

test "isPending: false after 500+ ms elapsed (tick sets visible=true)" {
    var t = newTooltip();
    t.onHover(1, "tip", 0);
    // Simulate what tick() would do after 500 ms: set visible = true
    t.visible = true;
    try testing.expect(!t.isPending());
}

// ---------------------------------------------------------------------------
// onLeave
// ---------------------------------------------------------------------------

test "onLeave: resets hover_idx to NONE" {
    var t = newTooltip();
    t.onHover(4, "tip", 0);
    t.onLeave(4);
    try testing.expectEqual(NONE, t.hover_idx);
}

test "onLeave: hides tooltip" {
    var t = newTooltip();
    t.onHover(4, "tip", 0);
    t.visible = true;
    t.onLeave(4);
    try testing.expect(!t.visible);
}

test "onLeave: clears text" {
    var t = newTooltip();
    t.onHover(4, "tip text", 0);
    t.onLeave(4);
    try testing.expectEqual(@as(usize, 0), t.text.len);
}

test "onLeave: no-op for a different idx" {
    var t = newTooltip();
    t.onHover(4, "tip", 0);
    t.onLeave(99); // wrong idx — must be ignored
    try testing.expectEqual(@as(u32, 4), t.hover_idx);
}

// ---------------------------------------------------------------------------
// deinit: safe when no commands allocated
// ---------------------------------------------------------------------------

test "deinit: safe with null current_cmds" {
    var t = newTooltip();
    t.deinit(testing.allocator); // Must not crash
}

// ---------------------------------------------------------------------------
// Hover → leave → hover again: timer restarts for new element
// ---------------------------------------------------------------------------

test "hover different element after leave restarts timer" {
    var t = newTooltip();
    t.onHover(1, "first", 100);
    t.onLeave(1);
    t.onHover(2, "second", 999);

    try testing.expectEqual(@as(u32, 2), t.hover_idx);
    try testing.expectEqual(@as(u64, 999), t.hover_start_ms);
    try testing.expect(!t.visible);
}
