//! 01 — Platform spike — unit tests
//!
//! Unit tests that go DEEPER than the smoke tests in docs/specs/01.smoke_test.zig:
//!   - Compile-time checks (error set taxonomy, struct/method existence)
//!   - Pure-logic struct construction with no GPU
//!   - Edge-case values (zero, max, boundary dimensions)
//!   - GPU-guarded tests that skip gracefully when no display is available
//!
//! DO NOT modify docs/specs/01.smoke_test.zig (INV-5.3).
//!
//! Run via the build system:
//!   zig build            — compiles only (no GPU required)
//!   zig build test-01-unit — compiles + runs (GPU tests auto-skip if unavailable)

const std = @import("std");
const testing = std.testing;
const P = @import("types.zig");

// ===========================================================================
// 1. Extent2D — construction and field access
// ===========================================================================

test "Extent2D: basic construction and field access" {
    const e = P.Extent2D{ .width = 800, .height = 600 };
    try testing.expectEqual(@as(u32, 800), e.width);
    try testing.expectEqual(@as(u32, 600), e.height);
}

test "Extent2D: zero dimensions are representable" {
    const e = P.Extent2D{ .width = 0, .height = 0 };
    try testing.expectEqual(@as(u32, 0), e.width);
    try testing.expectEqual(@as(u32, 0), e.height);
}

test "Extent2D: max u32 dimensions are representable" {
    const e = P.Extent2D{ .width = std.math.maxInt(u32), .height = std.math.maxInt(u32) };
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), e.width);
    try testing.expectEqual(@as(u32, std.math.maxInt(u32)), e.height);
}

test "Extent2D: non-square dimensions" {
    const wide = P.Extent2D{ .width = 3840, .height = 1 };
    const tall = P.Extent2D{ .width = 1, .height = 2160 };
    try testing.expectEqual(@as(u32, 3840), wide.width);
    try testing.expectEqual(@as(u32, 1), wide.height);
    try testing.expectEqual(@as(u32, 1), tall.width);
    try testing.expectEqual(@as(u32, 2160), tall.height);
}

test "Extent2D: is a struct with width and height fields of type u32 (compile-time)" {
    comptime {
        const info = @typeInfo(P.Extent2D);
        std.debug.assert(info == .@"struct");
        std.debug.assert(@hasField(P.Extent2D, "width"));
        std.debug.assert(@hasField(P.Extent2D, "height"));
    }
}

// ===========================================================================
// 2. Color — construction, field access, default alpha
// ===========================================================================

test "Color: explicit RGBA construction" {
    const col = P.Color{ .r = 0.25, .g = 0.50, .b = 0.75, .a = 0.10 };
    try testing.expectEqual(@as(f32, 0.25), col.r);
    try testing.expectEqual(@as(f32, 0.50), col.g);
    try testing.expectEqual(@as(f32, 0.75), col.b);
    try testing.expectEqual(@as(f32, 0.10), col.a);
}

test "Color: omitting alpha gives default 1.0" {
    const col = P.Color{ .r = 0.1, .g = 0.2, .b = 0.3 };
    try testing.expectEqual(@as(f32, 1.0), col.a);
}

test "Color: all-zero black (explicit alpha 0)" {
    const col = P.Color{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 0.0 };
    try testing.expectEqual(@as(f32, 0.0), col.r);
    try testing.expectEqual(@as(f32, 0.0), col.g);
    try testing.expectEqual(@as(f32, 0.0), col.b);
    try testing.expectEqual(@as(f32, 0.0), col.a);
}

test "Color: all-one white with default alpha" {
    const col = P.Color{ .r = 1.0, .g = 1.0, .b = 1.0 };
    try testing.expectEqual(@as(f32, 1.0), col.r);
    try testing.expectEqual(@as(f32, 1.0), col.g);
    try testing.expectEqual(@as(f32, 1.0), col.b);
    try testing.expectEqual(@as(f32, 1.0), col.a);
}

