//! 08 — Schema forms — unit tests
//!
//! Unit-level tests that go deeper than the acceptance tests.
//! INV-5.3: acceptance_test.zig is FROZEN — do NOT modify it.
//! Run: zig build test-08-unit

const std = @import("std");
const testing = std.testing;
const F = @import("types.zig");

// ---------------------------------------------------------------------------
// Helper schema (3 leaf fields: name/age/role; name is required)
// ---------------------------------------------------------------------------
fn sampleSchema() F.Schema {
    const S = F.Schema;
    const name = S{ .type = .string, .title = "Name", .min_length = 2 };
    const age = S{ .type = .integer, .title = "Age", .minimum = 0, .maximum = 120 };
    const role = S{
        .type = .string,
        .title = "Role",
        .enum_values = &.{ .{ .string = "admin" }, .{ .string = "user" } },
    };
    return S{
        .type = .object,
        .properties = &.{
            .{ .name = "name", .schema = name },
            .{ .name = "age", .schema = age },
            .{ .name = "role", .schema = role },
        },
        .required = &.{"name"},
    };
}

// ---------------------------------------------------------------------------
// Value.getPath — null / missing path coverage
// ---------------------------------------------------------------------------

test "getPath on integer root returns null for any path" {
    var v = F.Value{ .int = 42 };
    try testing.expect(v.getPath("anything") == null);
    try testing.expect(v.getPath("a.b") == null);
}

test "getPath on string root returns null" {
    var v = F.Value{ .string = "hello" };
    try testing.expect(v.getPath("x") == null);
    try testing.expect(v.getPath("x.y") == null);
}

test "getPath on empty object returns null for any key" {
    var v = F.Value{ .object = &.{} };
    try testing.expect(v.getPath("missing") == null);
    try testing.expect(v.getPath("a.b.c") == null);
}

test "getPath returns null when intermediate node is a scalar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    var v = F.Value{ .object = &.{} };
    try v.setPath(arena.allocator(), "a", .{ .string = "leaf" });
    // "a" is a string leaf — sub-path "a.b" cannot resolve
    try testing.expect(v.getPath("a.b") == null);
}

// ---------------------------------------------------------------------------
// Value.setPath — overwrite and 3-level deep nesting
// ---------------------------------------------------------------------------

test "setPath overwrites existing leaf value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "x", .{ .int = 1 });
    try v.setPath(a, "x", .{ .int = 99 });
    try testing.expectEqual(@as(i64, 99), v.getPath("x").?.int);
}

test "setPath overwrites value at a 2-level path" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "user.score", .{ .int = 10 });
    try v.setPath(a, "user.score", .{ .int = 20 });
    try testing.expectEqual(@as(i64, 20), v.getPath("user.score").?.int);
}

test "setPath creates 3-level deep nesting" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "a.b.c", .{ .string = "deep" });
    const got = v.getPath("a.b.c").?;
    try testing.expectEqualStrings("deep", got.string);
}

test "setPath siblings at same level are independent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "meta.x", .{ .int = 1 });
    try v.setPath(a, "meta.y", .{ .int = 2 });
    try testing.expectEqual(@as(i64, 1), v.getPath("meta.x").?.int);
    try testing.expectEqual(@as(i64, 2), v.getPath("meta.y").?.int);
}

// ---------------------------------------------------------------------------
// parseSchema — error taxonomy
// ---------------------------------------------------------------------------

test "parseSchema returns UnsupportedKeyword for minimal string schema" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(
        error.UnsupportedKeyword,
        F.parseSchema(arena.allocator(), "{\"type\":\"string\"}"),
    );
}

test "parseSchema returns UnsupportedKeyword for schema with enum" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    try testing.expectError(
        error.UnsupportedKeyword,
        F.parseSchema(arena.allocator(), "{\"type\":\"string\",\"enum\":[\"a\",\"b\"]}"),
    );
}

test "parseSchema returns error for invalid JSON input" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const result = F.parseSchema(arena.allocator(), "{{not valid json}}");
    // Must return some error — must NOT succeed
    if (result) |_| return error.TestExpectedError else |_| {}
}

// ---------------------------------------------------------------------------
// buildForm — edge cases
// ---------------------------------------------------------------------------

test "buildForm returns empty slice for schema with no properties" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const empty_schema = F.Schema{ .type = .object };
    const fields = try F.buildForm(arena.allocator(), empty_schema);
    try testing.expectEqual(@as(usize, 0), fields.len);
}

test "buildForm uses property name as label when title is absent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const schema = F.Schema{
        .type = .object,
        .properties = &.{
            .{ .name = "username", .schema = .{ .type = .string } },
        },
    };
    const fields = try F.buildForm(arena.allocator(), schema);
    try testing.expectEqual(@as(usize, 1), fields.len);
    try testing.expectEqualStrings("username", fields[0].label);
    try testing.expectEqualStrings("username", fields[0].path);
}

