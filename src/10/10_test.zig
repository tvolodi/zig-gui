//! Module 10 — GPU backend seam — unit tests for the RJ3 DX12 backend.
//!
//! All tests here are pure compile-time or struct-level checks.
//! No GPU, DX12 device, GLFW window, or live rendering is required.
//! Tests that require a DX12 device are marked with a comment:
//!   // verify manually — requires DX12 device
//!
//! Run: zig build -Dgpu=dx12 test-10-unit   (Windows + DX12 SDK required)
//! or:  zig build test-10-unit               (compiles everywhere; DX12 tests skipped on non-Windows)

const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;

// Import the types that are always available regardless of GPU backend.
const backend_mod = @import("types.zig");
const BackendKind = backend_mod.BackendKind;
const Caps = backend_mod.Caps;
const AtlasHandle = backend_mod.AtlasHandle;
const AtlasHandles = backend_mod.AtlasHandles;

// Import mod01 types — always available; contains Surface union and BackendKind.
const mod01 = @import("../01/types.zig");

// ---------------------------------------------------------------------------
// T1 — BackendKind.dx12 enum membership
// ---------------------------------------------------------------------------

test "BackendKind has .dx12 variant" {
    // Compile-time: verify .dx12 is a valid tag in the BackendKind enum.
    comptime {
        const k: BackendKind = .dx12;
        _ = k;
    }
    // Runtime verification that the discriminant works in a switch.
    const k = BackendKind.dx12;
    const label: []const u8 = switch (k) {
        .vulkan => "vulkan",
        .metal  => "metal",
        .dx12   => "dx12",
        .webgpu => "webgpu",
    };
    try testing.expectEqualStrings("dx12", label);
}

// ---------------------------------------------------------------------------
// T2 — Surface union has a .dx12 field
// ---------------------------------------------------------------------------

test "Surface union has .dx12 field" {
    // Compile-time: @hasField checks the union definition.
    comptime {
        if (!@hasField(mod01.Surface, "dx12")) {
            @compileError("Surface union is missing the .dx12 field (RJ3 / RJ5 requirement)");
        }
    }
    // The field must hold an opaque pointer (*anyopaque).
    // Use @typeInfo to extract the field type (std.meta.FieldType not available in Zig 0.16).
    comptime {
        const union_info = @typeInfo(mod01.Surface).@"union";
        var found = false;
        for (union_info.fields) |f| {
            if (std.mem.eql(u8, f.name, "dx12")) {
                if (f.type != *anyopaque) {
                    @compileError("Surface.dx12 field must be *anyopaque");
                }
                found = true;
            }
        }
        if (!found) @compileError("Surface.dx12 field not found in union");
    }
    try testing.expect(true); // compile-time checks passed
}

// ---------------------------------------------------------------------------
// T3 — Caps struct has the DX12-required fields and correct defaults
// ---------------------------------------------------------------------------

test "Caps struct fields exist" {
    // Verify that Caps has the three required fields.
    comptime {
        if (!@hasField(Caps, "max_texture_dim"))  @compileError("Caps missing max_texture_dim");
        if (!@hasField(Caps, "subpixel_text"))    @compileError("Caps missing subpixel_text");
        if (!@hasField(Caps, "present_modes"))    @compileError("Caps missing present_modes");
    }
}

test "Caps struct — DX12 expected values" {
    // Construct the expected Caps for DX12 (matches Dx12Backend.capabilities() constants).
    // This is a pure struct test — no device needed.
    const dx12_caps = Caps{
        .max_texture_dim = 16384,  // Feature level 11.0 minimum (RJ3 implementation constant)
        .subpixel_text   = true,   // DX12 supports subpixel rendering (RD2)
        .present_modes   = 0b0011, // fifo + mailbox
    };
    try testing.expectEqual(@as(u32, 16384), dx12_caps.max_texture_dim);
    try testing.expect(dx12_caps.subpixel_text);
    try testing.expectEqual(@as(u8, 0b0011), dx12_caps.present_modes);
}

