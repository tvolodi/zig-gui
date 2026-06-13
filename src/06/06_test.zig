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

// ===========================================================================
// R50 — parseHexColor
// ===========================================================================

test "R50: parseHexColor #FF0000 returns opaque red" {
    const c = M.parseHexColor("#FF0000");
    try testing.expect(c != null);
    try testing.expectEqual(@as(u8, 255), c.?.r);
    try testing.expectEqual(@as(u8, 0),   c.?.g);
    try testing.expectEqual(@as(u8, 0),   c.?.b);
    try testing.expectEqual(@as(u8, 255), c.?.a);
}

test "R50: parseHexColor #FF000080 returns red with alpha 128" {
    const c = M.parseHexColor("#FF000080");
    try testing.expect(c != null);
    try testing.expectEqual(@as(u8, 255), c.?.r);
    try testing.expectEqual(@as(u8, 0),   c.?.g);
    try testing.expectEqual(@as(u8, 0),   c.?.b);
    try testing.expectEqual(@as(u8, 128), c.?.a);
}

test "R50: parseHexColor empty string returns null" {
    try testing.expect(M.parseHexColor("") == null);
}

test "R50: parseHexColor word red returns null" {
    try testing.expect(M.parseHexColor("red") == null);
}

test "R50: parseHexColor without leading hash returns null" {
    try testing.expect(M.parseHexColor("FF0000") == null);
}

test "R50: parseHexColor with invalid hex digit returns null" {
    try testing.expect(M.parseHexColor("#GGGGGG") == null);
}

test "R50: parseHexColor #000000 returns black" {
    const c = M.parseHexColor("#000000");
    try testing.expect(c != null);
    try testing.expectEqual(@as(u8, 0),   c.?.r);
    try testing.expectEqual(@as(u8, 0),   c.?.g);
    try testing.expectEqual(@as(u8, 0),   c.?.b);
    try testing.expectEqual(@as(u8, 255), c.?.a);
}

test "R50: parseHexColor #FFFFFF returns white" {
    const c = M.parseHexColor("#FFFFFF");
    try testing.expect(c != null);
    try testing.expectEqual(@as(u8, 255), c.?.r);
    try testing.expectEqual(@as(u8, 255), c.?.g);
    try testing.expectEqual(@as(u8, 255), c.?.b);
    try testing.expectEqual(@as(u8, 255), c.?.a);
}

test "R50: parseHexColor #AABBCC returns correct RGB" {
    const c = M.parseHexColor("#AABBCC");
    try testing.expect(c != null);
    try testing.expectEqual(@as(u8, 0xAA), c.?.r);
    try testing.expectEqual(@as(u8, 0xBB), c.?.g);
    try testing.expectEqual(@as(u8, 0xCC), c.?.b);
    try testing.expectEqual(@as(u8, 255),  c.?.a);
}

test "R50: parseHexColor wrong length five digits returns null" {
    try testing.expect(M.parseHexColor("#FFFFF") == null);
}

test "R50: parseHexColor wrong length three digits returns null" {
    try testing.expect(M.parseHexColor("#FFF") == null);
}

// ===========================================================================
// R50 — parseFloat
// ===========================================================================

test "R50: parseFloat 12 returns 12.0" {
    const v = M.parseFloat("12");
    try testing.expect(v != null);
    try testing.expectApproxEqAbs(@as(f32, 12.0), v.?, 0.001);
}

test "R50: parseFloat 1.5 returns 1.5" {
    const v = M.parseFloat("1.5");
    try testing.expect(v != null);
    try testing.expectApproxEqAbs(@as(f32, 1.5), v.?, 0.001);
}

test "R50: parseFloat abc returns null" {
    try testing.expect(M.parseFloat("abc") == null);
}

test "R50: parseFloat empty string returns null" {
    try testing.expect(M.parseFloat("") == null);
}

test "R50: parseFloat 0.0 returns 0.0" {
    const v = M.parseFloat("0.0");
    try testing.expect(v != null);
    try testing.expectApproxEqAbs(@as(f32, 0.0), v.?, 0.001);
}

