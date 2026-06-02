//! 06 — Markup + style — unit tests (src/06/06_test.zig)
//!
//! Edge cases and boundary conditions complementing docs/specs/06.acceptance_test.zig.
//! Run via: zig build test-06-unit

const std = @import("std");
const testing = std.testing;
const M = @import("../../docs/specs/06.types.zig");
const store = @import("../03_element_store/types.zig");
const theme = @import("../../docs/specs/05.types.zig");

fn tokens() theme.Tokens {
    return theme.Tokens.light(theme.Palette.default());
}

fn eqColor(a: theme.Color, b: theme.Color) bool {
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
}

// ---------------------------------------------------------------------------
// Parser edge cases
// ---------------------------------------------------------------------------

// 1. Deep nesting: <A><B><C/></B></A> — three levels deep, correct tree shape
test "parse deep nesting three levels" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<A><B><C/></B></A>
    );
    try testing.expectEqualStrings("A", root.tag);
    try testing.expectEqual(@as(usize, 1), root.children.len);

    const b = root.children[0];
    try testing.expectEqualStrings("B", b.tag);
    try testing.expectEqual(@as(usize, 1), b.children.len);

    const c = b.children[0];
    try testing.expectEqualStrings("C", c.tag);
    try testing.expectEqual(@as(usize, 0), c.children.len);
}

// 2. Multiple children: <Row><A/><B/><C/></Row> — three siblings in order
test "parse multiple children order preserved" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Row><A/><B/><C/></Row>
    );
    try testing.expectEqualStrings("Row", root.tag);
    try testing.expectEqual(@as(usize, 3), root.children.len);
    try testing.expectEqualStrings("A", root.children[0].tag);
    try testing.expectEqualStrings("B", root.children[1].tag);
    try testing.expectEqualStrings("C", root.children[2].tag);
}

// 3. UnclosedTag error: <Column> with no closing tag
test "parse unclosed tag returns UnclosedTag error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(M.ParseError.UnclosedTag, M.parse(arena.allocator(),
        \\<Column>
    ));
}

// 4. Multiple attributes: <Img src="a.png" alt="desc" id="img1"/> — three attrs, all literal, order preserved
test "parse multiple attributes all literal order preserved" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Img src="a.png" alt="desc" id="img1"/>
    );
    try testing.expectEqualStrings("Img", root.tag);
    try testing.expectEqual(@as(usize, 3), root.attrs.len);
    try testing.expectEqualStrings("src", root.attrs[0].name);
    try testing.expectEqualStrings("a.png", root.attrs[0].value.literal);
    try testing.expectEqualStrings("alt", root.attrs[1].name);
    try testing.expectEqualStrings("desc", root.attrs[1].value.literal);
    try testing.expectEqualStrings("id", root.attrs[2].name);
    try testing.expectEqualStrings("img1", root.attrs[2].value.literal);
}

// 5. Whitespace tolerance: leading/trailing/internal whitespace around tags and attributes
test "parse whitespace tolerance around tags and attributes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\  <Text   class="body"   text="hi"  />
    );
    try testing.expectEqualStrings("Text", root.tag);
    try testing.expectEqualStrings("body", root.classes);
    try testing.expectEqual(@as(usize, 1), root.attrs.len);
    try testing.expectEqualStrings("hi", root.attrs[0].value.literal);
}

// 6. Empty class attr: <Text class="" text="hi"/> -> classes == ""
test "parse empty class attribute yields empty classes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Text class="" text="hi"/>
    );
    try testing.expectEqualStrings("Text", root.tag);
    try testing.expectEqualStrings("", root.classes);
    try testing.expectEqual(@as(usize, 1), root.attrs.len);
    try testing.expectEqualStrings("text", root.attrs[0].name);
}

// 7. Self-closing with no attrs: <Divider/> — tag only, no classes, no attrs
test "parse self-closing with no attrs" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const root = try M.parse(arena.allocator(),
        \\<Divider/>
    );
    try testing.expectEqualStrings("Divider", root.tag);
    try testing.expectEqualStrings("", root.classes);
    try testing.expectEqual(@as(usize, 0), root.attrs.len);
    try testing.expectEqual(@as(usize, 0), root.children.len);
}

// ---------------------------------------------------------------------------
// Resolver edge cases
// ---------------------------------------------------------------------------

// 8. h-full: height = .{ .percent = 100 }
test "resolve h-full sets height to 100 percent" {
    const r = M.resolveClasses("h-full", tokens());
    try testing.expect(r.layout.height == .percent);
    try testing.expectEqual(@as(f32, 100), r.layout.height.percent);
}

// 9. Individual padding sides: pt-2 pr-3 pb-1 pl-4 — each side set independently
test "resolve individual padding sides set independently" {
    const r = M.resolveClasses("pt-2 pr-3 pb-1 pl-4", tokens());
    try testing.expectEqual(@as(f32, 8), r.style.padding.top);    // pt-2 -> 2*4
    try testing.expectEqual(@as(f32, 12), r.style.padding.right); // pr-3 -> 3*4
    try testing.expectEqual(@as(f32, 4), r.style.padding.bottom); // pb-1 -> 1*4
    try testing.expectEqual(@as(f32, 16), r.style.padding.left);  // pl-4 -> 4*4
}

