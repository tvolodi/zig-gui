//! Module 11 unit tests — M24-02 bidi/itemize, M24-04 ShapedLine API.

const std = @import("std");
const types = @import("types.zig");
const bidi = @import("bidi.zig");

// ---------------------------------------------------------------------------
// Direction / Script enum tests
// ---------------------------------------------------------------------------

test "Direction enum has ltr and rtl" {
    const d: types.Direction = .ltr;
    try std.testing.expect(d == .ltr);
    const r: types.Direction = .rtl;
    try std.testing.expect(r == .rtl);
}

test "Script enum variants exist" {
    const s: types.Script = .arabic;
    try std.testing.expect(s == .arabic);
}

// ---------------------------------------------------------------------------
// Script detection tests
// ---------------------------------------------------------------------------

test "Script detection: Latin ASCII" {
    try std.testing.expect(bidi.detectScript('A') == .latin);
    try std.testing.expect(bidi.detectScript('z') == .latin);
    try std.testing.expect(bidi.detectScript('5') == .latin);
}

test "Script detection: Arabic" {
    try std.testing.expect(bidi.detectScript(0x0627) == .arabic); // alef
    try std.testing.expect(bidi.detectScript(0x0645) == .arabic); // meem
}

test "Script detection: Hebrew" {
    try std.testing.expect(bidi.detectScript(0x05D0) == .hebrew); // alef
    try std.testing.expect(bidi.detectScript(0x05D1) == .hebrew); // bet
}

test "Script detection: CJK" {
    try std.testing.expect(bidi.detectScript(0x4E2D) == .cjk); // 中
    try std.testing.expect(bidi.detectScript(0x6587) == .cjk); // 文
}

test "Script detection: Devanagari" {
    try std.testing.expect(bidi.detectScript(0x0905) == .devanagari); // a
}

// ---------------------------------------------------------------------------
// Bidi class tests
// ---------------------------------------------------------------------------

test "bidi class: digits are EN" {
    try std.testing.expect(bidi.bidiClass('0') == .EN);
    try std.testing.expect(bidi.bidiClass('5') == .EN);
    try std.testing.expect(bidi.bidiClass('9') == .EN);
}

test "bidi class: space is WS" {
    try std.testing.expect(bidi.bidiClass(' ') == .WS);
}

test "bidi class: newline is B" {
    try std.testing.expect(bidi.bidiClass('\n') == .B);
}

test "bidi class: Latin is L" {
    try std.testing.expect(bidi.bidiClass('A') == .L);
    try std.testing.expect(bidi.bidiClass('z') == .L);
}

test "bidi class: Arabic letter is AL" {
    try std.testing.expect(bidi.bidiClass(0x0627) == .AL); // alef
}

test "bidi class: Hebrew letter is R" {
    try std.testing.expect(bidi.bidiClass(0x05D0) == .R); // alef
}

// ---------------------------------------------------------------------------
// detectBaseDirection tests
// ---------------------------------------------------------------------------

test "detectBaseDirection: LTR for ASCII" {
    try std.testing.expect(bidi.detectBaseDirection("Hello world") == .ltr);
}

test "detectBaseDirection: LTR for CJK" {
    // CJK has bidi class L, so it's LTR
    const cjk = "\xe4\xb8\xad\xe6\x96\x87"; // 中文
    try std.testing.expect(bidi.detectBaseDirection(cjk) == .ltr);
}

test "detectBaseDirection: RTL for Arabic-leading" {
    // U+0645 = م (meem) — first strong character is Arabic (AL class → RTL)
    const arabic = "\xD9\x85\xD8\xB1\xD8\xAD\xD8\xA8\xD8\xA7"; // مرحبا
    try std.testing.expect(bidi.detectBaseDirection(arabic) == .rtl);
}

test "detectBaseDirection: RTL for Hebrew-leading" {
    const hebrew = "\xD7\x90"; // alef
    try std.testing.expect(bidi.detectBaseDirection(hebrew) == .rtl);
}

test "detectBaseDirection: LTR for empty string" {
    try std.testing.expect(bidi.detectBaseDirection("") == .ltr);
}

// ---------------------------------------------------------------------------
// itemize tests
// ---------------------------------------------------------------------------

test "itemize: pure LTR gives single run" {
    const allocator = std.testing.allocator;
    const items = try bidi.itemize(allocator, "Hello", .ltr);
    defer allocator.free(items);
    try std.testing.expect(items.len == 1);
    try std.testing.expect(items[0].direction == .ltr);
    try std.testing.expect(items[0].byte_start == 0);
    try std.testing.expect(items[0].byte_len == 5);
}

test "itemize: empty string returns empty slice" {
    const allocator = std.testing.allocator;
    const items = try bidi.itemize(allocator, "", .ltr);
    defer allocator.free(items);
    try std.testing.expect(items.len == 0);
}

