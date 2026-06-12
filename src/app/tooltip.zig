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
        var para = try mod02.layoutParagraph(gpa, font, atlas, text, font_size, max_tooltip_w);
        defer para.deinit(gpa);

        const text_w = para.width;
        const text_h = para.height;
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

        // Background quad.
        cmds.append(gpa, .{ .quad = .{
            .x = tx,
            .y = ty,
            .w = box_w,
            .h = box_h,
            .color = tokens.bg_raised,
            .radius = radius,
            .border_width = 1.0,
            .border_color = tokens.border_default,
        } }) catch {};

        // Glyph commands.
        const gx = tx + pad;
        const gy = ty + pad;
        for (para.glyphs) |g| {
            cmds.append(gpa, .{ .glyph = .{
                .x = gx + g.x,
                .y = gy + g.y,
                .w = g.w,
                .h = g.h,
                .uv_x = g.uv_x,
                .uv_y = g.uv_y,
                .uv_w = g.uv_w,
                .uv_h = g.uv_h,
                .color = tokens.text_body,
            } }) catch {};
        }

        self.current_cmds = try cmds.toOwnedSlice(gpa);
        layer.setSlot(self.overlay_id, self.current_cmds.?);
    }
};
