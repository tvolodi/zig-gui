//! Unit tests for M18-03 RH3: allOf / anyOf / oneOf combinators
//!
//! Tests the combinator validation logic in src/08/types.zig.
//! Run: zig build test-08-combinator

const std = @import("std");
const testing = std.testing;
const F = @import("types.zig");

// ---------------------------------------------------------------------------
// anyOf — at least one sub-schema must pass
// ---------------------------------------------------------------------------

test "anyOf passes when one sub-schema matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const string_schema = F.Schema{ .type = .string };
    const int_schema    = F.Schema{ .type = .integer };
    const schema = F.Schema{ .any_of = &.{ string_schema, int_schema } };

    var value = F.Value{ .string = "hello" };
    const errs = try F.validate(arena.allocator(), schema, &value);

    // Passes — string matches first sub-schema
    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "anyOf passes when second sub-schema matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const string_schema = F.Schema{ .type = .string };
    const int_schema    = F.Schema{ .type = .integer };
    const schema = F.Schema{ .any_of = &.{ string_schema, int_schema } };

    var value = F.Value{ .int = 42 };
    const errs = try F.validate(arena.allocator(), schema, &value);

    // Passes — integer matches second sub-schema
    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "anyOf fails when no sub-schema matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const string_schema = F.Schema{ .type = .string };
    const int_schema    = F.Schema{ .type = .integer };
    const schema = F.Schema{ .any_of = &.{ string_schema, int_schema } };

    // Boolean matches neither string nor integer
    var value = F.Value{ .bool = true };
    const errs = try F.validate(arena.allocator(), schema, &value);

    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .any_of_mismatch) found = true;
    }
    try testing.expect(found);
}

test "anyOf with empty sub-schemas emits any_of_mismatch (no schema can pass)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const schema = F.Schema{ .any_of = &.{} };
    var value = F.Value{ .string = "test" };
    const errs = try F.validate(arena.allocator(), schema, &value);

    // Empty anyOf — no schema passes → mismatch
    var found = false;
    for (errs) |e| {
        if (e.kind == .any_of_mismatch) found = true;
    }
    try testing.expect(found);
}

// ---------------------------------------------------------------------------
// oneOf — exactly one sub-schema must pass
// ---------------------------------------------------------------------------

test "oneOf passes when exactly one sub-schema matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const string_schema = F.Schema{ .type = .string };
    const int_schema    = F.Schema{ .type = .integer };
    const schema = F.Schema{ .one_of = &.{ string_schema, int_schema } };

    var value = F.Value{ .string = "hello" };
    const errs = try F.validate(arena.allocator(), schema, &value);

    // Passes — exactly one (string) matches
    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "oneOf fails when no sub-schema matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const string_schema = F.Schema{ .type = .string };
    const int_schema    = F.Schema{ .type = .integer };
    const schema = F.Schema{ .one_of = &.{ string_schema, int_schema } };

    var value = F.Value{ .bool = true };
    const errs = try F.validate(arena.allocator(), schema, &value);

    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .one_of_mismatch) found = true;
    }
    try testing.expect(found);
}

test "oneOf fails when more than one sub-schema matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Two schemas both accept numbers
    const num_schema1 = F.Schema{ .type = .number };
    const num_schema2 = F.Schema{ .type = .number };
    const schema = F.Schema{ .one_of = &.{ num_schema1, num_schema2 } };

    // Float matches BOTH sub-schemas
    var value = F.Value{ .float = 3.14 };
    const errs = try F.validate(arena.allocator(), schema, &value);

    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .one_of_mismatch) found = true;
    }
    try testing.expect(found);
}

test "oneOf with empty sub-schemas emits one_of_mismatch" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const schema = F.Schema{ .one_of = &.{} };
    var value = F.Value{ .string = "test" };
    const errs = try F.validate(arena.allocator(), schema, &value);

    var found = false;
    for (errs) |e| {
        if (e.kind == .one_of_mismatch) found = true;
    }
    try testing.expect(found);
}

// ---------------------------------------------------------------------------
// allOf — all sub-schemas must pass
// ---------------------------------------------------------------------------

test "allOf passes when all sub-schemas match" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Both schemas constrain the same type (object)
    const schema1 = F.Schema{
        .type     = .object,
        .required = &.{"name"},
    };
    const schema2 = F.Schema{
        .type     = .object,
        .required = &.{"age"},
    };
    const schema = F.Schema{ .all_of = &.{ schema1, schema2 } };

    // Object with both required fields — both schemas pass
    const fields = [_]F.Field{
        .{ .key = "name", .value = .{ .string = "Alice" } },
        .{ .key = "age",  .value = .{ .int = 30 } },
    };
    var value = F.Value{ .object = @constCast(&fields) };
    const errs = try F.validate(arena.allocator(), schema, &value);

    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "allOf emits errors when one sub-schema fails" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const schema1 = F.Schema{
        .type     = .object,
        .required = &.{"name"},
    };
    const schema2 = F.Schema{
        .type     = .object,
        .required = &.{"age"},
    };
    const schema = F.Schema{ .all_of = &.{ schema1, schema2 } };

    // Missing "age" — schema2 will fail
    const fields = [_]F.Field{
        .{ .key = "name", .value = .{ .string = "Bob" } },
    };
    var value = F.Value{ .object = @constCast(&fields) };
    const errs = try F.validate(arena.allocator(), schema, &value);

    // Should have at least one required_missing error for "age"
    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .required_missing and std.mem.eql(u8, e.path, "age")) {
            found = true;
        }
    }
    try testing.expect(found);
}

test "allOf with empty sub-schemas passes (no constraints)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const schema = F.Schema{ .all_of = &.{} };
    var value = F.Value{ .string = "anything" };
    const errs = try F.validate(arena.allocator(), schema, &value);

    // Empty allOf — no constraints → passes
    try testing.expectEqual(@as(usize, 0), errs.len);
}
