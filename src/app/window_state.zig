//! RA4 — M10-05: Window state persistence.
//!
//! WindowStateManager saves/restores window position, size, and maximised state
//! via PersistentSettings.
//! INV-5.6: uses GLFW calls already in the approved set.
//! INV-1.1: persist_window_state = false (default) = zero overhead.
//! INV-1.2: GLFW calls work on both Windows and Linux.

const std = @import("std");
// persistent_settings.zig is a named module in build.zig — import via that name.
const persistent_settings = @import("persistent_settings.zig");
pub const PersistentSettings = persistent_settings.PersistentSettings;

const mod01 = @import("../01/types.zig");
pub const Platform = mod01.Platform;

/// A snapshot of window geometry.
pub const SavedWindowState = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,
    maximised: bool,
};

/// Helper struct that reads and writes window geometry to PersistentSettings.
pub const WindowStateManager = struct {
    settings: *PersistentSettings, // borrowed — NOT owned
    key_prefix: [32]u8, // e.g. "win_" → keys: win_x, win_y, win_w, win_h, win_max
    key_prefix_len: usize,

    /// Wrap an existing PersistentSettings. `key_prefix` namespaces the keys.
    /// key_prefix must be <= 28 bytes (prefix + up to 3-char suffix = 31 max).
    pub fn init(settings: *PersistentSettings, key_prefix: []const u8) WindowStateManager {
        var mgr = WindowStateManager{
            .settings = settings,
            .key_prefix = undefined,
            .key_prefix_len = 0,
        };
        const copy_len = @min(key_prefix.len, 28); // max 28 bytes
        @memcpy(mgr.key_prefix[0..copy_len], key_prefix[0..copy_len]);
        mgr.key_prefix_len = copy_len;
        return mgr;
    }

    /// Load saved state. Returns null if any of the five keys is missing.
    pub fn load(self: *const WindowStateManager) ?SavedWindowState {
        var key_buf: [35]u8 = undefined;

        const x = self.settings.getI32(self.makeKey(&key_buf, "x")) orelse return null;
        const y = self.settings.getI32(self.makeKey(&key_buf, "y")) orelse return null;
        const w = self.settings.getU32(self.makeKey(&key_buf, "w")) orelse return null;
        const h = self.settings.getU32(self.makeKey(&key_buf, "h")) orelse return null;
        const maximised = self.settings.getBool(self.makeKey(&key_buf, "max")) orelse return null;

        return SavedWindowState{
            .x = x,
            .y = y,
            .width = w,
            .height = h,
            .maximised = maximised,
        };
    }

    /// Save the given state to settings (marks settings dirty; does NOT flush).
    pub fn save(self: *WindowStateManager, state: SavedWindowState) !void {
        var key_buf: [35]u8 = undefined;

        try self.settings.setI32(self.makeKey(&key_buf, "x"), state.x);
        try self.settings.setI32(self.makeKey(&key_buf, "y"), state.y);
        try self.settings.setU32(self.makeKey(&key_buf, "w"), state.width);
        try self.settings.setU32(self.makeKey(&key_buf, "h"), state.height);
        try self.settings.setBool(self.makeKey(&key_buf, "max"), state.maximised);
    }

    /// Clear all saved keys for this prefix (marks settings dirty).
    pub fn clear(self: *WindowStateManager) void {
        var key_buf: [35]u8 = undefined;
        self.settings.remove(self.makeKey(&key_buf, "x"));
        self.settings.remove(self.makeKey(&key_buf, "y"));
        self.settings.remove(self.makeKey(&key_buf, "w"));
        self.settings.remove(self.makeKey(&key_buf, "h"));
        self.settings.remove(self.makeKey(&key_buf, "max"));
    }

    // -----------------------------------------------------------------------
    // Private helpers
    // -----------------------------------------------------------------------

    /// Build a key string into `buf`, returning a slice.
    fn makeKey(self: *const WindowStateManager, buf: []u8, suffix: []const u8) []const u8 {
        const prefix_len = self.key_prefix_len;
        const suffix_len = suffix.len;
        const total = prefix_len + suffix_len;
        @memcpy(buf[0..prefix_len], self.key_prefix[0..prefix_len]);
        @memcpy(buf[prefix_len..total], suffix);
        return buf[0..total];
    }
};

// -----------------------------------------------------------------------
// Platform helpers
// -----------------------------------------------------------------------

// GLFW bindings used here.
const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cInclude("GLFW/glfw3.h");
});

// Internal GLFW window pointer extraction.
// Platform._impl is a *PlatformImpl (from src/01/types.zig).
// Since PlatformImpl is not exported, we use a minimal mirror of its layout.
// The first field is `window: *c.GLFWwindow` — so casting _impl to *?*anyopaque
// lets us get the window pointer. This is a safe cast because the layout is stable
// (Platform is owned by this codebase) and window_state.zig is in the app layer.
const PlatformImplMirror = extern struct {
    window: ?*anyopaque,
};

fn glfwWindowOf(platform: *Platform) ?*c.GLFWwindow {
    // _impl is always set after Platform.init; @intFromPtr == 0 means uninitialized.
    if (@intFromPtr(platform._impl) == 0) return null;
    const mirror: *const PlatformImplMirror = @ptrCast(@alignCast(platform._impl));
    const w = mirror.window orelse return null;
    return @ptrCast(@alignCast(w));
}

/// Read current window position and size from GLFW via the Platform handle.
pub fn readFromPlatform(platform: *Platform) SavedWindowState {
    const win = glfwWindowOf(platform) orelse return SavedWindowState{
        .x = 0,
        .y = 0,
        .width = 800,
        .height = 600,
        .maximised = false,
    };

    var x: c_int = 0;
    var y: c_int = 0;
    var w: c_int = 0;
    var h: c_int = 0;

    c.glfwGetWindowPos(win, &x, &y);
    c.glfwGetWindowSize(win, &w, &h);
    const maximised = c.glfwGetWindowAttrib(win, c.GLFW_MAXIMIZED) != 0;

    return SavedWindowState{
        .x = @intCast(x),
        .y = @intCast(y),
        .width = @intCast(@max(0, w)),
        .height = @intCast(@max(0, h)),
        .maximised = maximised,
    };
}

/// Apply a saved state to the GLFW window.
/// Must be called before the first frame.
pub fn applyToPlatform(state: SavedWindowState, platform: *Platform) void {
    const win = glfwWindowOf(platform) orelse return;

    if (state.maximised) {
        c.glfwMaximizeWindow(win);
    } else {
        c.glfwSetWindowPos(win, @intCast(state.x), @intCast(state.y));
        c.glfwSetWindowSize(win, @intCast(state.width), @intCast(state.height));
    }
}
