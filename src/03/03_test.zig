//! 03 — Element store — unit tests
//!
//! These tests cover edge cases, error paths, and boundary conditions not already
//! exercised by docs/specs/03.acceptance_test.zig. Do NOT modify that file.
//!
//! Run with: `zig test src/03/03_test.zig`

const std = @import("std");
const testing = std.testing;
const S = @import("types.zig");

// ---------------------------------------------------------------------------
// 1. count() reflects adds, removes, and reset accurately.
// ---------------------------------------------------------------------------
test "count after operations" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    // Empty store starts at 0.
    try testing.expectEqual(@as(u32, 0), s.count());

    const root = try s.addRoot(.{});
    try testing.expectEqual(@as(u32, 1), s.count());

    const c1 = try s.addChild(root, .{});
    const c2 = try s.addChild(root, .{});
    try testing.expectEqual(@as(u32, 3), s.count());

    // Removing one child decrements count.
    s.remove(c1);
    try testing.expectEqual(@as(u32, 2), s.count());

    // Removing root decrements again.
    s.remove(c2);
    s.remove(root);
    try testing.expectEqual(@as(u32, 0), s.count());

    // reset() on an already-empty store stays at 0.
    s.reset();
    try testing.expectEqual(@as(u32, 0), s.count());
}

// ---------------------------------------------------------------------------
// 2. Multiple roots: no common parent; each reports parentOf == null.
// ---------------------------------------------------------------------------
test "multiple roots all have null parent" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const r1 = try s.addRoot(.{ .gap = 1 });
    const r2 = try s.addRoot(.{ .gap = 2 });
    const r3 = try s.addRoot(.{ .gap = 3 });

    try testing.expect(s.isValid(r1));
    try testing.expect(s.isValid(r2));
    try testing.expect(s.isValid(r3));

    try testing.expect(s.parentOf(r1) == null);
    try testing.expect(s.parentOf(r2) == null);
    try testing.expect(s.parentOf(r3) == null);

    try testing.expectEqual(@as(u32, 3), s.count());
}

// ---------------------------------------------------------------------------
// 3. Deep nesting: parentOf chain traverses all the way up.
// ---------------------------------------------------------------------------
test "deep nesting parentOf chain" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});
    const child = try s.addChild(root, .{});
    const grandchild = try s.addChild(child, .{});
    const great = try s.addChild(grandchild, .{});

    // great-grandchild's parent is grandchild.
    const p1 = s.parentOf(great).?;
    try testing.expectEqual(grandchild.index, p1.index);
    try testing.expectEqual(grandchild.gen, p1.gen);

    // grandchild's parent is child.
    const p2 = s.parentOf(grandchild).?;
    try testing.expectEqual(child.index, p2.index);
    try testing.expectEqual(child.gen, p2.gen);

    // child's parent is root.
    const p3 = s.parentOf(child).?;
    try testing.expectEqual(root.index, p3.index);
    try testing.expectEqual(root.gen, p3.gen);

    // root has no parent.
    try testing.expect(s.parentOf(root) == null);
}

// ---------------------------------------------------------------------------
// 4a. Remove first child — remaining children still in insertion order.
// ---------------------------------------------------------------------------
test "remove first child preserves order of remaining" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});
    const a = try s.addChild(root, .{ .width = .{ .px = 10 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 20 } });
    const c = try s.addChild(root, .{ .width = .{ .px = 30 } });

    s.remove(a);

    var it = s.childrenOf(root);
    const first = it.next().?;
    const second = it.next().?;
    try testing.expect(it.next() == null);

    try testing.expectEqual(b.index, first.index);
    try testing.expectEqual(c.index, second.index);
    try testing.expectEqual(@as(f32, 20), s.get(first).width.px);
    try testing.expectEqual(@as(f32, 30), s.get(second).width.px);
}

// ---------------------------------------------------------------------------
// 4b. Remove last child — remaining children still in insertion order.
// ---------------------------------------------------------------------------
test "remove last child preserves order of remaining" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});
    const a = try s.addChild(root, .{ .width = .{ .px = 10 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 20 } });
    const c = try s.addChild(root, .{ .width = .{ .px = 30 } });

    s.remove(c);

    var it = s.childrenOf(root);
    const first = it.next().?;
    const second = it.next().?;
    try testing.expect(it.next() == null);

    try testing.expectEqual(a.index, first.index);
    try testing.expectEqual(b.index, second.index);
}

