//! 02 — Text — unit tests
//! Run via: `zig build test-02-unit`
//!
//! These tests go DEEPER than the acceptance tests in docs/specs/02.acceptance_test.zig.
//! They target boundary values, zero-inputs, exact-fit edges, and multi-cycle atlas growth.
//! DO NOT modify docs/specs/02.acceptance_test.zig (INV-5.3).
const std = @import("std");
const testing = std.testing;
const T = @import("types.zig");

/// Helper: construct a Word from a plain width value.
fn w(width: f32) T.Word {
    return .{ .width = width };
}

// ===========================================================================
// measureWidth — edge cases
// ===========================================================================

test "measureWidth: two equal words" {
    // 15 + 15 + 1 space*5 = 35
    try testing.expectEqual(@as(f32, 35), T.measureWidth(&.{ w(15), w(15) }, 5));
}

test "measureWidth: very large space_w dominates" {
    // 10 + 10 + 1*1000 = 1020 — confirms space term is scaled by (len-1) not len
    try testing.expectEqual(@as(f32, 1020), T.measureWidth(&.{ w(10), w(10) }, 1000));
}

test "measureWidth: space_w = 0 sums word widths only" {
    // 10 + 20 + 30 + 0 inter-word spaces = 60
    try testing.expectEqual(@as(f32, 60), T.measureWidth(&.{ w(10), w(20), w(30) }, 0));
}

// ===========================================================================
// blockHeight — edge cases
// ===========================================================================

test "blockHeight: single line" {
    try testing.expectEqual(@as(f32, 18), T.blockHeight(1, 18));
}

test "blockHeight: line_height = 0 always returns 0" {
    try testing.expectEqual(@as(f32, 0), T.blockHeight(5, 0));
}

test "blockHeight: 100 lines" {
    try testing.expectEqual(@as(f32, 200), T.blockHeight(100, 2));
}

// ===========================================================================
// wrap — additional edge cases
// ===========================================================================

test "wrap: single word that exactly fits max_width stays on its own line without overflow" {
    // word(50), max_width=50 → 50 <= 50, so one line, no overflow flag needed.
    const words = [_]T.Word{w(50)};
    var lines: [1]T.Line = undefined;
    const n = T.wrap(&words, 5, 50, &lines);
    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0), lines[0].first_word);
    try testing.expectEqual(@as(u32, 1), lines[0].word_count);
    try testing.expectApproxEqAbs(@as(f32, 50), lines[0].width, 0.001);
}

test "wrap: multiple oversized words each land on their own line" {
    // Both 200px words exceed max_width=50.  Neither may trigger an infinite loop.
    const words = [_]T.Word{ w(200), w(200) };
    var lines: [2]T.Line = undefined;
    const n = T.wrap(&words, 5, 50, &lines);
    try testing.expectEqual(@as(u32, 2), n);
    try testing.expectEqual(@as(u32, 0), lines[0].first_word);
    try testing.expectEqual(@as(u32, 1), lines[0].word_count);
    try testing.expectApproxEqAbs(@as(f32, 200), lines[0].width, 0.001);
    try testing.expectEqual(@as(u32, 1), lines[1].first_word);
    try testing.expectEqual(@as(u32, 1), lines[1].word_count);
    try testing.expectApproxEqAbs(@as(f32, 200), lines[1].width, 0.001);
}

test "wrap: four words all fitting on one line — correct first_word and word_count" {
    // 10 + 5 + 10 + 5 + 10 + 5 + 10 = 55 <= 200
    const words = [_]T.Word{ w(10), w(10), w(10), w(10) };
    var lines: [4]T.Line = undefined;
    const n = T.wrap(&words, 5, 200, &lines);
    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0), lines[0].first_word);
    try testing.expectEqual(@as(u32, 4), lines[0].word_count);
    try testing.expectApproxEqAbs(@as(f32, 55), lines[0].width, 0.001);
}

test "wrap: two words summing to exactly max_width stay on one line" {
    // 20 + 5 + 20 = 45 == max_width=45.  The condition is (next > max), so 45 > 45 is false.
    const words = [_]T.Word{ w(20), w(20) };
    var lines: [2]T.Line = undefined;
    const n = T.wrap(&words, 5, 45, &lines);
    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0), lines[0].first_word);
    try testing.expectEqual(@as(u32, 2), lines[0].word_count);
    try testing.expectApproxEqAbs(@as(f32, 45), lines[0].width, 0.001);
}

