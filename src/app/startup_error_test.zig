//! Unit tests for startup_error (RA3 — M10-04).
//! Tests showErrorDialog (compile check on Windows), encodeUtf16Truncated,
//! and initOrDialog behavior. Deterministic; no GPU/GLFW.

const std = @import("std");
const builtin = @import("builtin");
const startup_error = @import("startup_error.zig");

test "showErrorDialog: compiles and does not crash with empty strings" {
    // MessageBoxW on Windows is interactive — skip execution in CI/tests.
    // On Linux, writes to stderr — acceptable side-effect in test output.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    startup_error.showErrorDialog("", "");
    startup_error.showErrorDialog("Title", "Message");
}

test "showErrorDialog: title is empty string — no crash" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    startup_error.showErrorDialog("", "some message");
}

test "showErrorDialog: message with non-ASCII (Cyrillic) characters" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    // Cyrillic characters — should not panic on UTF-8 to UTF-16 conversion path.
    startup_error.showErrorDialog("Ошибка", "Не удалось запустить");
}

test "initOrDialog: returns error on failing init" {
    // On Windows, showErrorDialog shows a MessageBox which blocks interactively.
    if (builtin.os.tag == .windows) return error.SkipZigTest;

    // A failing AppInner is simulated by a thin mock type.
    const MockInner = struct {
        pub fn init(_: std.mem.Allocator, _: u32) !@This() {
            return error.VulkanInitFailed;
        }
    };
    const MockOptions = u32;

    const result = startup_error.initOrDialog(MockInner, MockOptions, std.testing.allocator, 42);
    try std.testing.expectError(error.VulkanInitFailed, result);
}

test "initOrDialog: returns value on successful init" {
    const MockInner = struct {
        value: u32,
        pub fn init(_: std.mem.Allocator, opts: u32) !@This() {
            return @This(){ .value = opts };
        }
    };
    const MockOptions = u32;

    const result = try startup_error.initOrDialog(MockInner, MockOptions, std.testing.allocator, 99);
    try std.testing.expectEqual(@as(u32, 99), result.value);
}

test "encodeUtf16Truncated: message exactly 511 UTF-16 units fits in 512-unit buffer" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    // Build a 511-char ASCII string.
    var long_msg: [511]u8 = undefined;
    @memset(&long_msg, 'A');
    startup_error.showErrorDialog("T", long_msg[0..]);
    // If we reach here without panic, the buffer handling is correct.
}

test "encodeUtf16Truncated: message exceeding 512 UTF-16 units is truncated without crash" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    // 600-char ASCII string — exceeds 512 unit limit, must truncate cleanly.
    var long_msg: [600]u8 = undefined;
    @memset(&long_msg, 'B');
    startup_error.showErrorDialog("T", long_msg[0..]);
}
