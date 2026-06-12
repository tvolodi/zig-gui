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
// (persistent_settings.zig is in the app.zig module; re-export through app_impl)
// ---------------------------------------------------------------------------
pub const PersistentSettings = app_impl.persistent_settings_mod.PersistentSettings;

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

// ---------------------------------------------------------------------------
// M10 re-exports — pulled from app_impl to avoid multi-module file conflicts.
// (All new M10 .zig files are imported by app.zig, which is module app.zig.
//  types.zig re-exports them via app_impl to keep each file in one module.)
// ---------------------------------------------------------------------------

// RA2 — FileLogger
pub const FileLogger = app_impl.file_logger_mod.FileLogger;

// RA1 — BudgetedArena
pub const BudgetedArena = app_impl.budgeted_arena_mod.BudgetedArena;

// RA3 — showErrorDialog, initOrDialog
pub const showErrorDialog = app_impl.startup_error_mod.showErrorDialog;

// RA4 — WindowStateManager, SavedWindowState
pub const WindowStateManager = app_impl.window_state_mod.WindowStateManager;
pub const SavedWindowState = app_impl.window_state_mod.SavedWindowState;

// RA0 — ErrorBoundary, buildFallbackScreen
pub const ErrorBoundary = app_impl.error_boundary_mod.ErrorBoundary;
pub const buildFallbackScreen = app_impl.error_boundary_mod.buildFallbackScreen;

// R74 — ToastManager / ToastKind (used by demo screens via GlobalState)
pub const ToastManager = @import("toast.zig").ToastManager;
pub const ToastKind    = @import("toast.zig").ToastKind;

// R75 — DialogManager
pub const DialogManager = @import("dialog.zig").DialogManager;

pub const App = struct {
    _inner: app_impl.AppInner,

    pub fn init(gpa: std.mem.Allocator, opts: AppOptions) !App {
        return App{ ._inner = try app_impl.AppInner.init(gpa, opts) };
    }

    pub fn run(self: *App) void {
        self._inner.run();
    }

    pub fn runWithNav(self: *App, nav: *Navigator) void {
        self._inner.runWithNav(nav);
    }

    pub fn deinit(self: *App) void {
        self._inner.deinit();
    }
};
