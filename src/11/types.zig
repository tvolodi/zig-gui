//! Module 11 — complex script shaping and bidi
//!
//! M24-01: HarfBuzz shaping pipeline (RK0)
//! M24-02: Unicode Bidirectional Algorithm itemization (RK1)
//! M24-03: CJK atlas scaling + LRU eviction (RK2) — GlyphAtlas extensions in src/02/types.zig
//! M24-04: ShapedLine query API (RK3)

const std = @import("std");

pub const Direction = enum { ltr, rtl };

pub const Script = enum {
    latin,
    arabic,
    hebrew,
    devanagari,
    cjk,
    unknown,
};

pub const ShapedGlyph = struct {
    glyph_id: u32,   // font-internal glyph id (NOT a Unicode codepoint)
    cluster: u32,    // byte offset into the source run text (absolute, from paragraph start)
    x_advance: f32,  // horizontal advance in pixels
    x_offset: f32,   // horizontal offset from pen position
    y_offset: f32,   // vertical offset from baseline
};

pub const ShapedRun = struct {
    glyphs: []const ShapedGlyph,
    font_id: u16,
    direction: Direction,
    script: Script,
    allocator: std.mem.Allocator, // owns glyphs slice

    pub fn deinit(self: *ShapedRun) void {
        self.allocator.free(self.glyphs);
    }
};

pub const TextRun = struct {
    text: []const u8,    // the UTF-8 bytes of this run
    byte_start: u32,     // byte offset of this run's start in the paragraph string
    direction: Direction,
    script: Script,
    font_id: u16,
};

pub const ShapeError = error{
    HarfBuzzError,
    OutOfMemory,
};

// ---------------------------------------------------------------------------
// M24-04 (RK3) — ShapedLine query API
// ---------------------------------------------------------------------------

pub const ShapedLine = struct {
    runs: []const ShapedRun, // in visual order
    line_x: f32,              // left edge of the line box
    allocator: std.mem.Allocator,

    /// Pixel x of the caret at a given byte offset.
    /// Snaps to the nearest cluster boundary in the run containing that offset.
    pub fn caretX(self: *const ShapedLine, byte_offset: u32) f32 {
        var x = self.line_x;
        for (self.runs) |run| {
            if (run.direction == .ltr) {
                for (run.glyphs) |g| {
                    if (g.cluster >= byte_offset) return x;
                    x += g.x_advance;
                }
            } else {
                // RTL: compute run width, then find caret from right
                var run_width: f32 = 0;
                for (run.glyphs) |g| run_width += g.x_advance;
                var rx = x + run_width;
                for (run.glyphs) |g| {
                    if (g.cluster <= byte_offset) return rx;
                    rx -= g.x_advance;
                }
                x += run_width;
            }
        }
        return x;
    }

    /// Map a pixel x position to the nearest insertion byte offset.
    pub fn byteAtX(self: *const ShapedLine, x: f32) u32 {
        var cx = self.line_x;
        var best_offset: u32 = 0;
        var best_dist: f32 = std.math.floatMax(f32);
        for (self.runs) |run| {
            for (run.glyphs) |g| {
                const mid = cx + g.x_advance * 0.5;
                const dist = @abs(x - mid);
                if (dist < best_dist) {
                    best_dist = dist;
                    best_offset = g.cluster;
                }
                cx += g.x_advance;
            }
        }
        return best_offset;
    }

    /// Next caret stop from byte_offset in visual order.
    pub fn nextCaret(self: *const ShapedLine, byte_offset: u32) u32 {
        var found_current = false;
        for (self.runs) |run| {
            for (run.glyphs) |g| {
                if (found_current) return g.cluster;
                if (g.cluster == byte_offset) found_current = true;
            }
        }
        // Already at end — return one past the last cluster
        if (self.runs.len > 0) {
            const last_run = self.runs[self.runs.len - 1];
            if (last_run.glyphs.len > 0) {
                const last_g = last_run.glyphs[last_run.glyphs.len - 1];
                return last_g.cluster + 1;
            }
        }
        return byte_offset;
    }

    /// Previous caret stop from byte_offset in visual order.
    pub fn prevCaret(self: *const ShapedLine, byte_offset: u32) u32 {
        var prev: u32 = 0;
        for (self.runs) |run| {
            for (run.glyphs) |g| {
                if (g.cluster >= byte_offset) return prev;
                prev = g.cluster;
            }
        }
        return prev;
    }

    /// Selection rectangles for a byte range [start, end).
    /// Returns one rect per visual segment (may be multiple for bidi boundaries).
    /// Uses the Rect type from module 03 (x, y, w, h fields).
    /// Caller owns the returned slice.
    pub fn selectionRects(
        self: *const ShapedLine,
        start: u32,
        end: u32,
        line_height: f32,
        line_y: f32,
        gpa: std.mem.Allocator,
    ) ![]Rect {
        var rects: std.ArrayList(Rect) = .empty;
        var x = self.line_x;
        for (self.runs) |run| {
            var seg_x: f32 = x;
            var seg_w: f32 = 0;
            for (run.glyphs) |g| {
                if (g.cluster >= start and g.cluster < end) {
                    if (seg_w == 0) seg_x = x;
                    seg_w += g.x_advance;
                } else if (seg_w > 0) {
                    try rects.append(gpa, .{ .x = seg_x, .y = line_y, .w = seg_w, .h = line_height });
                    seg_w = 0;
                }
                x += g.x_advance;
            }
            if (seg_w > 0) {
                try rects.append(gpa, .{ .x = seg_x, .y = line_y, .w = seg_w, .h = line_height });
            }
        }
        return rects.toOwnedSlice(gpa);
    }
};

/// Rect type matching module 03 (x, y, w, h fields).
/// Defined here to avoid importing module 03 from module 11 (build-order constraint).
pub const Rect = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };
