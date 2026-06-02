//! 06 — Markup + style — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3). DO NOT EDIT IT TO MAKE AN
//! IMPLEMENTATION PASS. If a test seems wrong, STOP and surface it to the human.
//!
//! All tests are pure (no GPU, no font). Run with: `zig test acceptance_test.zig`.
//! "Done" for module 06 == every test passes AND checklist.md is fully ticked.

const std = @import("std");
const testing = std.testing;
const M = @import("types.zig");
const store = @import("../03_element_store/types.zig");
const theme = @import("../05_theme/types.zig");

fn eqColor(a: theme.Color, b: theme.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

fn tokens() theme.Tokens {
    return theme.Tokens.light(theme.Palette.default());
}

// ===========================================================================
// Parser
// ===========================================================================

test "parse self-closing tag with class and literal attr" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Text class="text-sm" text="hello"/>
    );
    try testing.expectEqualStrings("Text", root.tag);
    try testing.expectEqualStrings("text-sm", root.classes);
    try testing.expectEqual(@as(usize, 0), root.children.len);
    try testing.expectEqual(@as(usize, 1), root.attrs.len);
    try testing.expectEqualStrings("text", root.attrs[0].name);
    try testing.expectEqualStrings("hello", root.attrs[0].value.literal);
}

test "parse nested container preserves child order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Column class="flex flex-col">
        \\  <Text text="a"/>
        \\  <Button class="bg-accent" text="b"/>
        \\</Column>
    );
    try testing.expectEqualStrings("Column", root.tag);
    try testing.expectEqual(@as(usize, 2), root.children.len);
    try testing.expectEqualStrings("Text", root.children[0].tag);
    try testing.expectEqualStrings("a", root.children[0].attrs[0].value.literal);
    try testing.expectEqualStrings("Button", root.children[1].tag);
    try testing.expectEqualStrings("bg-accent", root.children[1].classes);
}

test "parse records bindings as bind values" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Text text="{bind user.name}"/>
    );
    try testing.expectEqual(@as(usize, 1), root.attrs.len);
    switch (root.attrs[0].value) {
        .bind => |path| try testing.expectEqualStrings("user.name", path),
        .literal => return error.TestExpectedBind,
    }
}

test "parse literal vs bind distinguished on same node" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Img src="logo.png" alt="{bind a.b}"/>
    );
    // order preserved; src is literal, alt is bind
    try testing.expectEqualStrings("logo.png", root.attrs[0].value.literal);
    try testing.expectEqualStrings("a.b", root.attrs[1].value.bind);
}

test "parse mismatched tag is an error, not a crash" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(M.ParseError.MismatchedTag, M.parse(arena.allocator(),
        \\<Column></Row>
    ));
}

// ===========================================================================
// Resolver — layout classes
// ===========================================================================

test "resolve layout: flex column with gap, align, justify" {
    const r = M.resolveClasses("flex flex-col gap-2 items-center justify-between", tokens());
    try testing.expectEqual(store.Display.flex, r.layout.display);
    try testing.expectEqual(store.FlexDirection.column, r.layout.direction);
    try testing.expectEqual(@as(f32, 8), r.layout.gap); // gap-2 -> 2*4
    try testing.expectEqual(store.AlignItems.center, r.layout.align_items);
    try testing.expectEqual(store.JustifyContent.space_between, r.layout.justify_content);
}

test "resolve layout: grid-cols-3 makes three fr tracks" {
    const r = M.resolveClasses("grid grid-cols-3", tokens());
    try testing.expectEqual(store.Display.grid, r.layout.display);
    try testing.expectEqual(@as(usize, 3), r.layout.grid_template_columns.len);
    for (r.layout.grid_template_columns) |t| {
        try testing.expect(t == .fr);
    }
}

test "resolve layout: w-full and flex-1" {
    const r = M.resolveClasses("w-full flex-1", tokens());
    try testing.expect(r.layout.width == .percent);
    try testing.expectEqual(@as(f32, 100), r.layout.width.percent);
    try testing.expectEqual(@as(f32, 1), r.layout.flex_grow);
}

// ===========================================================================
// Resolver — style classes
// ===========================================================================

test "resolve style: colors and font-size come from tokens" {
    const t = tokens();
    const r = M.resolveClasses("bg-accent text-body text-lg", t);
    try testing.expect(eqColor(r.style.background, t.accent));
    try testing.expect(eqColor(r.style.text_color, t.text_body));
    try testing.expectEqual(t.text_lg, r.style.font_size);
}

test "resolve style: radius comes from tokens, padding from fixed scale" {
    const t = tokens();
    const r = M.resolveClasses("rounded-md p-4", t);
    try testing.expectEqual(t.radius_md, r.style.radius); // token-backed
    try testing.expectEqual(@as(f32, 16), r.style.padding.top); // 4*4 fixed scale
    try testing.expectEqual(@as(f32, 16), r.style.padding.left);
    try testing.expectEqual(@as(f32, 16), r.style.padding.right);
    try testing.expectEqual(@as(f32, 16), r.style.padding.bottom);
}

test "resolve style: axis padding and borders" {
    const t = tokens();
    const r = M.resolveClasses("px-3 py-1 border border-default", t);
    try testing.expectEqual(@as(f32, 12), r.style.padding.left); // px-3 -> 12
    try testing.expectEqual(@as(f32, 12), r.style.padding.right);
    try testing.expectEqual(@as(f32, 4), r.style.padding.top); // py-1 -> 4
    try testing.expectEqual(@as(f32, 4), r.style.padding.bottom);
    try testing.expectEqual(@as(f32, 1), r.style.border_width);
    try testing.expect(eqColor(r.style.border_color, t.border_default));
}

test "resolve: empty string is all defaults" {
    const r = M.resolveClasses("", tokens());
    try testing.expectEqual(store.Display.block, r.layout.display);
    try testing.expectEqual(@as(f32, 0), r.style.padding.top);
    try testing.expectEqual(@as(f32, 0), r.style.radius);
}

test "resolve: unknown class ignored, known classes still apply" {
    const r = M.resolveClasses("totally-bogus p-2 also-fake", tokens());
    try testing.expectEqual(@as(f32, 8), r.style.padding.top); // p-2 -> 8, no crash
}

test "resolve: last wins on direct conflict" {
    const r = M.resolveClasses("p-2 p-4", tokens());
    try testing.expectEqual(@as(f32, 16), r.style.padding.top); // p-4 wins
}
