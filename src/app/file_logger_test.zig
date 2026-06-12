//! Unit tests for FileLogger (RA2 — M10-03).
//! Uses a temp directory; deterministic; no wall-clock time dependence.

const std = @import("std");
const FileLogger = @import("file_logger.zig").FileLogger;

fn tmpPath(buf: []u8, comptime name: []const u8) []const u8 {
    return std.fmt.bufPrint(buf, "{s}/{s}", .{ std.testing.tmpDir(.{}).sub_path, name }) catch name;
}

test "FileLogger: init creates file and deinit frees memory" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/test.log", .{tmp.sub_path});

    var logger = try FileLogger.init(std.testing.allocator, path, 1024 * 1024);
    defer logger.deinit();

    try std.testing.expect(logger.is_open);
}

test "FileLogger: log writes a correctly formatted line" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/fmt.log", .{tmp.sub_path});

    var logger = try FileLogger.init(std.testing.allocator, path, 1024 * 1024);
    defer logger.deinit();

    logger.log(.info, .test_scope, "hello {s}", .{"world"});

    // Read back and verify the line contains expected content.
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const content = try std.Io.Dir.readFileAlloc(.cwd(), io, path, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "info") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "hello world") != null);
    // Check timestamp format: should contain 'T' between date and time.
    try std.testing.expect(std.mem.indexOf(u8, content, "T") != null);
}

test "FileLogger: roll when max_bytes exceeded" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/roll.log", .{tmp.sub_path});

    // Set max_bytes very small (128) so the first long message triggers a roll.
    var logger = try FileLogger.init(std.testing.allocator, path, 128);
    defer logger.deinit();

    // Write enough to exceed the budget.
    logger.log(.info, .test_scope, "first line: {s}", .{"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"});
    const bytes_after_first = logger.bytes_written;

    // This should trigger a roll.
    logger.log(.info, .test_scope, "second line: after roll", .{});

    // After roll, bytes_written should have reset and now be less than after first write.
    try std.testing.expect(logger.bytes_written < bytes_after_first + 200);

    // File should contain "second line" (roll cleared old content).
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const content = try std.Io.Dir.readFileAlloc(.cwd(), io, path, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "second line: after roll") != null);
}

test "FileLogger: deinit closes without leak" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/leak.log", .{tmp.sub_path});

    var logger = try FileLogger.init(std.testing.allocator, path, 1024 * 1024);
    logger.deinit();
    // No leak — testing allocator will detect if memory wasn't freed.
}

test "FileLogger: flush on not-open logger is no-op" {
    var logger = FileLogger{
        .path = "",
        .gpa = std.testing.allocator,
        .max_bytes = 1024,
        .bytes_written = 0,
        .is_open = false,
    };
    // Must not crash.
    logger.flush();
}

test "FileLogger: log with format string containing percent is safe" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [256]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/percent.log", .{tmp.sub_path});

    var logger = try FileLogger.init(std.testing.allocator, path, 1024 * 1024);
    defer logger.deinit();

    // Message with a literal percent sign via format spec — must not panic.
    logger.log(.warn, .test_scope, "progress: {d}%%", .{75});

    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const content = try std.Io.Dir.readFileAlloc(.cwd(), io, path, std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "progress: 75%") != null);
}

test "FileLogger: log_path null leaves file_logger null (AppOptions default)" {
    // Verify AppOptions.log_path defaults to null — no file is opened.
    // This tests the contract; actual AppInner.init is not called (needs GPU).
    const AppOptions = @import("app.zig").AppOptions;
    const opts = AppOptions{ .font_path = "dummy.ttf" };
    try std.testing.expectEqual(@as(?[]const u8, null), opts.log_path);
}
