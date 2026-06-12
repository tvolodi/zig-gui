//! R92 — Performance counters HUD.
//! FrameCounters holds per-frame metrics. PerfHud smooths frame times and
//! emits a small HUD panel in the top-right corner when the debug overlay is enabled.

const std = @import("std");
const mod01 = @import("../01/types.zig");
const mod02 = @import("../02/types.zig");
const mod05 = @import("../05/types.zig");

const DrawCommand = mod01.DrawCommand;
const Tokens = mod05.Tokens;
const Font = mod02.Font;
const GlyphAtlas = mod02.GlyphAtlas;

/// Per-frame performance counters.
pub const FrameCounters = struct {
    /// Frame time in milliseconds (wall-clock from previous beginFrame to current endFrame).
    frame_ms: f32 = 0,
    /// Number of DrawCommand entries submitted to the last drawFrame call.
    cmd_count: u32 = 0,
    /// Number of set bits in ElementStore.dirty at the START of the last frame.
    dirty_count: u32 = 0,
    /// Total live element count.
    element_count: u32 = 0,
};

/// Performance HUD — smoothed frame counter and draw-list builder.
pub const PerfHud = struct {
    counters: FrameCounters = .{},
    /// Ring buffer of the last 16 frame times for smoothing.
    frame_ms_history: [16]f32 = [_]f32{0} ** 16,
    history_idx: u8 = 0,

    pub fn init() PerfHud {
        return .{};
    }

    /// Record one frame's worth of counters. Updates the ring buffer.
    pub fn record(self: *PerfHud, c: FrameCounters) void {
        self.counters = c;
        self.frame_ms_history[self.history_idx] = c.frame_ms;
        self.history_idx = @intCast((@as(u32, self.history_idx) + 1) % 16);
    }

    /// Smoothed frame time: average of the non-zero entries in the ring buffer.
    /// Returns 0 if all entries are zero.
    pub fn smoothFrameMs(self: *const PerfHud) f32 {
        var sum: f32 = 0;
        var count: u32 = 0;
        for (self.frame_ms_history) |ms| {
            if (ms > 0) {
                sum += ms;
                count += 1;
            }
        }
        if (count == 0) return 0;
        return sum / @as(f32, @floatFromInt(count));
    }

    /// Produce the HUD draw list.  Returned slice is owned by `alloc`; caller frees it.
    /// Returns empty slice when `enabled` is false.
    pub fn buildHudDrawList(
        self: *const PerfHud,
        alloc: std.mem.Allocator,
        enabled: bool,
        viewport_w: f32,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
    ) ![]DrawCommand {
        if (!enabled) return &[_]DrawCommand{};

        var list: std.ArrayListUnmanaged(DrawCommand) = .empty;
        errdefer list.deinit(alloc);

        const FONT_SIZE: f32 = 11;
        const fm = font.metrics(FONT_SIZE);
        const line_h = fm.ascent + fm.descent + fm.line_gap;
        const pad: f32 = 8;
        const panel_w: f32 = 200;
        const num_lines: f32 = 3;
        const panel_h = num_lines * line_h + 2 * pad;

        const panel_x = viewport_w - panel_w - 12;
        const panel_y: f32 = 12;

        // Background
        try list.append(alloc, .{ .filled_rect = .{
            .rect = .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
            .color = .{ .r = tokens.bg_raised.r, .g = tokens.bg_raised.g, .b = tokens.bg_raised.b, .a = 210 },
            .radius = 4,
        } });

        // Border
        try list.append(alloc, .{ .border_rect = .{
            .rect = .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
            .color = .{ .r = tokens.border_default.r, .g = tokens.border_default.g, .b = tokens.border_default.b, .a = 255 },
            .width = 1,
            .radius = 4,
        } });

        const text_color = mod01.Color09{
            .r = tokens.text_body.r,
            .g = tokens.text_body.g,
            .b = tokens.text_body.b,
            .a = 255,
        };

        var line_y: f32 = panel_y + pad;

        // Line 1: frame time + fps
        const smooth_ms = self.smoothFrameMs();
        var buf1: [64]u8 = undefined;
        const line1 = if (smooth_ms > 0)
            std.fmt.bufPrint(&buf1, "frame  {d:.1} ms   ({d} fps)", .{
                smooth_ms,
                @as(u32, @intFromFloat(@round(1000.0 / smooth_ms))),
            }) catch "frame  ?"
        else
            std.fmt.bufPrint(&buf1, "frame  0.0 ms   (--- fps)", .{}) catch "frame  ?";
        try emitTextLine(&list, alloc, font, atlas, line1, panel_x + pad, line_y, FONT_SIZE, text_color);
        line_y += line_h;

        // Line 2: cmd count
        var buf2: [64]u8 = undefined;
        const line2 = std.fmt.bufPrint(&buf2, "cmds   {d}", .{self.counters.cmd_count}) catch "cmds  ?";
        try emitTextLine(&list, alloc, font, atlas, line2, panel_x + pad, line_y, FONT_SIZE, text_color);
        line_y += line_h;

        // Line 3: dirty / element count
        var buf3: [64]u8 = undefined;
        const line3 = std.fmt.bufPrint(&buf3, "dirty  {d} / {d}", .{
            self.counters.dirty_count, self.counters.element_count,
        }) catch "dirty  ?";
        try emitTextLine(&list, alloc, font, atlas, line3, panel_x + pad, line_y, FONT_SIZE, text_color);

        return list.toOwnedSlice(alloc);
    }
};

// ---------------------------------------------------------------------------
// Text rendering helper
// ---------------------------------------------------------------------------

fn emitTextLine(
    list: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    font: *Font,
    atlas: *GlyphAtlas,
    text: []const u8,
    x: f32,
    y: f32,
    font_size: f32,
    color: mod01.Color09,
) !void {
    const para = mod02.layoutParagraph(alloc, font, atlas, text, font_size, 1e6) catch return;
    defer alloc.free(para.glyphs);

    const atlas_w = @as(f32, @floatFromInt(atlas.width));
    const atlas_h = @as(f32, @floatFromInt(atlas.height));
    if (atlas_w == 0 or atlas_h == 0) return;

    for (para.glyphs) |g| {
        const gw = g.dest_w;
        const gh = g.dest_h;
        if (gw == 0 or gh == 0) continue;

        const uv = mod01.Rect09{
            .x = @as(f32, @floatFromInt(g.uv.x)) / atlas_w,
            .y = @as(f32, @floatFromInt(g.uv.y)) / atlas_h,
            .w = gw / atlas_w,
            .h = gh / atlas_h,
        };

        try list.append(alloc, .{ .glyph = .{
            .dst = .{ .x = x + g.dest_x, .y = y + g.dest_y, .w = gw, .h = gh },
            .uv = uv,
            .color = color,
        } });
    }
}
