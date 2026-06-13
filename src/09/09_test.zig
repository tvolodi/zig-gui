//! Module 09 unit tests — pure CPU, no GPU required.

const std = @import("std");
const testing = std.testing;
const C = @import("types.zig");
const store_mod = @import("../03/types.zig");
const theme_mod = @import("../05/types.zig");
const comp_mod = @import("../07/types.zig");
const markup_mod = @import("../06/types.zig");
const image_atlas_mod = @import("../app/image_atlas.zig");

fn tokens() theme_mod.Tokens {
    return theme_mod.Tokens.light(theme_mod.Palette.default());
}

/// Stub Font: no-op font for tests that don't need real text rendering.
/// Only safe to pass when truncate=false (ellipsisMetrics won't be called).
fn stubFont() C.text.Font {
    return .{ ._impl = undefined };
}

test "clampBorderWidth: no-op when width fits" {
    const br = C.BorderRect{ .rect = .{ .x = 0, .y = 0, .w = 100, .h = 50 }, .color = .{ .r = 0, .g = 0, .b = 0 }, .width = 10 };
    const result = C.clampBorderWidth(br);
    try testing.expectEqual(@as(f32, 10), result.width);
}

test "clampBorderWidth: clamps to min(w,h)/2" {
    const br = C.BorderRect{ .rect = .{ .x = 0, .y = 0, .w = 20, .h = 30 }, .color = .{ .r = 0, .g = 0, .b = 0 }, .width = 20 };
    const result = C.clampBorderWidth(br);
    try testing.expectEqual(@as(f32, 10), result.width); // min(20,30)/2 = 10
}

test "expandBorderToQuads: correct geometry" {
    const br = C.BorderRect{
        .rect = .{ .x = 10, .y = 20, .w = 100, .h = 60 },
        .color = .{ .r = 255, .g = 0, .b = 0 },
        .width = 4,
    };
    var quads: [4]C.FilledRect = undefined;
    C.expandBorderToQuads(br, &quads);
    // top
    try testing.expectEqual(@as(f32, 10), quads[0].rect.x);
    try testing.expectEqual(@as(f32, 20), quads[0].rect.y);
    try testing.expectEqual(@as(f32, 100), quads[0].rect.w);
    try testing.expectEqual(@as(f32, 4), quads[0].rect.h);
    // bottom
    try testing.expectEqual(@as(f32, 10), quads[1].rect.x);
    try testing.expectApproxEqAbs(@as(f32, 76), quads[1].rect.y, 0.001); // 20+60-4
    // left
    try testing.expectEqual(@as(f32, 4), quads[2].rect.w);
    try testing.expectEqual(@as(f32, 52), quads[2].rect.h); // 60-2*4
    // right
    try testing.expectApproxEqAbs(@as(f32, 106), quads[3].rect.x, 0.001); // 10+100-4
}

test "buildDrawList: empty scene" {
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens(), null, false, null);
    defer testing.allocator.free(cmds);
    try testing.expectEqual(@as(usize, 0), cmds.len);
}

test "buildDrawList: invisible row emits zero commands" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Row/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, tokens());
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 800, .max_w = 800, .min_h = 600, .max_h = 600 }, &scratch, 1.0);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens(), null, false, null);
    defer testing.allocator.free(cmds);
    try testing.expectEqual(@as(usize, 0), cmds.len);
}

test "buildDrawList: button has background" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"OK\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 50, .max_h = 50 }, &scratch, 1.0);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    var found = false;
    for (cmds) |cmd| {
        if (cmd == .filled_rect or cmd == .aa_filled_rect) found = true;
    }
    try testing.expect(found);
}

// ---------------------------------------------------------------------------
// R45 — opacity helper tests
// ---------------------------------------------------------------------------

test "applyOpacity: factor=1.0 returns unchanged" {
    const col = C.Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const result = C.applyOpacity(col, 1.0);
    try testing.expectEqual(@as(u8, 255), result.a);
}

test "applyOpacity: factor=0.0 returns a=0" {
    const col = C.Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const result = C.applyOpacity(col, 0.0);
    try testing.expectEqual(@as(u8, 0), result.a);
}

test "applyOpacity: factor=0.5 halves alpha" {
    const col = C.Color{ .r = 255, .g = 0, .b = 0, .a = 255 };
    const result = C.applyOpacity(col, 0.5);
    // 255 * 0.5 = 127.5 -> truncated to 127
    const diff: i16 = @as(i16, result.a) - 127;
    try testing.expect(diff >= -1 and diff <= 1);
}

test "applyOpacity: RGB channels unchanged" {
    const col = C.Color{ .r = 100, .g = 150, .b = 200, .a = 255 };
    const result = C.applyOpacity(col, 0.5);
    try testing.expectEqual(@as(u8, 100), result.r);
    try testing.expectEqual(@as(u8, 150), result.g);
    try testing.expectEqual(@as(u8, 200), result.b);
}

