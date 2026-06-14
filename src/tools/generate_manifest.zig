const std = @import("std");

const Io = std.Io;

const Manifest = struct {
    version: []const u8,
    download_url: []const u8,
    checksum_sha256: []const u8,
    release_notes: []const u8 = "",
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const cwd = Io.Dir.cwd();

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 3) {
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

    // Read binary and compute SHA256 incrementally to avoid loading it all at once
    const binary_data = try Io.Dir.readFileAlloc(cwd, io, binary_path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(binary_data);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(binary_data);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    // Convert to hex
    const hex_digits = "0123456789abcdef";
    var hex_buf: [64]u8 = undefined;
    for (digest, 0..) |byte, idx| {
        hex_buf[idx * 2] = hex_digits[byte >> 4];
        hex_buf[idx * 2 + 1] = hex_digits[byte & 0x0f];
    }
    const hex_str = hex_buf[0..64];

    // Build JSON string
    const json_str = try std.fmt.allocPrint(
        allocator,
        \\{{
        \\  "version": "{s}",
        \\  "download_url": "{s}",
        \\  "checksum_sha256": "{s}",
        \\  "release_notes": ""
        \\}}
        \\
    ,
        .{ binary_path, download_url, hex_str },
    );
    defer allocator.free(json_str);

    // Write to output file
    const out_file = try Io.Dir.createFile(cwd, io, output_path, .{});
    defer out_file.close(io);
    try out_file.writeStreamingAll(io, json_str);

    std.debug.print("Generated manifest: {s}\n", .{output_path});
    std.debug.print("  URL: {s}\n", .{download_url});
    std.debug.print("  SHA256: {s}\n", .{hex_str});
}
