//! App headless unit tests (R10 / R11).
//! No GPU, no GLFW.  Tests cover EventQueue, AppOptions construction, and event types.

const std = @import("std");
const types = @import("types.zig");
const events_mod = @import("events.zig");
const mod01 = @import("../01/types.zig");

const AppOptions = types.AppOptions;
const EventQueue = events_mod.EventQueue;
const Event = events_mod.Event; // = mod01.InputEvent
const MouseButton = mod01.MouseButton;
const Action = mod01.InputAction;
const Key = mod01.Key;
const Modifiers = mod01.Modifiers;
const CAPACITY = events_mod.CAPACITY;

// ---------------------------------------------------------------------------
// AppOptions can be constructed with required fields only.
// ---------------------------------------------------------------------------

test "AppOptions default construction" {
    const opts = AppOptions{
        .font_path = "test.ttf",
    };
    try std.testing.expectEqualSlices(u8, "test.ttf", opts.font_path);
    try std.testing.expectApproxEqAbs(@as(f32, 16), opts.font_size_px, 0.001);
}

test "AppOptions custom font_size_px" {
    const opts = AppOptions{
        .font_path = "/fonts/my.ttf",
        .font_size_px = 24.0,
    };
    try std.testing.expectApproxEqAbs(@as(f32, 24.0), opts.font_size_px, 0.001);
}

// ---------------------------------------------------------------------------
// EventQueue — push / drain / clear ordering.
// ---------------------------------------------------------------------------

test "EventQueue push drain clear basic ordering" {
    var q = EventQueue.init(std.testing.allocator);
    defer q.deinit();

    q.push(Event{ .mouse_move = .{ .x = 10, .y = 20 } });
    q.push(Event{ .mouse_move = .{ .x = 30, .y = 40 } });

    const evs = q.drain();
    try std.testing.expectEqual(@as(usize, 2), evs.len);

    switch (evs[0]) {
        .mouse_move => |m| {
            try std.testing.expectApproxEqAbs(@as(f32, 10), m.x, 0.001);
            try std.testing.expectApproxEqAbs(@as(f32, 20), m.y, 0.001);
        },
        else => return error.WrongEventType,
    }

    q.clear();
    try std.testing.expectEqual(@as(usize, 0), q.drain().len);
}

// ---------------------------------------------------------------------------
// EventQueue — overflow at 257 pushes: 256 delivered, warn logged.
// ---------------------------------------------------------------------------

test "EventQueue overflow delivers exactly 256 events" {
    var q = EventQueue.init(std.testing.allocator);
    defer q.deinit();

    var i: usize = 0;
    while (i < CAPACITY + 1) : (i += 1) {
        q.push(Event{ .scroll = .{ .dx = @floatFromInt(i), .dy = 0 } });
    }
    const evs = q.drain();
    try std.testing.expectEqual(CAPACITY, evs.len);
    // Spot-check first and last.
    switch (evs[0]) {
        .scroll => |s| try std.testing.expectApproxEqAbs(@as(f32, 0), s.dx, 0.001),
        else => return error.WrongEventType,
    }
    switch (evs[CAPACITY - 1]) {
        .scroll => |s| try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(CAPACITY - 1)), s.dx, 0.001),
        else => return error.WrongEventType,
    }
}

// ---------------------------------------------------------------------------
// Event type coverage — all variants compile and work.
// ---------------------------------------------------------------------------

test "Event variants are usable" {
    // MouseButton
    const btn: MouseButton = .left;
    try std.testing.expectEqual(MouseButton.left, btn);

    // Action
    const act: Action = .press;
    try std.testing.expectEqual(Action.press, act);

    // Key
    const k: Key = .enter;
    try std.testing.expectEqual(Key.enter, k);

    // Modifiers
    const mods = Modifiers{ .shift = true, .ctrl = false };
    try std.testing.expect(mods.shift);
    try std.testing.expect(!mods.ctrl);

    // Event union
    const ev = Event{ .key = .{ .key = .escape, .action = .release, .mods = .{} } };
    switch (ev) {
        .key => |ke| try std.testing.expectEqual(Key.escape, ke.key),
        else => return error.WrongEventType,
    }
}

test "Event char carries Unicode codepoint" {
    const ev = Event{ .char = .{ .codepoint = 0x044F } }; // Cyrillic 'я'
    switch (ev) {
        .char => |ch| try std.testing.expectEqual(@as(u21, 0x044F), ch.codepoint),
        else => return error.WrongEventType,
    }
}