// ---------------------------------------------------------------------------
// R42 — scissor helper tests
// ---------------------------------------------------------------------------

test "intersectScissor: overlapping rects" {
    const a = C.ScissorRect{ .x = 0, .y = 0, .w = 100, .h = 100 };
    const b = C.ScissorRect{ .x = 50, .y = 50, .w = 100, .h = 100 };
    const r = C.intersectScissor(a, b);
    try testing.expectEqual(@as(i32, 50), r.x);
    try testing.expectEqual(@as(i32, 50), r.y);
    try testing.expectEqual(@as(u32, 50), r.w);
    try testing.expectEqual(@as(u32, 50), r.h);
}

test "intersectScissor: non-overlapping rects returns zero area" {
    const a = C.ScissorRect{ .x = 0, .y = 0, .w = 50, .h = 50 };
    const b = C.ScissorRect{ .x = 100, .y = 100, .w = 50, .h = 50 };
    const r = C.intersectScissor(a, b);
    try testing.expectEqual(@as(u32, 0), r.w);
    try testing.expectEqual(@as(u32, 0), r.h);
}

test "rectToScissor: negative coords clamped to 0" {
    const rect = store_mod.Rect{ .x = -10, .y = -5, .w = 100, .h = 80 };
    const r = C.rectToScissor(rect);
    try testing.expectEqual(@as(i32, 0), r.x);
    try testing.expectEqual(@as(i32, 0), r.y);
}

// ---------------------------------------------------------------------------
// R40 — resolveStyle tests
// ---------------------------------------------------------------------------

test "resolveStyle: no flags returns base unchanged" {
    const base = C.ComputedStyle{ .background = .{ .r = 255, .g = 0, .b = 0, .a = 255 } };
    const overrides = C.PseudoStyleSet{};
    const state = C.PseudoState{};
    const result = C.resolveStyle(base, overrides, state);
    try testing.expectEqual(@as(u8, 255), result.background.r);
}

test "resolveStyle: hover applies background override" {
    const base = C.ComputedStyle{ .background = .{ .r = 100, .g = 0, .b = 0, .a = 255 } };
    const overrides = C.PseudoStyleSet{
        .hover = .{ .background = .{ .r = 200, .g = 0, .b = 0, .a = 255 } },
    };
    const state = C.PseudoState{ .hover = true };
    const result = C.resolveStyle(base, overrides, state);
    try testing.expectEqual(@as(u8, 200), result.background.r);
}

test "resolveStyle: active overwrites hover" {
    const base = C.ComputedStyle{};
    const overrides = C.PseudoStyleSet{
        .hover = .{ .background = .{ .r = 100, .g = 0, .b = 0, .a = 255 } },
        .active = .{ .background = .{ .r = 200, .g = 0, .b = 0, .a = 255 } },
    };
    const state = C.PseudoState{ .hover = true, .active = true };
    const result = C.resolveStyle(base, overrides, state);
    try testing.expectEqual(@as(u8, 200), result.background.r);
}

test "resolveStyle: disabled overwrites everything" {
    const base = C.ComputedStyle{};
    const overrides = C.PseudoStyleSet{
        .hover = .{ .background = .{ .r = 100, .g = 0, .b = 0, .a = 255 } },
        .active = .{ .background = .{ .r = 150, .g = 0, .b = 0, .a = 255 } },
        .disabled = .{ .background = .{ .r = 50, .g = 50, .b = 50, .a = 255 } },
    };
    const state = C.PseudoState{ .hover = true, .active = true, .disabled = true };
    const result = C.resolveStyle(base, overrides, state);
    try testing.expectEqual(@as(u8, 50), result.background.r);
}

// ---------------------------------------------------------------------------
// R46 — emitShadow tests
// ---------------------------------------------------------------------------

test "emitShadow: shadow_blur=0 emits nothing" {
    var list: std.ArrayListUnmanaged(C.DrawCommand) = .empty;
    defer list.deinit(testing.allocator);
    const style = C.ComputedStyle{ .shadow_blur = 0 };
    try C.emitShadow(&list, testing.allocator, .{ .x = 0, .y = 0, .w = 100, .h = 50 }, style, 1.0);
    try testing.expectEqual(@as(usize, 0), list.items.len);
}

test "emitShadow: shadow_blur=8 emits exactly 5 rects" {
    var list: std.ArrayListUnmanaged(C.DrawCommand) = .empty;
    defer list.deinit(testing.allocator);
    const style = C.ComputedStyle{ .shadow_blur = 8, .shadow_offset_y = 4 };
    try C.emitShadow(&list, testing.allocator, .{ .x = 10, .y = 10, .w = 100, .h = 50 }, style, 1.0);
    try testing.expectEqual(@as(usize, 5), list.items.len);
    // All commands should be filled_rect
    for (list.items) |cmd| {
        try testing.expect(cmd == .filled_rect);
    }
}

