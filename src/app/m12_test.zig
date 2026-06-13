//! M12 — Layout extensions unit tests (RC0–RC4)
//!
//! Headless tests — no GPU, no GLFW window required.
//! Run via:  zig build test-m12

const std = @import("std");
const testing = std.testing;

const store_mod = @import("../03/types.zig");
const layout_mod = @import("../04/types.zig");
const markup_mod = @import("../06/types.zig");
const mod07 = @import("../07/types.zig");
const theme_mod = @import("../05/types.zig");
const renderer_mod = @import("../09/types.zig");

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

fn testTokens() theme_mod.Tokens {
    return theme_mod.Tokens.light(theme_mod.Palette.default());
}

fn makeScene() mod07.Scene {
    return mod07.Scene.init(testing.allocator);
}

/// Stub Font: no-op font for tests that don't need real text rendering.
fn stubFont() renderer_mod.text.Font {
    return .{ ._impl = undefined };
}

// ---------------------------------------------------------------------------
// RC0 — Absolute positioning
// ---------------------------------------------------------------------------

test "RC0: Position enum has .static, .absolute, .sticky variants" {
    comptime {
        _ = store_mod.Position.static;
        _ = store_mod.Position.absolute;
        _ = store_mod.Position.sticky;
    }
}

test "RC0: LayoutNode.position defaults to .static" {
    const node = store_mod.LayoutNode{};
    try testing.expectEqual(store_mod.Position.static, node.position);
}

test "RC0: LayoutNode inset fields default to .auto" {
    const node = store_mod.LayoutNode{};
    try testing.expect(node.inset_top == .auto);
    try testing.expect(node.inset_right == .auto);
    try testing.expect(node.inset_bottom == .auto);
    try testing.expect(node.inset_left == .auto);
}

test "RC0: class 'absolute' sets position = .absolute" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("absolute", tok);
    try testing.expectEqual(store_mod.Position.absolute, resolved.layout.position);
}

test "RC0: class 'static' sets position = .static" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("static", tok);
    try testing.expectEqual(store_mod.Position.static, resolved.layout.position);
}

test "RC0: class 'top-4' sets inset_top = .px(16)" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("top-4", tok);
    switch (resolved.layout.inset_top) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 16.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
}

test "RC0: class 'top-0' sets inset_top = .px(0)" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("top-0", tok);
    switch (resolved.layout.inset_top) {
        .px => |v| try testing.expectApproxEqAbs(@as(f32, 0.0), v, 0.001),
        else => return error.TestUnexpectedResult,
    }
}

test "RC0: class 'inset-0' sets all four insets to .px(0)" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("inset-0", tok);
    const check = struct {
        fn px0(dim: store_mod.Dimension) !void {
            switch (dim) {
                .px => |v| try testing.expectApproxEqAbs(@as(f32, 0.0), v, 0.001),
                else => return error.TestUnexpectedResult,
            }
        }
    };
    try check.px0(resolved.layout.inset_top);
    try check.px0(resolved.layout.inset_right);
    try check.px0(resolved.layout.inset_bottom);
    try check.px0(resolved.layout.inset_left);
}

test "RC0: layout — absolute child is not counted in parent flex sizing" {
    // A flex row parent 200px wide with one static child (80px) and one absolute child (80px).
    // The parent should size as if there is only one static child.
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const parent_id = try store.addRoot(store_mod.LayoutNode{
        .display = .flex,
        .direction = .row,
        .width = .{ .px = 200 },
        .height = .auto,
    });

    _ = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = 40 },
        .position = .static,
    });
    _ = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = 40 },
        .position = .absolute,
        .inset_left = .{ .px = 0 },
        .inset_top = .{ .px = 0 },
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, parent_id, .{ .min_w = 0, .max_w = 200, .min_h = 0, .max_h = 200 }, &scratch, 1.0);

    // Parent width = 200 (declared). Parent height should come from the one static child only = 40.
    const parent = store.get(parent_id);
    try testing.expectApproxEqAbs(@as(f32, 200), parent.computed.w, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 40), parent.computed.h, 1.0);
}

