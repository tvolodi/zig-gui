//! R90 — Debug overlay.
//! DebugOverlay draws colored element bounds over the scene when toggled with F1.
//! The hover info panel shows computed rect and style for the hovered element.

const std = @import("std");
const mod01 = @import("../01/types.zig");
const mod02 = @import("../02/types.zig");
const mod05 = @import("../05/types.zig");
const mod07 = @import("../07/types.zig");

const DrawCommand = mod01.DrawCommand;
const Scene = mod07.Scene;
const Tokens = mod05.Tokens;
const Font = mod02.Font;
const GlyphAtlas = mod02.GlyphAtlas;

/// Sentinel — no hovered element.
const NONE: u32 = std.math.maxInt(u32);

pub const DebugOverlay = struct {
    enabled: bool = false,
    hovered_idx: u32 = NONE,

    pub fn init() DebugOverlay {
        return .{};
    }

    pub fn toggle(self: *DebugOverlay) void {
        self.enabled = !self.enabled;
    }

    pub fn isEnabled(self: *const DebugOverlay) bool {
        return self.enabled;
    }

    /// Update the hovered element from the current cursor position.
    /// Called once per frame before buildDebugDrawList.
    pub fn updateHover(self: *DebugOverlay, scene: *const Scene, x: f32, y: f32) void {
        // Reverse pre-order: topmost element in painter order is found last in forward order.
        const n = scene._kind.items.len;
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            const id = mod07.ElementId{ .index = @as(u32, @intCast(i)), .gen = scene.elements.gen.items[i] };
            if (!scene.elements.isValid(id)) continue;
            if (scene.isHidden(@as(u32, @intCast(i)))) continue;
            if (i >= scene.elements.layout.items.len) continue;
            const rect = scene.elements.layout.items[i].computed;
            if (rect.w == 0 or rect.h == 0) continue;
            if (x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h) {
                self.hovered_idx = @as(u32, @intCast(i));
                return;
            }
        }
        self.hovered_idx = NONE;
    }

    /// Produce an overlay draw list.  The returned slice is owned by `alloc`; caller frees it.
    /// Returns an empty slice when !enabled.
    pub fn buildDebugDrawList(
        self: *const DebugOverlay,
        alloc: std.mem.Allocator,
        scene: *const Scene,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
    ) ![]DrawCommand {
        if (!self.enabled) return &[_]DrawCommand{};

        var list: std.ArrayListUnmanaged(DrawCommand) = .empty;
        errdefer list.deinit(alloc);

        // ----------------------------------------------------------------
        // 1. Element bounds (border_rect per live element).
        // ----------------------------------------------------------------
        const s = &scene.elements;
        for (0..scene._kind.items.len) |i| {
            const idx = @as(u32, @intCast(i));
            const id = mod07.ElementId{ .index = idx, .gen = s.gen.items[idx] };
            if (!s.isValid(id)) continue;
            if (scene.isHidden(idx)) continue;
            if (idx >= s.layout.items.len) continue;
            const rect = s.layout.items[idx].computed;
            if (rect.w == 0 or rect.h == 0) continue;

            const kind = scene._kind.items[idx];
            const is_hovered = (idx == self.hovered_idx);
            const is_focusable = blk: {
                for (scene.focusable_indices.items) |fi| {
                    if (fi == idx) break :blk true;
                }
                break :blk false;
            };
            const is_container = (kind == .row or kind == .column or kind == .card or kind == .scrollview);

            const border_color: mod01.Color09 = if (is_hovered)
                .{ .r = tokens.accent.r, .g = tokens.accent.g, .b = tokens.accent.b, .a = 255 }
            else if (is_focusable)
                .{ .r = tokens.info.r, .g = tokens.info.g, .b = tokens.info.b, .a = 180 }
            else if (is_container)
                .{ .r = tokens.ok.r, .g = tokens.ok.g, .b = tokens.ok.b, .a = 140 }
            else
                .{ .r = tokens.warn.r, .g = tokens.warn.g, .b = tokens.warn.b, .a = 120 };

            const border_width: f32 = if (is_hovered) 2 else 1;

            try list.append(alloc, .{ .border_rect = .{
                .rect = .{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h },
                .color = border_color,
                .width = border_width,
            } });
        }

        // ----------------------------------------------------------------
        // 2. Hover info panel.
        // ----------------------------------------------------------------
        if (self.hovered_idx != NONE) {
            const idx = self.hovered_idx;
            if (idx < scene._kind.items.len and idx < s.layout.items.len) {
                try emitHoverPanel(&list, alloc, scene, tokens, font, atlas, idx);
            }
        }

        return list.toOwnedSlice(alloc);
    }
};

