//! 04 — Layout engine — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3).
//! DO NOT EDIT IT TO MAKE AN IMPLEMENTATION PASS. If a test seems wrong, STOP and surface
//! it to the human. An agent that edits this file to go green has defeated the pipeline.
//!
//! Run with: `zig test acceptance_test.zig`
//! "Done" for module 04 == every test here passes AND checklist.md is fully ticked.
//!
//! These tests assume small helpers from the ElementStore (module 03) for building a node
//! tree in tests: store.testInit(alloc), store.addRoot(node), store.addChild(parent, node).
//! If those helpers do not yet exist in module 03, that is a module-03 gap to surface, not
//! a reason to change these tests.

const std = @import("std");
const testing = std.testing;
const L = @import("types.zig");
const store_mod = @import("../03_element_store/types.zig");

fn expectRect(store: *L.ElementStore, id: L.ElementId, x: f32, y: f32, w: f32, h: f32) !void {
    const r = store.get(id).computed;
    try testing.expectApproxEqAbs(x, r.x, 0.5);
    try testing.expectApproxEqAbs(y, r.y, 0.5);
    try testing.expectApproxEqAbs(w, r.w, 0.5);
    try testing.expectApproxEqAbs(h, r.h, 0.5);
}

const full = L.Constraints{ .min_w = 0, .max_w = 800, .min_h = 0, .max_h = 600 };

// ---------------------------------------------------------------------------
// 1. A single fixed-size block fills nothing more than its declared size.
// ---------------------------------------------------------------------------
test "single fixed block" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .{ .px = 100 },
    });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, root, 0, 0, 200, 100);
}

// ---------------------------------------------------------------------------
// 2. Row flex with gap: three fixed children laid left to right.
//    children 60 wide, gap 10 → x = 0, 70, 140.
// ---------------------------------------------------------------------------
test "row flex with gap" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .gap = 10,
        .width = .{ .px = 400 },
        .height = .{ .px = 50 },
        .align_items = .stretch,
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 30 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 30 } });
    const c = try s.addChild(root, .{ .width = .{ .px = 60 }, .height = .{ .px = 30 } });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, a, 0, 0, 60, 50); // align stretch → height = container content height
    try expectRect(&s, b, 70, 0, 60, 50);
    try expectRect(&s, c, 140, 0, 60, 50);
}

// ---------------------------------------------------------------------------
// 3. flex_grow distributes leftover main-axis space proportionally.
//    container 300 wide, one fixed 100 child, one grow=1 child → grow child gets 200.
// ---------------------------------------------------------------------------
test "flex grow distribution" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 300 },
        .height = .{ .px = 40 },
    });
    const fixed = try s.addChild(root, .{ .width = .{ .px = 100 } });
    const grow = try s.addChild(root, .{ .flex_grow = 1, .flex_basis = .{ .px = 0 } });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, fixed, 0, 0, 100, 40);
    try expectRect(&s, grow, 100, 0, 200, 40);
}

// ---------------------------------------------------------------------------
// 4. justify_content: space_between pushes children to the ends.
//    container 300, two 50-wide children → x = 0 and x = 250.
// ---------------------------------------------------------------------------
test "justify space between" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .justify_content = .space_between,
        .width = .{ .px = 300 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 50 }, .height = .{ .px = 40 } });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, a, 0, 0, 50, 40);
    try expectRect(&s, b, 250, 0, 50, 40);
}

// ---------------------------------------------------------------------------
// 5. Column flex with padding: padding offsets children, shrinks content box.
//    container 200x200, padding 20 all sides, one stretch child →
//    child at (20,20), width 160, height = its fixed 50.
// ---------------------------------------------------------------------------
test "column flex with padding" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .column,
        .align_items = .stretch,
        .padding = .{ .top = 20, .right = 20, .bottom = 20, .left = 20 },
        .width = .{ .px = 200 },
        .height = .{ .px = 200 },
    });
    const child = try s.addChild(root, .{ .height = .{ .px = 50 } });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, child, 20, 20, 160, 50);
}

// ---------------------------------------------------------------------------
// 6. Grid: two px columns + one fr column, fixed gap.
//    container 320 wide, cols [100px, 100px, 1fr], gap 10 →
//    track widths 100,100,100 (320 - 100 - 100 - 2*10 = 100 for the fr) →
//    x positions 0, 110, 220.
// ---------------------------------------------------------------------------
test "grid fixed and fractional tracks" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const cols = [_]L.TrackSize{ .{ .px = 100 }, .{ .px = 100 }, .{ .fr = 1 } };
    const rows = [_]L.TrackSize{.{ .px = 40 }};
    const root = try s.addRoot(.{
        .display = .grid,
        .grid_template_columns = &cols,
        .grid_template_rows = &rows,
        .gap = 10,
        .width = .{ .px = 320 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{});
    const b = try s.addChild(root, .{});
    const c = try s.addChild(root, .{});

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, a, 0, 0, 100, 40);
    try expectRect(&s, b, 110, 0, 100, 40);
    try expectRect(&s, c, 220, 0, 100, 40);
}

