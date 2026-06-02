//! 07 — Components — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3). DO NOT EDIT IT TO MAKE AN
//! IMPLEMENTATION PASS. If a test seems wrong, STOP and surface it to the human.
//!
//! The instantiation tests are pure (no font). The measure test loads a font and SKIPS if
//! absent. Run with: `zig test acceptance_test.zig`.
//! "Done" for module 07 == pure tests pass, measure test passes with a font present, AND
//! checklist.md is fully ticked.

const std = @import("std");
const testing = std.testing;
const C = @import("types.zig");
const store = @import("../03_element_store/types.zig");
const theme = @import("../05_theme/types.zig");
const markup = @import("../06_markup_style/types.zig");
const text = @import("../02_text/types.zig");

const TEST_FONT_PATH = "testdata/DejaVuSans.ttf";

fn tokens() theme.Tokens {
    return theme.Tokens.light(theme.Palette.default());
}
fn eqColor(a: theme.Color, b: theme.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------
test "tagToKind maps known tags and rejects unknown" {
    try testing.expectEqual(C.WidgetKind.button, C.tagToKind("Button").?);
    try testing.expectEqual(C.WidgetKind.column, C.tagToKind("Column").?);
    try testing.expectEqual(C.WidgetKind.dropdown, C.tagToKind("Dropdown").?);
    try testing.expect(C.tagToKind("Nonsense") == null);
}

test "defaultLayoutFor sets flex direction for row and column" {
    try testing.expectEqual(store.Display.flex, C.defaultLayoutFor(.row).display);
    try testing.expectEqual(store.FlexDirection.row, C.defaultLayoutFor(.row).direction);
    try testing.expectEqual(store.FlexDirection.column, C.defaultLayoutFor(.column).direction);
    try testing.expectEqual(store.Display.block, C.defaultLayoutFor(.text).display);
}

// ---------------------------------------------------------------------------
// Instantiation (no font)
// ---------------------------------------------------------------------------
test "instantiate a single button stores kind, style, and text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup.parse(arena.allocator(),
        \\<Button text="Save"/>
    );

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();

    const id = try scene.instantiate(desc, tokens());
    try testing.expectEqual(C.WidgetKind.button, scene.kindOf(id));
    try testing.expectEqualStrings("Save", scene.textOf(id).?);
    try testing.expectEqual(@as(u32, 1), scene.count());
}

test "button default style comes from buttonPrimary; classes override it" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();

    // No classes → default buttonPrimary background (accent).
    const plain = try markup.parse(arena.allocator(), "<Button text=\"x\"/>");
    var s1 = C.Scene.init(testing.allocator);
    defer s1.deinit();
    const b1 = try s1.instantiate(plain, t);
    try testing.expect(eqColor(s1.styleOf(b1).background, t.accent));

    // bg-canvas overrides background but default padding (from buttonPrimary) remains > 0.
    const styled = try markup.parse(arena.allocator(), "<Button class=\"bg-canvas\" text=\"x\"/>");
    var s2 = C.Scene.init(testing.allocator);
    defer s2.deinit();
    const b2 = try s2.instantiate(styled, t);
    try testing.expect(eqColor(s2.styleOf(b2).background, t.bg_canvas));
    try testing.expect(s2.styleOf(b2).padding.left > 0); // default survived the override
}

test "instantiate nested tree: kinds, order, parent links" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup.parse(arena.allocator(),
        \\<Column class="flex flex-col gap-2">
        \\  <Text text="title"/>
        \\  <Row>
        \\    <Button text="ok"/>
        \\    <Button text="cancel"/>
        \\  </Row>
        \\</Column>
    );

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, tokens());

    try testing.expectEqual(C.WidgetKind.column, scene.kindOf(root));
    // gap-2 resolved onto the column's layout
    try testing.expectEqual(@as(f32, 8), scene.store().get(root).gap);

    var it = scene.store().childrenOf(root);
    const title = it.next().?;
    const row = it.next().?;
    try testing.expect(it.next() == null);
    try testing.expectEqual(C.WidgetKind.text, scene.kindOf(title));
    try testing.expectEqual(C.WidgetKind.row, scene.kindOf(row));

    var rit = scene.store().childrenOf(row);
    const ok = rit.next().?;
    const cancel = rit.next().?;
    try testing.expectEqualStrings("ok", scene.textOf(ok).?);
    try testing.expectEqualStrings("cancel", scene.textOf(cancel).?);
    // parent link is correct in the store
    try testing.expectEqual(row.index, scene.store().parentOf(ok).?.index);
}

test "unknown tag is an error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup.parse(arena.allocator(), "<Gizmo/>");

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    try testing.expectError(C.InstantiateError.UnknownTag, scene.instantiate(desc, tokens()));
}

test "text absent yields null text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup.parse(arena.allocator(), "<Card/>");

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, tokens());
    try testing.expect(scene.textOf(id) == null);
}

test "reset empties the scene and presentation arrays in lockstep" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup.parse(arena.allocator(),
        \\<Column><Text text="a"/><Text text="b"/></Column>
    );

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    _ = try scene.instantiate(desc, tokens());
    try testing.expectEqual(@as(u32, 3), scene.count());

    scene.reset();
    try testing.expectEqual(@as(u32, 0), scene.count());

    const again = try scene.instantiate(desc, tokens());
    try testing.expectEqual(C.WidgetKind.column, scene.kindOf(again));
}

// ---------------------------------------------------------------------------
// Measure pass (font-dependent — skip if absent)
// ---------------------------------------------------------------------------
test "FONT: measurePass fills measured size on text elements" {
    const file = std.fs.cwd().openFile(TEST_FONT_PATH, .{}) catch return error.SkipZigTest;
    const bytes = try file.readToEndAlloc(testing.allocator, 16 * 1024 * 1024);
    file.close();
    defer testing.allocator.free(bytes);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup.parse(arena.allocator(), "<Text text=\"Привет\"/>");

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, tokens());

    // Before measuring, measured is null.
    try testing.expect(scene.store().get(id).measured == null);

    var font = try text.Font.initFromBytes(testing.allocator, bytes);
    defer font.deinit();
    var atlas = try text.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();

    try scene.measurePass(&font, &atlas);

    const m = scene.store().get(id).measured.?;
    try testing.expect(m.w > 0 and m.h > 0);
}