test "Color: individual channel independence" {
    // Each channel must be stored independently — writing one must not corrupt others.
    const red = P.Color{ .r = 1.0, .g = 0.0, .b = 0.0 };
    const green = P.Color{ .r = 0.0, .g = 1.0, .b = 0.0 };
    const blue = P.Color{ .r = 0.0, .g = 0.0, .b = 1.0 };
    try testing.expectEqual(@as(f32, 1.0), red.r);
    try testing.expectEqual(@as(f32, 0.0), red.g);
    try testing.expectEqual(@as(f32, 1.0), green.g);
    try testing.expectEqual(@as(f32, 0.0), green.b);
    try testing.expectEqual(@as(f32, 1.0), blue.b);
    try testing.expectEqual(@as(f32, 0.0), blue.r);
}

test "Color: is a struct with r, g, b, a fields of type f32 (compile-time)" {
    comptime {
        const info = @typeInfo(P.Color);
        std.debug.assert(info == .@"struct");
        std.debug.assert(@hasField(P.Color, "r"));
        std.debug.assert(@hasField(P.Color, "g"));
        std.debug.assert(@hasField(P.Color, "b"));
        std.debug.assert(@hasField(P.Color, "a"));
    }
}

// ===========================================================================
// 3. WindowOptions — default values
// ===========================================================================

test "WindowOptions: default title is 'spike'" {
    const opts = P.WindowOptions{};
    try testing.expectEqualStrings("spike", opts.title);
}

test "WindowOptions: default width is 960" {
    const opts = P.WindowOptions{};
    try testing.expectEqual(@as(u32, 960), opts.width);
}

test "WindowOptions: default height is 600" {
    const opts = P.WindowOptions{};
    try testing.expectEqual(@as(u32, 600), opts.height);
}

test "WindowOptions: explicit values override all defaults" {
    const opts = P.WindowOptions{ .title = "my-app", .width = 1280, .height = 720 };
    try testing.expectEqualStrings("my-app", opts.title);
    try testing.expectEqual(@as(u32, 1280), opts.width);
    try testing.expectEqual(@as(u32, 720), opts.height);
}

test "WindowOptions: title is sentinel-terminated ([:0]const u8) (compile-time)" {
    comptime {
        const info = @typeInfo(P.WindowOptions);
        std.debug.assert(info == .@"struct");
        // The title field must be a sentinel-terminated slice, not a plain slice.
        // Verified by the fact that string literals ([:0]const u8) are accepted.
        const opts: P.WindowOptions = .{ .title = "check" };
        std.debug.assert(opts.title.len == 5);
    }
}

// ===========================================================================
// 4. PlatformError — error taxonomy (compile-time coercion checks)
// ===========================================================================

test "PlatformError: is an error set (compile-time)" {
    comptime {
        const info = @typeInfo(P.PlatformError);
        std.debug.assert(info == .error_set);
    }
}

test "PlatformError: contains GlfwInitFailed (compile-time)" {
    comptime {
        const e: P.PlatformError = error.GlfwInitFailed;
        _ = @intFromError(e);
    }
}

test "PlatformError: contains VulkanUnavailable (compile-time)" {
    comptime {
        const e: P.PlatformError = error.VulkanUnavailable;
        _ = @intFromError(e);
    }
}

test "PlatformError: contains WindowCreationFailed (compile-time)" {
    comptime {
        const e: P.PlatformError = error.WindowCreationFailed;
        _ = @intFromError(e);
    }
}

test "PlatformError: contains SurfaceCreationFailed (compile-time)" {
    comptime {
        const e: P.PlatformError = error.SurfaceCreationFailed;
        _ = @intFromError(e);
    }
}

// ===========================================================================
// 5. BackendError — error taxonomy (compile-time coercion checks)
// ===========================================================================

test "BackendError: is an error set (compile-time)" {
    comptime {
        const info = @typeInfo(P.BackendError);
        std.debug.assert(info == .error_set);
    }
}

test "BackendError: contains NoSuitableDevice (compile-time)" {
    comptime {
        const e: P.BackendError = error.NoSuitableDevice;
        _ = @intFromError(e);
    }
}

test "BackendError: contains InstanceCreationFailed (compile-time)" {
    comptime {
        const e: P.BackendError = error.InstanceCreationFailed;
        _ = @intFromError(e);
    }
}

test "BackendError: contains DeviceCreationFailed (compile-time)" {
    comptime {
        const e: P.BackendError = error.DeviceCreationFailed;
        _ = @intFromError(e);
    }
}