// ---------------------------------------------------------------------------
// Hover info panel
// ---------------------------------------------------------------------------

fn emitHoverPanel(
    list: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    scene: *const Scene,
    tokens: Tokens,
    font: *Font,
    atlas: *GlyphAtlas,
    idx: u32,
) !void {
    const rect = scene.elements.layout.items[idx].computed;
    const kind = scene._kind.items[idx];
    const style = if (idx < scene._style.items.len) scene._style.items[idx] else mod05.ComputedStyle{};

    const FONT_SIZE: f32 = 11;
    const fm = font.metrics(FONT_SIZE);
    const line_h = fm.ascent + fm.descent + fm.line_gap;
    const pad: f32 = 8;
    const panel_w: f32 = 240;
    const num_lines: f32 = 4;
    const panel_h = num_lines * line_h + 2 * pad;

    // Place at bottom-left corner: 24 px from each edge.
    // Without viewport height, place at y=24 as approximation (spec does not pass viewport_h).
    const panel_x: f32 = 24;
    const panel_y: f32 = 24;

    // Background
    try list.append(alloc, .{ .filled_rect = .{
        .rect = .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
        .color = .{ .r = tokens.bg_raised.r, .g = tokens.bg_raised.g, .b = tokens.bg_raised.b, .a = 230 },
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

    // Line 1: idx: N   kind: name
    var buf1: [128]u8 = undefined;
    const line1 = std.fmt.bufPrint(&buf1, "idx: {d}   kind: {s}", .{ idx, @tagName(kind) }) catch "idx: ?  kind: ?";
    try emitTextLine(list, alloc, font, atlas, line1, panel_x + pad, line_y, FONT_SIZE, text_color);
    line_y += line_h;

    // Line 2: x: N.N  y: N.N  w: N.N  h: N.N
    var buf2: [128]u8 = undefined;
    const line2 = std.fmt.bufPrint(&buf2, "x: {d:.1}  y: {d:.1}  w: {d:.1}  h: {d:.1}", .{
        rect.x, rect.y, rect.w, rect.h,
    }) catch "x: ?";
    try emitTextLine(list, alloc, font, atlas, line2, panel_x + pad, line_y, FONT_SIZE, text_color);
    line_y += line_h;

    // Line 3: bg, text, border
    var buf3: [128]u8 = undefined;
    const line3 = std.fmt.bufPrint(&buf3, "bg: #{x:0>2}{x:0>2}{x:0>2}  text: #{x:0>2}{x:0>2}{x:0>2}  brd: {d:.1}px", .{
        style.background.r, style.background.g, style.background.b,
        style.text_color.r, style.text_color.g, style.text_color.b,
        style.border_width,
    }) catch "style: ?";
    try emitTextLine(list, alloc, font, atlas, line3, panel_x + pad, line_y, FONT_SIZE, text_color);
    line_y += line_h;

    // Line 4: radius, pad, font
    var buf4: [128]u8 = undefined;
    const line4 = std.fmt.bufPrint(&buf4, "radius: {d:.1}  pad: {d:.1}/{d:.1}/{d:.1}/{d:.1}  font: {d:.1}px", .{
        style.radius,
        style.padding.top,
        style.padding.right,
        style.padding.bottom,
        style.padding.left,
        style.font_size,
    }) catch "radius: ?";
    try emitTextLine(list, alloc, font, atlas, line4, panel_x + pad, line_y, FONT_SIZE, text_color);
}

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
