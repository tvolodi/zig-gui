//! Unit tests for M18-05 RH5: if / then / else conditional schemas
//!
//! Tests the conditional schema validation logic in src/08/types.zig.
//! Run: zig build test-08-conditional

const std = @import("std");
const testing = std.testing;
const F = @import("types.zig");

// ---------------------------------------------------------------------------
// if → then (condition passes)
// ---------------------------------------------------------------------------

test "if/then: condition passes → then schema applied, required missing → error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // if: value is a string → then: must be at least 5 chars
    const if_s   = F.Schema{ .type = .string };
    const then_s = F.Schema{ .type = .string, .min_length = 5 };

    const schema = F.Schema{
        .type        = .string,
        .if_schema   = &if_s,
        .then_schema = &then_s,
    };

    // "hi" is a string (if passes) but only 2 chars (then fails)
    var value = F.Value{ .string = "hi" };
    const errs = try F.validate(a, schema, &value);

    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .min_length) found = true;
    }
    try testing.expect(found);
}

test "if/then: condition passes → then schema applied, all constraints satisfied → pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const if_s   = F.Schema{ .type = .string };
    const then_s = F.Schema{ .type = .string, .min_length = 3 };

    const schema = F.Schema{
        .type        = .string,
        .if_schema   = &if_s,
        .then_schema = &then_s,
    };

    // "hello" is a string and len >= 3 → pass
    var value = F.Value{ .string = "hello" };
    const errs = try F.validate(a, schema, &value);

    try testing.expectEqual(@as(usize, 0), errs.len);
}

// ---------------------------------------------------------------------------
// if → else (condition fails)
// ---------------------------------------------------------------------------

test "if/else: condition fails → else schema applied" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // if: value is a string → else: must be integer with minimum 0
    const if_s   = F.Schema{ .type = .string };
    const else_s = F.Schema{ .type = .integer, .minimum = 0 };

    const schema = F.Schema{
        .type        = .integer,
        .if_schema   = &if_s,
        .else_schema = &else_s,
    };

    // -5 is not a string (if fails) → else applies → -5 < minimum 0 → error
    var value = F.Value{ .int = -5 };
    const errs = try F.validate(a, schema, &value);

    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .minimum) found = true;
    }
    try testing.expect(found);
}

test "if/else: condition fails → else schema applied, passes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const if_s   = F.Schema{ .type = .string };
    const else_s = F.Schema{ .type = .integer, .minimum = 0 };

    const schema = F.Schema{
        .type        = .integer,
        .if_schema   = &if_s,
        .else_schema = &else_s,
    };

    // 10 is not a string (if fails) → else applies → 10 >= 0 → pass
    var value = F.Value{ .int = 10 };
    const errs = try F.validate(a, schema, &value);

    try testing.expectEqual(@as(usize, 0), errs.len);
}

// ---------------------------------------------------------------------------
// if without else: condition fails → no constraints applied
// ---------------------------------------------------------------------------

test "if/then (no else): condition fails → no additional errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // if: value is a string → then: requires min_length 100
    // (but if condition fails, then is not applied)
    const if_s   = F.Schema{ .type = .string };
    const then_s = F.Schema{ .type = .string, .min_length = 100 };

    const schema = F.Schema{
        .type        = .integer,
        .if_schema   = &if_s,
        .then_schema = &then_s,
    };

    // 42 is not a string → if fails → then not applied → no error
    var value = F.Value{ .int = 42 };
    const errs = try F.validate(a, schema, &value);

    try testing.expectEqual(@as(usize, 0), errs.len);
}

// ---------------------------------------------------------------------------
// Nested / complex condition
// ---------------------------------------------------------------------------

test "if/then/else with required field condition" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // if: object has "payment_type" required → then: also require "cvv"
    const if_s = F.Schema{
        .type     = .object,
        .required = &.{"payment_type"},
    };
    const then_s = F.Schema{
        .type     = .object,
        .required = &.{"cvv"},
    };

    const schema = F.Schema{
        .type        = .object,
        .if_schema   = &if_s,
        .then_schema = &then_s,
    };

    // payment_type present (if passes) but cvv absent (then fails)
    const fields = [_]F.Field{
        .{ .key = "payment_type", .value = .{ .string = "card" } },
    };
    var value = F.Value{ .object = @constCast(&fields) };
    const errs = try F.validate(a, schema, &value);

    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .required_missing) found = true;
    }
    try testing.expect(found);
}

test "if/then/else with required field condition — passes when all fields present" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const if_s = F.Schema{
        .type     = .object,
        .required = &.{"payment_type"},
    };
    const then_s = F.Schema{
        .type     = .object,
        .required = &.{"cvv"},
    };

    const schema = F.Schema{
        .type        = .object,
        .if_schema   = &if_s,
        .then_schema = &then_s,
    };

    const fields = [_]F.Field{
        .{ .key = "payment_type", .value = .{ .string = "card" } },
        .{ .key = "cvv",          .value = .{ .string = "123" } },
    };
    var value = F.Value{ .object = @constCast(&fields) };
    const errs = try F.validate(a, schema, &value);

    try testing.expectEqual(@as(usize, 0), errs.len);
}