test "RC0: layout — absolute child placed at inset offset from parent" {
    // Parent is a 200×200 static block. Child has inset_left=10, inset_top=5.
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const parent_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .{ .px = 200 },
    });
    const child_id = try store.addChild(parent_id, store_mod.LayoutNode{
        .position = .absolute,
        .width = .{ .px = 50 },
        .height = .{ .px = 30 },
        .inset_left = .{ .px = 10 },
        .inset_top = .{ .px = 5 },
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, parent_id, .{ .min_w = 0, .max_w = 400, .min_h = 0, .max_h = 400 }, &scratch, 1.0);

    const parent = store.get(parent_id);
    const child = store.get(child_id);
    try testing.expectApproxEqAbs(parent.computed.x + 10, child.computed.x, 0.001);
    try testing.expectApproxEqAbs(parent.computed.y + 5, child.computed.y, 0.001);
}

test "RC0: layout — absolute child with both horizontal insets stretches width" {
    // A 200px wide parent with absolute child having inset_left=10, inset_right=10, width=auto
    // → computed.w = 200 - 10 - 10 = 180
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const parent_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .{ .px = 100 },
    });
    const child_id = try store.addChild(parent_id, store_mod.LayoutNode{
        .position = .absolute,
        .width = .auto,
        .height = .{ .px = 20 },
        .inset_left = .{ .px = 10 },
        .inset_right = .{ .px = 10 },
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, parent_id, .{ .min_w = 0, .max_w = 400, .min_h = 0, .max_h = 400 }, &scratch, 1.0);

    const child = store.get(child_id);
    try testing.expectApproxEqAbs(@as(f32, 180), child.computed.w, 0.5);
}

// ---------------------------------------------------------------------------
// RC1 — Sticky positioning
// ---------------------------------------------------------------------------

test "RC1: Position.sticky exists in the enum" {
    comptime {
        _ = store_mod.Position.sticky;
    }
}

test "RC1: class 'sticky' sets position = .sticky" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("sticky", tok);
    try testing.expectEqual(store_mod.Position.sticky, resolved.layout.position);
}

test "RC1: Scene._sticky_offset_y field exists" {
    comptime {
        std.debug.assert(@hasField(mod07.Scene, "_sticky_offset_y"));
    }
}

test "RC1: _sticky_offset_y initialized to 0 after instantiate" {
    var scene = makeScene();
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"sticky\"/>");
    const id = try scene.instantiate(desc, testTokens());
    const idx = id.index;

    // After instantiate, the sticky offset should be 0 for all elements.
    try testing.expect(idx < scene._sticky_offset_y.items.len);
    try testing.expectApproxEqAbs(@as(f32, 0.0), scene._sticky_offset_y.items[idx], 0.001);
}

test "RC1: layout — sticky element participates in normal flow (parent height includes it)" {
    // A block parent with one sticky child of height 40px.
    // The parent's computed height should include the sticky child (= 40px when parent height is auto).
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const parent_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .auto,
    });
    _ = try store.addChild(parent_id, store_mod.LayoutNode{
        .position = .sticky,
        .width = .{ .px = 200 },
        .height = .{ .px = 40 },
        .inset_top = .{ .px = 0 },
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, parent_id, .{ .min_w = 0, .max_w = 200, .min_h = 0, .max_h = 600 }, &scratch, 1.0);

    const parent = store.get(parent_id);
    // Sticky element contributes to normal flow — parent height >= 40.
    try testing.expect(parent.computed.h >= 40.0);
}

// ---------------------------------------------------------------------------
// RC2 — Flex wrap
// ---------------------------------------------------------------------------

test "RC2: LayoutNode.flex_wrap defaults to false" {
    const node = store_mod.LayoutNode{};
    try testing.expect(!node.flex_wrap);
}

test "RC2: class 'flex-wrap' sets flex_wrap = true" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("flex-wrap", tok);
    try testing.expect(resolved.layout.flex_wrap);
}

test "RC2: class 'flex-nowrap' sets flex_wrap = false" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("flex-nowrap", tok);
    try testing.expect(!resolved.layout.flex_wrap);
}

