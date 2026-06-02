//! 08 — Schema forms — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3). DO NOT EDIT IT TO MAKE AN
//! IMPLEMENTATION PASS. If a test seems wrong, STOP and surface it to the human.
//!
//! All tests are pure (no GPU, no font). Run with: `zig test acceptance_test.zig`.
//! "Done" for module 08 == every test passes AND checklist.md is fully ticked.

const std = @import("std");
const testing = std.testing;
const F = @import("types.zig");
const comp = @import("../07_components/types.zig");
const theme = @import("../05_theme/types.zig");

fn tokens() theme.Tokens {
    return theme.Tokens.light(theme.Palette.default());
}

// A small schema: { name: string (required, minLength 2), age: integer (min 0, max 120),
//                    role: enum [admin, user] }
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
// Value path access
// ---------------------------------------------------------------------------
test "getPath and setPath over nested objects" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var root = F.Value{ .object = &.{} };
    try root.setPath(a, "user.name", .{ .string = "Vladimir" });
    try root.setPath(a, "user.age", .{ .int = 40 });

    const name = root.getPath("user.name").?;
    try testing.expectEqualStrings("Vladimir", name.string);
    const age = root.getPath("user.age").?;
    try testing.expectEqual(@as(i64, 40), age.int);

    // Missing path → null.
    try testing.expect(root.getPath("user.missing") == null);
    try testing.expect(root.getPath("nope.at.all") == null);
}

// ---------------------------------------------------------------------------
// Widget registry
// ---------------------------------------------------------------------------
test "widgetForNode maps schema nodes to component kinds" {
    try testing.expectEqual(comp.WidgetKind.input, F.widgetForNode(.{ .type = .string }));
    try testing.expectEqual(comp.WidgetKind.input, F.widgetForNode(.{ .type = .integer }));
    try testing.expectEqual(comp.WidgetKind.dropdown, F.widgetForNode(.{ .type = .boolean }));
    try testing.expectEqual(comp.WidgetKind.column, F.widgetForNode(.{ .type = .object }));

    const enum_field = F.Schema{
        .type = .string,
        .enum_values = &.{ .{ .string = "a" }, .{ .string = "b" } },
    };
    try testing.expectEqual(comp.WidgetKind.dropdown, F.widgetForNode(enum_field));
}

// ---------------------------------------------------------------------------
// Walker → FormModel
// ---------------------------------------------------------------------------
test "buildForm flattens properties into field specs with labels and paths" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const fields = try F.buildForm(arena.allocator(), sampleSchema());
    try testing.expectEqual(@as(usize, 3), fields.len);

    // name field
    try testing.expectEqualStrings("name", fields[0].path);
    try testing.expectEqualStrings("Name", fields[0].label);
    try testing.expectEqual(comp.WidgetKind.input, fields[0].kind);
    try testing.expect(fields[0].required);

    // role field → dropdown, not required
    try testing.expectEqualStrings("role", fields[2].path);
    try testing.expectEqual(comp.WidgetKind.dropdown, fields[2].kind);
    try testing.expect(!fields[2].required);
}

test "buildForm uses dotted paths for nested objects" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const street = F.Schema{ .type = .string, .title = "Street" };
    const address = F.Schema{
        .type = .object,
        .title = "Address",
        .properties = &.{.{ .name = "street", .schema = street }},
    };
    const schema = F.Schema{
        .type = .object,
        .properties = &.{.{ .name = "address", .schema = address }},
    };

    const fields = try F.buildForm(arena.allocator(), schema);
    try testing.expectEqual(@as(usize, 1), fields.len);
    try testing.expectEqualStrings("address.street", fields[0].path);
}

// ---------------------------------------------------------------------------
// Validator
// ---------------------------------------------------------------------------
test "validate flags each kind of violation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Violations: name too short (minLength 2), age out of range (max 120), role not in enum.
    var bad = F.Value{ .object = &.{} };
    try bad.setPath(a, "name", .{ .string = "V" });
    try bad.setPath(a, "age", .{ .int = 999 });
    try bad.setPath(a, "role", .{ .string = "wizard" });

    const errs = try F.validate(a, sampleSchema(), &bad);
    // One error per violation (name length, age range, role enum). Exact messages are the
    // implementation's; the COUNT and that each path appears is the contract.
    try testing.expectEqual(@as(usize, 3), errs.len);

    var saw_name = false;
    var saw_age = false;
    var saw_role = false;
    for (errs) |e| {
        if (std.mem.eql(u8, e.path, "name")) saw_name = true;
        if (std.mem.eql(u8, e.path, "age")) saw_age = true;
        if (std.mem.eql(u8, e.path, "role")) saw_role = true;
    }
    try testing.expect(saw_name and saw_age and saw_role);
}

test "validate flags a missing required field" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "age", .{ .int = 30 }); // name (required) absent

    const errs = try F.validate(a, sampleSchema(), &v);
    var saw_required = false;
    for (errs) |e| {
        if (std.mem.eql(u8, e.path, "name")) saw_required = true;
    }
    try testing.expect(saw_required);
}

test "validate passes a fully valid value" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ok = F.Value{ .object = &.{} };
    try ok.setPath(a, "name", .{ .string = "Vladimir" });
    try ok.setPath(a, "age", .{ .int = 40 });
    try ok.setPath(a, "role", .{ .string = "admin" });

    const errs = try F.validate(a, sampleSchema(), &ok);
    try testing.expectEqual(@as(usize, 0), errs.len);
}

test "validate flags a malformed email format" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const email_schema = F.Schema{
        .type = .object,
        .properties = &.{.{
            .name = "email",
            .schema = .{ .type = .string, .format = .email },
        }},
    };
    var v = F.Value{ .object = &.{} };
    try v.setPath(a, "email", .{ .string = "not-an-email" });

    const errs = try F.validate(a, email_schema, &v);
    try testing.expect(errs.len >= 1);
}

// ---------------------------------------------------------------------------
// Form — mount + value round-trip (no font)
// ---------------------------------------------------------------------------
test "Form.mount builds an input per field and binds paths" {
    var form = try F.Form.init(testing.allocator, sampleSchema());
    defer form.deinit();

    var scene = comp.Scene.init(testing.allocator);
    defer scene.deinit();

    const root = try form.mount(&scene, tokens());
    _ = root;

    // Three leaf fields → at least three input/dropdown elements in the scene.
    try testing.expect(scene.count() >= 3);

    // Value round-trip through the bound path.
    try form.setValue("name", .{ .string = "Vladimir" });
    const got = form.getValue("name").?;
    try testing.expectEqualStrings("Vladimir", got.string);
}
