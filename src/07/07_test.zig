//! 07 — Components — unit tests
//! Edge cases and boundary conditions not fully covered by the acceptance test.

const std = @import("std");
const testing = std.testing;
const C = @import("types.zig");
const store_mod = @import("../03/types.zig");
const theme_mod = @import("../05/types.zig");
const markup_mod = @import("../06/types.zig");

fn testTokens() theme_mod.Tokens {
    return theme_mod.Tokens.light(theme_mod.Palette.default());
}

// ---------------------------------------------------------------------------
// tagToKind — exhaustive coverage of all 7 tags
// ---------------------------------------------------------------------------

test "tagToKind covers all seven kinds" {
    try testing.expectEqual(C.WidgetKind.text, C.tagToKind("Text").?);
    try testing.expectEqual(C.WidgetKind.button, C.tagToKind("Button").?);
    try testing.expectEqual(C.WidgetKind.input, C.tagToKind("Input").?);
    try testing.expectEqual(C.WidgetKind.card, C.tagToKind("Card").?);
    try testing.expectEqual(C.WidgetKind.row, C.tagToKind("Row").?);
    try testing.expectEqual(C.WidgetKind.column, C.tagToKind("Column").?);
    try testing.expectEqual(C.WidgetKind.dropdown, C.tagToKind("Dropdown").?);
    // Case-sensitive: lowercase is unknown
    try testing.expect(C.tagToKind("button") == null);
    try testing.expect(C.tagToKind("text") == null);
    try testing.expect(C.tagToKind("") == null);
}

// ---------------------------------------------------------------------------
// defaultLayoutFor — all 7 kinds
// ---------------------------------------------------------------------------

test "defaultLayoutFor all seven kinds" {
    try testing.expectEqual(store_mod.Display.flex, C.defaultLayoutFor(.row).display);
    try testing.expectEqual(store_mod.FlexDirection.row, C.defaultLayoutFor(.row).direction);
    try testing.expectEqual(store_mod.Display.flex, C.defaultLayoutFor(.column).display);
    try testing.expectEqual(store_mod.FlexDirection.column, C.defaultLayoutFor(.column).direction);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.text).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.button).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.input).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.card).display);
    try testing.expectEqual(store_mod.Display.block, C.defaultLayoutFor(.dropdown).display);
}

// ---------------------------------------------------------------------------
// defaultStyleFor — per-kind defaults
// ---------------------------------------------------------------------------

test "defaultStyleFor button returns buttonPrimary (accent background)" {
    const t = testTokens();
    const s = C.defaultStyleFor(.button, t);
    try testing.expectEqual(t.accent.r, s.background.r);
    try testing.expectEqual(t.accent.g, s.background.g);
    try testing.expectEqual(t.accent.b, s.background.b);
    try testing.expect(s.padding.left > 0);
    try testing.expect(s.padding.top > 0);
}

test "defaultStyleFor card returns cardSurface (bg_surface background)" {
    const t = testTokens();
    const s = C.defaultStyleFor(.card, t);
    try testing.expectEqual(t.bg_surface.r, s.background.r);
    try testing.expect(s.padding.left > 0);
    try testing.expect(s.border_width > 0);
}

test "defaultStyleFor input and dropdown return inputDefault" {
    const t = testTokens();
    const si = C.defaultStyleFor(.input, t);
    const sd = C.defaultStyleFor(.dropdown, t);
    try testing.expectEqual(t.bg_surface.r, si.background.r);
    try testing.expectEqual(si.background.r, sd.background.r);
    try testing.expectEqual(si.border_width, sd.border_width);
}

test "defaultStyleFor text/row/column returns transparent background" {
    const t = testTokens();
    const st = C.defaultStyleFor(.text, t);
    const sr = C.defaultStyleFor(.row, t);
    const sc = C.defaultStyleFor(.column, t);
    try testing.expectEqual(@as(u8, 0), st.background.a);
    try testing.expectEqual(@as(u8, 0), sr.background.a);
    try testing.expectEqual(@as(u8, 0), sc.background.a);
}

// ---------------------------------------------------------------------------
// Scene.count() accuracy
// ---------------------------------------------------------------------------

test "count() tracks element additions" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    try testing.expectEqual(@as(u32, 0), scene.count());

    const d1 = try markup_mod.parse(arena.allocator(), "<Text text=\"a\"/>");
    _ = try scene.instantiate(d1, testTokens());
    try testing.expectEqual(@as(u32, 1), scene.count());

    const d2 = try markup_mod.parse(arena.allocator(), "<Button text=\"b\"/>");
    _ = try scene.instantiate(d2, testTokens());
    try testing.expectEqual(@as(u32, 2), scene.count());
}

// ---------------------------------------------------------------------------
// Deeply nested tree: 3 levels, parent links at every level
// ---------------------------------------------------------------------------

