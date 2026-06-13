//! M11 — Input completeness unit tests (RB0–RB5)
//!
//! Headless tests — no GPU, no GLFW window required.
//! Run via:  zig build test-m11

const std = @import("std");
const testing = std.testing;

const mod01 = @import("../01/types.zig");
const mod07 = @import("../07/types.zig");
const markup_mod = @import("../06/types.zig");
const theme_mod = @import("../05/types.zig");
const app_mod = @import("app.zig");

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

fn testTokens() theme_mod.Tokens {
    return theme_mod.Tokens.light(theme_mod.Palette.default());
}

fn makeScene() mod07.Scene {
    return mod07.Scene.init(testing.allocator);
}

// ---------------------------------------------------------------------------
// RB0 — Mouse cursor shapes
// ---------------------------------------------------------------------------

test "RB0: CursorShape enum has expected variants" {
    comptime {
        _ = mod01.CursorShape.arrow;
        _ = mod01.CursorShape.text_beam;
        _ = mod01.CursorShape.crosshair;
        _ = mod01.CursorShape.hand;
        _ = mod01.CursorShape.resize_ew;
        _ = mod01.CursorShape.resize_ns;
        _ = mod01.CursorShape.resize_all;
        _ = mod01.CursorShape.not_allowed;
    }
}

test "RB0: cursorOf returns null by default" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"ok\"/>");
    const id = try scene.instantiate(desc, testTokens());
    const idx = id.index;

    try testing.expectEqual(@as(?mod01.CursorShape, null), scene.cursorOf(idx));
}

test "RB0: CursorShape is re-exported from mod07" {
    comptime {
        const T = mod07.CursorShape;
        _ = T.arrow;
        _ = T.hand;
    }
}

test "RB0: Platform.setCursor exists on Platform type" {
    comptime {
        std.debug.assert(@hasDecl(mod01.Platform, "setCursor"));
    }
}

// ---------------------------------------------------------------------------
// RB1 — Drag-and-drop intra-window
// ---------------------------------------------------------------------------

test "RB1: DragCallbacks and DropCallbacks types exist in mod07" {
    comptime {
        _ = mod07.DragCallbacks;
        _ = mod07.DropCallbacks;
    }
}

test "RB1: setDragSource stores callbacks; clearDragSource removes them" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"drag\"/>");
    const id = try scene.instantiate(desc, testTokens());
    const idx = id.index;

    const cbs = mod07.DragCallbacks{};
    scene.setDragSource(idx, cbs);
    try testing.expect(scene._drag.items[idx] != null);

    scene.clearDragSource(idx);
    try testing.expect(scene._drag.items[idx] == null);
}

test "RB1: setDropTarget stores callbacks; clearDropTarget removes them" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Card/>");
    const id = try scene.instantiate(desc, testTokens());
    const idx = id.index;

    const cbs = mod07.DropCallbacks{};
    scene.setDropTarget(idx, cbs);
    try testing.expect(scene._drop.items[idx] != null);

    scene.clearDropTarget(idx);
    try testing.expect(scene._drop.items[idx] == null);
}

test "RB1: AppInner has drag field of type DragState" {
    comptime {
        const F = std.meta.fieldInfo(app_mod.AppInner, .drag);
        _ = F;
        _ = app_mod.DragState;
    }
}

// ---------------------------------------------------------------------------
// RB2 — Right-click routing
// ---------------------------------------------------------------------------

test "RB2: setRightClick stores callback; clearRightClick removes it" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"rc\"/>");
    const id = try scene.instantiate(desc, testTokens());
    const idx = id.index;

    var fired = false;
    const cb = mod07.CallbackFn{
        .ptr = &fired,
        .call = struct {
            fn f(ptr: *anyopaque) void {
                const b: *bool = @ptrCast(@alignCast(ptr));
                b.* = true;
            }
        }.f,
    };

    scene.setRightClick(idx, cb);
    const stored = scene.rightClickOf(idx);
    try testing.expect(stored != null);

    // Manually invoke to verify the pointer round-trips correctly.
    stored.?.call(stored.?.ptr);
    try testing.expect(fired);

    scene.clearRightClick(idx);
    try testing.expectEqual(@as(?mod07.CallbackFn, null), scene.rightClickOf(idx));
}

