//! 09 — Renderer — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3). DO NOT EDIT IT TO MAKE AN
//! IMPLEMENTATION PASS. If a test seems wrong, STOP and surface it to the human.
//!
//! Pure CPU tests run always. GPU tests skip automatically if Vulkan is unavailable.
//! Run with: `zig build test-09`.
//! "Done" for module 09 == all pure tests pass, GPU tests pass on a Vulkan-capable machine,
//! AND checklist.md is fully ticked.

const std = @import("std");
const testing = std.testing;
const C = @import("types.zig");
const store_mod = @import("../03_element_store/types.zig");
const theme_mod = @import("../05_theme/types.zig");
const comp_mod = @import("../07_components/types.zig");
const markup_mod = @import("../06_markup_style/types.zig");
const platform_mod = @import("../01_platform/types.zig");
const layout_mod = @import("../04_layout_engine/types.zig");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn tokens() theme_mod.Tokens {
    return theme_mod.Tokens.light(theme_mod.Palette.default());
}

fn makeScene(alloc: std.mem.Allocator) comp_mod.Scene {
    return comp_mod.Scene.init(alloc);
}

fn makeDummyImageAtlas(alloc: std.mem.Allocator) !C.ImageAtlas {
    return C.ImageAtlas.init(alloc);
}

/// Stub Font: no-op font for tests that don't perform real text rendering.
/// Only safe to pass when truncate=false or when no glyphs are rasterized.
fn stubFont() C.text.Font {
    return .{ ._impl = undefined };
}

// Manually solve a single-element scene with the given available size.
fn solve(scene: *comp_mod.Scene, root: store_mod.ElementId, w: f32, h: f32) void {
    var scratch: [4096]u8 = undefined;
    layout_mod.solve(scene.store(), root, .{ .min_w = w, .max_w = w, .min_h = h, .max_h = h }, &scratch);
}

// ---------------------------------------------------------------------------
// Pure CPU tests — buildDrawList
// ---------------------------------------------------------------------------

test "invisible element (transparent bg, no border, no text) emits no commands" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // A Row has no default background and no default border.
    const desc = try markup_mod.parse(arena.allocator(), "<Row/>");
    var scene = makeScene(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, tokens());
    solve(&scene, root, 800, 600);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try makeDummyImageAtlas(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens()), null, false;
    defer testing.allocator.free(cmds);

    try testing.expectEqual(@as(usize, 0), cmds.len);
}

test "zero-size element emits no commands" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Parse a button but do NOT call solve — computed stays zero.
    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"x\"/>");
    var scene = makeScene(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, tokens());
    // Intentionally skip solve: computed = {0,0,0,0}
    _ = root;

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try makeDummyImageAtlas(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens()), null, false;
    defer testing.allocator.free(cmds);

    try testing.expectEqual(@as(usize, 0), cmds.len);
}

test "button with solid background emits filled_rect with correct color and rect" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const t = tokens();

    const desc = try markup_mod.parse(arena.allocator(), "<Button text=\"Save\"/>");
    var scene = makeScene(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, t);
    solve(&scene, root, 200, 50);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try makeDummyImageAtlas(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, t), null, false;
    defer testing.allocator.free(cmds);

    // Must contain at least one filled_rect (background).
    var found_bg = false;
    for (cmds) |cmd| {
        switch (cmd) {
            .filled_rect => |r| {
                // Color must match the button's default background (accent).
                if (r.color.r == t.accent.r and r.color.g == t.accent.g and
                    r.color.b == t.accent.b)
                {
                    // Rect must be non-zero.
                    try testing.expect(r.rect.w > 0);
                    try testing.expect(r.rect.h > 0);
                    found_bg = true;
                }
            },
            else => {},
        }
    }
    try testing.expect(found_bg);
}

test "element with border emits border_rect command" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    // Input widget has a border by default (inputDefault in module 05).
    const desc = try markup_mod.parse(arena.allocator(), "<Input/>");
    var scene = makeScene(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, tokens());
    solve(&scene, root, 300, 40);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try makeDummyImageAtlas(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens()), null, false;
    defer testing.allocator.free(cmds);

    var found_border = false;
    for (cmds) |cmd| {
        if (cmd == .border_rect) found_border = true;
    }
    try testing.expect(found_border);
}

