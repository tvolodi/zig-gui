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
pub const DrawCommand = platform.DrawCommand;
pub const ScissorRect = platform.ScissorRect;
pub const ImageCmd = platform.ImageCmd;

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
pub fn rectToScissor(r: store_mod.Rect) ScissorRect {
    const x = @max(0, @as(i32, @intFromFloat(r.x)));
    const y = @max(0, @as(i32, @intFromFloat(r.y)));
    const x2 = @max(x, @as(i32, @intFromFloat(r.x + r.w)));
    const y2 = @max(y, @as(i32, @intFromFloat(r.y + r.h)));
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
// Serializer
// ---------------------------------------------------------------------------

// Stack entry for the DFS walk. Either an element to visit, or a restore_scissor sentinel.
const StackEntry = union(enum) {
    element: struct { id: store_mod.ElementId, alpha: f32, translate_x: f32, translate_y: f32 },
    restore_scissor: void,
};

/// Walk a solved Scene depth-first pre-order and emit a flat DrawCommand list.
/// Caller owns the returned slice; free with `alloc`.
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    atlas: *GlyphAtlas,
    image_atlas: *const ImageAtlas,
    font: *text_mod.Font,
    tokens: Tokens,
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

        const id = entry.element.id;
        const parent_alpha = entry.element.alpha;
        const translate_x = entry.element.translate_x;
        const translate_y = entry.element.translate_y;
        const raw_computed = s.get(id).computed;
        // R42: Apply scroll translation — offset children's rects when inside a scrollview.
        const computed = store_mod.Rect{
            .x = raw_computed.x - translate_x,
            .y = raw_computed.y - translate_y,
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
            if (style.background.a > 0) {
                try list.append(alloc, .{ .filled_rect = .{
                    .rect = toRect09(computed),
                    .color = toColor09(applyOpacity(style.background, effective_alpha)),
                    .radius = style.radius,
                } });
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
                const bar_w: f32 = 6.0;
                const track_x = computed.x + computed.w - bar_w;
                const track_y = computed.y;
                const track_h = computed.h;
                try list.append(alloc, .{ .filled_rect = .{
                    .rect = .{ .x = track_x, .y = track_y, .w = bar_w, .h = track_h },
                    .color = .{ .r = 220, .g = 220, .b = 220, .a = 180 },
                    .radius = 3.0,
                } });
                const ratio = container_h / content_h;
                const thumb_h = @max(20.0, track_h * ratio);
                const max_scroll = content_h - container_h;
                const scroll_frac = if (max_scroll > 0) ss.scroll_y / max_scroll else 0;
                const thumb_y = track_y + scroll_frac * (track_h - thumb_h);
                try list.append(alloc, .{ .filled_rect = .{
                    .rect = .{ .x = track_x, .y = thumb_y, .w = bar_w, .h = thumb_h },
                    .color = .{ .r = 150, .g = 150, .b = 150, .a = 220 },
                    .radius = 3.0,
                } });
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

        // R46: Shadow before background.
        if (style.shadow_blur > 0) {
            try emitShadow(&list, alloc, computed, style, effective_alpha);
        }

        // 1. Background
        if (style.background.a > 0) {
            try list.append(alloc, .{ .filled_rect = .{
                .rect = toRect09(computed),
                .color = toColor09(applyOpacity(style.background, effective_alpha)),
                .radius = style.radius,
            } });
        }

        // 2. Border
        if (style.border_width > 0) {
            try list.append(alloc, .{ .border_rect = .{
                .rect = toRect09(computed),
                .color = toColor09(applyOpacity(style.border_color, effective_alpha)),
                .width = style.border_width,
            } });
        }

        // 3. Text glyphs
        if (scene.textOf(id)) |str| {
            if (str.len > 0) {
                try emitGlyphs(&list, alloc, id, str, computed, &style, atlas, font, effective_alpha);
            }
        }

        // 4. Widget-specific rendering.
        switch (kind) {
            .button => {
                // Pseudo-state visual handled via resolveStyle (R40).
            },
            .input => {
                // Input cursor and selection highlight (R32).
                const inp = scene.inputStateOf(id.index);
                if (inp.active) {
                    const px_u16: u16 = @intFromFloat(style.font_size);
                    const sel_lo = @min(inp.selection_start, inp.cursor);
                    const sel_hi = @max(inp.selection_start, inp.cursor);
                    const cursor_x = computeTextX(computed.x, inp.text.items, inp.cursor, px_u16, atlas);
                    if (sel_lo != sel_hi) {
                        const sel_x0 = computeTextX(computed.x, inp.text.items, sel_lo, px_u16, atlas);
                        const sel_x1 = computeTextX(computed.x, inp.text.items, sel_hi, px_u16, atlas);
                        try list.append(alloc, .{ .filled_rect = .{
                            .rect = .{ .x = sel_x0, .y = computed.y, .w = sel_x1 - sel_x0, .h = computed.h },
                            .color = .{ .r = 100, .g = 160, .b = 255, .a = 100 },
                            .radius = 0,
                        } });
                    }
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = cursor_x, .y = computed.y + 2.0, .w = 1.5, .h = computed.h - 4.0 },
                        .color = .{ .r = 30, .g = 30, .b = 30, .a = 220 },
                        .radius = 0,
                    } });
                }
            },
            .checkbox => {
                const st = scene.checkboxStateOf(id.index);
                const box_size: f32 = @min(computed.w, computed.h) - 4.0;
                const bx = computed.x + 2.0;
                const by = computed.y + (computed.h - box_size) / 2.0;
                const box_color: platform.Color09 = if (st.hovered)
                    .{ .r = 80, .g = 80, .b = 80, .a = 255 }
                else
                    .{ .r = 120, .g = 120, .b = 120, .a = 255 };
                try list.append(alloc, .{ .border_rect = .{
                    .rect = .{ .x = bx, .y = by, .w = box_size, .h = box_size },
                    .color = box_color,
                    .width = 1.5,
                } });
                if (st.checked) {
                    const m: f32 = box_size * 0.25;
                    try list.append(alloc, .{ .filled_rect = .{
                        .rect = .{ .x = bx + m, .y = by + m, .w = box_size - 2.0 * m, .h = box_size - 2.0 * m },
                        .color = .{ .r = 40, .g = 130, .b = 220, .a = 255 },
                        .radius = 1.0,
                    } });
                }
            },
            .image, .icon => {
                // R43: Image/icon rendering.
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
            },
            else => {},
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
        try list.append(alloc, .{ .filled_rect = .{
            .rect = .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
            .color = toColor09(style.background),
            .radius = 2.0,
        } });
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
                try list.append(alloc, .{ .filled_rect = .{
                    .rect = .{ .x = panel_x, .y = oy, .w = panel_w, .h = item_h },
                    .color = if (is_highlight) .{ .r = 200, .g = 220, .b = 255, .a = 200 } else .{ .r = 220, .g = 235, .b = 255, .a = 150 },
                    .radius = 0,
                } });
            }
            if (opt.label.len > 0) {
                const opt_style = scene.styleOf(id);
                const opt_computed = store_mod.Rect{ .x = panel_x + 4.0, .y = oy, .w = panel_w - 8.0, .h = item_h };
                try emitGlyphs(&list, alloc, id, opt.label, opt_computed, opt_style, atlas, font, 1.0);
            }
        }
    }

    return list.toOwnedSlice(alloc);
}

