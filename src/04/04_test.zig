//! 04 — Layout engine — unit tests
//!
//! These tests cover edge cases, error paths, and boundary conditions NOT already
//! exercised by docs/specs/04.acceptance_test.zig. Do NOT modify that file (INV-5.3).
//!
//! Run with: `zig build test-04-unit`

const std = @import("std");
const testing = std.testing;
const L = @import("types.zig");
const store_mod = @import("../03_element_store/types.zig");

fn expectRect(s: *L.ElementStore, id: L.ElementId, x: f32, y: f32, w: f32, h: f32) !void {
    const r = s.get(id).computed;
    try testing.expectApproxEqAbs(x, r.x, 0.5);
    try testing.expectApproxEqAbs(y, r.y, 0.5);
    try testing.expectApproxEqAbs(w, r.w, 0.5);
    try testing.expectApproxEqAbs(h, r.h, 0.5);
}

const full = L.Constraints{ .min_w = 0, .max_w = 800, .min_h = 0, .max_h = 600 };

// ---------------------------------------------------------------------------
// 1. justify_content: .center — two 50-wide children in a 300 container.
//    free space = 300 - 100 = 200, so each side gets 100 → first child at x=100.
// ---------------------------------------------------------------------------
test "justify center" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .justify_content = .center,
        .width = .{ .px = 300 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } });

    L.solve(&s, root, full, &scratch);
    // free space = 300 - 50 - 50 = 200; center offset = 100
    try expectRect(&s, a, 100, 0, 50, 40);
    try expectRect(&s, b, 150, 0, 50, 40);
}

// ---------------------------------------------------------------------------
// 2. justify_content: .end — two 50-wide children in a 300 container.
//    free space = 200; both pushed to the end → first child at x=200.
// ---------------------------------------------------------------------------
test "justify end" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .justify_content = .end,
        .width = .{ .px = 300 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } });

    L.solve(&s, root, full, &scratch);
    // free space = 200; offset = 200 → children at 200 and 250
    try expectRect(&s, a, 200, 0, 50, 40);
    try expectRect(&s, b, 250, 0, 50, 40);
}

// ---------------------------------------------------------------------------
// 3. justify_content: .space_around — three 40-wide children in a 220 container.
//    free space = 220 - 120 = 100; per_item = 100/3 ≈ 33.33;
//    half_item ≈ 16.67 → offsets: 16.67, 16.67+40+33.33=90, 90+40+33.33=163.33.
// ---------------------------------------------------------------------------
test "justify space around" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .justify_content = .space_around,
        .width = .{ .px = 220 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } });
    const c = try s.addChild(root, .{ .width = .{ .px = 40 }, .height = .{ .px = 40 } });

    L.solve(&s, root, full, &scratch);
    // free = 100; per_item = 100/3; start = per_item/2
    const per_item: f32 = 100.0 / 3.0;
    const start = per_item / 2.0;
    const ra = s.get(a).computed;
    const rb = s.get(b).computed;
    const rc = s.get(c).computed;
    try testing.expectApproxEqAbs(start, ra.x, 0.6);
    try testing.expectApproxEqAbs(start + 40 + per_item, rb.x, 0.6);
    try testing.expectApproxEqAbs(start + 2 * (40 + per_item), rc.x, 0.6);
}

// ---------------------------------------------------------------------------
// 4. align_items: .start in a flex row — children stay at the top of the container.
//    container 300×100, two 30-high children → cross (y) position = 0.
// ---------------------------------------------------------------------------
test "align items start" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .align_items = .start,
        .width = .{ .px = 300 },
        .height = .{ .px = 100 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 30 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 30 } });

    L.solve(&s, root, full, &scratch);
    // align start → cross_pos = 0 (top of container content box)
    try expectRect(&s, a, 0, 0, 50, 30);
    try expectRect(&s, b, 50, 0, 50, 30);
}

// ---------------------------------------------------------------------------
// 5. align_items: .center in a flex row — children centered on the cross axis.
//    container 300×100, two 30-high children → y = (100 - 30) / 2 = 35.
// ---------------------------------------------------------------------------
test "align items center" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .align_items = .center,
        .width = .{ .px = 300 },
        .height = .{ .px = 100 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 30 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 30 } });

    L.solve(&s, root, full, &scratch);
    // cross = 100, child cross = 30 → offset = (100-30)/2 = 35
    try expectRect(&s, a, 0, 35, 60, 30);
    try expectRect(&s, b, 60, 35, 60, 30);
}