test "painter order: parent filled_rect comes before child filled_rect" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(),
        \\<Card><Button text="ok"/></Card>
    );
    var scene = makeScene(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, tokens());
    solve(&scene, root, 300, 100);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try makeDummyImageAtlas(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens()), null, false;
    defer testing.allocator.free(cmds);

    // Find index of parent (card) bg and child (button) bg.
    // Card rect is larger; button rect is nested inside it.
    var parent_idx: ?usize = null;
    var child_idx: ?usize = null;
    for (cmds, 0..) |cmd, i| {
        switch (cmd) {
            .filled_rect => |r| {
                if (parent_idx == null) {
                    parent_idx = i;
                } else if (child_idx == null and r.rect.w < cmds[parent_idx.?].filled_rect.rect.w) {
                    child_idx = i;
                }
            },
            else => {},
        }
    }
    try testing.expect(parent_idx != null);
    try testing.expect(child_idx != null);
    try testing.expect(parent_idx.? < child_idx.?);
}

test "border_rect clamped when width exceeds half of min dimension" {
    // A 10x10 rect with border_width=8 must clamp to width=5 (min(10,10)/2).
    const border = C.BorderRect{
        .rect = .{ .x = 0, .y = 0, .w = 10, .h = 10 },
        .color = .{ .r = 255, .g = 0, .b = 0, .a = 255 },
        .width = 8,
    };
    const clamped = C.clampBorderWidth(border);
    try testing.expectEqual(@as(f32, 5), clamped.width);
}

test "border_rect expands to four filled quads covering each edge" {
    const border = C.BorderRect{
        .rect = .{ .x = 10, .y = 20, .w = 100, .h = 60 },
        .color = .{ .r = 0, .g = 0, .b = 255, .a = 255 },
        .width = 2,
    };
    var quads: [4]C.FilledRect = undefined;
    C.expandBorderToQuads(border, &quads);

    // Top edge
    try testing.expectEqual(@as(f32, 10), quads[0].rect.x);
    try testing.expectEqual(@as(f32, 20), quads[0].rect.y);
    try testing.expectEqual(@as(f32, 100), quads[0].rect.w);
    try testing.expectEqual(@as(f32, 2), quads[0].rect.h);

    // Bottom edge
    try testing.expectEqual(@as(f32, 10), quads[1].rect.x);
    try testing.expectApproxEqAbs(@as(f32, 78), quads[1].rect.y, 0.001); // 20+60-2
    try testing.expectEqual(@as(f32, 100), quads[1].rect.w);
    try testing.expectEqual(@as(f32, 2), quads[1].rect.h);

    // Left edge (inner height: h - 2*width = 56)
    try testing.expectEqual(@as(f32, 10), quads[2].rect.x);
    try testing.expectEqual(@as(f32, 22), quads[2].rect.y); // 20+2
    try testing.expectEqual(@as(f32, 2), quads[2].rect.w);
    try testing.expectEqual(@as(f32, 56), quads[2].rect.h);

    // Right edge
    try testing.expectEqual(@as(f32, 108), quads[3].rect.x); // 10+100-2
    try testing.expectEqual(@as(f32, 22), quads[3].rect.y);
    try testing.expectEqual(@as(f32, 2), quads[3].rect.w);
    try testing.expectEqual(@as(f32, 56), quads[3].rect.h);
}

test "text element emits glyph commands (font present, else skip)" {
    // Load font — skip if absent.
    var threaded: std.Io.Threaded = .init(testing.allocator, .{});
    const io = threaded.io();
    const font_bytes = std.Io.Dir.cwd().readFileAlloc(
        io, "testdata/DejaVuSans.ttf", testing.allocator, .unlimited,
    ) catch return error.SkipZigTest;
    defer testing.allocator.free(font_bytes);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const desc = try markup_mod.parse(arena.allocator(), "<Text text=\"Hi\"/>");
    var scene = makeScene(testing.allocator);
    defer scene.deinit();
    const root = try scene.instantiate(desc, tokens());

    var font = try C.text.Font.initFromBytes(testing.allocator, font_bytes);
    defer font.deinit();
    var atlas = try C.GlyphAtlas.init(testing.allocator, 512, 512);
    defer atlas.deinit();

    try scene.measurePass(&font, &atlas);
    solve(&scene, root, 800, 600);

    var img_atlas = try makeDummyImageAtlas(testing.allocator);
    defer img_atlas.deinit();

    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens()), null, false;
    defer testing.allocator.free(cmds);

    var glyph_count: usize = 0;
    for (cmds) |cmd| {
        if (cmd == .glyph) glyph_count += 1;
    }
    // "Hi" = 2 visible glyphs (H and i); may be more due to spacing glyphs.
    try testing.expect(glyph_count >= 2);

    // Each glyph command must have a non-zero dst and a uv inside 0..1.
    for (cmds) |cmd| {
        switch (cmd) {
            .glyph => |g| {
                try testing.expect(g.dst.w > 0);
                try testing.expect(g.dst.h > 0);
                try testing.expect(g.uv.x >= 0 and g.uv.x <= 1);
                try testing.expect(g.uv.y >= 0 and g.uv.y <= 1);
                try testing.expect(g.uv.w > 0 and g.uv.w <= 1);
                try testing.expect(g.uv.h > 0 and g.uv.h <= 1);
            },
            else => {},
        }
    }
}

