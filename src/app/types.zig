//! App layer — public API contract (INV-5.1).
//!
//! Exposes AppOptions, App, and the full event vocabulary (R11).
//! Event types are defined in module 01 (to avoid upward imports) and re-exported here
//! under the names the R11 spec prescribes.

const std = @import("std");
pub const app_impl = @import("app.zig");
pub const events = @import("events.zig");

const mod01 = @import("../01/types.zig");

// ---------------------------------------------------------------------------
// Re-export EventQueue so callers can use it without reaching into events.zig.
// ---------------------------------------------------------------------------
pub const EventQueue = events.EventQueue;

// ---------------------------------------------------------------------------
// Event vocabulary (R11) — canonical definitions live in module 01 (same
// pattern as DrawCommand).  Re-exported here under the public names.
// ---------------------------------------------------------------------------

pub const MouseButton = mod01.MouseButton;
pub const Action      = mod01.InputAction;   // R11 calls this `Action`
pub const Key         = mod01.Key;
pub const Modifiers   = mod01.Modifiers;
pub const Event       = mod01.InputEvent;    // R11 calls this `Event`

// ---------------------------------------------------------------------------
// Application options — canonical definition lives in app.zig (no circular dep).
// ---------------------------------------------------------------------------

pub const WindowOptions = mod01.WindowOptions;
pub const AppOptions = app_impl.AppOptions;

// ---------------------------------------------------------------------------
// App — three-method public API (R10)
// ---------------------------------------------------------------------------

pub const App = struct {
    _inner: app_impl.AppInner,

    pub fn init(gpa: std.mem.Allocator, opts: AppOptions) !App {
        return App{ ._inner = try app_impl.AppInner.init(gpa, opts) };
    }

    pub fn run(self: *App) void {
        self._inner.run();
    }

    pub fn deinit(self: *App) void {
        self._inner.deinit();
    }
};
