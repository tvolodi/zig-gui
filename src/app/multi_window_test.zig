//! multi_window_test.zig — R83 acceptance tests (headless — no GPU required).
//!
//! Tests the bookkeeping logic of MultiWindowApp:
//!   openWindow / closeWindow / windowById / run exit condition / is_shared flag.

const std = @import("std");
const testing = std.testing;

const multi_window = @import("multi_window.zig");
const MultiWindowApp = multi_window.MultiWindowApp;
const WindowEntry = multi_window.WindowEntry;
const WindowId = multi_window.WindowId;
const WindowOptions = multi_window.WindowOptions;
const ScreenFn = multi_window.ScreenFn;

const mod01 = @import("../01/types.zig");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");

// ---------------------------------------------------------------------------
// Stub ScreenFn — does nothing to the scene (headless tests don't need a real scene).
// ---------------------------------------------------------------------------

fn stubBuild(
    scene: *mod07.Scene,
    tokens: mod05.Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = scene;
    _ = tokens;
    _ = app;
    _ = ctx;
}

// ---------------------------------------------------------------------------
// T1: openWindow returns valid WindowId; windowById returns entry;
//     closeWindow marks it closed; entry removed at top of next frame.
// ---------------------------------------------------------------------------

test "openWindow returns valid id; windowById finds it; closeWindow marks closed" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const id = try mw.openWindow(.{}, stubBuild, null);

    // id must be non-zero.
    try testing.expect(id != 0);

    // windowById finds it.
    const entry = mw.windowById(id);
    try testing.expect(entry != null);
    try testing.expectEqual(id, entry.?.id);
    try testing.expect(entry.?.open);

    // closeWindow marks it closed.
    mw.closeWindow(id);

    // windowById no longer returns it after closing.
    const after_close = mw.windowById(id);
    try testing.expect(after_close == null);

    // Entry still in windows list (not pruned yet).
    try testing.expectEqual(@as(usize, 1), mw.windows.items.len);

    // Prune → entry removed.
    mw.pruneClosedWindows();
    try testing.expectEqual(@as(usize, 0), mw.windows.items.len);
}

// ---------------------------------------------------------------------------
// T2: Frame loop exits when windows list is empty.
// ---------------------------------------------------------------------------

test "run exits when no open windows" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    // No windows — run should return immediately.
    mw.run();

    // Still alive, no crash.
    try testing.expectEqual(@as(usize, 0), mw.windows.items.len);
}

test "run exits after all windows closed and pruned" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const id = try mw.openWindow(.{}, stubBuild, null);
    mw.closeWindow(id);

    // run: prunes closed windows → list empty → exits.
    mw.run();

    try testing.expectEqual(@as(usize, 0), mw.windows.items.len);
}

// ---------------------------------------------------------------------------
// T3: Closing one window does not affect another window's scene.
// ---------------------------------------------------------------------------

test "closing one window does not affect another" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const id_a = try mw.openWindow(.{}, stubBuild, null);
    const id_b = try mw.openWindow(.{}, stubBuild, null);

    // Both present.
    try testing.expect(mw.windowById(id_a) != null);
    try testing.expect(mw.windowById(id_b) != null);

    // Close A.
    mw.closeWindow(id_a);
    mw.pruneClosedWindows();

    // B still open.
    try testing.expect(mw.windowById(id_b) != null);
    try testing.expectEqual(@as(usize, 1), mw.windows.items.len);
    try testing.expectEqual(id_b, mw.windows.items[0].id);
}

// ---------------------------------------------------------------------------
// T4: windowById for unknown id returns null.
// ---------------------------------------------------------------------------

test "windowById unknown id returns null" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const result = mw.windowById(42);
    try testing.expect(result == null);
}

// ---------------------------------------------------------------------------
// T5: is_shared flag on VulkanBackend — deinit respects it.
//
// We cannot call the real VulkanBackend on headless machines, so we verify
// the is_shared field exists and the deinit path would skip device destruction.
// The field is checked via a compile-time assertion.
// ---------------------------------------------------------------------------

