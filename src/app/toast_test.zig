//! R74 — Toast notification manager unit tests.
//! Tests the ToastManager in isolation — no GPU, no GLFW, no window.
//! All timestamps are supplied by the caller (deterministic).

const std = @import("std");
const testing = std.testing;
const toast_mod = @import("toast.zig");

pub const ToastManager = toast_mod.ToastManager;
pub const ToastKind = toast_mod.ToastKind;
pub const MAX_TOASTS = toast_mod.MAX_TOASTS;

/// Create a minimal ToastManager that does not require an OverlayLayer slot.
/// We skip `init` (which allocates an overlay slot) and use a zero-value struct
/// directly; overlay_id defaults to 0 which is harmless for pure state tests.
fn newManager() ToastManager {
    return ToastManager{};
}

// ---------------------------------------------------------------------------
// show() — enqueue
// ---------------------------------------------------------------------------

test "show: adds a toast, count increases" {
    var m = newManager();
    try testing.expectEqual(@as(u8, 0), m.count);

    m.show("Hello", .info, 3000, 1000);
    try testing.expectEqual(@as(u8, 1), m.count);
}

test "show: message is stored correctly" {
    var m = newManager();
    m.show("World", .success, 3000, 0);
    try testing.expectEqual(@as(u8, 1), m.count);
    try testing.expectEqualSlices(u8, "World", m.toasts[0].message[0..m.toasts[0].message_len]);
}

test "show: kind is stored correctly" {
    var m = newManager();
    m.show("warn", .warning, 3000, 0);
    try testing.expectEqual(ToastKind.warning, m.toasts[0].kind);

    var m2 = newManager();
    m2.show("err", .@"error", 3000, 0);
    try testing.expectEqual(ToastKind.@"error", m2.toasts[0].kind);
}

test "show: created_ms is recorded" {
    var m = newManager();
    m.show("ts", .info, 3000, 42_000);
    try testing.expectEqual(@as(u64, 42_000), m.toasts[0].created_ms);
}

// ---------------------------------------------------------------------------
// MAX_TOASTS cap — 9th toast drops oldest
// ---------------------------------------------------------------------------

test "show: up to MAX_TOASTS toasts are kept" {
    var m = newManager();
    var i: u8 = 0;
    while (i < MAX_TOASTS) : (i += 1) {
        m.show("msg", .info, 3000, @as(u64, i) * 100);
    }
    try testing.expectEqual(MAX_TOASTS, m.count);
}

test "show: exceeding MAX_TOASTS drops the oldest" {
    var m = newManager();
    // Fill to capacity — each with a distinct created_ms
    var i: u8 = 0;
    while (i < MAX_TOASTS) : (i += 1) {
        m.show("old", .info, 3000, @as(u64, i) * 100);
    }
    // The first toast has created_ms = 0.
    try testing.expectEqual(@as(u64, 0), m.toasts[0].created_ms);

    // Enqueue one more — oldest (index 0) must be evicted
    m.show("new", .success, 3000, 9999);
    try testing.expectEqual(MAX_TOASTS, m.count);
    // The last slot should now hold the new toast
    try testing.expectEqual(ToastKind.success, m.toasts[m.count - 1].kind);
    // The oldest created_ms is no longer 0 (it was dropped)
    for (m.toasts[0..m.count]) |t| {
        try testing.expect(t.created_ms != 0);
    }
}

// ---------------------------------------------------------------------------
// dismiss() — immediate removal
// ---------------------------------------------------------------------------

test "dismiss: removes toast at index, count decreases" {
    var m = newManager();
    m.show("a", .info, 3000, 0);
    m.show("b", .info, 3000, 1);
    try testing.expectEqual(@as(u8, 2), m.count);

    m.dismiss(0);
    try testing.expectEqual(@as(u8, 1), m.count);
}

test "dismiss: remaining toasts are shifted forward" {
    var m = newManager();
    m.show("first", .info, 3000, 0);
    m.show("second", .info, 3000, 1);
    m.show("third", .info, 3000, 2);

    m.dismiss(0); // remove "first"
    // "second" is now at index 0
    try testing.expectEqualSlices(u8, "second", m.toasts[0].message[0..m.toasts[0].message_len]);
}

test "dismiss: count is 0 after dismissing sole toast" {
    var m = newManager();
    m.show("solo", .info, 0, 0); // duration_ms = 0 = forever
    m.dismiss(0);
    try testing.expectEqual(@as(u8, 0), m.count);
}

// ---------------------------------------------------------------------------
// Expiry via tick simulation (manual: no overlay, no rendering)
// ---------------------------------------------------------------------------
// We cannot call tick() directly here without a full OverlayLayer + Font + GlyphAtlas.
// Instead, we test the expiry logic by inspecting what show/dismiss do together,
// and verify the duration_ms field is stored so that a real tick() would use it.

test "toast: duration_ms stored for tick-based expiry" {
    var m = newManager();
    m.show("expires", .info, 1500, 0);
    try testing.expectEqual(@as(u32, 1500), m.toasts[0].duration_ms);
}

test "toast: duration_ms=0 means keep forever" {
    var m = newManager();
    m.show("forever", .info, 0, 0);
    try testing.expectEqual(@as(u32, 0), m.toasts[0].duration_ms);
}

// ---------------------------------------------------------------------------
// count / isPending
// ---------------------------------------------------------------------------

test "count is 0 on a fresh manager" {
    const m = newManager();
    try testing.expectEqual(@as(u8, 0), m.count);
}

test "count reflects show/dismiss sequence" {
    var m = newManager();
    m.show("1", .info, 0, 0);
    m.show("2", .info, 0, 0);
    try testing.expectEqual(@as(u8, 2), m.count);
    m.dismiss(1);
    try testing.expectEqual(@as(u8, 1), m.count);
    m.dismiss(0);
    try testing.expectEqual(@as(u8, 0), m.count);
}
