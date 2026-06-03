//! 09 — Renderer — types.zig
//!
//! Contract (INV-5.1). The struct shapes (DrawCommand, FilledRect, BorderRect, GlyphCmd,
//! GpuAtlas) and all public signatures are the contract — match them exactly.
//! Do not change signatures; if a signature seems wrong, STOP and surface it (INV-5.1).
//!
//! Depends on: std, module 01 (VulkanBackend), 02 (GlyphAtlas/Font), 03 (Rect/ElementStore),
//!             05 (ComputedStyle/Color/Tokens), 07 (Scene), app/image_atlas (ImageAtlas).
//! All lower-numbered in the build order — legal under INV-3.4.
//!
//! VulkanBackend extensions (drawFrame, initQuadPipeline, deinitQuadPipeline) are
//! implemented inside src/01/types.zig, NOT here. GpuAtlas and buildDrawList live here.

const std = @import("std");
const store = @import("../03/types.zig");
const theme = @import("../05/types.zig");
const comp = @import("../07/types.zig");
const text_mod = @import("../02/types.zig");
const platform = @import("../01/types.zig");
const image_atlas_mod = @import("../app/image_atlas.zig");

pub const Rect = store.Rect;
pub const Color = theme.Color;
pub const Scene = comp.Scene;
pub const GlyphAtlas = text_mod.GlyphAtlas;
pub const Tokens = theme.Tokens;
pub const PseudoState = comp.PseudoState;
pub const PseudoStyleSet = theme.PseudoStyleSet;
pub const ComputedStyle = theme.ComputedStyle;
pub const ImageAtlas = image_atlas_mod.ImageAtlas;

// Re-export text module so acceptance test can do C.text.Font.initFromBytes
pub const text = text_mod;

// ---------------------------------------------------------------------------
// Draw command vocabulary (re-exported from module 01)
// ---------------------------------------------------------------------------

pub const FilledRect = platform.FilledRect;
pub const BorderRect = platform.BorderRect;
pub const GlyphCmd = platform.GlyphCmd;
pub const ScissorRect = platform.ScissorRect;
pub const ImageCmd = platform.ImageCmd;

pub const DrawCommand = platform.DrawCommand;

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
    image_atlas: *const ImageAtlas,
    font: *text_mod.Font,
    tokens: Tokens,
) error{OutOfMemory}![]DrawCommand {
    _ = alloc;
    _ = scene;
    _ = atlas;
    _ = image_atlas;
    _ = font;
    _ = tokens;
    @compileError("buildDrawList: not implemented");
}

// ---------------------------------------------------------------------------
// Border helpers (public — tested directly by acceptance_test.zig)
// ---------------------------------------------------------------------------

/// Clamp border.width to min(rect.w, rect.h) / 2 to prevent inverted geometry.
pub fn clampBorderWidth(border: BorderRect) BorderRect {
    _ = border;
    @compileError("clampBorderWidth: not implemented");
}

/// Expand a border_rect into 4 FilledRect quads (top, bottom, left, right).
pub fn expandBorderToQuads(border: BorderRect, out: *[4]FilledRect) void {
    _ = border;
    _ = out;
    @compileError("expandBorderToQuads: not implemented");
}

// ---------------------------------------------------------------------------
// R40 — Style resolution helper
// ---------------------------------------------------------------------------

/// Resolve the effective ComputedStyle by layering pseudo-state overrides.
/// Priority: disabled > active > hover > focus > base.
pub fn resolveStyle(
    base: ComputedStyle,
    overrides: PseudoStyleSet,
    state: PseudoState,
) ComputedStyle {
    _ = base;
    _ = overrides;
    _ = state;
    @compileError("resolveStyle: not implemented");
}

// ---------------------------------------------------------------------------
// R45 — Opacity helper
// ---------------------------------------------------------------------------

/// Multiply the alpha channel of `c` by `factor` (clamped to [0, 1]).
pub fn applyOpacity(col: Color, factor: f32) Color {
    _ = col;
    _ = factor;
    @compileError("applyOpacity: not implemented");
}

// ---------------------------------------------------------------------------
// R46 — Box shadow helper
// ---------------------------------------------------------------------------

/// Emit N filled_rect commands approximating a blurred drop shadow.
pub fn emitShadow(
    cmds: *std.ArrayListUnmanaged(DrawCommand),
    alloc: std.mem.Allocator,
    element_rect: store.Rect,
    style: ComputedStyle,
    effective_alpha: f32,
) error{OutOfMemory}!void {
    _ = cmds;
    _ = alloc;
    _ = element_rect;
    _ = style;
    _ = effective_alpha;
    @compileError("emitShadow: not implemented");
}

// ---------------------------------------------------------------------------
// R42 — Scissor helpers
// ---------------------------------------------------------------------------

/// Convert a floating-point layout Rect to an integer ScissorRect, clamping to [0, max].
pub fn rectToScissor(r: store.Rect) ScissorRect {
    _ = r;
    @compileError("rectToScissor: not implemented");
}

/// Compute the intersection of two ScissorRects. Returns zero-area if no overlap.
pub fn intersectScissor(a: ScissorRect, b: ScissorRect) ScissorRect {
    _ = a;
    _ = b;
    @compileError("intersectScissor: not implemented");
}

// ---------------------------------------------------------------------------
// GPU image atlas (R43)
// ---------------------------------------------------------------------------

/// GPU-side image atlas. Mirrors GpuAtlas pattern; upload/deinit are stubs for v1.
pub const GpuImageAtlas = struct {
    image: *anyopaque = undefined,
    image_view: *anyopaque = undefined,
    sampler: *anyopaque = undefined,
    memory: *anyopaque = undefined,
    width: u32 = 0,
    height: u32 = 0,

    pub fn upload(
        gpa: std.mem.Allocator,
        device: *anyopaque,
        phys_device: *anyopaque,
        cmd_pool: *anyopaque,
        queue: *anyopaque,
        atlas: *const ImageAtlas,
    ) error{ OutOfMemory, GpuUploadFailed }!GpuImageAtlas {
        _ = gpa;
        _ = device;
        _ = phys_device;
        _ = cmd_pool;
        _ = queue;
        _ = atlas;
        @compileError("GpuImageAtlas.upload: not implemented");
    }

    pub fn deinit(self: *GpuImageAtlas, device: *anyopaque) void {
        _ = self;
        _ = device;
        @compileError("GpuImageAtlas.deinit: not implemented");
    }
};

// ---------------------------------------------------------------------------
// GPU atlas
// ---------------------------------------------------------------------------

/// GPU-side representation of a GlyphAtlas. Owns a VkImage, VkImageView, and VkSampler.
/// All Vulkan handles are stored as *anyopaque to avoid importing vulkan headers here.
pub const GpuAtlas = struct {
    image: ?*anyopaque = null,       // VkImage
    image_view: ?*anyopaque = null,  // VkImageView
    sampler: ?*anyopaque = null,     // VkSampler
    memory: ?*anyopaque = null,      // VkDeviceMemory
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
