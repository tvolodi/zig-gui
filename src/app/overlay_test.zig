//! R41 — Overlay / z-layer — unit tests.
//! All tests are CPU-only (no GPU, no GLFW).

const std = @import("std");
const testing = std.testing;
const overlay_mod = @import("overlay.zig");

const OverlayLayer = overlay_mod.OverlayLayer;
const OverlayId = overlay_mod.OverlayId;
const DrawCommand = overlay_mod.DrawCommand;

// ---------------------------------------------------------------------------
// Helpers — build small DrawCommand slices for testing.
// ---------------------------------------------------------------------------

fn makeFilledRectCmd(x: f32) DrawCommand {
    return .{ .filled_rect = .{
        .rect = .{ .x = x, .y = 0, .w = 10, .h = 10 },
        .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .radius = 0,
    } };
}

// ---------------------------------------------------------------------------
// R41 AC-1: allocId() returns distinct IDs across multiple calls.
// ---------------------------------------------------------------------------

test "allocId returns distinct IDs" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    const id0 = layer.allocId();
    const id1 = layer.allocId();
    const id2 = layer.allocId();

    try testing.expect(id0 != id1);
    try testing.expect(id1 != id2);
    try testing.expect(id0 != id2);
}

test "allocId returns monotonically increasing IDs starting at 0" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    const id0 = layer.allocId();
    const id1 = layer.allocId();
    try testing.expectEqual(@as(OverlayId, 0), id0);
    try testing.expectEqual(@as(OverlayId, 1), id1);
}

// ---------------------------------------------------------------------------
// R41 AC-1: setSlot with a new ID appends the slot.
// ---------------------------------------------------------------------------

test "setSlot with new ID appends slot" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    var cmds = [_]DrawCommand{makeFilledRectCmd(0)};
    const id = layer.allocId();
    layer.setSlot(id, &cmds);

    try testing.expectEqual(@as(usize, 1), layer.slots.items.len);
    try testing.expectEqual(id, layer.slots.items[0].id);
    try testing.expectEqual(@as(usize, 1), layer.slots.items[0].commands.len);
}

// ---------------------------------------------------------------------------
// R41 AC-1: setSlot with existing ID replaces commands in place.
// ---------------------------------------------------------------------------

test "setSlot with existing ID replaces commands" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    var cmds_a = [_]DrawCommand{makeFilledRectCmd(0)};
    var cmds_b = [_]DrawCommand{ makeFilledRectCmd(10), makeFilledRectCmd(20) };

    const id = layer.allocId();
    layer.setSlot(id, &cmds_a);
    try testing.expectEqual(@as(usize, 1), layer.slots.items[0].commands.len);

    // Replace with a 2-command slice.
    layer.setSlot(id, &cmds_b);
    // Slot count must not grow.
    try testing.expectEqual(@as(usize, 1), layer.slots.items.len);
    try testing.expectEqual(@as(usize, 2), layer.slots.items[0].commands.len);
}

// ---------------------------------------------------------------------------
// R41 AC-1: removeSlot removes the slot; subsequent flatten does not include it.
// ---------------------------------------------------------------------------

test "removeSlot removes slot; flatten excludes it" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    var cmds = [_]DrawCommand{makeFilledRectCmd(5)};
    const id = layer.allocId();
    layer.setSlot(id, &cmds);
    try testing.expectEqual(@as(usize, 1), layer.slots.items.len);

    layer.removeSlot(id);
    try testing.expectEqual(@as(usize, 0), layer.slots.items.len);

    const flat = try layer.flatten(testing.allocator);
    defer testing.allocator.free(flat);
    try testing.expectEqual(@as(usize, 0), flat.len);
}

test "removeSlot on non-existent ID is a no-op" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    // Should not panic or corrupt state.
    layer.removeSlot(99);
    try testing.expectEqual(@as(usize, 0), layer.slots.items.len);
}

// ---------------------------------------------------------------------------
// R41 AC-1: flatten on empty OverlayLayer returns an empty slice.
// ---------------------------------------------------------------------------

test "flatten on empty layer returns empty slice" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    const flat = try layer.flatten(testing.allocator);
    defer testing.allocator.free(flat);
    try testing.expectEqual(@as(usize, 0), flat.len);
}

