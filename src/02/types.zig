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
const c = @cImport({
    @cInclude("stb_truetype.h");
});

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
    if (words.len == 0) return 0;
    var line_count: u32 = 0;
    var start: u32 = 0;
    var cur_w: f32 = words[0].width;
    var i: u32 = 1;
    while (i < words.len) : (i += 1) {
        const next_w = cur_w + space_w + words[i].width;
        if (next_w > max_width) {
            out_lines[line_count] = .{ .first_word = start, .word_count = i - start, .width = cur_w };
            line_count += 1;
            start = i;
            cur_w = words[i].width;
        } else {
            cur_w = next_w;
        }
    }
    out_lines[line_count] = .{ .first_word = start, .word_count = @as(u32, @intCast(words.len)) - start, .width = cur_w };
    return line_count + 1;
}

// ===========================================================================
// Atlas — pure CPU packed grayscale bitmap. Packing is unit-tested with synthetic sizes.
// ===========================================================================

pub const AtlasRect = struct { x: u32, y: u32, w: u32, h: u32 };

/// R60 — Discriminant for bold/italic atlas cache slots.
pub const FontVariant = enum(u8) { regular, bold, italic };

/// R64 — Rendered when no font in the fallback chain covers a codepoint.
pub const REPLACEMENT_CODEPOINT: u21 = 0xFFFD;

pub const GlyphKey = struct {
    codepoint: u21,
    px: u16,
    variant: FontVariant = .regular,
    /// R64: 0 = primary font, 1–4 = fallback index + 1.
    font_id: u8 = 0,
};

/// Convert a font size in pixels to the integer key used in GlyphKey.
/// Rounds to the nearest integer to minimize rasterization artifacts.
pub fn fontSizePx(size: f32) u16 {
    return @intCast(@as(u32, @intFromFloat(@round(size))));
}

pub const AtlasError = error{ OutOfMemory, GlyphTooLarge };

const AtlasImpl = struct {
    gpa: std.mem.Allocator,
    bitmap: []u8,
    width: u32,
    height: u32,
    shelf_x: u32,
    shelf_y: u32,
    shelf_row_h: u32,
    cache: std.AutoHashMap(GlyphKey, AtlasRect),
};

/// R44 — Ellipsis glyph metrics (advance width + atlas key).
pub const EllipsisMetrics = struct {
    advance: f32,
    glyph_id: u16,
};

const EllipsisCacheEntry = struct { font_size: u32, metrics: EllipsisMetrics };

