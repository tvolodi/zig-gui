//! Unit tests for ErrorBoundary (RA0 — M10-01).
//! Headless — no GPU/GLFW. Tests boundary call/capture/clear behavior.

const std = @import("std");
const eb_mod = @import("error_boundary.zig");
const ErrorBoundary = eb_mod.ErrorBoundary;
const ScreenFn = eb_mod.ScreenFn;
const Scene = eb_mod.Scene;
const Tokens = eb_mod.Tokens;

// -----------------------------------------------------------------------
// Mock ScreenFn helpers
// -----------------------------------------------------------------------

fn passingFn(scene: *Scene, tokens: Tokens, app: *anyopaque, ctx: ?*anyopaque) anyerror!void {
    _ = scene;
    _ = tokens;
    _ = app;
    _ = ctx;
    // succeeds without error
}

fn failingOOM(scene: *Scene, tokens: Tokens, app: *anyopaque, ctx: ?*anyopaque) anyerror!void {
    _ = scene;
    _ = tokens;
    _ = app;
    _ = ctx;
    return error.OutOfMemory;
}

fn failingCustom(scene: *Scene, tokens: Tokens, app: *anyopaque, ctx: ?*anyopaque) anyerror!void {
    _ = scene;
    _ = tokens;
    _ = app;
    _ = ctx;
    return error.SomeCustomError;
}

// We need a minimal Scene for testing.
// Since Scene requires GPU setup, we create a bare Scene using Scene.init with
// the testing allocator and only exercise the error boundary logic.
fn makeScene() !Scene {
    return Scene.init(std.testing.allocator);
}

fn makeTokens() Tokens {
    const mod05 = @import("../05/types.zig");
    return mod05.Tokens.light(mod05.Palette.default());
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "ErrorBoundary: call with passing ScreenFn returns true, lastError is null" {
    var scene = try makeScene();
    defer scene.deinit();

    var boundary = ErrorBoundary{};
    var dummy_app: u8 = 0;

    const ok = boundary.call(passingFn, &scene, makeTokens(), @ptrCast(&dummy_app), null);
    try std.testing.expect(ok);
    try std.testing.expectEqual(@as(?anyerror, null), boundary.lastError());
    try std.testing.expectEqualSlices(u8, "", boundary.lastMessage());
}

test "ErrorBoundary: call with failing ScreenFn returns false and captures error" {
    var scene = try makeScene();
    defer scene.deinit();

    var boundary = ErrorBoundary{};
    var dummy_app: u8 = 0;

    const ok = boundary.call(failingOOM, &scene, makeTokens(), @ptrCast(&dummy_app), null);
    try std.testing.expect(!ok);
    try std.testing.expectEqual(@as(?anyerror, error.OutOfMemory), boundary.lastError());
}

test "ErrorBoundary: lastMessage contains error name" {
    var scene = try makeScene();
    defer scene.deinit();

    var boundary = ErrorBoundary{};
    var dummy_app: u8 = 0;

    _ = boundary.call(failingCustom, &scene, makeTokens(), @ptrCast(&dummy_app), null);
    const msg = boundary.lastMessage();
    try std.testing.expect(std.mem.indexOf(u8, msg, "SomeCustomError") != null);
}

test "ErrorBoundary: clear resets last_error to null" {
    var scene = try makeScene();
    defer scene.deinit();

    var boundary = ErrorBoundary{};
    var dummy_app: u8 = 0;

    _ = boundary.call(failingOOM, &scene, makeTokens(), @ptrCast(&dummy_app), null);
    try std.testing.expect(boundary.lastError() != null);

    boundary.clear();
    try std.testing.expectEqual(@as(?anyerror, null), boundary.lastError());
    try std.testing.expectEqualSlices(u8, "", boundary.lastMessage());
}

test "ErrorBoundary: call twice — second call overwrites first" {
    var scene = try makeScene();
    defer scene.deinit();

    var boundary = ErrorBoundary{};
    var dummy_app: u8 = 0;
    const tokens = makeTokens();

    _ = boundary.call(failingOOM, &scene, tokens, @ptrCast(&dummy_app), null);
    try std.testing.expectEqual(@as(?anyerror, error.OutOfMemory), boundary.lastError());

    // Reset scene for second call.
    scene.reset();
    _ = boundary.call(failingCustom, &scene, tokens, @ptrCast(&dummy_app), null);
    try std.testing.expectEqual(@as(?anyerror, error.SomeCustomError), boundary.lastError());
}

test "ErrorBoundary: enable_error_boundary=false default produces null error_boundary" {
    const AppOptions = @import("app.zig").AppOptions;
    const opts = AppOptions{ .font_path = "dummy.ttf" };
    try std.testing.expect(!opts.enable_error_boundary);
}