test "itemize: pure RTL gives single RTL run" {
    const allocator = std.testing.allocator;
    const arabic = "\xD9\x85\xD8\xB1\xD8\xAD\xD8\xA8\xD8\xA7"; // مرحبا
    const items = try bidi.itemize(allocator, arabic, .rtl);
    defer allocator.free(items);
    try std.testing.expect(items.len >= 1);
    try std.testing.expect(items[0].direction == .rtl);
}

test "itemize: byte_start and byte_len are correct" {
    const allocator = std.testing.allocator;
    const items = try bidi.itemize(allocator, "Hi", .ltr);
    defer allocator.free(items);
    try std.testing.expect(items.len >= 1);
    try std.testing.expect(items[0].byte_start == 0);
    try std.testing.expect(items[0].byte_len == 2);
}

// ---------------------------------------------------------------------------
// reorderVisual tests
// ---------------------------------------------------------------------------

test "reorderVisual: single LTR run unchanged" {
    const allocator = std.testing.allocator;
    const items = [_]bidi.TextItem{.{
        .byte_start = 0, .byte_len = 5, .level = 0,
        .script = .latin, .font_id = 0, .direction = .ltr,
    }};
    const visual = try bidi.reorderVisual(allocator, &items);
    defer allocator.free(visual);
    try std.testing.expect(visual.len == 1);
    try std.testing.expect(visual[0].direction == .ltr);
}

test "reorderVisual: single RTL run unchanged in position (one element)" {
    const allocator = std.testing.allocator;
    const items = [_]bidi.TextItem{.{
        .byte_start = 0, .byte_len = 10, .level = 1,
        .script = .arabic, .font_id = 0, .direction = .rtl,
    }};
    const visual = try bidi.reorderVisual(allocator, &items);
    defer allocator.free(visual);
    try std.testing.expect(visual.len == 1);
    try std.testing.expect(visual[0].direction == .rtl);
}

test "reorderVisual: RTL run between two LTR runs gets reversed" {
    const allocator = std.testing.allocator;
    const items = [_]bidi.TextItem{
        .{ .byte_start = 0,  .byte_len = 5, .level = 0, .script = .latin,  .font_id = 0, .direction = .ltr },
        .{ .byte_start = 5,  .byte_len = 5, .level = 1, .script = .arabic, .font_id = 0, .direction = .rtl },
        .{ .byte_start = 10, .byte_len = 5, .level = 0, .script = .latin,  .font_id = 0, .direction = .ltr },
    };
    const visual = try bidi.reorderVisual(allocator, &items);
    defer allocator.free(visual);
    try std.testing.expect(visual.len == 3);
    // The RTL run (level 1) stays in place since only it is reversed by L2.
    // With 3 items and only level-1 item in the middle, it reverses a range of 1 — no change.
    // The overall order for [L, R, L] at levels [0,1,0] is: R reverses itself (noop), so [L, R, L].
    try std.testing.expect(visual[1].direction == .rtl);
}

test "reorderVisual: two RTL runs reverse" {
    const allocator = std.testing.allocator;
    const items = [_]bidi.TextItem{
        .{ .byte_start = 0, .byte_len = 5, .level = 1, .script = .arabic, .font_id = 0, .direction = .rtl },
        .{ .byte_start = 5, .byte_len = 5, .level = 1, .script = .arabic, .font_id = 0, .direction = .rtl },
    };
    const visual = try bidi.reorderVisual(allocator, &items);
    defer allocator.free(visual);
    try std.testing.expect(visual.len == 2);
    // Two level-1 items: L2 reverses the entire sequence
    try std.testing.expect(visual[0].byte_start == 5);
    try std.testing.expect(visual[1].byte_start == 0);
}

test "reorderVisual: empty input" {
    const allocator = std.testing.allocator;
    const items = [_]bidi.TextItem{};
    const visual = try bidi.reorderVisual(allocator, &items);
    defer allocator.free(visual);
    try std.testing.expect(visual.len == 0);
}

// ---------------------------------------------------------------------------
// ShapedLine query API tests (M24-04)
// ---------------------------------------------------------------------------

test "ShapedLine caretX: single LTR run at x=0" {
    const allocator = std.testing.allocator;
    var glyphs = [_]types.ShapedGlyph{
        .{ .glyph_id = 72,  .cluster = 0, .x_advance = 10.0, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = 101, .cluster = 1, .x_advance = 8.0,  .x_offset = 0, .y_offset = 0 },
    };
    const run = types.ShapedRun{
        .glyphs = &glyphs,
        .font_id = 0,
        .direction = .ltr,
        .script = .latin,
        .allocator = allocator,
    };
    const runs = [_]types.ShapedRun{run};
    const line = types.ShapedLine{ .runs = &runs, .line_x = 0.0, .allocator = allocator };

    // caret at byte 0 should be at x=0 (before first glyph)
    try std.testing.expectApproxEqAbs(@as(f32, 0.0), line.caretX(0), 0.01);
    // caret at byte 1 (after first glyph) should be at x=10
    try std.testing.expectApproxEqAbs(@as(f32, 10.0), line.caretX(1), 0.01);
}

