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
const image_atlas_mod = @import("../app/image_atlas.zig");
const sdf_icons = @import("sdf_icons.zig");

// ---------------------------------------------------------------------------
// Re-exports
// ---------------------------------------------------------------------------

pub const Rect = store_mod.Rect;
pub const Color = theme_mod.Color;
pub const Scene = comp_mod.Scene;
pub const GlyphAtlas = text_mod.GlyphAtlas;
pub const Tokens = theme_mod.Tokens;
pub const PseudoState = comp_mod.PseudoState;
pub const PseudoStyleSet = theme_mod.PseudoStyleSet;
pub const ComputedStyle = theme_mod.ComputedStyle;
pub const ImageAtlas = image_atlas_mod.ImageAtlas;

pub const FilledRect = platform.FilledRect;
pub const BorderRect = platform.BorderRect;
pub const GlyphCmd = platform.GlyphCmd;
pub const CircleCmd = platform.CircleCmd; // M13-05 RD4
pub const SdfIconCmd = platform.SdfIconCmd; // M13-04 RD3
pub const DrawCommand = platform.DrawCommand;
pub const ScissorRect = platform.ScissorRect;
pub const ImageCmd = platform.ImageCmd;
pub const ClipRounded = platform.ClipRounded; // M13-02 RD1

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
        const h = try platform.vkUploadAtlas(device, phys_device, cmd_pool, queue, pixels, atlas.width, atlas.height);
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
            .image = self.image,
            .image_view = self.image_view,
            .sampler = self.sampler,
            .memory = self.memory,
        };
        h.deinit(device);
        self.* = .{};
    }

    /// M13-03 RD2 — Upload an RGBA8 subpixel atlas to the GPU.
    pub fn uploadRgba8(
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        queue: *anyopaque,
        pixels: []const u8,
        atlas_w: u32,
        atlas_h: u32,
    ) error{ GpuUploadFailed }!GpuAtlas {
        const h = try platform.vkUploadAtlasRgba8(device, phys_device, cmd_pool, queue, pixels, atlas_w, atlas_h);
        return GpuAtlas{
            .image = h.image,
            .image_view = h.image_view,
            .sampler = h.sampler,
            .memory = h.memory,
            .width = atlas_w,
            .height = atlas_h,
        };
    }

    /// Cast to platform.GpuAtlas for VulkanBackend.drawFrame.
    pub fn asHandles(self: *const GpuAtlas) platform.GpuAtlas {
        return .{ .image = self.image, .image_view = self.image_view, .sampler = self.sampler, .memory = self.memory, .width = self.width, .height = self.height };
    }
};

/// GPU-side image atlas. Stub implementation — actual Vulkan upload mirrors GpuAtlas.upload.
/// The TYPE must exist so the build compiles; real GPU upload is deferred to a GPU integration step.
pub const GpuImageAtlas = struct {
    image: *anyopaque = undefined,
    image_view: *anyopaque = undefined,
    sampler: *anyopaque = undefined,
    memory: *anyopaque = undefined,
    width: u32 = 0,
    height: u32 = 0,

    pub fn upload(
        gpa: std.mem.Allocator,
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        queue: *anyopaque,
        atlas: *const ImageAtlas,
    ) error{ OutOfMemory, GpuUploadFailed }!GpuImageAtlas {
        _ = gpa;
        _ = device;
        _ = phys_device;
        _ = cmd_pool;
        _ = queue;
        _ = atlas;
        // Stub: returns zero-value atlas. Real GPU upload follows same pattern as GpuAtlas.
        return GpuImageAtlas{};
    }

    pub fn deinit(self: *GpuImageAtlas, device: *anyopaque) void {
        _ = self;
        _ = device;
        // Stub: no-op. Real implementation would destroy VkImage/VkImageView/VkSampler.
    }
};

// ---------------------------------------------------------------------------
// M13-04 RD3 — SDF Icon Atlas
// ---------------------------------------------------------------------------

/// CPU-side SDF icon atlas. Generated once at startup from built-in icon paths.
/// Each icon is a 64×64 signed-distance-field bitmap packed in a vertical strip.
pub const SdfAtlas = struct {
    /// Packed SDF pixel data: sdf_icons.ICON_SIZE * sdf_icons.ICON_SIZE * N bytes.
    pixels: []const u8,
    /// Total width of the atlas (fixed 64 for strip layout).
    width: u32,
    /// Total height = ICON_SIZE * ICON_COUNT.
    height: u32,
    /// Mapping from icon name string to atlas UV rect (normalized 0–1).
    entries: std.StringHashMapUnmanaged(platform.Rect09),

    /// Number of icons in the atlas.
    pub fn count(self: *const SdfAtlas) u32 {
        return @intCast(self.entries.count());
    }

    /// Initialize the SDF atlas by generating SDF bitmaps from built-in icon paths.
    pub fn init(alloc: std.mem.Allocator) !SdfAtlas {
        const icon_count = sdf_icons.builtin_icons.len;
        const px = try sdf_icons.generateAllIcons(alloc);
        errdefer alloc.free(px);

        var entries: std.StringHashMapUnmanaged(platform.Rect09) = .empty;
        errdefer entries.deinit(alloc);

        const cell_h_f: f32 = @floatFromInt(sdf_icons.ICON_SIZE);
        const atlas_h_f: f32 = cell_h_f * @as(f32, @floatFromInt(icon_count));

        for (sdf_icons.builtin_icons, 0..) |def, i| {
            const y: f32 = @as(f32, @floatFromInt(i)) * cell_h_f;
            const uv = platform.Rect09{
                .x = 0.0,
                .y = y / atlas_h_f,
                .w = 1.0,
                .h = cell_h_f / atlas_h_f,
            };
            // Duplicate the name so the hashmap owns it.
            const name_copy = try alloc.dupe(u8, def.name);
            errdefer alloc.free(name_copy);
            try entries.put(alloc, name_copy, uv);
        }

        return SdfAtlas{
            .pixels = px,
            .width = sdf_icons.ICON_SIZE,
            .height = sdf_icons.ICON_SIZE * @as(u32, @intCast(icon_count)),
            .entries = entries,
        };
    }

    /// Look up an icon by name. Returns normalized UV rect (0–1 range) or null.
    pub fn lookup(self: *const SdfAtlas, name: []const u8) ?platform.Rect09 {
        return self.entries.get(name);
    }

    pub fn deinit(self: *SdfAtlas, alloc: std.mem.Allocator) void {
        // Free each key in the hashmap.
        var it = self.entries.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
        }
        self.entries.deinit(alloc);
        if (self.pixels.len > 0) {
            alloc.free(self.pixels);
        }
        self.* = .{ .pixels = &.{}, .width = 0, .height = 0, .entries = .empty };
    }
};

