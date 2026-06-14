// Update manifest check — M19-01
// Fetches a JSON manifest from a URL and returns whether a newer version is available.
// Called from App.init if update_manifest_url is set in AppConfig.
//
// Note: std.http.Client in Zig 0.16 requires an std.Io handle (for async I/O).
// Callers must pass the io value from their std.process.Init context.

const std = @import("std");

pub const UpdateCheckResult = struct {
    available: bool,
    latest_version: []const u8,
    download_url: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: UpdateCheckResult) void {
        self.allocator.free(self.latest_version);
        self.allocator.free(self.download_url);
    }
};

pub const UpdateCheckError = error{
    NetworkError,
    InvalidManifest,
    OutOfMemory,
};

/// Fetch and parse the update manifest. Returns null if no update is available.
///
/// io:              the std.Io handle from the caller's context (required by std.http.Client in Zig 0.16)
/// manifest_url:    URL of the JSON manifest file (e.g. "https://example.com/manifest.json")
/// current_version: the running app's version string (e.g. "1.0.0")
/// allocator:       arena or gpa; caller owns result — call result.deinit() when done
pub fn checkForUpdate(
    allocator: std.mem.Allocator,
    io: std.Io,
    manifest_url: []const u8,
    current_version: []const u8,
) UpdateCheckError!?UpdateCheckResult {
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    // Use std.Io.Writer.Allocating to grow-collect the response body
    var body_list = std.ArrayList(u8).empty;
    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &body_list);
    errdefer aw.deinit();

    const result = client.fetch(.{
        .location = .{ .url = manifest_url },
        .response_writer = &aw.writer,
    }) catch return UpdateCheckError.NetworkError;

    body_list = aw.toArrayList();
    defer body_list.deinit(allocator);

    if (result.status != .ok) return UpdateCheckError.NetworkError;

    // Parse the JSON manifest: { "version": "1.2.3", "url": "https://..." }
    const parsed = std.json.parseFromSlice(
        struct { version: []const u8, url: []const u8 },
        allocator,
        body_list.items,
        .{ .ignore_unknown_fields = true },
    ) catch return UpdateCheckError.InvalidManifest;
    defer parsed.deinit();

    const latest = parsed.value.version;
    const url = parsed.value.url;

    if (isNewerVersion(latest, current_version)) {
        return UpdateCheckResult{
            .available = true,
            .latest_version = allocator.dupe(u8, latest) catch return UpdateCheckError.OutOfMemory,
            .download_url = allocator.dupe(u8, url) catch return UpdateCheckError.OutOfMemory,
            .allocator = allocator,
        };
    }

    return null;
}

/// Simple semver comparison: returns true if `a` > `b`.
/// Parses "MAJOR.MINOR.PATCH"; ignores pre-release suffixes after '-'.
pub fn isNewerVersion(a: []const u8, b: []const u8) bool {
    var a_it = std.mem.splitScalar(u8, a, '.');
    var b_it = std.mem.splitScalar(u8, b, '.');

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const a_part = a_it.next() orelse "0";
        const b_part = b_it.next() orelse "0";
        // strip any suffix after '-'
        const a_num_str = if (std.mem.indexOfScalar(u8, a_part, '-')) |idx| a_part[0..idx] else a_part;
        const b_num_str = if (std.mem.indexOfScalar(u8, b_part, '-')) |idx| b_part[0..idx] else b_part;
        const av = std.fmt.parseInt(u32, a_num_str, 10) catch 0;
        const bv = std.fmt.parseInt(u32, b_num_str, 10) catch 0;
        if (av > bv) return true;
        if (av < bv) return false;
    }
    return false;
}
