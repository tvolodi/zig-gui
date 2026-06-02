//! 03 — Element store — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3).
//! DO NOT EDIT IT TO MAKE AN IMPLEMENTATION PASS. If a test seems wrong, STOP and surface
//! it to the human.
//!
//! Run with: `zig test acceptance_test.zig`
//! "Done" for module 03 == every test here passes AND checklist.md is fully ticked.

const std = @import("std");
const testing = std.testing;
const S = @import("types.zig");

// ---------------------------------------------------------------------------
// 1. Allocate a root and read its data back through get().
// ---------------------------------------------------------------------------
test "addRoot then get returns stored data" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{ .display = .flex, .gap = 12, .width = .{ .px = 200 } });
    try testing.expect(s.isValid(root));

    const node = s.get(root);
    try testing.expectEqual(S.Display.flex, node.display);
    try testing.expectEqual(@as(f32, 12), node.gap);
    try testing.expectEqual(@as(u32, 1), s.count());
}

// ---------------------------------------------------------------------------
// 2. Children iterate in insertion order (module 04 depends on this).
// ---------------------------------------------------------------------------
test "childrenOf yields insertion order" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{ .display = .flex });
    const a = try s.addChild(root, .{ .width = .{ .px = 1 } });
    const b = try s.addChild(root, .{ .width = .{ .px = 2 } });
    const c = try s.addChild(root, .{ .width = .{ .px = 3 } });

    var it = s.childrenOf(root);
    const first = it.next().?;
    const second = it.next().?;
    const third = it.next().?;
    try testing.expect(it.next() == null);

    try testing.expectEqual(a.index, first.index);
    try testing.expectEqual(b.index, second.index);
    try testing.expectEqual(c.index, third.index);

    // Data is addressable per child.
    try testing.expectEqual(@as(f32, 1), s.get(first).width.px);
    try testing.expectEqual(@as(f32, 3), s.get(third).width.px);
}

// ---------------------------------------------------------------------------
// 3. parentOf returns the parent for children and null for a root.
// ---------------------------------------------------------------------------
test "parentOf" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});
    const child = try s.addChild(root, .{});

    try testing.expect(s.parentOf(root) == null);
    const p = s.parentOf(child).?;
    try testing.expectEqual(root.index, p.index);
    try testing.expectEqual(root.gen, p.gen);
}

// ---------------------------------------------------------------------------
// 4. Generational handles: a removed-then-reused index invalidates old handles.
// ---------------------------------------------------------------------------
test "generational handle invalidation" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const a = try s.addRoot(.{ .width = .{ .px = 100 } });
    const old_index = a.index;

    s.remove(a);
    try testing.expect(!s.isValid(a)); // stale handle no longer valid

    // Next allocation should reuse the freed index but with a bumped generation.
    const b = try s.addRoot(.{ .width = .{ .px = 200 } });
    try testing.expectEqual(old_index, b.index); // index reused
    try testing.expect(b.gen != a.gen); // generation differs
    try testing.expect(s.isValid(b));
    try testing.expect(!s.isValid(a)); // old handle still invalid against reused slot
}

// ---------------------------------------------------------------------------
// 5. Childless element: childrenOf yields nothing, no crash.
// ---------------------------------------------------------------------------
test "childless element iterates empty" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const leaf = try s.addRoot(.{});
    var it = s.childrenOf(leaf);
    try testing.expect(it.next() == null);
}

// ---------------------------------------------------------------------------
// 6. Dirty tracking: new elements are dirty; clearDirty empties; markDirty sets.
// ---------------------------------------------------------------------------
test "dirty tracking" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const a = try s.addRoot(.{});
    const b = try s.addChild(a, .{});

    // Newly added elements start dirty (never laid out).
    var seen_a = false;
    var seen_b = false;
    var it = s.dirtyIndices();
    while (it.next()) |idx| {
        if (idx == a.index) seen_a = true;
        if (idx == b.index) seen_b = true;
    }
    try testing.expect(seen_a and seen_b);

    // clearDirty empties the set.
    s.clearDirty();
    var it2 = s.dirtyIndices();
    try testing.expect(it2.next() == null);

    // markDirty re-sets a single element.
    s.markDirty(b);
    var it3 = s.dirtyIndices();
    const only = it3.next().?;
    try testing.expectEqual(b.index, only);
    try testing.expect(it3.next() == null);
}

// ---------------------------------------------------------------------------
// 7. reset returns the store to empty but usable.
// ---------------------------------------------------------------------------
test "reset clears all elements" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});
    _ = try s.addChild(root, .{});
    _ = try s.addChild(root, .{});
    try testing.expectEqual(@as(u32, 3), s.count());

    s.reset();
    try testing.expectEqual(@as(u32, 0), s.count());

    // Store is still usable after reset.
    const r2 = try s.addRoot(.{ .gap = 5 });
    try testing.expect(s.isValid(r2));
    try testing.expectEqual(@as(f32, 5), s.get(r2).gap);
    try testing.expectEqual(@as(u32, 1), s.count());
}

// ---------------------------------------------------------------------------
// 8. Growth past initial capacity keeps all handles valid and data intact.
// ---------------------------------------------------------------------------
test "growth preserves handles" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const root = try s.addRoot(.{});

    var ids: [500]S.ElementId = undefined;
    for (&ids, 0..) |*slot, i| {
        slot.* = try s.addChild(root, .{ .width = .{ .px = @floatFromInt(i) } });
    }

    // Every handle remains valid and points at the right data after many reallocations.
    for (ids, 0..) |id, i| {
        try testing.expect(s.isValid(id));
        try testing.expectEqual(@as(f32, @floatFromInt(i)), s.get(id).width.px);
    }
    try testing.expectEqual(@as(u32, 501), s.count());

    // Children still iterate in insertion order.
    var it = s.childrenOf(root);
    var expected: u32 = 0;
    while (it.next()) |child| : (expected += 1) {
        try testing.expectEqual(@as(f32, @floatFromInt(expected)), s.get(child).width.px);
    }
    try testing.expectEqual(@as(u32, 500), expected);
}

// ---------------------------------------------------------------------------
// 9. get returns a mutable pointer the layout engine can write through.
// ---------------------------------------------------------------------------
test "get returns mutable node" {
    var s = try S.ElementStore.testInit(testing.allocator);
    defer s.deinit();

    const id = try s.addRoot(.{});
    s.get(id).computed = .{ .x = 4, .y = 8, .w = 16, .h = 32 };

    const r = s.get(id).computed;
    try testing.expectEqual(@as(f32, 4), r.x);
    try testing.expectEqual(@as(f32, 32), r.h);
}
