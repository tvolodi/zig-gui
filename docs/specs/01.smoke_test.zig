//! 01 — Platform spike — smoke_test.zig
//!
//! This is the AUTOMATABLE half of "done" (see spec.md "Definition of done"). It is NOT a
//! pure unit test: it requires a machine with a working GPU and display (or a headless
//! Vulkan surface). It is the executable specification of the parts that CAN be checked
//! without a human (INV-5.3 still applies — DO NOT edit this to make an implementation pass).
//!
//! The VISUAL confirmation (a window actually shows the color + triangle, resizes, closes)
//! is the MANUAL half and lives in checklist.md. This file prints instructions for it.
//!
//! Run with: `zig test smoke_test.zig`   (on a GPU-capable machine)
//! Or build the spike app and run it by hand for the visual check.

const std = @import("std");
const testing = std.testing;
const P = @import("types.zig");

// How many frames the headless-ish smoke run records/presents before tearing down.
const SMOKE_FRAMES: u32 = 30;

// ---------------------------------------------------------------------------
// 1. Bring-up succeeds: window, Vulkan, swapchain with at least one image.
// ---------------------------------------------------------------------------
test "vulkan bring-up succeeds with a valid swapchain" {
    var platform = P.Platform.init(testing.allocator, .{
        .title = "smoke",
        .width = 640,
        .height = 400,
    }) catch |e| {
        // No display/GPU in this environment → skip rather than fail.
        std.debug.print("skipping: platform init failed ({s})\n", .{@errorName(e)});
        return error.SkipZigTest;
    };
    defer platform.deinit();

    var backend = P.VulkanBackend.init(testing.allocator, &platform) catch |e| {
        std.debug.print("skipping: backend init failed ({s})\n", .{@errorName(e)});
        return error.SkipZigTest;
    };
    defer backend.deinit();

    try testing.expect(backend.swapchainImageCount() >= 1);
}

// ---------------------------------------------------------------------------
// 2. A run of frames records, draws, and presents without validation issues.
// ---------------------------------------------------------------------------
test "frames present cleanly with zero validation issues" {
    var platform = P.Platform.init(testing.allocator, .{ .title = "smoke" }) catch {
        return error.SkipZigTest;
    };
    defer platform.deinit();

    var backend = P.VulkanBackend.init(testing.allocator, &platform) catch {
        return error.SkipZigTest;
    };
    defer backend.deinit();

    var frames: u32 = 0;
    while (frames < SMOKE_FRAMES) : (frames += 1) {
        platform.pollEvents();
        if (!backend.beginFrame()) continue; // swapchain was recreated; retry next loop
        backend.clear(.{ .r = 0.10, .g = 0.12, .b = 0.16 });
        backend.drawTriangle();
        backend.endFrame();
    }

    // The single strongest automatable correctness signal: validation layers stayed silent.
    try testing.expectEqual(@as(u32, 0), backend.validationIssueCount());
}

// ---------------------------------------------------------------------------
// 3. Init → deinit → init again does not leak or corrupt state.
//    (Catches teardown-order bugs, which are the most common Vulkan spike mistake.)
// ---------------------------------------------------------------------------
test "clean teardown allows re-init" {
    var platform = P.Platform.init(testing.allocator, .{ .title = "smoke" }) catch {
        return error.SkipZigTest;
    };
    defer platform.deinit();

    {
        var b1 = P.VulkanBackend.init(testing.allocator, &platform) catch {
            return error.SkipZigTest;
        };
        try testing.expectEqual(@as(u32, 0), b1.validationIssueCount());
        b1.deinit();
    }
    {
        var b2 = try P.VulkanBackend.init(testing.allocator, &platform);
        defer b2.deinit();
        try testing.expect(b2.swapchainImageCount() >= 1);
        try testing.expectEqual(@as(u32, 0), b2.validationIssueCount());
    }
}

// ---------------------------------------------------------------------------
// Manual-check reminder. Always "passes"; its only job is to print the human steps so
// they are never forgotten when reading test output.
// ---------------------------------------------------------------------------
test "MANUAL: confirm visually on Windows AND Linux" {
    std.debug.print(
        \\
        \\  [MANUAL VERIFICATION REQUIRED — both halves of "done"]
        \\  Run the spike app by hand on BOTH target OSes and confirm:
        \\    1. A window opens at the requested size.
        \\    2. It shows the clear color with a visible triangle.
        \\    3. Resizing the window does not crash and the image stays correct.
        \\    4. Closing the window exits cleanly (no validation errors on shutdown).
        \\  Record both OS confirmations in checklist.md. This module is NOT done until
        \\  the manual check passes on Windows and on Linux.
        \\
    , .{});
}