test "RB2: rightClickOf returns null by default" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    const id = try scene.instantiate(desc, testTokens());
    try testing.expectEqual(@as(?mod07.CallbackFn, null), scene.rightClickOf(id.index));
}

// ---------------------------------------------------------------------------
// RB3 — Double-click detection
// ---------------------------------------------------------------------------

test "RB3: setDoubleClick stores callback; clearDoubleClick removes it" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"dc\"/>");
    const id = try scene.instantiate(desc, testTokens());
    const idx = id.index;

    var count: u32 = 0;
    const cb = mod07.CallbackFn{
        .ptr = &count,
        .call = struct {
            fn f(ptr: *anyopaque) void {
                const n: *u32 = @ptrCast(@alignCast(ptr));
                n.* += 1;
            }
        }.f,
    };

    scene.setDoubleClick(idx, cb);
    try testing.expect(scene.doubleClickOf(idx) != null);

    scene.clearDoubleClick(idx);
    try testing.expectEqual(@as(?mod07.CallbackFn, null), scene.doubleClickOf(idx));
}

test "RB3: DoubleClickState and double_click_threshold_ms exist on AppInner" {
    comptime {
        _ = app_mod.DoubleClickState;
        const F = std.meta.fieldInfo(app_mod.AppInner, .double_click);
        _ = F;
        const F2 = std.meta.fieldInfo(app_mod.AppInner, .double_click_threshold_ms);
        _ = F2;
    }
}

test "RB3: AppOptions.double_click_threshold_ms defaults to 250" {
    const opts = app_mod.AppOptions{
        .font_path = "dummy.ttf",
    };
    try testing.expectEqual(@as(u64, 250), opts.double_click_threshold_ms);
}

// ---------------------------------------------------------------------------
// RB4 — Keyboard shortcuts
// ---------------------------------------------------------------------------

test "RB4: ShortcutTable register and lookup" {
    var table = app_mod.ShortcutTable{};

    var fired = false;
    const cb = mod07.CallbackFn{
        .ptr = &fired,
        .call = struct {
            fn f(ptr: *anyopaque) void {
                const b: *bool = @ptrCast(@alignCast(ptr));
                b.* = true;
            }
        }.f,
    };

    try table.register(.a, .{ .ctrl = true }, cb);
    const found = table.lookup(.a, .{ .ctrl = true });
    try testing.expect(found != null);
    found.?.call(found.?.ptr);
    try testing.expect(fired);
}

test "RB4: ShortcutTable lookup with wrong mods returns null" {
    var table = app_mod.ShortcutTable{};
    var dummy: u8 = 0;
    const cb = mod07.CallbackFn{
        .ptr = &dummy,
        .call = struct {
            fn f(_: *anyopaque) void {}
        }.f,
    };

    try table.register(.a, .{ .ctrl = true }, cb);
    const found = table.lookup(.a, .{});  // no ctrl
    try testing.expectEqual(@as(?mod07.CallbackFn, null), found);
}

test "RB4: ShortcutTable unregister removes entry" {
    var table = app_mod.ShortcutTable{};
    var dummy: u8 = 0;
    const cb = mod07.CallbackFn{
        .ptr = &dummy,
        .call = struct {
            fn f(_: *anyopaque) void {}
        }.f,
    };

    try table.register(.z, .{ .ctrl = true }, cb);
    table.unregister(.z, .{ .ctrl = true });
    try testing.expectEqual(@as(?mod07.CallbackFn, null), table.lookup(.z, .{ .ctrl = true }));
}

