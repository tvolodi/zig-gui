const std = @import("std");

const Manifest = struct {
    version: []const u8,
    download_url: []const u8,
    checksum_sha256: []const u8,
    release_notes: []const u8 = "",
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 4) {
        std.debug.print("Usage: {s} <binary_path> <download_url> [--output <file>]\n", .{args[0]});
        return;
    }

    const binary_path = args[1];
    const download_url = args[2];
    var output_path: []const u8 = "manifest.json";

    // Parse optional --output flag
    var i: usize = 3;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            output_path = args[i + 1];
            i += 1;
        }
    }

    // Compute SHA256 of binary
    var binary_file = try std.fs.cwd().openFile(binary_path, .{});
    defer binary_file.close();

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var buffer: [4096]u8 = undefined;

    while (true) {
        const bytes_read = try binary_file.read(&buffer);
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    // Convert to hex
    var hex_buf: [64]u8 = undefined;
    _ = try std.fmt.bufPrint(&hex_buf, "{}", .{std.fmt.fmtSliceHexLower(&digest)});
    const hex_str = hex_buf[0..64];

    // Create manifest
    const manifest = Manifest{
        .version = args[1], // Will be parsed from --version flag in the tool
        .download_url = download_url,
        .checksum_sha256 = hex_str,
        .release_notes = "",
    };

    // Write JSON to output file
    var output_file = try std.fs.cwd().createFile(output_path, .{});
    defer output_file.close();

    const writer = output_file.writer();
    try std.json.stringify(manifest, .{}, writer);
    try writer.writeAll("\n");

    std.debug.print("Generated manifest: {s}\n", .{output_path});
    std.debug.print("  Version: {s}\n", .{manifest.version});
    std.debug.print("  URL: {s}\n", .{manifest.download_url});
    std.debug.print("  SHA256: {s}\n", .{manifest.checksum_sha256});
}
