//! 10 — GPU backend seam — types.zig
//!
//! Defines the GpuBackend interface contract. Every GPU backend (Vulkan, Metal, DX12, WebGPU)
//! must implement these exact signatures. Selection is comptime via -Dgpu build option.
//!
//! Fragment shader modes (every backend implements all):
//!   mode 0: solid rect
//!   mode 1: glyph (atlas-sampled)
//!   mode 2: bordered rect
//!   mode 3: image rect (RGBA)
//!   mode 4: SDF icon
//!   mode 5: gradient
//!   mode 6: AA filled circle
//!   mode 7: subpixel glyph
//!   mode 8: curve/polyline (added by RM0 charts, deferred)

const std = @import("std");

// Re-export BackendKind from module 01 (the canonical home of the Surface union)
pub const BackendKind = @import("../01/types.zig").BackendKind;

pub const AtlasHandle = struct { backend_obj: *anyopaque };

pub const AtlasHandles = struct {
    glyph: AtlasHandle,
    sdf: AtlasHandle,
    image: AtlasHandle,
};

pub const PresentModeSet = u8; // Bitmask; concrete definition TBD from Vulkan enum

pub const Caps = struct {
    max_texture_dim: u32,
    subpixel_text: bool,        // RD2 supported on this backend
    present_modes: PresentModeSet,
};

pub const BackendError = error{
    NoSuitableDevice,
    InstanceCreationFailed,
    DeviceCreationFailed,
    SwapchainCreationFailed,
    ShaderLoadFailed,
};

/// GpuBackend — the seam contract (documentation type).
///
/// Every backend must implement these exact signatures:
///   init(gpa: std.mem.Allocator, platform: *Platform) BackendError!Self
///   deinit(self: *Self) void
///   initPipelines(self: *Self) BackendError!void
///   resize(self: *Self, w: u32, h: u32, dpi_scale: f32) void
///   uploadAtlas(self: *Self, atlas: *const GlyphAtlas) BackendError!AtlasHandle
///   uploadSdfAtlas(self: *Self, atlas: *const SdfAtlas) BackendError!AtlasHandle
///   uploadImage(self: *Self, pixels: []const u8, w: u32, h: u32) BackendError!AtlasHandle
///   drawFrame(self: *Self, commands: []const DrawCommand, handles: AtlasHandles) void
///   capabilities(self: *const Self) Caps
///
/// The concrete backend type (e.g., VulkanBackend) is selected at build time via -Dgpu.
/// See backend.zig for the comptime dispatch. This type is never instantiated;
/// it exists only as a contract specification in documentation.
pub const GpuBackend = struct {};

// Re-export types from dependencies for convenience
pub const Platform = @import("../01/types.zig").Platform;
pub const DrawCommand = @import("../09/types.zig").DrawCommand;
pub const GlyphAtlas = @import("../02/types.zig").GlyphAtlas;
pub const SdfAtlas = @import("../09/types.zig").SdfAtlas;