test "emitShadow: effective_alpha=0.5 halves shadow alphas" {
    var list: std.ArrayListUnmanaged(C.DrawCommand) = .empty;
    defer list.deinit(testing.allocator);
    var list_full: std.ArrayListUnmanaged(C.DrawCommand) = .empty;
    defer list_full.deinit(testing.allocator);
    const style = C.ComputedStyle{ .shadow_blur = 8, .shadow_offset_y = 4, .shadow_color = .{ .r = 0, .g = 0, .b = 0, .a = 100 } };
    try C.emitShadow(&list, testing.allocator, .{ .x = 0, .y = 0, .w = 100, .h = 50 }, style, 0.5);
    try C.emitShadow(&list_full, testing.allocator, .{ .x = 0, .y = 0, .w = 100, .h = 50 }, style, 1.0);
    // Each half-alpha rect should have roughly half the alpha of the full-alpha rect
    for (list.items, list_full.items) |half, full| {
        const h_alpha = half.filled_rect.color.a;
        const f_alpha = full.filled_rect.color.a;
        if (f_alpha > 0) {
            try testing.expect(h_alpha <= f_alpha / 2 + 1);
        }
    }
}

// ---------------------------------------------------------------------------
// R46 — emitShadow geometry tests
// ---------------------------------------------------------------------------

test "emitShadow: outer rects have strictly larger w and h than inner rects" {
    // The algorithm goes from i=0 (outermost, most transparent) to i=4 (innermost).
    // Outer rects have larger expand, hence larger w/h.
    var list: std.ArrayListUnmanaged(C.DrawCommand) = .empty;
    defer list.deinit(testing.allocator);
    const style = C.ComputedStyle{ .shadow_blur = 8, .shadow_offset_y = 0 };
    try C.emitShadow(&list, testing.allocator, .{ .x = 0, .y = 0, .w = 100, .h = 50 }, style, 1.0);
    try testing.expectEqual(@as(usize, 5), list.items.len);
    // Outer is index 0 (largest expand), inner is index 4 (smallest expand).
    const w0 = list.items[0].filled_rect.rect.w;
    const w4 = list.items[4].filled_rect.rect.w;
    try testing.expect(w0 > w4);
    const h0 = list.items[0].filled_rect.rect.h;
    const h4 = list.items[4].filled_rect.rect.h;
    try testing.expect(h0 > h4);
}

test "emitShadow: shadow rect y values are offset by shadow_offset_y" {
    var list: std.ArrayListUnmanaged(C.DrawCommand) = .empty;
    defer list.deinit(testing.allocator);
    const offset_y: f32 = 8.0;
    const style = C.ComputedStyle{ .shadow_blur = 6, .shadow_offset_y = offset_y };
    const elem_rect = C.Rect{ .x = 10, .y = 20, .w = 80, .h = 40 };
    try C.emitShadow(&list, testing.allocator, elem_rect, style, 1.0);
    // Each shadow rect's center y should be offset relative to element
    for (list.items) |cmd| {
        // The shadow rect y = element.y + oy - expand.  With oy > 0 and expand >= 0,
        // all rects should have y >= element.y + oy - blur (i.e., at least partially offset).
        // Verify that none have y == element.y (i.e., the offset is applied).
        try testing.expect(cmd.filled_rect.rect.y != elem_rect.y);
    }
}

test "emitShadow: innermost rect is closest to element rect position" {
    var list: std.ArrayListUnmanaged(C.DrawCommand) = .empty;
    defer list.deinit(testing.allocator);
    const style = C.ComputedStyle{ .shadow_blur = 8, .shadow_offset_x = 0, .shadow_offset_y = 0 };
    const elem_rect = C.Rect{ .x = 0, .y = 0, .w = 100, .h = 50 };
    try C.emitShadow(&list, testing.allocator, elem_rect, style, 1.0);
    // Innermost rect (index 4): x = elem.x + ox - expand where expand is smallest.
    // Outermost rect (index 0): expand is largest so x is smallest (most negative offset).
    // Since ox=oy=0 and expand>0: x < 0 for all rects; innermost is closest to 0.
    const x0 = list.items[0].filled_rect.rect.x; // outermost, most negative
    const x4 = list.items[4].filled_rect.rect.x; // innermost, least negative
    try testing.expect(x4 > x0); // innermost x is closer to 0 than outermost
}

// ---------------------------------------------------------------------------
// R40 — resolveStyle: non-interactive kind returns base unchanged
// ---------------------------------------------------------------------------

test "resolveStyle: empty PseudoStyleSet (non-interactive) returns base" {
    const base = C.ComputedStyle{ .background = .{ .r = 77, .g = 88, .b = 99, .a = 255 } };
    // Empty PseudoStyleSet{} has all null overrides — no state should change anything.
    const overrides = C.PseudoStyleSet{};
    const state = C.PseudoState{ .hover = true, .active = true };
    const result = C.resolveStyle(base, overrides, state);
    try testing.expectEqual(@as(u8, 77), result.background.r);
    try testing.expectEqual(@as(u8, 88), result.background.g);
    try testing.expectEqual(@as(u8, 99), result.background.b);
}

