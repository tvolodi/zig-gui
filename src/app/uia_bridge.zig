//! RG3 — Windows UI Automation (UIA) bridge
//!
//! Exposes the Scene's AccessNode tree to Windows screen readers (Narrator, NVDA)
//! via COM/UIA (UI Automation). Uses IRawElementProvider interface.
//! On Linux, all methods are stubs (AT-SPI2 is handled separately in atspi_bridge.zig).
//! On Windows, registers element providers and handles UIA queries.

const std = @import("std");
const builtin = @import("builtin");
const Scene = @import("../07/types.zig").Scene;
const AccessRole = @import("../07/types.zig").AccessRole;
const mod01 = @import("../01/types.zig");

// Platform-specific dispatch
const is_windows = builtin.os.tag == .windows;

pub const UiaBridge = if (is_windows) UiaBridgeWindows else UiaBridgeStub;

// ============================================================================
// Linux stub — no-op on non-Windows
// ============================================================================

pub const UiaBridgeStub = struct {
    pub fn init(
        scene: *Scene,
        platform: *mod01.Platform,
        app_name: []const u8,
        allocator: std.mem.Allocator,
    ) !UiaBridgeStub {
        _ = scene;
        _ = platform;
        _ = app_name;
        _ = allocator;
        return .{};
    }

    pub fn deinit(self: *UiaBridgeStub) void {
        _ = self;
    }

    pub fn tick(self: *UiaBridgeStub) void {
        _ = self;
    }

    pub fn markElementChanged(self: *UiaBridgeStub, idx: u32) void {
        _ = self;
        _ = idx;
    }

    pub fn markTreeChanged(self: *UiaBridgeStub) void {
        _ = self;
    }
};

// ============================================================================
// Windows implementation (stub pending COM integration)
// ============================================================================

pub const UiaBridgeWindows = struct {
    scene: *Scene,
    platform: *mod01.Platform,
    app_name: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(
        scene: *Scene,
        platform: *mod01.Platform,
        app_name: []const u8,
        allocator: std.mem.Allocator,
    ) !UiaBridgeWindows {
        return .{
            .scene = scene,
            .platform = platform,
            .app_name = app_name,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *UiaBridgeWindows) void {
        _ = self;
        // TODO: Release COM objects, unregister UIA provider
    }

    pub fn tick(self: *UiaBridgeWindows) void {
        _ = self;
        // TODO: Raise UIA events (via UiaRaiseAutomationEvent)
    }

    pub fn markElementChanged(self: *UiaBridgeWindows, idx: u32) void {
        _ = self;
        _ = idx;
        // TODO: Enqueue a UIA PropertyChanged event for the changed element
    }

    pub fn markTreeChanged(self: *UiaBridgeWindows) void {
        _ = self;
        // TODO: Raise a UIA TreeChanged event for screen readers to refresh
    }
};

/// Map AccessRole to UIA ControlType ID (for Windows UIA).
/// Called during GetPropertyValue(UIA_ControlTypePropertyId, ...).
pub fn uiaControlTypeFor(role: AccessRole) u32 {
    return switch (role) {
        .button => 50000, // UIA_ButtonControlTypeId
        .text => 50020, // UIA_TextControlTypeId
        .textbox => 50004, // UIA_EditControlTypeId
        .checkbox => 50003, // UIA_CheckBoxControlTypeId
        .radio => 50021, // UIA_RadioButtonControlTypeId
        .combobox => 50002, // UIA_ComboBoxControlTypeId
        .listbox => 50008, // UIA_ListControlTypeId
        .option => 50010, // UIA_ListItemControlTypeId
        .listitem => 50010, // UIA_ListItemControlTypeId
        .slider => 50014, // UIA_SliderControlTypeId
        .spinbutton => 50016, // UIA_SpinnerControlTypeId
        .textarea => 50004, // UIA_EditControlTypeId
        .tab => 50018, // UIA_TabItemControlTypeId
        .tablist => 50017, // UIA_TabControlTypeId
        .tabpanel => 50029, // UIA_PaneControlTypeId
        .progressbar => 50033, // UIA_ProgressBarControlTypeId
        .dialog => 50032, // UIA_WindowControlTypeId
        .menu => 50025, // UIA_MenuControlTypeId
        .menuitem => 50026, // UIA_MenuItemControlTypeId
        .tooltip => 50027, // UIA_ToolTipControlTypeId
        .img => 50007, // UIA_ImageControlTypeId
        .link => 50005, // UIA_HyperlinkControlTypeId
        .list => 50013, // UIA_GroupControlTypeId
        .region => 50013, // UIA_GroupControlTypeId
        .none => 50025, // UIA_CustomControlTypeId
        .menuitemcheckbox => 50026, // menu item as fallback
        .menuitemradio => 50026, // menu item as fallback
        else => 50025, // UIA_CustomControlTypeId for any unhandled role
    };
}