test "empty draw list is valid (no commands emitted, no crash)" {
    var scene = makeScene(testing.allocator);
    defer scene.deinit();

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();
    var img_atlas = try makeDummyImageAtlas(testing.allocator);
    defer img_atlas.deinit();
    var font = stubFont();

    const cmds = try C.buildDrawList(testing.allocator, &scene, &atlas, &img_atlas, &font, tokens()), null, false;
    defer testing.allocator.free(cmds);

    try testing.expectEqual(@as(usize, 0), cmds.len);
}

// ---------------------------------------------------------------------------
// GPU tests — skip if no Vulkan display
// ---------------------------------------------------------------------------

fn tryInitVulkan(alloc: std.mem.Allocator) !struct {
    platform: platform_mod.Platform,
    backend: platform_mod.VulkanBackend,
} {
    const platform = platform_mod.Platform.init(alloc, .{ .title = "09-test", .width = 1, .height = 1 }) catch
        return error.SkipZigTest;
    const backend = platform_mod.VulkanBackend.init(alloc, @constCast(&platform)) catch {
        var p = platform;
        p.deinit();
        return error.SkipZigTest;
    };
    return .{ .platform = platform, .backend = backend };
}

test "GPU: initQuadPipeline succeeds and validation is clean" {
    var ctx = tryInitVulkan(testing.allocator) catch return error.SkipZigTest;
    defer {
        ctx.backend.deinitQuadPipeline();
        ctx.backend.deinit();
        ctx.platform.deinit();
    }

    try ctx.backend.initQuadPipeline(testing.allocator);
    try testing.expectEqual(@as(u32, 0), ctx.backend.validationIssueCount());
}

test "GPU: drawFrame with empty command list completes without validation errors" {
    var ctx = tryInitVulkan(testing.allocator) catch return error.SkipZigTest;
    defer {
        ctx.backend.deinitQuadPipeline();
        ctx.backend.deinit();
        ctx.platform.deinit();
    }
    try ctx.backend.initQuadPipeline(testing.allocator);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();

    const impl = try ctx.backend._impl_vulkan();
    var gpu_atlas = try C.GpuAtlas.upload(
        testing.allocator,
        impl.device,
        impl.phys_device,
        impl.cmd_pool,
        impl.graphics_queue,
        &atlas,
    );
    defer gpu_atlas.deinit(impl.device);

    if (ctx.backend.beginFrame()) {
        ctx.backend.drawFrame(&.{}, &gpu_atlas);
        ctx.backend.endFrame();
    }
    try testing.expectEqual(@as(u32, 0), ctx.backend.validationIssueCount());
}

test "GPU: GpuAtlas re-upload after atlas change is clean" {
    var ctx = tryInitVulkan(testing.allocator) catch return error.SkipZigTest;
    defer {
        ctx.backend.deinitQuadPipeline();
        ctx.backend.deinit();
        ctx.platform.deinit();
    }
    try ctx.backend.initQuadPipeline(testing.allocator);

    var atlas = try C.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();

    const impl = try ctx.backend._impl_vulkan();

    // First upload.
    var gpu_atlas = try C.GpuAtlas.upload(
        testing.allocator, impl.device, impl.phys_device,
        impl.cmd_pool, impl.graphics_queue, &atlas,
    );

    // Simulate atlas update (increment generation manually).
    atlas.generation += 1;

    // Re-upload (old resources freed, new ones created).
    gpu_atlas.deinit(impl.device);
    gpu_atlas = try C.GpuAtlas.upload(
        testing.allocator, impl.device, impl.phys_device,
        impl.cmd_pool, impl.graphics_queue, &atlas,
    );
    defer gpu_atlas.deinit(impl.device);

    try testing.expectEqual(@as(u32, 0), ctx.backend.validationIssueCount());
}