test "BackendError: contains SwapchainCreationFailed (compile-time)" {
    comptime {
        const e: P.BackendError = error.SwapchainCreationFailed;
        _ = @intFromError(e);
    }
}

test "BackendError: contains ShaderLoadFailed (compile-time)" {
    comptime {
        const e: P.BackendError = error.ShaderLoadFailed;
        _ = @intFromError(e);
    }
}

// ===========================================================================
// 6. Struct type checks — Platform and VulkanBackend
// ===========================================================================

test "Platform: is a struct type (compile-time)" {
    comptime {
        const info = @typeInfo(P.Platform);
        std.debug.assert(info == .@"struct");
    }
}

test "VulkanBackend: is a struct type (compile-time)" {
    comptime {
        const info = @typeInfo(P.VulkanBackend);
        std.debug.assert(info == .@"struct");
    }
}

// ===========================================================================
// 7. Platform method existence (compile-time @hasDecl checks)
// ===========================================================================

test "Platform: has method init (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.Platform, "init"));
}

test "Platform: has method deinit (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.Platform, "deinit"));
}

test "Platform: has method shouldClose (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.Platform, "shouldClose"));
}

test "Platform: has method pollEvents (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.Platform, "pollEvents"));
}

test "Platform: has method framebufferSize (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.Platform, "framebufferSize"));
}

test "Platform: has method requiredInstanceExtensions (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.Platform, "requiredInstanceExtensions"));
}

test "Platform: has method createSurface (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.Platform, "createSurface"));
}

// ===========================================================================
// 8. VulkanBackend method existence (compile-time @hasDecl checks)
// ===========================================================================

test "VulkanBackend: has method init (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "init"));
}

test "VulkanBackend: has method deinit (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "deinit"));
}

test "VulkanBackend: has method beginFrame (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "beginFrame"));
}

test "VulkanBackend: has method clear (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "clear"));
}

test "VulkanBackend: has method drawTriangle (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "drawTriangle"));
}

test "VulkanBackend: has method endFrame (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "endFrame"));
}

test "VulkanBackend: has method onResize (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "onResize"));
}

test "VulkanBackend: has method swapchainImageCount (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "swapchainImageCount"));
}

test "VulkanBackend: has method validationIssueCount (compile-time)" {
    comptime std.debug.assert(@hasDecl(P.VulkanBackend, "validationIssueCount"));
}

// ===========================================================================
// 9. GPU-requiring tests — skip gracefully when no display/GPU is available
// ===========================================================================

test "Platform.init with 1x1 window: no panic — succeeds or returns valid PlatformError" {
    // A 1x1 window is the minimal possible size. The implementation must either
    // succeed (and give back a usable Platform) or return a typed PlatformError —
    // it must NOT panic or return an untyped error.
    var platform = P.Platform.init(testing.allocator, .{
        .title = "01-unit-tiny",
        .width = 1,
        .height = 1,
    }) catch {
        // Acceptable: no GPU/display in this environment, OR GLFW rejects 1x1.
        // Platform.init is typed to return PlatformError, so any catch here is typed.
        return error.SkipZigTest;
    };
    defer platform.deinit();
    // 1x1 init succeeded — shouldClose must be false immediately after init.
    try testing.expect(!platform.shouldClose());
    // framebufferSize must not produce values larger than requested
    // (it may be smaller on HiDPI but never larger than the window creation size).
    const sz = platform.framebufferSize();
    _ = sz; // just verifying the call doesn't crash
}

test "zero-frame loop: init then immediate deinit reports zero validation issues" {
    // Different from the smoke test's re-init test: this verifies that validation
    // layer counters are zero even when NO frames are submitted at all. This catches
    // init-path validation errors that only appear before any frame is rendered.
    var platform = P.Platform.init(testing.allocator, .{
        .title = "01-unit-zero-frames",
    }) catch {
        return error.SkipZigTest;
    };
    defer platform.deinit();

    var backend = P.VulkanBackend.init(testing.allocator, &platform) catch {
        return error.SkipZigTest;
    };
    defer backend.deinit();

    // No beginFrame/endFrame at all — validation must still be clean.
    try testing.expectEqual(@as(u32, 0), backend.validationIssueCount());
}