test "wrap: out_lines has exactly words.len slots — worst-case one word per line" {
    // Three 100px words with max_width=50: every word overflows onto its own line.
    // out_lines has exactly 3 slots.  No out-of-bounds access must occur.
    const words = [_]T.Word{ w(100), w(100), w(100) };
    var lines: [3]T.Line = undefined;
    const n = T.wrap(&words, 5, 50, &lines);
    try testing.expectEqual(@as(u32, 3), n);
    try testing.expectEqual(@as(u32, 0), lines[0].first_word);
    try testing.expectEqual(@as(u32, 1), lines[0].word_count);
    try testing.expectEqual(@as(u32, 1), lines[1].first_word);
    try testing.expectEqual(@as(u32, 1), lines[1].word_count);
    try testing.expectEqual(@as(u32, 2), lines[2].first_word);
    try testing.expectEqual(@as(u32, 1), lines[2].word_count);
}

// ===========================================================================
// GlyphAtlas — additional edge cases
// ===========================================================================

test "GlyphAtlas: lookup on an empty atlas returns null" {
    var atlas = try T.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    const result = atlas.lookup(.{ .codepoint = 'A', .px = 16 });
    try testing.expect(result == null);
}

test "GlyphAtlas: insert zero-size glyph does not crash, returns zero-sized rect" {
    var atlas = try T.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    const rect = try atlas.insert(.{ .codepoint = 'Z', .px = 16 }, 0, 0, &.{});
    try testing.expectEqual(@as(u32, 0), rect.w);
    try testing.expectEqual(@as(u32, 0), rect.h);
    // A subsequent lookup must find the cached entry.
    const cached = atlas.lookup(.{ .codepoint = 'Z', .px = 16 });
    try testing.expect(cached != null);
    try testing.expectEqual(rect, cached.?);
}

test "GlyphAtlas: inserting the same key 3+ times always returns the same rect" {
    var atlas = try T.GlyphAtlas.init(testing.allocator, 64, 64);
    defer atlas.deinit();
    var buf: [8 * 8]u8 = [_]u8{0xFF} ** 64;
    const key = T.GlyphKey{ .codepoint = 'M', .px = 16 };
    const r1 = try atlas.insert(key, 8, 8, &buf);
    const r2 = try atlas.insert(key, 8, 8, &buf);
    const r3 = try atlas.insert(key, 8, 8, &buf);
    try testing.expectEqual(r1, r2);
    try testing.expectEqual(r1, r3);
    // Direct lookup must agree.
    const looked = atlas.lookup(key).?;
    try testing.expectEqual(r1, looked);
}

test "GlyphAtlas: multiple growth cycles preserve all prior entries" {
    // Start with a 4×4 atlas and insert 5×5 glyphs.
    //   • First glyph triggers growth 4→8 (glyph doesn't fit horizontally or vertically).
    //   • Second glyph triggers growth 8→16 (new shelf needed; still doesn't fit vertically).
    //   • Third glyph fits without further growth.
    // After two doublings the atlas must be ≥16×16 and all rects must survive re-lookup.
    var atlas = try T.GlyphAtlas.init(testing.allocator, 4, 4);
    defer atlas.deinit();
    var buf: [5 * 5]u8 = [_]u8{0xAB} ** 25;

    const r_a = try atlas.insert(.{ .codepoint = 'A', .px = 16 }, 5, 5, &buf);
    const r_b = try atlas.insert(.{ .codepoint = 'B', .px = 16 }, 5, 5, &buf);
    _ = try atlas.insert(.{ .codepoint = 'C', .px = 16 }, 5, 5, &buf);

    // Atlas must have grown at least to 16×16 after two doublings.
    try testing.expect(atlas.width >= 16 and atlas.height >= 16);

    // Re-lookup must return the rects that were returned at insertion time.
    const check_a = atlas.lookup(.{ .codepoint = 'A', .px = 16 }).?;
    const check_b = atlas.lookup(.{ .codepoint = 'B', .px = 16 }).?;
    try testing.expectEqual(r_a, check_a);
    try testing.expectEqual(r_b, check_b);

    // All returned rects must lie within the (grown) atlas bounds.
    try testing.expect(r_a.x + r_a.w <= atlas.width);
    try testing.expect(r_a.y + r_a.h <= atlas.height);
    try testing.expect(r_b.x + r_b.w <= atlas.width);
    try testing.expect(r_b.y + r_b.h <= atlas.height);
}