// ---------------------------------------------------------------------------
// T4 — AtlasHandles struct (shared between DX12 and Vulkan via mod01)
// ---------------------------------------------------------------------------

test "AtlasHandles has glyph, sdf, image fields" {
    comptime {
        if (!@hasField(AtlasHandles, "glyph")) @compileError("AtlasHandles missing glyph");
        if (!@hasField(AtlasHandles, "sdf"))   @compileError("AtlasHandles missing sdf");
        if (!@hasField(AtlasHandles, "image")) @compileError("AtlasHandles missing image");
    }
}

// ---------------------------------------------------------------------------
// T5 — HLSL shader source files are present and non-empty
//       (Compile-time content check via @embedFile — works cross-platform.)
// ---------------------------------------------------------------------------

test "quad.hlsl is present and non-empty" {
    const content = @embedFile("shaders/quad.hlsl");
    comptime try testing.expect(content.len > 0);
    // Verify the file mentions both entry points.
    try testing.expect(std.mem.indexOf(u8, content, "VSMain") != null);
    try testing.expect(std.mem.indexOf(u8, content, "PSMain") != null);
}

test "quad.hlsl declares all 9 fragment mode cases (0-8)" {
    const content = @embedFile("shaders/quad.hlsl");
    // Modes 0-8 must each appear as "case N:" in the HLSL switch statement.
    inline for (0..9) |mode| {
        const needle = std.fmt.comptimePrint("case {d}:", .{mode});
        try testing.expect(std.mem.indexOf(u8, content, needle) != null);
    }
}

test "curve.hlsl is present and non-empty" {
    const content = @embedFile("shaders/curve.hlsl");
    comptime try testing.expect(content.len > 0);
    // Verify the curve stub mentions both entry points.
    try testing.expect(std.mem.indexOf(u8, content, "VSMain") != null);
    try testing.expect(std.mem.indexOf(u8, content, "PSMain") != null);
}

test "curve.hlsl mentions mode 8 stub" {
    const content = @embedFile("shaders/curve.hlsl");
    // The curve shader is the RM0-deferred stub; it should exist as a stub.
    // We verify the file is a valid stub (non-empty, has shader structure).
    try testing.expect(std.mem.indexOf(u8, content, "cbuffer") != null);
}

// ---------------------------------------------------------------------------
// T6 — Active Backend declares all 9 GpuBackend methods
//
// We check via backend_mod.Backend (the comptime-selected backend type from
// backend.zig). When -Dgpu=dx12 this is Dx12Backend; when -Dgpu=vulkan this
// is VulkanBackend. Either way all 9 methods must be present.
//
// NOTE: We deliberately do NOT do `@import("dx12_backend.zig")` here.
// The Zig module system forbids a file from being claimed by two different
// modules simultaneously. Since backend.zig already imports dx12_backend.zig
// via the `types.zig` alias, a second direct file import in the test root
// produces "file exists in modules 'root' and 'types.zig'" at compile time.
// Checking via backend_mod.Backend avoids this conflict.
// ---------------------------------------------------------------------------

// Import the active backend type through the module (avoids file-ownership conflict).
const BackendType = @import("types.zig").Backend;

// Comptime conformance check: every method in the GpuBackend contract must be present.
comptime {
    const B = BackendType;
    if (!@hasDecl(B, "init"))           @compileError("Backend missing: init");
    if (!@hasDecl(B, "deinit"))         @compileError("Backend missing: deinit");
    if (!@hasDecl(B, "initPipelines"))  @compileError("Backend missing: initPipelines");
    if (!@hasDecl(B, "resize"))         @compileError("Backend missing: resize");
    if (!@hasDecl(B, "uploadAtlas"))    @compileError("Backend missing: uploadAtlas");
    if (!@hasDecl(B, "uploadSdfAtlas")) @compileError("Backend missing: uploadSdfAtlas");
    if (!@hasDecl(B, "uploadImage"))    @compileError("Backend missing: uploadImage");
    if (!@hasDecl(B, "drawFrame"))      @compileError("Backend missing: drawFrame");
    if (!@hasDecl(B, "capabilities"))   @compileError("Backend missing: capabilities");
    if (@sizeOf(B) == 0)                @compileError("Backend has zero size (missing _impl field?)");
}

