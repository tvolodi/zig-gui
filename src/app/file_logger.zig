//! RA2 — M10-03: Release logging.
//!
//! FileLogger writes timestamped log lines to a file on disk.
//! The file rolls (truncates to zero) when it exceeds max_bytes.
//! INV-5.6: uses only std.Io / std.fs.path — no new dependencies.
//! INV-1.2: works on both Windows and Linux via std.Io.

const std = @import("std");

pub const FileLogger = struct {
    /// Owned path to the log file (absolute or relative).
    path: []const u8,
    gpa: std.mem.Allocator,
    /// Roll threshold in bytes. 0 means unlimited.
    max_bytes: usize,
    bytes_written: usize,
    is_open: bool,

    /// Open (or create) the log file at `path`. Creates parent directories.
    /// Returns a fully initialised FileLogger on success.
    pub fn init(gpa: std.mem.Allocator, path: []const u8, max_bytes: usize) !FileLogger {
        const path_owned = try gpa.dupe(u8, path);
        errdefer gpa.free(path_owned);

        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        // Create parent directories if needed.
        if (std.fs.path.dirname(path_owned)) |dir_path| {
            std.Io.Dir.createDirPath(.cwd(), io, dir_path) catch |e| switch (e) {
                error.PathAlreadyExists => {},
                else => {}, // best-effort; createFile will fail explicitly if needed
            };
        }

        // Create or open the file.
        {
            const f = try std.Io.Dir.createFile(.cwd(), io, path_owned, .{ .truncate = false });
            f.close(io);
        }

        // Measure existing size for bytes_written tracking.
        const bytes_written: usize = blk: {
            const content = std.Io.Dir.readFileAlloc(.cwd(), io, path_owned, gpa, .unlimited) catch break :blk 0;
            defer gpa.free(content);
            break :blk content.len;
        };

        return FileLogger{
            .path = path_owned,
            .gpa = gpa,
            .max_bytes = max_bytes,
            .bytes_written = bytes_written,
            .is_open = true,
        };
    }

    /// Flush and close the file. Frees owned memory.
    pub fn deinit(self: *FileLogger) void {
        self.gpa.free(self.path);
        self.is_open = false;
    }

    /// Write one log line. Format:
    ///   YYYY-MM-DDTHH:MM:SS [LEVEL] message\n
    /// If `bytes_written` would exceed `max_bytes` after this write, truncate the file
    /// first (roll) and reset `bytes_written` to 0.
    pub fn log(
        self: *FileLogger,
        level: std.log.Level,
        scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = scope;
        if (!self.is_open) return;

        // Format the message.
        var msg_buf: [1024]u8 = undefined;
        const msg = std.fmt.bufPrint(&msg_buf, format, args) catch "(message formatting failed)";

        const level_str: []const u8 = switch (level) {
            .err => "err  ",
            .warn => "warn ",
            .info => "info ",
            .debug => "debug",
        };

        // Build timestamp from monotonic nanoseconds ÷ 1e9 for seconds.
        // std.time.timestamp() was removed in Zig 0.16; use std.Io.Clock instead.
        const epoch_secs: i64 = blk: {
            var ts_threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
            defer ts_threaded.deinit();
            const ts_io = ts_threaded.io();
            const ns: i128 = std.Io.Clock.real.now(ts_io).nanoseconds;
            break :blk @intCast(@divFloor(ns, 1_000_000_000));
        };
        const epoch_day = std.time.epoch.EpochSeconds{
            .secs = @as(u64, @intCast(@max(0, epoch_secs))),
        };
        const day_seconds = epoch_day.getDaySeconds();
        const year_day = epoch_day.getEpochDay().calculateYearDay();
        const month_day = year_day.calculateMonthDay();

        var line_buf: [2048]u8 = undefined;
        const line = std.fmt.bufPrint(&line_buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2} [{s}] {s}\n", .{
            year_day.year,
            month_day.month.numeric(),
            month_day.day_index + 1,
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
            level_str,
            msg,
        }) catch return;

        const line_len = line.len;

        // Read-modify-write: build the new content.
        var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
        defer threaded.deinit();
        const io = threaded.io();

        if (self.max_bytes > 0 and self.bytes_written + line_len > self.max_bytes) {
            // Roll: truncate file and write fresh.
            writeToFile(io, self.path, line, true) catch return;
            self.bytes_written = line_len;
        } else {
            // Append to existing file.
            appendToFile(io, self.gpa, self.path, line) catch return;
            self.bytes_written += line_len;
        }
    }

    /// Flush buffered writes to disk. (Each write is already immediate; this is a no-op.)
    pub fn flush(self: *FileLogger) void {
        _ = self;
    }

    // -----------------------------------------------------------------------
    // Private helpers
    // -----------------------------------------------------------------------

    fn writeToFile(io: std.Io, path: []const u8, content: []const u8, truncate: bool) !void {
        const f = try std.Io.Dir.createFile(.cwd(), io, path, .{ .truncate = truncate });
        defer f.close(io);
        try std.Io.File.writeStreamingAll(f, io, content);
    }

    fn appendToFile(io: std.Io, gpa: std.mem.Allocator, path: []const u8, content: []const u8) !void {
        // Read existing, append new content, rewrite.
        const existing = std.Io.Dir.readFileAlloc(.cwd(), io, path, gpa, .unlimited) catch "";
        defer if (existing.len > 0) gpa.free(existing);

        const f = try std.Io.Dir.createFile(.cwd(), io, path, .{ .truncate = true });
        defer f.close(io);
        if (existing.len > 0) {
            try std.Io.File.writeStreamingAll(f, io, existing);
        }
        try std.Io.File.writeStreamingAll(f, io, content);
    }
};
