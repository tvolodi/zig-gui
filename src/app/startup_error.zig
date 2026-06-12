//! RA3 — M10-04: Graceful startup failure.
//!
//! showErrorDialog: displays a native OS error dialog.
//! initOrDialog: wraps AppInner.init; shows dialog on failure.
//! INV-5.6: Windows uses MessageBoxW (user32, already linked via GLFW).
//!          Linux uses stderr only (GTK not an approved dependency — INV-5.6).
//! INV-1.2: comptime OS dispatch covers Windows and Linux only. No macOS path.
//!
//! NOTE: This file does NOT import app.zig directly.
//! initOrDialog is a thin generic helper — callers pass AppInner/AppOptions directly.

const std = @import("std");
const builtin = @import("builtin");

/// Display a native OS error dialog and block until the user dismisses it.
/// On Windows: calls MessageBoxW via extern declaration.
/// On Linux:   writes to stderr (native dialog requires GTK, which is out of scope).
pub fn showErrorDialog(title: []const u8, message: []const u8) void {
    if (comptime builtin.os.tag == .windows) {
        showErrorDialogWindows(title, message);
    } else {
        // Linux / other: stderr fallback (INV-5.6: no GTK dependency).
        std.io.getStdErr().writer().print("ERROR: {s}: {s}\n", .{ title, message }) catch {};
    }
}

/// Encode a UTF-8 string into a NUL-terminated UTF-16LE buffer.
/// Truncates to fit within max_codeunits (including NUL).
/// Returns a slice of buf including the NUL terminator.
fn encodeUtf16Truncated(s: []const u8, buf: []u16, max_codeunits: usize) []const u16 {
    std.debug.assert(max_codeunits >= 1);
    var len: usize = 0;
    var view = std.unicode.Utf8View.init(s) catch {
        buf[0] = 0;
        return buf[0..1];
    };
    var iter = view.iterator();
    while (iter.nextCodepoint()) |cp| {
        if (cp < 0x10000) {
            // Need 1 code unit + 1 for NUL.
            if (len + 1 >= max_codeunits) break;
            buf[len] = @intCast(cp);
            len += 1;
        } else {
            // Surrogate pair: need 2 code units + 1 for NUL.
            if (len + 2 >= max_codeunits) break;
            const v = cp - 0x10000;
            buf[len] = @intCast(0xD800 + (v >> 10));
            buf[len + 1] = @intCast(0xDC00 + (v & 0x3FF));
            len += 2;
        }
    }
    buf[len] = 0;
    return buf[0 .. len + 1];
}

/// Windows-specific implementation using MessageBoxW (user32).
/// user32 is already linked transitively through GLFW (INV-5.6).
fn showErrorDialogWindows(title: []const u8, message: []const u8) void {
    if (comptime builtin.os.tag != .windows) return;

    const MAX_UTF16: usize = 512;
    var title_buf: [MAX_UTF16]u16 = undefined;
    var msg_buf: [MAX_UTF16]u16 = undefined;

    const title_utf16 = encodeUtf16Truncated(title, &title_buf, MAX_UTF16);
    const msg_utf16 = encodeUtf16Truncated(message, &msg_buf, MAX_UTF16);

    const MB_OK: u32 = 0x00000000;
    const MB_ICONERROR: u32 = 0x00000010;

    // user32 is already linked — use extern declaration.
    const MessageBoxW_fn = *const fn (hWnd: ?*anyopaque, lpText: [*:0]const u16, lpCaption: [*:0]const u16, uType: u32) callconv(.winapi) i32;
    const MessageBoxW = @extern(MessageBoxW_fn, .{ .name = "MessageBoxW" });
    _ = MessageBoxW(null, @ptrCast(msg_utf16.ptr), @ptrCast(title_utf16.ptr), MB_OK | MB_ICONERROR);
}

/// Run `AppInner.init` and, on failure, display a native error dialog before returning the error.
/// Intended to be called from `main`:
///
///   const app = try startup_error.initOrDialog(AppInner, gpa, opts);
///
/// Uses a stack buffer for the error message — no allocation needed.
pub fn initOrDialog(
    comptime AppInner: type,
    comptime AppOptions: type,
    gpa: std.mem.Allocator,
    opts: AppOptions,
) !AppInner {
    return AppInner.init(gpa, opts) catch |err| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Failed to start: {s}", .{@errorName(err)}) catch "Failed to start";
        showErrorDialog("Application Error", msg);
        return err;
    };
}
