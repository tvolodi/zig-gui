//! 02 — Text — types.zig
//!
//! Contract (INV-5.1). The PURE-LAYER struct shapes (Word, Line, TextExtent, FontMetrics)
//! and all public signatures are the contract — match them exactly. For Font / GlyphAtlas /
//! layoutParagraph the internal field layout is implementation-defined (they wrap a C library
//! and a bitmap); only their method signatures are the contract.
//!
//! Two trivial pure helpers (measureWidth, blockHeight) are implemented here to pin their
//! exact formulas. Everything else is stubbed — implement per spec.md; do not change
//! signatures.
//!
//! Module 02 is below module 03 in build order and may NOT import the element store
//! (INV-3.4). It defines its own TextExtent (distinct from module 03's Size — see spec.md).

const std = @import("std");

// ===========================================================================
// Pure layout layer — no font, no GPU. The core of acceptance_test.zig.
// ===========================================================================

pub const TextExtent = struct { w: f32 = 0, h: f32 = 0 };

/// An already-measured wrappable unit (one "word" between whitespace).
pub const Word = struct { width: f32 };

/// A wrapped line: a contiguous span of words and the line's total width (excluding the
/// trailing space).
pub const Line = struct {
    first_word: u32,
    word_count: u32,
    width: f32,
};

pub const FontMetrics = struct {
    /// Pixels above the baseline (positive).
    ascent: f32,
    /// Pixels below the baseline (positive magnitude).
    descent: f32,
    /// Extra leading between lines.
    line_gap: f32,
};

/// Total advance of a run of words separated by single spaces:
/// sum(word widths) + space_w * (count - 1). Zero words → 0.
pub fn measureWidth(words: []const Word, space_w: f32) f32 {
    if (words.len == 0) return 0;
    var total: f32 = 0;
    for (words) |w| total += w.width;
    total += space_w * @as(f32, @floatFromInt(words.len - 1));
    return total;
}

/// Total stacked height of `line_count` lines, each `line_height` tall.
pub fn blockHeight(line_count: u32, line_height: f32) f32 {
    return @as(f32, @floatFromInt(line_count)) * line_height;
}

/// Greedy word wrap at whitespace only. Fills `out_lines` (must be large enough for the
/// worst case of one word per line, i.e. words.len) and returns the number of lines written.
/// A single word wider than `max_width` occupies its own line and is allowed to overflow.
/// Zero words → 0 lines.
pub fn wrap(words: []const Word, space_w: f32, max_width: f32, out_lines: []Line) u32 {
    _ = words;
    _ = space_w;
    _ = max_width;
    _ = out_lines;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

// ===========================================================================
// Atlas — pure CPU packed grayscale bitmap. Packing is unit-tested with synthetic sizes.
// ===========================================================================

pub const AtlasRect = struct { x: u32, y: u32, w: u32, h: u32 };

/// R60 — Discriminant for bold/italic atlas cache slots.
pub const FontVariant = enum(u8) { regular, bold, italic };

pub const GlyphKey = struct { codepoint: u21, px: u16, variant: FontVariant = .regular };

/// Convert a font size in pixels to the integer key used in GlyphKey.
/// Rounds to the nearest integer to minimize rasterization artifacts.
pub fn fontSizePx(size: f32) u16 {
    _ = size;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}

pub const AtlasError = error{ OutOfMemory, GlyphTooLarge };

pub const GlyphAtlas = struct {
    width: u32 = 0,
    height: u32 = 0,
    // Internal packer state + bitmap are implementation-defined (not contract).
    _impl: *anyopaque = undefined,

    pub fn init(gpa: std.mem.Allocator, width: u32, height: u32) AtlasError!GlyphAtlas {
        _ = gpa;
        _ = width;
        _ = height;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *GlyphAtlas) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Return the rect for an already-inserted glyph, or null.
    pub fn lookup(self: *GlyphAtlas, key: GlyphKey) ?AtlasRect {
        _ = self;
        _ = key;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Pack a `w`x`h` grayscale glyph (`pixels.len == w*h`) and return its rect. If the
    /// glyph does not fit, the atlas grows (doubles) and existing entries stay valid.
    /// Re-inserting the same key returns the existing rect without repacking.
    pub fn insert(self: *GlyphAtlas, key: GlyphKey, w: u32, h: u32, pixels: []const u8) AtlasError!AtlasRect {
        _ = self;
        _ = key;
        _ = w;
        _ = h;
        _ = pixels;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// The atlas bitmap (width*height grayscale), for the renderer to upload.
    pub fn pixels(self: *GlyphAtlas) []const u8 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};

// ===========================================================================
// Font — stb_truetype-backed. Needs a real font; tested with a skip-if-absent test font.
// ===========================================================================

pub const GlyphRender = struct {
    advance: f32,
    bearing_x: f32,
    bearing_y: f32,
    width: u32,
    height: u32,
    /// Grayscale coverage, `width*height` bytes. Owned by the provided allocator/arena.
    bitmap: []const u8,
};

pub const FontError = error{ InvalidFont, OutOfMemory, GlyphNotFound };

pub const Font = struct {
    _impl: *anyopaque = undefined,
    /// R60 — variant this font face represents (set by FontFamily.init; default .regular).
    variant: FontVariant = .regular,

    pub fn initFromBytes(gpa: std.mem.Allocator, ttf: []const u8) FontError!Font {
        _ = gpa;
        _ = ttf;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *Font) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn metrics(self: *Font, px: f32) FontMetrics {
        _ = self;
        _ = px;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn advance(self: *Font, codepoint: u21, px: f32) f32 {
        _ = self;
        _ = codepoint;
        _ = px;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// `kern`-table kerning between two codepoints in pixels (often <= 0). 0 if absent or if
    /// the font only has GPOS kerning (see spec.md caveat).
    pub fn kerning(self: *Font, a: u21, b: u21, px: f32) f32 {
        _ = self;
        _ = a;
        _ = b;
        _ = px;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn rasterize(self: *Font, gpa: std.mem.Allocator, codepoint: u21, px: f32) FontError!GlyphRender {
        _ = self;
        _ = gpa;
        _ = codepoint;
        _ = px;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};

// ===========================================================================
// Tie-together — font-dependent paragraph layout.
// ===========================================================================

pub const PositionedGlyph = struct {
    codepoint: u21,
    /// Pixel rect on screen, relative to the paragraph origin (0,0 = top-left).
    dest_x: f32,
    dest_y: f32,
    dest_w: f32,
    dest_h: f32,
    /// Location of the glyph in the atlas.
    uv: AtlasRect,
};

pub const Paragraph = struct {
    glyphs: []PositionedGlyph,
    extent: TextExtent,
};

/// Shape `str` with `font` at `px`, wrap to `max_width` (use a large value for no wrap),
/// ensure each glyph is in `atlas`, and produce positioned glyphs + the paragraph extent.
/// Allocations (the glyph slice, any rasterized bitmaps) come from `gpa`.
pub fn layoutParagraph(
    gpa: std.mem.Allocator,
    font: *Font,
    atlas: *GlyphAtlas,
    str: []const u8,
    px: f32,
    max_width: f32,
) FontError!Paragraph {
    _ = gpa;
    _ = font;
    _ = atlas;
    _ = str;
    _ = px;
    _ = max_width;
    @compileError("not implemented — implement per spec.md; do not change this signature");
}
