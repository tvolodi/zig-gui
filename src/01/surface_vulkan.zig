//! 01 — Platform surface layer — Vulkan (RJ2 extraction).
//!
//! Owns VkSurfaceKHR creation via GLFW. Called from Platform.createSurface in types.zig.
//! When a second backend lands (RJ2 Metal, RJ3 DX12, RJ4 WebGPU), the equivalent
//! surface_macos.zig / surface_win32.zig / surface_web.zig files are created here;
//! types.zig dispatches to the correct file based on build_options.gpu (INV-1.2-v2).

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("GLFW_INCLUDE_VULKAN", "1");
    @cInclude("GLFW/glfw3.h");
});

/// Create a VkSurfaceKHR for the given GLFW window and Vulkan instance.
/// `window` is a *c.GLFWwindow (passed as *anyopaque to avoid exposing GLFW types).
/// `instance` is a VkInstance (passed as *anyopaque).
/// Returns the surface handle as *anyopaque (caller casts back to VkSurfaceKHR).
pub fn createVulkanSurface(window: *anyopaque, instance: ?*anyopaque) error{SurfaceCreationFailed}!*anyopaque {
    const vk_instance: c.VkInstance = @ptrCast(instance orelse return error.SurfaceCreationFailed);
    const glfw_window: *c.GLFWwindow = @ptrCast(@alignCast(window));
    var surface: c.VkSurfaceKHR = undefined;
    if (c.glfwCreateWindowSurface(vk_instance, glfw_window, null, &surface) != c.VK_SUCCESS) {
        return error.SurfaceCreationFailed;
    }
    return @ptrCast(surface.?);
}