// ---------------------------------------------------------------------------
// R41 AC-1: flatten on two slots returns first slot's commands followed by second's.
// ---------------------------------------------------------------------------

test "flatten two slots returns commands in insertion order" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    // Slot A: one command with x=1.0
    var cmds_a = [_]DrawCommand{makeFilledRectCmd(1.0)};
    // Slot B: two commands with x=2.0 and x=3.0
    var cmds_b = [_]DrawCommand{ makeFilledRectCmd(2.0), makeFilledRectCmd(3.0) };

    const id_a = layer.allocId();
    const id_b = layer.allocId();
    layer.setSlot(id_a, &cmds_a);
    layer.setSlot(id_b, &cmds_b);

    const flat = try layer.flatten(testing.allocator);
    defer testing.allocator.free(flat);

    try testing.expectEqual(@as(usize, 3), flat.len);
    // First command is from slot A.
    try testing.expectApproxEqAbs(@as(f32, 1.0), flat[0].filled_rect.rect.x, 0.001);
    // Second and third from slot B.
    try testing.expectApproxEqAbs(@as(f32, 2.0), flat[1].filled_rect.rect.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 3.0), flat[2].filled_rect.rect.x, 0.001);
}

// ---------------------------------------------------------------------------
// R41 AC-1: empty command slice (setSlot(id, &.{})) contributes zero commands to flatten.
// ---------------------------------------------------------------------------

test "setSlot with empty slice contributes zero commands to flatten" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    // Slot A has one command; Slot B is set to an empty slice.
    var cmds_a = [_]DrawCommand{makeFilledRectCmd(1.0)};
    const id_a = layer.allocId();
    const id_b = layer.allocId();
    layer.setSlot(id_a, &cmds_a);
    layer.setSlot(id_b, &.{});

    const flat = try layer.flatten(testing.allocator);
    defer testing.allocator.free(flat);
    // Only slot A contributes.
    try testing.expectEqual(@as(usize, 1), flat.len);
}

// ---------------------------------------------------------------------------
// R41 AC-1: deinit frees all slots without double-free.
// ---------------------------------------------------------------------------

test "deinit frees slots without double-free (testing allocator detects leaks)" {
    var layer = OverlayLayer.init(testing.allocator);

    var cmds_a = [_]DrawCommand{makeFilledRectCmd(0)};
    var cmds_b = [_]DrawCommand{makeFilledRectCmd(5)};
    const id_a = layer.allocId();
    const id_b = layer.allocId();
    layer.setSlot(id_a, &cmds_a);
    layer.setSlot(id_b, &cmds_b);

    // deinit should free the internal slots list without leaking.
    layer.deinit();
    // If testing.allocator.deinit() is not called here, the leak check happens at
    // test teardown automatically by the testing harness.
}

// ---------------------------------------------------------------------------
// R41 AC-2: Integration — build two overlay slots, verify flatten gives correct order.
// ---------------------------------------------------------------------------

test "integration: main ++ slot_a ++ slot_b ordering via flatten" {
    var layer = OverlayLayer.init(testing.allocator);
    defer layer.deinit();

    // Simulate "main layer" commands built separately.
    var main_cmds = [_]DrawCommand{makeFilledRectCmd(100)};

    // Two overlay slots.
    var slot_a_cmds = [_]DrawCommand{makeFilledRectCmd(200)};
    var slot_b_cmds = [_]DrawCommand{ makeFilledRectCmd(300), makeFilledRectCmd(400) };

    const id_a = layer.allocId();
    const id_b = layer.allocId();
    layer.setSlot(id_a, &slot_a_cmds);
    layer.setSlot(id_b, &slot_b_cmds);

    const overlay_flat = try layer.flatten(testing.allocator);
    defer testing.allocator.free(overlay_flat);

    // Concatenate main + overlay manually (as App.run() would do).
    const all = try std.mem.concat(testing.allocator, DrawCommand, &.{ &main_cmds, overlay_flat });
    defer testing.allocator.free(all);

    try testing.expectEqual(@as(usize, 4), all.len);
    try testing.expectApproxEqAbs(@as(f32, 100), all[0].filled_rect.rect.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 200), all[1].filled_rect.rect.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 300), all[2].filled_rect.rect.x, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 400), all[3].filled_rect.rect.x, 0.001);
}