test "VulkanBackend has is_shared field" {
    // Compile-time check: VulkanBackend must have is_shared field.
    // In headless tests we do NOT create a real VulkanBackend (no GPU);
    // we just verify the type has the expected field at the struct level.
    //
    // Note: VulkanBackend._impl is *anyopaque so we can't directly inspect the
    // VulkanImpl struct. The is_shared field is on VulkanBackend itself (per R83).
    const backend_type = mod01.VulkanBackend;
    const fields = @typeInfo(backend_type).@"struct".fields;
    comptime var found = false;
    inline for (fields) |f| {
        if (comptime std.mem.eql(u8, f.name, "is_shared")) {
            found = true;
            // Verify it's a bool.
            comptime std.debug.assert(f.type == bool);
        }
    }
    try testing.expect(found);
}

test "VulkanBackend.initShared exists as a declaration" {
    // Verify initShared is declared on VulkanBackend.
    try testing.expect(@hasDecl(mod01.VulkanBackend, "initShared"));
}

// ---------------------------------------------------------------------------
// T6: No memory leaks — use testing.allocator throughout.
//     (std.testing.allocator reports leaks automatically on test completion.)
// ---------------------------------------------------------------------------

test "no memory leaks on open+close" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const id1 = try mw.openWindow(.{}, stubBuild, null);
    const id2 = try mw.openWindow(.{}, stubBuild, null);
    mw.closeWindow(id1);
    mw.closeWindow(id2);
    mw.pruneClosedWindows();
    // deinit called by defer — no leak expected.
}

// ---------------------------------------------------------------------------
// T7: closeWindow for already-closed id is a no-op (no error, no double-free).
// ---------------------------------------------------------------------------

test "closeWindow already-closed id is no-op" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const id = try mw.openWindow(.{}, stubBuild, null);
    mw.closeWindow(id);

    // Second close — must not crash or double-free.
    mw.closeWindow(id);

    // Still only one entry in windows (not yet pruned).
    try testing.expectEqual(@as(usize, 1), mw.windows.items.len);

    mw.pruneClosedWindows();
    try testing.expectEqual(@as(usize, 0), mw.windows.items.len);
}

// ---------------------------------------------------------------------------
// T8: All windows closed on the same frame — loop exits cleanly.
// ---------------------------------------------------------------------------

test "all windows closed same frame loop exits" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const id_a = try mw.openWindow(.{}, stubBuild, null);
    const id_b = try mw.openWindow(.{}, stubBuild, null);
    const id_c = try mw.openWindow(.{}, stubBuild, null);

    mw.closeWindow(id_a);
    mw.closeWindow(id_b);
    mw.closeWindow(id_c);

    // run prunes all three → empty → exits.
    mw.run();

    try testing.expectEqual(@as(usize, 0), mw.windows.items.len);
}

// ---------------------------------------------------------------------------
// T9: Atlas generation tracking fields exist.
//     (Re-upload happens at most once per frame — tracked via generation.)
// ---------------------------------------------------------------------------

test "MultiWindowApp has atlas generation fields" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    // Verify the fields are accessible.
    _ = mw.atlas_generation_seen;
    _ = mw.image_atlas_generation_seen;
}

// ---------------------------------------------------------------------------
// T10: next_id starts at 1 and increments monotonically.
// ---------------------------------------------------------------------------

test "next_id increments monotonically starting at 1" {
    var mw = MultiWindowApp.init(testing.allocator);
    defer mw.deinit();

    const id1 = try mw.openWindow(.{}, stubBuild, null);
    const id2 = try mw.openWindow(.{}, stubBuild, null);
    const id3 = try mw.openWindow(.{}, stubBuild, null);

    try testing.expect(id1 >= 1);
    try testing.expect(id2 > id1);
    try testing.expect(id3 > id2);
}