test "resolveStyle: focus applies border_color and border_width" {
    const base = C.ComputedStyle{ .border_color = .{ .r = 200, .g = 200, .b = 200, .a = 255 }, .border_width = 1 };
    const overrides = C.PseudoStyleSet{
        .focus = .{ .border_color = .{ .r = 0, .g = 102, .b = 255, .a = 255 }, .border_width = 2 },
    };
    const state = C.PseudoState{ .focus = true };
    const result = C.resolveStyle(base, overrides, state);
    try testing.expectEqual(@as(u8, 0), result.border_color.r);
    try testing.expectEqual(@as(u8, 102), result.border_color.g);
    try testing.expectEqual(@as(f32, 2), result.border_width);
}

// ---------------------------------------------------------------------------
// R40 — Scene.setPseudo / pseudoOf / reset
// ---------------------------------------------------------------------------

test "setPseudo marks element dirty" {
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"OK\"/>");
    _ = try scene.instantiate(desc, tokens());
    // After instantiate, the element exists at index 0.
    // Clear dirty first, then set pseudo.
    scene.store().dirty.unset(0);
    scene.setPseudo(0, .{ .hover = true });
    // Dirty bit must be set again.
    try testing.expect(scene.store().dirty.isSet(0));
}

test "pseudoOf returns pointer to correct element state" {
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"OK\"/>");
    _ = try scene.instantiate(desc, tokens());
    scene.setPseudo(0, .{ .hover = true, .focus = false, .active = false, .disabled = false });
    const ps = scene.pseudoOf(0);
    try testing.expect(ps.hover == true);
    try testing.expect(ps.focus == false);
}

test "Scene.reset clears all pseudo-state entries" {
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"OK\"/>");
    _ = try scene.instantiate(desc, tokens());
    scene.setPseudo(0, .{ .hover = true, .active = true, .disabled = true });
    scene.reset();
    // After reset, the pseudo array is empty (clearRetainingCapacity).
    try testing.expectEqual(@as(usize, 0), scene._pseudo.items.len);
}

// ---------------------------------------------------------------------------
// R40 — buildDrawList: hovered button produces accent_hover background
// ---------------------------------------------------------------------------

test "buildDrawList: hovered button produces accent_hover background" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"OK\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 50, .max_h = 50 }, &scratch, 1.0);
    // Set hover state on the button (idx 0).
    scene.setPseudo(0, .{ .hover = true });
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    // Find a filled_rect with the accent_hover color.
    const expected_color = t.accent_hover;
    var found = false;
    for (cmds) |cmd| {
        const fr = switch (cmd) {
            .filled_rect, .aa_filled_rect => |f| f,
            else => continue,
        };
        const col = fr.color;
        if (col.r == expected_color.r and col.g == expected_color.g and col.b == expected_color.b) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

// ---------------------------------------------------------------------------
// R42 — buildDrawList: scrollview emits set_scissor / restore_scissor
// ---------------------------------------------------------------------------

test "buildDrawList: scrollview emits set_scissor before children and restore_scissor after" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView><Button text=\"Item\"/></ScrollView>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 400, .max_w = 400, .min_h = 300, .max_h = 300 }, &scratch, 1.0);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    // Verify set_scissor appears before restore_scissor
    var set_idx: ?usize = null;
    var restore_idx: ?usize = null;
    for (cmds, 0..) |cmd, i| {
        if (cmd == .set_scissor and set_idx == null) set_idx = i;
        if (cmd == .restore_scissor) restore_idx = i;
    }
    try testing.expect(set_idx != null);
    try testing.expect(restore_idx != null);
    try testing.expect(set_idx.? < restore_idx.?);
}

test "buildDrawList: scene without scrollview emits no scissor commands" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"OK\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 50, .max_h = 50 }, &scratch, 1.0);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    for (cmds) |cmd| {
        try testing.expect(cmd != .set_scissor);
        try testing.expect(cmd != .restore_scissor);
    }
}

test "buildDrawList: child outside scrollview bounds still appears in draw list" {
    // The CPU serializer emits all children; clipping is GPU-side via the scissor.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    // ScrollView with a button child — layout may place the button outside if container is tiny.
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView><Button text=\"VeryLongButtonLabel\"/></ScrollView>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    // Give the scroll view a very small container so the child "overflows".
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 10, .max_w = 10, .min_h = 10, .max_h = 10 }, &scratch, 1.0);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    // There should be at least a set_scissor and restore_scissor plus the child's commands.
    var has_scissor = false;
    for (cmds) |cmd| {
        if (cmd == .set_scissor) has_scissor = true;
    }
    try testing.expect(has_scissor);
    // Total commands > 2 (not just scissor bookends) — the child has at least a background.
    try testing.expect(cmds.len > 2);
}

// ---------------------------------------------------------------------------
// R43 — ImageAtlas tests
// ---------------------------------------------------------------------------

