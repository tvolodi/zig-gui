//! R74 — Toast notification manager.
//!
//! Owned by the caller. Call `show()` to enqueue a toast, `tick()` once per
//! frame to expire old toasts and rebuild the overlay slot.  The overlay slot
//! is allocated once via `init()` and freed when the manager is no longer
//! needed (no explicit deinit — overlay.removeSlot covers it).

const std = @import("std");
const mod01 = @import("../01/types.zig");
const mod02 = @import("../02/types.zig");
const mod05 = @import("../05/types.zig");
const overlay_mod = @import("overlay.zig");

pub const DrawCommand = mod01.DrawCommand;
pub const GlyphAtlas = mod02.GlyphAtlas;
pub const Font = mod02.Font;
pub const Tokens = mod05.Tokens;
pub const Color = mod05.Color;
pub const OverlayId = overlay_mod.OverlayId;
pub const OverlayLayer = overlay_mod.OverlayLayer;

const TOAST_W: f32 = 280;
const TOAST_H: f32 = 56;
const MARGIN: f32 = 16;
const GAP: f32 = 8;
const TAB_BAR_H: f32 = 36;

pub const ToastKind = enum { info, success, warning, @"error" };

pub const MAX_TOASTS: u8 = 4;

pub const Toast = struct {
    /// UTF-8 message (up to 127 bytes + NUL).
    message: [128]u8 = .{0} ** 128,
    message_len: u8 = 0,
    kind: ToastKind = .info,
    /// Millisecond timestamp from std.time.milliTimestamp() at creation time.
    created_ms: u64 = 0,
    /// How long to show the toast before auto-dismissing (0 = forever).
    duration_ms: u32 = 3000,
};

