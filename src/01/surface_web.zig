// surface_web.zig — Web <canvas> surface — M23-01 (RJ4)
//
// On WASM/Emscripten, provides a GPUCanvasContext surface handle.
// Also handles JS input event forwarding (mouse, keyboard, resize).
//
// This file is compiled only when -Dtarget=wasm32-emscripten is selected.
// On native targets the @compileError in createWebSurface fires if called.

const std = @import("std");
const builtin = @import("builtin");

/// Web surface handle: represents a <canvas> element on the page.
/// Fields match the parameters needed by wgpuInstanceCreateSurface on Emscripten.
pub const WebSurface = struct {
    /// CSS selector ID of the <canvas> element, e.g. "#canvas".
    canvas_id: []const u8,
    /// Logical width in CSS pixels.
    width: u32,
    /// Logical height in CSS pixels.
    height: u32,
    /// Device pixel ratio (window.devicePixelRatio in JS) — used to scale physical pixels.
    device_pixel_ratio: f32,
};

/// Create a web surface from the canvas element ID.
/// On non-WASM targets, calling this function is a compile-time error.
///
/// `canvas_id` — the CSS id of the <canvas> element (e.g. "#canvas").
/// `width`     — initial logical width in CSS pixels.
/// `height`    — initial logical height in CSS pixels.
pub fn createWebSurface(canvas_id: []const u8, width: u32, height: u32) WebSurface {
    if (comptime builtin.cpu.arch != .wasm32) {
        @compileError("createWebSurface is only available on WASM targets (RJ4)");
    }
    return .{
        .canvas_id = canvas_id,
        .width = width,
        .height = height,
        .device_pixel_ratio = 1.0,
    };
}