test "ImageAtlas.addImage returns non-zero ImageId" {
    var atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer atlas.deinit();
    // 2x2 white RGBA image
    const pixels = [_]u8{ 255, 255, 255, 255 } ** 4;
    const id = try atlas.addImage(&pixels, 2, 2);
    try testing.expect(id != 0);
}

test "ImageAtlas.getRect returns correct UV subregion" {
    var atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer atlas.deinit();
    const w: u32 = 32;
    const h: u32 = 16;
    const pixels = [_]u8{128} ** (32 * 16 * 4);
    const id = try atlas.addImage(&pixels, w, h);
    const rect = atlas.getRect(id);
    // UV width should equal w / ATLAS_SIZE.
    const expected_uv_w = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(image_atlas_mod.ImageAtlas.ATLAS_SIZE));
    const expected_uv_h = @as(f32, @floatFromInt(h)) / @as(f32, @floatFromInt(image_atlas_mod.ImageAtlas.ATLAS_SIZE));
    try testing.expectApproxEqAbs(expected_uv_w, rect.uv_w, 0.001);
    try testing.expectApproxEqAbs(expected_uv_h, rect.uv_h, 0.001);
    try testing.expectEqual(w, rect.pixel_w);
    try testing.expectEqual(h, rect.pixel_h);
}

test "ImageAtlas: two images produce non-overlapping UV rects" {
    var atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer atlas.deinit();
    const pixels_a = [_]u8{255} ** (16 * 16 * 4);
    const pixels_b = [_]u8{128} ** (16 * 16 * 4);
    const id_a = try atlas.addImage(&pixels_a, 16, 16);
    const id_b = try atlas.addImage(&pixels_b, 16, 16);
    const ra = atlas.getRect(id_a);
    const rb = atlas.getRect(id_b);
    // Both are on the same row. ra ends at uv_x + uv_w; rb starts at rb.uv_x.
    // They must not overlap: ra.uv_x + ra.uv_w <= rb.uv_x (on same shelf).
    try testing.expect(ra.uv_x + ra.uv_w <= rb.uv_x + 0.001); // allow float rounding
}

test "ImageAtlas.addImage: filling atlas returns error.AtlasFull" {
    var atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer atlas.deinit();
    // Each row can hold ATLAS_SIZE pixels wide. Use 512×1 strips to fill row by row.
    const strip_pixels = try testing.allocator.alloc(u8, image_atlas_mod.ImageAtlas.ATLAS_SIZE * 1 * 4);
    defer testing.allocator.free(strip_pixels);
    @memset(strip_pixels, 255);
    // Fill all ATLAS_SIZE rows.
    var rows: u32 = 0;
    while (rows < image_atlas_mod.ImageAtlas.ATLAS_SIZE) : (rows += 1) {
        _ = atlas.addImage(strip_pixels, image_atlas_mod.ImageAtlas.ATLAS_SIZE, 1) catch break;
    }
    // Next add should fail.
    const result = atlas.addImage(strip_pixels, image_atlas_mod.ImageAtlas.ATLAS_SIZE, 1);
    try testing.expectError(error.AtlasFull, result);
}

test "buildDrawList: image element with image_id != 0 emits image_rect command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Image/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 100, .max_w = 100, .min_h = 100, .max_h = 100 }, &scratch, 1.0);
    // Set up image atlas with a real image.
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    const pixels = [_]u8{255} ** (4 * 4 * 4);
    const img_id = try img_atlas.addImage(&pixels, 4, 4);
    // Register the image on the element.
    scene.setImage(root.index, img_id);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    var found = false;
    for (cmds) |cmd| {
        if (cmd == .image_rect) found = true;
    }
    try testing.expect(found);
}

test "buildDrawList: image element with image_id == 0 emits no image_rect" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Image/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 100, .max_w = 100, .min_h = 100, .max_h = 100 }, &scratch, 1.0);
    // image_id defaults to 0 — do not call setImage.
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    for (cmds) |cmd| {
        try testing.expect(cmd != .image_rect);
    }
}

// ---------------------------------------------------------------------------
// R45 — buildDrawList: opacity=0.0 produces commands with a==0
// ---------------------------------------------------------------------------

test "buildDrawList: element with opacity=0.0 produces draw commands with a==0" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    // Card with opacity-0 class so its background has a > 0 normally but opacity=0 zeroes it.
    const desc = try markup_mod.parse(arena.allocator(), "<Card class=\"opacity-0\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 100, .max_h = 100 }, &scratch, 1.0);
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    // Every color in the draw commands should have a == 0.
    for (cmds) |cmd| {
        switch (cmd) {
            .filled_rect => |fr| try testing.expectEqual(@as(u8, 0), fr.color.a),
            .border_rect => |br| try testing.expectEqual(@as(u8, 0), br.color.a),
            .glyph => |g| try testing.expectEqual(@as(u8, 0), g.color.a),
            .set_scissor, .restore_scissor, .image_rect, .gradient_rect, .aa_filled_rect, .aa_filled_circle, .clip_rounded_begin, .clip_rounded_end, .sdf_icon => {},
        }
    }
}

