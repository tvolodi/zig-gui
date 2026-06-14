//! 10 — GPU backend seam — backend.zig
//!
//! Comptime selection of the active GPU backend based on -Dgpu build option.
//! This file is the root of mod10_gpu_backend; it re-exports src/10/types.zig
//! so that all public API types are available from one module import.

const std = @import("std");
const builtin = @import("builtin");

// Re-export all types from types.zig so mod10_gpu_backend consumers
// get the contract types (BackendKind, GpuBackend, Caps, etc.) directly.
pub const types = @import("types.zig");

pub const BackendKind = types.BackendKind;
pub const GpuBackend = types.GpuBackend;
pub const Caps = types.Caps;
pub const BackendError = types.BackendError;
pub const AtlasHandle = types.AtlasHandle;
pub const AtlasHandles = types.AtlasHandles;
pub const Platform = types.Platform;
pub const DrawCommand = types.DrawCommand;

// Build-time option: -Dgpu=vulkan|metal|dx12|webgpu (default per target)
const gpu_backend = @import("build_options").gpu;

/// The concrete backend struct selected at build time.
pub const Backend = switch (gpu_backend) {
    .vulkan => @import("../01/types.zig").VulkanBackend,
    .metal => @compileError("Metal backend not yet implemented (RJ2)"),
    .dx12 => @import("dx12_backend.zig").Dx12Backend,
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
