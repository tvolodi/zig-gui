//! 01 — Platform surface layer — Win32 / DXGI (RJ3 / M22-01).
//!
//! Provides the HWND needed by the DX12 backend to create an IDXGISwapChain.
//! Called from Platform.createSurface in types.zig when backend == .dx12.
//!
//! The actual IDXGISwapChain3 is created by Dx12Backend.init (src/10/dx12_backend.zig),
//! not here. This layer's job is only to extract the HWND from GLFW and return it
//! as an opaque pointer that the backend can cast to HWND.

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cDefine("GLFW_EXPOSE_NATIVE_WIN32", "1");
    @cInclude("GLFW/glfw3.h");
    @cInclude("GLFW/glfw3native.h");
});

/// Extract the Win32 HWND from the given GLFW window.
///
/// `window` is a *c.GLFWwindow (passed as *anyopaque to avoid exposing GLFW types).
///
/// Returns the HWND as *anyopaque (caller casts back to HWND via @ptrCast).
/// Only valid on Windows targets (compile-error on other platforms).
pub fn createWin32Surface(window: *anyopaque) error{SurfaceCreationFailed}!*anyopaque {
    if (comptime builtin.os.tag != .windows) {
        @compileError("surface_win32.zig is only available on Windows (RJ3)");
    }

    const glfw_window: *c.GLFWwindow = @ptrCast(@alignCast(window));
    const hwnd = c.glfwGetWin32Window(glfw_window);
    if (hwnd == null) return error.SurfaceCreationFailed;
    return @ptrCast(hwnd);
}
