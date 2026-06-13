//! 10 — GPU backend seam — backend.zig
//!
//! Comptime selection of the active GPU backend based on -Dgpu build option.

const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");

pub const BackendKind = types.BackendKind;
pub const GpuBackend = types.GpuBackend;

// Build-time option: -Dgpu=vulkan|metal|dx12|webgpu (default per target)
const gpu_backend = @import("build_options").gpu;

/// The concrete backend struct selected at build time.
pub const Backend = switch (gpu_backend) {
    .vulkan => @import("../01/types.zig").VulkanBackend,
    .metal => @compileError("Metal backend not yet implemented (RJ2)"),
    .dx12 => @compileError("DX12 backend not yet implemented (RJ3)"),
    .webgpu => @compileError("WebGPU backend not yet implemented (RJ4)"),
};

// Re-export all GpuBackend methods through the selected backend
pub const init = Backend.init;
pub const deinit = Backend.deinit;
pub const initPipelines = Backend.initPipelines;
pub const resize = Backend.resize;
pub const uploadAtlas = Backend.uploadAtlas;
pub const uploadSdfAtlas = Backend.uploadSdfAtlas;
pub const uploadImage = Backend.uploadImage;
pub const drawFrame = Backend.drawFrame;
pub const capabilities = Backend.capabilities;
