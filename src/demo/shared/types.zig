//! shared/types.zig — GlobalState and sidebar callback types for the Showcase Demo.
//!
//! Imported by both main.zig and all screen files (no circular dep).

const std = @import("std");
const app_types = @import("app");
pub const Navigator  = app_types.Navigator;
pub const AppInner   = app_types.app_impl.AppInner;

const mod05 = @import("../05/types.zig");
pub const Tokens = mod05.Tokens;

const mod07 = @import("../07/types.zig");
pub const Scene      = mod07.Scene;
pub const CallbackFn = mod07.CallbackFn;

pub const ToastManager  = app_types.ToastManager;
pub const ToastKind     = app_types.ToastKind;
pub const DialogManager = app_types.DialogManager;

// ---------------------------------------------------------------------------
// GlobalState — shared across all screens, stack-allocated in main.zig
// ---------------------------------------------------------------------------

pub const GlobalState = struct {
    nav: *Navigator,
    /// Per-screen ctx opaque pointers (set in main.zig after all ctxs are initialized).
    home_ctx:   ?*anyopaque = null,
    text_ctx:   ?*anyopaque = null,
    forms_ctx:  ?*anyopaque = null,
    data_ctx:   ?*anyopaque = null,
    theme_ctx:  ?*anyopaque = null,
    notif_ctx:  ?*anyopaque = null,
    layout_ctx: ?*anyopaque = null,
    state_ctx:  ?*anyopaque = null,
    m12_ctx:    ?*anyopaque = null,
    m13_ctx:    ?*anyopaque = null,
    /// Toast manager — set by main.zig after ToastManager.init; nil-safe (no-op when null).
    toasts: ?*ToastManager = null,
    /// AppInner pointer — set by main.zig; used by callbacks to read frame_time_ms etc.
    app_inner: ?*AppInner = null,
    /// Persistent sidebar button callback storage.
    sidebar_cbs: SidebarCbs = undefined,
};

// ---------------------------------------------------------------------------
// Sidebar callback — one per navigation target
// ---------------------------------------------------------------------------

pub const SidebarCb = struct {
    global: *GlobalState,
    screen_name: []const u8,

    pub fn onClick(ptr: *anyopaque) void {
        const self: *SidebarCb = @ptrCast(@alignCast(ptr));
        const ctx = ctxForScreen(self.global, self.screen_name);
        self.global.nav.requestPush(self.screen_name, ctx);
    }
};

pub const SidebarCbs = struct {
    home:          SidebarCb,
    text:          SidebarCb,
    forms:         SidebarCb,
    data:          SidebarCb,
    theme:         SidebarCb,
    notifications: SidebarCb,
    layout:        SidebarCb,
    state:         SidebarCb,
    m12:           SidebarCb,
    m13:           SidebarCb,
};

fn ctxForScreen(global: *GlobalState, name: []const u8) ?*anyopaque {
    if (std.mem.eql(u8, name, "home"))          return global.home_ctx;
    if (std.mem.eql(u8, name, "text"))          return global.text_ctx;
    if (std.mem.eql(u8, name, "forms"))         return global.forms_ctx;
    if (std.mem.eql(u8, name, "data"))          return global.data_ctx;
    if (std.mem.eql(u8, name, "theme"))         return global.theme_ctx;
    if (std.mem.eql(u8, name, "notifications")) return global.notif_ctx;
    if (std.mem.eql(u8, name, "layout"))        return global.layout_ctx;
    if (std.mem.eql(u8, name, "state"))         return global.state_ctx;
    if (std.mem.eql(u8, name, "m12"))           return global.m12_ctx;
    if (std.mem.eql(u8, name, "m13"))           return global.m13_ctx;
    return null;
}

/// Wire the 10 sidebar button callbacks for a freshly instantiated scene and highlight
/// the active screen button.
/// Sidebar buttons are always at fixed element indices 2–11 (DFS pre-order:
///   0 = root Row, 1 = Sidebar Column, 2–11 = sidebar buttons, 12 = content Column).
/// `active_btn_idx` is the element index of the currently displayed screen's button (2–11).
/// Bug 4 fix: set accent background + accent_text color on the active button.
pub fn wireSidebarCallbacks(scene: *Scene, global: *GlobalState, tokens: Tokens, active_btn_idx: u32) !void {
    const pairs = [10]struct { idx: u32, cb: *SidebarCb }{
        .{ .idx = 2,  .cb = &global.sidebar_cbs.home },
        .{ .idx = 3,  .cb = &global.sidebar_cbs.text },
        .{ .idx = 4,  .cb = &global.sidebar_cbs.forms },
        .{ .idx = 5,  .cb = &global.sidebar_cbs.data },
        .{ .idx = 6,  .cb = &global.sidebar_cbs.theme },
        .{ .idx = 7,  .cb = &global.sidebar_cbs.notifications },
        .{ .idx = 8,  .cb = &global.sidebar_cbs.layout },
        .{ .idx = 9,  .cb = &global.sidebar_cbs.state },
        .{ .idx = 10, .cb = &global.sidebar_cbs.m12 },
        .{ .idx = 11, .cb = &global.sidebar_cbs.m13 },
    };
    for (pairs) |p| {
        try scene.setButtonCallback(p.idx, CallbackFn{
            .ptr = p.cb,
            .call = SidebarCb.onClick,
        });
        // Inactive buttons: transparent background with muted text so active stands out.
        if (p.idx != active_btn_idx and p.idx < scene._style.items.len) {
            scene._style.items[p.idx].background = tokens.bg_surface;
            scene._style.items[p.idx].text_color = tokens.text_body;
        }
    }
    // Active button: accent background + accent text.
    if (active_btn_idx >= 2 and active_btn_idx <= 11 and active_btn_idx < scene._style.items.len) {
        scene._style.items[active_btn_idx].background = tokens.accent;
        scene._style.items[active_btn_idx].text_color = tokens.accent_text;
    }
}