/// M13-04 RD3 — GPU-side SDF atlas handle. Mirrors GpuAtlas but uses platform.GpuSdfAtlas deinit.
pub const GpuSdfAtlas = struct {
    image: ?*anyopaque = null,
    image_view: ?*anyopaque = null,
    sampler: ?*anyopaque = null,
    memory: ?*anyopaque = null,
    width: u32 = 0,
    height: u32 = 0,

    /// Upload the SDF atlas to the GPU using VK_FORMAT_R8_UNORM with LINEAR sampling.
    pub fn upload(
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        queue: *anyopaque,
        atlas: *const SdfAtlas,
    ) error{ GpuUploadFailed }!GpuSdfAtlas {
        const h = try platform.vkUploadAtlas(device, phys_device, cmd_pool, queue, atlas.pixels, atlas.width, atlas.height);
        return GpuSdfAtlas{
            .image = h.image,
            .image_view = h.image_view,
            .sampler = h.sampler,
            .memory = h.memory,
            .width = atlas.width,
            .height = atlas.height,
        };
    }

    pub fn deinit(self: *GpuSdfAtlas, device: *anyopaque) void {
        var h = platform.GpuSdfAtlas{
            .image = self.image,
            .image_view = self.image_view,
            .sampler = self.sampler,
            .memory = self.memory,
        };
        h.deinit(device);
        self.* = .{};
    }

    /// Cast to platform.GpuSdfAtlas for VulkanBackend.updateSdfAtlas.
    pub fn asHandles(self: *const GpuSdfAtlas) platform.GpuSdfAtlas {
        return .{ .image = self.image, .image_view = self.image_view, .sampler = self.sampler, .memory = self.memory, .width = self.width, .height = self.height };
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
    out[0] = .{ .rect = .{ .x = r.x, .y = r.y, .w = r.w, .h = w }, .color = col };
    out[1] = .{ .rect = .{ .x = r.x, .y = r.y + r.h - w, .w = r.w, .h = w }, .color = col };
    out[2] = .{ .rect = .{ .x = r.x, .y = r.y + w, .w = w, .h = r.h - 2.0 * w }, .color = col };
    out[3] = .{ .rect = .{ .x = r.x + r.w - w, .y = r.y + w, .w = w, .h = r.h - 2.0 * w }, .color = col };
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
// R42 — Scissor helpers
// ---------------------------------------------------------------------------

/// Convert a floating-point layout Rect to an integer ScissorRect, clamping to [0, max].
/// Floors top-left and ceils bottom-right so that sub-pixel content at the edges is
/// included rather than clipped by integer rounding.
pub fn rectToScissor(r: store_mod.Rect) ScissorRect {
    const x = @max(0, @as(i32, @intFromFloat(@floor(r.x))));
    const y = @max(0, @as(i32, @intFromFloat(@floor(r.y))));
    const x2 = @max(x, @as(i32, @intFromFloat(@ceil(r.x + r.w))));
    const y2 = @max(y, @as(i32, @intFromFloat(@ceil(r.y + r.h))));
    return .{
        .x = x,
        .y = y,
        .w = @intCast(x2 - x),
        .h = @intCast(y2 - y),
    };
}

/// Compute the intersection of two ScissorRects. Returns zero-area if no overlap.
pub fn intersectScissor(a: ScissorRect, b: ScissorRect) ScissorRect {
    const ax0: i64 = a.x;
    const ay0: i64 = a.y;
    const ax1: i64 = ax0 + a.w;
    const ay1: i64 = ay0 + a.h;
    const bx0: i64 = b.x;
    const by0: i64 = b.y;
    const bx1: i64 = bx0 + b.w;
    const by1: i64 = by0 + b.h;
    const ix0 = @max(ax0, bx0);
    const iy0 = @max(ay0, by0);
    const ix1 = @min(ax1, bx1);
    const iy1 = @min(ay1, by1);
    if (ix1 <= ix0 or iy1 <= iy0) return .{ .x = 0, .y = 0, .w = 0, .h = 0 };
    return .{
        .x = @intCast(ix0),
        .y = @intCast(iy0),
        .w = @intCast(ix1 - ix0),
        .h = @intCast(iy1 - iy0),
    };
}

// ---------------------------------------------------------------------------
// R45 — Opacity helper
// ---------------------------------------------------------------------------

/// Multiply the alpha channel of `c` by `factor` (clamped to [0, 1]).
pub fn applyOpacity(col: Color, factor: f32) Color {
    const a = @as(f32, @floatFromInt(col.a)) * std.math.clamp(factor, 0.0, 1.0);
    return .{ .r = col.r, .g = col.g, .b = col.b, .a = @intFromFloat(a) };
}

// ---------------------------------------------------------------------------
// R40 — Style resolution helper
// ---------------------------------------------------------------------------

/// Resolve the effective ComputedStyle by layering pseudo-state overrides.
/// Priority: disabled > active > hover > focus > base.
pub fn resolveStyle(
    base: ComputedStyle,
    overrides: PseudoStyleSet,
    state: PseudoState,
) ComputedStyle {
    var out = base;
    if (state.focus) {
        if (overrides.focus.background) |v| out.background = v;
        if (overrides.focus.text_color) |v| out.text_color = v;
        if (overrides.focus.border_color) |v| out.border_color = v;
        if (overrides.focus.border_width) |v| out.border_width = v;
        if (overrides.focus.radius) |v| out.radius = v;
    }
    if (state.hover) {
        if (overrides.hover.background) |v| out.background = v;
        if (overrides.hover.text_color) |v| out.text_color = v;
        if (overrides.hover.border_color) |v| out.border_color = v;
        if (overrides.hover.border_width) |v| out.border_width = v;
        if (overrides.hover.radius) |v| out.radius = v;
    }
    if (state.active) {
        if (overrides.active.background) |v| out.background = v;
        if (overrides.active.text_color) |v| out.text_color = v;
        if (overrides.active.border_color) |v| out.border_color = v;
        if (overrides.active.border_width) |v| out.border_width = v;
        if (overrides.active.radius) |v| out.radius = v;
    }
    if (state.disabled) {
        if (overrides.disabled.background) |v| out.background = v;
        if (overrides.disabled.text_color) |v| out.text_color = v;
        if (overrides.disabled.border_color) |v| out.border_color = v;
        if (overrides.disabled.border_width) |v| out.border_width = v;
        if (overrides.disabled.radius) |v| out.radius = v;
    }
    return out;
}

// ---------------------------------------------------------------------------
// R46 — Box shadow helper
// ---------------------------------------------------------------------------

/// Emit N filled_rect commands approximating a blurred drop shadow.
pub fn emitShadow(
    cmds: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    element_rect: store_mod.Rect,
    style: ComputedStyle,
    effective_alpha: f32,
) error{OutOfMemory}!void {
    if (style.shadow_blur == 0) return;
    const N: comptime_int = 5;
    const blur = style.shadow_blur;
    const ox = style.shadow_offset_x;
    const oy = style.shadow_offset_y;

    var i: u32 = 0;
    while (i < N) : (i += 1) {
        const t = @as(f32, @floatFromInt(i + 1)) / @as(f32, N + 1);
        const expand = blur * (1.0 - t);
        const shadow_rect = store_mod.Rect{
            .x = element_rect.x + ox - expand,
            .y = element_rect.y + oy - expand,
            .w = element_rect.w + expand * 2,
            .h = element_rect.h + expand * 2,
        };
        const base_alpha = @as(f32, @floatFromInt(style.shadow_color.a));
        const layer_alpha: u8 = @intFromFloat(base_alpha * t * effective_alpha);
        try cmds.append(alloc, .{ .filled_rect = .{
            .rect = toRect09(shadow_rect),
            .color = .{
                .r = style.shadow_color.r,
                .g = style.shadow_color.g,
                .b = style.shadow_color.b,
                .a = layer_alpha,
            },
            .radius = style.radius,
        } });
    }
}

// ---------------------------------------------------------------------------
// M13-03 RD2 — Subpixel atlas (CPU-side RGBA8 packing for subpixel glyphs)
// ---------------------------------------------------------------------------

pub const SubpixelAtlas = struct {
    width: u32 = 0,
    height: u32 = 0,
    generation: u32 = 0,
    _impl: *anyopaque = undefined,

    const SubImpl = struct {
        gpa: std.mem.Allocator,
        bitmap: []u8, // RGBA8, width*height*4 bytes
        width: u32,
        height: u32,
        shelf_x: u32,
        shelf_y: u32,
        shelf_row_h: u32,
        cache: std.AutoHashMap(text_mod.GlyphKey, text_mod.AtlasRect),
    };

    pub fn init(gpa: std.mem.Allocator, width: u32, height: u32) text_mod.AtlasError!SubpixelAtlas {
        const impl = try gpa.create(SubImpl);
        errdefer gpa.destroy(impl);
        const bitmap = try gpa.alloc(u8, @as(usize, width) * height * 4);
        @memset(bitmap, 0);
        impl.* = .{
            .gpa = gpa,
            .bitmap = bitmap,
            .width = width,
            .height = height,
            .shelf_x = 0,
            .shelf_y = 0,
            .shelf_row_h = 0,
            .cache = std.AutoHashMap(text_mod.GlyphKey, text_mod.AtlasRect).init(gpa),
        };
        return SubpixelAtlas{
            .width = width,
            .height = height,
            ._impl = @ptrCast(impl),
        };
    }

    pub fn deinit(self: *SubpixelAtlas) void {
        const impl: *SubImpl = @ptrCast(@alignCast(self._impl));
        const gpa = impl.gpa;
        gpa.free(impl.bitmap);
        impl.cache.deinit();
        gpa.destroy(impl);
    }

    pub fn lookup(self: *SubpixelAtlas, key: text_mod.GlyphKey) ?text_mod.AtlasRect {
        const impl: *SubImpl = @ptrCast(@alignCast(self._impl));
        return impl.cache.get(key);
    }

    /// Pack an RGB subpixel glyph bitmap (width*height*3 bytes) into the atlas.
    /// Returns the atlas rect for UV mapping.
    pub fn insert(self: *SubpixelAtlas, key: text_mod.GlyphKey, w: u32, h: u32, rgb_data: []const u8) text_mod.AtlasError!text_mod.AtlasRect {
        const impl: *SubImpl = @ptrCast(@alignCast(self._impl));

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
            const new_bitmap = try impl.gpa.alloc(u8, @as(usize, new_w) * new_h * 4);
            @memset(new_bitmap, 0);
            var row: u32 = 0;
            while (row < impl.height) : (row += 1) {
                const src = impl.bitmap[@as(usize, row) * impl.width * 4 ..][0 .. impl.width * 4];
                const dst = new_bitmap[@as(usize, row) * new_w * 4 ..][0 .. impl.width * 4];
                @memcpy(dst, src);
            }
            impl.gpa.free(impl.bitmap);
            impl.bitmap = new_bitmap;
            impl.width = new_w;
            impl.height = new_h;
            self.width = new_w;
            self.height = new_h;
            if (impl.shelf_x + w > impl.width) {
                impl.shelf_y += impl.shelf_row_h;
                impl.shelf_x = 0;
                impl.shelf_row_h = 0;
            }
        }

        if (impl.shelf_x + w > impl.width or impl.shelf_y + h > impl.height) {
            return text_mod.AtlasError.GlyphTooLarge;
        }

        const rect = text_mod.AtlasRect{ .x = impl.shelf_x, .y = impl.shelf_y, .w = w, .h = h };

        // Blit RGB glyph data into RGBA atlas: R,G,B from rgb_data, A=255.
        var blit_row: u32 = 0;
        while (blit_row < h) : (blit_row += 1) {
            const src = rgb_data[@as(usize, blit_row) * w * 3 ..][0 .. w * 3];
            const dst_row_start: usize = @as(usize, impl.shelf_y + blit_row) * impl.width * 4 + @as(usize, impl.shelf_x) * 4;
            var x: u32 = 0;
            while (x < w) : (x += 1) {
                const si: usize = @as(usize, x) * 3;
                const di: usize = dst_row_start + @as(usize, x) * 4;
                impl.bitmap[di + 0] = src[si + 0]; // R
                impl.bitmap[di + 1] = src[si + 1]; // G
                impl.bitmap[di + 2] = src[si + 2]; // B
                impl.bitmap[di + 3] = 255;          // A
            }
        }

        impl.shelf_x += w;
        if (h > impl.shelf_row_h) impl.shelf_row_h = h;

        try impl.cache.put(key, rect);
        self.generation +%= 1;
        return rect;
    }

    /// The atlas RGBA8 pixels (width*height*4 bytes), for GPU upload.
    pub fn pixels(self: *SubpixelAtlas) []const u8 {
        const impl: *SubImpl = @ptrCast(@alignCast(self._impl));
        return impl.bitmap;
    }
};

// ---------------------------------------------------------------------------
// Serializer
// ---------------------------------------------------------------------------

// Stack entry for the DFS walk. Either an element to visit, or a sentinel.
const StackEntry = union(enum) {
    element: struct { id: store_mod.ElementId, alpha: f32, translate_x: f32, translate_y: f32 },
    restore_scissor: void,
    clip_rounded_end: void, // M13-02 RD1
};

fn toGradientDir(v: u32) platform.GradientDirection {
    return switch (v) {
        1 => .right,
        2 => .bottom,
        3 => .bottom_right,
        else => .right, // safe default
    };
}

/// Walk a solved Scene depth-first pre-order and emit a flat DrawCommand list.
/// Caller owns the returned slice; free with `alloc`.
/// `font` is the fallback face when scene.font_family is null (acceptance test path).
/// When scene.font_family is set (app path, R60), per-element bold/italic face is selected.
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    atlas: *GlyphAtlas,
    image_atlas: *const ImageAtlas,
    font: *text_mod.Font,
    tokens: Tokens,
    subpixel_atlas: ?*SubpixelAtlas,
    subpixel_text: bool,
    sdf_atlas: ?*const SdfAtlas,
) error{OutOfMemory}![]DrawCommand {
    var list: std.ArrayListUnmanaged(DrawCommand) = .empty;
    errdefer list.deinit(alloc);

    const s = scene.store();
    if (s.live == 0) return list.toOwnedSlice(alloc);

    var stack: std.ArrayListUnmanaged(StackEntry) = .empty;
    defer stack.deinit(alloc);

    // Find root: first valid element with no parent.
    var root_found = false;
    var idx: u32 = 0;
    while (idx < s.gen.items.len) : (idx += 1) {
        const id = store_mod.ElementId{ .index = idx, .gen = s.gen.items[idx] };
        if (!s.isValid(id)) continue;
        if (s.parentOf(id) == null) {
            try stack.append(alloc, .{ .element = .{ .id = id, .alpha = 1.0, .translate_x = 0, .translate_y = 0 } });
            root_found = true;
            break;
        }
    }
    if (!root_found) return list.toOwnedSlice(alloc);

    while (stack.items.len > 0) {
        const entry = stack.pop().?;

        // Handle restore_scissor sentinel.
        if (entry == .restore_scissor) {
            try list.append(alloc, .{ .restore_scissor = {} });
            continue;
        }

        // Handle clip_rounded_end sentinel (RD1).
        if (entry == .clip_rounded_end) {
            try list.append(alloc, .{ .clip_rounded_end = {} });
            continue;
        }

        const id = entry.element.id;
        const parent_alpha = entry.element.alpha;
        const translate_x = entry.element.translate_x;
        const translate_y = entry.element.translate_y;
        const raw_computed = s.get(id).computed;

        // M12 RC1 — sticky positioning draw-time offset.
        // For sticky elements: find the nearest scroll-container ancestor, compute the
        // clamped y, store the delta in _sticky_offset_y, and adjust the drawn position.
        var sticky_dy: f32 = 0;
        if (s.get(id).position == .sticky) {
            // Walk parent chain to find a scrollview.
            var scroll_y_of_container: f32 = 0;
            var container_computed_y: f32 = 0;
            var anc = s.parentOf(id);
            while (anc) |anc_id| {
                if (anc_id.index < scene._kind.items.len and
                    scene._kind.items[anc_id.index] == .scrollview)
                {
                    if (anc_id.index < scene._scroll_state.items.len) {
                        scroll_y_of_container = scene._scroll_state.items[anc_id.index].scroll_y;
                        container_computed_y = s.get(anc_id).computed.y;
                    }
                    break;
                }
                anc = s.parentOf(anc_id);
            }
            const inset_top_px: f32 = switch (s.get(id).inset_top) {
                .px => |v| v,
                else => 0,
            };
            // natural_y is the element's y position relative to the container's viewport top.
            const natural_y = raw_computed.y - container_computed_y - scroll_y_of_container;
            const sticky_clamped_y = @max(natural_y, inset_top_px);
            sticky_dy = sticky_clamped_y - natural_y;
            // Write to _sticky_offset_y for hit-test path.
            if (id.index < scene._sticky_offset_y.items.len) {
                scene._sticky_offset_y.items[id.index] = sticky_dy;
            }
        }

        // R42: Apply scroll translation — offset children's rects when inside a scrollview.
        const computed = store_mod.Rect{
            .x = raw_computed.x - translate_x,
            .y = raw_computed.y - translate_y + sticky_dy,
            .w = raw_computed.w,
            .h = raw_computed.h,
        };

        // Zero-size: skip drawing but still traverse children.
        if (computed.w <= 0 or computed.h <= 0) {
            try pushChildrenReversed(&stack, alloc, s, id, parent_alpha, translate_x, translate_y);
            continue;
        }

        // R40: Resolve pseudo-state and effective style.
        const base_style = scene.styleOf(id).*;
        const pseudo = if (id.index < scene._pseudo.items.len)
            scene._pseudo.items[id.index]
        else
            PseudoState{};

        const overrides: PseudoStyleSet = switch (scene.kindOfIdx(id.index)) {
            .button => theme_mod.buttonPseudo(tokens),
            .input => theme_mod.inputPseudo(tokens),
            .dropdown => theme_mod.dropdownPseudo(tokens),
            .checkbox => theme_mod.checkboxPseudo(tokens),
            else => PseudoStyleSet{},
        };

        const style = resolveStyle(base_style, overrides, pseudo);

        // R45: Accumulate effective alpha.
        const effective_alpha = parent_alpha * style.opacity;

        const kind = scene.kindOfIdx(id.index);

        // Handle scrollview: emit scissor, push restore sentinel below children.
        if (kind == .scrollview) {
            // Draw scrollview background and scrollbar.
            if (style.gradient_direction != 0) {
                try list.append(alloc, .{ .gradient_rect = .{
                    .rect = toRect09(computed),
                    .color_a = toColor09(applyOpacity(tokens.bg_canvas, effective_alpha)),
                    .color_b = toColor09(applyOpacity(tokens.bg_surface, effective_alpha)),
                    .direction = toGradientDir(style.gradient_direction),
                } });
            } else if (style.background.a > 0) {
                try emitFilledRectAA(&list, alloc, toRect09(computed), toColor09(applyOpacity(style.background, effective_alpha)), style.radius);
            }
            if (style.border_width > 0) {
                try list.append(alloc, .{ .border_rect = .{
                    .rect = toRect09(computed),
                    .color = toColor09(applyOpacity(style.border_color, effective_alpha)),
                    .width = style.border_width,
                } });
            }

            // Scrollbar rendering.
            const ss = scene.scrollStateOf(id.index);
            const content_h = ss.content_height;
            const container_h = if (ss.container_height > 0) ss.container_height else computed.h;
            if (content_h > container_h and container_h > 0) {
                const bar_w: f32 = 14.0;
                const track_x = computed.x + computed.w - bar_w;
                const track_y = computed.y;
                const track_h = computed.h;
                try emitFilledRectAA(&list, alloc, .{ .x = track_x, .y = track_y, .w = bar_w, .h = track_h }, .{ .r = 220, .g = 220, .b = 220, .a = 180 }, 3.0);
                const ratio = container_h / content_h;
                const thumb_h = @max(20.0, track_h * ratio);
                const max_scroll = content_h - container_h;
                const scroll_frac = if (max_scroll > 0) ss.scroll_y / max_scroll else 0;
                const thumb_y = track_y + scroll_frac * (track_h - thumb_h);
                try emitFilledRectAA(&list, alloc, .{ .x = track_x, .y = thumb_y, .w = bar_w, .h = thumb_h }, .{ .r = 150, .g = 150, .b = 150, .a = 220 }, 3.0);
            }

            // R42: Emit scissor around children.
            const sr = rectToScissor(computed);
            try list.append(alloc, .{ .set_scissor = sr });

            // Push restore_scissor sentinel FIRST (it will fire LAST, after all children,
            // since the stack is LIFO).
            try stack.append(alloc, .{ .restore_scissor = {} });
            // Then push children (they will be processed before the sentinel).
            // R42 scroll offset: children are offset by scroll_x/scroll_y in addition to
            // any outer translation already applied.
            const child_translate_x = translate_x + ss.scroll_x;
            const child_translate_y = translate_y + ss.scroll_y;
            try pushChildrenReversedWithTranslate(&stack, alloc, s, id, effective_alpha, child_translate_x, child_translate_y);
            continue;
        }

        // R63: Handle textarea — inline multi-line text rendering with scissor.
        if (kind == .textarea) {
            // 1. Background and border.
            if (style.shadow_blur > 0) try emitShadow(&list, alloc, computed, style, effective_alpha);
            if (style.background.a > 0) {
                try emitFilledRectAA(&list, alloc, toRect09(computed), toColor09(applyOpacity(style.background, effective_alpha)), style.radius);
            }
            if (style.border_width > 0) {
                try list.append(alloc, .{ .border_rect = .{
                    .rect = toRect09(computed),
                    .color = toColor09(applyOpacity(style.border_color, effective_alpha)),
                    .width = style.border_width,
                } });
            }

            // 2. Emit scissor for the textarea's rect.
            try list.append(alloc, .{ .set_scissor = rectToScissor(computed) });

            const ts = scene.textareaStateOf(id.index);
            const inp = scene.inputStateOf(id.index);
            const text_content = inp.text.items;
            const ta_font = if (scene.font_family) |fam| fam.face(style.font_bold, style.font_italic) else font;
            const fm = ta_font.metrics(@round(style.font_size * scene.dpi_scale));
            const line_h = fm.ascent + fm.descent + fm.line_gap;

            // Update container_h from layout.
            ts.container_h = computed.h;

            // Ensure at least one line-start entry (line 0 = byte 0).
            const line_count: usize = if (ts.line_starts.items.len > 0) ts.line_starts.items.len else 1;
            ts.content_h = @as(f32, @floatFromInt(line_count)) * line_h;

            // Selection range for later use.
            const sel = scene.selectionOf(id.index).*;
            const sel_r = sel.range();

            // 3. For each line: emit glyph commands + selection highlights.
            // Show placeholder when textarea is empty.
            if (text_content.len == 0) {
                if (scene.textOf(id)) |placeholder| {
                    if (placeholder.len > 0) {
                        var ph_style = style;
                        ph_style.text_color = tokens.text_muted;
                        const ph_rect = store_mod.Rect{
                            .x = computed.x + style.padding.left,
                            .y = computed.y + style.padding.top,
                            .w = computed.w - style.padding.left - style.padding.right,
                            .h = computed.h - style.padding.top - style.padding.bottom,
                        };
                        try emitGlyphs(&list, alloc, id, placeholder, ph_rect, &ph_style, atlas, ta_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                }
            }
            const num_lines = ts.line_starts.items.len;
            if (num_lines > 0) {
                for (ts.line_starts.items, 0..) |line_start, li| {
                    const line_end: u32 = if (li + 1 < num_lines)
                        ts.line_starts.items[li + 1] -| 1 // exclude the '\n'
                    else
                        @intCast(text_content.len);

                    const line_y = computed.y + @as(f32, @floatFromInt(li)) * line_h - ts.scroll_y;
                    // Cull lines outside the visible area.
                    if (line_y + line_h < computed.y or line_y > computed.y + computed.h) continue;

                    const effective_start = if (line_start <= @as(u32, @intCast(text_content.len))) line_start else @as(u32, @intCast(text_content.len));
                    const effective_end = if (line_end <= @as(u32, @intCast(text_content.len))) line_end else @as(u32, @intCast(text_content.len));
                    if (effective_start > effective_end) continue;
                    const line_text = text_content[effective_start..effective_end];

                    const line_rect = store_mod.Rect{
                        .x = computed.x + style.padding.left,
                        .y = line_y,
                        .w = computed.w - style.padding.left - style.padding.right,
                        .h = line_h,
                    };

                    // 3a. Selection highlight for this line.
                    if (!sel.isEmpty() and line_text.len > 0 and
                        sel_r.lo < effective_end + 1 and sel_r.hi > effective_start)
                    {
                        const para_opt = text_mod.layoutParagraphEx(alloc, ta_font, atlas, line_text, @round(style.font_size * scene.dpi_scale), 1e6, scene.font_family) catch null;
                        if (para_opt) |para| {
                            defer alloc.free(para.glyphs);
                            var run_start_x: ?f32 = null;
                            var run_end_x: f32 = 0;
                            for (para.glyphs) |g| {
                                const abs_off = g.byte_offset + effective_start;
                                const in_sel = abs_off >= sel_r.lo and abs_off < sel_r.hi;
                                if (in_sel) {
                                    if (run_start_x == null) run_start_x = g.dest_x;
                                    run_end_x = g.dest_x + g.dest_w;
                                } else if (run_start_x != null) {
                                    try emitFilledRectAA(&list, alloc, .{ .x = computed.x + run_start_x.?, .y = line_y, .w = run_end_x - run_start_x.?, .h = line_h }, .{ .r = tokens.accent.r, .g = tokens.accent.g, .b = tokens.accent.b, .a = 80 }, 0);
                                    run_start_x = null;
                                }
                            }
                            if (run_start_x != null) {
                                try emitFilledRectAA(&list, alloc, .{ .x = computed.x + run_start_x.?, .y = line_y, .w = run_end_x - run_start_x.?, .h = line_h }, .{ .r = tokens.accent.r, .g = tokens.accent.g, .b = tokens.accent.b, .a = 80 }, 0);
                            }
                        }
                    }

                    // 3b. Glyph commands for this line.
                    if (line_text.len > 0) {
                        try emitGlyphs(&list, alloc, id, line_text, line_rect, &style, atlas, ta_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                }
            }

            // 4. Cursor (thin vertical line, 2px wide).
            if (inp.active) {
                const cursor_line = textareaLineOfByte(ts.line_starts.items, inp.cursor);
                const cl_start = if (cursor_line < ts.line_starts.items.len) ts.line_starts.items[cursor_line] else 0;
                const cl_end: u32 = if (cursor_line + 1 < ts.line_starts.items.len)
                    ts.line_starts.items[cursor_line + 1] -| 1
                else
                    @intCast(text_content.len);
                const cl_eff_end = if (cl_end <= @as(u32, @intCast(text_content.len))) cl_end else @as(u32, @intCast(text_content.len));
                const cl_eff_start = if (cl_start <= @as(u32, @intCast(text_content.len))) cl_start else @as(u32, @intCast(text_content.len));
                const line_text_for_cursor = if (cl_eff_start <= cl_eff_end) text_content[cl_eff_start..cl_eff_end] else "";
                const cursor_in_line = if (inp.cursor >= cl_eff_start) inp.cursor - cl_eff_start else 0;
                const px_u16: u16 = text_mod.fontSizePx(@round(style.font_size * scene.dpi_scale));
                const cursor_x = computeTextX(computed.x, line_text_for_cursor, cursor_in_line, px_u16, atlas, ta_font);
                const cursor_y = computed.y + @as(f32, @floatFromInt(cursor_line)) * line_h - ts.scroll_y;
                try list.append(alloc, .{ .filled_rect = .{
                    .rect = .{ .x = cursor_x, .y = cursor_y + 2.0, .w = 1.5, .h = line_h - 4.0 },
                    .color = .{ .r = 30, .g = 30, .b = 30, .a = 220 },
                    .radius = 0,
                } });
            }

            // 5. Restore scissor.
            try list.append(alloc, .{ .restore_scissor = {} });

            // Textarea has no child widgets — do not push children.
            continue;
        }

        // R46: Shadow before background.
        if (style.shadow_blur > 0) {
            try emitShadow(&list, alloc, computed, style, effective_alpha);
        }

        // 1. Background
        if (style.background.a > 0) {
            try emitFilledRectAA(&list, alloc, toRect09(computed), toColor09(applyOpacity(style.background, effective_alpha)), style.radius);
        }

        // 2. Border (skip for checkbox/radio — they draw their own box border in step 4)
        if (style.border_width > 0 and kind != .checkbox and kind != .radio) {
            try list.append(alloc, .{ .border_rect = .{
                .rect = toRect09(computed),
                .color = toColor09(applyOpacity(style.border_color, effective_alpha)),
                .width = style.border_width,
            } });
        }

        // 2.5. Selection highlight (R62) — after background/border, before glyph commands.
        if (kind == .text or kind == .input) {
            const sel = scene.selectionOf(id.index).*;
            if (!sel.isEmpty()) {
                const text_for_sel: []const u8 = blk: {
                    if (kind == .input) {
                        const inp_s = scene.inputStateOf(id.index);
                        if (inp_s.text.items.len == 0) break :blk "";
                        break :blk inp_s.text.items;
                    } else {
                        break :blk scene.textOf(id) orelse "";
                    }
                };
                if (text_for_sel.len > 0) {
                    const sel_font = if (scene.font_family) |fam| fam.face(style.font_bold, style.font_italic) else font;
                    const para_opt = text_mod.layoutParagraphEx(alloc, sel_font, atlas, text_for_sel, @round(style.font_size * scene.dpi_scale), 1e6, scene.font_family) catch null;
                    if (para_opt) |para| {
                        defer alloc.free(para.glyphs);
                        const r = sel.range();
                        var run_start_x: ?f32 = null;
                        var run_end_x: f32 = 0;
                        for (para.glyphs) |g| {
                            const in_sel = g.byte_offset >= r.lo and g.byte_offset < r.hi;
                            if (in_sel) {
                                if (run_start_x == null) run_start_x = g.dest_x;
                                run_end_x = g.dest_x + g.dest_w;
                            } else if (run_start_x != null) {
                                try emitFilledRectAA(&list, alloc, .{ .x = computed.x + run_start_x.?, .y = computed.y, .w = run_end_x - run_start_x.?, .h = computed.h }, .{ .r = tokens.accent.r, .g = tokens.accent.g, .b = tokens.accent.b, .a = 80 }, 0);
                                run_start_x = null;
                            }
                        }
                        // Flush final run.
                        if (run_start_x != null) {
                            try emitFilledRectAA(&list, alloc, .{ .x = computed.x + run_start_x.?, .y = computed.y, .w = run_end_x - run_start_x.?, .h = computed.h }, .{ .r = tokens.accent.r, .g = tokens.accent.g, .b = tokens.accent.b, .a = 80 }, 0);
                        }
                    }
                }
            }
        }

        // 3. Text glyphs (inputs/textarea/checkbox/radio/badge emit in step 4 with custom placement)
        if (kind != .checkbox and kind != .radio and kind != .badge and kind != .input and kind != .textarea) {
            if (scene.textOf(id)) |str| {
                if (str.len > 0) {
                    const elem_font = if (scene.font_family) |fam| fam.face(style.font_bold, style.font_italic) else font;
                    // Buttons: center text horizontally. Use font advance metrics for accuracy.
                    const text_rect = if (kind == .button) blk: {
                        const px_u16: u16 = text_mod.fontSizePx(@round(style.font_size * scene.dpi_scale));
                        const text_w = computeTextX(0, str, @intCast(str.len), px_u16, atlas, elem_font);
                        const offset_x: f32 = if (text_w > 0 and text_w < computed.w)
                            @round((computed.w - text_w) * 0.5)
                        else
                            style.padding.left;
                        break :blk store_mod.Rect{
                            .x = computed.x + offset_x,
                            .y = computed.y,
                            .w = computed.w - offset_x,
                            .h = computed.h,
                        };
                    } else computed;
                    try emitGlyphs(&list, alloc, id, str, text_rect, &style, atlas, elem_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                }
            }
        }

        // 4. Widget-specific rendering.
        switch (kind) {
            .button => {
                // Pseudo-state visual handled via resolveStyle (R40).
            },
            .dropdown => {
                // Bug 2 fix: render selected option label in closed state.
                // The second-pass overlay loop only runs when dd.open; closed state needs
                // the selected label drawn here in the first-pass DFS walk.
                const dd = scene.dropdownStateOf(id.index);
                if (!dd.open and dd.options.items.len > 0 and dd.selected_idx < dd.options.items.len) {
                    const label = dd.options.items[dd.selected_idx].label;
                    if (label.len > 0) {
                        const dd_font = if (scene.font_family) |fam| fam.face(style.font_bold, style.font_italic) else font;
                        try emitGlyphs(&list, alloc, id, label, computed, &style, atlas, dd_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                }
            },
            .input => {
                // Input cursor (R32). Selection highlight handled by R62 block above.
                const inp = scene.inputStateOf(id.index);
                // Text and cursor start at the content area (inside padding).
                const inp_x = computed.x + style.padding.left;
                const inp_content = store_mod.Rect{
                    .x = inp_x,
                    .y = computed.y,
                    .w = computed.w - style.padding.left - style.padding.right,
                    .h = computed.h,
                };
                const inp_font = if (scene.font_family) |fam| fam.face(style.font_bold, style.font_italic) else font;
                if (inp.text.items.len > 0) {
                    try emitGlyphs(&list, alloc, id, inp.text.items, inp_content, &style, atlas, inp_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                } else if (scene.textOf(id)) |placeholder| {
                    // Render placeholder with muted color when input is empty.
                    if (placeholder.len > 0) {
                        var ph_style = style;
                        ph_style.text_color = tokens.text_muted;
                        try emitGlyphs(&list, alloc, id, placeholder, inp_content, &ph_style, atlas, inp_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                }
                if (inp.active) {
                    const px_u16: u16 = text_mod.fontSizePx(@round(style.font_size * scene.dpi_scale));
                    const cursor_x = computeTextX(inp_x, inp.text.items, inp.cursor, px_u16, atlas, inp_font);
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = cursor_x, .y = computed.y + 2.0, .w = 1.5, .h = computed.h - 4.0 },
                        .color = .{ .r = 30, .g = 30, .b = 30, .a = 220 },
                        .radius = 0,
                    } });
                }
            },
            .checkbox => {
                // R70 — Polished checkbox: box + checkmark as two FilledRect tick strokes.
                const st = scene.checkboxStateOf(id.index);
                const S: f32 = @round(style.font_size * scene.dpi_scale); // box side length (revised decision)
                const bx = computed.x;
                const by = computed.y + (computed.h - S) / 2.0;
                // Box background: accent when checked, raised (white) when unchecked so it
                // is visually distinct from the card surface background.
                const bg_col = if (st.checked) tokens.accent else tokens.bg_raised;
                try emitFilledRectAA(&list, alloc, .{ .x = bx, .y = by, .w = S, .h = S }, toColor09(applyOpacity(bg_col, effective_alpha)), 2.0);
                // Box border: focus = blue ring, hover = strong, else default.
                const border_col = if (pseudo.focus) theme_mod.Color.hex(0x0066FF)
                    else if (st.hovered) tokens.border_strong
                    else tokens.border_default;
                const border_w: f32 = if (pseudo.focus) 2.0 else 1.5;
                try list.append(alloc, .{ .border_rect = .{
                    .rect = .{ .x = bx, .y = by, .w = S, .h = S },
                    .color = toColor09(applyOpacity(border_col, effective_alpha)),
                    .width = border_w,
                } });
                if (st.checked) {
                    // Checkmark: short left-down stroke + long right-up stroke.
                    const ck = toColor09(applyOpacity(tokens.accent_text, effective_alpha));
                    const t = S * 0.13; // stroke thickness
                    // Left leg: goes from bottom-left of tick down-right to elbow.
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = bx + S * 0.15, .y = by + S * 0.50, .w = t, .h = S * 0.28 },
                        .color = ck, .radius = 1,
                    } });
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = bx + S * 0.15, .y = by + S * 0.64, .w = S * 0.22, .h = t },
                        .color = ck, .radius = 1,
                    } });
                    // Right leg: goes from elbow up-right to top-right corner.
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = bx + S * 0.33, .y = by + S * 0.25, .w = t, .h = S * 0.42 },
                        .color = ck, .radius = 1,
                    } });
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = bx + S * 0.33, .y = by + S * 0.25, .w = S * 0.38, .h = t },
                        .color = ck, .radius = 1,
                    } });
                }
                // Emit label text to the right of the box.
                if (scene.textOf(id)) |label| {
                    if (label.len > 0) {
                        const label_rect = store_mod.Rect{ .x = computed.x + S + 4.0, .y = computed.y, .w = computed.w - S - 4.0, .h = computed.h };
                        const cb_font = if (scene.font_family) |fam| fam.face(style.font_bold, style.font_italic) else font;
                        try emitGlyphs(&list, alloc, id, label, label_rect, &style, atlas, cb_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                }
            },
            .radio => {
                // R71 — Radio button: outer ring + inner fill + accent dot if selected.
                // Uses scanline circle approximation (GPU renderer ignores FilledRect.radius).
                const rs = scene.radioStateOf(id.index);
                const S: f32 = @round(style.font_size * scene.dpi_scale); // circle diameter
                const r = S / 2.0;
                // Circle center: horizontally left-aligned, vertically centered in the element.
                const ccx = computed.x + r;
                const ccy = computed.y + computed.h / 2.0;
                // Outer filled circle in ring color:
                const ring_col = if (rs.hovered) tokens.border_strong else tokens.border_default;
                try emitFilledCircle(&list, alloc, ccx, ccy, r, toColor09(applyOpacity(ring_col, effective_alpha)));
                // Inner filled circle in surface color (creates visible ring):
                if (r > 2.0) {
                    try emitFilledCircle(&list, alloc, ccx, ccy, r - 2.0, toColor09(applyOpacity(tokens.bg_surface, effective_alpha)));
                }
                // Accent dot if selected:
                if (rs.selected) {
                    const dot_r = r * 0.4;
                    if (dot_r >= 0.5) {
                        try emitFilledCircle(&list, alloc, ccx, ccy, dot_r, toColor09(applyOpacity(tokens.accent, effective_alpha)));
                    }
                }
                // Emit label text to the right of the circle.
                if (scene.textOf(id)) |label| {
                    if (label.len > 0) {
                        const label_rect = store_mod.Rect{ .x = computed.x + S + 4.0, .y = computed.y, .w = computed.w - S - 4.0, .h = computed.h };
                        const r_font = if (scene.font_family) |fam| fam.face(style.font_bold, style.font_italic) else font;
                        try emitGlyphs(&list, alloc, id, label, label_rect, &style, atlas, r_font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                }
            },
            .slider => {
                // R72 — Slider: track + filled portion + thumb.
                const ss = scene.sliderStateOf(id.index);
                const track_h: f32 = 4;
                const thumb_r: f32 = @round(style.font_size * scene.dpi_scale) * 0.5;
                // Track background:
                const track_rect = platform.Rect09{
                    .x = computed.x,
                    .y = computed.y + (computed.h - track_h) / 2.0,
                    .w = computed.w,
                    .h = track_h,
                };
                try emitFilledRectAA(&list, alloc, track_rect, toColor09(applyOpacity(tokens.border_default, effective_alpha)), track_h / 2.0);
                // Filled portion (left of thumb):
                const range = ss.max - ss.min;
                const t = if (range > 0) std.math.clamp((ss.value - ss.min) / range, 0, 1) else 0;
                const filled_rect = platform.Rect09{
                    .x = track_rect.x,
                    .y = track_rect.y,
                    .w = track_rect.w * t,
                    .h = track_h,
                };
                try emitFilledRectAA(&list, alloc, filled_rect, toColor09(applyOpacity(tokens.accent, effective_alpha)), track_h / 2.0);
                // Thumb:
                const thumb_x = computed.x + computed.w * t;
                const thumb_rect = platform.Rect09{
                    .x = thumb_x - thumb_r,
                    .y = computed.y + (computed.h / 2.0) - thumb_r,
                    .w = thumb_r * 2,
                    .h = thumb_r * 2,
                };
                const thumb_color = if (ss.dragging) tokens.accent_hover else tokens.accent;
                try emitFilledRectAA(&list, alloc, thumb_rect, toColor09(applyOpacity(thumb_color, effective_alpha)), thumb_r);
            },
            .image, .icon => {
                // R43: Image/icon rendering.
                // M13-04 RD3: Check icon_name first for SDF icons.
                var icon_rendered = false;
                if (kind == .icon and sdf_atlas != null) {
                    if (scene.iconNameOf(id.index)) |icon_name| {
                        if (sdf_atlas.?.lookup(icon_name)) |uv| {
                            const icon_color = applyOpacity(style.text_color, effective_alpha);
                            try list.append(alloc, .{ .sdf_icon = .{
                                .dst = toRect09(computed),
                                .uv = uv,
                                .color = toColor09(icon_color),
                            } });
                            icon_rendered = true;
                        }
                    }
                }
                if (!icon_rendered) {
                    const img_state = if (id.index < scene._image_state.items.len)
                        scene._image_state.items[id.index]
                    else
                        comp_mod.ImageState{};
                    if (img_state.image_id != 0) {
                        const uv = image_atlas.getRect(img_state.image_id);
                        const tint = applyOpacity(img_state.tint, effective_alpha);
                        try list.append(alloc, .{ .image_rect = .{
                            .dst = toRect09(computed),
                            .uv = .{ .x = uv.uv_x, .y = uv.uv_y, .w = uv.uv_w, .h = uv.uv_h },
                            .tint = toColor09(tint),
                        } });
                    }
                }
            },
            .progress_bar => {
                // R73 — Progress bar: track + fill or indeterminate animation.
                const ps = scene.progressStateOf(id.index);
                const track_h = computed.h;
                // Track background — use border color so it's visible on any canvas.
                try emitFilledRectAA(&list, alloc, toRect09(computed), toColor09(applyOpacity(tokens.border_default, effective_alpha)), track_h / 2.0);
                if (!ps.indeterminate) {
                    const fill_w = computed.w * std.math.clamp(ps.value, 0.0, 1.0);
                    if (fill_w > 0) {
                        try emitFilledRectAA(&list, alloc, .{ .x = computed.x, .y = computed.y, .w = fill_w, .h = track_h }, toColor09(applyOpacity(tokens.accent, effective_alpha)), track_h / 2.0);
                    }
                } else {
                    // Indeterminate: moving 40% fill band.
                    const phase: f32 = @as(f32, @floatFromInt(scene.frame_count % 120)) / 120.0;
                    const fill_w = computed.w * 0.4;
                    const travel = computed.w + fill_w;
                    const fill_x = computed.x - fill_w + travel * phase;
                    try emitFilledRectAA(&list, alloc, .{ .x = fill_x, .y = computed.y, .w = fill_w, .h = track_h }, toColor09(applyOpacity(tokens.accent, effective_alpha)), track_h / 2.0);
                }
            },
            .spinner => {
                // R73 — Spinner: 8 tick marks rotating.
                const N: u32 = 8;
                const cx = computed.x + computed.w / 2.0;
                const cy = computed.y + computed.h / 2.0;
                const r = computed.w * 0.35;
                const tw = computed.w * 0.10;
                const th = computed.w * 0.25;
                // Advance one tick every 10 frames (~8 steps/sec at 80 fps).
                const phase_idx: u32 = @intCast((scene.frame_count / 10) % N);
                var i: u32 = 0;
                while (i < N) : (i += 1) {
                    const angle = @as(f32, @floatFromInt(i)) * (std.math.tau / @as(f32, @floatFromInt(N)));
                    const age: u32 = (i + N - phase_idx) % N;
                    const a_frac: f32 = @as(f32, @floatFromInt(N - age)) / @as(f32, @floatFromInt(N));
                    const tick_alpha = effective_alpha * a_frac;
                    const tx = cx + r * @cos(angle) - tw / 2.0;
                    const ty = cy + r * @sin(angle) - th / 2.0;
                    try emitFilledRectAA(&list, alloc, .{ .x = tx, .y = ty, .w = tw, .h = th }, toColor09(applyOpacity(tokens.accent, tick_alpha)), tw / 2.0);
                }
            },
            .tabs => {
                // R76 — Tabs: render a tab bar at the top, one button per TabItem.
                const ts = scene.tabsStateOf(id.index);
                if (ts.tab_count == 0) {
                    try pushChildrenReversed(&stack, alloc, s, id, effective_alpha, translate_x, translate_y);
                    continue;
                }
                const tab_bar_h: f32 = 36.0;
                const tab_w = computed.w / @as(f32, @floatFromInt(ts.tab_count));
                var child_idx = scene.elements.first_child.items[id.index];
                var tab_i: u32 = 0;
                while (child_idx != store_mod.NONE) : (child_idx = scene.elements.next_sibling.items[child_idx]) {
                    if (child_idx >= scene._kind.items.len) break;
                    if (scene._kind.items[child_idx] != .tab_item) continue;
                    const is_active = tab_i == ts.active_idx;
                    const btn_x = computed.x + @as(f32, @floatFromInt(tab_i)) * tab_w;
                    const btn_rect = platform.Rect09{ .x = btn_x, .y = computed.y, .w = tab_w, .h = tab_bar_h };
                    // Tab button background.
                    const btn_bg = if (is_active) tokens.bg_raised else tokens.bg_surface;
                    try emitFilledRectAA(&list, alloc, btn_rect, toColor09(applyOpacity(btn_bg, effective_alpha)), 0);
                    // Active accent bottom border.
                    if (is_active) {
                        try list.append(alloc, .{ .filled_rect = .{
                            .rect = .{ .x = btn_x, .y = computed.y + tab_bar_h - 2, .w = tab_w, .h = 2 },
                            .color = toColor09(applyOpacity(tokens.accent, effective_alpha)),
                            .radius = 0,
                        } });
                    }
                    // Tab label text.
                    if (scene.textOf(.{ .index = child_idx, .gen = s.gen.items[child_idx] })) |label| {
                        if (label.len > 0) {
                            const label_rect = store_mod.Rect{ .x = btn_x + 8, .y = computed.y, .w = tab_w - 16, .h = tab_bar_h };
                            const label_style = comp_mod.ComputedStyle{ .text_color = tokens.text_body, .font_size = tokens.text_sm };
                            try emitGlyphs(&list, alloc, .{ .index = child_idx, .gen = s.gen.items[child_idx] }, label, label_rect, &label_style, atlas, font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                        }
                    }
                    tab_i += 1;
                }
                // Bottom divider line.
                try list.append(alloc, .{ .filled_rect = .{
                    .rect = .{ .x = computed.x, .y = computed.y + tab_bar_h - 1, .w = computed.w, .h = 1 },
                    .color = toColor09(applyOpacity(tokens.border_subtle, effective_alpha)),
                    .radius = 0,
                } });
            },
            .tab_item => {
                // R76 — Tab item: just a container for content (children rendered normally).
            },
            .accordion => {
                // R77 — Accordion: draw chevron on the first child (header) rect.
                const acc_state = scene.accordionStateOf(id.index);
                const header_child = scene.elements.first_child.items[id.index];
                if (header_child != store_mod.NONE and header_child < s.layout.items.len) {
                    const header_computed = s.get(.{ .index = header_child, .gen = s.gen.items[header_child] }).computed;
                    const chevron_sz: f32 = 8.0;
                    const chevron_x = computed.x + computed.w - 20.0;
                    const chevron_y = header_computed.y + (header_computed.h - chevron_sz) / 2.0;
                    const chev_col = toColor09(applyOpacity(tokens.text_muted, effective_alpha));
                    if (acc_state.open) {
                        // Down chevron: two rect "strokes".
                        try list.append(alloc, .{ .filled_rect = .{ .rect = .{ .x = chevron_x - chevron_sz * 0.5, .y = chevron_y + chevron_sz * 0.3, .w = chevron_sz * 0.6, .h = 2 }, .color = chev_col, .radius = 1 } });
                        try list.append(alloc, .{ .filled_rect = .{ .rect = .{ .x = chevron_x, .y = chevron_y + chevron_sz * 0.3, .w = chevron_sz * 0.6, .h = 2 }, .color = chev_col, .radius = 1 } });
                    } else {
                        // Right chevron.
                        try list.append(alloc, .{ .filled_rect = .{ .rect = .{ .x = chevron_x + chevron_sz * 0.3, .y = chevron_y, .w = 2, .h = chevron_sz * 0.6 }, .color = chev_col, .radius = 1 } });
                        try list.append(alloc, .{ .filled_rect = .{ .rect = .{ .x = chevron_x + chevron_sz * 0.3, .y = chevron_y + chevron_sz * 0.4, .w = 2, .h = chevron_sz * 0.6 }, .color = chev_col, .radius = 1 } });
                    }
                }
            },
            .date_picker => {
                // R78 — DatePicker: input-like appearance + calendar icon.
                const dp = scene.datePickerStateOf(id.index);
                const base_col = if (dp.disabled)
                    toColor09(applyOpacity(tokens.bg_surface, effective_alpha * 0.5))
                else
                    toColor09(applyOpacity(style.background, effective_alpha));
                try emitFilledRectAA(&list, alloc, .{ .x = computed.x, .y = computed.y, .w = computed.w, .h = computed.h }, base_col, style.radius);
                // Border
                if (style.border_width > 0) {
                    try list.append(alloc, .{ .border_rect = .{
                        .rect = .{ .x = computed.x, .y = computed.y, .w = computed.w, .h = computed.h },
                        .color = toColor09(applyOpacity(style.border_color, effective_alpha)),
                        .width = style.border_width,
                    } });
                }
                // Display the selected date text.
                var date_buf: [10]u8 = undefined;
                const date_str: []const u8 = if (dp.value.year > 0) blk: {
                    const s2 = std.fmt.bufPrint(&date_buf, "{d:0>4}-{d:0>2}-{d:0>2}", .{
                        dp.value.year, dp.value.month, dp.value.day,
                    }) catch break :blk "YYYY-MM-DD";
                    break :blk s2;
                } else "YYYY-MM-DD";
                try emitGlyphs(&list, alloc, id, date_str, computed, &style, atlas, font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
            },
            .avatar => {
                // R7B — Avatar: circular frame, image or initials.
                const av = scene.avatarStateOf(id.index);
                const cx = computed.x + computed.w / 2.0;
                const cy = computed.y + computed.h / 2.0;
                const radius_px = computed.w / 2.0;
                if (av.image_id != 0) {
                    // Draw as filled circle with tinted image (quad approximation).
                    const img_rect = image_atlas.getRect(av.image_id);
                    try list.append(alloc, .{ .image_rect = .{
                        .dst = toRect09(computed),
                        .uv = .{ .x = img_rect.uv_x, .y = img_rect.uv_y, .w = img_rect.uv_w, .h = img_rect.uv_h },
                        .tint = toColor09(applyOpacity(.{ .r = 255, .g = 255, .b = 255, .a = 255 }, effective_alpha)),
                    } });
                } else {
                    // Initialscolour based on first initial character.
                    const init_char = av.initials[0];
                    const bg_color = initialsColor(init_char, tokens);
                    try emitFilledRectAA(&list, alloc, .{ .x = computed.x, .y = computed.y, .w = computed.w, .h = computed.h }, toColor09(applyOpacity(bg_color, effective_alpha)), radius_px);
                    // Draw initials text.
                    const init_text: []const u8 = av.initials[0..if (av.initials[1] != 0) @as(usize, 2) else @as(usize, 1)];
                    const init_style = theme_mod.ComputedStyle{
                        .text_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
                        .font_size = @max(10.0, computed.w * 0.35),
                    };
                    try emitGlyphs(&list, alloc, id, init_text, computed, &init_style, atlas, font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                }
                // Circle border.
                try list.append(alloc, .{ .border_rect = .{
                    .rect = .{ .x = computed.x, .y = computed.y, .w = computed.w, .h = computed.h },
                    .color = toColor09(applyOpacity(tokens.border_default, effective_alpha)),
                    .width = 1.5,
                } });
                _ = cx;
                _ = cy;
            },
            .badge => {
                // R7B — Badge: small pill with text label.
                const bs = scene.badgeStateOf(id.index);
                if (bs.text[0] != 0) {
                    const badge_bg = switch (bs.color) {
                        .default => toColor09(applyOpacity(tokens.border_strong, effective_alpha)),
                        .success => toColor09(applyOpacity(tokens.ok, effective_alpha)),
                        .warning => toColor09(applyOpacity(tokens.warn, effective_alpha)),
                        .error_c => toColor09(applyOpacity(tokens.err, effective_alpha)),
                    };
                    try emitFilledRectAA(&list, alloc, .{ .x = computed.x, .y = computed.y, .w = computed.w, .h = computed.h }, badge_bg, computed.h / 2.0);
                    const cnt_style = theme_mod.ComputedStyle{
                        .text_color = .{ .r = 255, .g = 255, .b = 255, .a = 255 },
                        .font_size = style.font_size,
                    };
                    const text_len = std.mem.indexOfScalar(u8, &bs.text, 0) orelse bs.text.len;
                    try emitGlyphs(&list, alloc, id, bs.text[0..text_len], computed, &cnt_style, atlas, font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                }
            },
            .data_table => {
                // R79 — DataTable: header row + virtualized data rows with scissor.
                const ts = scene.tableStateOf(id.index);
                const header_h: f32 = 36.0;
                const header_bg = toColor09(applyOpacity(tokens.bg_surface, effective_alpha));
                const border_col = toColor09(applyOpacity(tokens.border_default, effective_alpha));

                // Scissor to table bounds.
                try list.append(alloc, .{ .set_scissor = rectToScissor(computed) });

                // Header row background.
                try emitFilledRectAA(&list, alloc, .{ .x = computed.x, .y = computed.y, .w = computed.w, .h = header_h }, header_bg, 0);

                // Draw column headers.
                var col_x = computed.x;
                for (ts.columns[0..ts.col_count], 0..) |*col, ci| {
                    const header_label = col.headerSlice();
                    const is_sorted = (ts.sort_dir != .none and ts.sort_col == @as(u8, @intCast(ci)));
                    const hdr_style = theme_mod.ComputedStyle{
                        .text_color = if (is_sorted) tokens.accent else tokens.text_body,
                        .font_size = 13.0,
                        .font_bold = true,
                    };
                    if (header_label.len > 0) {
                        const hdr_rect = store_mod.Rect{ .x = col_x + 4.0, .y = computed.y, .w = col.width_px - 8.0, .h = header_h };
                        try emitGlyphs(&list, alloc, id, header_label, hdr_rect, &hdr_style, atlas, font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                    // Sort indicator: ▲ (asc) or ▼ (desc) after header text.
                    if (is_sorted) {
                        const indicator: []const u8 = if (ts.sort_dir == .asc) "\xe2\x96\xb2" else "\xe2\x96\xbc";
                        const ind_rect = store_mod.Rect{ .x = col_x + 4.0, .y = computed.y, .w = col.width_px - 8.0, .h = header_h };
                        const ind_style = theme_mod.ComputedStyle{ .text_color = tokens.accent, .font_size = 10.0 };
                        // Offset x past header text — approximate by using text-align end via a wide rect
                        _ = ind_rect;
                        // Emit indicator aligned to right side of column header
                        const ind_x = col_x + col.width_px - 16.0;
                        const ind_rect2 = store_mod.Rect{ .x = ind_x, .y = computed.y + 2.0, .w = 14.0, .h = header_h - 4.0 };
                        try emitGlyphs(&list, alloc, id, indicator, ind_rect2, &ind_style, atlas, font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                    }
                    // Column divider.
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = col_x + col.width_px - 1.0, .y = computed.y, .w = 1.0, .h = header_h },
                        .color = border_col,
                        .radius = 0,
                    } });
                    col_x += col.width_px;
                }

                // Header bottom border.
                try list.append(alloc, .{ .filled_rect = .{
                    .rect = .{ .x = computed.x, .y = computed.y + header_h - 1.0, .w = computed.w, .h = 1.0 },
                    .color = border_col,
                    .radius = 0,
                } });

                // Data rows.
                if (ts.rows) |rows_data| {
                    const view_h = computed.h - header_h;
                    const first_row: u32 = @intFromFloat(@max(0.0, ts.scroll_y / ts.row_height));
                    const visible_count: u32 = @as(u32, @intFromFloat(@ceil(view_h / ts.row_height))) + 1;
                    const n_sorted = ts.sorted_indices.items.len;

                    var row_i: u32 = first_row;
                    while (row_i < first_row + visible_count and row_i < n_sorted) : (row_i += 1) {
                        const data_row = ts.sorted_indices.items[row_i];
                        const row_y = computed.y + header_h + @as(f32, @floatFromInt(row_i - first_row)) * ts.row_height - @mod(ts.scroll_y, ts.row_height);

                        // Alternating row background.
                        if (row_i % 2 == 0) {
                            try emitFilledRectAA(&list, alloc, .{ .x = computed.x, .y = row_y, .w = computed.w, .h = ts.row_height }, toColor09(applyOpacity(tokens.bg_surface, effective_alpha * 0.5)), 0);
                        }

                        // Cell text.
                        var cell_x = computed.x;
                        const row_base: [*]u8 = @ptrCast(rows_data.row_ptr);
                        for (ts.columns[0..ts.col_count], 0..) |*col, ci| {
                            var cell_buf: [128]u8 = undefined;
                            const row_ptr: *anyopaque = @ptrCast(row_base + @as(usize, data_row) * rows_data.row_size);
                            const cell_len = rows_data.cell_fn(row_ptr, @intCast(ci), &cell_buf);
                            const cell_text = cell_buf[0..cell_len];
                            if (cell_text.len > 0) {
                                const cell_style = theme_mod.ComputedStyle{
                                    .text_color = tokens.text_body,
                                    .font_size = 13.0,
                                };
                                const cell_rect = store_mod.Rect{ .x = cell_x + 4.0, .y = row_y, .w = col.width_px - 8.0, .h = ts.row_height };
                                try emitGlyphs(&list, alloc, id, cell_text, cell_rect, &cell_style, atlas, font, effective_alpha, scene.dpi_scale, subpixel_atlas, subpixel_text);
                            }
                            cell_x += col.width_px;
                        }

                        // Row bottom border.
                        try list.append(alloc, .{ .filled_rect = .{
                            .rect = .{ .x = computed.x, .y = row_y + ts.row_height - 1.0, .w = computed.w, .h = 1.0 },
                            .color = border_col,
                            .radius = 0,
                        } });
                    }
                }

                // Scrollbar — only when content exceeds view.
                if (ts.rows) |rows_data| {
                    const view_h = computed.h - header_h;
                    const content_h = ts.row_height * @as(f32, @floatFromInt(rows_data.row_count));
                    if (content_h > view_h and view_h > 0) {
                        const sb_w: f32 = 6.0;
                        const sb_x = computed.x + computed.w - sb_w;
                        const thumb_ratio = view_h / content_h;
                        const thumb_h = @max(20.0, view_h * thumb_ratio);
                        const max_scroll = content_h - view_h;
                        const thumb_y = computed.y + header_h + (ts.scroll_y / max_scroll) * (view_h - thumb_h);
                        // Track
                        try emitFilledRectAA(&list, alloc, .{ .x = sb_x, .y = computed.y + header_h, .w = sb_w, .h = view_h }, toColor09(applyOpacity(tokens.bg_surface, effective_alpha)), 3);
                        // Thumb
                        try emitFilledRectAA(&list, alloc, .{ .x = sb_x + 1.0, .y = thumb_y, .w = sb_w - 2.0, .h = thumb_h }, toColor09(applyOpacity(tokens.border_strong, effective_alpha)), 3);
                    }
                }

                // Restore scissor.
                try list.append(alloc, .restore_scissor);
            },
            else => {},
        }

        // RD1: Rounded content clipping for overflow-hidden containers with radius > 0.
        // Skip scrollview/textarea/data_table — they handle their own scissor/clip path.
        if (s.get(id).overflow == .hidden and style.radius > 0 and
            kind != .scrollview and kind != .textarea and kind != .data_table)
        {
            try list.append(alloc, .{ .clip_rounded_begin = .{
                .rect = toRect09(computed),
                .radius_tl = style.radius,
                .radius_tr = style.radius,
                .radius_br = style.radius,
                .radius_bl = style.radius,
            } });
            try stack.append(alloc, .{ .clip_rounded_end = {} });
        }

        try pushChildrenReversed(&stack, alloc, s, id, effective_alpha, translate_x, translate_y);
    }

    // ---------------------------------------------------------------------------
    // Second pass: dropdown overlays (R33 — must render on top of all other elements).
    // ---------------------------------------------------------------------------
    for (0..scene._kind.items.len) |i| {
        if (scene.kindOfIdx(@as(u32, @intCast(i))) != .dropdown) continue;
        const id = store_mod.ElementId{ .index = @as(u32, @intCast(i)), .gen = s.gen.items[i] };
        if (!s.isValid(id)) continue;
        const dd = scene.dropdownStateOf(@as(u32, @intCast(i)));
        if (!dd.open or dd.options.items.len == 0) continue;

        const computed = s.get(id).computed;
        const style = scene.styleOf(id);
        const item_h: f32 = computed.h;
        const panel_w = computed.w;
        const panel_x = computed.x;
        const panel_y = computed.y + computed.h;

        const panel_h = item_h * @as(f32, @floatFromInt(dd.options.items.len));
        try emitFilledRectAA(&list, alloc, .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h }, toColor09(style.background), 2.0);
        try list.append(alloc, .{ .border_rect = .{
            .rect = .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
            .color = toColor09(style.border_color),
            .width = 1.0,
        } });

        for (dd.options.items, 0..) |opt, oi| {
            const oy = panel_y + @as(f32, @floatFromInt(oi)) * item_h;
            const is_highlight = oi == dd.highlight_idx;
            const is_selected = oi == dd.selected_idx;
            if (is_highlight or is_selected) {
                try emitFilledRectAA(&list, alloc, .{ .x = panel_x, .y = oy, .w = panel_w, .h = item_h }, if (is_highlight) .{ .r = 200, .g = 220, .b = 255, .a = 200 } else .{ .r = 220, .g = 235, .b = 255, .a = 150 }, 0);
            }
            if (opt.label.len > 0) {
                const opt_style = scene.styleOf(id);
                const opt_computed = store_mod.Rect{ .x = panel_x + 4.0, .y = oy, .w = panel_w - 8.0, .h = item_h };
                const opt_font = if (scene.font_family) |fam| fam.face(opt_style.font_bold, opt_style.font_italic) else font;
                try emitGlyphs(&list, alloc, id, opt.label, opt_computed, opt_style, atlas, opt_font, 1.0, scene.dpi_scale, subpixel_atlas, subpixel_text);
            }
        }
    }

    return list.toOwnedSlice(alloc);
}

/// Binary-search for the line index whose start is <= `offset`.
/// Returns 0 if line_starts is empty.
fn textareaLineOfByte(line_starts: []const u32, offset: u32) u32 {
    if (line_starts.len == 0) return 0;
    var lo: u32 = 0;
    var hi: u32 = @as(u32, @intCast(line_starts.len));
    while (lo + 1 < hi) {
        const mid = (lo + hi) / 2;
        if (line_starts[mid] <= offset) {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    return lo;
}

/// Compute the X pixel position of a cursor at `cursor_pos` bytes into `text_bytes`.
/// When `font` is non-null uses font advance metrics for accuracy; falls back to atlas
/// bitmap widths when the font is unavailable (e.g. in unit tests with stub fonts).
fn computeTextX(base_x: f32, text_bytes: []const u8, cursor_pos: u32, px: u16, atlas: *GlyphAtlas, font: ?*text_mod.Font) f32 {
    var x = base_x;
    const px_f = @as(f32, @floatFromInt(px));
    var iter = std.unicode.Utf8Iterator{ .bytes = text_bytes, .i = 0 };
    var byte_pos: u32 = 0;
    while (byte_pos < cursor_pos) {
        const cp = iter.nextCodepoint() orelse break;
        const cp_len = std.unicode.utf8CodepointSequenceLength(cp) catch 1;
        byte_pos += @as(u32, @intCast(cp_len));
        if (font) |f| {
            if (f._valid) {
                x += f.advance(cp, px_f);
                continue;
            }
        }
        const key = text_mod.GlyphKey{ .codepoint = cp, .px = px, .variant = .regular };
        if (atlas.lookup(key)) |uv_rect| {
            x += @as(f32, @floatFromInt(uv_rect.w));
        }
    }
    return x;
}

fn pushChildrenReversed(
    stack: *std.ArrayListUnmanaged(StackEntry),
    alloc: std.mem.Allocator,
    s: *store_mod.ElementStore,
    id: store_mod.ElementId,
    alpha: f32,
    translate_x: f32,
    translate_y: f32,
) !void {
    var buf: [256]store_mod.ElementId = undefined;
    var n: usize = 0;
    var it = s.childrenOf(id);
    while (it.next()) |child| {
        if (n < buf.len) {
            buf[n] = child;
        }
        n += 1;
    }

    // M12 RC4 — z-index sort: stable insertion sort by z_index ascending.
    // Only sort when all children fit in buf (i.e. n <= 256).
    // Higher z_index items end up at the end of buf, so they are pushed to the
    // LIFO stack first (in the reversed pass below), making them processed last
    // and drawn on top.
    if (n > 0 and n <= 256) {
        var si: usize = 1;
        while (si < n) : (si += 1) {
            const key = buf[si];
            const key_z = s.get(key).z_index;
            var sj: usize = si;
            while (sj > 0 and s.get(buf[sj - 1]).z_index > key_z) : (sj -= 1) {
                buf[sj] = buf[sj - 1];
            }
            buf[sj] = key;
        }

        // Push in reverse so that the first child (lowest z_index) is on top of the stack
        // (processed first = drawn first = behind). Highest z_index ends up at bottom of
        // the reversed range (processed last = drawn last = on top).
        var i = n;
        while (i > 0) {
            i -= 1;
            try stack.append(alloc, .{ .element = .{ .id = buf[i], .alpha = alpha, .translate_x = translate_x, .translate_y = translate_y } });
        }
    } else if (n > 256) {
        // Too many children for the stack buffer — emit in document order (no sort).
        // Re-walk the child list so we visit all children, not just the first 256.
        var it2 = s.childrenOf(id);
        // Collect into a heap-allocated slice so we can push in reverse for correct
        // painter's-algorithm ordering (first child drawn first = behind later siblings).
        var dyn = try std.ArrayListUnmanaged(store_mod.ElementId).initCapacity(alloc, n);
        defer dyn.deinit(alloc);
        while (it2.next()) |child| {
            try dyn.append(alloc, child);
        }
        var i = dyn.items.len;
        while (i > 0) {
            i -= 1;
            try stack.append(alloc, .{ .element = .{ .id = dyn.items[i], .alpha = alpha, .translate_x = translate_x, .translate_y = translate_y } });
        }
    }
}

fn pushChildrenReversedWithTranslate(
    stack: *std.ArrayListUnmanaged(StackEntry),
    alloc: std.mem.Allocator,
    s: *store_mod.ElementStore,
    id: store_mod.ElementId,
    alpha: f32,
    translate_x: f32,
    translate_y: f32,
) !void {
    return pushChildrenReversed(stack, alloc, s, id, alpha, translate_x, translate_y);
}

/// Deterministic avatar background color from initial character.
/// Uses 4 semantic token colors (INV-4.3: no hex literals).
fn initialsColor(c: u8, tokens: Tokens) Color {
    return switch (c % 4) {
        0 => tokens.accent,
        1 => tokens.ok,
        2 => tokens.warn,
        3 => tokens.err,
        else => unreachable,
    };
}

/// M13-05 RD4 — Emit a filled rect, using anti-aliasing when both dimensions are > 2 px.
/// Falls back to non-AA `filled_rect` for thin rects (w <= 2 or h <= 2) where AA would
/// produce fuzzy edges.
fn emitFilledRectAA(
    list: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    rect: platform.Rect09,
    color: platform.Color09,
    radius: f32,
) error{OutOfMemory}!void {
    if (rect.w <= 2 or rect.h <= 2) {
        try list.append(alloc, .{ .filled_rect = .{
            .rect = rect,
            .color = color,
            .radius = radius,
        } });
    } else {
        try list.append(alloc, .{ .aa_filled_rect = .{
            .rect = rect,
            .color = color,
            .radius = radius,
        } });
    }
}

fn emitFilledCircle(
    list: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    cx: f32,
    cy: f32,
    r: f32,
    color: platform.Color09,
) error{OutOfMemory}!void {
    if (r <= 0) return;
    // M13-05 RD4 — Emit a single anti-aliased filled circle (mode 6) instead of
    // scanline filled_rect approximation. The GPU fragment shader computes the
    // per-pixel distance to the circle edge and applies a 1-px smooth feather.
    try list.append(alloc, .{ .aa_filled_circle = .{
        .center_x = cx,
        .center_y = cy,
        .radius = r,
        .color = color,
    } });
}

/// M13-03 RD2 — Result of subpixel UV resolution.
const ResolvedGlyph = struct { uv: platform.Rect09, mode: u32 };

/// M13-03 RD2 — Resolve subpixel UV and mode for a glyph key.
/// Falls back to regular atlas UVs with mode 1 on failure.
fn resolveSubpixelUv(
    sp_atlas: *SubpixelAtlas,
    key: text_mod.GlyphKey,
    regular_uv: platform.Rect09,
    cp: u21,
    fs_px: f32,
    font: *text_mod.Font,
    sp_atlas_w: f32,
    sp_atlas_h: f32,
) ResolvedGlyph {
    // Check if already in subpixel atlas.
    if (sp_atlas.lookup(key)) |sp_rect| {
        return .{
            .uv = .{
                .x = @as(f32, @floatFromInt(sp_rect.x)) / sp_atlas_w,
                .y = @as(f32, @floatFromInt(sp_rect.y)) / sp_atlas_h,
                .w = @as(f32, @floatFromInt(sp_rect.w)) / sp_atlas_w,
                .h = @as(f32, @floatFromInt(sp_rect.h)) / sp_atlas_h,
            },
            .mode = 3,
        };
    }
    // Lazy-rasterize and insert into subpixel atlas.
    const sp_bmp = font.rasterizeSubpixel(std.heap.page_allocator, cp, fs_px) catch return .{ .uv = regular_uv, .mode = 1 };
    defer std.heap.page_allocator.free(sp_bmp.rgb);
    const sp_rect = sp_atlas.insert(key, sp_bmp.width, sp_bmp.height, sp_bmp.rgb) catch return .{ .uv = regular_uv, .mode = 1 };
    return .{
        .uv = .{
            .x = @as(f32, @floatFromInt(sp_rect.x)) / sp_atlas_w,
            .y = @as(f32, @floatFromInt(sp_rect.y)) / sp_atlas_h,
            .w = @as(f32, @floatFromInt(sp_rect.w)) / sp_atlas_w,
            .h = @as(f32, @floatFromInt(sp_rect.h)) / sp_atlas_h,
        },
        .mode = 3,
    };
}

fn emitGlyphs(
    list: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    id: store_mod.ElementId,
    str: []const u8,
    computed: store_mod.Rect,
    style: *const theme_mod.ComputedStyle,
    atlas: *GlyphAtlas,
    font: *text_mod.Font,
    effective_alpha: f32,
    dpi_scale: f32,
    subpixel_atlas: ?*SubpixelAtlas,
    subpixel_text: bool,
) !void {
    _ = id;
    const atlas_w = @as(f32, @floatFromInt(atlas.width));
    const atlas_h = @as(f32, @floatFromInt(atlas.height));
    if (atlas_w == 0 or atlas_h == 0) return;

    const fs = @round(style.font_size * dpi_scale);
    const px_u16: u16 = text_mod.fontSizePx(fs);
    var pen_x: f32 = computed.x;
    var fm: ?text_mod.FontMetrics = null;
    var baseline_y: f32 = computed.y;
    const text_color = toColor09(applyOpacity(style.text_color, effective_alpha));
    // font_valid: when false, _impl is undefined — guard all calls that dereference _impl.
    // Atlas lookups proceed unconditionally; pen advancement and bearing fall back to
    // atlas-derived values so that tests that pre-populate the atlas still emit glyphs.
    const font_valid = font._valid;

    // M13-03 RD2 — Subpixel activation gate: only for 12-14 px with subpixel_text enabled.
    const use_subpixel = subpixel_text and font_valid and subpixel_atlas != null and fs >= 12 and fs <= 14;
    const sp_atlas_w: f32 = if (subpixel_atlas) |sp| @as(f32, @floatFromInt(sp.width)) else 0;
    const sp_atlas_h: f32 = if (subpixel_atlas) |sp| @as(f32, @floatFromInt(sp.height)) else 0;

    // R44: Text truncation with ellipsis.
    if (style.truncate) {
        // Get ellipsis metrics (only calls font if not already in atlas; safe for stub fonts
        // because preInsertGlyphs pre-populates the ellipsis glyph in tests).
        const em = if (font_valid) atlas.ellipsisMetrics(font, fs) catch null else blk: {
            // Stub font: check whether the ellipsis is already in the atlas.
            const ellipsis_key = text_mod.GlyphKey{ .codepoint = 0x2026, .px = px_u16, .variant = font.variant };
            if (atlas.lookup(ellipsis_key)) |uv_rect| {
                const adv = @as(f32, @floatFromInt(uv_rect.w));
                break :blk text_mod.EllipsisMetrics{ .advance = adv, .glyph_id = 0 };
            }
            break :blk null;
        };
        const ellipsis_advance: f32 = if (em) |e| e.advance else 0;
        const available_w = computed.w - ellipsis_advance;

        var truncated = false;
        var last_x_end: f32 = pen_x;
        var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
        while (iter.nextCodepoint()) |cp| {
            const key = text_mod.GlyphKey{ .codepoint = cp, .px = px_u16, .variant = font.variant };
            const maybe_uv = atlas.lookup(key);
            if (maybe_uv == null) {
                // Glyph not in atlas (e.g. space, or not yet rasterized). Still advance pen.
                if (font_valid) pen_x += font.advance(cp, fs);
                continue;
            }
            const uv_rect = maybe_uv.?;

            const gw = @as(f32, @floatFromInt(uv_rect.w));
            const gh = @as(f32, @floatFromInt(uv_rect.h));
            if (gw == 0 or gh == 0) {
                if (font_valid) pen_x += font.advance(cp, fs);
                continue;
            }

            if (pen_x + gw > computed.x + available_w) {
                truncated = true;
                break;
            }

            if (font_valid and fm == null) {
                fm = font.metrics(fs);
                baseline_y = computed.y + fm.?.ascent;
            }

            const uv = platform.Rect09{
                .x = @as(f32, @floatFromInt(uv_rect.x)) / atlas_w,
                .y = @as(f32, @floatFromInt(uv_rect.y)) / atlas_h,
                .w = gw / atlas_w,
                .h = gh / atlas_h,
            };

            // M13-03 RD2: resolve subpixel UV + mode when active.
            const sp_resolved = if (use_subpixel)
                resolveSubpixelUv(subpixel_atlas.?, key, uv, cp, fs, font, sp_atlas_w, sp_atlas_h)
            else
                ResolvedGlyph{ .uv = uv, .mode = 1 };

            var bearing_bx: f32 = 0;
            var bearing_by: f32 = 0;
            if (font_valid) {
                const b = font.glyphBearing(cp, fs);
                bearing_bx = b.bx;
                bearing_by = b.by;
            }
            try list.append(alloc, .{ .glyph = .{
                .dst = .{ .x = pen_x + bearing_bx, .y = baseline_y + bearing_by, .w = gw, .h = gh },
                .uv = sp_resolved.uv,
                .color = text_color,
                .mode = sp_resolved.mode,
            } });

            if (font_valid) {
                pen_x += font.advance(cp, fs);
            } else {
                pen_x += gw;
            }
            last_x_end = pen_x;
        }

        if (truncated) {
            // Emit ellipsis glyph.
            if (em) |e| {
                const ellipsis_cp: u21 = 0x2026;
                const key = text_mod.GlyphKey{ .codepoint = ellipsis_cp, .px = px_u16, .variant = font.variant };
                if (atlas.lookup(key)) |uv_rect| {
                    const gw = @as(f32, @floatFromInt(uv_rect.w));
                    const gh = @as(f32, @floatFromInt(uv_rect.h));
                    if (gw > 0 and gh > 0) {
                        const uv = platform.Rect09{
                            .x = @as(f32, @floatFromInt(uv_rect.x)) / atlas_w,
                            .y = @as(f32, @floatFromInt(uv_rect.y)) / atlas_h,
                            .w = gw / atlas_w,
                            .h = gh / atlas_h,
                        };
                        var ell_bx: f32 = 0;
                        var ell_by: f32 = 0;
                        if (font_valid) {
                            const eb = font.glyphBearing(0x2026, fs);
                            ell_bx = eb.bx;
                            ell_by = eb.by;
                        }
                        try list.append(alloc, .{ .glyph = .{
                            .dst = .{ .x = last_x_end + ell_bx, .y = baseline_y + ell_by, .w = gw, .h = gh },
                            .uv = uv,
                            .color = text_color,
                        } });
                    }
                } else {
                    // Fallback: emit "..." as three separate period glyphs.
                    _ = e;
                }
            }
        }
        return;
    }

    // Normal (non-truncated) path: emit glyphs already rasterized in the atlas.
    // Glyphs not yet rasterized (e.g. when using a stub font) are skipped but pen still advances.
    var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    while (iter.nextCodepoint()) |cp| {
        const key = text_mod.GlyphKey{ .codepoint = cp, .px = px_u16, .variant = font.variant };
        const maybe_uv2 = atlas.lookup(key);
        if (maybe_uv2 == null) {
            // Glyph not in atlas (e.g. space, or not yet rasterized). Still advance pen.
            if (font_valid) pen_x += font.advance(cp, fs);
            continue;
        }
        const uv_rect = maybe_uv2.?;

        const gw = @as(f32, @floatFromInt(uv_rect.w));
        const gh = @as(f32, @floatFromInt(uv_rect.h));
        if (gw == 0 or gh == 0) {
            if (font_valid) pen_x += font.advance(cp, fs);
            continue;
        }

        // Clip overflow glyphs
        if (pen_x + gw > computed.x + computed.w) break;

        if (font_valid and fm == null) {
            fm = font.metrics(fs);
            baseline_y = computed.y + fm.?.ascent;
        }

        const uv = platform.Rect09{
            .x = @as(f32, @floatFromInt(uv_rect.x)) / atlas_w,
            .y = @as(f32, @floatFromInt(uv_rect.y)) / atlas_h,
            .w = gw / atlas_w,
            .h = gh / atlas_h,
        };

        // M13-03 RD2: resolve subpixel UV + mode when active.
        const sp_resolved = if (use_subpixel)
            resolveSubpixelUv(subpixel_atlas.?, key, uv, cp, fs, font, sp_atlas_w, sp_atlas_h)
        else
            ResolvedGlyph{ .uv = uv, .mode = 1 };

        var bearing_bx: f32 = 0;
        var bearing_by: f32 = 0;
        if (font_valid) {
            const b = font.glyphBearing(cp, fs);
            bearing_bx = b.bx;
            bearing_by = b.by;
        }
        try list.append(alloc, .{ .glyph = .{
            .dst = .{ .x = pen_x + bearing_bx, .y = baseline_y + bearing_by, .w = gw, .h = gh },
            .uv = sp_resolved.uv,
            .color = text_color,
            .mode = sp_resolved.mode,
        } });

        if (font_valid) {
            pen_x += font.advance(cp, fs);
        } else {
            pen_x += gw;
        }
    }
}
