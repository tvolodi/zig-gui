//! 09 — Renderer — implementation.
//!
//! Re-exports draw-command types from module 01 (Vulkan machinery lives there) and
//! implements the CPU-side serializer (buildDrawList).
//! GpuAtlas.upload + GpuAtlas.deinit live in module 01 so Vulkan calls stay in one place.

const std = @import("std");
const platform = @import("../01/types.zig");
const text_mod = @import("../02/types.zig");
const store_mod = @import("../03/types.zig");
const theme_mod = @import("../05/types.zig");
const comp_mod = @import("../07/types.zig");

// ---------------------------------------------------------------------------
// Re-exports
// ---------------------------------------------------------------------------

pub const Rect = store_mod.Rect;
pub const Color = theme_mod.Color;
pub const Scene = comp_mod.Scene;
pub const GlyphAtlas = text_mod.GlyphAtlas;

pub const FilledRect = platform.FilledRect;
pub const BorderRect = platform.BorderRect;
pub const GlyphCmd = platform.GlyphCmd;
pub const DrawCommand = platform.DrawCommand;

/// GPU-side atlas. Extends platform.GpuAtlas with upload() which needs GlyphAtlas (mod 02).
/// deinit() delegates to platform.GpuAtlas.deinit which owns the Vulkan calls.
pub const GpuAtlas = struct {
    image: ?*anyopaque = null,
    image_view: ?*anyopaque = null,
    sampler: ?*anyopaque = null,
    memory: ?*anyopaque = null,
    width: u32 = 0,
    height: u32 = 0,

    pub fn upload(
        gpa: std.mem.Allocator,
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        queue: *anyopaque,
        atlas: *const GlyphAtlas,
    ) error{ OutOfMemory, GpuUploadFailed }!GpuAtlas {
        _ = gpa;
        const pixels = @constCast(atlas).pixels();
        const h = try platform.vkUploadAtlas(device, phys_device, cmd_pool, queue,
            pixels, atlas.width, atlas.height);
        return GpuAtlas{
            .image = h.image,
            .image_view = h.image_view,
            .sampler = h.sampler,
            .memory = h.memory,
            .width = atlas.width,
            .height = atlas.height,
        };
    }

    pub fn deinit(self: *GpuAtlas, device: *anyopaque) void {
        var h = platform.GpuAtlas{
            .image = self.image, .image_view = self.image_view,
            .sampler = self.sampler, .memory = self.memory,
        };
        h.deinit(device);
        self.* = .{};
    }

    /// Cast to platform.GpuAtlas for VulkanBackend.drawFrame.
    /// Safe: same field layout for the first 6 fields.
    pub fn asHandles(self: *const GpuAtlas) platform.GpuAtlas {
        return .{ .image = self.image, .image_view = self.image_view,
                  .sampler = self.sampler, .memory = self.memory,
                  .width = self.width, .height = self.height };
    }
};

// Re-export text module so acceptance test can do C.text.Font.initFromBytes
pub const text = text_mod;

// ---------------------------------------------------------------------------
// Border helpers (public — tested directly by acceptance_test.zig)
// ---------------------------------------------------------------------------

/// Clamp border.width to min(rect.w, rect.h) / 2 to prevent inverted geometry.
pub fn clampBorderWidth(border: BorderRect) BorderRect {
    const max_w = @min(border.rect.w, border.rect.h) / 2.0;
    if (border.width <= max_w) return border;
    var result = border;
    result.width = max_w;
    return result;
}

/// Expand a border_rect into 4 FilledRect quads (top, bottom, left, right).
pub fn expandBorderToQuads(border: BorderRect, out: *[4]FilledRect) void {
    const r = border.rect;
    const w = border.width;
    const col = border.color;
    out[0] = .{ .rect = .{ .x = r.x,           .y = r.y,           .w = r.w, .h = w }, .color = col };
    out[1] = .{ .rect = .{ .x = r.x,           .y = r.y + r.h - w, .w = r.w, .h = w }, .color = col };
    out[2] = .{ .rect = .{ .x = r.x,           .y = r.y + w,       .w = w,   .h = r.h - 2.0 * w }, .color = col };
    out[3] = .{ .rect = .{ .x = r.x + r.w - w, .y = r.y + w,       .w = w,   .h = r.h - 2.0 * w }, .color = col };
}

// ---------------------------------------------------------------------------
// Conversion helpers
// ---------------------------------------------------------------------------

fn toRect09(r: store_mod.Rect) platform.Rect09 {
    return .{ .x = r.x, .y = r.y, .w = r.w, .h = r.h };
}