pub const ToastManager = struct {
    toasts: [MAX_TOASTS]Toast = [1]Toast{.{}} ** MAX_TOASTS,
    count: u8 = 0,
    overlay_id: OverlayId = 0,
    /// Slice owned by this manager; freed at the start of each `tick`.
    current_cmds: ?[]DrawCommand = null,

    /// Must be called once before using the manager.
    pub fn init(overlay: *OverlayLayer) ToastManager {
        return ToastManager{
            .overlay_id = overlay.allocId(),
        };
    }

    /// Enqueue a new toast.  If MAX_TOASTS is already reached, the oldest is dropped.
    pub fn show(
        self: *ToastManager,
        message: []const u8,
        kind: ToastKind,
        duration_ms: u32,
        now_ms: u64,
    ) void {
        if (self.count >= MAX_TOASTS) self.dismiss(0);
        var t = Toast{
            .kind = kind,
            .created_ms = now_ms,
            .duration_ms = duration_ms,
        };
        const copy_len = @min(message.len, t.message.len - 1);
        @memcpy(t.message[0..copy_len], message[0..copy_len]);
        t.message_len = @intCast(copy_len);
        self.toasts[self.count] = t;
        self.count += 1;
    }

    /// Must be called once per frame.
    /// Frees the previous frame's command slice, expires old toasts, and rebuilds
    /// the overlay slot.
    pub fn tick(
        self: *ToastManager,
        now_ms: u64,
        window_w: f32,
        window_h: f32,
        tokens: Tokens,
        font: *Font,
        glyph_atlas: *GlyphAtlas,
        overlay: *OverlayLayer,
        alloc: std.mem.Allocator,
    ) error{OutOfMemory}!void {
        // Free the slice from the previous frame.
        if (self.current_cmds) |old| {
            alloc.free(old);
            self.current_cmds = null;
        }

        // Expire old toasts (walk backwards to keep indices stable after dismiss).
        var i: u8 = self.count;
        while (i > 0) {
            i -= 1;
            const t = &self.toasts[i];
            if (t.duration_ms > 0 and now_ms >= t.created_ms and
                now_ms -% t.created_ms >= t.duration_ms)
            {
                self.dismiss(i);
            }
        }

        if (self.count == 0) {
            overlay.setSlot(self.overlay_id, &.{});
            return;
        }

        // Build draw commands for all active toasts.
        var cmds: std.ArrayList(DrawCommand) = .empty;
        errdefer cmds.deinit(alloc);

        const atlas_w = @as(f32, @floatFromInt(glyph_atlas.width));
        const atlas_h = @as(f32, @floatFromInt(glyph_atlas.height));

        for (self.toasts[0..self.count], 0..) |t, ti| {
            const toast_y = window_h -
                (@as(f32, @floatFromInt(ti + 1)) * (TOAST_H + GAP)) - MARGIN;
            const toast_x = window_w - TOAST_W - MARGIN;

            const bg = toastBg(t.kind, tokens);
            const border = toastBorder(t.kind, tokens);

            // Background.
            try cmds.append(alloc, .{ .filled_rect = .{
                .rect = .{ .x = toast_x, .y = toast_y, .w = TOAST_W, .h = TOAST_H },
                .color = toC09(bg),
                .radius = tokens.radius_sm,
            } });
            // Border.
            try cmds.append(alloc, .{ .border_rect = .{
                .rect = .{ .x = toast_x, .y = toast_y, .w = TOAST_W, .h = TOAST_H },
                .color = toC09(border),
                .width = 1,
            } });

            // Message text.
            const msg = t.message[0..t.message_len];
            if (msg.len > 0 and atlas_w > 0 and atlas_h > 0) {
                const para = mod02.layoutParagraph(
                    alloc,
                    font,
                    glyph_atlas,
                    msg,
                    tokens.text_sm,
                    TOAST_W - 24,
                ) catch continue;
                defer alloc.free(para.glyphs);
                const text_col = toC09(tokens.text_body);
                for (para.glyphs) |g| {
                    if (g.dest_w == 0 or g.dest_h == 0) continue;
                    const uv_x = @as(f32, @floatFromInt(g.uv.x)) / atlas_w;
                    const uv_y = @as(f32, @floatFromInt(g.uv.y)) / atlas_h;
                    const uv_w = g.dest_w / atlas_w;
                    const uv_h = g.dest_h / atlas_h;
                    try cmds.append(alloc, .{ .glyph = .{
                        .dst = .{
                            .x = toast_x + 12 + g.dest_x,
                            .y = toast_y + (TOAST_H - tokens.text_sm) / 2.0 + g.dest_y,
                            .w = g.dest_w,
                            .h = g.dest_h,
                        },
                        .uv = .{ .x = uv_x, .y = uv_y, .w = uv_w, .h = uv_h },
                        .color = text_col,
                    } });
                }
            }
        }

        const slice = try cmds.toOwnedSlice(alloc);
        self.current_cmds = slice;
        overlay.setSlot(self.overlay_id, slice);
    }

    /// Remove a toast by index (shifts remaining items down).
    pub fn dismiss(self: *ToastManager, index: u8) void {
        if (index >= self.count) return;
        var j = index;
        while (j + 1 < self.count) : (j += 1) {
            self.toasts[j] = self.toasts[j + 1];
        }
        self.count -= 1;
    }

    /// Free the current command slice (call before the manager goes out of scope).
    pub fn deinit(self: *ToastManager, alloc: std.mem.Allocator) void {
        if (self.current_cmds) |cmds| {
            alloc.free(cmds);
            self.current_cmds = null;
        }
    }
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn toC09(c: Color) mod01.Color09 {
    return .{ .r = c.r, .g = c.g, .b = c.b, .a = c.a };
}

fn toastBg(kind: ToastKind, t: Tokens) Color {
    return switch (kind) {
        .info => t.bg_raised,
        .success => Color{ .r = t.ok.r, .g = t.ok.g, .b = t.ok.b, .a = 220 },
        .warning => Color{ .r = t.warn.r, .g = t.warn.g, .b = t.warn.b, .a = 220 },
        .@"error" => Color{ .r = t.err.r, .g = t.err.g, .b = t.err.b, .a = 220 },
    };
}

fn toastBorder(kind: ToastKind, t: Tokens) Color {
    return switch (kind) {
        .info => t.border_default,
        .success => t.ok,
        .warning => t.warn,
        .@"error" => t.err,
    };
}
