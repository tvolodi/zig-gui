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

// ---------------------------------------------------------------------------
// R80 — Navigator re-exports
// ---------------------------------------------------------------------------
pub const Navigator = @import("navigator.zig").Navigator;
pub const ScreenFn = @import("navigator.zig").ScreenFn;
pub const NavEntry = @import("navigator.zig").NavEntry;
pub const PendingNav = @import("navigator.zig").PendingNav;
pub const ScreenEntry = @import("navigator.zig").ScreenEntry;

// ---------------------------------------------------------------------------
// R81 — AppState re-export
// ---------------------------------------------------------------------------
pub const AppState = @import("app_state.zig").AppState;

// ---------------------------------------------------------------------------
// R82 — PersistentSettings re-export
// ---------------------------------------------------------------------------
pub const PersistentSettings = @import("persistent_settings.zig").PersistentSettings;

// ---------------------------------------------------------------------------
// R83 — MultiWindowApp re-exports
// ---------------------------------------------------------------------------
pub const MultiWindowApp = @import("multi_window.zig").MultiWindowApp;
pub const WindowEntry = @import("multi_window.zig").WindowEntry;
pub const WindowId = @import("multi_window.zig").WindowId;
// Note: multi_window.WindowOptions is intentionally not re-exported here because
// types.zig already exports mod01.WindowOptions under that name (R10 API).
// Callers that need the multi-window window-open options use:
//   @import("multi_window.zig").WindowOptions  or
//   app_types.MultiWindowApp ... WindowOptions via multi_window.zig directly.

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
