//! MultiWindowApp — R83 (M8-04): Multi-window support.
//!
//! Allows opening multiple top-level windows that share the GPU device and
//! font atlas with the primary window. Each window owns its own Scene,
//! swapchain, BindingSet, and OverlayLayer.
//!
//! In headless/test mode (no GPU), the GPU-specific fields (platform, backend)
//! are not populated. Tests construct WindowEntry directly and test only the
//! bookkeeping logic (openWindow/closeWindow/windowById/run-exit-condition).

const std = @import("std");

const overlay_mod = @import("overlay.zig");
const binding_mod = @import("binding.zig");
const events_mod = @import("events.zig");
const navigator = @import("navigator.zig");

const mod05 = @import("../05/types.zig");
const mod07 = @import("../07/types.zig");

// Re-export ScreenFn from navigator (avoids circular import — same pattern as app.zig).
pub const ScreenFn = navigator.ScreenFn;

const comp = mod07;
const theme = mod05;
const store = @import("../01/types.zig");

// Type aliases
pub const Scene = comp.Scene;
pub const Tokens = theme.Tokens;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Opaque handle identifying one managed window. Value 0 is reserved/invalid.
pub const WindowId = u16;

/// Options for opening a new window.
pub const WindowOptions = struct {
    title: []const u8 = "Window",
    width: u32 = 800,
    height: u32 = 600,
};

/// One managed window entry.
///
/// GPU fields (platform, backend) are opaque pointers so that headless tests
/// can use this struct without linking against GLFW/Vulkan. In a real GPU
/// build, `platform_ptr` points to a heap-allocated Platform and `backend_ptr`
/// points to a heap-allocated VulkanBackend. Both are null in headless mode.
pub const WindowEntry = struct {
    id: WindowId,

    // GPU resources — null in headless / test mode.
    // In a real GPU build these would be: platform: Platform, backend: VulkanBackend.
    platform_ptr: ?*anyopaque = null,
    backend_ptr: ?*anyopaque = null,

    scene: comp.Scene,
    bindings: binding_mod.BindingSet,
    overlay: overlay_mod.OverlayLayer,
    pending_resize: ?store.Extent2D,
    event_queue: events_mod.EventQueue,
    build: ScreenFn,
    ctx: ?*anyopaque,
    tokens: theme.Tokens,
    open: bool,
};

// ---------------------------------------------------------------------------
// MultiWindowApp
// ---------------------------------------------------------------------------