fn toColor09(col: theme_mod.Color) platform.Color09 {
    return .{ .r = col.r, .g = col.g, .b = col.b, .a = col.a };
}

// ---------------------------------------------------------------------------
// Serializer
// ---------------------------------------------------------------------------

/// Walk a solved Scene depth-first pre-order and emit a flat DrawCommand list.
/// Caller owns the returned slice; free with `alloc`.
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    atlas: *GlyphAtlas,
) error{OutOfMemory}![]DrawCommand {
    var list: std.ArrayList(DrawCommand) = .empty;
    errdefer list.deinit(alloc);

    const s = scene.store();
    if (s.live == 0) return list.toOwnedSlice(alloc);

    var stack: std.ArrayList(store_mod.ElementId) = .empty;
    defer stack.deinit(alloc);

    // Find root: first valid element with no parent.
    var root_found = false;
    var idx: u32 = 0;
    while (idx < s.gen.items.len) : (idx += 1) {
        const id = store_mod.ElementId{ .index = idx, .gen = s.gen.items[idx] };
        if (!s.isValid(id)) continue;
        if (s.parentOf(id) == null) {
            try stack.append(alloc, id);
            root_found = true;
            break;
        }
    }
    if (!root_found) return list.toOwnedSlice(alloc);

    while (stack.items.len > 0) {
        const id = stack.pop().?;
        const computed = s.get(id).computed;

        // Zero-size: skip drawing but still traverse children.
        if (computed.w <= 0 or computed.h <= 0) {
            try pushChildrenReversed(&stack, alloc, s, id);
            continue;
        }

        const style = scene.styleOf(id);

        // 1. Background
        if (style.background.a > 0) {
            try list.append(alloc, .{ .filled_rect = .{
                .rect = toRect09(computed),
                .color = toColor09(style.background),
                .radius = style.radius,
            } });
        }

        // 2. Border
        if (style.border_width > 0) {
            try list.append(alloc, .{ .border_rect = .{
                .rect = toRect09(computed),
                .color = toColor09(style.border_color),
                .width = style.border_width,
            } });
        }

        // 3. Text glyphs
        if (scene.textOf(id)) |str| {
            if (str.len > 0) {
                try emitGlyphs(&list, alloc, id, str, computed, style, atlas);
            }
        }

        try pushChildrenReversed(&stack, alloc, s, id);
    }

    return list.toOwnedSlice(alloc);
}

fn pushChildrenReversed(
    stack: *std.ArrayList(store_mod.ElementId),
    alloc: std.mem.Allocator,
    s: *store_mod.ElementStore,
    id: store_mod.ElementId,
) !void {
    var buf: [256]store_mod.ElementId = undefined;
    var n: usize = 0;
    var it = s.childrenOf(id);
    while (it.next()) |child| {
        if (n < buf.len) { buf[n] = child; n += 1; }
    }
    var i = n;
    while (i > 0) { i -= 1; try stack.append(alloc, buf[i]); }
}

fn emitGlyphs(
    list: *std.ArrayList(DrawCommand),
    alloc: std.mem.Allocator,
    id: store_mod.ElementId,
    str: []const u8,
    computed: store_mod.Rect,
    style: *const theme_mod.ComputedStyle,
    atlas: *GlyphAtlas,
) !void {
    _ = id;
    const atlas_w = @as(f32, @floatFromInt(atlas.width));
    const atlas_h = @as(f32, @floatFromInt(atlas.height));
    if (atlas_w == 0 or atlas_h == 0) return;

    const px_u16: u16 = @intFromFloat(style.font_size);
    var pen_x: f32 = computed.x;
    const pen_y: f32 = computed.y;

    var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        const key = text_mod.GlyphKey{ .codepoint = cp, .px = px_u16 };
        const uv_rect = atlas.lookup(key) orelse continue;

        const gw = @as(f32, @floatFromInt(uv_rect.w));
        const gh = @as(f32, @floatFromInt(uv_rect.h));
        if (gw == 0 or gh == 0) continue;

        // Clip overflow glyphs
        if (pen_x + gw > computed.x + computed.w) break;

        const uv = platform.Rect09{
            .x = @as(f32, @floatFromInt(uv_rect.x)) / atlas_w,
            .y = @as(f32, @floatFromInt(uv_rect.y)) / atlas_h,
            .w = gw / atlas_w,
            .h = gh / atlas_h,
        };

        try list.append(alloc, .{ .glyph = .{
            .dst = .{ .x = pen_x, .y = pen_y, .w = gw, .h = gh },
            .uv = uv,
            .color = toColor09(style.text_color),
        } });

        pen_x += gw;
    }
}