test "RC2: layout — wrapping row: three 80px children in 200px container wrap to two lines" {
    // Row 200px wide, three children each 80px wide, gap=4.
    // 80 + 4 + 80 = 164 fits on line 1. Third child wraps to line 2.
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const child_h: f32 = 20;

    const parent_id = try store.addRoot(store_mod.LayoutNode{
        .display = .flex,
        .direction = .row,
        .flex_wrap = true,
        .gap = 4,
        .width = .{ .px = 200 },
        .height = .auto,
    });
    const c0 = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = child_h },
    });
    const c1 = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = child_h },
    });
    const c2 = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = child_h },
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, parent_id, .{ .min_w = 0, .max_w = 200, .min_h = 0, .max_h = 1000 }, &scratch, 1.0);

    const p = store.get(parent_id);
    const ch0 = store.get(c0);
    const ch1 = store.get(c1);
    const ch2 = store.get(c2);

    // c0 and c1 are on line 1 — same y.
    try testing.expectApproxEqAbs(ch0.computed.y, ch1.computed.y, 0.5);

    // c2 is on line 2 — its y is greater.
    try testing.expect(ch2.computed.y > ch0.computed.y + child_h * 0.5);

    // Parent height = 2 lines + 1 gap = 2*child_h + gap = 2*20 + 4 = 44.
    try testing.expectApproxEqAbs(@as(f32, 2 * child_h + 4), p.computed.h, 1.0);
}

test "RC2: layout — no-wrap row: three 80px children overflow but stay on one line" {
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const child_h: f32 = 20;

    const parent_id = try store.addRoot(store_mod.LayoutNode{
        .display = .flex,
        .direction = .row,
        .flex_wrap = false,
        .gap = 4,
        .width = .{ .px = 200 },
        .height = .{ .px = child_h },
    });
    const c0 = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = child_h },
    });
    const c1 = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = child_h },
    });
    const c2 = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 80 },
        .height = .{ .px = child_h },
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, parent_id, .{ .min_w = 0, .max_w = 200, .min_h = 0, .max_h = 1000 }, &scratch, 1.0);

    const ch0 = store.get(c0);
    const ch1 = store.get(c1);
    const ch2 = store.get(c2);

    // All three children are on the same line (same y).
    try testing.expectApproxEqAbs(ch0.computed.y, ch1.computed.y, 0.5);
    try testing.expectApproxEqAbs(ch0.computed.y, ch2.computed.y, 0.5);

    // Parent height stays at child_h (explicit; no height expansion).
    const p = store.get(parent_id);
    try testing.expectApproxEqAbs(child_h, p.computed.h, 0.5);
}

test "RC2: layout — wrapping row: single wide child (no crash)" {
    // A 200px wide container with one 300px child and flex_wrap=true.
    // Should not crash; the child fits on a single line.
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const parent_id = try store.addRoot(store_mod.LayoutNode{
        .display = .flex,
        .direction = .row,
        .flex_wrap = true,
        .width = .{ .px = 200 },
        .height = .auto,
    });
    const c0 = try store.addChild(parent_id, store_mod.LayoutNode{
        .width = .{ .px = 300 },
        .height = .{ .px = 20 },
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, parent_id, .{ .min_w = 0, .max_w = 200, .min_h = 0, .max_h = 1000 }, &scratch, 1.0);

    const ch0 = store.get(c0);
    // Single child on its own line; overflow is not clipped by layout.
    try testing.expectApproxEqAbs(@as(f32, 300), ch0.computed.w, 0.5);
}

// ---------------------------------------------------------------------------
// RC3 — Aspect ratio
// ---------------------------------------------------------------------------

test "RC3: LayoutNode.aspect_ratio defaults to 0.0" {
    const node = store_mod.LayoutNode{};
    try testing.expectApproxEqAbs(@as(f32, 0.0), node.aspect_ratio, 0.001);
}

test "RC3: class 'aspect-square' sets aspect_ratio = 1.0" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("aspect-square", tok);
    try testing.expectApproxEqAbs(@as(f32, 1.0), resolved.layout.aspect_ratio, 0.001);
}

test "RC3: class 'aspect-video' sets aspect_ratio ≈ 1.778 (16/9)" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("aspect-video", tok);
    const expected: f32 = 16.0 / 9.0;
    try testing.expectApproxEqAbs(expected, resolved.layout.aspect_ratio, 0.001);
}

test "RC3: class 'aspect-auto' sets aspect_ratio = 0" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("aspect-auto", tok);
    try testing.expectApproxEqAbs(@as(f32, 0.0), resolved.layout.aspect_ratio, 0.001);
}