// ---------------------------------------------------------------------------
// validate — additional keyword and format coverage
// ---------------------------------------------------------------------------

test "validate flags maxLength violation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type = .object,
        .properties = &.{.{
            .name = "code",
            .schema = .{ .type = .string, .max_length = 5 },
        }},
    };
    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "code", .{ .string = "toolongstring" });

    const errs = try F.validate(a, schema, &v);
    try testing.expect(errs.len >= 1);
    var saw_code = false;
    for (errs) |e| {
        if (std.mem.eql(u8, e.path, "code")) saw_code = true;
    }
    try testing.expect(saw_code);
}

test "validate passes for a valid email address" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type = .object,
        .properties = &.{.{
            .name = "email",
            .schema = .{ .type = .string, .format = .email },
        }},
    };
    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "email", .{ .string = "user@example.com" });

    const errs = try F.validate(a, schema, &v);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "validate flags email missing @" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type = .object,
        .properties = &.{.{
            .name = "email",
            .schema = .{ .type = .string, .format = .email },
        }},
    };
    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "email", .{ .string = "noemail" });

    const errs = try F.validate(a, schema, &v);
    try testing.expect(errs.len >= 1);
    try testing.expectEqualStrings("email", errs[0].path);
}

test "validate flags email with @ at start" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const schema = F.Schema{
        .type = .object,
        .properties = &.{.{
            .name = "email",
            .schema = .{ .type = .string, .format = .email },
        }},
    };
    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "email", .{ .string = "@nodomain" });

    const errs = try F.validate(a, schema, &v);
    try testing.expect(errs.len >= 1);
}

test "validate nested error path has parent prefix" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const inner = F.Schema{
        .type = .object,
        .properties = &.{.{
            .name = "zip",
            .schema = .{ .type = .string, .min_length = 5 },
        }},
    };
    const schema = F.Schema{
        .type = .object,
        .properties = &.{.{ .name = "address", .schema = inner }},
    };
    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "address.zip", .{ .string = "ab" }); // too short

    const errs = try F.validate(a, schema, &v);
    try testing.expect(errs.len >= 1);
    try testing.expectEqualStrings("address.zip", errs[0].path);
}

// ---------------------------------------------------------------------------
// Form.init — model length matches leaf count
// ---------------------------------------------------------------------------

test "Form.init model length matches leaf count" {
    var form = try F.Form.init(testing.allocator, sampleSchema());
    defer form.deinit();
    // sampleSchema has 3 leaf fields: name, age, role
    try testing.expectEqual(@as(usize, 3), form.model.len);
}

test "Form.init with empty schema has zero model fields" {
    const empty = F.Schema{ .type = .object };
    var form = try F.Form.init(testing.allocator, empty);
    defer form.deinit();
    try testing.expectEqual(@as(usize, 0), form.model.len);
}

// ---------------------------------------------------------------------------
// Form.setValue / getValue — multiple paths
// ---------------------------------------------------------------------------

test "Form.setValue and getValue round-trip for multiple paths" {
    var form = try F.Form.init(testing.allocator, sampleSchema());
    defer form.deinit();

    try form.setValue("name", .{ .string = "Alice" });
    try form.setValue("age", .{ .int = 25 });
    try form.setValue("role", .{ .string = "user" });

    try testing.expectEqualStrings("Alice", form.getValue("name").?.string);
    try testing.expectEqual(@as(i64, 25), form.getValue("age").?.int);
    try testing.expectEqualStrings("user", form.getValue("role").?.string);
}

test "Form.setValue overwrites previously set value" {
    var form = try F.Form.init(testing.allocator, sampleSchema());
    defer form.deinit();

    try form.setValue("name", .{ .string = "First" });
    try form.setValue("name", .{ .string = "Second" });
    try testing.expectEqualStrings("Second", form.getValue("name").?.string);
}

test "Form.getValue returns null for unknown path" {
    var form = try F.Form.init(testing.allocator, sampleSchema());
    defer form.deinit();

    try testing.expect(form.getValue("nonexistent") == null);
    try testing.expect(form.getValue("a.b.c") == null);
}

// ---------------------------------------------------------------------------
// Form.validate — empty values flags required
// ---------------------------------------------------------------------------

test "Form.validate with empty values flags required field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var form = try F.Form.init(testing.allocator, sampleSchema());
    defer form.deinit();

    // No values set — "name" is required
    const errs = try form.validate(arena.allocator());
    var saw_name = false;
    for (errs) |e| {
        if (std.mem.eql(u8, e.path, "name")) saw_name = true;
    }
    try testing.expect(saw_name);
}

test "Form.validate passes after all required fields are set" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var form = try F.Form.init(testing.allocator, sampleSchema());
    defer form.deinit();

    try form.setValue("name", .{ .string = "Bob" });
    // age and role are optional

    const errs = try form.validate(arena.allocator());
    // "name" must not appear in errors
    for (errs) |e| {
        try testing.expect(!std.mem.eql(u8, e.path, "name"));
    }
}
