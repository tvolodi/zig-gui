// Delta download and patch application — M19-02
// Downloads a binary patch from a URL and applies it to the current binary.
//
// Note: std.http.Client in Zig 0.16 requires an std.Io handle at all call sites.

const std = @import("std");
const bspatch = @import("bspatch.zig");

pub const DeltaError = error{
    NetworkError,
    PatchError,
    ChecksumMismatch,
    OutOfMemory,
};

pub const DownloadedPatch = struct {
    new_binary: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: DownloadedPatch) void {
        self.allocator.free(self.new_binary);
    }
};

/// Download a BSDFRAW1 patch from `patch_url` and apply it to the binary at `current_binary_path`.
///
/// io:                   the std.Io handle from the caller's context (Zig 0.16 requirement)
/// patch_url:            URL of the .bsdfraw1 patch file
/// current_binary_path:  path to the current binary on disk
/// expected_sha256:      optional 64-character hex SHA256 of the expected new binary; if present,
///                       the applied output is verified before returning
/// Returns a DownloadedPatch; caller must call result.deinit() when done.
pub fn downloadAndApplyPatch(
    allocator: std.mem.Allocator,
    io: std.Io,
    patch_url: []const u8,
    current_binary_path: []const u8,
    expected_sha256: ?[64]u8,
) DeltaError!DownloadedPatch {
    // Read current binary (up to 256 MiB)
    const old_data = std.fs.cwd().readFileAlloc(allocator, current_binary_path, 256 * 1024 * 1024) catch
        return DeltaError.PatchError;
    defer allocator.free(old_data);

    // Download patch via std.http.Client
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    var patch_list = std.ArrayList(u8).empty;
    var aw: std.Io.Writer.Allocating = .fromArrayList(allocator, &patch_list);
    errdefer aw.deinit();

    const result = client.fetch(.{
        .location = .{ .url = patch_url },
        .response_writer = &aw.writer,
    }) catch return DeltaError.NetworkError;

    patch_list = aw.toArrayList();
    defer patch_list.deinit(allocator);

    if (result.status != .ok) return DeltaError.NetworkError;

    // Apply the BSDFRAW1 patch
    const new_binary = bspatch.applyPatch(allocator, old_data, patch_list.items) catch
        return DeltaError.PatchError;
    errdefer allocator.free(new_binary);

    // Verify SHA256 checksum if provided
    if (expected_sha256) |expected| {
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(new_binary, &digest, .{});
        var hex: [64]u8 = undefined;
        _ = std.fmt.bufPrint(&hex, "{}", .{std.fmt.fmtSliceHexLower(&digest)}) catch unreachable;
        if (!std.mem.eql(u8, &hex, &expected)) {
            return DeltaError.ChecksumMismatch;
        }
    }

    return DownloadedPatch{ .new_binary = new_binary, .allocator = allocator };
}
