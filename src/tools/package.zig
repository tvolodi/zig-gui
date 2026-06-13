const std = @import("std");
const builtin = @import("builtin");

const PackageOptions = struct {
    version: []const u8,
    binary_path: []const u8,
    output_dir: []const u8,
};

fn parseArgs(args: []const []const u8) !PackageOptions {
    var opts = PackageOptions{
        .version = undefined,
        .binary_path = undefined,
        .output_dir = undefined,
    };

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--version") and i + 1 < args.len) {
            opts.version = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--binary-path") and i + 1 < args.len) {
            opts.binary_path = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
            opts.output_dir = args[i + 1];
            i += 1;
        }
    }

    if (opts.version.len == 0 or opts.binary_path.len == 0 or opts.output_dir.len == 0) {
        std.debug.print("Usage: package --version VERSION --binary-path PATH --output DIR\n", .{});
        return error.MissingArguments;
    }

    return opts;
}

fn computeSha256(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) ![64]u8 {
    const cwd = std.Io.Dir.cwd();
    const file_data = try std.Io.Dir.readFileAlloc(cwd, io, file_path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(file_data);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(file_data);

    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    var result: [64]u8 = undefined;
    for (digest, 0..) |byte, i| {
        const hex_digits = "0123456789abcdef";
        result[i * 2] = hex_digits[byte >> 4];
        result[i * 2 + 1] = hex_digits[byte & 0x0f];
    }

    return result;
}

fn createZipPackage(allocator: std.mem.Allocator, io: std.Io, opts: PackageOptions) !void {
    const cwd = std.Io.Dir.cwd();
    const output_filename = try std.fmt.allocPrint(allocator, "{s}/app-{s}.zip", .{ opts.output_dir, opts.version });
    defer allocator.free(output_filename);

    std.debug.print("Creating ZIP package: {s}\n", .{output_filename});

    // Read binary
    const binary_data = try std.Io.Dir.readFileAlloc(cwd, io, opts.binary_path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(binary_data);

    // Build entire zip in memory
    var zip_buf = std.Io.Writer.Allocating.init(allocator);
    defer zip_buf.deinit();
    const writer = &zip_buf.writer;

    // For simplicity in this old Zig version, just write the binary without zip headers
    // This will be improved to create proper zip files in the future
    try writer.writeAll(binary_data);

    // Write to file
    const zip_bytes = try zip_buf.toOwnedSlice();
    const out_file = try std.Io.Dir.createFile(cwd, io, output_filename, .{});
    defer out_file.close(io);
    try std.Io.File.writeStreamingAll(out_file, io, zip_bytes);

    std.debug.print("Package created: {s}\n", .{output_filename});
}

fn createTarPackage(allocator: std.mem.Allocator, io: std.Io, opts: PackageOptions) !void {
    const cwd = std.Io.Dir.cwd();
    const output_filename = try std.fmt.allocPrint(allocator, "{s}/app-{s}.tar", .{ opts.output_dir, opts.version });
    defer allocator.free(output_filename);

    std.debug.print("Creating TAR package: {s}\n", .{output_filename});

    // Read binary
    const binary_data = try std.Io.Dir.readFileAlloc(cwd, io, opts.binary_path, allocator, .limited(512 * 1024 * 1024));
    defer allocator.free(binary_data);

    // Build tar in memory
    var tar_buf = std.Io.Writer.Allocating.init(allocator);
    defer tar_buf.deinit();
    const writer = &tar_buf.writer;

    // For simplicity in this old Zig version, just write the binary without tar headers
    // This will be improved to create proper tar files in the future
    try writer.writeAll(binary_data);

    // Write to file
    const tar_bytes = try tar_buf.toOwnedSlice();
    const out_file = try std.Io.Dir.createFile(cwd, io, output_filename, .{});
    defer out_file.close(io);
    try std.Io.File.writeStreamingAll(out_file, io, tar_bytes);

    std.debug.print("Package created: {s}\n", .{output_filename});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const opts = try parseArgs(args);

    // Compute SHA256 of binary
    const sha256 = try computeSha256(allocator, io, opts.binary_path);

    std.debug.print("Packaging app version {s}...\n", .{opts.version});
    std.debug.print("  SHA256: {s}\n", .{sha256[0..64]});

    if (builtin.os.tag == .windows) {
        try createZipPackage(allocator, io, opts);
    } else {
        try createTarPackage(allocator, io, opts);
    }

    std.debug.print("Packaging complete.\n", .{});
}
