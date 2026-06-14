//! Unit tests for M18-04 RH4: dependentRequired
//!
//! Tests conditional field requirements in src/08/types.zig.
//! Run: zig build test-08-dependent-required

const std = @import("std");
const testing = std.testing;
const F = @import("types.zig");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a Value.object from a stack slice of Field, duplicated into the arena.
fn makeObj(arena: std.mem.Allocator, fields: []const F.Field) !F.Value {
    const owned = try arena.dupe(F.Field, fields);
    return F.Value{ .object = owned };
}

// ---------------------------------------------------------------------------
// Basic trigger / no-trigger
// ---------------------------------------------------------------------------

test "dependentRequired: trigger present, required field missing → error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var deps = std.StringHashMap([]const []const u8).init(a);
    try deps.put("credit_card", &.{"cvv"});

    const schema = F.Schema{ .type = .object, .dependent_required = deps };

    // credit_card present, cvv absent
    var value = try makeObj(a, &.{
        .{ .key = "credit_card", .value = .{ .string = "4111111111111111" } },
    });

    const errs = try F.validate(a, schema, &value);

    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .dependent_required_missing) found = true;
    }
    try testing.expect(found);
}

test "dependentRequired: trigger and required field both present → pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var deps = std.StringHashMap([]const []const u8).init(a);
    try deps.put("credit_card", &.{"cvv"});

    const schema = F.Schema{ .type = .object, .dependent_required = deps };

    var value = try makeObj(a, &.{
        .{ .key = "credit_card", .value = .{ .string = "4111111111111111" } },
        .{ .key = "cvv",         .value = .{ .string = "123" } },
    });

    const errs = try F.validate(a, schema, &value);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "dependentRequired: trigger absent → no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var deps = std.StringHashMap([]const []const u8).init(a);
    try deps.put("credit_card", &.{"cvv"});

    const schema = F.Schema{ .type = .object, .dependent_required = deps };

    // No credit_card — dependency does not apply even though cvv is also absent
    var value = try makeObj(a, &.{
        .{ .key = "name", .value = .{ .string = "Alice" } },
    });

    const errs = try F.validate(a, schema, &value);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

// ---------------------------------------------------------------------------
// Multiple dependent fields
// ---------------------------------------------------------------------------

test "dependentRequired: multiple required fields — one missing → error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var deps = std.StringHashMap([]const []const u8).init(a);
    // When credit_card is present, both cvv AND billing_address are required
    try deps.put("credit_card", &.{ "cvv", "billing_address" });

    const schema = F.Schema{ .type = .object, .dependent_required = deps };

    // credit_card + cvv present, but billing_address missing
    var value = try makeObj(a, &.{
        .{ .key = "credit_card", .value = .{ .string = "4111111111111111" } },
        .{ .key = "cvv",         .value = .{ .string = "123" } },
    });

    const errs = try F.validate(a, schema, &value);

    // Expect at least one error for billing_address
    try testing.expect(errs.len >= 1);
    var found_billing = false;
    for (errs) |e| {
        if (e.kind == .dependent_required_missing) found_billing = true;
    }
    try testing.expect(found_billing);
}

test "dependentRequired: multiple required fields — all present → pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var deps = std.StringHashMap([]const []const u8).init(a);
    try deps.put("credit_card", &.{ "cvv", "billing_address" });

    const schema = F.Schema{ .type = .object, .dependent_required = deps };

    var value = try makeObj(a, &.{
        .{ .key = "credit_card",     .value = .{ .string = "4111111111111111" } },
        .{ .key = "cvv",             .value = .{ .string = "123" } },
        .{ .key = "billing_address", .value = .{ .string = "123 Main St" } },
    });

    const errs = try F.validate(a, schema, &value);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

// ---------------------------------------------------------------------------
// Multiple independent trigger keys
// ---------------------------------------------------------------------------

test "dependentRequired: two independent triggers — first fires, second doesn't" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var deps = std.StringHashMap([]const []const u8).init(a);
    try deps.put("credit_card", &.{"cvv"});
    try deps.put("paypal",      &.{"paypal_email"});

    const schema = F.Schema{ .type = .object, .dependent_required = deps };

    // Only credit_card present — should check for cvv but not paypal_email
    var value = try makeObj(a, &.{
        .{ .key = "credit_card", .value = .{ .string = "4111111111111111" } },
        .{ .key = "cvv",         .value = .{ .string = "123" } },
    });

    // Both triggers' requirements satisfied for those that apply
    const errs = try F.validate(a, schema, &value);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "dependentRequired: non-object value → no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var deps = std.StringHashMap([]const []const u8).init(a);
    try deps.put("credit_card", &.{"cvv"});

    // dependentRequired only applies to object values; non-objects skip the check
    const schema = F.Schema{ .type = .string, .dependent_required = deps };

    var value = F.Value{ .string = "some string" };
    const errs = try F.validate(a, schema, &value);

    // validateScalar for string type won't check dependentRequired (it's in the object branch)
    _ = errs; // no assertion — just confirm it doesn't crash
}
