//! 01 — Platform spike — types.zig
//!
//! Contract (INV-5.1): match the PUBLIC METHOD SIGNATURES below. Unlike the data-oriented
//! modules (03/04), the struct field layout here is NOT part of the contract — Platform and
//! VulkanBackend wrap C libraries (GLFW, Vulkan) and may lay out internal fields however the
//! implementation needs. Implement the stubbed bodies per spec.md; do not change signatures.
//!
//! Depends ONLY on std (this module is below module 03 in build order, so it may NOT import
//! the element store's geometry types — see spec.md note 2). GLFW and Vulkan are pulled in
//! by the implementation via @cImport; their handle types are not exposed in this contract.

const std = @import("std");

// ---------------------------------------------------------------------------
// Local types (module 01 owns these; it cannot use module 03's Size — spec note 2)
// ---------------------------------------------------------------------------

/// Pixel dimensions of the framebuffer / window. Distinct from module 03's layout `Size`.
pub const Extent2D = struct { width: u32, height: u32 };

/// Linear RGBA in 0..1. Used only for the spike's clear color.
pub const Color = struct { r: f32, g: f32, b: f32, a: f32 = 1.0 };

pub const WindowOptions = struct {
    title: [:0]const u8 = "spike",
    width: u32 = 960,
    height: u32 = 600,
};

pub const PlatformError = error{
    GlfwInitFailed,
    VulkanUnavailable,
    WindowCreationFailed,
    SurfaceCreationFailed,
};

pub const BackendError = error{
    NoSuitableDevice,
    InstanceCreationFailed,
    DeviceCreationFailed,
    SwapchainCreationFailed,
    ShaderLoadFailed,
};

// ---------------------------------------------------------------------------
// Input event vocabulary (R11 + RB3 + RB5)
// ---------------------------------------------------------------------------

pub const MouseButton = enum { left, right, middle };
pub const InputAction = enum { press, release };

pub const InputEvent = union(enum) {
    mouse_move:          struct { x: f32, y: f32 },
    mouse_button:        struct { button: MouseButton, action: InputAction, x: f32, y: f32 },
    /// RB3 — Synthesized by dispatchEvents; never pushed directly by GLFW callbacks.
    mouse_button_double: struct { button: MouseButton, x: f32, y: f32 },
    scroll:              struct { dx: f32, dy: f32 },
    /// RB5 — Synthesized from trackpad fractional scroll input.
    gesture_swipe:       struct { dx: f32, dy: f32 },
    /// RB5 — Synthesized when |dy| > PINCH_THRESHOLD with dx==0. scale_delta > 1 = zoom in.
    gesture_pinch:       struct { scale_delta: f32 },
    key:                 struct { key: Key, action: InputAction, mods: Modifiers },
    char:                struct { codepoint: u21 },
};

pub const Key = enum { enter, escape, tab, backspace, delete, left, right, up, down,
    home, end, page_up, page_down, left_shift, right_shift, left_ctrl, right_ctrl,
    left_alt, right_alt, f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
    space, a, c, v, x, z, other };

pub const Modifiers = packed struct {
    shift: bool = false,
    ctrl:  bool = false,
    alt:   bool = false,
    super: bool = false,
};

/// RB5 — Scale factor applied to trackpad swipe deltas to match scroll-wheel step sizes.
pub const SWIPE_SCALE: f32 = 20;
/// RB5 — |dy| threshold above which a scroll event is treated as a pinch gesture.
pub const PINCH_THRESHOLD: f32 = 5.0;
/// RB5 — Scaling factor mapping dy to pinch scale_delta (5% per unit).
pub const PINCH_SCALE: f32 = 0.05;

/// RB0 — OS cursor shapes available via glfwCreateStandardCursor.
pub const CursorShape = enum {
    arrow,       // GLFW_ARROW_CURSOR
    text_beam,   // GLFW_IBEAM_CURSOR
    crosshair,   // GLFW_CROSSHAIR_CURSOR
    hand,        // GLFW_POINTING_HAND_CURSOR
    resize_ew,   // GLFW_RESIZE_EW_CURSOR   (horizontal resize)
    resize_ns,   // GLFW_RESIZE_NS_CURSOR   (vertical resize)
    resize_all,  // GLFW_RESIZE_ALL_CURSOR  (move/drag)
    not_allowed, // GLFW_NOT_ALLOWED_CURSOR
};