// ---------------------------------------------------------------------------
// 6. align_items: .end in a flex row — children at the bottom of the container.
//    container 300×100, two 40-high children → y = 100 - 40 = 60.
// ---------------------------------------------------------------------------
test "align items end" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .align_items = .end,
        .width = .{ .px = 300 },
        .height = .{ .px = 100 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 40 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 40 } });

    L.solve(&s, root, full, &scratch);
    // cross = 100, child cross = 40 → cross_pos = 100 - 40 = 60
    try expectRect(&s, a, 0, 60, 60, 40);
    try expectRect(&s, b, 60, 60, 60, 40);
}

// ---------------------------------------------------------------------------
// 7. flex_shrink: two equal-base children shrink proportionally.
//    container 200, two children each 150px wide, flex_shrink=1 by default.
//    total base = 300, overflow = 100; each shrinks by 50 → final = 100.
// ---------------------------------------------------------------------------
test "flex shrink proportional" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 200 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 150 }, .flex_shrink = 1 });
    const b = try s.addChild(root, .{ .width = .{ .px = 150 }, .flex_shrink = 1 });

    L.solve(&s, root, full, &scratch);
    // weighted shrink: each weight = 1 * 150 = 150; total = 300
    // each shrinks by (150/300)*100 = 50 → final = 100
    try expectRect(&s, a, 0, 0, 100, 40);
    try expectRect(&s, b, 100, 0, 100, 40);
}

// ---------------------------------------------------------------------------
// 8. flex_shrink: unequal shrink factors — double weight shrinks more.
//    container 200, child A 150px shrink=1, child B 150px shrink=2.
//    weighted totals: A=150, B=300; overflow=100.
//    A shrinks by (150/450)*100 ≈ 33.33 → ~116.67; B shrinks by (300/450)*100 ≈ 66.67 → ~83.33.
// ---------------------------------------------------------------------------
test "flex shrink unequal factors" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 200 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 150 }, .flex_shrink = 1 });
    const b = try s.addChild(root, .{ .width = .{ .px = 150 }, .flex_shrink = 2 });

    L.solve(&s, root, full, &scratch);
    // overflow = 100; wA = 1*150=150, wB = 2*150=300, total = 450
    // A shrinks by 150/450*100 ≈ 33.33 → 116.67; B shrinks by 300/450*100 ≈ 66.67 → 83.33
    const ra = s.get(a).computed;
    const rb = s.get(b).computed;
    try testing.expectApproxEqAbs(116.67, ra.w, 0.6);
    try testing.expectApproxEqAbs(83.33, rb.w, 0.6);
    // They must be adjacent
    try testing.expectApproxEqAbs(ra.x + ra.w, rb.x, 0.6);
}

// ---------------------------------------------------------------------------
// 9. Column flex direction: children stacked vertically with gap.
//    container 100×300, two 80-high children, gap 10 → y=0 and y=90.
// ---------------------------------------------------------------------------
test "column flex with gap" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .column,
        .gap = 10,
        .width = .{ .px = 100 },
        .height = .{ .px = 300 },
        .align_items = .stretch,
    });
    const a = try s.addChild(root, .{ .height = .{ .px = 80 } });
    const b = try s.addChild(root, .{ .height = .{ .px = 80 } });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, a, 0, 0, 100, 80);
    try expectRect(&s, b, 0, 90, 100, 80);
}

// ---------------------------------------------------------------------------
// 10. Dimension.percent: a child with width 50% in a 200px parent → 100px.
// ---------------------------------------------------------------------------
test "percent dimension width" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 200 },
        .height = .{ .px = 60 },
        .align_items = .stretch,
    });
    // flex_basis percent resolves against main axis (200)
    const child = try s.addChild(root, .{
        .flex_basis = .{ .percent = 50 },
        .height = .{ .px = 60 },
    });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, child, 0, 0, 100, 60);
}