test "RB4: ShortcutTable returns error when full" {
    var table = app_mod.ShortcutTable{};
    var dummy: u8 = 0;
    const cb = mod07.CallbackFn{
        .ptr = &dummy,
        .call = struct {
            fn f(_: *anyopaque) void {}
        }.f,
    };
    // Fill all MAX_SHORTCUTS slots using the 5 printable keys × 4 modifier combos
    // = 20 slots, then cycle with alt combos.  Since MAX_SHORTCUTS = 64 we use
    // all Key enum members × modifier variations to guarantee unique (key,mods) pairs.
    const keys = [_]mod01.Key{ .a, .c, .v, .x, .z, .enter, .escape, .tab };
    const mod_variants = [_]mod01.Modifiers{
        .{},
        .{ .ctrl = true },
        .{ .alt = true },
        .{ .shift = true },
        .{ .ctrl = true, .alt = true },
        .{ .ctrl = true, .shift = true },
        .{ .alt = true, .shift = true },
        .{ .ctrl = true, .alt = true, .shift = true },
    };
    var filled: usize = 0;
    outer: for (keys) |k| {
        for (mod_variants) |m| {
            if (filled >= app_mod.MAX_SHORTCUTS) break :outer;
            try table.register(k, m, cb);
            filled += 1;
        }
    }
    // If we couldn't fill MAX_SHORTCUTS with unique combos above, pad with f-keys.
    const fkeys = [_]mod01.Key{ .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12 };
    for (fkeys) |k| {
        if (filled >= app_mod.MAX_SHORTCUTS) break;
        for (mod_variants) |m| {
            if (filled >= app_mod.MAX_SHORTCUTS) break;
            try table.register(k, m, cb);
            filled += 1;
        }
    }
    // One more should fail.
    const err = table.register(.backspace, .{}, cb);
    try testing.expectError(app_mod.ShortcutError.TooManyShortcuts, err);
}

// ---------------------------------------------------------------------------
// RB5 — Touch / trackpad gestures
// ---------------------------------------------------------------------------

test "RB5: InputEvent has gesture_swipe and gesture_pinch variants" {
    comptime {
        const ev_swipe = mod01.InputEvent{ .gesture_swipe = .{ .dx = 1.0, .dy = 2.0 } };
        const ev_pinch = mod01.InputEvent{ .gesture_pinch = .{ .scale_delta = 1.1 } };
        _ = ev_swipe;
        _ = ev_pinch;
    }
}

test "RB5: SWIPE_SCALE, PINCH_THRESHOLD, PINCH_SCALE constants exist" {
    comptime {
        const s: f32 = mod01.SWIPE_SCALE;
        const t: f32 = mod01.PINCH_THRESHOLD;
        const p: f32 = mod01.PINCH_SCALE;
        std.debug.assert(s == 20.0);
        std.debug.assert(t == 5.0);
        std.debug.assert(p == 0.05);
    }
}

test "RB5: setPinch stores callback; pinchOf returns it; clearPinch removes it" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Card/>");
    const id = try scene.instantiate(desc, testTokens());
    const idx = id.index;

    var last_delta: f32 = 0;
    const cb: mod07.PinchCallbackFn = struct {
        fn f(i: u32, delta: f32) void {
            _ = i;
            // Can't write into a local here — pure compile-time test.
            _ = delta;
        }
    }.f;
    _ = &last_delta;

    scene.setPinch(idx, cb);
    try testing.expect(scene.pinchOf(idx) != null);

    scene.clearPinch(idx);
    try testing.expectEqual(@as(?mod07.PinchCallbackFn, null), scene.pinchOf(idx));
}

test "RB5: scale_delta for dy=10 equals 1.5" {
    const dy: f32 = 10.0;
    const scale_delta: f32 = 1.0 + dy * mod01.PINCH_SCALE;
    try testing.expectApproxEqAbs(@as(f32, 1.5), scale_delta, 1e-6);
}

test "RB5: scale_delta for dy=-6 equals 0.7" {
    const dy: f32 = -6.0;
    const scale_delta: f32 = 1.0 + dy * mod01.PINCH_SCALE;
    try testing.expectApproxEqAbs(@as(f32, 0.7), scale_delta, 1e-6);
}
