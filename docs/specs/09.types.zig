//! 09 — Renderer — types.zig
//!
//! Contract (INV-5.1). The struct shapes (DrawCommand, FilledRect, BorderRect, GlyphCmd,
//! GpuAtlas) and all public signatures are the contract — match them exactly.
//! Do not change signatures; if a signature seems wrong, STOP and surface it (INV-5.1).
//!
//! Depends on: std, module 01 (VulkanBackend), 02 (GlyphAtlas/layoutParagraph),
//!             03 (Rect/ElementStore), 05 (ComputedStyle/Color), 07 (Scene).
//! All lower-numbered in the build order — legal under INV-3.4.
//!
//! VulkanBackend extensions (drawFrame, initQuadPipeline, deinitQuadPipeline) are
//! implemented inside src/01/types.zig, NOT here. GpuAtlas and buildDrawList live here.

const std = @import("std");
const store = @import("../03/types.zig");
const theme = @import("../05/types.zig");
const comp = @import("../07/types.zig");
const text = @import("../02/types.zig");

pub const Rect = store.Rect;
pub const Color = theme.Color;
pub const Scene = comp.Scene;
pub const GlyphAtlas = text.GlyphAtlas;

// ---------------------------------------------------------------------------
// Draw command vocabulary
// ---------------------------------------------------------------------------

pub const FilledRect = struct {
    rect: Rect,
    color: Color,
    radius: f32 = 0,
};

pub const BorderRect = struct {
    rect: Rect,
    color: Color,
    width: f32,
    radius: f32 = 0,
};

pub const GlyphCmd = struct {
    dst: Rect,   // destination pixel rect on screen
    uv: Rect,    // source rect in normalized atlas coordinates (0..1)
    color: Color,
};

pub const DrawCommand = union(enum) {
    filled_rect: FilledRect,
    border_rect: BorderRect,
    glyph: GlyphCmd,
};

// ---------------------------------------------------------------------------
// Serializer
// ---------------------------------------------------------------------------

/// Walk a solved Scene (layout.computed must be filled by module 04 before calling)
/// and emit a flat DrawCommand list in depth-first pre-order (painter's algorithm).
/// Caller owns the returned slice and must free it with `alloc`.
pub fn buildDrawList(
    alloc: std.mem.Allocator,
    scene: *Scene,
    atlas: *GlyphAtlas,
) error{OutOfMemory}![]DrawCommand {
    _ = alloc;
    _ = scene;
    _ = atlas;
    @compileError("buildDrawList: not implemented");
}

// ---------------------------------------------------------------------------
// GPU atlas
// ---------------------------------------------------------------------------

/// GPU-side representation of a GlyphAtlas. Owns a VkImage, VkImageView, and VkSampler.
/// All Vulkan handles are stored as *anyopaque to avoid importing vulkan headers here.
pub const GpuAtlas = struct {
    image: *anyopaque = undefined,       // VkImage
    image_view: *anyopaque = undefined,  // VkImageView
    sampler: *anyopaque = undefined,     // VkSampler
    memory: *anyopaque = undefined,      // VkDeviceMemory
    width: u32 = 0,
    height: u32 = 0,

    /// Upload the CPU atlas bitmap to the GPU. Creates VkImage (R8_UNORM), uploads via
    /// staging buffer, transitions layout to SHADER_READ_ONLY_OPTIMAL, creates view and
    /// sampler. Frees the staging buffer before returning.
    /// `device`, `phys_device`, `cmd_pool`, `queue` are VkDevice / VkPhysicalDevice /
    /// VkCommandPool / VkQueue cast to *anyopaque (pointer-sized Vulkan handles).
    pub fn upload(
        gpa: std.mem.Allocator,
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        queue: *anyopaque,
        atlas: *const GlyphAtlas,
    ) error{ OutOfMemory, GpuUploadFailed }!GpuAtlas {
        _ = gpa;
        _ = device;
        _ = phys_device;
        _ = cmd_pool;
        _ = queue;
        _ = atlas;
        @compileError("GpuAtlas.upload: not implemented");
    }

    /// Destroy the VkImage, VkImageView, VkSampler, and VkDeviceMemory.
    /// `device` is VkDevice cast to *anyopaque.
    pub fn deinit(self: *GpuAtlas, device: *anyopaque) void {
        _ = self;
        _ = device;
        @compileError("GpuAtlas.deinit: not implemented");
    }
};
