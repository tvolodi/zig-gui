//! RA0 — M10-01: Error boundary / recovery.
//!
//! ErrorBoundary wraps ScreenFn calls in an error-catch block.
//! On error: stores the error, renders a fallback scene.
//! Panics are NOT caught (see Non-goals in RA0).
//! INV-5.6: uses only Zig's standard anyerror catch — no new dependencies.
//! INV-3.1: buildFallbackScreen uses Scene's arena-backed APIs (no per-widget heap).
//! INV-1.1: enable_error_boundary = false (default) = zero overhead.
//!
//! NOTE: This file does NOT import navigator.zig to avoid a circular dependency.
//! (navigator.zig imports error_boundary.zig; error_boundary.zig imports mod07/mod05
//!  directly instead of going through navigator.zig.)

const std = @import("std");

// Import Scene and Tokens directly from their source modules (not via navigator.zig)
// to break the navigator.zig <-> error_boundary.zig circular dependency.
const mod07 = @import("../07/types.zig");
const mod05 = @import("../05/types.zig");

pub const Scene = mod07.Scene;
pub const Tokens = mod05.Tokens;

/// A function that (re-)builds a scene for one named screen.
/// Must match navigator.ScreenFn exactly (same signature).
pub const ScreenFn = *const fn (
    scene: *Scene,
    tokens: Tokens,
    app: *anyopaque,
    ctx: ?*anyopaque,
) anyerror!void;

pub const ErrorBoundary = struct {
    /// Last error captured by `call`. Null when no error has been captured.
    last_error: ?anyerror = null,
    /// Buffer for the last error message.
    last_message: [256]u8 = undefined,
    last_message_len: usize = 0,

    /// Call `screen_fn` with the given arguments, catching any returned error.
    /// Panics are NOT caught (see Non-goals in RA0).
    /// Returns `true` if the call succeeded; `false` if it returned an error.
    pub fn call(
        self: *ErrorBoundary,
        screen_fn: ScreenFn,
        scene: *Scene,
        tokens: Tokens,
        app: *anyopaque,
        ctx: ?*anyopaque,
    ) bool {
        screen_fn(scene, tokens, app, ctx) catch |err| {
            self.last_error = err;
            const name = @errorName(err);
            const copy_len = @min(name.len, self.last_message.len);
            @memcpy(self.last_message[0..copy_len], name[0..copy_len]);
            self.last_message_len = copy_len;
            return false;
        };
        return true;
    }

    /// Returns the last captured error, or null if none.
    pub fn lastError(self: *const ErrorBoundary) ?anyerror {
        return self.last_error;
    }

    /// Returns a slice into `last_message` describing the last error, or "" if none.
    pub fn lastMessage(self: *const ErrorBoundary) []const u8 {
        if (self.last_error == null) return "";
        return self.last_message[0..self.last_message_len];
    }

    /// Clear the captured error state.
    pub fn clear(self: *ErrorBoundary) void {
        self.last_error = null;
        self.last_message_len = 0;
    }
};

/// Build a minimal fallback scene that shows the error message.
/// Called by Navigator when `call` returns false.
/// Does NOT use markup parsing — builds the scene programmatically via Scene API.
/// INV-3.1: no per-widget heap allocations; uses Scene's arena-backed APIs.
pub fn buildFallbackScreen(
    boundary: *const ErrorBoundary,
    scene: *Scene,
    tokens: Tokens,
) void {
    const mod06 = @import("../06/types.zig");

    // Build a root column element.
    const root_desc = mod06.NodeDesc{
        .tag = "column",
        .attrs = &.{},
        .classes = "",
        .children = &.{},
    };
    const root_id = scene.instantiate(root_desc, tokens) catch return;

    // Title text element: "Something went wrong".
    const title_attr = mod06.Attr{
        .name = "text",
        .value = .{ .literal = "Something went wrong" },
    };
    const title_desc = mod06.NodeDesc{
        .tag = "text",
        .attrs = &.{title_attr},
        .classes = "",
        .children = &.{},
    };
    _ = scene.instantiateUnder(root_id, title_desc, tokens) catch return;

    // Message text element: show error name if available.
    const msg = boundary.lastMessage();
    if (msg.len == 0) return;

    const msg_attr = mod06.Attr{
        .name = "text",
        .value = .{ .literal = "" }, // placeholder; overwritten via setText below
    };
    const msg_desc = mod06.NodeDesc{
        .tag = "text",
        .attrs = &.{msg_attr},
        .classes = "",
        .children = &.{},
    };
    const msg_id = scene.instantiateUnder(root_id, msg_desc, tokens) catch return;
    // Set the actual error text via the index-based setText API.
    scene.setText(msg_id.index, msg);
}
