//! R7C — Tooltip manager.
//!
//! Renders a tooltip bubble 500 ms after the cursor enters a widget that
//! carries a `tooltip` attribute.  The overlay slot is allocated lazily on
//! the first call to `tick`.

const std = @import("std");
const mod01 = @import("../01/types.zig");
const mod02 = @import("../02/types.zig");
const mod05 = @import("../05/types.zig");
const mod07 = @import("../07/types.zig");
const overlay_mod = @import("overlay.zig");

pub const Tokens = mod05.Tokens;
pub const DrawCommand = mod01.DrawCommand;
pub const OverlayLayer = overlay_mod.OverlayLayer;
pub const OverlayId = overlay_mod.OverlayId;
pub const Font = mod02.Font;
pub const GlyphAtlas = mod02.GlyphAtlas;
pub const FontFamily = @import("font_family.zig").FontFamily;

const Color = mod05.Color;

fn toColor09(c: Color) mod01.Color09 {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

const HOVER_DELAY_MS: f32 = 500.0;
const NONE: u32 = std.math.maxInt(u32);

pub const TooltipManager = struct {
    hover_idx: u32 = NONE,
    hover_start_ms: u64 = 0,
    visible: bool = false,
    text: []const u8 = "",
    overlay_id: OverlayId = 0,
    overlay_allocated: bool = false,
    current_cmds: ?[]DrawCommand = null,

    /// Must be called before tick if overlay_id should be stable.
    pub fn ensureOverlaySlot(self: *TooltipManager, layer: *OverlayLayer) void {
        if (!self.overlay_allocated) {
            self.overlay_id = layer.allocId();
            self.overlay_allocated = true;
        }
    }

    pub fn deinit(self: *TooltipManager, gpa: std.mem.Allocator) void {
        if (self.current_cmds) |cmds| {
            gpa.free(cmds);
            self.current_cmds = null;
        }
    }

    /// Called from `dispatchEvents` when the mouse moves onto a widget.
    pub fn onHover(self: *TooltipManager, idx: u32, text: []const u8, now_ms: u64) void {
        if (self.hover_idx == idx) return; // already tracking
        self.hover_idx = idx;
        self.hover_start_ms = now_ms;
        self.visible = false;
        self.text = text;
    }

    /// Called from `dispatchEvents` when the mouse leaves any tooltip widget,
    /// or when `idx` no longer matches the hover widget.
    pub fn onLeave(self: *TooltipManager, idx: u32) void {
        if (self.hover_idx != idx) return;
        self.hover_idx = NONE;
        self.visible = false;
        self.text = "";
    }

    /// Returns true if we are in the 0–500 ms hover countdown (drives `hasAnimatedElements`).
    pub fn isPending(self: *const TooltipManager) bool {
        return self.hover_idx != NONE and !self.visible;
    }

    /// Update tooltip visibility and rebuild overlay slot. `now_ms` is frame time.
    pub fn tick(
        self: *TooltipManager,
        now_ms: u64,
        mouse_x: f32,
        mouse_y: f32,
        window_w: f32,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
        layer: *OverlayLayer,
        gpa: std.mem.Allocator,
    ) !void {
        self.ensureOverlaySlot(layer);

        // Free previous frame's commands.
        if (self.current_cmds) |cmds| {
            gpa.free(cmds);
            self.current_cmds = null;
        }

        if (self.hover_idx == NONE) {
            layer.setSlot(self.overlay_id, &.{});
            self.visible = false;
            return;
        }

        const elapsed = if (now_ms >= self.hover_start_ms)
            now_ms - self.hover_start_ms
        else
            0;

        if (elapsed < @as(u64, HOVER_DELAY_MS)) {
            // Still in delay; no overlay content yet.
            layer.setSlot(self.overlay_id, &.{});
            return;
        }

        // Time to show the tooltip.
        self.visible = true;
        const text = self.text;
        if (text.len == 0) {
            layer.setSlot(self.overlay_id, &.{});
            return;
        }

        try self.buildTooltip(text, mouse_x, mouse_y, window_w, tokens, font, atlas, layer, gpa);
    }

    fn buildTooltip(
        self: *TooltipManager,
        text: []const u8,
        mouse_x: f32,
        mouse_y: f32,
        window_w: f32,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
        layer: *OverlayLayer,
        gpa: std.mem.Allocator,
    ) !void {
        const pad: f32 = 6.0;
        const font_size: f32 = tokens.text_sm;
        const radius: f32 = 4.0;

        // Layout the text to find dimensions.
        const max_tooltip_w: f32 = @min(window_w - 16.0, 280.0);
        const para = try mod02.layoutParagraph(gpa, font, atlas, text, font_size, max_tooltip_w);
        defer gpa.free(para.glyphs);

        const text_w = para.extent.w;
        const text_h = para.extent.h;
        const box_w = text_w + pad * 2.0;
        const box_h = text_h + pad * 2.0;

        // Position: just below and right of cursor; clamp to window.
        const offset_x: f32 = 12.0;
        const offset_y: f32 = 20.0;
        var tx = mouse_x + offset_x;
        const ty = mouse_y + offset_y;
        if (tx + box_w > window_w - 4.0) tx = window_w - box_w - 4.0;
        if (tx < 4.0) tx = 4.0;

        // Build draw commands.
        var cmds: std.ArrayList(DrawCommand) = .empty;
        errdefer cmds.deinit(gpa);

        // Background filled rect + border rect.
        const bg = toColor09(tokens.bg_raised);
        const border = toColor09(tokens.border_default);
        const text_col = toColor09(tokens.text_body);
        const box_rect = mod01.Rect09{ .x = tx, .y = ty, .w = box_w, .h = box_h };
        try cmds.append(gpa, .{ .filled_rect = .{ .rect = box_rect, .color = bg, .radius = radius } });
        try cmds.append(gpa, .{ .border_rect = .{ .rect = box_rect, .color = border, .width = 1.0, .radius = radius } });

        // Glyph commands.
        const atlas_w = @as(f32, @floatFromInt(atlas.width));
        const atlas_h = @as(f32, @floatFromInt(atlas.height));
        if (atlas_w > 0 and atlas_h > 0) {
            const gx = tx + pad;
            const gy = ty + pad;
            for (para.glyphs) |g| {
                if (g.dest_w == 0 or g.dest_h == 0) continue;
                const uv_x = @as(f32, @floatFromInt(g.uv.x)) / atlas_w;
                const uv_y = @as(f32, @floatFromInt(g.uv.y)) / atlas_h;
                const uv_w = g.dest_w / atlas_w;
                const uv_h = g.dest_h / atlas_h;
                try cmds.append(gpa, .{ .glyph = .{
                    .dst = .{ .x = gx + g.dest_x, .y = gy + g.dest_y, .w = g.dest_w, .h = g.dest_h },
                    .uv  = .{ .x = uv_x, .y = uv_y, .w = uv_w, .h = uv_h },
                    .color = text_col,
                } });
            }
        }

        self.current_cmds = try cmds.toOwnedSlice(gpa);
        layer.setSlot(self.overlay_id, self.current_cmds.?);
    }
};
