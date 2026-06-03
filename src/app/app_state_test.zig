//! Acceptance tests for AppState(T) — R81 (M8-02).
//!
//! All tests are pure (no GPU, no GLFW). Uses std.testing.allocator for leak detection.
//! Covers every acceptance criterion and edge case in R81.

const std = @import("std");
const AppState = @import("app_state.zig").AppState;
const Signal = @import("signal.zig").Signal;

// ---------------------------------------------------------------------------
// Helper: create a zero-capacity dummy dirty bitset for signals that are not
// bound to any ElementStore element (no subscribers need dirty marking).
// ---------------------------------------------------------------------------
fn makeDummyDirty(gpa: std.mem.Allocator) !std.DynamicBitSetUnmanaged {
    return std.DynamicBitSetUnmanaged.initEmpty(gpa, 0);
}

// ===========================================================================
// AC-2: AppState(T).init with three Signal fields compiles and runs.
// AC-3: deinit calls .deinit() on each Signal; no leaks.
// ===========================================================================

test "AppState: init/deinit with three Signal fields, no leaks" {
    const gpa = std.testing.allocator;

    var dummy = try makeDummyDirty(gpa);
    defer dummy.deinit(gpa);

    const MyState = struct {
        username: Signal([]const u8),
        is_logged_in: Signal(bool),
        item_count: Signal(u32),
    };

    var state = try AppState(MyState).init(gpa, .{
        .username = Signal([]const u8).init(gpa, "", &dummy),
        .is_logged_in = Signal(bool).init(gpa, false, &dummy),
        .item_count = Signal(u32).init(gpa, 0, &dummy),
    });
    defer state.deinit();

    // Basic sanity: values are as initialised.
    try std.testing.expectEqualStrings("", state.get().username.get());
    try std.testing.expect(state.get().is_logged_in.get() == false);
    try std.testing.expectEqual(@as(u32, 0), state.get().item_count.get());
}

// ===========================================================================
// AC-4: get() returns a mutable pointer; mutations via signal.set() are
//        reflected in subsequent signal.get() calls.
// ===========================================================================

test "AppState.get: mutations via signal.set are visible through get()" {
    const gpa = std.testing.allocator;

    var dummy = try makeDummyDirty(gpa);
    defer dummy.deinit(gpa);

    const S = struct {
        counter: Signal(u32),
    };

    var state = try AppState(S).init(gpa, .{
        .counter = Signal(u32).init(gpa, 0, &dummy),
    });
    defer state.deinit();

    state.get().counter.set(42);
    try std.testing.expectEqual(@as(u32, 42), state.get().counter.get());

    state.get().counter.set(100);
    try std.testing.expectEqual(@as(u32, 100), state.get().counter.get());
}

// ===========================================================================
// AC-5: setGlobal / getGlobal round-trip; getGlobal returns null before call.
// ===========================================================================

test "AppState.getGlobal: returns null before setGlobal is called" {
    const S = struct {
        val: Signal(u32),
    };

    // Reset the global first (in case a previous test set it).
    // We use the type-level _global directly by checking getGlobal.
    // Since each AppState(T) instantiation gets its own _global, and
    // this is a fresh type, it starts as null.
    const AS = AppState(S);
    try std.testing.expect(AS.getGlobal() == null);
}

test "AppState.setGlobal / getGlobal: round-trip" {
    const gpa = std.testing.allocator;

    var dummy = try makeDummyDirty(gpa);
    defer dummy.deinit(gpa);

    const S = struct {
        val: Signal(u32),
    };

    // Use a distinct wrapper type to avoid colliding with the null-check test above.
    const AS = AppState(S);

    var state = try AS.init(gpa, .{
        .val = Signal(u32).init(gpa, 7, &dummy),
    });
    defer state.deinit();

    state.setGlobal();

    const g = AS.getGlobal();
    try std.testing.expect(g != null);
    try std.testing.expectEqual(@as(u32, 7), g.?.get().val.get());

    // Reset to null to avoid polluting other tests that use this type.
    AS._global = null;
}

// ===========================================================================
// AC-6 / Edge: struct with a plain u32 field compiles; field unmodified by deinit.
// ===========================================================================

test "AppState: plain scalar field unmodified by deinit, no crash" {
    const gpa = std.testing.allocator;

    var dummy = try makeDummyDirty(gpa);
    defer dummy.deinit(gpa);

    const S = struct {
        sig: Signal(u32),
        plain: u32,
    };

    var state = try AppState(S).init(gpa, .{
        .sig = Signal(u32).init(gpa, 1, &dummy),
        .plain = 0xDEAD,
    });
    defer state.deinit();

    // plain field should still hold its value after mutations to sig.
    state.get().sig.set(99);
    try std.testing.expectEqual(@as(u32, 0xDEAD), state.get().plain);
}

// ===========================================================================
// Edge: T = struct {} — init and deinit are no-ops; no crash.
// ===========================================================================

test "AppState: empty state struct — init/deinit are no-ops" {
    const gpa = std.testing.allocator;

    const S = struct {};
    var state = try AppState(S).init(gpa, .{});
    defer state.deinit();

    // If we reach here without a crash, the test passes.
    const ptr = state.get();
    _ = ptr;
}

// ===========================================================================
// Edge: Signal with zero subscribers — set() does not crash.
// ===========================================================================

test "AppState: signal with zero subscribers — set() does not crash" {
    const gpa = std.testing.allocator;

    var dummy = try makeDummyDirty(gpa);
    defer dummy.deinit(gpa);

    const S = struct {
        val: Signal(u32),
    };

    var state = try AppState(S).init(gpa, .{
        .val = Signal(u32).init(gpa, 0, &dummy),
    });
    defer state.deinit();

    // No subscribers registered; set() must not crash.
    state.get().val.set(1);
    state.get().val.set(2);
    try std.testing.expectEqual(@as(u32, 2), state.get().val.get());
}

// ===========================================================================
// Edge: two calls to setGlobal — second overwrites first, no leak.
// ===========================================================================

test "AppState.setGlobal: second call overwrites first, no leak" {
    const gpa = std.testing.allocator;

    var dummy = try makeDummyDirty(gpa);
    defer dummy.deinit(gpa);

    const S = struct {
        val: Signal(u32),
    };

    const AS = AppState(S);

    var state_a = try AS.init(gpa, .{
        .val = Signal(u32).init(gpa, 1, &dummy),
    });
    defer state_a.deinit();

    var state_b = try AS.init(gpa, .{
        .val = Signal(u32).init(gpa, 2, &dummy),
    });
    defer state_b.deinit();

    state_a.setGlobal();
    try std.testing.expectEqual(@as(u32, 1), AS.getGlobal().?.get().val.get());

    state_b.setGlobal();
    try std.testing.expectEqual(@as(u32, 2), AS.getGlobal().?.get().val.get());

    // Clean up global to avoid polluting other tests.
    AS._global = null;
}