test "deeply nested tree has correct parent links at every level" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(),
        \\<Column>
        \\  <Row>
        \\    <Button text="deep"/>
        \\  </Row>
        \\</Column>
    );
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const col_id = try scene.instantiate(desc, testTokens());

    var col_it = scene.store().childrenOf(col_id);
    const row_id = col_it.next().?;
    try testing.expect(col_it.next() == null);

    var row_it = scene.store().childrenOf(row_id);
    const btn_id = row_it.next().?;
    try testing.expect(row_it.next() == null);

    // Parent of row is col
    try testing.expectEqual(col_id.index, scene.store().parentOf(row_id).?.index);
    // Parent of button is row
    try testing.expectEqual(row_id.index, scene.store().parentOf(btn_id).?.index);

    try testing.expectEqual(C.WidgetKind.column, scene.kindOf(col_id));
    try testing.expectEqual(C.WidgetKind.row, scene.kindOf(row_id));
    try testing.expectEqual(C.WidgetKind.button, scene.kindOf(btn_id));
}

// ---------------------------------------------------------------------------
// Multiple resets — no stale state
// ---------------------------------------------------------------------------

test "multiple reset cycles leave no stale state" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();

    const d = try markup_mod.parse(arena.allocator(), "<Column><Text text=\"a\"/><Text text=\"b\"/></Column>");

    // First populate + reset
    _ = try scene.instantiate(d, testTokens());
    try testing.expectEqual(@as(u32, 3), scene.count());
    scene.reset();
    try testing.expectEqual(@as(u32, 0), scene.count());

    // Second populate + reset
    _ = try scene.instantiate(d, testTokens());
    try testing.expectEqual(@as(u32, 3), scene.count());
    scene.reset();
    try testing.expectEqual(@as(u32, 0), scene.count());

    // Third populate — kinds must be correct, no residue from previous cycles
    const root3 = try scene.instantiate(d, testTokens());
    try testing.expectEqual(C.WidgetKind.column, scene.kindOf(root3));
    var it = scene.store().childrenOf(root3);
    const c1 = it.next().?;
    const c2 = it.next().?;
    try testing.expect(it.next() == null);
    try testing.expectEqual(C.WidgetKind.text, scene.kindOf(c1));
    try testing.expectEqual(C.WidgetKind.text, scene.kindOf(c2));
    try testing.expectEqualStrings("a", scene.textOf(c1).?);
    try testing.expectEqualStrings("b", scene.textOf(c2).?);
}

// ---------------------------------------------------------------------------
// Style merge: class overrides specific fields while defaults survive
// ---------------------------------------------------------------------------

test "button with text-muted class: text_color changes, background stays accent" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = testTokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Button class=\"text-muted\" text=\"x\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, t);
    const s = scene.styleOf(id);
    // text_color was overridden
    try testing.expectEqual(t.text_muted.r, s.text_color.r);
    try testing.expectEqual(t.text_muted.g, s.text_color.g);
    // background is still accent (default survived)
    try testing.expectEqual(t.accent.r, s.background.r);
    // padding survived
    try testing.expect(s.padding.left > 0);
}

test "row with gap-4 class has gap=16" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Row class=\"gap-4\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    // gap-4 → 4 * 4 = 16
    try testing.expectEqual(@as(f32, 16), scene.store().get(id).gap);
    // Row keeps its flex display
    try testing.expectEqual(store_mod.Display.flex, scene.store().get(id).display);
}

// ---------------------------------------------------------------------------
// Layout merge: flex properties on Column
// ---------------------------------------------------------------------------

test "column with justify-center retains flex and column direction" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Column class=\"justify-center\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    const node = scene.store().get(id);
    try testing.expectEqual(store_mod.Display.flex, node.display);
    try testing.expectEqual(store_mod.FlexDirection.column, node.direction);
    try testing.expectEqual(store_mod.JustifyContent.center, node.justify_content);
}

// ---------------------------------------------------------------------------
// Text widget — transparent background, no default style
// ---------------------------------------------------------------------------

test "text widget has transparent background and correct text" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"hello\"/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, testTokens());
    try testing.expectEqual(C.WidgetKind.text, scene.kindOf(id));
    try testing.expectEqualStrings("hello", scene.textOf(id).?);
    // Text has no default style — background is transparent (alpha = 0)
    try testing.expectEqual(@as(u8, 0), scene.styleOf(id).background.a);
}

// ---------------------------------------------------------------------------
// Dropdown default style matches inputDefault
// ---------------------------------------------------------------------------

test "dropdown default style has border and bg_surface background" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = testTokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Dropdown/>");
    var scene = C.Scene.init(testing.allocator);
    defer scene.deinit();
    const id = try scene.instantiate(desc, t);
    const s = scene.styleOf(id);
    try testing.expectEqual(t.bg_surface.r, s.background.r);
    try testing.expectEqual(t.bg_surface.g, s.background.g);
    try testing.expect(s.border_width > 0);
}
