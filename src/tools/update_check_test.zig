// Unit tests for update_check.zig — M19-01
// Tests cover only the pure isNewerVersion function (no network required).

const std = @import("std");
const update_check = @import("update_check.zig");

test "isNewerVersion: newer patch" {
    try std.testing.expect(update_check.isNewerVersion("1.0.1", "1.0.0"));
}

test "isNewerVersion: newer minor" {
    try std.testing.expect(update_check.isNewerVersion("1.1.0", "1.0.9"));
}

test "isNewerVersion: newer major" {
    try std.testing.expect(update_check.isNewerVersion("2.0.0", "1.9.9"));
}

test "isNewerVersion: same version" {
    try std.testing.expect(!update_check.isNewerVersion("1.0.0", "1.0.0"));
}

test "isNewerVersion: older" {
    try std.testing.expect(!update_check.isNewerVersion("0.9.9", "1.0.0"));
}

test "isNewerVersion: pre-release suffix stripped" {
    try std.testing.expect(update_check.isNewerVersion("1.1.0-rc1", "1.0.0"));
}

test "isNewerVersion: both same with pre-release suffix" {
    // "1.0.0-rc1" numerics equal "1.0.0" — not newer
    try std.testing.expect(!update_check.isNewerVersion("1.0.0-rc1", "1.0.0"));
}

test "isNewerVersion: missing patch component treated as 0" {
    try std.testing.expect(!update_check.isNewerVersion("1.0", "1.0.0"));
    try std.testing.expect(update_check.isNewerVersion("1.1", "1.0.0"));
}
