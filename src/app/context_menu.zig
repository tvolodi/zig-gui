//! R7D — Context-menu manager (Model A: register-by-index).
//!
//! Registration:
//!   const menu_idx = app.context_menu_manager.register(widget_idx, items);
//!
//! Showing:
//!   app.context_menu_manager.openAt(menu_idx, x, y, &overlay, tokens, font, atlas, gpa);
//!
//! The overlay slot is allocated lazily on the first openAt call.

const std = @import("std");
const mod01 = @import("../01/types.zig");
const mod02 = @import("../02/types.zig");
const mod05 = @import("../05/types.zig");
const overlay_mod = @import("overlay.zig");

pub const Tokens = mod05.Tokens;
pub const DrawCommand = mod01.DrawCommand;
pub const OverlayLayer = overlay_mod.OverlayLayer;
pub const OverlayId = overlay_mod.OverlayId;
pub const Font = mod02.Font;
pub const GlyphAtlas = mod02.GlyphAtlas;
pub const FontFamily = @import("font_family.zig").FontFamily;

pub const MAX_MENU_ITEMS: usize = 16;
pub const MAX_REGISTERED_MENUS: usize = 16;
const NONE_U8: u8 = 0xFF;

/// A single item in a context menu.
pub const ContextMenuItem = struct {
    label: [64]u8 = [_]u8{0} ** 64,
    label_len: u8 = 0,
    disabled: bool = false,
    separator: bool = false,
    on_click: ?*const fn () void = null,

    pub fn fromSlice(text: []const u8) ContextMenuItem {
        var item = ContextMenuItem{};
        const copy_len = @min(text.len, item.label.len - 1);
        @memcpy(item.label[0..copy_len], text[0..copy_len]);
        item.label_len = @intCast(copy_len);
        return item;
    }

    pub fn labelSlice(self: *const ContextMenuItem) []const u8 {
        return self.label[0..self.label_len];
    }
};

/// One registered context menu.
pub const ContextMenu = struct {
    items: [MAX_MENU_ITEMS]ContextMenuItem = undefined,
    count: u8 = 0,
    target_idx: u32 = std.math.maxInt(u32),
};