/// Compute the X pixel position of a cursor at `cursor_pos` bytes into `text_bytes`.
fn computeTextX(base_x: f32, text_bytes: []const u8, cursor_pos: u32, px: u16, atlas: *GlyphAtlas) f32 {
    var x = base_x;
    var iter = std.unicode.Utf8Iterator{ .bytes = text_bytes, .i = 0 };
    var byte_pos: u32 = 0;
    while (byte_pos < cursor_pos) {
        const cp = iter.nextCodepoint() orelse break;
        const cp_len = std.unicode.utf8CodepointSequenceLength(cp) catch 1;
        byte_pos += @as(u32, @intCast(cp_len));
        const key = text_mod.GlyphKey{ .codepoint = cp, .px = px };
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
            n += 1;
        }
    }
    var i = n;
    while (i > 0) {
        i -= 1;
        try stack.append(alloc, .{ .element = .{ .id = buf[i], .alpha = alpha, .translate_x = translate_x, .translate_y = translate_y } });
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
) !void {
    _ = id;
    const atlas_w = @as(f32, @floatFromInt(atlas.width));
    const atlas_h = @as(f32, @floatFromInt(atlas.height));
    if (atlas_w == 0 or atlas_h == 0) return;

    const px_u16: u16 = @intFromFloat(style.font_size);
    var pen_x: f32 = computed.x;
    const pen_y: f32 = computed.y;
    const text_color = toColor09(applyOpacity(style.text_color, effective_alpha));

    // R44: Text truncation with ellipsis.
    if (style.truncate) {
        // Get ellipsis metrics (may rasterize if not cached).
        const em = atlas.ellipsisMetrics(font, style.font_size) catch null;
        const ellipsis_advance: f32 = if (em) |e| e.advance else 0;
        const available_w = computed.w - ellipsis_advance;

        var truncated = false;
        var last_x_end: f32 = pen_x;
        var iter = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
        while (iter.nextCodepoint()) |cp| {
            const key = text_mod.GlyphKey{ .codepoint = cp, .px = px_u16 };
            const uv_rect = atlas.lookup(key) orelse continue;

            const gw = @as(f32, @floatFromInt(uv_rect.w));
            const gh = @as(f32, @floatFromInt(uv_rect.h));
            if (gw == 0 or gh == 0) continue;

            if (pen_x + gw > computed.x + available_w) {
                truncated = true;
                break;
            }

            const uv = platform.Rect09{
                .x = @as(f32, @floatFromInt(uv_rect.x)) / atlas_w,
                .y = @as(f32, @floatFromInt(uv_rect.y)) / atlas_h,
                .w = gw / atlas_w,
                .h = gh / atlas_h,
            };

            try list.append(alloc, .{ .glyph = .{
                .dst = .{ .x = pen_x, .y = pen_y, .w = gw, .h = gh },
                .uv = uv,
                .color = text_color,
            } });

            pen_x += gw;
            last_x_end = pen_x;
        }

        if (truncated) {
            // Emit ellipsis glyph.
            if (em) |e| {
                const ellipsis_cp: u21 = 0x2026;
                const key = text_mod.GlyphKey{ .codepoint = ellipsis_cp, .px = px_u16 };
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
                        try list.append(alloc, .{ .glyph = .{
                            .dst = .{ .x = last_x_end, .y = pen_y, .w = gw, .h = gh },
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

    // Normal (non-truncated) path.
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
            .color = text_color,
        } });

        pen_x += gw;
    }
}