test "RC3: layout — width=200, height=auto, aspect_ratio=2.0 → computed.h = 100" {
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const node_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .auto,
        .aspect_ratio = 2.0,
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, node_id, .{ .min_w = 0, .max_w = 400, .min_h = 0, .max_h = 400 }, &scratch, 1.0);

    const node = store.get(node_id);
    try testing.expectApproxEqAbs(@as(f32, 100), node.computed.h, 0.5);
}

test "RC3: layout — width=100, height=auto, aspect_ratio=1.0 → computed.h = 100" {
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const node_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 100 },
        .height = .auto,
        .aspect_ratio = 1.0,
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, node_id, .{ .min_w = 0, .max_w = 400, .min_h = 0, .max_h = 400 }, &scratch, 1.0);

    const node = store.get(node_id);
    try testing.expectApproxEqAbs(@as(f32, 100), node.computed.h, 0.5);
}

test "RC3: layout — width=160, height=auto, aspect_ratio=16/9 → computed.h ≈ 90" {
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const node_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 160 },
        .height = .auto,
        .aspect_ratio = 16.0 / 9.0,
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, node_id, .{ .min_w = 0, .max_w = 400, .min_h = 0, .max_h = 400 }, &scratch, 1.0);

    const node = store.get(node_id);
    // 160 / (16/9) = 90 exactly
    try testing.expectApproxEqAbs(@as(f32, 90), node.computed.h, 0.5);
}

test "RC3: layout — explicit height and aspect_ratio: height unchanged" {
    // When both width and height are explicit, aspect_ratio is ignored.
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const node_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .{ .px = 50 }, // explicit, not auto
        .aspect_ratio = 1.0,     // should be ignored
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, node_id, .{ .min_w = 0, .max_w = 400, .min_h = 0, .max_h = 400 }, &scratch, 1.0);

    const node = store.get(node_id);
    try testing.expectApproxEqAbs(@as(f32, 50), node.computed.h, 0.5);
}

test "RC3: layout — aspect_ratio=0 leaves behavior unchanged" {
    // With aspect_ratio=0, a 200×auto block should have h=0 (no children, no measured).
    var store = try store_mod.ElementStore.testInit(testing.allocator);
    defer store.deinit();

    const node_id = try store.addRoot(store_mod.LayoutNode{
        .display = .block,
        .width = .{ .px = 200 },
        .height = .auto,
        .aspect_ratio = 0.0,
    });

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(&store, node_id, .{ .min_w = 0, .max_w = 400, .min_h = 0, .max_h = 400 }, &scratch, 1.0);

    const node = store.get(node_id);
    // No children and no measured → height should be 0 (same as before this feature).
    try testing.expectApproxEqAbs(@as(f32, 0), node.computed.h, 0.5);
}

// ---------------------------------------------------------------------------
// RC4 — Z-index
// ---------------------------------------------------------------------------

test "RC4: LayoutNode.z_index defaults to 0" {
    const node = store_mod.LayoutNode{};
    try testing.expectEqual(@as(i16, 0), node.z_index);
}

test "RC4: class 'z-10' sets z_index = 10" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("z-10", tok);
    try testing.expectEqual(@as(i16, 10), resolved.layout.z_index);
}

test "RC4: class 'z-50' sets z_index = 50" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("z-50", tok);
    try testing.expectEqual(@as(i16, 50), resolved.layout.z_index);
}

test "RC4: class 'z-0' sets z_index = 0" {
    const tok = testTokens();
    const resolved = markup_mod.resolveClasses("z-0", tok);
    try testing.expectEqual(@as(i16, 0), resolved.layout.z_index);
}

// Helper: build a minimal scene with a parent Row containing two Card children A and B,
// each given a specific z_index. Returns the indices of A and B.
//
// We use Cards (not Buttons) because Card has a non-transparent background color
// (bg_surface), which guarantees a .filled_rect draw command is emitted for each,
// making it easy to detect when each element appears in the draw list.
//
// The returned (a_idx, b_idx) are element indices in the scene.
const ZIndexSceneResult = struct {
    scene: mod07.Scene,
    root_id: mod07.ElementId,
    a_idx: u32,
    b_idx: u32,
};

