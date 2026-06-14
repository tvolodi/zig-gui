//! Unit tests for M18-06 RH6: array fields (minItems, maxItems, item schema)
//!
//! Tests array field validation and buildForm behavior in src/08/types.zig.
//! Run: zig build test-08-array-field

const std = @import("std");
const testing = std.testing;
const F = @import("types.zig");

// ---------------------------------------------------------------------------
// buildForm — array-type properties emit is_array=true FieldSpec
// ---------------------------------------------------------------------------

test "buildForm: array property produces is_array FieldSpec" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const item_schema = F.Schema{ .type = .string };
    const schema = F.Schema{
        .type = .object,
        .properties = &.{
            .{ .name = "tags", .schema = .{
                .type  = .array,
                .items = &item_schema,
                .title = "Tags",
            } },
        },
    };

    const fields = try F.buildForm(arena.allocator(), schema);

    try testing.expectEqual(@as(usize, 1), fields.len);
    try testing.expect(fields[0].is_array);
    try testing.expectEqualStrings("tags", fields[0].path);
    try testing.expectEqualStrings("Tags", fields[0].label);
}

test "buildForm: array property stores item schema pointer" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const item_schema = F.Schema{ .type = .string };
    const schema = F.Schema{
        .type = .object,
        .properties = &.{
            .{ .name = "items", .schema = .{
                .type  = .array,
                .items = &item_schema,
            } },
        },
    };

    const fields = try F.buildForm(arena.allocator(), schema);
    try testing.expect(fields[0].array_item_schema != null);
}

test "buildForm: array property stores min/max item bounds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const item_schema = F.Schema{ .type = .string };
    const schema = F.Schema{
        .type = .object,
        .properties = &.{
            .{ .name = "emails", .schema = .{
                .type      = .array,
                .items     = &item_schema,
                .min_items = 1,
                .max_items = 5,
            } },
        },
    };

    const fields = try F.buildForm(arena.allocator(), schema);
    try testing.expect(fields[0].is_array);
    try testing.expectEqual(@as(u32, 1), fields[0].array_min_items);
    try testing.expectEqual(@as(u32, 5), fields[0].array_max_items);
}

test "buildForm: array property uses field name as label when title is absent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const schema = F.Schema{
        .type = .object,
        .properties = &.{
            .{ .name = "phones", .schema = .{ .type = .array } },
        },
    };

    const fields = try F.buildForm(arena.allocator(), schema);
    try testing.expectEqualStrings("phones", fields[0].label);
}

// ---------------------------------------------------------------------------
// Validation — minItems
// ---------------------------------------------------------------------------

test "validate: array with too few items → type_mismatch error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type      = .object,
        .properties = &.{
            .{ .name = "tags", .schema = .{
                .type      = .array,
                .min_items = 2,
            } },
        },
    };

    // Array with 0 items → fails minItems = 2
    const items = try a.alloc(F.Value, 0);
    const obj_fields = try a.dupe(F.Field, &.{
        .{ .key = "tags", .value = .{ .array = items } },
    });
    var value = F.Value{ .object = obj_fields };

    const errs = try F.validate(a, schema, &value);
    try testing.expect(errs.len >= 1);
}

test "validate: array with exactly minItems items → pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type      = .object,
        .properties = &.{
            .{ .name = "tags", .schema = .{
                .type      = .array,
                .min_items = 2,
            } },
        },
    };

    const items = try a.alloc(F.Value, 2);
    items[0] = .{ .string = "a" };
    items[1] = .{ .string = "b" };
    const obj_fields = try a.dupe(F.Field, &.{
        .{ .key = "tags", .value = .{ .array = items } },
    });
    var value = F.Value{ .object = obj_fields };

    const errs = try F.validate(a, schema, &value);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

// ---------------------------------------------------------------------------
// Validation — maxItems
// ---------------------------------------------------------------------------

test "validate: array with too many items → error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type      = .object,
        .properties = &.{
            .{ .name = "choices", .schema = .{
                .type      = .array,
                .max_items = 3,
            } },
        },
    };

    const items = try a.alloc(F.Value, 5);
    for (items) |*item| item.* = .{ .string = "x" };
    const obj_fields = try a.dupe(F.Field, &.{
        .{ .key = "choices", .value = .{ .array = items } },
    });
    var value = F.Value{ .object = obj_fields };

    const errs = try F.validate(a, schema, &value);
    try testing.expect(errs.len >= 1);
}

test "validate: array within maxItems bound → pass" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type      = .object,
        .properties = &.{
            .{ .name = "choices", .schema = .{
                .type      = .array,
                .max_items = 3,
            } },
        },
    };

    const items = try a.alloc(F.Value, 2);
    items[0] = .{ .string = "a" };
    items[1] = .{ .string = "b" };
    const obj_fields = try a.dupe(F.Field, &.{
        .{ .key = "choices", .value = .{ .array = items } },
    });
    var value = F.Value{ .object = obj_fields };

    const errs = try F.validate(a, schema, &value);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

// ---------------------------------------------------------------------------
// Validation — per-item schema
// ---------------------------------------------------------------------------

test "validate: items failing item schema → per-item errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const item_schema = F.Schema{ .type = .string };
    const schema = F.Schema{
        .type      = .object,
        .properties = &.{
            .{ .name = "values", .schema = .{
                .type  = .array,
                .items = &item_schema,
            } },
        },
    };

    // One valid string, one integer (wrong type)
    const items = try a.alloc(F.Value, 2);
    items[0] = .{ .string = "ok" };
    items[1] = .{ .int = 42 }; // should be string
    const obj_fields = try a.dupe(F.Field, &.{
        .{ .key = "values", .value = .{ .array = items } },
    });
    var value = F.Value{ .object = obj_fields };

    const errs = try F.validate(a, schema, &value);

    // Expect at least one type_mismatch for the integer item
    try testing.expect(errs.len >= 1);
    var found = false;
    for (errs) |e| {
        if (e.kind == .type_mismatch) found = true;
    }
    try testing.expect(found);
}

test "validate: all items match item schema → no errors" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const item_schema = F.Schema{ .type = .string };
    const schema = F.Schema{
        .type      = .object,
        .properties = &.{
            .{ .name = "tags", .schema = .{
                .type  = .array,
                .items = &item_schema,
            } },
        },
    };

    const items = try a.alloc(F.Value, 3);
    items[0] = .{ .string = "alpha" };
    items[1] = .{ .string = "beta" };
    items[2] = .{ .string = "gamma" };
    const obj_fields = try a.dupe(F.Field, &.{
        .{ .key = "tags", .value = .{ .array = items } },
    });
    var value = F.Value{ .object = obj_fields };

    const errs = try F.validate(a, schema, &value);
    try testing.expectEqual(@as(usize, 0), errs.len);
}