/// Manages a fixed registry of context menus and the active popup.
pub const ContextMenuManager = struct {
    registered: [MAX_REGISTERED_MENUS]ContextMenu = [_]ContextMenu{.{}} ** MAX_REGISTERED_MENUS,
    menu_count: u8 = 0,
    active_menu_idx: u8 = NONE_U8,
    highlight: u8 = NONE_U8,
    pos_x: f32 = 0,
    pos_y: f32 = 0,
    overlay_id: OverlayId = 0,
    overlay_allocated: bool = false,
    current_cmds: ?[]DrawCommand = null,

    /// Register items for a widget (by element index). Returns the menu index.
    /// Returns 0xFF if registry is full.
    pub fn register(
        self: *ContextMenuManager,
        target_idx: u32,
        items: []const ContextMenuItem,
    ) u8 {
        if (self.menu_count >= MAX_REGISTERED_MENUS) return NONE_U8;
        const idx = self.menu_count;
        self.menu_count += 1;
        var menu = ContextMenu{ .target_idx = target_idx };
        const copy_count = @min(items.len, MAX_MENU_ITEMS);
        menu.count = @intCast(copy_count);
        for (0..copy_count) |i| {
            menu.items[i] = items[i];
        }
        self.registered[idx] = menu;
        return idx;
    }

    /// Open the menu at screen position (x, y).
    pub fn openAt(
        self: *ContextMenuManager,
        menu_idx: u8,
        x: f32,
        y: f32,
        layer: *OverlayLayer,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
        gpa: std.mem.Allocator,
    ) !void {
        if (menu_idx >= self.menu_count) return;
        self.active_menu_idx = menu_idx;
        self.pos_x = x;
        self.pos_y = y;
        self.highlight = NONE_U8;
        try self.rebuildOverlay(layer, tokens, font, atlas, gpa);
    }

    /// Close / dismiss the context menu.
    pub fn dismiss(self: *ContextMenuManager, layer: *OverlayLayer, gpa: std.mem.Allocator) void {
        self.active_menu_idx = NONE_U8;
        self.highlight = NONE_U8;
        if (self.current_cmds) |cmds| {
            gpa.free(cmds);
            self.current_cmds = null;
        }
        if (self.overlay_allocated) {
            layer.setSlot(self.overlay_id, &.{});
        }
    }

    pub fn isOpen(self: *const ContextMenuManager) bool {
        return self.active_menu_idx != NONE_U8;
    }

    pub fn deinit(self: *ContextMenuManager, gpa: std.mem.Allocator) void {
        if (self.current_cmds) |cmds| {
            gpa.free(cmds);
            self.current_cmds = null;
        }
    }

    fn ensureOverlaySlot(self: *ContextMenuManager, layer: *OverlayLayer) void {
        if (!self.overlay_allocated) {
            self.overlay_id = layer.allocId();
            self.overlay_allocated = true;
        }
    }

    fn rebuildOverlay(
        self: *ContextMenuManager,
        layer: *OverlayLayer,
        tokens: Tokens,
        font: *Font,
        atlas: *GlyphAtlas,
        gpa: std.mem.Allocator,
    ) !void {
        self.ensureOverlaySlot(layer);

        if (self.current_cmds) |cmds| {
            gpa.free(cmds);
            self.current_cmds = null;
        }

        if (self.active_menu_idx == NONE_U8) {
            layer.setSlot(self.overlay_id, &.{});
            return;
        }

        const menu = &self.registered[self.active_menu_idx];
        const item_h: f32 = 32.0;
        const sep_h: f32 = 9.0;
        const menu_w: f32 = 180.0;
        const pad_x: f32 = 10.0;
        const font_size: f32 = 14.0;
        const radius: f32 = 6.0;

        // Measure total height.
        var total_h: f32 = 8.0; // top/bottom padding
        for (menu.items[0..menu.count]) |item| {
            total_h += if (item.separator) sep_h else item_h;
        }

        var cmds: std.ArrayList(DrawCommand) = .empty;
        errdefer cmds.deinit(gpa);

        // Helper: convert mod05 Color to Color09.
        const C = mod01.Color09;
        const c09 = struct {
            fn f(col: mod05.Color) C {
                return .{ .r = col.r, .g = col.g, .b = col.b, .a = col.a };
            }
        }.f;

        // Background panel.
        cmds.append(gpa, .{ .filled_rect = .{
            .rect = .{ .x = self.pos_x, .y = self.pos_y, .w = menu_w, .h = total_h },
            .color = c09(tokens.bg_surface),
            .radius = radius,
        } }) catch {};
        cmds.append(gpa, .{ .border_rect = .{
            .rect = .{ .x = self.pos_x, .y = self.pos_y, .w = menu_w, .h = total_h },
            .color = c09(tokens.border_default),
            .width = 1.0,
            .radius = radius,
        } }) catch {};

        // Items.
        var cursor_y = self.pos_y + 4.0;
        for (menu.items[0..menu.count], 0..) |*item, i| {
            if (item.separator) {
                // Horizontal rule.
                cmds.append(gpa, .{ .filled_rect = .{
                    .rect = .{ .x = self.pos_x + 8.0, .y = cursor_y + 4.0, .w = menu_w - 16.0, .h = 1.0 },
                    .color = c09(tokens.border_default),
                    .radius = 0,
                } }) catch {};
                cursor_y += sep_h;
                continue;
            }

            const is_highlighted = (i == self.highlight);
            if (is_highlighted) {
                cmds.append(gpa, .{ .filled_rect = .{
                    .rect = .{ .x = self.pos_x + 2.0, .y = cursor_y, .w = menu_w - 4.0, .h = item_h },
                    .color = c09(tokens.accent),
                    .radius = 4.0,
                } }) catch {};
            }

            // Label text.
            const label = item.labelSlice();
            if (label.len > 0) {
                const text_color = if (item.disabled)
                    tokens.text_muted
                else if (is_highlighted)
                    tokens.accent_text
                else
                    tokens.text_body;

                const para = mod02.layoutParagraph(gpa, font, atlas, label, font_size, menu_w - pad_x * 2.0) catch {
                    cursor_y += item_h;
                    continue;
                };
                defer gpa.free(para.glyphs);

                const atlas_w = @as(f32, @floatFromInt(atlas.width));
                const atlas_h_f = @as(f32, @floatFromInt(atlas.height));
                const text_y = cursor_y + (item_h - para.extent.h) * 0.5;
                for (para.glyphs) |g| {
                    if (g.dest_w == 0 or g.dest_h == 0) continue;
                    const uv_x = @as(f32, @floatFromInt(g.uv.x)) / atlas_w;
                    const uv_y = @as(f32, @floatFromInt(g.uv.y)) / atlas_h_f;
                    const uv_w = g.dest_w / atlas_w;
                    const uv_h = g.dest_h / atlas_h_f;
                    cmds.append(gpa, .{ .glyph = .{
                        .dst = .{ .x = self.pos_x + pad_x + g.dest_x, .y = text_y + g.dest_y, .w = g.dest_w, .h = g.dest_h },
                        .uv = .{ .x = uv_x, .y = uv_y, .w = uv_w, .h = uv_h },
                        .color = c09(text_color),
                    } }) catch {};
                }
            }
            cursor_y += item_h;
        }

        self.current_cmds = try cmds.toOwnedSlice(gpa);
        layer.setSlot(self.overlay_id, self.current_cmds.?);
    }
};
