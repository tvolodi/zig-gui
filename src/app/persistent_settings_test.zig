//! R82 — PersistentSettings acceptance tests.
//!
//! All file I/O tests use a real temp directory via std.testing.tmpDir.
//! Tests call loadAbsolute() to bypass the env-var path resolution so they
//! are hermetic and do not touch %APPDATA% / $HOME.

const std = @import("std");
const ps_mod = @import("persistent_settings.zig");
const PersistentSettings = ps_mod.PersistentSettings;

// ---------------------------------------------------------------------------
// Helper: obtain the absolute path of the tmpDir, then append `rel`.
// Returns a slice into `buf`.
// ---------------------------------------------------------------------------

fn tmpPath(tmp: *std.testing.TmpDir, rel: []const u8, buf: []u8) ![]const u8 {
    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const n = try std.Io.Dir.realPath(tmp.dir, std.testing.io, &path_buf);
    const dir_path = path_buf[0..n];
    if (rel.len == 0) {
        if (dir_path.len > buf.len) return error.NameTooLong;
        @memcpy(buf[0..dir_path.len], dir_path);
        return buf[0..dir_path.len];
    }
    return std.fmt.bufPrint(buf, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ dir_path, rel });
}

// ---------------------------------------------------------------------------
// Test 1: load on non-existent file → creates file + dirs, no error.
// ---------------------------------------------------------------------------
test "load: non-existent path creates file and dirs without error" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "subdir/settings.txt", &path_buf);

    var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
    defer prefs.deinit();

    // File should now exist; re-loading should also succeed.
    var prefs2 = try PersistentSettings.loadAbsolute(gpa, abs_path);
    defer prefs2.deinit();
}

// ---------------------------------------------------------------------------
// Test 2: setU32 + flush + fresh load round-trips correctly.
// ---------------------------------------------------------------------------
test "setU32 + flush + load: round-trip" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    {
        var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs.deinit();

        try prefs.setU32("window_width", 1400);
        try std.testing.expect(prefs.isDirty());
        try prefs.flush();
        try std.testing.expect(!prefs.isDirty());
    }

    {
        var prefs2 = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs2.deinit();

        const v = prefs2.getU32("window_width");
        try std.testing.expect(v != null);
        try std.testing.expectEqual(@as(u32, 1400), v.?);
    }
}

// ---------------------------------------------------------------------------
// Test 3: setString with special chars round-trips correctly.
// ---------------------------------------------------------------------------
test "setString: special characters round-trip (=, newline, %)" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    const weird = "key=val\nand%more";

    {
        var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs.deinit();
        try prefs.setString("data", weird);
        try prefs.flush();
    }

    {
        var prefs2 = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs2.deinit();
        const v = prefs2.getString("data");
        try std.testing.expect(v != null);
        try std.testing.expectEqualStrings(weird, v.?);
    }
}

// ---------------------------------------------------------------------------
// Test 4: getBool returns null for a key that holds u32 (type mismatch).
// ---------------------------------------------------------------------------
test "getBool: type mismatch returns null" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
    defer prefs.deinit();

    try prefs.setU32("counter", 42);
    try std.testing.expect(prefs.getBool("counter") == null);
    try std.testing.expectEqual(@as(?u32, 42), prefs.getU32("counter"));
}

// ---------------------------------------------------------------------------
// Test 5: flush is a no-op when isDirty() is false.
// ---------------------------------------------------------------------------
test "flush: no-op when not dirty" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
    defer prefs.deinit();

    try std.testing.expect(!prefs.isDirty());
    try prefs.flush();
    try std.testing.expect(!prefs.isDirty());
}

// ---------------------------------------------------------------------------
// Test 6: deinit produces no leaks (testing.allocator will catch them).
// ---------------------------------------------------------------------------
test "deinit: no memory leaks" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
    try prefs.setU32("a", 1);
    try prefs.setI32("b", -2);
    try prefs.setF32("c", 3.14);
    try prefs.setBool("d", true);
    try prefs.setString("e", "hello world");
    try prefs.flush();
    prefs.deinit(); // testing.allocator checks for leaks after this test.
}

// ---------------------------------------------------------------------------
// Test 7: comment and blank lines are preserved on flush.
// ---------------------------------------------------------------------------
test "flush: comment and blank lines preserved" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    // Write a file that contains comments and blank lines.
    const initial_content =
        "# This is a comment\n" ++
        "\n" ++
        "# Another comment\n";
    try std.Io.Dir.writeFile(.cwd(), std.testing.io, .{
        .sub_path = abs_path,
        .data = initial_content,
    });

    // Load, add an entry, flush.
    {
        var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs.deinit();
        try prefs.setU32("x", 99);
        try prefs.flush();
    }

    // Read the file back and verify comments are still present.
    const written = try std.Io.Dir.readFileAlloc(.cwd(), std.testing.io, abs_path, gpa, .unlimited);
    defer gpa.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "# This is a comment") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "# Another comment") != null);
    try std.testing.expect(std.mem.indexOf(u8, written, "x=u32:99") != null);
}

