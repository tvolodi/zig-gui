//! RA2 — M10-03: Global log hook.
//!
//! Provides a `pub fn log` that callers include in their `root` module.
//! Writes to stderr (always) and, if a global *FileLogger is set, to the file.
//! INV-5.6: no new dependencies.
//! INV-1.1: when g_logger is null, zero overhead (no file I/O).

const std = @import("std");
const FileLogger = @import("file_logger.zig").FileLogger;

/// Global file logger pointer. Set by AppInner.init when opts.log_path != null.
/// Application code MUST NOT call this directly — use std.log.* instead.
pub var g_logger: ?*FileLogger = null;

/// Drop-in replacement for std.log's default handler.
/// Include in your root module:
///   pub const log = @import("app/logger.zig").log;
pub fn log(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    // Always write to stderr.
    std.log.defaultLog(level, scope, format, args);

    // Also write to file logger if set.
    if (g_logger) |logger| {
        logger.log(level, scope, format, args);
    }
}