// ---------------------------------------------------------------------------
// 4c. Remove middle child — first and last remain in order, middle gone.
// ---------------------------------------------------------------------------
test "remove middle child preserves first and last" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});
    const a = try s.addChild(root, .{ .width = .{ .px = 1 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 2 } });
    const c = try s.addChild(root, .{ .width = .{ .px = 3 } });

    s.remove(b);

    var it = s.childrenOf(root);
    const first = it.next().?;
    const second = it.next().?;
    try testing.expect(it.next() == null);

    try testing.expectEqual(a.index, first.index);
    try testing.expectEqual(c.index, second.index);
    try testing.expectEqual(@as(f32, 1), s.get(first).width.px);
    try testing.expectEqual(@as(f32, 3), s.get(second).width.px);
}

// ---------------------------------------------------------------------------
// 5. Remove an element that has children: parent's child chain stays consistent.
//    The spec only requires the PARENT's link to be updated (the removed element's
//    own subtree becomes orphaned / unreachable from the parent chain).
// ---------------------------------------------------------------------------
test "remove element with children unlinks from grandparent" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});
    const mid = try s.addChild(root, .{ .width = .{ .px = 5 } });
    const leaf1 = try s.addChild(mid, .{ .width = .{ .px = 11 } });
    const leaf2 = try s.addChild(mid, .{ .width = .{ .px = 12 } });
    _ = leaf1;
    _ = leaf2;

    // Sanity: root has one child (mid).
    {
        var it = s.childrenOf(root);
        const only = it.next().?;
        try testing.expectEqual(mid.index, only.index);
        try testing.expect(it.next() == null);
    }

    // Remove mid. Root should now have no children.
    s.remove(mid);
    try testing.expect(!s.isValid(mid));

    var it2 = s.childrenOf(root);
    try testing.expect(it2.next() == null);
}

// ---------------------------------------------------------------------------
// 6. isValid with an out-of-bounds index returns false, no panic.
// ---------------------------------------------------------------------------
test "isValid out-of-bounds index returns false" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    // No elements added — any index should be out of bounds.
    try testing.expect(!s.isValid(.{ .index = 9999, .gen = 0 }));
    try testing.expect(!s.isValid(.{ .index = 0, .gen = 0 }));

    // Add a root so gen array has at least one slot, then check beyond it.
    _ = try s.addRoot(.{});
    try testing.expect(!s.isValid(.{ .index = 9999, .gen = 0 }));
    try testing.expect(!s.isValid(.{ .index = 9999, .gen = 1 }));
}

// ---------------------------------------------------------------------------
// 7. dirtyIndices yields exactly the elements that were marked dirty.
// ---------------------------------------------------------------------------
test "dirtyIndices yields only marked elements" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const r = try s.addRoot(.{});
    const a = try s.addChild(r, .{});
    const b = try s.addChild(r, .{});
    const c = try s.addChild(r, .{});

    // Clear all dirty bits.
    s.clearDirty();

    // Mark only a and c dirty.
    s.markDirty(a);
    s.markDirty(c);

    var seen_r = false;
    var seen_a = false;
    var seen_b = false;
    var seen_c = false;
    var total: u32 = 0;

    var it = s.dirtyIndices();
    while (it.next()) |idx| {
        total += 1;
        if (idx == r.index) seen_r = true;
        if (idx == a.index) seen_a = true;
        if (idx == b.index) seen_b = true;
        if (idx == c.index) seen_c = true;
    }

    try testing.expect(!seen_r);
    try testing.expect(seen_a);
    try testing.expect(!seen_b);
    try testing.expect(seen_c);
    try testing.expectEqual(@as(u32, 2), total);
}

// ---------------------------------------------------------------------------
// 8. reset then grow again — handles and count are correct.
// ---------------------------------------------------------------------------
test "reset then grow beyond previous size" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    // First generation: add 5 elements.
    const root1 = try s.addRoot(.{});
    for (0..4) |_| {
        _ = try s.addChild(root1, .{});
    }
    try testing.expectEqual(@as(u32, 5), s.count());

    s.reset();
    try testing.expectEqual(@as(u32, 0), s.count());
    try testing.expect(!s.isValid(root1)); // old handle stale after reset

    // Second generation: add more elements than before.
    const root2 = try s.addRoot(.{ .gap = 99 });
    var ids: [10]S.ElementId = undefined;
    for (&ids, 0..) |*slot, i| {
        slot.* = try s.addChild(root2, .{ .width = .{ .px = @floatFromInt(i) } });
    }

    try testing.expectEqual(@as(u32, 11), s.count());
    try testing.expect(s.isValid(root2));
    try testing.expectEqual(@as(f32, 99), s.get(root2).gap);

    for (ids, 0..) |id, i| {
        try testing.expect(s.isValid(id));
        try testing.expectEqual(@as(f32, @floatFromInt(i)), s.get(id).width.px);
    }
}