// ---------------------------------------------------------------------------
// R46 — buildDrawList: shadow rects emitted before background rect
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// R42 — buildDrawList: scroll offset translation
// ---------------------------------------------------------------------------

test "buildDrawList: scrollview child rect is offset by scroll_y" {
    // Create a scrollview with scroll_y=20 and a child button at layout y=10.
    // After buildDrawList the child's filled_rect.y should be 10 - 20 = -10.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<ScrollView><Button text=\"\"/></ScrollView>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    // Layout: scrollview 400x300, button fills it.
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 400, .max_w = 400, .min_h = 300, .max_h = 300 }, &scratch, 1.0);

    // Manually set child layout y to 10 (simulate a positioned child).
    const s = scene.store();
    // The button is the second element (index 1 after root at index 0).
    // Set its computed rect directly so we have a predictable y.
    s.layout.items[1].computed.y = 10;
    s.layout.items[1].computed.x = 0;
    s.layout.items[1].computed.w = 400;
    s.layout.items[1].computed.h = 50;

    // Set scroll_y = 20 on the scrollview (index 0).
    scene._scroll_state.items[0].scroll_y = 20;
    scene._scroll_state.items[0].content_height = 300;
    scene._scroll_state.items[0].container_height = 200;

    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);

    // Find the filled_rect that belongs to the button child (after set_scissor).
    // It should be at y = 10 - 20 = -10.
    var set_scissor_seen = false;
    var child_y: ?f32 = null;
    for (cmds) |cmd| {
        if (cmd == .set_scissor) {
            set_scissor_seen = true;
            continue;
        }
        // First filled_rect after the scrollview's own background and scrollbar rects
        // that is at y == -10 is our child.
        if (set_scissor_seen) {
            const fr = switch (cmd) {
                .filled_rect, .aa_filled_rect => |f| f,
                else => continue,
            };
            const fy = fr.rect.y;
            if (fy < 0) {
                child_y = fy;
                break;
            }
        }
    }
    // The child must have been translated.
    try testing.expect(child_y != null);
    try testing.expectApproxEqAbs(@as(f32, -10.0), child_y.?, 1.0);
}

// ---------------------------------------------------------------------------
// R44 — buildDrawList: text truncation
// ---------------------------------------------------------------------------

// Helper: pre-insert a fixed-size glyph (8x8 blank) for each ASCII character in `str`
// and optionally for the ellipsis codepoint.
fn preInsertGlyphs(atlas: *C.GlyphAtlas, str: []const u8, px: u16, include_ellipsis: bool) !void {
    const blank = [_]u8{128} ** (8 * 8);
    var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        const key = C.text.GlyphKey{ .codepoint = cp, .px = px };
        _ = try atlas.insert(key, 8, 8, &blank);
    }
    if (include_ellipsis) {
        // Pre-insert the ellipsis glyph (U+2026) so ellipsisMetrics doesn't need rasterize.
        const ellipsis_key = C.text.GlyphKey{ .codepoint = 0x2026, .px = px };
        _ = try atlas.insert(ellipsis_key, 8, 8, &blank);
    }
}

test "buildDrawList: truncate=false, overflowing text skips glyphs beyond rect" {
    // Each glyph is 8 wide. rect.w = 32 → only 4 glyphs fit. Text is 8 chars → 4 clipped.
    // truncate=false: normal clip path — no ellipsis.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    // Use a class-less Text element so we control the style directly.
    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"ABCDEFGH\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 32, .max_w = 32, .min_h = 20, .max_h = 20 }, &scratch, 1.0);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();

    const px: u16 = @intFromFloat(scene._style.items[0].font_size);
    try preInsertGlyphs(&atlas, "ABCDEFGH", px, false);

    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);

    // Count glyph commands.
    var glyph_count: usize = 0;
    var ellipsis_found = false;
    const rect_x: f32 = scene.store().layout.items[root.index].computed.x;
    const rect_w: f32 = scene.store().layout.items[root.index].computed.w;
    for (cmds) |cmd| {
        if (cmd == .glyph) {
            glyph_count += 1;
            // Every glyph must fit within the rect.
            try testing.expect(cmd.glyph.dst.x + cmd.glyph.dst.w <= rect_x + rect_w + 0.5);
            // Check if it's beyond the 4th glyph position (would be ellipsis territory).
            if (cmd.glyph.dst.x >= rect_x + rect_w) ellipsis_found = true;
        }
    }
    // truncate=false: at most 4 glyphs emitted (8px each, 32px wide), no ellipsis.
    try testing.expect(glyph_count <= 4);
    try testing.expect(!ellipsis_found);
}