fn buildZIndexScene(
    arena_alloc: std.mem.Allocator,
    z_a: i16,
    z_b: i16,
) !ZIndexSceneResult {
    const tok = testTokens();

    // Build markup as a Row with two Card children (self-closing).
    // We set size so the cards have non-zero computed rects and emit draw commands.
    var markup_buf: [256]u8 = undefined;
    const markup = try std.fmt.bufPrint(&markup_buf,
        "<Row class=\"w-50 h-12\"><Card class=\"w-20 h-12\"/><Card class=\"w-20 h-12\"/></Row>",
        .{},
    );

    var scene = mod07.Scene.init(testing.allocator);
    errdefer scene.deinit();

    const desc = try markup_mod.parse(arena_alloc, markup);
    const root_id = try scene.instantiate(desc, tok);

    // The row is index 0, first Card is index 1, second Card is index 2.
    // (Instantiation is depth-first; children follow the parent in element order.)
    const a_idx: u32 = 1;
    const b_idx: u32 = 2;

    // Apply z_index values directly to the layout nodes.
    scene.elements.layout.items[a_idx].z_index = z_a;
    scene.elements.layout.items[b_idx].z_index = z_b;

    return ZIndexSceneResult{
        .scene = scene,
        .root_id = root_id,
        .a_idx = a_idx,
        .b_idx = b_idx,
    };
}

/// Return the index of the first .filled_rect command whose .rect.x matches the
/// computed x of element `target_idx` within ±1 px. Returns null if not found.
fn firstFilledRectIndexFor(cmds: []const renderer_mod.DrawCommand, target_x: f32) ?usize {
    for (cmds, 0..) |cmd, i| {
        const fr = switch (cmd) {
            .filled_rect, .aa_filled_rect => |f| f,
            else => continue,
        };
        if (@abs(fr.rect.x - target_x) < 1.5) {
            return i;
        }
    }
    return null;
}

test "RC4: draw order — sibling A(z=0) drawn before B(z=10)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var result = try buildZIndexScene(arena.allocator(), 0, 10);
    defer result.scene.deinit();

    // Solve layout.
    var scratch: [4096]u8 = undefined;
    layout_mod.solve(result.scene.store(), result.root_id,
        .{ .min_w = 0, .max_w = 800, .min_h = 0, .max_h = 600 }, &scratch, 1.0);

    // Build draw list.
    var atlas = try renderer_mod.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try renderer_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try renderer_mod.buildDrawList(
        testing.allocator, &result.scene, &atlas, &img_atlas, &font, testTokens(),
        null, false, null,
    );
    defer testing.allocator.free(cmds);

    const store = result.scene.store();
    const a_x = store.get(.{ .index = result.a_idx, .gen = store.gen.items[result.a_idx] }).computed.x;
    const b_x = store.get(.{ .index = result.b_idx, .gen = store.gen.items[result.b_idx] }).computed.x;

    const a_cmd_idx = firstFilledRectIndexFor(cmds, a_x);
    const b_cmd_idx = firstFilledRectIndexFor(cmds, b_x);

    try testing.expect(a_cmd_idx != null);
    try testing.expect(b_cmd_idx != null);
    // B (z=10) must appear AFTER A (z=0) in the draw list.
    try testing.expect(b_cmd_idx.? > a_cmd_idx.?);
}

test "RC4: draw order — sibling A(z=20) drawn after B(z=10)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var result = try buildZIndexScene(arena.allocator(), 20, 10);
    defer result.scene.deinit();

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(result.scene.store(), result.root_id,
        .{ .min_w = 0, .max_w = 800, .min_h = 0, .max_h = 600 }, &scratch, 1.0);

    var atlas = try renderer_mod.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try renderer_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try renderer_mod.buildDrawList(
        testing.allocator, &result.scene, &atlas, &img_atlas, &font, testTokens(),
        null, false, null,
    );
    defer testing.allocator.free(cmds);

    const store = result.scene.store();
    const a_x = store.get(.{ .index = result.a_idx, .gen = store.gen.items[result.a_idx] }).computed.x;
    const b_x = store.get(.{ .index = result.b_idx, .gen = store.gen.items[result.b_idx] }).computed.x;

    const a_cmd_idx = firstFilledRectIndexFor(cmds, a_x);
    const b_cmd_idx = firstFilledRectIndexFor(cmds, b_x);

    try testing.expect(a_cmd_idx != null);
    try testing.expect(b_cmd_idx != null);
    // A (z=20) must appear AFTER B (z=10) in the draw list — A is on top.
    try testing.expect(a_cmd_idx.? > b_cmd_idx.?);
}