test "ShapedLine caretX: respects line_x offset" {
    const allocator = std.testing.allocator;
    var glyphs = [_]types.ShapedGlyph{
        .{ .glyph_id = 65, .cluster = 0, .x_advance = 12.0, .x_offset = 0, .y_offset = 0 },
    };
    const run = types.ShapedRun{
        .glyphs = &glyphs,
        .font_id = 0,
        .direction = .ltr,
        .script = .latin,
        .allocator = allocator,
    };
    const runs = [_]types.ShapedRun{run};
    const line = types.ShapedLine{ .runs = &runs, .line_x = 50.0, .allocator = allocator };

    // caret at byte 0 should be at line_x = 50
    try std.testing.expectApproxEqAbs(@as(f32, 50.0), line.caretX(0), 0.01);
}

test "ShapedLine byteAtX: nearest cluster" {
    const allocator = std.testing.allocator;
    var glyphs = [_]types.ShapedGlyph{
        .{ .glyph_id = 72,  .cluster = 0, .x_advance = 10.0, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = 101, .cluster = 1, .x_advance = 10.0, .x_offset = 0, .y_offset = 0 },
    };
    const run = types.ShapedRun{
        .glyphs = &glyphs, .font_id = 0, .direction = .ltr, .script = .latin, .allocator = allocator,
    };
    const runs = [_]types.ShapedRun{run};
    const line = types.ShapedLine{ .runs = &runs, .line_x = 0.0, .allocator = allocator };
    // x=3 is closer to glyph 0 (midpoint at 5) — should return cluster 0
    try std.testing.expect(line.byteAtX(3.0) == 0);
    // x=12 is closer to glyph 1 (midpoint at 15) — should return cluster 1
    try std.testing.expect(line.byteAtX(12.0) == 1);
}

test "ShapedLine nextCaret: advances to next cluster" {
    const allocator = std.testing.allocator;
    var glyphs = [_]types.ShapedGlyph{
        .{ .glyph_id = 65, .cluster = 0, .x_advance = 8.0, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = 66, .cluster = 1, .x_advance = 8.0, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = 67, .cluster = 2, .x_advance = 8.0, .x_offset = 0, .y_offset = 0 },
    };
    const run = types.ShapedRun{
        .glyphs = &glyphs, .font_id = 0, .direction = .ltr, .script = .latin, .allocator = allocator,
    };
    const runs = [_]types.ShapedRun{run};
    const line = types.ShapedLine{ .runs = &runs, .line_x = 0.0, .allocator = allocator };

    try std.testing.expect(line.nextCaret(0) == 1);
    try std.testing.expect(line.nextCaret(1) == 2);
}

test "ShapedLine prevCaret: moves to previous cluster" {
    const allocator = std.testing.allocator;
    var glyphs = [_]types.ShapedGlyph{
        .{ .glyph_id = 65, .cluster = 0, .x_advance = 8.0, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = 66, .cluster = 1, .x_advance = 8.0, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = 67, .cluster = 2, .x_advance = 8.0, .x_offset = 0, .y_offset = 0 },
    };
    const run = types.ShapedRun{
        .glyphs = &glyphs, .font_id = 0, .direction = .ltr, .script = .latin, .allocator = allocator,
    };
    const runs = [_]types.ShapedRun{run};
    const line = types.ShapedLine{ .runs = &runs, .line_x = 0.0, .allocator = allocator };

    try std.testing.expect(line.prevCaret(2) == 1);
    try std.testing.expect(line.prevCaret(1) == 0);
    try std.testing.expect(line.prevCaret(0) == 0);
}

test "ShapedLine selectionRects: full run selected" {
    const allocator = std.testing.allocator;
    var glyphs = [_]types.ShapedGlyph{
        .{ .glyph_id = 65, .cluster = 0, .x_advance = 10.0, .x_offset = 0, .y_offset = 0 },
        .{ .glyph_id = 66, .cluster = 1, .x_advance = 10.0, .x_offset = 0, .y_offset = 0 },
    };
    const run = types.ShapedRun{
        .glyphs = &glyphs, .font_id = 0, .direction = .ltr, .script = .latin, .allocator = allocator,
    };
    const runs = [_]types.ShapedRun{run};
    const line = types.ShapedLine{ .runs = &runs, .line_x = 0.0, .allocator = allocator };
    const rects = try line.selectionRects(0, 2, 16.0, 0.0, allocator);
    defer allocator.free(rects);
    try std.testing.expect(rects.len >= 1);
    // Total width should be 20 (two glyphs at 10px each)
    var total_w: f32 = 0;
    for (rects) |r| total_w += r.w;
    try std.testing.expectApproxEqAbs(@as(f32, 20.0), total_w, 0.01);
}
