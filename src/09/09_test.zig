//! Module 09 unit tests — pure CPU, no GPU required.

const std = @import("std");
const testing = std.testing;
const C = @import("types.zig");
const store_mod = @import("../03/types.zig");
const theme_mod = @import("../05/types.zig");
const comp_mod = @import("../07/types.zig");
const markup_mod = @import("../06/types.zig");

fn tokens() theme_mod.Tokens {
    return theme_mod.Tokens.light(theme_mod.Palette.default());
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
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas);
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
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 800, .max_w = 800, .min_h = 600, .max_h = 600 }, &scratch);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas);
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
    @import("layout_engine").solve(scene.store(), root, .{ .min_w = 200, .max_w = 200, .min_h = 50, .max_h = 50 }, &scratch);
    var atlas = try C.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas);
    defer testing.allocator.free(cmds);
    var found = false;
    for (cmds) |cmd| {
        if (cmd == .filled_rect) found = true;
    }
    try testing.expect(found);
}
