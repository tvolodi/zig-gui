//! 02 — Text — acceptance_test.zig
//!
//! THIS FILE IS THE SPECIFICATION OF CORRECT BEHAVIOR (INV-5.3). DO NOT EDIT IT TO MAKE AN
//! IMPLEMENTATION PASS. If a test seems wrong, STOP and surface it to the human.
//!
//! Run with: `zig test acceptance_test.zig`
//! Most tests are pure (no font, no GPU). The font-dependent tests at the bottom load a test
//! font from TEST_FONT_PATH and SKIP if it is absent — provide a DejaVuSans.ttf (or similar,
//! with Cyrillic + a kern table) there to exercise them.
//!
//! "Done" for module 02 == all pure tests pass AND the font tests pass with a test font
//! present AND checklist.md is fully ticked.

const std = @import("std");
const testing = std.testing;
const T = @import("types.zig");

const TEST_FONT_PATH = "testdata/DejaVuSans.ttf";

fn w(width: f32) T.Word {
    return .{ .width = width };
}

// ---------------------------------------------------------------------------
// PURE: measureWidth sums words plus one space between each.
// ---------------------------------------------------------------------------
test "measureWidth sums words and inter-word spaces" {
    try testing.expectEqual(@as(f32, 0), T.measureWidth(&.{}, 5));
    try testing.expectEqual(@as(f32, 30), T.measureWidth(&.{w(30)}, 5)); // one word, no space
    // 10 + 20 + 30 + 2 spaces*5 = 70
    try testing.expectEqual(@as(f32, 70), T.measureWidth(&.{ w(10), w(20), w(30) }, 5));
}

// ---------------------------------------------------------------------------
// PURE: blockHeight is line_count * line_height.
// ---------------------------------------------------------------------------
test "blockHeight" {
    try testing.expectEqual(@as(f32, 0), T.blockHeight(0, 18));
    try testing.expectEqual(@as(f32, 54), T.blockHeight(3, 18));
}

// ---------------------------------------------------------------------------
// PURE: wrap keeps everything on one line when it fits.
// ---------------------------------------------------------------------------
test "wrap single line when it fits" {
    const words = [_]T.Word{ w(20), w(20), w(20) }; // 60 + 2*5 = 70
    var lines: [3]T.Line = undefined;
    const n = T.wrap(&words, 5, 100, &lines);
    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0), lines[0].first_word);
    try testing.expectEqual(@as(u32, 3), lines[0].word_count);
    try testing.expectApproxEqAbs(@as(f32, 70), lines[0].width, 0.5);
}

// ---------------------------------------------------------------------------
// PURE: wrap breaks at the right word when the run exceeds max_width.
//   words 40,40,40 with space 5, max 90:
//   line1 = [40,40] (40+5+40 = 85 <= 90); adding third → 85+5+40 = 130 > 90 → line2 = [40]
// ---------------------------------------------------------------------------
test "wrap breaks when exceeding max width" {
    const words = [_]T.Word{ w(40), w(40), w(40) };
    var lines: [3]T.Line = undefined;
    const n = T.wrap(&words, 5, 90, &lines);
    try testing.expectEqual(@as(u32, 2), n);
    try testing.expectEqual(@as(u32, 2), lines[0].word_count); // first two words
    try testing.expectEqual(@as(u32, 2), lines[1].first_word); // resumes at word index 2
    try testing.expectEqual(@as(u32, 1), lines[1].word_count);
}

// ---------------------------------------------------------------------------
// PURE: a single word wider than max_width gets its own line and overflows (no infinite loop).
// ---------------------------------------------------------------------------
test "wrap oversized single word overflows on its own line" {
    const words = [_]T.Word{ w(200), w(10) }; // first word alone exceeds max 50
    var lines: [2]T.Line = undefined;
    const n = T.wrap(&words, 5, 50, &lines);
    try testing.expectEqual(@as(u32, 2), n);
    try testing.expectEqual(@as(u32, 1), lines[0].word_count); // oversized word alone
    try testing.expectApproxEqAbs(@as(f32, 200), lines[0].width, 0.5); // allowed to overflow
    try testing.expectEqual(@as(u32, 1), lines[1].word_count);
}

// ---------------------------------------------------------------------------
// PURE: empty input → zero lines, no crash.
// ---------------------------------------------------------------------------
test "wrap empty input" {
    var lines: [1]T.Line = undefined;
    try testing.expectEqual(@as(u32, 0), T.wrap(&.{}, 5, 100, &lines));
}

// ---------------------------------------------------------------------------
// PURE: atlas packs synthetic glyphs without overlap and within bounds; caches by key.
// ---------------------------------------------------------------------------
fn rectsOverlap(a: T.AtlasRect, b: T.AtlasRect) bool {
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h;
}