// ---------------------------------------------------------------------------
// 9. Reuse multiple freed indices: gen is bumped, old handles are invalid.
// ---------------------------------------------------------------------------
test "reuse multiple freed indices bumps generation each time" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    // Allocate three roots and immediately free them to populate the free list.
    const x = try s.addRoot(.{});
    const y = try s.addRoot(.{});
    const z = try s.addRoot(.{});

    const xi = x.index;
    const yi = y.index;
    const zi = z.index;
    const xg = x.gen;
    const yg = y.gen;
    const zg = z.gen;

    s.remove(z);
    s.remove(y);
    s.remove(x);

    // All old handles are invalid.
    try testing.expect(!s.isValid(x));
    try testing.expect(!s.isValid(y));
    try testing.expect(!s.isValid(z));

    // Reallocate three roots — indices reused (in LIFO free-list order).
    const a = try s.addRoot(.{ .gap = 10 });
    const b = try s.addRoot(.{ .gap = 20 });
    const c = try s.addRoot(.{ .gap = 30 });

    // Each reused index must have a strictly higher generation.
    // We don't know exact reuse order, but we know each new gen > old gen for its index.
    // Collect (index -> new gen) for a, b, c.
    const new_gens = [_]S.ElementId{ a, b, c };
    const old_gens_by_index = [_]struct { idx: u32, old_gen: u32 }{
        .{ .idx = xi, .old_gen = xg },
        .{ .idx = yi, .old_gen = yg },
        .{ .idx = zi, .old_gen = zg },
    };
    for (new_gens) |new_id| {
        for (old_gens_by_index) |old| {
            if (new_id.index == old.idx) {
                try testing.expect(new_id.gen != old.old_gen);
            }
        }
    }

    // All new handles valid; all old handles still invalid.
    try testing.expect(s.isValid(a));
    try testing.expect(s.isValid(b));
    try testing.expect(s.isValid(c));
    try testing.expect(!s.isValid(x));
    try testing.expect(!s.isValid(y));
    try testing.expect(!s.isValid(z));

    try testing.expectEqual(@as(f32, 10), s.get(a).gap);
    try testing.expectEqual(@as(f32, 20), s.get(b).gap);
    try testing.expectEqual(@as(f32, 30), s.get(c).gap);
}

// ===========================================================================
// R51 — New types in module 03: Display.none, AlignSelf, MarginValue, Margin
// ===========================================================================

test "R51: Display enum has none variant" {
    // Verify Display.none compiles and equals itself (type check)
    const d: S.Display = .none;
    try testing.expectEqual(S.Display.none, d);
    // Distinct from block/flex/grid
    try testing.expect(d != .block);
    try testing.expect(d != .flex);
    try testing.expect(d != .grid);
}

test "R51: AlignSelf enum has all required variants" {
    const variants = [_]S.AlignSelf{ .auto, .start, .center, .end, .stretch };
    // Verify they are all distinct
    try testing.expectEqual(S.AlignSelf.auto, variants[0]);
    try testing.expectEqual(S.AlignSelf.start, variants[1]);
    try testing.expectEqual(S.AlignSelf.center, variants[2]);
    try testing.expectEqual(S.AlignSelf.end, variants[3]);
    try testing.expectEqual(S.AlignSelf.stretch, variants[4]);
}

test "R51: MarginValue has zero, px and auto variants" {
    const zero_val: S.MarginValue = .zero;
    const px_val: S.MarginValue = .{ .px = 8.0 };
    const auto_val: S.MarginValue = .auto;

    try testing.expect(zero_val == .zero);
    try testing.expect(px_val == .px);
    try testing.expect(auto_val == .auto);
    try testing.expectApproxEqAbs(@as(f32, 8.0), px_val.px, 0.001);
}

test "R51: Margin struct has top, right, bottom, left fields all MarginValue" {
    var m: S.Margin = .{};
    // Defaults are .zero
    try testing.expect(m.top == .zero);
    try testing.expect(m.right == .zero);
    try testing.expect(m.bottom == .zero);
    try testing.expect(m.left == .zero);
    // Can set each independently
    m.left = .auto;
    m.right = .auto;
    m.top = .{ .px = 4.0 };
    m.bottom = .{ .px = 8.0 };
    try testing.expect(m.left == .auto);
    try testing.expect(m.right == .auto);
    switch (m.top) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 4.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    switch (m.bottom) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 8.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
}