test "RC4: draw order — three siblings [z=0, z=10, z=5] drawn in order [z=0, z=5, z=10]" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const tok = testTokens();

    var markup_buf: [512]u8 = undefined;
    const markup = try std.fmt.bufPrint(&markup_buf,
        "<Row class=\"w-60 h-12\"><Card class=\"w-20 h-12\"/><Card class=\"w-20 h-12\"/><Card class=\"w-20 h-12\"/></Row>",
        .{},
    );

    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    const desc = try markup_mod.parse(arena.allocator(), markup);
    const root_id = try scene.instantiate(desc, tok);

    // Indices: row=0, card_a=1 (z=0), card_b=2 (z=10), card_c=3 (z=5)
    const a_idx: u32 = 1;
    const b_idx: u32 = 2;
    const c_idx: u32 = 3;

    scene.elements.layout.items[a_idx].z_index = 0;
    scene.elements.layout.items[b_idx].z_index = 10;
    scene.elements.layout.items[c_idx].z_index = 5;

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(scene.store(), root_id,
        .{ .min_w = 0, .max_w = 800, .min_h = 0, .max_h = 600 }, &scratch, 1.0);

    var atlas = try renderer_mod.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try renderer_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try renderer_mod.buildDrawList(
        testing.allocator, &scene, &atlas, &img_atlas, &font, tok,
        null, false, null,
    );
    defer testing.allocator.free(cmds);

    const store_ref = scene.store();
    const a_x = store_ref.get(.{ .index = a_idx, .gen = store_ref.gen.items[a_idx] }).computed.x;
    const b_x = store_ref.get(.{ .index = b_idx, .gen = store_ref.gen.items[b_idx] }).computed.x;
    const c_x = store_ref.get(.{ .index = c_idx, .gen = store_ref.gen.items[c_idx] }).computed.x;

    const a_pos = firstFilledRectIndexFor(cmds, a_x);
    const b_pos = firstFilledRectIndexFor(cmds, b_x);
    const c_pos = firstFilledRectIndexFor(cmds, c_x);

    try testing.expect(a_pos != null);
    try testing.expect(b_pos != null);
    try testing.expect(c_pos != null);

    // Expected draw order: z=0 (a) first, then z=5 (c), then z=10 (b) last.
    try testing.expect(a_pos.? < c_pos.?);
    try testing.expect(c_pos.? < b_pos.?);
}

test "RC4: draw order — container with > 256 children: sort skipped, no crash" {
    // Regression guard: buildDrawList must not crash or OOM when a container
    // has more than 256 children (the z-index sort stack buffer limit).
    // The expected behavior is graceful fallback to document order.
    const tok = testTokens();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Build markup: a row with 260 text labels, each with varying z-index.
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(arena.allocator(), "<Row class=\"flex-wrap\">");
    for (0..260) |i| {
        const z_class = switch (i % 6) {
            0 => "z-0",
            1 => "z-10",
            2 => "z-20",
            3 => "z-30",
            4 => "z-40",
            else => "z-50",
        };
        try buf.print(arena.allocator(), "<Text class=\"{s}\" text=\"{d}\"/>", .{ z_class, i });
    }
    try buf.appendSlice(arena.allocator(), "</Row>");

    var scene = mod07.Scene.init(testing.allocator);
    defer scene.deinit();

    const desc = try markup_mod.parse(arena.allocator(), buf.items);
    const root_id = try scene.instantiate(desc, tok);

    var scratch: [4096]u8 = undefined;
    layout_mod.solve(scene.store(), root_id,
        .{ .min_w = 0, .max_w = 800, .min_h = 0, .max_h = 4000 }, &scratch, 1.0);

    var atlas = try renderer_mod.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try renderer_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    // Must not crash or return an error.
    const cmds = try renderer_mod.buildDrawList(
        testing.allocator, &scene, &atlas, &img_atlas, &font, tok,
        null, false, null,
    );
    defer testing.allocator.free(cmds);

    // The sort was skipped and buildDrawList returned without error — that's the regression
    // guard.  With a stub font (no glyphs rasterised) and unstyled Text nodes the list may
    // be empty, so we only assert that the call succeeded (no crash / OOM).
}