// ---------------------------------------------------------------------------
// 11. Grid with col_span=2: a child spanning two columns gets the combined width + gap.
//    container 320, cols [100px, 100px, 100px], gap 10.
//    Track widths: 100, 100, 100. Track starts: 0, 110, 220.
//    First child col_span=2 → width = 100 + 100 + 10 (gap) = 210.
//    Second child col_span=1 → placed after col 2, col_cursor wraps to next row.
// ---------------------------------------------------------------------------
test "grid col span 2" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const cols = [_]L.TrackSize{ .{ .px = 100 }, .{ .px = 100 }, .{ .px = 100 } };
    const rows = [_]L.TrackSize{ .{ .px = 40 }, .{ .px = 40 } };
    const root = try s.addRoot(.{
        .display = .grid,
        .grid_template_columns = &cols,
        .grid_template_rows = &rows,
        .gap = 10,
        .width = .{ .px = 320 },
        .height = .{ .px = 90 },
    });
    // First child spans 2 columns
    const a = try s.addChild(root, .{ .col_span = 2 });
    // Second child spans 1 column (placed in col 2, row 0)
    const b = try s.addChild(root, .{ .col_span = 1 });

    L.solve(&s, root, full, &scratch);
    // a: col 0 + 1 → x=0, w = 100+100+10 = 210, y=0, h=40
    try expectRect(&s, a, 0, 0, 210, 40);
    // b: col 2 → x=220, w=100, y=0, h=40
    try expectRect(&s, b, 220, 0, 100, 40);
}

// ---------------------------------------------------------------------------
// 12. Grid with row_span=2: a child spanning two rows gets combined height + gap.
//    container 100x210 (2 rows 100px each, gap 10).
//    First child row_span=2 → h = 100+100+10 = 210.
// ---------------------------------------------------------------------------
test "grid row span 2" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const cols = [_]L.TrackSize{.{ .px = 100 }};
    const rows = [_]L.TrackSize{ .{ .px = 100 }, .{ .px = 100 } };
    const root = try s.addRoot(.{
        .display = .grid,
        .grid_template_columns = &cols,
        .grid_template_rows = &rows,
        .gap = 10,
        .width = .{ .px = 100 },
        .height = .{ .px = 210 },
    });
    const a = try s.addChild(root, .{ .row_span = 2 });

    L.solve(&s, root, full, &scratch);
    // a: row 0 + 1 → y=0, h = 100+100+10 = 210, x=0, w=100
    try expectRect(&s, a, 0, 0, 100, 210);
}

// ---------------------------------------------------------------------------
// 13. Grid with .auto tracks — .auto tracks have 0 width per spec.
//    container 200, cols [100px, auto, 1fr].
//    auto = 0; fr_space = 200 - 100 - 0 - gap*2 = 90; 1fr → 90.
// ---------------------------------------------------------------------------
test "grid auto track is zero width" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const cols = [_]L.TrackSize{ .{ .px = 100 }, .auto, .{ .fr = 1 } };
    const rows = [_]L.TrackSize{.{ .px = 40 }};
    const root = try s.addRoot(.{
        .display = .grid,
        .grid_template_columns = &cols,
        .grid_template_rows = &rows,
        .gap = 5,
        .width = .{ .px = 200 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{});
    const b = try s.addChild(root, .{});
    const c = try s.addChild(root, .{});

    L.solve(&s, root, full, &scratch);
    // col starts: a=0 (w=100), b=105 (w=0), c=110 (w=200-100-0-2*5=90)
    try expectRect(&s, a, 0, 0, 100, 40);
    try expectRect(&s, b, 105, 0, 0, 40);
    try expectRect(&s, c, 110, 0, 90, 40);
}

// ---------------------------------------------------------------------------
// 14. Fixed child inside a flex row (no grow) — exact position is preserved.
//    container 400, fixed child 80px at start, then flex_grow child fills rest.
//    The fixed child must be at x=0, w=80 exactly.
// ---------------------------------------------------------------------------
test "fixed child in flex row no grow exact position" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 400 },
        .height = .{ .px = 50 },
    });
    const fixed = try s.addChild(root, .{
        .width = .{ .px = 80 },
        .flex_grow = 0,
        .flex_shrink = 0,
    });
    const filler = try s.addChild(root, .{ .flex_grow = 1, .flex_basis = .{ .px = 0 } });

    L.solve(&s, root, full, &scratch);
    // fixed child: x=0, w=80
    try expectRect(&s, fixed, 0, 0, 80, 50);
    // filler gets remaining 320
    try expectRect(&s, filler, 80, 0, 320, 50);
}