// ---------------------------------------------------------------------------
// 7. EDGE: empty container does not crash and takes its own declared size.
// ---------------------------------------------------------------------------
test "empty container" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .width = .{ .px = 120 },
        .height = .{ .px = 80 },
    });
    L.solve(&s, root, full, &scratch);
    try expectRect(&s, root, 0, 0, 120, 80);
}

// ---------------------------------------------------------------------------
// 8. EDGE: zero available space yields zero-area rects, never negative.
// ---------------------------------------------------------------------------
test "zero available space" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const zero = L.Constraints{ .min_w = 0, .max_w = 0, .min_h = 0, .max_h = 0 };
    const root = try s.addRoot(.{ .display = .flex, .width = .auto, .height = .auto });
    const child = try s.addChild(root, .{ .flex_grow = 1 });

    L.solve(&s, root, zero, &scratch);
    const rr = s.get(root).computed;
    const cr = s.get(child).computed;
    try testing.expect(rr.w >= 0 and rr.h >= 0 and cr.w >= 0 and cr.h >= 0);
}

// ---------------------------------------------------------------------------
// 9. EDGE: overflow — children exceeding container keep min size, are NOT clamped
//    into the parent. Two 200-wide children in a 300 container, no shrink allowed.
// ---------------------------------------------------------------------------
test "overflow does not clamp children" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 300 },
        .height = .{ .px = 40 },
    });
    const a = try s.addChild(root, .{
        .width = .{ .px = 200 },
        .min_size = .{ .w = 200, .h = 0 },
        .flex_shrink = 0,
    });
    const b = try s.addChild(root, .{
        .width = .{ .px = 200 },
        .min_size = .{ .w = 200, .h = 0 },
        .flex_shrink = 0,
    });

    L.solve(&s, root, full, &scratch);
    try expectRect(&s, a, 0, 0, 200, 40);
    try expectRect(&s, b, 200, 0, 200, 40); // extends to x=400, past the 300 container — correct
}

// ---------------------------------------------------------------------------
// 10. EDGE: integer pixel output, no cumulative rounding drift.
//     three 1fr columns in a 100px container → widths 33,33,34 (sum == 100), no overlap.
// ---------------------------------------------------------------------------
test "rounding has no drift" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const cols = [_]L.TrackSize{ .{ .fr = 1 }, .{ .fr = 1 }, .{ .fr = 1 } };
    const rows = [_]L.TrackSize{.{ .px = 20 }};
    const root = try s.addRoot(.{
        .display = .grid,
        .grid_template_columns = &cols,
        .grid_template_rows = &rows,
        .gap = 0,
        .width = .{ .px = 100 },
        .height = .{ .px = 20 },
    });
    const a = try s.addChild(root, .{});
    const b = try s.addChild(root, .{});
    const c = try s.addChild(root, .{});

    L.solve(&s, root, full, &scratch);
    const ra = s.get(a).computed;
    const rb = s.get(b).computed;
    const rc = s.get(c).computed;

    // No gaps, no overlaps: each starts exactly where the previous ends.
    try testing.expectApproxEqAbs(ra.x + ra.w, rb.x, 0.5);
    try testing.expectApproxEqAbs(rb.x + rb.w, rc.x, 0.5);
    // Total covers the full 100px with no drift.
    try testing.expectApproxEqAbs(rc.x + rc.w, 100, 0.5);
    // All integer-valued.
    inline for (.{ ra, rb, rc }) |r| {
        try testing.expectEqual(@floor(r.w), r.w);
        try testing.expectEqual(@floor(r.x), r.x);
    }
}

// ---------------------------------------------------------------------------
// 11. Determinism: solving twice yields identical results.
// ---------------------------------------------------------------------------
test "deterministic" {
    var s = try store_mod.ElementStore.testInit(testing.allocator);
    defer s.deinit();
    var scratch: [4096]u8 = undefined;

    const root = try s.addRoot(.{
        .display = .flex,
        .direction = .row,
        .gap = 7,
        .width = .{ .px = 333 },
        .height = .{ .px = 41 },
    });
    _ = try s.addChild(root, .{ .flex_grow = 1 });
    _ = try s.addChild(root, .{ .flex_grow = 2 });

    L.solve(&s, root, full, &scratch);
    const first = s.get(root).computed;
    L.solve(&s, root, full, &scratch);
    const second = s.get(root).computed;
    try testing.expectEqual(first, second);
}