test "R50: parseFloat negative value returns negative float" {
    const v = M.parseFloat("-1.5");
    try testing.expect(v != null);
    try testing.expectApproxEqAbs(@as(f32, -1.5), v.?, 0.001);
}

// ===========================================================================
// R51 — resolveClasses: new Tailwind classes added in M5
// ===========================================================================

test "R51: hidden sets display to none" {
    const r = M.resolveClasses("hidden", tokens());
    try testing.expectEqual(store.Display.none, r.layout.display);
}

test "R51: overflow-hidden sets overflow to hidden" {
    const r = M.resolveClasses("overflow-hidden", tokens());
    try testing.expectEqual(store.Overflow.hidden, r.layout.overflow);
}

test "R51: w-12 sets width to 48px (12 * 4)" {
    const r = M.resolveClasses("w-12", tokens());
    try testing.expect(r.layout.width == .px);
    try testing.expectApproxEqAbs(@as(f32, 48.0), r.layout.width.px, 0.001);
}

test "R51: h-auto sets height to auto" {
    const r = M.resolveClasses("h-auto", tokens());
    try testing.expect(r.layout.height == .auto);
}

test "R51: min-w-4 sets min_size.w to 16px (4 * 4)" {
    const r = M.resolveClasses("min-w-4", tokens());
    try testing.expectApproxEqAbs(@as(f32, 16.0), r.layout.min_size.w, 0.001);
}

test "R51: max-w-none sets max_size.w to infinity" {
    const r = M.resolveClasses("max-w-none", tokens());
    try testing.expect(std.math.isInf(r.layout.max_size.w));
}

test "R51: mx-auto sets margin left and right to auto" {
    const r = M.resolveClasses("mx-auto", tokens());
    try testing.expect(r.layout.margin.left == .auto);
    try testing.expect(r.layout.margin.right == .auto);
}

test "R51: m-2 sets all four margin sides to 8px (2 * 4)" {
    const r = M.resolveClasses("m-2", tokens());
    // All four sides should be .px = 8
    switch (r.layout.margin.top) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 8.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    switch (r.layout.margin.right) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 8.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    switch (r.layout.margin.bottom) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 8.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    switch (r.layout.margin.left) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 8.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
}

test "R51: shrink-0 sets flex_shrink to 0" {
    const r = M.resolveClasses("shrink-0", tokens());
    try testing.expectApproxEqAbs(@as(f32, 0.0), r.layout.flex_shrink, 0.001);
}

test "R51: self-center sets align_self to center" {
    const r = M.resolveClasses("self-center", tokens());
    try testing.expectEqual(store.AlignSelf.center, r.layout.align_self);
}

test "R51: col-span-3 sets col_span to 3" {
    const r = M.resolveClasses("col-span-3", tokens());
    try testing.expectEqual(@as(u16, 3), r.layout.col_span);
}

test "R51: row-span-2 sets row_span to 2" {
    const r = M.resolveClasses("row-span-2", tokens());
    try testing.expectEqual(@as(u16, 2), r.layout.row_span);
}

test "R51: self-start sets align_self to start" {
    const r = M.resolveClasses("self-start", tokens());
    try testing.expectEqual(store.AlignSelf.start, r.layout.align_self);
}

test "R51: self-end sets align_self to end" {
    const r = M.resolveClasses("self-end", tokens());
    try testing.expectEqual(store.AlignSelf.end, r.layout.align_self);
}

test "R51: self-stretch sets align_self to stretch" {
    const r = M.resolveClasses("self-stretch", tokens());
    try testing.expectEqual(store.AlignSelf.stretch, r.layout.align_self);
}

test "R51: min-h-4 sets min_size.h to 16px" {
    const r = M.resolveClasses("min-h-4", tokens());
    try testing.expectApproxEqAbs(@as(f32, 16.0), r.layout.min_size.h, 0.001);
}

test "R51: max-h-none sets max_size.h to infinity" {
    const r = M.resolveClasses("max-h-none", tokens());
    try testing.expect(std.math.isInf(r.layout.max_size.h));
}

