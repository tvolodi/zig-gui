//! RG2 — AT-SPI2 bridge for Linux accessibility (D-Bus)
//!
//! Exposes the Scene's AccessNode tree to screen readers (Orca, NVDA) via AT-SPI2/D-Bus.
//! On Windows, all methods are stubs (UIA is handled separately in uia_bridge.zig).
//! On Linux, registers the app with D-Bus and serves accessibility queries.

const std = @import("std");
const builtin = @import("builtin");
const Scene = @import("../07/types.zig").Scene;

// Platform-specific dispatch
const is_linux = builtin.os.tag == .linux;

pub const AtSpiService = if (is_linux) AtSpiServiceLinux else AtSpiServiceStub;

// ============================================================================
// Windows stub — no-op on non-Linux
// ============================================================================

pub const AtSpiServiceStub = struct {
    pub fn init(
        scene: *Scene,
        app_name: []const u8,
        allocator: std.mem.Allocator,
    ) !AtSpiServiceStub {
        _ = scene;
        _ = app_name;
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *AtSpiServiceStub) void {
        _ = self;
    }

    pub fn tick(self: *AtSpiServiceStub) void {
        _ = self;
    }

    pub fn markElementChanged(self: *AtSpiServiceStub, idx: u32) void {
        _ = self;
        _ = idx;
    }

    pub fn markTreeChanged(self: *AtSpiServiceStub) void {
        _ = self;
    }
};

// ============================================================================
// Linux implementation (stub pending D-Bus integration)
// ============================================================================

pub const AtSpiServiceLinux = struct {
    scene: *Scene,
    app_name: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(
        scene: *Scene,
        app_name: []const u8,
        allocator: std.mem.Allocator,
    ) !AtSpiServiceLinux {
        return .{
            .scene = scene,
            .app_name = app_name,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AtSpiServiceLinux) void {
        _ = self;
        // TODO: Disconnect from D-Bus, unregister service
    }

    pub fn tick(self: *AtSpiServiceLinux) void {
        _ = self;
        // TODO: Process pending D-Bus queries and emit accessibility events
    }

    pub fn markElementChanged(self: *AtSpiServiceLinux, idx: u32) void {
        _ = self;
        _ = idx;
        // TODO: Enqueue a PropertyChanged event for the changed element
    }

    pub fn markTreeChanged(self: *AtSpiServiceLinux) void {
        _ = self;
        // TODO: Enqueue a TreeChanged event for screen readers to re-query
    }
};