// ---------------------------------------------------------------------------
// Test 8: unknown value prefix silently ignored on load; not emitted on flush.
// ---------------------------------------------------------------------------
test "load: unknown value prefix silently ignored; not re-emitted on flush" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    try std.Io.Dir.writeFile(.cwd(), std.testing.io, .{
        .sub_path = abs_path,
        .data = "future_key=v9:some_future_value\nknown=u32:7\n",
    });

    {
        var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs.deinit();

        try std.testing.expect(prefs.getU32("future_key") == null);
        try std.testing.expect(prefs.getI32("future_key") == null);
        try std.testing.expectEqual(@as(?u32, 7), prefs.getU32("known"));

        // Force flush.
        try prefs.setU32("extra", 1);
        try prefs.flush();
    }

    // future_key must not appear in flushed output.
    const written = try std.Io.Dir.readFileAlloc(.cwd(), std.testing.io, abs_path, gpa, .unlimited);
    defer gpa.free(written);

    try std.testing.expect(std.mem.indexOf(u8, written, "future_key") == null);
    try std.testing.expect(std.mem.indexOf(u8, written, "known=u32:7") != null);
}

// ---------------------------------------------------------------------------
// Test 9: remove absent key → no error, isDirty unchanged.
// ---------------------------------------------------------------------------
test "remove: absent key is a no-op, isDirty unchanged" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
    defer prefs.deinit();

    try std.testing.expect(!prefs.isDirty());
    prefs.remove("nonexistent_key");
    try std.testing.expect(!prefs.isDirty());
}

// ---------------------------------------------------------------------------
// Test 10: setString twice → second replaces first; no leak.
// ---------------------------------------------------------------------------
test "setString: second call replaces first; no memory leak" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "settings.txt", &path_buf);

    var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
    defer prefs.deinit();

    try prefs.setString("msg", "first value");
    try prefs.setString("msg", "second value"); // must free "first value"

    const v = prefs.getString("msg");
    try std.testing.expect(v != null);
    try std.testing.expectEqualStrings("second value", v.?);
    // testing.allocator will catch a leak if "first value" was not freed.
}

// ---------------------------------------------------------------------------
// Test 11: app_name with path separator returns error.InvalidAppName.
// ---------------------------------------------------------------------------
test "load: app_name with path separator returns error.InvalidAppName" {
    const gpa = std.testing.allocator;

    try std.testing.expectError(error.InvalidAppName, PersistentSettings.load(gpa, "some/app"));
    try std.testing.expectError(error.InvalidAppName, PersistentSettings.load(gpa, "some\\app"));
    try std.testing.expectError(error.InvalidAppName, PersistentSettings.load(gpa, ""));
}

// ---------------------------------------------------------------------------
// Test 12: all scalar types round-trip correctly in a single file.
// ---------------------------------------------------------------------------
test "all types: round-trip via flush + load" {
    const gpa = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_path = try tmpPath(&tmp, "all_types.txt", &path_buf);

    {
        var prefs = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs.deinit();
        try prefs.setU32("u", 4294967295);
        try prefs.setI32("i", -2147483648);
        try prefs.setF32("f", 1.5);
        try prefs.setBool("bt", true);
        try prefs.setBool("bf", false);
        try prefs.setString("s", "hello");
        try prefs.flush();
    }

    {
        var prefs2 = try PersistentSettings.loadAbsolute(gpa, abs_path);
        defer prefs2.deinit();
        try std.testing.expectEqual(@as(?u32, 4294967295), prefs2.getU32("u"));
        try std.testing.expectEqual(@as(?i32, -2147483648), prefs2.getI32("i"));
        try std.testing.expect(prefs2.getF32("f") != null);
        try std.testing.expectApproxEqAbs(@as(f32, 1.5), prefs2.getF32("f").?, 0.0001);
        try std.testing.expectEqual(@as(?bool, true), prefs2.getBool("bt"));
        try std.testing.expectEqual(@as(?bool, false), prefs2.getBool("bf"));
        const sv = prefs2.getString("s");
        try std.testing.expect(sv != null);
        try std.testing.expectEqualStrings("hello", sv.?);
    }
}
