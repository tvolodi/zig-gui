//! Navigator acceptance tests (R80 / M8-01).
//!
//! Headless — no GPU, no GLFW.
//! Acceptance criteria from docs/requirements/R80_screen_navigation.md.

const std = @import("std");
const testing = std.testing;

// Import navigator types directly to avoid circular dep issues in tests.
const navigator_mod = @import("../07/types.zig"); // for Scene, Tokens
const nav = @import("types.zig"); // types.zig re-exports Navigator, ScreenFn etc.

const Scene = navigator_mod.Scene;
const Tokens = navigator_mod.Tokens;
const Navigator = nav.Navigator;
const ScreenFn = nav.ScreenFn;

// ---------------------------------------------------------------------------
// Stub ScreenFn implementations
// ---------------------------------------------------------------------------

/// A simple ScreenFn that does nothing and ignores all parameters.
fn nopScreen(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = scene;
    _ = tokens;
    _ = app;
    _ = ctx;
}

/// A ScreenFn that records how many times it was called.
var call_count: u32 = 0;
fn countingScreen(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = scene;
    _ = tokens;
    _ = app;
    _ = ctx;
    call_count += 1;
}

/// A ScreenFn that returns an error.
fn failScreen(
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void {
    _ = scene;
    _ = tokens;
    _ = app;
    _ = ctx;
    return error.ScreenBuildFailed;
}

// Dummy app pointer — we just need a non-null *anyopaque.
var dummy_app_storage: u8 = 0;
const dummy_app: *anyopaque = @ptrCast(&dummy_app_storage);

// Tokens helper (light theme from the module 05 default palette).
fn defaultTokens() Tokens {
    const mod05 = @import("../05/types.zig");
    return mod05.Tokens.light(mod05.Palette.default());
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// AC1: register + push + currentName + depth
test "register and push sets name and depth" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);
    try nav_inst.register("settings", nopScreen);

    try nav_inst.push("home", null, &scene, tokens, dummy_app);

    try testing.expectEqual(@as(usize, 1), nav_inst.depth());
    try testing.expectEqualStrings("home", nav_inst.currentName().?);
}

// AC2: pop from depth 1 returns error.EmptyStack, scene unchanged
test "pop from depth 1 returns EmptyStack" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);
    try nav_inst.push("home", null, &scene, tokens, dummy_app);

    const result = nav_inst.pop(&scene, tokens, dummy_app);
    try testing.expectError(error.EmptyStack, result);

    // Depth must remain 1.
    try testing.expectEqual(@as(usize, 1), nav_inst.depth());
}

// AC3: replace on single-entry stack succeeds
test "replace on single-entry stack succeeds" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);
    try nav_inst.register("settings", nopScreen);

    try nav_inst.push("home", null, &scene, tokens, dummy_app);
    try nav_inst.replace("settings", null, &scene, tokens, dummy_app);

    try testing.expectEqual(@as(usize, 1), nav_inst.depth());
    try testing.expectEqualStrings("settings", nav_inst.currentName().?);
}

// AC4: requestPush + drainPending applies navigation
test "requestPush then drainPending applies navigation" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);
    try nav_inst.register("details", nopScreen);

    // Start at home.
    try nav_inst.push("home", null, &scene, tokens, dummy_app);
    try testing.expectEqual(@as(usize, 1), nav_inst.depth());

    // Queue a push to details.
    nav_inst.requestPush("details", null);

    // Before drain, depth is still 1.
    try testing.expectEqual(@as(usize, 1), nav_inst.depth());

    // Drain.
    try nav_inst.drainPending(&scene, tokens, dummy_app);

    try testing.expectEqual(@as(usize, 2), nav_inst.depth());
    try testing.expectEqualStrings("details", nav_inst.currentName().?);
}

// AC5: ctx null doesn't crash
test "null ctx passed to ScreenFn does not crash" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);
    // push with null ctx — must not crash.
    try nav_inst.push("home", null, &scene, tokens, dummy_app);
    try testing.expectEqual(@as(usize, 1), nav_inst.depth());
}

// AC6: Screen name not found → error.ScreenNotFound
test "push with unknown name returns ScreenNotFound" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);

    const result = nav_inst.push("nonexistent", null, &scene, tokens, dummy_app);
    try testing.expectError(error.ScreenNotFound, result);
}

// AC7: Push same screen twice → depth == 2
test "push same screen twice gives depth 2" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);

    try nav_inst.push("home", null, &scene, tokens, dummy_app);
    try nav_inst.push("home", null, &scene, tokens, dummy_app);

    try testing.expectEqual(@as(usize, 2), nav_inst.depth());
    try testing.expectEqualStrings("home", nav_inst.currentName().?);
}

// AC8: No memory leaks (uses testing.allocator)
test "no memory leaks" {
    const gpa = testing.allocator;

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("a", nopScreen);
    try nav_inst.register("b", nopScreen);

    try nav_inst.push("a", null, &scene, tokens, dummy_app);
    try nav_inst.push("b", null, &scene, tokens, dummy_app);
    try nav_inst.pop(&scene, tokens, dummy_app);
    try nav_inst.replace("b", null, &scene, tokens, dummy_app);

    // drainPending with requestPop
    nav_inst.requestPop();
    const r = nav_inst.drainPending(&scene, tokens, dummy_app);
    try testing.expectError(error.EmptyStack, r);
    // After a failed drain, pending was already cleared before the pop attempted.
    // Verify depth is still 1 (pop failed because depth == 1).
    try testing.expectEqual(@as(usize, 1), nav_inst.depth());
}

// Edge case: last-write-wins for pending requests
test "requestPush then requestPop last write wins" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);
    try nav_inst.register("details", nopScreen);

    try nav_inst.push("home", null, &scene, tokens, dummy_app);

    nav_inst.requestPush("details", null);
    nav_inst.requestPop(); // overwrites the push

    // Drain — should attempt pop, which returns EmptyStack (depth==1).
    const result = nav_inst.drainPending(&scene, tokens, dummy_app);
    try testing.expectError(error.EmptyStack, result);
    try testing.expectEqual(@as(usize, 1), nav_inst.depth());
    try testing.expectEqualStrings("home", nav_inst.currentName().?);
}

// currentName on empty stack returns null
test "currentName on empty stack returns null" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try testing.expect(nav_inst.currentName() == null);
}

// depth on empty stack returns 0
test "depth on empty stack is zero" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try testing.expectEqual(@as(usize, 0), nav_inst.depth());
}

// requestReplace is applied by drainPending
test "requestReplace then drainPending replaces top" {
    var gpa_state = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var scene = Scene.init(gpa);
    defer scene.deinit();
    const tokens = defaultTokens();

    var nav_inst = Navigator.init(gpa);
    defer nav_inst.deinit();

    try nav_inst.register("home", nopScreen);
    try nav_inst.register("settings", nopScreen);

    try nav_inst.push("home", null, &scene, tokens, dummy_app);
    nav_inst.requestReplace("settings", null);
    try nav_inst.drainPending(&scene, tokens, dummy_app);

    try testing.expectEqual(@as(usize, 1), nav_inst.depth());
    try testing.expectEqualStrings("settings", nav_inst.currentName().?);
}