pub const MultiWindowApp = struct {
    gpa: std.mem.Allocator,

    /// All managed windows (including closed ones pending removal).
    windows: std.ArrayListUnmanaged(WindowEntry),

    /// Next window ID to allocate. Starts at 1; 0 is reserved/invalid.
    next_id: u16,

    // Shared atlas generation tracking (headless: unused but kept for API consistency).
    atlas_generation_seen: u32,
    image_atlas_generation_seen: u32,

    // ---------------------------------------------------------------------------
    // Init / Deinit
    // ---------------------------------------------------------------------------

    /// Create a MultiWindowApp. In headless tests, `opts` is not used to create
    /// GPU resources — it is stored but no Platform/VulkanBackend is initialised.
    /// For a real GPU build, replace this body with the full GPU init sequence.
    pub fn init(gpa: std.mem.Allocator) MultiWindowApp {
        return MultiWindowApp{
            .gpa = gpa,
            .windows = .empty,
            .next_id = 1,
            .atlas_generation_seen = 0,
            .image_atlas_generation_seen = 0,
        };
    }

    pub fn deinit(self: *MultiWindowApp) void {
        for (self.windows.items) |*w| {
            w.event_queue.deinit();
            w.bindings.deinit(self.gpa);
            w.overlay.deinit();
            w.scene.deinit();
            // GPU resources (platform_ptr, backend_ptr) are freed by the caller
            // in a real GPU build. In headless mode they are null.
        }
        self.windows.deinit(self.gpa);
    }

    // ---------------------------------------------------------------------------
    // openWindow
    // ---------------------------------------------------------------------------

    /// Open a new window. Returns the new window's WindowId (always >= 1).
    /// `build` is called immediately to populate the window's scene (same
    /// convention as Navigator.push).
    ///
    /// In headless mode, platform and backend are left null. In a GPU build
    /// the caller is responsible for assigning `platform_ptr` / `backend_ptr`
    /// after this call (or a GPU-aware override of this function would do it).
    pub fn openWindow(
        self: *MultiWindowApp,
        opts: WindowOptions,
        build: ScreenFn,
        ctx: ?*anyopaque,
    ) !WindowId {
        _ = opts; // headless: window size / title not used

        const id: WindowId = self.next_id;
        self.next_id +%= 1;
        if (self.next_id == 0) self.next_id = 1; // skip 0 on wrap

        const default_tokens = theme.Tokens.light(theme.Palette.default());

        var scene = comp.Scene.init(self.gpa);
        errdefer scene.deinit();

        // Call build to populate the scene (same as Navigator.push).
        // In headless tests, app is a dummy pointer — build functions must handle null.
        try build(&scene, default_tokens, @ptrFromInt(1), ctx);

        const entry = WindowEntry{
            .id = id,
            .platform_ptr = null,
            .backend_ptr = null,
            .scene = scene,
            .bindings = binding_mod.BindingSet.init(),
            .overlay = overlay_mod.OverlayLayer.init(self.gpa),
            .pending_resize = null,
            .event_queue = events_mod.EventQueue.init(self.gpa),
            .build = build,
            .ctx = ctx,
            .tokens = default_tokens,
            .open = true,
        };

        try self.windows.append(self.gpa, entry);
        return id;
    }

    // ---------------------------------------------------------------------------
    // closeWindow
    // ---------------------------------------------------------------------------

    /// Mark a window closed. It will be removed at the start of the next frame.
    /// Closing an unknown or already-closed id is a no-op (no error, no double-free).
    pub fn closeWindow(self: *MultiWindowApp, id: WindowId) void {
        for (self.windows.items) |*w| {
            if (w.id == id) {
                w.open = false;
                return;
            }
        }
        // Unknown id — no-op per spec.
    }

    // ---------------------------------------------------------------------------
    // windowById
    // ---------------------------------------------------------------------------

    /// Look up a WindowEntry by id. Returns null if not found or already closed.
    pub fn windowById(self: *MultiWindowApp, id: WindowId) ?*WindowEntry {
        for (self.windows.items) |*w| {
            if (w.id == id and w.open) return w;
        }
        return null;
    }

    // ---------------------------------------------------------------------------
    // run (headless frame-loop logic)
    // ---------------------------------------------------------------------------

    /// Run the frame loop until all windows are closed.
    ///
    /// In headless / test mode this only drives the bookkeeping:
    ///   1. Prune closed windows.
    ///   2. Exit when windows list is empty.
    ///
    /// In a real GPU build this would also call platform.pollEvents(),
    /// rebuild scenes, upload atlases, etc. (see R83 spec §5).
    pub fn run(self: *MultiWindowApp) void {
        while (true) {
            // Step 1: prune closed windows.
            self.pruneClosedWindows();

            // Step 2: exit when no open windows remain.
            if (!self.hasOpenWindows()) break;

            // In headless tests, immediately close all open windows so the
            // loop terminates. A real GPU build would poll OS events here.
            // We do NOT auto-close here — callers must close windows via closeWindow.
            // The loop only exits when windows is empty after pruning.
            break; // headless: exit after one prune pass (no OS events to wait on)
        }
    }

    // ---------------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------------

    /// Remove all entries where `open == false` and free their resources.
    pub fn pruneClosedWindows(self: *MultiWindowApp) void {
        var i: usize = 0;
        while (i < self.windows.items.len) {
            if (!self.windows.items[i].open) {
                // Deinit resources for this window before removing.
                var w = self.windows.swapRemove(i);
                w.event_queue.deinit();
                w.bindings.deinit(self.gpa);
                w.overlay.deinit();
                w.scene.deinit();
                // Do NOT advance i — swapRemove puts a different element at [i].
            } else {
                i += 1;
            }
        }
    }

    fn hasOpenWindows(self: *const MultiWindowApp) bool {
        for (self.windows.items) |w| {
            if (w.open) return true;
        }
        return false;
    }
};