test "R51: mt-3 sets only margin top to 12px" {
    const r = M.resolveClasses("mt-3", tokens());
    switch (r.layout.margin.top) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 12.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    // Other sides should be zero (default)
    try testing.expect(r.layout.margin.right == .zero);
    try testing.expect(r.layout.margin.bottom == .zero);
    try testing.expect(r.layout.margin.left == .zero);
}

test "R51: mx-4 sets left and right margin to 16px, top and bottom zero" {
    const r = M.resolveClasses("mx-4", tokens());
    switch (r.layout.margin.left) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 16.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    switch (r.layout.margin.right) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 16.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    try testing.expect(r.layout.margin.top == .zero);
    try testing.expect(r.layout.margin.bottom == .zero);
}

// ===========================================================================
// M14-02 — Transition class resolution
// ===========================================================================

test "M14-02: transition-opacity sets transition_opacity=true" {
    const r = M.resolveClasses("transition-opacity", tokens());
    try testing.expect(r.style.transition_opacity);
}

test "M14-02: transition-background sets transition_background=true" {
    const r = M.resolveClasses("transition-background", tokens());
    try testing.expect(r.style.transition_background);
}

test "M14-02: transition-colors sets both opacity and background" {
    const r = M.resolveClasses("transition-colors", tokens());
    try testing.expect(r.style.transition_opacity);
    try testing.expect(r.style.transition_background);
}

test "M14-02: duration-60 sets transition_duration=60" {
    const r = M.resolveClasses("duration-60", tokens());
    try testing.expectEqual(@as(u32, 60), r.style.transition_duration);
}

test "M14-02: duration-0 sets transition_duration=0" {
    const r = M.resolveClasses("duration-0", tokens());
    try testing.expectEqual(@as(u32, 0), r.style.transition_duration);
}

test "M14-02: duration-120 sets transition_duration=120" {
    const r = M.resolveClasses("duration-120", tokens());
    try testing.expectEqual(@as(u32, 120), r.style.transition_duration);
}

// ===========================================================================
// M14-03 — Enter/exit class resolution
// ===========================================================================

test "M14-03: animate-in sets animate_in=true" {
    const r = M.resolveClasses("animate-in", tokens());
    try testing.expect(r.style.animate_in);
}

test "M14-03: animate-out sets animate_out=true" {
    const r = M.resolveClasses("animate-out", tokens());
    try testing.expect(r.style.animate_out);
}

test "M14-03: fade-in sets fade_in=true" {
    const r = M.resolveClasses("fade-in", tokens());
    try testing.expect(r.style.fade_in);
}

test "M14-03: fade-out sets fade_out=true" {
    const r = M.resolveClasses("fade-out", tokens());
    try testing.expect(r.style.fade_out);
}

test "M14-03: slide-in-from-top sets slide_in_from_top=true" {
    const r = M.resolveClasses("slide-in-from-top", tokens());
    try testing.expect(r.style.slide_in_from_top);
}

test "M14-03: slide-in-from-bottom sets slide_in_from_bottom=true" {
    const r = M.resolveClasses("slide-in-from-bottom", tokens());
    try testing.expect(r.style.slide_in_from_bottom);
}

test "M14-03: slide-out-to-top sets slide_out_to_top=true" {
    const r = M.resolveClasses("slide-out-to-top", tokens());
    try testing.expect(r.style.slide_out_to_top);
}

test "M14-03: slide-out-to-bottom sets slide_out_to_bottom=true" {
    const r = M.resolveClasses("slide-out-to-bottom", tokens());
    try testing.expect(r.style.slide_out_to_bottom);
}

test "M14: multiple classes compose correctly" {
    const r = M.resolveClasses("transition-opacity animate-in fade-in duration-60", tokens());
    try testing.expect(r.style.transition_opacity);
    try testing.expect(!r.style.transition_background);
    try testing.expect(r.style.animate_in);
    try testing.expect(r.style.fade_in);
    try testing.expectEqual(@as(u32, 60), r.style.transition_duration);
}