test "atlas packing is non-overlapping and in-bounds, with caching" {
    var atlas = try T.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();

    var rects: [16]T.AtlasRect = undefined;
    var buf: [16 * 16]u8 = [_]u8{0xFF} ** (16 * 16);
    var i: u32 = 0;
    while (i < rects.len) : (i += 1) {
        const gw: u32 = 8 + (i % 3) * 4; // varying sizes 8,12,16
        const gh: u32 = 10;
        rects[i] = try atlas.insert(
            .{ .codepoint = @intCast('A' + i), .px = 16 },
            gw,
            gh,
            buf[0 .. gw * gh],
        );
    }

    // No two inserted rects overlap, and all fit in the (possibly grown) atlas.
    for (rects, 0..) |ra, a_idx| {
        try testing.expect(ra.x + ra.w <= atlas.width);
        try testing.expect(ra.y + ra.h <= atlas.height);
        for (rects[a_idx + 1 ..]) |rb| {
            try testing.expect(!rectsOverlap(ra, rb));
        }
    }

    // Cache: lookup and re-insert of an existing key return the same rect.
    const key = T.GlyphKey{ .codepoint = 'A', .px = 16 };
    const looked = atlas.lookup(key).?;
    try testing.expectEqual(rects[0], looked);
    const reinserted = try atlas.insert(key, 8, 10, buf[0..80]);
    try testing.expectEqual(rects[0], reinserted);
}

// ---------------------------------------------------------------------------
// PURE: atlas grows when full; entries inserted before growth remain valid.
// ---------------------------------------------------------------------------
test "atlas grows and preserves prior entries" {
    var atlas = try T.GlyphAtlas.init(testing.allocator, 16, 16); // tiny on purpose
    defer atlas.deinit();

    var buf: [10 * 10]u8 = [_]u8{0xFF} ** 100;
    const first = try atlas.insert(.{ .codepoint = 'X', .px = 16 }, 10, 10, &buf);

    // Force growth: another 10x10 cannot fit beside the first in a 16x16 atlas.
    _ = try atlas.insert(.{ .codepoint = 'Y', .px = 16 }, 10, 10, &buf);

    // The first glyph is still retrievable and correct after growth.
    const again = atlas.lookup(.{ .codepoint = 'X', .px = 16 }).?;
    try testing.expectEqual(first, again);
    try testing.expect(atlas.width >= 16 and atlas.height >= 16);
}

// ===========================================================================
// FONT-DEPENDENT: skip if no test font is present.
// ===========================================================================

fn loadTestFont(gpa: std.mem.Allocator) !?[]u8 {
    const file = std.fs.cwd().openFile(TEST_FONT_PATH, .{}) catch return null;
    defer file.close();
    return try file.readToEndAlloc(gpa, 16 * 1024 * 1024);
}

test "FONT: rasterize Latin and Cyrillic glyphs" {
    const bytes = (try loadTestFont(testing.allocator)) orelse {
        std.debug.print("skipping font test: {s} not present\n", .{TEST_FONT_PATH});
        return error.SkipZigTest;
    };
    defer testing.allocator.free(bytes);

    var font = try T.Font.initFromBytes(testing.allocator, bytes);
    defer font.deinit();

    const fm = font.metrics(16);
    try testing.expect(fm.ascent > 0);
    try testing.expect(fm.ascent + fm.descent + fm.line_gap > 0);

    // Latin 'A'
    const a = try font.rasterize(testing.allocator, 'A', 16);
    defer testing.allocator.free(@constCast(a.bitmap));
    try testing.expect(a.advance > 0);
    try testing.expect(a.width > 0 and a.height > 0);
    try testing.expectEqual(a.width * a.height, @as(u32, @intCast(a.bitmap.len)));

    // Cyrillic 'Д' (U+0414)
    const d = try font.rasterize(testing.allocator, 0x0414, 16);
    defer testing.allocator.free(@constCast(d.bitmap));
    try testing.expect(d.advance > 0);
    try testing.expect(d.width > 0 and d.height > 0);
}

test "FONT: layoutParagraph produces positioned glyphs and a sane extent" {
    const bytes = (try loadTestFont(testing.allocator)) orelse return error.SkipZigTest;
    defer testing.allocator.free(bytes);

    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var font = try T.Font.initFromBytes(testing.allocator, bytes);
    defer font.deinit();
    var atlas = try T.GlyphAtlas.init(testing.allocator, 256, 256);
    defer atlas.deinit();

    const para = try T.layoutParagraph(arena.allocator(), &font, &atlas, "Привет world", 16, 1000);
    try testing.expect(para.glyphs.len > 0);
    try testing.expect(para.extent.w > 0);
    try testing.expect(para.extent.h > 0);

    // Glyphs advance left-to-right on a single line (no wrap at width 1000).
    var prev_x: f32 = -1;
    for (para.glyphs) |g| {
        try testing.expect(g.dest_x >= prev_x);
        prev_x = g.dest_x;
    }
}