// ---------------------------------------------------------------------------
// Platform — GLFW-backed window + Vulkan surface + input (INV-2.2)
// ---------------------------------------------------------------------------

pub const Platform = struct {
    // Internal fields are implementation-defined (GLFW window handle, etc.) — NOT contract.
    _impl: *anyopaque = undefined,

    pub fn init(gpa: std.mem.Allocator, opts: WindowOptions) PlatformError!Platform {
        _ = gpa;
        _ = opts;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *Platform) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn shouldClose(self: *Platform) bool {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn pollEvents(self: *Platform) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Block the calling thread until the OS delivers at least one windowing or
    /// input event, then return. Wraps glfwWaitEvents.
    /// Call only from the main thread (GLFW requirement).
    pub fn waitEvents(self: *Platform) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn framebufferSize(self: *Platform) Extent2D {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Vulkan instance extensions GLFW requires (returned as C strings). The backend passes
    /// these to instance creation.
    pub fn requiredInstanceExtensions(self: *Platform) []const [*:0]const u8 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Create the window surface for an existing Vulkan instance. `instance` and the returned
    /// surface are passed as opaque pointers so this contract does not depend on the Vulkan
    /// headers; the implementation casts them to VkInstance / VkSurfaceKHR.
    pub fn createSurface(self: *Platform, instance: *anyopaque) PlatformError!*anyopaque {
        _ = self;
        _ = instance;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Set the system clipboard to the given text (R36).
    /// Text is copied; ownership remains with the caller. `text` must be valid UTF-8.
    pub fn setClipboard(self: *Platform, text: []const u8) void {
        _ = self;
        _ = text;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Get the current system clipboard content as a UTF-8 string (R36).
    /// Returns an allocated string (owned by caller), or null if clipboard is empty or
    /// contains non-UTF-8 data. Caller must free with `allocator.free()`.
    pub fn getClipboard(self: *Platform, allocator: std.mem.Allocator) ?[]u8 {
        _ = self;
        _ = allocator;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// RB0 — Change the OS cursor displayed over the GLFW window.
    /// Cursor objects are created on first use and cached for the window's lifetime.
    /// Calling with the same shape as the current shape is a no-op at the OS level.
    pub fn setCursor(self: *Platform, shape: CursorShape) void {
        _ = self;
        _ = shape;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};

// ---------------------------------------------------------------------------
// VulkanBackend — the only GPU backend (INV-2.1). The seam is this method set, not a vtable.
// ---------------------------------------------------------------------------

pub const VulkanBackend = struct {
    // Internal fields implementation-defined (instance, device, swapchain, sync, …) — NOT
    // contract.
    _impl: *anyopaque = undefined,

    /// Bring up Vulkan against the given platform window. Enables validation layers in debug.
    pub fn init(gpa: std.mem.Allocator, platform: *Platform) BackendError!VulkanBackend {
        _ = gpa;
        _ = platform;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn deinit(self: *VulkanBackend) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Acquire the next swapchain image. Returns false if the swapchain was out of date and
    /// was recreated (caller should skip this frame and retry next loop iteration).
    pub fn beginFrame(self: *VulkanBackend) bool {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    pub fn clear(self: *VulkanBackend, color: Color) void {
        _ = self;
        _ = color;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Spike-only: draw one hardcoded triangle through a SPIR-V pipeline. Proves the shader
    /// path. Throwaway — not part of the real render API.
    pub fn drawTriangle(self: *VulkanBackend) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Submit the recorded commands and present the image.
    pub fn endFrame(self: *VulkanBackend) void {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Recreate the swapchain for a new framebuffer size (resize / out-of-date).
    pub fn onResize(self: *VulkanBackend, size: Extent2D) void {
        _ = self;
        _ = size;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    // --- introspection used by smoke_test.zig (automatable proof) ---

    /// Number of swapchain images (must be >= 1 once init succeeds).
    pub fn swapchainImageCount(self: *VulkanBackend) u32 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }

    /// Total validation-layer errors + warnings observed since init (must be 0). The debug
    /// messenger increments this; release builds without validation return 0.
    pub fn validationIssueCount(self: *VulkanBackend) u32 {
        _ = self;
        @compileError("not implemented — implement per spec.md; do not change this signature");
    }
};