// 10a. grid-cols-1: boundary value — one fr track
test "resolve grid-cols-1 makes one fr track" {
    const r = M.resolveClasses("grid grid-cols-1", tokens());
    try testing.expectEqual(store.Display.grid, r.layout.display);
    try testing.expectEqual(@as(usize, 1), r.layout.grid_template_columns.len);
    try testing.expect(r.layout.grid_template_columns[0] == .fr);
    try testing.expectEqual(@as(f32, 1), r.layout.grid_template_columns[0].fr);
}

// 10b. grid-cols-12: boundary value — twelve fr tracks
test "resolve grid-cols-12 makes twelve fr tracks" {
    const r = M.resolveClasses("grid grid-cols-12", tokens());
    try testing.expectEqual(store.Display.grid, r.layout.display);
    try testing.expectEqual(@as(usize, 12), r.layout.grid_template_columns.len);
    for (r.layout.grid_template_columns) |t| {
        try testing.expect(t == .fr);
        try testing.expectEqual(@as(f32, 1), t.fr);
    }
}

// 11a. bg-surface: token-backed background
test "resolve bg-surface sets background to tokens.bg_surface" {
    const t = tokens();
    const r = M.resolveClasses("bg-surface", t);
    try testing.expect(eqColor(r.style.background, t.bg_surface));
}

// 11b. bg-raised: token-backed background
test "resolve bg-raised sets background to tokens.bg_raised" {
    const t = tokens();
    const r = M.resolveClasses("bg-raised", t);
    try testing.expect(eqColor(r.style.background, t.bg_raised));
}

// 12a. text-muted: token-backed text color
test "resolve text-muted sets text_color to tokens.text_muted" {
    const t = tokens();
    const r = M.resolveClasses("text-muted", t);
    try testing.expect(eqColor(r.style.text_color, t.text_muted));
}

// 12b. text-accent: text color from accent token
test "resolve text-accent sets text_color to tokens.accent" {
    const t = tokens();
    const r = M.resolveClasses("text-accent", t);
    try testing.expect(eqColor(r.style.text_color, t.accent));
}

// 13a. rounded-sm: radius_sm
test "resolve rounded-sm sets radius to tokens.radius_sm" {
    const t = tokens();
    const r = M.resolveClasses("rounded-sm", t);
    try testing.expectEqual(t.radius_sm, r.style.radius);
}

// 13b. rounded-lg: radius_lg
test "resolve rounded-lg sets radius to tokens.radius_lg" {
    const t = tokens();
    const r = M.resolveClasses("rounded-lg", t);
    try testing.expectEqual(t.radius_lg, r.style.radius);
}

// 13c. rounded-full: radius = 9999 (large fixed value)
test "resolve rounded-full sets radius to 9999" {
    const r = M.resolveClasses("rounded-full", tokens());
    try testing.expectEqual(@as(f32, 9999), r.style.radius);
}

// 14a. border-subtle: border color from tokens.border_subtle
test "resolve border-subtle sets border_color to tokens.border_subtle" {
    const t = tokens();
    const r = M.resolveClasses("border-subtle", t);
    try testing.expect(eqColor(r.style.border_color, t.border_subtle));
}

// 14b. border-strong: border color from tokens.border_strong
test "resolve border-strong sets border_color to tokens.border_strong" {
    const t = tokens();
    const r = M.resolveClasses("border-strong", t);
    try testing.expect(eqColor(r.style.border_color, t.border_strong));
}

// 15. flex-row: direction = .row
test "resolve flex-row sets direction to row" {
    const r = M.resolveClasses("flex flex-row", tokens());
    try testing.expectEqual(store.FlexDirection.row, r.layout.direction);
}

// 16a. justify-center
test "resolve justify-center sets justify_content to center" {
    const r = M.resolveClasses("justify-center", tokens());
    try testing.expectEqual(store.JustifyContent.center, r.layout.justify_content);
}

// 16b. justify-end
test "resolve justify-end sets justify_content to end" {
    const r = M.resolveClasses("justify-end", tokens());
    try testing.expectEqual(store.JustifyContent.end, r.layout.justify_content);
}

// 17a. items-start
test "resolve items-start sets align_items to start" {
    const r = M.resolveClasses("items-start", tokens());
    try testing.expectEqual(store.AlignItems.start, r.layout.align_items);
}

// 17b. items-end
test "resolve items-end sets align_items to end" {
    const r = M.resolveClasses("items-end", tokens());
    try testing.expectEqual(store.AlignItems.end, r.layout.align_items);
}

// 17c. items-stretch
test "resolve items-stretch sets align_items to stretch" {
    const r = M.resolveClasses("items-stretch", tokens());
    try testing.expectEqual(store.AlignItems.stretch, r.layout.align_items);
}

// 18. gap-0: gap = 0 (degenerate/boundary case)
test "resolve gap-0 sets gap to zero" {
    const r = M.resolveClasses("flex gap-0", tokens());
    try testing.expectEqual(@as(f32, 0), r.layout.gap);
}