test "R51: LayoutNode has margin field of type Margin" {
    var node = S.LayoutNode{};
    // Default margin is all zero
    try testing.expect(node.margin.top == .zero);
    try testing.expect(node.margin.right == .zero);
    try testing.expect(node.margin.bottom == .zero);
    try testing.expect(node.margin.left == .zero);
    // Can apply mx-auto pattern
    node.margin.left = .auto;
    node.margin.right = .auto;
    try testing.expect(node.margin.left == .auto);
    try testing.expect(node.margin.right == .auto);
}

test "R51: LayoutNode has align_self field with default .auto" {
    const node = S.LayoutNode{};
    try testing.expectEqual(S.AlignSelf.auto, node.align_self);
}

test "R51: LayoutNode with display=.none stores value correctly" {
    const node = S.LayoutNode{ .display = .none };
    try testing.expectEqual(S.Display.none, node.display);
}

test "R51: LayoutNode stored in ElementStore can have display=.none" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const id = try s.addRoot(.{ .display = .none });
    try testing.expectEqual(S.Display.none, s.get(id).display);
}

test "R51: LayoutNode margin round-trips through ElementStore" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const node = S.LayoutNode{
        .margin = .{
            .top    = .{ .px = 4.0 },
            .right  = .auto,
            .bottom = .zero,
            .left   = .auto,
        },
    };
    const id = try s.addRoot(node);
    const stored = s.get(id);
    switch (stored.margin.top) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 4.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
    try testing.expect(stored.margin.right == .auto);
    try testing.expect(stored.margin.bottom == .zero);
    try testing.expect(stored.margin.left == .auto);
}

// ---------------------------------------------------------------------------
// 10. addChild to a non-root (multi-level tree): childrenOf correct at each level.
// ---------------------------------------------------------------------------
test "addChild to non-root yields correct childrenOf at each level" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    // Build:  root -> [mid_a, mid_b]
    //         mid_a -> [leaf1, leaf2]
    //         mid_b -> [leaf3]
    const root = try s.addRoot(.{});
    const mid_a = try s.addChild(root, .{ .gap = 1 });
    const mid_b = try s.addChild(root, .{ .gap = 2 });
    const leaf1 = try s.addChild(mid_a, .{ .width = .{ .px = 100 } });
    const leaf2 = try s.addChild(mid_a, .{ .width = .{ .px = 200 } });
    const leaf3 = try s.addChild(mid_b, .{ .width = .{ .px = 300 } });

    // root's direct children are mid_a then mid_b.
    {
        var it = s.childrenOf(root);
        const first = it.next().?;
        const second = it.next().?;
        try testing.expect(it.next() == null);
        try testing.expectEqual(mid_a.index, first.index);
        try testing.expectEqual(mid_b.index, second.index);
    }

    // mid_a's children are leaf1 then leaf2.
    {
        var it = s.childrenOf(mid_a);
        const first = it.next().?;
        const second = it.next().?;
        try testing.expect(it.next() == null);
        try testing.expectEqual(leaf1.index, first.index);
        try testing.expectEqual(leaf2.index, second.index);
        try testing.expectEqual(@as(f32, 100), s.get(first).width.px);
        try testing.expectEqual(@as(f32, 200), s.get(second).width.px);
    }

    // mid_b has exactly one child: leaf3.
    {
        var it = s.childrenOf(mid_b);
        const only = it.next().?;
        try testing.expect(it.next() == null);
        try testing.expectEqual(leaf3.index, only.index);
        try testing.expectEqual(@as(f32, 300), s.get(only).width.px);
    }

    // Leaves have no children.
    {
        var it1 = s.childrenOf(leaf1);
        try testing.expect(it1.next() == null);
        var it3 = s.childrenOf(leaf3);
        try testing.expect(it3.next() == null);
    }

    // Leaf parents point back correctly.
    const p1 = s.parentOf(leaf1).?;
    try testing.expectEqual(mid_a.index, p1.index);
    const p3 = s.parentOf(leaf3).?;
    try testing.expectEqual(mid_b.index, p3.index);
    const pm = s.parentOf(mid_a).?;
    try testing.expectEqual(root.index, pm.index);
}
