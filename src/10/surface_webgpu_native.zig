// surface_webgpu_native.zig — Native WebGPU surface — M23-01 (RJ4)
//
// Extracts a WGPUSurface from a GLFW window handle using wgpu-native.
// On Windows, uses glfwGetWin32Window + WGPUSurfaceDescriptorFromWindowsHWND.
//
// Called from webgpu_backend.zig when initialising the WebGPU backend.
// Placed in src/10/ (not src/01/) so it stays within the mod10_gpu_backend
// module boundary and can use @cImport for wgpu-native symbols without
// leaking those symbols into mod01_platform (which must compile without
// wgpu_native.lib when -Dgpu=vulkan).
//
// The WGPUInstance is passed in; the WGPUSurface is returned as *anyopaque.

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("webgpu/webgpu.h");
    if (builtin.os.tag == .windows) {
        @cInclude("windows.h"); // for GetModuleHandleW, HINSTANCE
        @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1");
    }
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

/// Create a wgpu-native WGPUSurface for a GLFW window.
///
/// `instance` — WGPUInstance (created by webgpu_backend.zig), passed as *anyopaque.
/// `window`   — *c.GLFWwindow, passed as *anyopaque.
///
/// Returns the WGPUSurface as *anyopaque (caller casts to c.WGPUSurface).
/// Returns error.SurfaceCreationFailed if the surface cannot be created.
pub fn createWebGpuNativeSurface(
    instance: *anyopaque,
    window: *anyopaque,
) error{SurfaceCreationFailed}!*anyopaque {
    const wgpu_instance: c.WGPUInstance = @ptrCast(instance);
    const glfw_window: *c.GLFWwindow = @ptrCast(@alignCast(window));

    const surface = blk: {
        if (comptime builtin.os.tag == .windows) {
            const hwnd = c.glfwGetWin32Window(glfw_window);
            if (hwnd == null) return error.SurfaceCreationFailed;

            // hinstance is the module handle for the current executable.
            // On Windows, GetModuleHandleW(null) returns the exe's base address.
            // We call via C import (windows.h) rather than std.os.windows (Zig 0.16 compat).
            const hinstance = c.GetModuleHandleW(null);

            var desc_hwnd = std.mem.zeroes(c.WGPUSurfaceDescriptorFromWindowsHWND);
            desc_hwnd.chain.sType = c.WGPUSType_SurfaceDescriptorFromWindowsHWND;
            desc_hwnd.chain.next = null;
            desc_hwnd.hinstance = hinstance;
            desc_hwnd.hwnd = hwnd;

            var desc = std.mem.zeroes(c.WGPUSurfaceDescriptor);
            desc.nextInChain = @ptrCast(&desc_hwnd.chain);

            break :blk c.wgpuInstanceCreateSurface(wgpu_instance, &desc);
        } else {
            // Linux/macOS: not yet implemented for this pass (RJ4 Windows-first).
            // A future pass will add XLib/Wayland/NSWindow surface creation here.
            @compileError("WebGPU native surface on non-Windows not yet implemented (RJ4)");
        }
    };

    if (surface == null) return error.SurfaceCreationFailed;
    return @ptrCast(surface);
}