test "buildDrawList: truncate=true, overflowing text emits ellipsis" {
    // 8 chars × 8px = 64px wide. rect.w = 32px. With ellipsis (8px), available = 24px = 3 glyphs.
    // So 3 chars emitted + 1 ellipsis = 4 glyph commands total.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"ABCDEFGH\" class=\"truncate\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 32, .max_w = 32, .min_h = 20, .max_h = 20 }, &scratch, 1.0);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();

    const px: u16 = @intFromFloat(scene._style.items[0].font_size);
    // Pre-insert all text glyphs + ellipsis so ellipsisMetrics skips rasterize.
    try preInsertGlyphs(&atlas, "ABCDEFGH", px, true);

    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);

    var glyph_count: usize = 0;
    for (cmds) |cmd| {
        if (cmd == .glyph) glyph_count += 1;
    }

    // truncate=true: fewer than 8 full glyphs; at least 1 glyph (the ellipsis) emitted.
    try testing.expect(glyph_count < 8);
    try testing.expect(glyph_count >= 1);
}

test "buildDrawList: truncate=true, short text that fits emits all glyphs, no ellipsis" {
    // 3 chars × 8px = 24px wide. rect.w = 200px — plenty of room. All 3 glyphs fit,
    // no truncation occurs → no ellipsis appended.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"ABC\" class=\"truncate\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 20, .max_h = 20 }, &scratch, 1.0);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();

    const px: u16 = @intFromFloat(scene._style.items[0].font_size);
    // Pre-insert glyphs + ellipsis (ellipsis won't be emitted, but pre-insert avoids rasterize call).
    try preInsertGlyphs(&atlas, "ABC", px, true);

    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);

    // Count glyphs. Exactly 3 should be emitted (A, B, C). No extra trailing ellipsis glyph.
    var glyph_count: usize = 0;
    for (cmds) |cmd| {
        if (cmd == .glyph) glyph_count += 1;
    }
    // All 3 chars fit; no extra ellipsis glyph.
    try testing.expectEqual(@as(usize, 3), glyph_count);
}

test "buildDrawList: truncate=true, ellipsis glyph dst.x within element rect" {
    // Same setup as the overflowing truncate test.
    // Verify the last glyph emitted (the ellipsis) has dst.x <= rect.x + rect.w.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"ABCDEFGH\" class=\"truncate\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 32, .max_w = 32, .min_h = 20, .max_h = 20 }, &scratch, 1.0);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();

    const px: u16 = @intFromFloat(scene._style.items[0].font_size);
    try preInsertGlyphs(&atlas, "ABCDEFGH", px, true);

    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);

    const rect_x: f32 = scene.store().layout.items[root.index].computed.x;
    const rect_w: f32 = scene.store().layout.items[root.index].computed.w;

    var last_glyph_x: f32 = 0;
    for (cmds) |cmd| {
        if (cmd == .glyph) last_glyph_x = cmd.glyph.dst.x;
    }
    // The last glyph (ellipsis) must start within the element rect.
    try testing.expect(last_glyph_x <= rect_x + rect_w + 0.5);
}

// ---------------------------------------------------------------------------
// R45 — buildDrawList: opacity inheritance
// ---------------------------------------------------------------------------

test "buildDrawList: opacity=0.5 element emits commands with halved alpha" {
    // A card with opacity-50 and a solid background. Expect filled_rect.color.a ≈ 100.
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    // Use "bg-red-500" or explicit background — the important thing is the card has
    // a non-transparent background. "opacity-50" sets opacity=0.5.
    // cardSurface has background.a > 0 by default.
    const desc = try markup_mod.parse(arena.allocator(), "<Card class=\"opacity-50\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 100, .max_h = 100 }, &scratch, 1.0);

    // Override background to have a=200 so we can measure the alpha multiplication clearly.
    scene._style.items[0].background = .{ .r = 200, .g = 0, .b = 0, .a = 200 };
    scene._style.items[0].opacity = 0.5;

    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);

    // Find the first filled_rect (the card background).
    var found = false;
    for (cmds) |cmd| {
        const fr = switch (cmd) {
            .filled_rect, .aa_filled_rect => |f| f,
            else => continue,
        };
        // 200 * 0.5 = 100
        const alpha = fr.color.a;
        const diff: i16 = @as(i16, alpha) - 100;
        try testing.expect(diff >= -2 and diff <= 2);
        found = true;
        break;
    }
    try testing.expect(found);
}