// ---------------------------------------------------------------------------
// 15. Nested flex: a flex container inside a flex row.
//    Outer: row, 400×100, two children 200px each (no grow).
//    Inner (first child): column flex, 200×100, two 40px-high children → stacked at y=0/40.
// ---------------------------------------------------------------------------
test "nested flex containers" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const outer = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 400 },
        .height = .{ .px = 100 },
        .align_items = .stretch,
    });
    // Inner flex container (column)
    const inner = try s.addChild(outer, .{
        .display = .flex,
        .direction = .column,
        .width = .{ .px = 200 },
        .align_items = .stretch,
    });
    const second_col = try s.addChild(outer, .{
        .width = .{ .px = 200 },
    });
    // Children of inner
    const leaf_a = try s.addChild(inner, .{ .height = .{ .px = 40 } });
    const leaf_b = try s.addChild(inner, .{ .height = .{ .px = 40 } });

    L.solve(&s, outer, full, &scratch);
    // outer children
    try expectRect(&s, inner, 0, 0, 200, 100);
    try expectRect(&s, second_col, 200, 0, 200, 100);
    // inner leaves: stacked top-to-bottom, stretched to inner width (200)
    try expectRect(&s, leaf_a, 0, 0, 200, 40);
    try expectRect(&s, leaf_b, 0, 40, 200, 40);
}

// ---------------------------------------------------------------------------
// 16. Block layout: multiple children stacked, height = sum of children heights.
//    container auto height, 3 children 100×30 each → computed h = 90.
//    Children have explicit width to avoid .auto→0 resolution.
// ---------------------------------------------------------------------------
test "block layout height sum of children" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .block,
        .width = .{ .px = 100 },
        .height = .auto,
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } });
    const c = try s.addChild(root, .{ .width = .{ .px = 100 }, .height = .{ .px = 30 } });

    L.solve(&s, root, full, &scratch);
    // children stacked at y=0, 30, 60
    try expectRect(&s, a, 0, 0, 100, 30);
    try expectRect(&s, b, 0, 30, 100, 30);
    try expectRect(&s, c, 0, 60, 100, 30);
    // root height: content-driven = 90
    const rr = s.get(root).computed;
    try testing.expectApproxEqAbs(90.0, rr.h, 0.5);
}

// ---------------------------------------------------------------------------
// 17. Block layout with padding: children offset by padding, width constrained.
//    container 200×auto, padding 10 all sides, two children 180×50 each →
//    first child at (10, 10) w=180; second at (10, 60).
// ---------------------------------------------------------------------------
test "block layout with padding" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .auto,
        .padding = .{ .top = 10, .right = 10, .bottom = 10, .left = 10 },
    });
    // content_w = 200 - 10 - 10 = 180; children use explicit width to match
    const a = try s.addChild(root, .{ .width = .{ .px = 180 }, .height = .{ .px = 50 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 180 }, .height = .{ .px = 50 } });

    L.solve(&s, root, full, &scratch);
    // a: x=10, y=10, w=180, h=50; b: x=10, y=60, w=180, h=50
    try expectRect(&s, a, 10, 10, 180, 50);
    try expectRect(&s, b, 10, 60, 180, 50);
    // root height: padding.top + 50 + 50 + padding.bottom = 120
    const rr = s.get(root).computed;
    try testing.expectApproxEqAbs(120.0, rr.h, 0.5);
}

// ---------------------------------------------------------------------------
// 18. flex_shrink=0 (no shrink): children keep their declared size even when
//    they overflow the container. Two 160px children in 200px container.
// ---------------------------------------------------------------------------
test "flex shrink zero no shrink" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 200 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 160 }, .flex_shrink = 0 });
    const b = try s.addChild(root, .{ .width = .{ .px = 160 }, .flex_shrink = 0 });

    L.solve(&s, root, full, &scratch);
    // No shrink; children keep their 160px width
    try expectRect(&s, a, 0, 0, 160, 40);
    try expectRect(&s, b, 160, 0, 160, 40);
}

// ---------------------------------------------------------------------------
// 19. Column flex: align_items center on cross axis (width axis).
//    container 200×300 column, align_items=center, one 60px-wide child →
//    x = (200 - 60) / 2 = 70.
// ---------------------------------------------------------------------------
test "column flex align items center cross axis" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .column,
        .align_items = .center,
        .width = .{ .px = 200 },
        .height = .{ .px = 300 },
    });
    const child = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 50 } });

    L.solve(&s, root, full, &scratch);
    // cross = width = 200; child cross = 60 → offset = (200-60)/2 = 70
    try expectRect(&s, child, 70, 0, 60, 50);
}

// ---------------------------------------------------------------------------
// 20. justify_content start with gap: explicit gap is respected.
//    container 300, two 60px children, gap 20, justify=start →
//    a at x=0, b at x=80.
// ---------------------------------------------------------------------------
test "justify start with explicit gap" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .justify_content = .start,
        .gap = 20,
        .width = .{ .px = 300 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 40 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 40 } });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, a, 0, 0, 60, 40);
    try expectRect(&s, b, 80, 0, 60, 40);
}
