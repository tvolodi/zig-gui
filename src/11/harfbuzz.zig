//! HarfBuzz C wrapper — shaping engine for module 11 (M24-01 / RK0).
//!
//! Uses the vendored stub at vendor/harfbuzz/src/hb-stub.c when the real
//! HarfBuzz library is not present. Drop real HarfBuzz headers + lib into
//! vendor/harfbuzz/ to enable full OpenType shaping for Arabic, Indic, etc.

const std = @import("std");
const c = @cImport({
    @cInclude("hb.h");
});
const types = @import("types.zig");

// ---------------------------------------------------------------------------
// HbContext — font cache keyed by (font_data_ptr, pixel_size)
// ---------------------------------------------------------------------------

pub const HbContext = struct {
    allocator: std.mem.Allocator,
    font_cache: std.AutoHashMap(FontCacheKey, *c.hb_font_t),

    const FontCacheKey = struct { ptr: usize, size: u16 };

    pub fn init(allocator: std.mem.Allocator) HbContext {
        return .{
            .allocator = allocator,
            .font_cache = std.AutoHashMap(FontCacheKey, *c.hb_font_t).init(allocator),
        };
    }

    pub fn deinit(self: *HbContext) void {
        var it = self.font_cache.iterator();
        while (it.next()) |entry| {
            c.hb_font_destroy(entry.value_ptr.*);
        }
        self.font_cache.deinit();
    }

    /// Get or create an hb_font_t for the given raw font data + pixel size.
    /// The returned pointer is owned by HbContext and destroyed in deinit().
    pub fn getHbFont(
        self: *HbContext,
        font_data: []const u8,
        font_ptr_id: usize,
        pixel_size: u16,
    ) !*c.hb_font_t {
        const key = FontCacheKey{ .ptr = font_ptr_id, .size = pixel_size };
        if (self.font_cache.get(key)) |f| return f;

        const blob = c.hb_blob_create(
            font_data.ptr,
            @intCast(font_data.len),
            c.HB_MEMORY_MODE_READONLY,
            null,
            null,
        ) orelse return types.ShapeError.HarfBuzzError;

        const face = c.hb_face_create(blob, 0) orelse {
            c.hb_blob_destroy(blob);
            return types.ShapeError.HarfBuzzError;
        };
        c.hb_blob_destroy(blob);

        const font = c.hb_font_create(face) orelse {
            c.hb_face_destroy(face);
            return types.ShapeError.HarfBuzzError;
        };
        c.hb_face_destroy(face);

        // Scale: HarfBuzz uses 26.6 fixed-point, so scale = pixel_size * 64
        const scale: c_int = @intCast(@as(u32, pixel_size) * 64);
        c.hb_font_set_scale(font, scale, scale);

        try self.font_cache.put(key, font);
        return font;
    }
};

// ---------------------------------------------------------------------------
// shapeRun — shape one TextRun into a ShapedRun
// ---------------------------------------------------------------------------

/// Shape one TextRun. Returns a ShapedRun with glyphs in visual order for the run.
/// Caller owns result — call result.deinit() when done.
pub fn shapeRun(
    ctx: *HbContext,
    font_data: []const u8,
    font_ptr_id: usize,
    pixel_size: u16,
    run: types.TextRun,
    allocator: std.mem.Allocator,
) types.ShapeError!types.ShapedRun {
    const hb_font = ctx.getHbFont(font_data, font_ptr_id, pixel_size) catch
        return types.ShapeError.HarfBuzzError;

    const buf = c.hb_buffer_create() orelse return types.ShapeError.HarfBuzzError;
    defer c.hb_buffer_destroy(buf);

    c.hb_buffer_add_utf8(
        buf,
        run.text.ptr,
        @intCast(run.text.len),
        0,
        @intCast(run.text.len),
    );

    const hb_dir: c.hb_direction_t = if (run.direction == .rtl)
        c.HB_DIRECTION_RTL
    else
        c.HB_DIRECTION_LTR;
    c.hb_buffer_set_direction(buf, hb_dir);
    c.hb_buffer_guess_segment_properties(buf);

    c.hb_shape(hb_font, buf, null, 0);

    var glyph_count: c_uint = 0;
    const infos = c.hb_buffer_get_glyph_infos(buf, &glyph_count);
    const positions = c.hb_buffer_get_glyph_positions(buf, &glyph_count);

    if (infos == null or positions == null) {
        return types.ShapeError.HarfBuzzError;
    }

    const glyphs = try allocator.alloc(types.ShapedGlyph, glyph_count);
    for (0..glyph_count) |i| {
        glyphs[i] = .{
            .glyph_id = infos[i].codepoint,
            // cluster is relative to run.text; add run.byte_start for paragraph offset
            .cluster = infos[i].cluster + run.byte_start,
            .x_advance = @as(f32, @floatFromInt(positions[i].x_advance)) / 64.0,
            .x_offset  = @as(f32, @floatFromInt(positions[i].x_offset))  / 64.0,
            .y_offset  = @as(f32, @floatFromInt(positions[i].y_offset))  / 64.0,
        };
    }

    return types.ShapedRun{
        .glyphs = glyphs,
        .font_id = run.font_id,
        .direction = run.direction,
        .script = run.script,
        .allocator = allocator,
    };
}
