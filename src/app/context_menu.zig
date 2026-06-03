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

        var cmds = std.ArrayList(DrawCommand).init(gpa);
        errdefer cmds.deinit();

        // Background panel.
        cmds.append(.{ .quad = .{
            .x = self.pos_x,
            .y = self.pos_y,
            .w = menu_w,
            .h = total_h,
            .color = tokens.bg_surface,
            .radius = radius,
            .border_width = 1.0,
            .border_color = tokens.border_default,
        } }) catch {};

        // Items.
        var cursor_y = self.pos_y + 4.0;
        for (menu.items[0..menu.count], 0..) |*item, i| {
            if (item.separator) {
                // Horizontal rule.
                cmds.append(.{ .quad = .{
                    .x = self.pos_x + 8.0,
                    .y = cursor_y + 4.0,
                    .w = menu_w - 16.0,
                    .h = 1.0,
                    .color = tokens.border_default,
                    .radius = 0,
                    .border_width = 0,
                    .border_color = tokens.border_default,
                } }) catch {};
                cursor_y += sep_h;
                continue;
            }

            const is_highlighted = (i == self.highlight);
            if (is_highlighted) {
                cmds.append(.{ .quad = .{
                    .x = self.pos_x + 2.0,
                    .y = cursor_y,
                    .w = menu_w - 4.0,
                    .h = item_h,
                    .color = tokens.accent,
                    .radius = 4.0,
                    .border_width = 0,
                    .border_color = tokens.accent,
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

                var para = mod02.layoutParagraph(gpa, font, atlas, label, font_size, menu_w - pad_x * 2.0) catch {
                    cursor_y += item_h;
                    continue;
                };
                defer para.deinit(gpa);

                const text_y = cursor_y + (item_h - para.height) * 0.5;
                for (para.glyphs) |g| {
                    cmds.append(.{ .glyph = .{
                        .x = self.pos_x + pad_x + g.x,
                        .y = text_y + g.y,
                        .w = g.w,
                        .h = g.h,
                        .uv_x = g.uv_x,
                        .uv_y = g.uv_y,
                        .uv_w = g.uv_w,
                        .uv_h = g.uv_h,
                        .color = text_color,
                    } }) catch {};
                }
            }
            cursor_y += item_h;
        }

        self.current_cmds = try cmds.toOwnedSlice();
        layer.setSlot(self.overlay_id, self.current_cmds.?);
    }
};
