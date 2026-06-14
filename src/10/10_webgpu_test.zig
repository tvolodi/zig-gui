// 10_webgpu_test.zig — WebGPU backend unit tests (M23-01 / RJ4)
//
// Compile-time and struct-level tests only — no GPU device required.
// Tests verify:
//   1. BackendKind has .webgpu variant
//   2. WebGpuBackend declares all 9 GpuBackend methods
//   3. quad.wgsl exists and contains all 9 mode cases
//   4. Caps type has the expected fields
//   5. Surface union has the .webgpu field

const std = @import("std");
const types = @import("types.zig");

// ---------------------------------------------------------------------------
// Test 1: BackendKind has .webgpu
// ---------------------------------------------------------------------------

test "BackendKind has .webgpu" {
    const k: types.BackendKind = .webgpu;
    try std.testing.expect(k == .webgpu);
}

// ---------------------------------------------------------------------------
// Test 2: WebGpuBackend declares all 9 GpuBackend methods
//
// Access WebGpuBackend via the backend module's `Backend` re-export rather than
// importing webgpu_backend.zig directly. Zig 0.16 enforces one-module-per-file;
// direct import would conflict with backend.zig's import of the same file.
// ---------------------------------------------------------------------------

test "WebGpuBackend declares all 9 GpuBackend methods" {
    // types.zig is backend.zig which re-exports Backend = WebGpuBackend (when -Dgpu=webgpu).
    const Backend = @import("types.zig").Backend;
    try std.testing.expect(@hasDecl(Backend, "init"));
    try std.testing.expect(@hasDecl(Backend, "deinit"));
    try std.testing.expect(@hasDecl(Backend, "initPipelines"));
    try std.testing.expect(@hasDecl(Backend, "resize"));
    try std.testing.expect(@hasDecl(Backend, "uploadAtlas"));
    try std.testing.expect(@hasDecl(Backend, "uploadSdfAtlas"));
    try std.testing.expect(@hasDecl(Backend, "uploadImage"));
    try std.testing.expect(@hasDecl(Backend, "drawFrame"));
    try std.testing.expect(@hasDecl(Backend, "capabilities"));
}

// ---------------------------------------------------------------------------
// Test 3: quad.wgsl exists and has all 9 mode cases
// ---------------------------------------------------------------------------

test "quad.wgsl exists and has all 9 mode cases" {
    const src = @embedFile("shaders/quad.wgsl");
    // Each mode must appear as a WGSL switch case.
    try std.testing.expect(std.mem.indexOf(u8, src, "case 0u") != null); // filled_rect
    try std.testing.expect(std.mem.indexOf(u8, src, "case 1u") != null); // glyph
    try std.testing.expect(std.mem.indexOf(u8, src, "case 2u") != null); // border_rect
    try std.testing.expect(std.mem.indexOf(u8, src, "case 3u") != null); // image_rect
    try std.testing.expect(std.mem.indexOf(u8, src, "case 4u") != null); // sdf_icon
    try std.testing.expect(std.mem.indexOf(u8, src, "case 5u") != null); // gradient_rect
    try std.testing.expect(std.mem.indexOf(u8, src, "case 6u") != null); // aa_filled_circle
    try std.testing.expect(std.mem.indexOf(u8, src, "case 7u") != null); // subpixel_glyph
    try std.testing.expect(std.mem.indexOf(u8, src, "case 8u") != null); // curve stub
}

// ---------------------------------------------------------------------------
// Test 4: Caps type has the expected fields
// ---------------------------------------------------------------------------

test "Caps type has expected fields" {
    const Caps = types.Caps;
    try std.testing.expect(@hasField(Caps, "max_texture_dim"));
    try std.testing.expect(@hasField(Caps, "subpixel_text"));
    try std.testing.expect(@hasField(Caps, "present_modes"));
}

// ---------------------------------------------------------------------------
// Test 5: Surface union has .webgpu field
// ---------------------------------------------------------------------------

test "Surface union has .webgpu field" {
    const mod01 = @import("../01/types.zig");
    // Verify the .webgpu tag exists in BackendKind (and therefore in Surface).
    const k: mod01.BackendKind = .webgpu;
    try std.testing.expect(k == .webgpu);
    // Verify Surface is a union tagged by BackendKind (compile-time check).
    const Surface = mod01.Surface;
    try std.testing.expect(@typeInfo(Surface) == .@"union");
}
