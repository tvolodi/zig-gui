//! Unit tests for WindowStateManager (RA4 — M10-05).
//! Uses a mock PersistentSettings backed by testing.allocator.
//! Headless — no GLFW/GPU.

const std = @import("std");
const window_state = @import("window_state.zig");
const WindowStateManager = window_state.WindowStateManager;
const SavedWindowState = window_state.SavedWindowState;
const PersistentSettings = window_state.PersistentSettings;

/// Create a PersistentSettings backed by a temp file for testing.
fn newSettings(tmp: *std.testing.TmpDir) !PersistentSettings {
    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/test_settings.txt", .{tmp.sub_path});
    return PersistentSettings.loadAbsolute(std.testing.allocator, path);
}

test "WindowStateManager: save writes five keys with correct prefix" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var settings = try newSettings(&tmp);
    defer settings.deinit();

    var mgr = WindowStateManager.init(&settings, "win_");

    const state = SavedWindowState{
        .x = 100,
        .y = 200,
        .width = 800,
        .height = 600,
        .maximised = false,
    };
    try mgr.save(state);

    try std.testing.expectEqual(@as(?i32, 100), settings.getI32("win_x"));
    try std.testing.expectEqual(@as(?i32, 200), settings.getI32("win_y"));
    try std.testing.expectEqual(@as(?u32, 800), settings.getU32("win_w"));
    try std.testing.expectEqual(@as(?u32, 600), settings.getU32("win_h"));
    try std.testing.expectEqual(@as(?bool, false), settings.getBool("win_max"));
}

test "WindowStateManager: load returns null when any key is missing" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var settings = try newSettings(&tmp);
    defer settings.deinit();

    var mgr = WindowStateManager.init(&settings, "win_");

    // Only 4 of 5 keys present — load must return null.
    try settings.setI32("win_x", 10);
    try settings.setI32("win_y", 20);
    try settings.setU32("win_w", 640);
    try settings.setU32("win_h", 480);
    // win_max is absent.

    try std.testing.expectEqual(@as(?SavedWindowState, null), mgr.load());
}

test "WindowStateManager: load returns correct state when all five keys exist" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var settings = try newSettings(&tmp);
    defer settings.deinit();

    var mgr = WindowStateManager.init(&settings, "win_");

    const state = SavedWindowState{
        .x = -50,
        .y = 10,
        .width = 1920,
        .height = 1080,
        .maximised = true,
    };
    try mgr.save(state);

    const loaded = mgr.load() orelse {
        try std.testing.expect(false); // should not be null
        return;
    };
    try std.testing.expectEqual(state.x, loaded.x);
    try std.testing.expectEqual(state.y, loaded.y);
    try std.testing.expectEqual(state.width, loaded.width);
    try std.testing.expectEqual(state.height, loaded.height);
    try std.testing.expectEqual(state.maximised, loaded.maximised);
}

test "WindowStateManager: clear removes all five keys" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var settings = try newSettings(&tmp);
    defer settings.deinit();

    var mgr = WindowStateManager.init(&settings, "win_");

    const state = SavedWindowState{ .x = 0, .y = 0, .width = 100, .height = 100, .maximised = false };
    try mgr.save(state);

    mgr.clear();

    try std.testing.expectEqual(@as(?SavedWindowState, null), mgr.load());
    try std.testing.expect(settings.getI32("win_x") == null);
    try std.testing.expect(settings.getI32("win_y") == null);
    try std.testing.expect(settings.getU32("win_w") == null);
    try std.testing.expect(settings.getU32("win_h") == null);
    try std.testing.expect(settings.getBool("win_max") == null);
}

test "WindowStateManager: maximised=true saves 'true' and loads correctly" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var settings = try newSettings(&tmp);
    defer settings.deinit();

    var mgr = WindowStateManager.init(&settings, "win_");

    try mgr.save(.{ .x = 0, .y = 0, .width = 0, .height = 0, .maximised = true });
    const loaded = mgr.load().?;
    try std.testing.expect(loaded.maximised);
}

test "WindowStateManager: width=0 height=0 saves and restores without crash" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var settings = try newSettings(&tmp);
    defer settings.deinit();

    var mgr = WindowStateManager.init(&settings, "win_");

    try mgr.save(.{ .x = 0, .y = 0, .width = 0, .height = 0, .maximised = false });
    const loaded = mgr.load().?;
    try std.testing.expectEqual(@as(u32, 0), loaded.width);
    try std.testing.expectEqual(@as(u32, 0), loaded.height);
}

test "WindowStateManager: key_prefix exactly 28 bytes produces valid keys" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var settings = try newSettings(&tmp);
    defer settings.deinit();

    // 28-byte prefix → keys like "aaaaaaaaaaaaaaaaaaaaaaaaaaaa" + "x" = 29 chars (within 31 limit).
    const prefix = "a" ** 28;
    var mgr = WindowStateManager.init(&settings, prefix);

    try mgr.save(.{ .x = 1, .y = 2, .width = 3, .height = 4, .maximised = false });
    const loaded = mgr.load().?;
    try std.testing.expectEqual(@as(i32, 1), loaded.x);
}

test "WindowStateManager: persist_window_state=false gives null window_state_mgr (AppOptions default)" {
    const AppOptions = @import("app.zig").AppOptions;
    const opts = AppOptions{ .font_path = "dummy.ttf" };
    try std.testing.expect(!opts.persist_window_state);
    try std.testing.expectEqual(@as(?*PersistentSettings, null), opts.persistent_settings);
}