pub const GlyphAtlas = struct {
    width: u32 = 0,
    height: u32 = 0,
    generation: u32 = 0,
    // Internal packer state + bitmap are implementation-defined (not contract).
    _impl: *anyopaque = undefined,
    /// R44: Cached ellipsis metrics per font size (max 8 slots).
    ellipsis_cache: [8]?EllipsisCacheEntry = [_]?EllipsisCacheEntry{null} ** 8,

    pub fn init(gpa: std.mem.Allocator, width: u32, height: u32) AtlasError!GlyphAtlas {
        const impl = try gpa.create(AtlasImpl);
        errdefer gpa.destroy(impl);
        const bitmap = try gpa.alloc(u8, width * height);
        @memset(bitmap, 0);
        impl.* = .{
            .gpa = gpa,
            .bitmap = bitmap,
            .width = width,
            .height = height,
            .shelf_x = 0,
            .shelf_y = 0,
            .shelf_row_h = 0,
            .cache = std.AutoHashMap(GlyphKey, AtlasRect).init(gpa),
        };
        return GlyphAtlas{
            .width = width,
            .height = height,
            ._impl = @ptrCast(impl),
        };
    }

    pub fn deinit(self: *GlyphAtlas) void {
        const impl: *AtlasImpl = @ptrCast(@alignCast(self._impl));
        const gpa = impl.gpa;
        gpa.free(impl.bitmap);
        impl.cache.deinit();
        gpa.destroy(impl);
    }

    /// Return the rect for an already-inserted glyph, or null.
    pub fn lookup(self: *GlyphAtlas, key: GlyphKey) ?AtlasRect {
        const impl: *AtlasImpl = @ptrCast(@alignCast(self._impl));
        return impl.cache.get(key);
    }

    /// Pack a `w`x`h` grayscale glyph (`pixels.len == w*h`) and return its rect. If the
    /// glyph does not fit, the atlas grows (doubles) and existing entries stay valid.
    /// Re-inserting the same key returns the existing rect without repacking.
    pub fn insert(self: *GlyphAtlas, key: GlyphKey, w: u32, h: u32, glyph_data: []const u8) AtlasError!AtlasRect {
        const impl: *AtlasImpl = @ptrCast(@alignCast(self._impl));

        // Cache hit: return existing rect without repacking.
        if (impl.cache.get(key)) |rect| return rect;

        // Start a new shelf row if the glyph does not fit horizontally.
        if (impl.shelf_x + w > impl.width) {
            impl.shelf_y += impl.shelf_row_h;
            impl.shelf_x = 0;
            impl.shelf_row_h = 0;
        }

        // Grow the atlas (double both dimensions) while the glyph does not fit vertically.
        while (impl.shelf_y + h > impl.height) {
            const new_w = impl.width * 2;
            const new_h = impl.height * 2;
            const new_bitmap = try impl.gpa.alloc(u8, new_w * new_h);
            @memset(new_bitmap, 0);
            var row: u32 = 0;
            while (row < impl.height) : (row += 1) {
                const src = impl.bitmap[row * impl.width ..][0..impl.width];
                const dst = new_bitmap[row * new_w ..][0..impl.width];
                @memcpy(dst, src);
            }
            impl.gpa.free(impl.bitmap);
            impl.bitmap = new_bitmap;
            impl.width = new_w;
            impl.height = new_h;
            self.width = new_w;
            self.height = new_h;
            // After width doubled, re-check whether a new row is still needed.
            if (impl.shelf_x + w > impl.width) {
                impl.shelf_y += impl.shelf_row_h;
                impl.shelf_x = 0;
                impl.shelf_row_h = 0;
            }
        }

        // Guard against a glyph too large to ever fit.
        if (impl.shelf_x + w > impl.width or impl.shelf_y + h > impl.height) {
            return AtlasError.GlyphTooLarge;
        }

        const rect = AtlasRect{ .x = impl.shelf_x, .y = impl.shelf_y, .w = w, .h = h };

        // Blit glyph pixels into atlas bitmap row by row.
        var blit_row: u32 = 0;
        while (blit_row < h) : (blit_row += 1) {
            const src = glyph_data[blit_row * w ..][0..w];
            const dst = impl.bitmap[(impl.shelf_y + blit_row) * impl.width + impl.shelf_x ..][0..w];
            @memcpy(dst, src);
        }

        // Advance shelf cursor and update row height.
        impl.shelf_x += w;
        if (h > impl.shelf_row_h) impl.shelf_row_h = h;

        // Cache and return; bump generation so renderers know the bitmap changed.
        try impl.cache.put(key, rect);
        self.generation +%= 1;
        return rect;
    }

    /// The atlas bitmap (width*height grayscale), for the renderer to upload.
    pub fn pixels(self: *GlyphAtlas) []const u8 {
        const impl: *AtlasImpl = @ptrCast(@alignCast(self._impl));
        return impl.bitmap;
    }

    // -----------------------------------------------------------------------
    // R44 — Ellipsis metrics (cached per font size)
    // -----------------------------------------------------------------------

    /// Return ellipsis metrics for `font_size`, rasterizing "…" (U+2026) if not cached.
    pub fn ellipsisMetrics(
        self: *GlyphAtlas,
        font: *Font,
        font_size: f32,
    ) error{OutOfMemory}!EllipsisMetrics {
        const fs_key: u32 = @intFromFloat(@round(font_size));

        // Check cache first.
        for (self.ellipsis_cache) |entry| {
            if (entry) |e| {
                if (e.font_size == fs_key) return e.metrics;
            }
        }

        // Rasterize "…" (U+2026) into the atlas.
        const ellipsis_cp: u21 = 0x2026;
        const px_u16: u16 = @intCast(fs_key);
        const key = GlyphKey{ .codepoint = ellipsis_cp, .px = px_u16, .variant = font.variant };

        // Try to look up first (may already be in atlas from a prior rasterize call).
        const uv = if (self.lookup(key)) |existing| existing else blk: {
            const render = font.rasterize(std.heap.page_allocator, ellipsis_cp, font_size) catch {
                const metrics = EllipsisMetrics{ .advance = 0, .glyph_id = 0 };
                self.storeEllipsisCache(fs_key, metrics);
                return metrics;
            };
            defer std.heap.page_allocator.free(render.bitmap);
            const rect = self.insert(key, render.width, render.height, render.bitmap) catch {
                // Atlas full or glyph too large — return zero advance as fallback.
                const metrics = EllipsisMetrics{ .advance = 0, .glyph_id = 0 };
                self.storeEllipsisCache(fs_key, metrics);
                return metrics;
            };
            break :blk rect;
        };

        const advance = @as(f32, @floatFromInt(uv.w));
        const metrics = EllipsisMetrics{ .advance = advance, .glyph_id = 0 };
        self.storeEllipsisCache(fs_key, metrics);
        return metrics;
    }

    fn storeEllipsisCache(self: *GlyphAtlas, fs_key: u32, metrics: EllipsisMetrics) void {
        for (&self.ellipsis_cache) |*slot| {
            if (slot.* == null) {
                slot.* = .{ .font_size = fs_key, .metrics = metrics };
                return;
            }
        }
        // All slots full — overwrite last (simple eviction).
        self.ellipsis_cache[7] = .{ .font_size = fs_key, .metrics = metrics };
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

/// M13-03 RD2 — Subpixel glyph bitmap with RGB-packed subpixel coverage.
pub const SubpixelBitmap = struct {
    width: u32,
    height: u32,
    /// RGBRGBRGB... packed bytes. width * height * 3 bytes.
    rgb: []u8,
};

pub const FontError = error{ InvalidFont, OutOfMemory, GlyphNotFound };

const FontImpl = struct {
    gpa: std.mem.Allocator,
    info: c.stbtt_fontinfo,
    ttf_data: []u8,
};

pub const Font = struct {
    _impl: *anyopaque = undefined,
    /// R60 — variant this font face represents (set by FontFamily.init; default .regular).
    variant: FontVariant = .regular,
    /// True only when _impl points to a valid FontImpl (set by initFromBytes).
    /// Stub fonts created via .{ ._impl = undefined } leave this false.
    _valid: bool = false,

    pub fn initFromBytes(gpa: std.mem.Allocator, ttf: []const u8) FontError!Font {
        const impl = try gpa.create(FontImpl);
        errdefer gpa.destroy(impl);
        impl.gpa = gpa;
        impl.ttf_data = try gpa.dupe(u8, ttf);
        errdefer gpa.free(impl.ttf_data);
        if (c.stbtt_InitFont(&impl.info, impl.ttf_data.ptr, 0) == 0) {
            return FontError.InvalidFont;
        }
        return Font{ ._impl = impl, ._valid = true };
    }

    pub fn deinit(self: *Font) void {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        impl.gpa.free(impl.ttf_data);
        impl.gpa.destroy(impl);
    }

    pub fn metrics(self: *Font, px: f32) FontMetrics {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        var ascent: c_int = 0;
        var descent: c_int = 0;
        var line_gap: c_int = 0;
        c.stbtt_GetFontVMetrics(&impl.info, &ascent, &descent, &line_gap);
        const scale = c.stbtt_ScaleForPixelHeight(&impl.info, px);
        return .{
            .ascent = @as(f32, @floatFromInt(ascent)) * scale,
            .descent = -@as(f32, @floatFromInt(descent)) * scale,
            .line_gap = @as(f32, @floatFromInt(line_gap)) * scale,
        };
    }

    pub fn advance(self: *Font, codepoint: u21, px: f32) f32 {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        var adv: c_int = 0;
        var lsb: c_int = 0;
        c.stbtt_GetCodepointHMetrics(&impl.info, @intCast(codepoint), &adv, &lsb);
        const scale = c.stbtt_ScaleForPixelHeight(&impl.info, px);
        return @as(f32, @floatFromInt(adv)) * scale;
    }

    /// Return the bitmap bearing offsets (ix0, iy0) for a codepoint at the given pixel size.
    /// Uses stbtt_GetCodepointBitmapBox — does NOT rasterize the glyph (cheap).
    /// bx = horizontal offset from pen to left edge of bitmap (ix0).
    /// by = vertical offset from baseline to top edge of bitmap (iy0, typically negative).
    pub fn glyphBearing(self: *Font, codepoint: u21, px: f32) struct { bx: f32, by: f32 } {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        const scale = c.stbtt_ScaleForPixelHeight(&impl.info, px);
        var ix0: c_int = 0;
        var iy0: c_int = 0;
        var ix1: c_int = 0;
        var iy1: c_int = 0;
        c.stbtt_GetCodepointBitmapBox(&impl.info, @intCast(codepoint), 0, scale, &ix0, &iy0, &ix1, &iy1);
        return .{ .bx = @as(f32, @floatFromInt(ix0)), .by = @as(f32, @floatFromInt(iy0)) };
    }

    /// `kern`-table kerning between two codepoints in pixels (often <= 0). 0 if absent or if
    /// the font only has GPOS kerning (see spec.md caveat).
    pub fn kerning(self: *Font, a: u21, b: u21, px: f32) f32 {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        const kern = c.stbtt_GetCodepointKernAdvance(&impl.info, @intCast(a), @intCast(b));
        const scale = c.stbtt_ScaleForPixelHeight(&impl.info, px);
        return @as(f32, @floatFromInt(kern)) * scale;
    }

    pub fn rasterize(self: *Font, gpa: std.mem.Allocator, codepoint: u21, px: f32) FontError!GlyphRender {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        const scale = c.stbtt_ScaleForPixelHeight(&impl.info, px);
        var w: c_int = 0;
        var h: c_int = 0;
        var xoff: c_int = 0;
        var yoff: c_int = 0;
        const raw = c.stbtt_GetCodepointBitmap(&impl.info, 0, scale, @intCast(codepoint), &w, &h, &xoff, &yoff);
        if (raw == null) return FontError.GlyphNotFound;
        defer c.stbtt_FreeBitmap(raw, null);
        const len: usize = @intCast(w * h);
        const bitmap = try gpa.alloc(u8, len);
        @memcpy(bitmap, raw[0..len]);
        var adv: c_int = 0;
        var lsb: c_int = 0;
        c.stbtt_GetCodepointHMetrics(&impl.info, @intCast(codepoint), &adv, &lsb);
        return GlyphRender{
            .advance = @as(f32, @floatFromInt(adv)) * scale,
            .bearing_x = @as(f32, @floatFromInt(xoff)),
            .bearing_y = @as(f32, @floatFromInt(yoff)),
            .width = @intCast(w),
            .height = @intCast(h),
            .bitmap = bitmap,
        };
    }

    /// M13-03 RD2 — Rasterize a glyph at 3× horizontal resolution for subpixel rendering.
    /// Returns the RGB-packed bitmap where each output pixel's R,G,B channels contain
    /// the subpixel coverage from the 3× wider rasterization.
    /// Caller owns the returned `SubpixelBitmap.rgb` (allocated with `gpa`).
    pub fn rasterizeSubpixel(self: *Font, gpa: std.mem.Allocator, codepoint: u21, px: f32) FontError!SubpixelBitmap {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        const scale = c.stbtt_ScaleForPixelHeight(&impl.info, px);
        // Rasterize at 3× horizontal resolution using subpixel-aware bitmap function.
        const scale_x = scale * 3.0;
        const scale_y = scale;
        const glyph_index = c.stbtt_FindGlyphIndex(&impl.info, @intCast(codepoint));
        if (glyph_index == 0) return FontError.GlyphNotFound;

        var raw_w: c_int = 0;
        var raw_h: c_int = 0;
        var raw_xoff: c_int = 0;
        var raw_yoff: c_int = 0;
        const raw = c.stbtt_GetGlyphBitmapSubpixel(&impl.info, scale_x, scale_y, 0, 0, glyph_index, &raw_w, &raw_h, &raw_xoff, &raw_yoff);
        if (raw == null) return FontError.GlyphNotFound;
        defer c.stbtt_FreeBitmap(raw, null);

        // The rasterized bitmap is 3× wider than the normal glyph.
        // Pack every 3 adjacent pixels into one RGB triplet.
        const out_w: u32 = @intCast(@divTrunc(raw_w + 2, 3)); // ceiling division
        const out_h: u32 = @intCast(raw_h);
        const out_len: usize = @as(usize, out_w) * out_h * 3;
        const rgb = try gpa.alloc(u8, out_len);

        var y: u32 = 0;
        while (y < out_h) : (y += 1) {
            var x: u32 = 0;
            while (x < out_w) : (x += 1) {
                const src_idx: usize = @as(usize, y) * @as(usize, @intCast(raw_w)) + @as(usize, x) * 3;
                const dst_idx: usize = (@as(usize, y) * out_w + x) * 3;
                // R = pixel[3*x+0], G = pixel[3*x+1], B = pixel[3*x+2]
                rgb[dst_idx + 0] = if (x * 3 + 0 < @as(u32, @intCast(raw_w))) raw[src_idx + 0] else 0;
                rgb[dst_idx + 1] = if (x * 3 + 1 < @as(u32, @intCast(raw_w))) raw[src_idx + 1] else 0;
                rgb[dst_idx + 2] = if (x * 3 + 2 < @as(u32, @intCast(raw_w))) raw[src_idx + 2] else 0;
            }
        }

        return SubpixelBitmap{
            .width = out_w,
            .height = out_h,
            .rgb = rgb,
        };
    }

    /// R64 — Return the stb_truetype glyph index for `codepoint`, or 0 if absent.
    pub fn glyphIndex(self: *Font, codepoint: u21) i32 {
        const impl: *FontImpl = @ptrCast(@alignCast(self._impl));
        return c.stbtt_FindGlyphIndex(&impl.info, @intCast(codepoint));
    }
};

// ===========================================================================
// R64 — FontFamily: three-slot font container + fallback chain.
// Moved here from src/app/font_family.zig so that layoutParagraphEx can use
// it without violating the upward-import prohibition (INV-3.4).
// src/app/font_family.zig re-exports this type.
// ===========================================================================

pub const FontFamily = struct {
    regular: Font,
    bold: ?Font,
    italic: ?Font,
    /// Ordered fallback fonts tried when the primary face lacks a codepoint. Max 4.
    fallbacks: [4]?Font = .{null} ** 4,
    fallback_count: u8 = 0,
    gpa: std.mem.Allocator,

    /// Load up to three TTF faces. `regular_ttf` is required; bold/italic are optional.
    pub fn init(
        gpa: std.mem.Allocator,
        regular_ttf: []const u8,
        bold_ttf: ?[]const u8,
        italic_ttf: ?[]const u8,
    ) FontError!FontFamily {
        var regular = try Font.initFromBytes(gpa, regular_ttf);
        regular.variant = .regular;
        errdefer regular.deinit();

        var bold: ?Font = null;
        if (bold_ttf) |b| {
            var bf = try Font.initFromBytes(gpa, b);
            bf.variant = .bold;
            bold = bf;
        }
        errdefer if (bold) |*b| b.deinit();

        var italic: ?Font = null;
        if (italic_ttf) |it| {
            var itf = try Font.initFromBytes(gpa, it);
            itf.variant = .italic;
            italic = itf;
        }

        return FontFamily{
            .regular = regular,
            .bold = bold,
            .italic = italic,
            .gpa = gpa,
        };
    }

    pub fn deinit(self: *FontFamily) void {
        self.regular.deinit();
        if (self.bold) |*b| b.deinit();
        if (self.italic) |*it| it.deinit();
        var i: u8 = 0;
        while (i < self.fallback_count) : (i += 1) {
            if (self.fallbacks[i]) |*fb| fb.deinit();
        }
    }

    /// Return a pointer to the best-matching font face (bold → italic → regular).
    /// Variant field on the returned font is already set correctly from init.
    pub fn face(self: *FontFamily, bold: bool, italic: bool) *Font {
        if (bold) {
            if (self.bold != null) return &self.bold.?;
            return &self.regular;
        }
        if (italic) {
            if (self.italic != null) return &self.italic.?;
            return &self.regular;
        }
        return &self.regular;
    }

    /// Add a fallback font. TTF bytes are copied into the family's allocator.
    /// Returns error.TooManyFallbacks if the 4-fallback limit is reached.
    pub fn addFallback(self: *FontFamily, ttf: []const u8) !void {
        if (self.fallback_count >= 4) return error.TooManyFallbacks;
        var fb = try Font.initFromBytes(self.gpa, ttf);
        fb.variant = .regular;
        self.fallbacks[self.fallback_count] = fb;
        self.fallback_count += 1;
    }

    /// Return the best Font for `codepoint` starting from `primary`, then trying fallbacks.
    /// Returns null if no font in the chain covers the codepoint.
    pub fn fontForCodepoint(self: *FontFamily, primary: *Font, codepoint: u21) ?*Font {
        if (primary.glyphIndex(codepoint) != 0) return primary;
        var i: u8 = 0;
        while (i < self.fallback_count) : (i += 1) {
            if (self.fallbacks[i] != null) {
                if (self.fallbacks[i].?.glyphIndex(codepoint) != 0) {
                    return &self.fallbacks[i].?;
                }
            }
        }
        return null;
    }

    /// Return font_id: 0 for primary, 1+index for the fallback that covers the codepoint.
    pub fn fontIdForCodepoint(self: *FontFamily, primary: *Font, codepoint: u21) u8 {
        if (primary.glyphIndex(codepoint) != 0) return 0;
        var i: u8 = 0;
        while (i < self.fallback_count) : (i += 1) {
            if (self.fallbacks[i] != null) {
                if (self.fallbacks[i].?.glyphIndex(codepoint) != 0) {
                    return i + 1;
                }
            }
        }
        return 0;
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
    /// R62 — byte offset of this glyph's codepoint in the source string.
    byte_offset: u32,
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
    return layoutParagraphEx(gpa, font, atlas, str, px, max_width, null);
}

/// R64 — Like `layoutParagraph` but with font-family fallback support.
/// When `family` is non-null, each codepoint is resolved to the best font in the chain.
/// Codepoints with no coverage render as U+FFFD (REPLACEMENT CHARACTER); if even that
/// is absent from the chain the glyph is silently skipped.
pub fn layoutParagraphEx(
    gpa: std.mem.Allocator,
    font: *Font,
    atlas: *GlyphAtlas,
    str: []const u8,
    px: f32,
    max_width: f32,
    family: ?*FontFamily,
) FontError!Paragraph {
    const fm = font.metrics(px);
    const line_height = fm.ascent + fm.descent + fm.line_gap;
    const space_w = font.advance(' ', px);
    const px_u16: u16 = fontSizePx(px);

    // Tokenize into words (non-whitespace runs), measuring each word's width.
    var words: std.ArrayList(Word) = .empty;
    defer words.deinit(gpa);

    // Also remember the codepoints for each word so we can iterate later.
    // We store them as (start, len) into a flat codepoints array.
    const WordSpan = struct { start: u32, len: u32 };
    var word_spans: std.ArrayList(WordSpan) = .empty;
    defer word_spans.deinit(gpa);

    var codepoints_buf: std.ArrayList(u21) = .empty;
    defer codepoints_buf.deinit(gpa);

    // R62: parallel byte-offset buffer for selection hit-testing.
    var byte_offsets_buf: std.ArrayList(u32) = .empty;
    defer byte_offsets_buf.deinit(gpa);

    {
        var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
        var in_word = false;
        var word_start: u32 = 0;
        var word_w: f32 = 0;
        var prev_cp: ?u21 = null;

        while (true) {
            const byte_off = @as(u32, @intCast(iter.i));
            const cp = iter.nextCodepoint() orelse break;
            const is_ws = cp == ' ' or cp == '\t' or cp == '\n' or cp == '\r';
            if (!is_ws) {
                if (!in_word) {
                    // Start a new word.
                    in_word = true;
                    word_start = @intCast(codepoints_buf.items.len);
                    word_w = 0;
                    prev_cp = null;
                }
                // Add kerning from previous codepoint in this word.
                if (prev_cp) |pcp| {
                    word_w += font.kerning(pcp, cp, px);
                }
                word_w += font.advance(cp, px);
                try codepoints_buf.append(gpa, cp);
                try byte_offsets_buf.append(gpa, byte_off);
                prev_cp = cp;
            } else {
                if (in_word) {
                    // End word.
                    in_word = false;
                    try words.append(gpa, .{ .width = word_w });
                    try word_spans.append(gpa, .{
                        .start = word_start,
                        .len = @intCast(codepoints_buf.items.len - word_start),
                    });
                }
            }
        }
        if (in_word) {
            try words.append(gpa, .{ .width = word_w });
            try word_spans.append(gpa, .{
                .start = word_start,
                .len = @intCast(codepoints_buf.items.len - word_start),
            });
        }
    }

    if (words.items.len == 0) {
        return Paragraph{
            .glyphs = try gpa.alloc(PositionedGlyph, 0),
            .extent = .{ .w = 0, .h = 0 },
        };
    }

    // Wrap into lines.
    var lines_buf = try gpa.alloc(Line, words.items.len);
    defer gpa.free(lines_buf);
    const line_count = wrap(words.items, space_w, max_width, lines_buf);
    const lines = lines_buf[0..line_count];

    // Build positioned glyphs.
    var glyphs: std.ArrayList(PositionedGlyph) = .empty;
    errdefer glyphs.deinit(gpa);

    var pen_y: f32 = fm.ascent; // baseline y for first line
    var max_line_w: f32 = 0;

    for (lines) |line| {
        var pen_x: f32 = 0;
        const line_words = words.items[line.first_word .. line.first_word + line.word_count];
        if (line.width > max_line_w) max_line_w = line.width;

        for (line_words, 0..) |_, wi| {
            const word_idx = line.first_word + wi;
            const span = word_spans.items[word_idx];
            const cps = codepoints_buf.items[span.start .. span.start + span.len];

            for (cps, 0..) |cp, ci| {
                // R64: Resolve active font and actual codepoint via fallback chain.
                var active_font: *Font = font;
                var actual_cp: u21 = cp;
                var fid: u8 = 0;
                if (family) |fam| {
                    if (fam.fontForCodepoint(font, cp)) |fb| {
                        active_font = fb;
                        fid = fam.fontIdForCodepoint(font, cp);
                    } else if (fam.fontForCodepoint(font, REPLACEMENT_CODEPOINT)) |fb| {
                        active_font = fb;
                        actual_cp = REPLACEMENT_CODEPOINT;
                        fid = fam.fontIdForCodepoint(font, REPLACEMENT_CODEPOINT);
                    } else {
                        std.log.warn("zig-gui: no glyph for U+{X:04}, skipping", .{cp});
                        pen_x += font.advance(cp, px);
                        if (ci + 1 < cps.len) pen_x += font.kerning(cp, cps[ci + 1], px);
                        continue;
                    }
                }

                const key = GlyphKey{ .codepoint = actual_cp, .px = px_u16, .variant = active_font.variant, .font_id = fid };

                // Ensure glyph is in atlas.
                const uv: AtlasRect = if (atlas.lookup(key)) |r| r else blk: {
                    const gr = active_font.rasterize(gpa, actual_cp, px) catch |err| switch (err) {
                        FontError.GlyphNotFound => {
                            // No bitmap (e.g. space) — skip adding to atlas, just advance.
                            pen_x += font.advance(cp, px);
                            if (ci + 1 < cps.len) {
                                pen_x += font.kerning(cp, cps[ci + 1], px);
                            }
                            continue;
                        },
                        else => return err,
                    };
                    defer gpa.free(@constCast(gr.bitmap));
                    const r = atlas.insert(key, gr.width, gr.height, gr.bitmap) catch |err| switch (err) {
                        error.OutOfMemory => return FontError.OutOfMemory,
                        error.GlyphTooLarge => return FontError.OutOfMemory,
                    };
                    break :blk r;
                };

                // Get glyph metrics for positioning.
                var adv_c: c_int = 0;
                var lsb_c: c_int = 0;
                const impl: *FontImpl = @ptrCast(@alignCast(active_font._impl));
                c.stbtt_GetCodepointHMetrics(&impl.info, @intCast(actual_cp), &adv_c, &lsb_c);
                const scale = c.stbtt_ScaleForPixelHeight(&impl.info, px);
                var ix0: c_int = 0;
                var iy0: c_int = 0;
                var ix1: c_int = 0;
                var iy1: c_int = 0;
                c.stbtt_GetCodepointBitmapBox(&impl.info, @intCast(actual_cp), 0, scale, &ix0, &iy0, &ix1, &iy1);

                const dest_x = pen_x + @as(f32, @floatFromInt(ix0));
                const dest_y = pen_y + @as(f32, @floatFromInt(iy0));

                try glyphs.append(gpa, PositionedGlyph{
                    .codepoint = actual_cp,
                    .dest_x = dest_x,
                    .dest_y = dest_y,
                    .dest_w = @as(f32, @floatFromInt(uv.w)),
                    .dest_h = @as(f32, @floatFromInt(uv.h)),
                    .uv = uv,
                    .byte_offset = byte_offsets_buf.items[span.start + ci],
                });

                pen_x += @as(f32, @floatFromInt(adv_c)) * scale;
                if (ci + 1 < cps.len) {
                    pen_x += font.kerning(cp, cps[ci + 1], px);
                }
            }

            // Add inter-word space (except after the last word on the line).
            if (wi + 1 < line_words.len) {
                pen_x += space_w;
            }
        }

        pen_y += line_height;
    }

    return Paragraph{
        .glyphs = try glyphs.toOwnedSlice(gpa),
        .extent = .{
            .w = max_line_w,
            .h = @as(f32, @floatFromInt(line_count)) * line_height,
        },
    };
}