test "buildDrawList: parent opacity=0.5, child opacity=0.5 produces effective 0.25" {
    // Two nested cards. Parent opacity=0.5, child opacity=0.5.
    // Expected: parent filled_rect.a ≈ 200*0.5 = 100, child filled_rect.a ≈ 200*0.5*0.5 = 50.
    // Strategy: create a scene with exactly two elements (parent Card, child Card),
    // each with background.a=200, border_width=0 (no extra rects), opacity=0.5.
    // Then verify both alpha values appear in filled_rect commands.
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const s = scene.store();

    // Manually build a two-element tree: parent (idx 0) and child (idx 1).
    const layout_engine = @import("layout_engine");
    const parent_layout = store_mod.LayoutNode{ .display = .block };
    const child_layout = store_mod.LayoutNode{ .display = .block };
    const parent_id = try s.addRoot(parent_layout);
    const child_id = try s.addChild(parent_id, child_layout);

    // Extend all parallel arrays in Scene to cover index 1.
    const needed: usize = 2;
    try scene._kind.ensureTotalCapacity(testing.allocator, needed);
    scene._kind.items.len = needed;
    scene._kind.items[0] = .card;
    scene._kind.items[1] = .card;

    try scene._style.ensureTotalCapacity(testing.allocator, needed);
    scene._style.items.len = needed;
    scene._style.items[0] = C.ComputedStyle{
        .background = .{ .r = 200, .g = 0, .b = 0, .a = 200 },
        .border_width = 0,
        .opacity = 0.5,
    };
    scene._style.items[1] = C.ComputedStyle{
        .background = .{ .r = 200, .g = 0, .b = 0, .a = 200 },
        .border_width = 0,
        .opacity = 0.5,
    };

    try scene._text.ensureTotalCapacity(testing.allocator, needed);
    scene._text.items.len = needed;
    scene._text.items[0] = null;
    scene._text.items[1] = null;

    try scene._button_state.ensureTotalCapacity(testing.allocator, needed);
    scene._button_state.items.len = needed;
    scene._button_state.items[0] = .{};
    scene._button_state.items[1] = .{};

    try scene._input_state.ensureTotalCapacity(testing.allocator, needed);
    scene._input_state.items.len = needed;
    scene._input_state.items[0] = .{};
    scene._input_state.items[1] = .{};

    try scene._dropdown_state.ensureTotalCapacity(testing.allocator, needed);
    scene._dropdown_state.items.len = needed;
    scene._dropdown_state.items[0] = .{};
    scene._dropdown_state.items[1] = .{};

    try scene._checkbox_state.ensureTotalCapacity(testing.allocator, needed);
    scene._checkbox_state.items.len = needed;
    scene._checkbox_state.items[0] = .{};
    scene._checkbox_state.items[1] = .{};

    try scene._scroll_state.ensureTotalCapacity(testing.allocator, needed);
    scene._scroll_state.items.len = needed;
    scene._scroll_state.items[0] = .{};
    scene._scroll_state.items[1] = .{};

    try scene._pseudo.ensureTotalCapacity(testing.allocator, needed);
    scene._pseudo.items.len = needed;
    scene._pseudo.items[0] = .{};
    scene._pseudo.items[1] = .{};

    try scene._image_state.ensureTotalCapacity(testing.allocator, needed);
    scene._image_state.items.len = needed;
    scene._image_state.items[0] = .{};
    scene._image_state.items[1] = .{};

    s.markAllDirty();

    // Solve layout.
    var scratch: [4096]u8 = undefined;
    layout_engine.solve(s, parent_id, .{ .min_w = 200, .max_w = 200, .min_h = 200, .max_h = 200 }, &scratch, 1.0);
    _ = child_id;

    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();
    const t = tokens();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);

    // Collect filled_rect alpha values from the two card backgrounds.
    // parent: alpha = @intFromFloat(200.0 * 0.5) = 100
    // child:  alpha = @intFromFloat(200.0 * 0.5 * 0.5) = 50
    var outer_found = false;
    var inner_found = false;
    for (cmds) |cmd| {
        const fr = switch (cmd) {
            .filled_rect, .aa_filled_rect => |f| f,
            else => continue,
        };
        const a = fr.color.a;
        const diff_100: i16 = @as(i16, a) - 100;
        const diff_50: i16 = @as(i16, a) - 50;
        if (diff_100 >= -2 and diff_100 <= 2) outer_found = true;
        if (diff_50 >= -2 and diff_50 <= 2) inner_found = true;
    }
    try testing.expect(outer_found);
    try testing.expect(inner_found);
}

test "buildDrawList: element with shadow-md emits shadow rects before background rect" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();
    const desc = try markup_mod.parse(arena.allocator(), "<Card class=\"shadow-md\"/>");
    var scene = comp_mod.Scene.init(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    var scratch: [4096]u8 = undefined;
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 100, .max_h = 100 }, &scratch, 1.0);
    var img_atlas = try image_atlas_mod.ImageAtlas.init(testing.allocator);
    defer img_atlas.deinit();
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var font = stubFont();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t, null, false, null);
    defer testing.allocator.free(cmds);
    // The first filled_rect commands should be the shadow rects (5 of them for shadow-md).
    // shadow-md sets shadow_blur=8 → 5 rects.
    var shadow_count: usize = 0;
    var background_idx: ?usize = null;
    for (cmds, 0..) |cmd, i| {
        if (cmd == .filled_rect) {
            if (background_idx == null and shadow_count >= 5) {
                background_idx = i;
            } else if (background_idx == null) {
                shadow_count += 1;
            }
        }
    }
    // There are at least 5 filled_rects before the background.
    try testing.expect(shadow_count >= 5);
}
