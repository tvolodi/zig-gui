//! RF0 — M16-01: System tray unit tests.
//!
//! Tests run on both Windows and Linux.
//! On Linux, all Tray methods are no-op stubs — they compile and run without
//! panics. On Windows they exercise the real Win32 path (message-only window +
//! icon registration), but we never call setVisible(true) so no icon appears
//! in the system notification area during the test run.
//!
//! No GPU, no GLFW, no real window required.
//!
//! Import note: tray.zig belongs to the app.zig module (app.zig imports it by
//! relative path). To avoid the "file exists in multiple modules" build error,
//! we import tray.zig through the app.zig module here.

const std = @import("std");
const testing = std.testing;

// tray.zig is registered as a named build module (mod_tray in build.zig).
// Both app.zig and this test file import it through that named module so the
// Zig build system sees only one canonical module identity for src/app/tray.zig
// (build rule: each .zig file belongs to exactly one module).
const app_mod = @import("app.zig");
const tray_mod = @import("tray.zig");
const Tray = tray_mod.Tray;
const CallbackFn = tray_mod.CallbackFn;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// A 2×2 pixel RGBA image (4 pixels × 4 bytes = 16 bytes), all white + opaque.
const test_icon_rgba: []const u8 = &[_]u8{0xFF} ** 16;
const test_icon_w: u32 = 2;
const test_icon_h: u32 = 2;
const test_tooltip = "Test tray";

var dummy_ctx: u32 = 0;

fn dummyCb(ptr: *anyopaque) void {
    _ = ptr;
}

fn makeDummyCb() CallbackFn {
    return CallbackFn{
        .ptr = @as(*anyopaque, @ptrCast(&dummy_ctx)),
        .call = dummyCb,
    };
}

// ---------------------------------------------------------------------------
// RF0-AC8: init / deinit round-trip (no panic on either platform)
// ---------------------------------------------------------------------------

test "Tray: init and deinit without error" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();
    // Reaching here means init succeeded and deinit will clean up.
}

// ---------------------------------------------------------------------------
// RF0-AC2: addMenuItem appends items; item count increases
// ---------------------------------------------------------------------------

test "Tray: addMenuItem appends items" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    try testing.expectEqual(@as(usize, 0), tray.items.items.len);

    try tray.addMenuItem("Open", makeDummyCb(), false);
    try testing.expectEqual(@as(usize, 1), tray.items.items.len);

    try tray.addMenuItem("Quit", makeDummyCb(), false);
    try testing.expectEqual(@as(usize, 2), tray.items.items.len);
}

// ---------------------------------------------------------------------------
// Verify the first item stores the correct label and disabled flag
// ---------------------------------------------------------------------------

test "Tray: addMenuItem stores label and disabled flag" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    try tray.addMenuItem("Settings", makeDummyCb(), true);

    const item = tray.items.items[0];
    try testing.expectEqualSlices(u8, "Settings", item.label);
    try testing.expect(item.disabled);
    try testing.expect(!item.is_separator);
}

// ---------------------------------------------------------------------------
// RF0-AC5: addSeparator appends a separator; item count increases
// ---------------------------------------------------------------------------

test "Tray: addSeparator appends a separator" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    try tray.addMenuItem("Open", makeDummyCb(), false);
    const count_before = tray.items.items.len;

    try tray.addSeparator();
    try testing.expectEqual(count_before + 1, tray.items.items.len);

    const sep = tray.items.items[tray.items.items.len - 1];
    try testing.expect(sep.is_separator);
}

// ---------------------------------------------------------------------------
// Mixed items: menu items and separators interleaved
// ---------------------------------------------------------------------------

test "Tray: mixed addMenuItem and addSeparator item ordering" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    try tray.addMenuItem("Open", makeDummyCb(), false);
    try tray.addSeparator();
    try tray.addMenuItem("Quit", makeDummyCb(), false);

    try testing.expectEqual(@as(usize, 3), tray.items.items.len);
    try testing.expect(!tray.items.items[0].is_separator);
    try testing.expect(tray.items.items[1].is_separator);
    try testing.expect(!tray.items.items[2].is_separator);
}

// ---------------------------------------------------------------------------
// RF0-AC6: setVisible toggles _visible field
// ---------------------------------------------------------------------------

test "Tray: setVisible toggles _visible field" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    // After init the icon should be hidden.
    try testing.expect(!tray._visible);

    // On Linux this just flips the field; on Windows it also calls Shell_NotifyIconW.
    // We never actually show the tray icon in CI; we just verify the field toggles.
    tray.setVisible(true);
    try testing.expect(tray._visible);

    tray.setVisible(false);
    try testing.expect(!tray._visible);
}

// ---------------------------------------------------------------------------
// RF0-AC11: pumpMessages runs without panic (Linux stub / Win32 empty queue)
// ---------------------------------------------------------------------------

test "Tray: pumpMessages does not panic" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    // On Linux: no-op. On Windows: drains the message-only window queue (empty at test time).
    tray.pumpMessages();
}

// ---------------------------------------------------------------------------
// RF0-AC11: update runs without panic (Linux stub / Win32 rebuilds empty menu)
// ---------------------------------------------------------------------------

test "Tray: update does not panic on empty item list" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    tray.update();
}

test "Tray: update does not panic with items in the list" {
    var tray = try Tray.init(test_icon_rgba, test_icon_w, test_icon_h, test_tooltip, testing.allocator);
    defer tray.deinit();

    try tray.addMenuItem("Open", makeDummyCb(), false);
    try tray.addSeparator();
    try tray.addMenuItem("Quit", makeDummyCb(), false);

    tray.update();
}

// ---------------------------------------------------------------------------
// RF0-AC9: AppOptions.tray field exists (compile-time structural check)
// ---------------------------------------------------------------------------

test "AppOptions.tray field exists and defaults to null" {
    const AppOptions = app_mod.AppOptions;
    comptime try testing.expect(@hasField(AppOptions, "tray"));

    // Construct with minimum required fields and verify default.
    const opts = AppOptions{ .font_path = "dummy.ttf" };
    try testing.expectEqual(@as(?*Tray, null), opts.tray);
}
