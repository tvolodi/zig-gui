//! EventQueue acceptance tests (R11).
//! No GPU, no GLFW.

const std = @import("std");
const events_mod = @import("events.zig");
const types = @import("types.zig");

const EventQueue = events_mod.EventQueue;
const Event = events_mod.Event; // = mod01.InputEvent
const CAPACITY = events_mod.CAPACITY;

// ---------------------------------------------------------------------------
// Test 1: Push N events, drain returns all N in order.
// ---------------------------------------------------------------------------

test "EventQueue push and drain preserves order" {
    const gpa = std.testing.allocator;
    var q = EventQueue.init(gpa);
    defer q.deinit();

    const n: usize = 5;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        q.push(Event{ .mouse_move = .{ .x = @floatFromInt(i), .y = 0 } });
    }

    const evs = q.drain();
    try std.testing.expectEqual(n, evs.len);
    i = 0;
    while (i < n) : (i += 1) {
        switch (evs[i]) {
            .mouse_move => |m| try std.testing.expectApproxEqAbs(@as(f32, @floatFromInt(i)), m.x, 0.001),
            else => return error.WrongEventType,
        }
    }
}

// ---------------------------------------------------------------------------
// Test 2: Drain after clear returns zero events.
// ---------------------------------------------------------------------------

test "EventQueue drain after clear returns empty slice" {
    const gpa = std.testing.allocator;
    var q = EventQueue.init(gpa);
    defer q.deinit();

    q.push(Event{ .mouse_move = .{ .x = 1, .y = 2 } });
    q.push(Event{ .mouse_move = .{ .x = 3, .y = 4 } });

    _ = q.drain();
    q.clear();

    const evs2 = q.drain();
    try std.testing.expectEqual(@as(usize, 0), evs2.len);
}

// ---------------------------------------------------------------------------
// Test 3: Push 257 events — only 256 delivered, warn logged, no crash.
// ---------------------------------------------------------------------------

test "EventQueue overflow: 257 pushes delivers 256 events" {
    const gpa = std.testing.allocator;
    var q = EventQueue.init(gpa);
    defer q.deinit();

    var i: usize = 0;
    while (i < CAPACITY + 1) : (i += 1) {
        q.push(Event{ .scroll = .{ .dx = @floatFromInt(i), .dy = 0 } });
    }

    const evs = q.drain();
    try std.testing.expectEqual(CAPACITY, evs.len);
    // First event is index 0, last is CAPACITY - 1.
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
// Test 4: Multiple drain/clear cycles work independently.
// ---------------------------------------------------------------------------

test "EventQueue multiple drain/clear cycles" {
    const gpa = std.testing.allocator;
    var q = EventQueue.init(gpa);
    defer q.deinit();

    // Cycle 1
    q.push(Event{ .char = .{ .codepoint = 'A' } });
    {
        const evs = q.drain();
        try std.testing.expectEqual(@as(usize, 1), evs.len);
        q.clear();
    }

    // Cycle 2 — queue should be empty and ready for new events.
    q.push(Event{ .char = .{ .codepoint = 'B' } });
    q.push(Event{ .char = .{ .codepoint = 'C' } });
    {
        const evs = q.drain();
        try std.testing.expectEqual(@as(usize, 2), evs.len);
        switch (evs[0]) {
            .char => |ch| try std.testing.expectEqual(@as(u21, 'B'), ch.codepoint),
            else => return error.WrongEventType,
        }
        q.clear();
    }

    // After second clear: empty.
    try std.testing.expectEqual(@as(usize, 0), q.drain().len);
}

// ---------------------------------------------------------------------------
// Test 5: All Event variants can be pushed and drained.
// ---------------------------------------------------------------------------

test "EventQueue handles all Event variants" {
    const gpa = std.testing.allocator;
    var q = EventQueue.init(gpa);
    defer q.deinit();

    const mod01 = @import("../01/types.zig");

    q.push(Event{ .mouse_move = .{ .x = 1.0, .y = 2.0 } });
    q.push(Event{ .mouse_button = .{
        .button = .left,
        .action = .press,
        .x = 10,
        .y = 20,
    } });
    q.push(Event{ .scroll = .{ .dx = 0.5, .dy = -1.0 } });
    q.push(Event{ .key = .{
        .key = .enter,
        .action = .release,
        .mods = mod01.Modifiers{ .shift = true },
    } });
    q.push(Event{ .char = .{ .codepoint = 0x0430 } }); // Cyrillic 'а'

    const evs = q.drain();
    try std.testing.expectEqual(@as(usize, 5), evs.len);
    q.clear();
    try std.testing.expectEqual(@as(usize, 0), q.drain().len);
}
