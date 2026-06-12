//! R75 — Modal dialog manager.
//!
//! Owned by the caller. Call `open()` to show and `close()` to hide the modal.
//! Call `buildOverlay()` once per frame while visible to refresh the overlay slot
//! with backdrop + panel draw commands.
//!
//! Dialog content (child widgets) are rendered by the normal Scene traversal.
//! The manager renders only the backdrop and the panel background so the content
//! subtree is visible on top.

const std = @import("std");
const mod01 = @import("../01/types.zig");
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");
const overlay_mod = @import("overlay.zig");

pub const DrawCommand = mod01.DrawCommand;
pub const Tokens = mod05.Tokens;
pub const OverlayId = overlay_mod.OverlayId;
pub const OverlayLayer = overlay_mod.OverlayLayer;
pub const Scene = mod07.Scene;

const NONE: u32 = std.math.maxInt(u32);

pub const DialogManager = struct {
    /// Whether the dialog is currently shown.
    visible: bool = false,
    /// Index of the Scene element used as the dialog content root (NONE if unset).
    content_idx: u32 = NONE,
    /// Index of the element that had focus before the dialog opened (for focus restore).
    return_focus_idx: u32 = NONE,
    overlay_id: OverlayId = 0,
    /// Command slice owned by this manager; freed at the start of each `buildOverlay`.
    current_cmds: ?[]DrawCommand = null,

    /// Allocate an overlay slot.  Must be called once before use.
    pub fn init(overlay: *OverlayLayer) DialogManager {
        return DialogManager{
            .overlay_id = overlay.allocId(),
        };
    }

    /// Show the dialog, optionally trapping focus on `content_idx`.
    pub fn open(self: *DialogManager, content_idx: u32, scene: *Scene) void {
        self.return_focus_idx = scene.focused_idx;
        self.content_idx = content_idx;
        self.visible = true;
        if (content_idx != NONE) {
            scene.setFocus(content_idx);
        }
    }

    /// Hide the dialog and restore focus to the element that was focused before.
    pub fn close(self: *DialogManager, scene: *Scene) void {
        self.visible = false;
        scene.setFocus(self.return_focus_idx);
        self.content_idx = NONE;
        self.return_focus_idx = NONE;
    }

    pub fn isOpen(self: *const DialogManager) bool {
        return self.visible;
    }

    /// Call once per frame.  Rebuilds the overlay slot with the backdrop and panel
    /// background commands.  No-ops when the dialog is closed (clears the slot).
    pub fn buildOverlay(
        self: *DialogManager,
        window_w: f32,
        window_h: f32,
        tokens: Tokens,
        overlay: *OverlayLayer,
        alloc: std.mem.Allocator,
    ) error{OutOfMemory}!void {
        // Free slice from the previous frame.
        if (self.current_cmds) |old| {
            alloc.free(old);
            self.current_cmds = null;
        }

        if (!self.visible) {
            overlay.setSlot(self.overlay_id, &.{});
            return;
        }

        var cmds: std.ArrayList(DrawCommand) = .empty;
        errdefer cmds.deinit(alloc);

        // Semi-transparent backdrop covering the entire window.
        try cmds.append(alloc, .{ .filled_rect = .{
            .rect = .{ .x = 0, .y = 0, .w = window_w, .h = window_h },
            .color = .{ .r = 0, .g = 0, .b = 0, .a = 160 },
            .radius = 0,
        } });

        // Panel background (centred, capped to window with margins).
        const panel_w: f32 = @min(480, window_w - 64);
        const panel_h: f32 = @min(320, window_h - 64);
        const panel_x = (window_w - panel_w) / 2.0;
        const panel_y = (window_h - panel_h) / 2.0;

        try cmds.append(alloc, .{ .filled_rect = .{
            .rect = .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
            .color = .{ .r = tokens.bg_raised.r, .g = tokens.bg_raised.g, .b = tokens.bg_raised.b, .a = 255 },
            .radius = tokens.radius_md,
        } });
        try cmds.append(alloc, .{ .border_rect = .{
            .rect = .{ .x = panel_x, .y = panel_y, .w = panel_w, .h = panel_h },
            .color = .{ .r = tokens.border_default.r, .g = tokens.border_default.g, .b = tokens.border_default.b, .a = 255 },
            .width = 1,
            .radius = tokens.radius_md,
        } });

        const slice = try cmds.toOwnedSlice(alloc);
        self.current_cmds = slice;
        overlay.setSlot(self.overlay_id, slice);
    }

    /// Free the current command slice (call before the manager goes out of scope).
    pub fn deinit(self: *DialogManager, alloc: std.mem.Allocator) void {
        if (self.current_cmds) |cmds| {
            alloc.free(cmds);
            self.current_cmds = null;
        }
    }
};