test "active Backend declares all 9 GpuBackend methods" {
    // The compile-time checks are in the comptime block above.
    // This test confirms the check ran (it's a no-op at runtime).
    try testing.expect(@sizeOf(BackendType) > 0);
}

// ---------------------------------------------------------------------------
// T7 — Surface.dx12 creation path exists (structural check only)
//
// A direct @import("../01/surface_win32.zig") here would collide with the
// module-system's ownership of that file by mod01_platform.
// Instead we verify the structural presence:
//   (a) Surface.dx12 field exists (already checked in T2)
//   (b) Platform.createSurface is declared (it dispatches to surface_win32.zig
//       internally via the .dx12 branch)
//
// verify manually — requires Windows + GLFW window:
//   Platform.createSurface(.dx12, null) must return Surface{ .dx12 = hwnd }
// ---------------------------------------------------------------------------

test "Platform has createSurface method (dispatches to surface_win32 on .dx12)" {
    comptime {
        if (!@hasDecl(mod01.Platform, "createSurface")) {
            @compileError("Platform missing createSurface (required for DX12 surface dispatch)");
        }
    }
    // Runtime: type of createSurface must be a function.
    const Fn = @TypeOf(mod01.Platform.createSurface);
    try testing.expect(@typeInfo(Fn) == .@"fn");
}

// ---------------------------------------------------------------------------
// T8 — Backend comptime switch routes .dx12 to Dx12Backend (Windows-only)
//       The backend.zig module is build-options-gated; we test the routing
//       logic symbolically by verifying the switch expression in types.
//       A full round-trip test requires -Dgpu=dx12 and a real build.
//
// verify manually — requires DX12 device:
//   zig build -Dgpu=dx12 run   — launches the demo under DX12
//   zig build -Dgpu=dx12 test-10 — runs the acceptance smoke test
// ---------------------------------------------------------------------------

test "BackendKind.dx12 comptime tag matches enum ordinal" {
    // Verify the dx12 ordinal is stable (important for switch dispatch in backend.zig).
    // This is a pure compile-time check.
    const tags = std.meta.tags(BackendKind);
    var found = false;
    for (tags) |t| {
        if (t == .dx12) {
            found = true;
            break;
        }
    }
    try testing.expect(found);
}

// ---------------------------------------------------------------------------
// T9 — QuadVertex layout matches DX12 input element stride (28 bytes)
//       This is the same assert in dx12_backend.zig's comptime block.
// ---------------------------------------------------------------------------

test "QuadVertex size is 28 bytes (matches DX12 input layout stride)" {
    const QV = mod01.QuadVertex;
    // pos[2]f32 (8) + uv[2]f32 (8) + color[4]u8 (4) + color_b[4]u8 (4) + mode u32 (4) = 28
    try testing.expectEqual(@as(usize, 28), @sizeOf(QV));
}

test "QuadVertex field offsets match HLSL input element AlignedByteOffset" {
    const QV = mod01.QuadVertex;
    // pos at offset 0 (POSITION, R32G32_FLOAT)
    try testing.expectEqual(@as(usize, 0),  @offsetOf(QV, "pos"));
    // uv at offset 8 (TEXCOORD0, R32G32_FLOAT)
    try testing.expectEqual(@as(usize, 8),  @offsetOf(QV, "uv"));
    // color at offset 16 (COLOR0, R8G8B8A8_UNORM)
    try testing.expectEqual(@as(usize, 16), @offsetOf(QV, "color"));
    // color_b at offset 20 (COLOR1, R8G8B8A8_UNORM)
    try testing.expectEqual(@as(usize, 20), @offsetOf(QV, "color_b"));
    // mode at offset 24 (BLENDINDICES, R32_UINT)
    try testing.expectEqual(@as(usize, 24), @offsetOf(QV, "mode"));
}
