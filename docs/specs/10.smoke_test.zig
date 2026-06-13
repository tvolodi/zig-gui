//! Module 10 — GPU backend seam — smoke test
//!
//! Verifies that the GpuBackend interface compiles and the selected backend
//! (via -Dgpu build option) is available at comptime.
//!
//! Run: zig build test-10
//! Or with explicit backend: zig build -Dgpu=vulkan test-10

const std = @import("std");
const types = @import("types.zig");

pub fn main() void {
    std.debug.print("Module 10 smoke test: GPU backend seam interface compiles.\n", .{});
}

test "BackendKind enum exists" {
    const kind = types.BackendKind.vulkan;
    try std.testing.expect(kind == .vulkan);
}

test "GpuBackend interface contract type-checks" {
    // This is a compile-time check: ensure the GpuBackend struct type is valid.
    // Runtime code cannot instantiate it directly (no constructor), but the type
    // definition itself must be valid.
    const interface_type = types.GpuBackend;
    _ = interface_type;
}

test "AtlasHandle opaque type" {
    const handle = types.AtlasHandle{ .backend_obj = @ptrFromInt(0x1234) };
    try std.testing.expect(handle.backend_obj == @ptrFromInt(0x1234));
}

test "Caps struct compiles" {
    const caps = types.Caps{
        .max_texture_dim = 4096,
        .subpixel_text = true,
        .present_modes = 0,
    };
    try std.testing.expect(caps.max_texture_dim == 4096);
    try std.testing.expect(caps.subpixel_text == true);
}
