//! Unit tests for BudgetedArena (RA1 — M10-02).
//! Deterministic; no GPU/GLFW/wall-clock.

const std = @import("std");
const BudgetedArena = @import("budgeted_arena.zig").BudgetedArena;



test "BudgetedArena: allocating within budget succeeds" {
    var ba = BudgetedArena.init(std.testing.allocator, 1024);
    defer ba.deinit();

    const alloc = ba.allocator();
    const buf = try alloc.alloc(u8, 256);
    try std.testing.expectEqual(@as(usize, 256), buf.len);
    try std.testing.expect(ba.usedBytes() >= 256);
}

test "BudgetedArena: allocating past budget returns OutOfMemory" {
    var ba = BudgetedArena.init(std.testing.allocator, 64);
    defer ba.deinit();

    const alloc = ba.allocator();
    // First allocation: 64 bytes exactly — should succeed.
    const buf = try alloc.alloc(u8, 64);
    try std.testing.expectEqual(@as(usize, 64), buf.len);

    // Second allocation: 1 byte — should fail (budget exhausted).
    const result = alloc.alloc(u8, 1);
    try std.testing.expectError(error.OutOfMemory, result);

    // First allocation still readable.
    buf[0] = 42;
    try std.testing.expectEqual(@as(u8, 42), buf[0]);
}

test "BudgetedArena: reset resets usedBytes to zero" {
    var ba = BudgetedArena.init(std.testing.allocator, 512);
    defer ba.deinit();

    const alloc = ba.allocator();
    _ = try alloc.alloc(u8, 128);
    try std.testing.expect(ba.usedBytes() >= 128);

    ba.reset();
    try std.testing.expectEqual(@as(usize, 0), ba.usedBytes());
}

test "BudgetedArena: reset then allocate within budget succeeds" {
    var ba = BudgetedArena.init(std.testing.allocator, 64);
    defer ba.deinit();

    const alloc = ba.allocator();
    _ = try alloc.alloc(u8, 64);
    ba.reset();

    // Should succeed again after reset.
    const buf2 = try alloc.alloc(u8, 32);
    try std.testing.expectEqual(@as(usize, 32), buf2.len);
}

test "BudgetedArena: budget_bytes = 0 means unlimited" {
    var ba = BudgetedArena.init(std.testing.allocator, 0);
    defer ba.deinit();

    const alloc = ba.allocator();
    // Allocate more than any typical budget — should succeed.
    const buf = try alloc.alloc(u8, 4096);
    try std.testing.expectEqual(@as(usize, 4096), buf.len);
    try std.testing.expectEqual(@as(usize, 0), ba.budgetBytes());
}

test "BudgetedArena: multiple small allocations accumulate correctly" {
    var ba = BudgetedArena.init(std.testing.allocator, 100);
    defer ba.deinit();

    const alloc = ba.allocator();
    // 10 allocations of 9 bytes each = 90 bytes total, within budget.
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        _ = try alloc.alloc(u8, 9);
    }
    try std.testing.expect(ba.usedBytes() >= 90);

    // Next allocation of 11 bytes would exceed 100 byte budget — should fail.
    const result = alloc.alloc(u8, 11);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "BudgetedArena: first allocation exactly equals budget succeeds" {
    var ba = BudgetedArena.init(std.testing.allocator, 32);
    defer ba.deinit();

    const alloc = ba.allocator();
    const buf = try alloc.alloc(u8, 32);
    try std.testing.expectEqual(@as(usize, 32), buf.len);
}

test "BudgetedArena: AppOptions.arena_budget_bytes defaults to 0" {
    const AppOptions = @import("app.zig").AppOptions;
    const opts = AppOptions{ .font_path = "dummy.ttf" };
    try std.testing.expectEqual(@as(usize, 0), opts.arena_budget_bytes);
}