test "M14: all enter/exit classes compose" {
    const r = M.resolveClasses("animate-in animate-out fade-in fade-out slide-in-from-top slide-in-from-bottom slide-out-to-top slide-out-to-bottom duration-120", tokens());
    try testing.expect(r.style.animate_in);
    try testing.expect(r.style.animate_out);
    try testing.expect(r.style.fade_in);
    try testing.expect(r.style.fade_out);
    try testing.expect(r.style.slide_in_from_top);
    try testing.expect(r.style.slide_in_from_bottom);
    try testing.expect(r.style.slide_out_to_top);
    try testing.expect(r.style.slide_out_to_bottom);
    try testing.expectEqual(@as(u32, 120), r.style.transition_duration);
}

// ===========================================================================
// R54 — parseWithDiag
// ===========================================================================

test "R54: parseWithDiag on unclosed tag returns UnclosedTag error and sets diag" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var diag: M.ParseDiagnostic = undefined;
    const result = M.parseWithDiag(arena.allocator(), "<Text", &diag);
    try testing.expectError(M.ParseError.UnclosedTag, result);
    try testing.expectEqual(M.ParseErrorKind.UnclosedTag, diag.err);
}

test "R54: parseWithDiag on mismatched tag returns MismatchedTag error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var diag: M.ParseDiagnostic = undefined;
    // <Column> opened but </Row> closes it
    const result = M.parseWithDiag(arena.allocator(), "<Column></Row>", &diag);
    try testing.expectError(M.ParseError.MismatchedTag, result);
    try testing.expectEqual(M.ParseErrorKind.MismatchedTag, diag.err);
    // Line 1 (single-line input)
    try testing.expectEqual(@as(u32, 1), diag.loc.line);
}

test "R54: parseWithDiag on mismatched tag with child reports line 1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var diag: M.ParseDiagnostic = undefined;
    const result = M.parseWithDiag(arena.allocator(), "<Column><Text/></Row>", &diag);
    try testing.expectError(M.ParseError.MismatchedTag, result);
    try testing.expectEqual(M.ParseErrorKind.MismatchedTag, diag.err);
    try testing.expectEqual(@as(u32, 1), diag.loc.line);
}

test "R54: parseWithDiag multi-line error on line 3 reports line 3" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Lines 1-2 are valid content inside Column, line 3 has the mismatched close tag
    const src =
        \\<Column>
        \\  <Text text="a"/>
        \\</Row>
    ;
    var diag: M.ParseDiagnostic = undefined;
    const result = M.parseWithDiag(arena.allocator(), src, &diag);
    try testing.expectError(M.ParseError.MismatchedTag, result);
    try testing.expectEqual(M.ParseErrorKind.MismatchedTag, diag.err);
    try testing.expectEqual(@as(u32, 3), diag.loc.line);
}

test "R54: parseWithDiag with null diag on invalid input returns error without crashing" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Passing null diag must not crash even on error
    const result = M.parseWithDiag(arena.allocator(), "<Text", null);
    try testing.expectError(M.ParseError.UnclosedTag, result);
}

test "R54: parseWithDiag on valid markup returns successfully" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var diag: M.ParseDiagnostic = undefined;
    const node = try M.parseWithDiag(arena.allocator(), "<Column><Text text=\"hi\"/></Column>", &diag);
    try testing.expectEqualStrings("Column", node.tag);
    try testing.expectEqual(@as(usize, 1), node.children.len);
    try testing.expectEqualStrings("Text", node.children[0].tag);
}

test "R54: parseWithDiag column tracking — error on line 2 reports column within line 2" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Line 1 is "<Column>", line 2 starts with "</Row>" — mismatch triggers at column > 1
    const src = "<Column>\n</Row>";
    var diag: M.ParseDiagnostic = undefined;
    const result = M.parseWithDiag(arena.allocator(), src, &diag);
    try testing.expectError(M.ParseError.MismatchedTag, result);
    // Must be on line 2
    try testing.expectEqual(@as(u32, 2), diag.loc.line);
    // Column must be >= 1 (1-based)
    try testing.expect(diag.loc.column >= 1);
}
